"""考试信息页面解析（Android 端）。

和培养计划页一样，教务把考试列表以 **JavaScript 对象字面量**内联在页面里
（``var studentExamInfoVms = [...]``），既不是 JSON，也不是单独的 XHR 接口。
所以复用 ``mobile_plan_page`` 里只解析数据字面量的解析器。

本模块刻意不依赖 ``gmalg`` / ``cryptography`` / ``loguru``，这样离线自检可以直接
导入它，不必拉起整个 ``mobile_zzupy``。

页面地址：``GET /student/for-std/exam-arrange/info/{studentId}?semesterId={id}``；
学期下拉来自 ``GET /student/for-std/exam-arrange``。
"""

from __future__ import annotations

import re
from typing import Any

import mobile_plan_page

#: 考试列表在页面里内联的变量名。
EXAM_VARIABLE = "studentExamInfoVms"

_SEMESTER_SELECT = re.compile(
    r"""<select[^>]*\bid=["']semester["'][^>]*>(.*?)</select>""", re.S | re.I
)
_SEMESTER_OPTION = re.compile(
    r"""<option[^>]*\bvalue=["'](\d+)["'][^>]*>(.*?)</option>""", re.S | re.I
)
_TAG = re.compile(r"<[^>]+>")

#: 状态码到中文说明的映射；未收录的取值原样展示。
STATUS_LABELS = {
    "NORMAL": "正常",
    "DELAY": "延期",
    "DELAYED": "延期",
    "CANCEL": "取消",
    "CANCELED": "取消",
    "CANCELLED": "取消",
}


def _text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _nested(record: dict, key: str) -> dict:
    value = record.get(key)
    return value if isinstance(value, dict) else {}


def extract_exam_records(html: str) -> list:
    """从「考试信息」页面里抽出内联的考试数组。"""
    pattern = re.compile(r"var\s+" + EXAM_VARIABLE + r"\s*=\s*\[")
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
    raise RuntimeError("考试页面里没有找到考试数据。")


def parse_exam_semesters(html: str) -> list[dict]:
    """解析考试页的学期下拉，顺序与页面一致（通常最新在前）。"""
    match = _SEMESTER_SELECT.search(html)
    if match is None:
        raise RuntimeError("考试页面里没有找到学期下拉。")
    semesters = []
    for value, label in _SEMESTER_OPTION.findall(match.group(1)):
        name = _text(_TAG.sub("", label))
        if name and name != "...":
            semesters.append({"id": int(value), "name": name})
    return semesters


def exam_payload(record: dict) -> dict:
    """把一条考试记录映射成扁平字典，字段与桌面端 ``Exam.to_dict()`` 对齐。"""
    course = _nested(record, "course")
    exam_type = _nested(record, "examType")
    campus = _nested(record, "requiredCampus")
    batch = _nested(record, "examBatch")
    department = _nested(record, "examMngtDepartment")
    exam_place = _nested(record, "examPlace")

    exam_time = _text(record.get("examTime"))
    date_part = start_time = end_time = ""
    if exam_time:
        date_part, _, times = exam_time.partition(" ")
        start_time, _, end_time = times.partition("~")
        start_time = start_time.strip()
        end_time = end_time.strip()

    room = _text(record.get("room"))
    campus_name = _text(campus.get("nameZh"))
    place = _text(exam_place.get("arrangedExamPlace"))
    if not place:
        place = " ".join(part for part in (campus_name, room) if part)

    status = _text(record.get("examStatusStr")) or _text(
        _nested(record, "examStatus").get("$name")
    )
    try:
        credits = float(course.get("credits"))
    except (TypeError, ValueError):
        credits = 0.0

    return {
        "id": int(record.get("id") or 0),
        "course_name": _text(course.get("nameZh")) or "未知课程",
        "course_code": _text(course.get("code")),
        "credits": credits,
        "exam_time": exam_time,
        "date": date_part,
        "start_time": start_time,
        "end_time": end_time,
        "exam_type": _text(exam_type.get("nameZh")),
        "campus": campus_name,
        "room": room,
        "place": place,
        "seat_no": _text(record.get("alphabetSeatNo"))
        or _text(record.get("seatNo")),
        "paper_code": _text(record.get("paperCode")),
        "paper_kind": _text(record.get("paperKind")),
        "status": status,
        "status_label": STATUS_LABELS.get(status.upper(), status or "未知"),
        "finished": bool(record.get("finished")),
        "batch": _text(batch.get("name")),
        "department": _text(department.get("nameZh")),
        "remark": _text(record.get("remark")) or None,
        "make_up_status": _text(record.get("makeUpConfirmStatus")) or None,
    }


def parse_exams(html: str) -> list[dict]:
    """从「考试信息」页面解析出考试列表（该学期没有考试时返回空列表）。"""
    return [
        exam_payload(record)
        for record in extract_exam_records(html)
        if isinstance(record, dict)
    ]
