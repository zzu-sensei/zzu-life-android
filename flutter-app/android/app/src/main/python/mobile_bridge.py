"""Android native bridge for ZZU.Py.

All network traffic is initiated on the Android device.  The Java UI exchanges
JSON strings with this module so no Python implementation details leak into the
view layer.
"""

from __future__ import annotations

import base64
import html
import json
import re
import threading
from datetime import date, datetime, timezone
from typing import Any, Callable

from mobile_zzupy import (
    MobileCASClient,
    MobileEASClient,
    MobileECardClient,
    MobileWebEASClient,
    discover_meter_energy,
)


_lock = threading.RLock()
_pending_cas: MobileCASClient | None = None


def _json(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _error(exc: BaseException) -> str:
    message = getattr(exc, "message", None) or str(exc) or type(exc).__name__
    return _json({"ok": False, "error": message})


def _tokens(cas: MobileCASClient) -> dict[str, Any]:
    return {
        "ok": True,
        "mfa_required": False,
        "user_token": cas.user_token,
        "refresh_token": cas.refresh_token,
    }


def begin_login(account: str, password: str, device_id: str) -> str:
    """Start local CAS login and send MFA SMS when required."""
    global _pending_cas
    with _lock:
        if _pending_cas is not None:
            _pending_cas.close()
            _pending_cas = None
        cas = MobileCASClient(account.strip(), password)
        try:
            cas.set_device(device_id.strip() or "ZZU Life Android")
            if cas.mfa.is_required():
                cas.mfa.send_sms()
                _pending_cas = cas
                return _json({"ok": True, "mfa_required": True})
            cas.login()
            result = _tokens(cas)
            cas.close()
            return _json(result)
        except BaseException as exc:
            cas.close()
            return _error(exc)


def complete_mfa(code: str) -> str:
    global _pending_cas
    with _lock:
        cas = _pending_cas
        if cas is None:
            return _json({"ok": False, "error": "短信验证会话已失效，请重新登录。"})
        try:
            cas.mfa.verify_sms(code.strip())
            cas.login()
            return _json(_tokens(cas))
        except BaseException as exc:
            return _error(exc)
        finally:
            cas.close()
            _pending_cas = None


def _with_cas(
    account: str,
    user_token: str,
    refresh_token: str,
    operation: Callable[[MobileCASClient], dict[str, Any]],
) -> str:
    with _lock:
        cas = MobileCASClient(account, "")
        try:
            cas.set_device("ZZU Life Android")
            cas.set_token(user_token, refresh_token)
            cas.login()
            payload = operation(cas)
            payload["ok"] = True
            return _json(payload)
        except BaseException as exc:
            return _error(exc)
        finally:
            cas.close()


_GRADE_COMPONENT_ALIASES = {
    "grade_level": {
        "gradelevel", "gradelevelname", "level", "graderank", "gradeclass",
        "scorelevel", "gradingmode", "grademode", "gradetype",
        "成绩等级", "等级", "层级", "成绩制",
    },
    "usual_score": {
        "usualgrade", "usualscore", "normalgrade", "normalscore",
        "regulargrade", "regularscore", "dailygrade", "平时成绩", "平时",
    },
    "paper_score": {
        "papergrade", "paperscore", "examgrade", "examscore",
        "finalexamgrade", "finalexamscore", "卷面成绩", "卷面",
        "考试成绩", "期末成绩",
    },
    "experiment_score": {
        "experimentgrade", "experimentscore", "labgrade", "labscore",
        "practicegrade", "practicescore", "实验成绩", "实验",
    },
}

_GRADE_LABELS = {
    "grade_level": "成绩等级",
    "usual_score": "平时成绩",
    "paper_score": "卷面成绩",
    "experiment_score": "实验成绩",
}


def _grade_components(value: Any) -> dict[str, str]:
    result: dict[str, str] = {}

    def normalized(raw: Any) -> str:
        return re.sub(r"[\s_.:\-：]", "", str(raw)).lower()

    def store(label: Any, score: Any) -> None:
        if score in (None, ""):
            return
        key = normalized(label)
        for field, aliases in _GRADE_COMPONENT_ALIASES.items():
            if key in aliases:
                result.setdefault(field, str(score))

    def visit(node: Any) -> None:
        if isinstance(node, dict):
            label = next(
                (
                    node.get(key)
                    for key in ("name", "label", "itemName", "typeName", "gradeTypeName")
                    if node.get(key) not in (None, "")
                ),
                None,
            )
            score = next(
                (
                    node.get(key)
                    for key in ("score", "grade", "value", "result")
                    if node.get(key) not in (None, "")
                ),
                None,
            )
            if label is not None:
                store(label, score)
            for key, item in node.items():
                store(key, item)
                if isinstance(item, (dict, list)):
                    visit(item)
        elif isinstance(node, list):
            for item in node:
                visit(item)

    parsed = value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except (TypeError, ValueError):
            for label, score in re.findall(
                r"(平时成绩|平时|卷面成绩|卷面|考试成绩|期末成绩)\s*[：:=]\s*([^,，;；\s]+)",
                value,
            ):
                store(label, score)
            return result
    visit(parsed)
    return result


def _first_value(value: dict[str, Any], keys: tuple[str, ...]) -> Any:
    return next((value[key] for key in keys if value.get(key) not in (None, "")), None)


def _grade_component_items(value: dict[str, Any]) -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    seen: set[str] = set()

    def add(label: Any, score: Any) -> None:
        label_text = str(label or "").strip()
        score_text = "" if score is None else str(score).strip()
        if not label_text or not score_text:
            return
        key = re.sub(r"[\s_.:\-：]", "", label_text).lower()
        canonical = next(
            (field for field, aliases in _GRADE_COMPONENT_ALIASES.items() if key in aliases),
            key,
        )
        if canonical in seen:
            return
        seen.add(canonical)
        items.append({"label": _GRADE_LABELS.get(canonical, label_text), "value": score_text})

    direct_fields = {
        "成绩等级": ("gradeLevel", "gradeLevelName", "level", "gradeRank", "scoreLevel"),
        "平时成绩": ("usualGrade", "usualScore", "normalGrade", "normalScore", "regularGrade", "regularScore", "dailyGrade", "平时成绩"),
        "卷面成绩": ("paperGrade", "paperScore", "examGrade", "examScore", "finalExamGrade", "finalExamScore", "卷面成绩", "考试成绩", "期末成绩"),
        "实验成绩": ("experimentGrade", "experimentScore", "labGrade", "labScore", "practiceGrade", "practiceScore", "实验成绩"),
        "期中成绩": ("midtermGrade", "midtermScore", "middleGrade", "middleScore", "期中成绩"),
        "考勤成绩": ("attendanceGrade", "attendanceScore", "考勤成绩"),
        "作业成绩": ("homeworkGrade", "homeworkScore", "作业成绩"),
        "实践成绩": ("practiceGrade", "practiceScore", "实践成绩"),
        "项目成绩": ("projectGrade", "projectScore", "项目成绩"),
        "口试成绩": ("oralGrade", "oralScore", "口试成绩"),
    }
    for label, keys in direct_fields.items():
        add(label, _first_value(value, keys))

    detail = _first_value(value, ("gradeDetail", "detail", "scoreDetail"))

    def visit(node: Any) -> None:
        if isinstance(node, dict):
            label = _first_value(
                node,
                ("name", "nameZh", "label", "itemName", "typeName", "gradeTypeName"),
            )
            score = _first_value(node, ("score", "grade", "value", "result"))
            if label is not None and score is not None:
                add(label, score)
            ignored = {
                "id", "code", "name", "nameZh", "label", "itemName", "typeName",
                "gradeTypeName", "score", "grade", "value", "result",
            }
            for key, item in node.items():
                if isinstance(item, (dict, list)):
                    visit(item)
                elif key not in ignored:
                    add(key, item)
        elif isinstance(node, list):
            for item in node:
                visit(item)

    if isinstance(detail, str):
        try:
            visit(json.loads(detail))
        except (TypeError, ValueError):
            for label, score in re.findall(
                r"([^,，;；:\n]{1,24})\s*[：:=]\s*([^,，;；\n]+)", detail
            ):
                add(label, score)
    else:
        visit(detail)

    final_score = _first_value(value, ("finalGrade", "score", "grade"))
    add("最终成绩", final_score)
    return items


def get_grades(account: str, user_token: str, refresh_token: str) -> str:
    def operation(cas: MobileCASClient) -> dict[str, Any]:
        eas = MobileEASClient(cas)
        try:
            eas.login()
            values = eas.get_grades()
        finally:
            eas.close()

        grades = []
        for value in values:
            course = value.get("course") if isinstance(value.get("course"), dict) else {}
            detail = _first_value(value, ("gradeDetail", "detail", "scoreDetail"))
            components = _grade_components(detail)
            component_items = _grade_component_items(value)
            semester = value.get("semester")
            if isinstance(semester, dict):
                semester_name = str(
                    semester.get("nameZh")
                    or semester.get("name")
                    or semester.get("semesterName")
                    or "未知学期"
                )
            else:
                semester_name = str(
                    semester
                    or value.get("semesterName")
                    or value.get("termName")
                    or "未知学期"
                )
            grade = {
                "semester": semester_name,
                "course": str(
                    value.get("courseNameZh")
                    or value.get("courseName")
                    or course.get("nameZh")
                    or course.get("name")
                    or "未知课程"
                ),
                "code": str(
                    value.get("lessonCode")
                    or value.get("courseCode")
                    or course.get("code")
                    or ""
                ),
                "score": value.get("finalGrade", value.get("score", value.get("grade"))),
                "usual_score": _first_value(
                    value,
                    (
                        "usualGrade", "usualScore", "normalGrade", "normalScore",
                        "regularGrade", "regularScore", "dailyGrade", "平时成绩",
                    ),
                ) or components.get("usual_score"),
                "paper_score": _first_value(
                    value,
                    (
                        "paperGrade", "paperScore", "examGrade", "examScore",
                        "finalExamGrade", "finalExamScore", "卷面成绩", "考试成绩",
                        "期末成绩",
                    ),
                ) or components.get("paper_score"),
                "experiment_score": _first_value(
                    value,
                    (
                        "experimentGrade", "experimentScore", "labGrade", "labScore",
                        "practiceGrade", "practiceScore", "实验成绩",
                    ),
                ) or components.get("experiment_score"),
                "components": component_items,
                "gp": value.get("gp", value.get("gpa", value.get("gradePoint"))),
                "credits": value.get("credits", value.get("credit", course.get("credits", 0))) or 0,
                "passed": value.get("passed", value.get("isPassed")),
            }
            try:
                grade["gp"] = None if grade["gp"] in (None, "") else float(grade["gp"])
                grade["credits"] = float(grade["credits"])
            except (TypeError, ValueError):
                grade["gp"] = None
                grade["credits"] = 0.0
            grades.append(grade)

        selected: dict[str, Any] = {}
        for grade in grades:
            key = grade["code"].strip() or grade["course"].strip()
            score_match = re.search(r"\d+(?:\.\d+)?", str(grade["score"] or ""))
            score = float(score_match.group()) if score_match else -1.0
            rank = (grade["gp"] if grade["gp"] is not None else -1.0, score)
            current = selected.get(key)
            if current is None or rank > current[0]:
                selected[key] = (rank, grade)

        best = [item[1] for item in selected.values()]
        included = [g for g in best if g["gp"] is not None and g["credits"] > 0]
        credits = sum(g["credits"] for g in included)
        weighted = sum(float(g["gp"]) * g["credits"] for g in included)
        return {
            "gpa": round(weighted / credits, 4) if credits else None,
            "credits": round(credits, 2),
            "grades": grades,
        }

    return _with_cas(account, user_token, refresh_token, operation)


def get_transcript_document(account: str, user_token: str, refresh_token: str) -> str:
    """Build a printable personal transcript from the authenticated App API.

    The official MVC transcript page requires a separate browser TGC on some
    accounts. The grade API already authenticates with the App token, so use it
    as the reliable source and keep the document entirely on the device.
    """
    payload = json.loads(get_grades(account, user_token, refresh_token))
    if payload.get("ok") is not True:
        return _json(payload)

    rows = []
    for grade in payload.get("grades", []):
        gp = grade.get("gp")
        credits = grade.get("credits")
        rows.append(
            "<tr>"
            f"<td>{html.escape(str(grade.get('semester') or '--'))}</td>"
            f"<td>{html.escape(str(grade.get('course') or '--'))}</td>"
            f"<td>{html.escape(str(grade.get('score') or '--'))}</td>"
            f"<td>{'--' if gp is None else html.escape(str(gp))}</td>"
            f"<td>{html.escape(str(credits if credits is not None else '--'))}</td>"
            "</tr>"
        )
    gpa = payload.get("gpa")
    gpa_text = "--" if gpa is None else f"{float(gpa):.4f}"
    content = f"""<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>个人成绩表</title>
<style>body{{font-family:sans-serif;color:#172a25;margin:28px}}h1{{color:#08483c}}
.note{{color:#65746f;font-size:12px}}.summary{{display:flex;gap:28px;padding:14px;background:#edf6f1;border-radius:10px}}
table{{border-collapse:collapse;width:100%;margin-top:20px}}th,td{{padding:8px;border:1px solid #d7e1dc;text-align:left}}
th{{background:#f3f8f5}}@media print{{body{{margin:0}}}}</style></head><body>
<h1>郑州大学个人成绩表</h1><p class="note">由本机直连本科教务成绩 API 实时生成，仅供个人核对。</p>
<div class="summary"><b>参考累计绩点：{gpa_text}</b><b>计入学分：{payload.get('credits', '--')}</b></div>
<table><thead><tr><th>学期</th><th>课程</th><th>最终成绩</th><th>绩点</th><th>学分</th></tr></thead>
<tbody>{''.join(rows)}</tbody></table></body></html>""".encode("utf-8")
    return _json(
        {
            "ok": True,
            "name": "郑大个人成绩表",
            "mime_type": "text/html; charset=utf-8",
            "content_base64": base64.b64encode(content).decode("ascii"),
        }
    )


def get_grade_rank_document(account: str, user_token: str, refresh_token: str) -> str:
    def operation(cas: MobileCASClient) -> dict[str, Any]:
        web = MobileWebEASClient(cas)
        try:
            web.login()
            content = web.get_grade_rank_report()
            return {
                "name": "郑大成绩排名",
                "mime_type": "application/pdf",
                "content_base64": base64.b64encode(content).decode("ascii"),
            }
        finally:
            web.close()

    return _with_cas(account, user_token, refresh_token, operation)


def get_program_plan(account: str, user_token: str, refresh_token: str) -> str:
    """获取培养计划完成情况（独立页面用）。

    网页端登录后抓取「培养计划完成情况预览」页面并解析。数据内联在页面里，
    不需要额外的接口。
    """
    def operation(cas: MobileCASClient) -> dict[str, Any]:
        web = MobileWebEASClient(cas)
        try:
            web.login()
            return web.get_program_plan()
        finally:
            web.close()

    return _with_cas(account, user_token, refresh_token, operation)


def get_semesters(account: str, user_token: str, refresh_token: str) -> str:
    def operation(cas: MobileCASClient) -> dict[str, Any]:
        eas = MobileEASClient(cas)
        try:
            eas.login()
            semesters = eas.get_semesters()
        finally:
            eas.close()
        return {
            "semesters": [
                {
                    "id": int(semester.get("id", 0)),
                    "name": str(semester.get("nameZh") or semester.get("name") or "未知学期"),
                    "weeks": len(semester.get("weekIndices") or []),
                }
                for semester in semesters
            ]
        }

    return _with_cas(account, user_token, refresh_token, operation)


def _format_clock_time(value: Any) -> str:
    if isinstance(value, (int, float)):
        raw = str(int(value))
    else:
        raw = str(value or "").strip()
    if "T" in raw:
        raw = raw.split("T", 1)[1]
    digits = "".join(ch for ch in raw if ch.isdigit())
    if 1 <= len(digits) <= 4:
        digits = digits.zfill(4)
        return f"{digits[:2]}:{digits[2:4]}"
    return raw


def _is_experiment_schedule(schedule: dict[str, Any]) -> bool:
    lesson_type = str(schedule.get("lessonType") or "").strip().upper()
    return "EXPERIMENT" in lesson_type or "LAB" in lesson_type or "实验" in lesson_type


def _schedule_payload(
    eas: MobileEASClient,
    week: int | None,
    semester_id: int | None,
) -> dict[str, Any]:
    teaching_week = eas.get_teaching_week(week, semester_id)
    lessons: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    for lesson in teaching_week:
        course = lesson.get("course") or {}
        schedule = lesson.get("schedule") or {}
        date_value = str(schedule.get("date") or schedule.get("originalDate") or "")
        start_unit = int(schedule.get("startUnit", 0))
        end_unit = int(schedule.get("endUnit", start_unit))
        key = (
            course.get("code", ""),
            date_value,
            schedule.get("weekday", 0),
            start_unit,
            end_unit,
        )
        if key in seen:
            continue
        seen.add(key)
        room = schedule.get("room")
        if isinstance(room, dict):
            campus = room.get("campus") or {}
            building = room.get("building") or {}
            place = " ".join(
                value
                for value in (
                    campus.get("nameZh") or campus.get("name"),
                    building.get("nameZh") or building.get("name"),
                    room.get("nameZh") or room.get("name"),
                )
                if value
            )
        else:
            place = str(schedule.get("customPlace") or "")

        start = _format_clock_time(schedule.get("realStartTime") or schedule.get("startTime"))
        end = _format_clock_time(schedule.get("realEndTime") or schedule.get("endTime"))
        lessons.append(
            {
                "course": str(course.get("nameZh") or course.get("name") or "未知课程"),
                "code": str(course.get("code") or ""),
                "date": date_value,
                "weekday": int(schedule.get("weekday", 0)),
                "start_unit": start_unit,
                "end_unit": end_unit,
                "start_time": start,
                "end_time": end,
                "teacher": str(schedule.get("teacherName") or ""),
                "place": place,
                "lesson_type": str(schedule.get("lessonType") or ""),
                "is_experiment": _is_experiment_schedule(schedule),
                "week_indexes": [
                    int(value)
                    for value in (
                        schedule.get("weekIndexes")
                        or ([schedule.get("weekIndex")] if schedule.get("weekIndex") else [])
                    )
                    if str(value).strip()
                ],
            }
        )
    lessons.sort(key=lambda item: (item["weekday"], item["start_unit"]))
    return {"week": week or 0, "lessons": lessons}


def get_schedule(
    account: str,
    user_token: str,
    refresh_token: str,
    week: int,
    semester_id: int,
) -> str:
    def operation(cas: MobileCASClient) -> dict[str, Any]:
        eas = MobileEASClient(cas)
        try:
            eas.login()
            selected_semester = semester_id if semester_id > 0 else None
            selected_week = week
            if selected_week <= 0:
                today = date.today()
                selected_week = eas.resolve_current_week(today.isoformat())
            return _schedule_payload(eas, selected_week, selected_semester)
        finally:
            eas.close()

    return _with_cas(account, user_token, refresh_token, operation)


def get_today_schedule(account: str, user_token: str, refresh_token: str) -> str:
    def operation(cas: MobileCASClient) -> dict[str, Any]:
        eas = MobileEASClient(cas)
        try:
            eas.login()
            today = date.today()
            week = eas.resolve_current_week(today.isoformat())
            payload = _schedule_payload(eas, week, None)
            payload["lessons"] = [
                item for item in payload["lessons"] if item["weekday"] == today.isoweekday()
            ]
            return payload
        finally:
            eas.close()

    return _with_cas(account, user_token, refresh_token, operation)


def _ics_escape(value: Any) -> str:
    return (
        str(value or "")
        .replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace(",", "\\,")
        .replace(";", "\\;")
    )


def export_schedule_ics(account: str, user_token: str, refresh_token: str) -> str:
    def operation(cas: MobileCASClient) -> dict[str, Any]:
        eas = MobileEASClient(cas)
        try:
            eas.login()
            payload = _schedule_payload(eas, None, None)
            semester = eas.current_semester or {}
            semester_start = date.fromisoformat(str(semester.get("startDate"))[:10])
            events: list[tuple[dict[str, Any], date]] = []
            for lesson in payload["lessons"]:
                weekday = int(lesson.get("weekday") or 1)
                week_indexes = lesson.get("week_indexes") or []
                if week_indexes:
                    for week_index in week_indexes:
                        lesson_date = date.fromordinal(
                            semester_start.toordinal()
                            + (int(week_index) - 1) * 7
                            + weekday
                            - 1
                        )
                        events.append((lesson, lesson_date))
                    continue
                raw_date = str(lesson.get("date") or "")[:10]
                if raw_date:
                    try:
                        events.append((lesson, date.fromisoformat(raw_date)))
                        continue
                    except ValueError:
                        pass

            lines = [
                "BEGIN:VCALENDAR",
                "VERSION:2.0",
                "CALSCALE:GREGORIAN",
                "METHOD:PUBLISH",
                "PRODID:-//ZZU Life//Semester Schedule//CN",
                "X-WR-CALNAME:郑大课表",
            ]
            timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            seen: set[tuple[str, str, str]] = set()
            for lesson, lesson_date in sorted(
                events,
                key=lambda item: (
                    item[1],
                    int(item[0].get("start_unit") or 0),
                    str(item[0].get("course") or ""),
                ),
            ):
                start_time = str(lesson.get("start_time") or "").replace(":", "")
                end_time = str(lesson.get("end_time") or "").replace(":", "")
                if len(start_time) != 4 or len(end_time) != 4:
                    continue
                marker = (
                    str(lesson.get("code") or lesson.get("course") or ""),
                    lesson_date.isoformat(),
                    start_time,
                )
                if marker in seen:
                    continue
                seen.add(marker)
                date_text = lesson_date.strftime("%Y%m%d")
                uid = f"{marker[0]}-{date_text}-{start_time}@zzu-life"
                description = str(lesson.get("teacher") or "教师未定")
                if lesson.get("is_experiment"):
                    description += " · 实验课"
                lines.extend(
                    [
                        "BEGIN:VEVENT",
                        f"UID:{_ics_escape(uid)}",
                        f"DTSTAMP:{timestamp}",
                        f"DTSTART;TZID=Asia/Shanghai:{date_text}T{start_time}00",
                        f"DTEND;TZID=Asia/Shanghai:{date_text}T{end_time}00",
                        f"SUMMARY:{_ics_escape(lesson.get('course'))}",
                        f"LOCATION:{_ics_escape(lesson.get('place') or '地点未定')}",
                        f"DESCRIPTION:{_ics_escape(description)}",
                        "END:VEVENT",
                    ]
                )
            lines.append("END:VCALENDAR")
            semester_name = str(
                semester.get("nameZh") or semester.get("name") or "当前学期"
            ).replace("/", "-").replace("\\", "-")
            return {
                "filename": f"郑大课表-{semester_name}.ics",
                "content": "\r\n".join(lines) + "\r\n",
                "count": len(seen),
            }
        finally:
            eas.close()

    return _with_cas(account, user_token, refresh_token, operation)


def get_energy(account: str, user_token: str, refresh_token: str) -> str:
    def operation(cas: MobileCASClient) -> dict[str, Any]:
        ecard = MobileECardClient(cas)
        try:
            ecard.login()
            default_room = ecard.get_default_room()
            meter_list = discover_meter_energy(ecard, default_room)
            if not meter_list:
                raise RuntimeError("没有查询到可用电表，请检查一卡通默认房间设置。")
            for meter in meter_list:
                meter["remaining"] = round(float(meter["remaining"]), 2)
        finally:
            ecard.close()
        return {"room": default_room, "meter_list": meter_list}

    return _with_cas(account, user_token, refresh_token, operation)


def recharge_energy(
    account: str,
    user_token: str,
    refresh_token: str,
    meter_id: str,
    meter_type: str,
    amount: int,
    payment_password: str,
) -> str:
    def operation(cas: MobileCASClient) -> dict[str, Any]:
        ecard = MobileECardClient(cas)
        try:
            ecard.login()
            message = ecard.recharge_energy(payment_password, int(amount), meter_id)
            return {
                "meter_id": meter_id,
                "meter_type": meter_type,
                "amount": int(amount),
                "message": message,
            }
        finally:
            ecard.close()

    return _with_cas(account, user_token, refresh_token, operation)

