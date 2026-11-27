"""空闲教室与门户信息卡（一卡通余额）解析模块（Android 端）。

与 ``mobile_exam_page`` 相同，本模块仅依赖标准库与 ``mobile_plan_page`` 的
JS 数据字面量解析器，刻意不引入 ``gmalg`` / ``cryptography`` / ``loguru``，
便于通过 ``scripts/test_mobile_room.py`` 进行纯离线回归验证。
"""

from __future__ import annotations

import re
from typing import Any

import mobile_plan_page

_SCALAR_VARS = ("_semesterStart", "_semesterWeeks")


def _text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _int(value: Any, default: int = 0) -> int:
    try:
        return int(float(str(value).strip()))
    except (TypeError, ValueError):
        return default


def _nested(record: dict, key: str) -> dict:
    value = record.get(key)
    return value if isinstance(value, dict) else {}


def _extract_js_array(html: str, var_name: str) -> list:
    pattern = re.compile(rf"var\s+{re.escape(var_name)}\s*=\s*\[")
    for match in pattern.finditer(html):
        bracket = html.find("[", match.start())
        snippet = mobile_plan_page.slice_js_array(html, bracket)
        if snippet is None:
            continue
        try:
            parsed = mobile_plan_page.parse_js_literal(snippet)
        except mobile_plan_page.JsLiteralError:
            continue
        if isinstance(parsed, list):
            return parsed
    return []


def normalize_units(raw: list) -> list[dict]:
    """标准化校区节次列表。"""
    units: list[dict] = []
    for item in raw or []:
        if not isinstance(item, dict):
            continue
        val = _int(item.get("value") or item.get("name"), 0)
        if val <= 0:
            continue
        day_part = ""
        raw_part = item.get("dayPart")
        if isinstance(raw_part, dict):
            day_part = _text(raw_part.get("$name") or raw_part.get("name"))
        else:
            day_part = _text(raw_part)
        units.append(
            {
                "value": val,
                "name": _text(item.get("name")) or str(val),
                "time": _text(item.get("time")),
                "day_part": day_part,
                "segment_index": _int(item.get("segmentIndex"), 0),
            }
        )
    return units


def normalize_buildings(raw: list) -> list[dict]:
    """过滤启用状态并标准化教学楼列表。"""
    buildings: list[dict] = []
    for item in raw or []:
        if not isinstance(item, dict):
            continue
        if item.get("enabled") is False:
            continue
        bid = _int(item.get("id"), 0)
        name = _text(item.get("nameZh") or item.get("name") or item.get("code"))
        if bid > 0 and name:
            buildings.append({"id": bid, "name": name})
    return buildings


def parse_room_free_meta(html: str) -> dict:
    """从 ``/student/for-std/room-free`` 页面提取校区、教室类型、默认节次与学期周次。"""
    raw_campuses = _extract_js_array(html, "_campusList")
    if not raw_campuses:
        raise RuntimeError("空闲教室页面缺少校区列表，可能未登录或页面结构已变更。")

    campuses = []
    for item in raw_campuses:
        if not isinstance(item, dict):
            continue
        cid = _int(item.get("value") or item.get("id"), 0)
        name = _text(item.get("text") or item.get("nameZh") or item.get("name"))
        if cid > 0 and name:
            campuses.append({"id": cid, "name": name})

    room_types = []
    for item in _extract_js_array(html, "_roomTypeList"):
        if not isinstance(item, dict):
            continue
        tid = _int(item.get("value") or item.get("id"), 0)
        name = _text(item.get("text") or item.get("nameZh") or item.get("name"))
        if tid > 0 and name:
            room_types.append({"id": tid, "name": name})

    units = normalize_units(_extract_js_array(html, "_units"))

    semester_start = ""
    m_start = re.search(r"var\s+_semesterStart\s*=\s*['\"]([^'\"]+)['\"]", html)
    if m_start:
        semester_start = _text(m_start.group(1))[:10]

    semester_weeks = 19
    m_weeks = re.search(r"var\s+_semesterWeeks\s*=\s*(\d+)", html)
    if m_weeks:
        semester_weeks = max(1, _int(m_weeks.group(1), 19))

    return {
        "campuses": campuses,
        "room_types": room_types,
        "units": units,
        "semester_start": semester_start,
        "semester_weeks": semester_weeks,
    }


def normalize_free_rooms(raw: list) -> list[dict]:
    """标准化空闲教室结果并按（教学楼, 楼层, 教室名）排序，跳过虚拟教室。"""
    rooms: list[dict] = []
    for item in raw or []:
        if not isinstance(item, dict):
            continue
        if item.get("virtual") is True:
            continue
        building = _nested(item, "building")
        campus = _nested(building, "campus")
        room_type = _nested(item, "roomType")
        rooms.append(
            {
                "id": _int(item.get("id"), 0),
                "name": _text(item.get("nameZh") or item.get("name") or item.get("code")) or "未知教室",
                "code": _text(item.get("code")),
                "campus": _text(campus.get("nameZh") or campus.get("name")),
                "building_id": _int(building.get("id"), 0),
                "building": _text(building.get("nameZh") or building.get("name")) or "其他教学楼",
                "room_type": _text(room_type.get("nameZh") or room_type.get("name")),
                "floor": _int(item.get("floor"), 0),
                "seats": _int(item.get("seatsForLesson") or item.get("seats"), 0),
                "remark": _text(item.get("remark")),
            }
        )
    rooms.sort(key=lambda r: (r["building"], r["floor"], r["name"]))
    return rooms


def parse_portal_cards(payload: dict) -> dict:
    """从门户 ``get-person-info-card-list`` 响应提取一卡通余额与邮箱未读数。"""
    if not isinstance(payload, dict):
        raise RuntimeError("未能从门户接口解析一卡通余额")
    items = payload.get("data")
    if not isinstance(items, list):
        raise RuntimeError("未能从门户接口解析一卡通余额")

    balance: float | None = None
    email_unread: int | None = None

    for item in items:
        if not isinstance(item, dict):
            continue
        name = _text(item.get("name") or item.get("title"))
        unit = _text(item.get("unit"))
        raw_amount = item.get("amount")

        if "邮箱" in name and email_unread is None:
            try:
                email_unread = int(float(str(raw_amount).strip()))
            except (TypeError, ValueError):
                pass

        is_card = ("一卡通" in name or "余额" in name) or (unit == "元" and balance is None)
        if is_card and raw_amount is not None:
            try:
                balance = round(float(str(raw_amount).strip()), 2)
            except (TypeError, ValueError):
                continue

    if balance is None:
        raise RuntimeError("未能从门户接口解析一卡通余额")

    return {
        "balance": balance,
        "unit": "元",
        "email_unread": email_unread,
    }
