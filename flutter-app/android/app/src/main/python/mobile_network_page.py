"""校园网自助服务系统页面解析（Android 端）。

两处数据都不是 JSON 接口：

- **账户对象**内联在「个人设置」页里，形如
  ``(function (user) { window.user = user || {}; })({...});``，是 JS 对象字面量；
- **登录历史**接口返回的是**位置数组**，没有字段名。

因此账户对象复用 ``mobile_plan_page`` 的数据字面量解析器；登录历史只映射已确认的
位置，含义未确认的原样保留在 ``raw`` 里。

本模块刻意不依赖 ``gmalg`` / ``cryptography`` / ``loguru``，便于离线自检。

!!! warning
    个人设置页里内联的对象**包含明文账户密码**（``userPassword``）。本模块刻意
    不解析、不返回该字段。
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Any

import mobile_plan_page

#: 个人设置页里内联账户对象的标记。
ACCOUNT_MARKER = "window.user = user || {};"

#: 学校用的是东八区。
_CST = timezone(timedelta(hours=8))


def _text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _local_text(millis: Any) -> str | None:
    """毫秒时间戳 → 东八区的 ``YYYY-MM-DD HH:MM:SS``；0 或非法值返回 None。"""
    if not isinstance(millis, (int, float)) or millis <= 0:
        return None
    try:
        return datetime.fromtimestamp(millis / 1000, _CST).strftime("%Y-%m-%d %H:%M:%S")
    except (ValueError, OverflowError, OSError):
        return None


def _local_date(millis: Any) -> str | None:
    text = _local_text(millis)
    return text[:10] if text else None


def parse_account_page(html: str) -> dict:
    """从「个人设置」页解析账户概览。"""
    marker = html.find(ACCOUNT_MARKER)
    if marker == -1:
        raise RuntimeError("自助服务页面里没有找到账户对象。")
    brace = html.find("{", marker + len(ACCOUNT_MARKER))
    if brace == -1:
        raise RuntimeError("账户对象缺少起始花括号。")
    snippet = mobile_plan_page.slice_js_object(html, brace)
    if snippet is None:
        raise RuntimeError("账户对象括号不配平。")
    try:
        data = mobile_plan_page.parse_js_literal(snippet)
    except mobile_plan_page.JsLiteralError as exc:
        raise RuntimeError("账户对象不是可解析的 JS 字面量。") from exc
    if not isinstance(data, dict):
        raise RuntimeError("账户对象不是对象。")
    return account_payload(data)


def account_payload(data: dict) -> dict:
    """把内联账户对象映射成扁平字典，字段与桌面端 ``NetworkAccount.to_dict()`` 对齐。"""
    group_raw = data.get("userGroup")
    group = group_raw if isinstance(group_raw, dict) else {}
    service_raw = data.get("serviceDefault")
    service = service_raw if isinstance(service_raw, dict) else {}

    return {
        "user_name": _text(data.get("userName")),
        "real_name": _text(data.get("userRealName")) or None,
        "user_id": _int(data.get("userId")),
        "user_ip": _text(data.get("userIp")),
        "mac_address": _text(data.get("macAddress")),
        "service_name": _text(service.get("defaultName")),
        "group_name": _text(group.get("userGroupName")),
        "left_money": _float(data.get("leftMoney")),
        "use_money": _float(data.get("useMoney")),
        "left_flow": _float(data.get("leftFlow")),
        "use_flow": _float(data.get("useFlow")),
        "down_flow": _float(data.get("internetDownFlow")),
        "up_flow": _float(data.get("internetUpFlow")),
        "left_time": _int(data.get("leftTime")),
        "use_time": _int(data.get("useTime")),
        "download_band": _int(data.get("downloadBand")),
        "upload_band": _int(data.get("uploadBand")),
        "multi_login": _int(data.get("multiLogin")),
        "ip_max_count": _int(group.get("ipMaxCount")),
        "ip_count": _int(data.get("ipCount")),
        "start_date": _local_date(data.get("startDate")),
        "stop_date": _local_date(data.get("stopDate")),
        "install_date": _local_date(data.get("installDate")),
        "stop_reason": _text(data.get("stopReason")),
        "bind_cm_flag": _text(data.get("bindCmFlag")) or "0",
    }


def login_record_payload(row: list) -> dict:
    """把一条位置数组记录映射成扁平字典。

    位置含义：``[上线, 下线, IP, MAC, ?, ?, ?, ?, null, "#终端", 终端, 序号]``。
    第 5–9 项含义未确认，原样保留在 ``raw`` 里——不猜。
    """

    def at(position: int) -> Any:
        return row[position] if position < len(row) else None

    start = _local_text(at(0))
    end = _local_text(at(1))
    duration = None
    if isinstance(at(0), (int, float)) and isinstance(at(1), (int, float)):
        duration = (at(1) - at(0)) / 1000

    return {
        "start_time": start,
        "end_time": end,
        "ip": _text(at(2)),
        "mac": _text(at(3)),
        "terminal_type": _text(at(10)) or _text(at(9)).lstrip("#"),
        "duration_seconds": duration,
        "index": _int(at(11)),
        "raw": list(row),
    }


def parse_login_history(payload: str) -> list[dict]:
    """解析登录历史接口的响应。"""
    try:
        data = json.loads(payload)
    except (TypeError, ValueError) as exc:
        raise RuntimeError("登录历史不是合法 JSON。") from exc
    if not isinstance(data, list):
        raise RuntimeError("登录历史不是数组。")
    return [login_record_payload(row) for row in data if isinstance(row, list)]
