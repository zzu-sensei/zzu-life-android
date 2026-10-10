"""培养计划解析（Android 精简版）。

数据来源与桌面端 ``zzupy.web.eas`` + ``zzupy.plan`` 完全一致：教务学生端的
「培养计划完成情况预览」页面，数据以 **JavaScript 对象字面量** 内联在
``<script>var model = {...}</script>`` 里。

这里做成自包含实现，不依赖 ``zzupy.logging``（需要 loguru，手机端未打包）。
但**解析规则必须与桌面端逐条一致**，否则两端会给出不同结论：

- 学分要求字段是 ``credits`` / ``subModuleNum``；
- 每个模块的通过／在修／未通过学分取自 ``completionSummary``（教务官方口径）；
- 结课结果只有 ``PASSED`` / ``UNREPAIRED`` / ``TAKING`` 三种实际取值，
  未通过的取值是 ``UNREPAIRED`` 而不是 ``FAILED``；
- 父模块与子模块都是独立学分桶，不能因为节点有子模块就跳过它本身。

一致性由 ``scripts/test_mobile_plan_page.py`` 与桌面端交叉比对。
"""

from __future__ import annotations

import json
import re
from typing import Any

WHITESPACE = " \t\r\n\u00a0\ufeff"
_JS_OBJECT_VAR = "model"


# ---------------------------------------------------------------------------
# JS 对象字面量解析（只支持数据字面量，不求值）
# ---------------------------------------------------------------------------


class JsLiteralError(ValueError):
    """输入不是可解析的 JS 数据字面量。"""


class _JsParser:
    def __init__(self, text: str) -> None:
        self.text = text
        self.pos = 0

    def error(self, message: str) -> JsLiteralError:
        return JsLiteralError(f"{message}（位置 {self.pos}）")

    def skip(self) -> None:
        while self.pos < len(self.text) and self.text[self.pos] in WHITESPACE:
            self.pos += 1

    def peek(self) -> str:
        return self.text[self.pos] if self.pos < len(self.text) else ""

    def value(self) -> Any:
        self.skip()
        char = self.peek()
        if char == "":
            raise self.error("内容意外结束")
        if char == "{":
            return self.obj()
        if char == "[":
            return self.arr()
        if char in "'\"":
            return self.string()
        if char == "-" or char.isdigit():
            return self.number()
        word = self.identifier()
        if word == "true":
            return True
        if word == "false":
            return False
        if word in ("null", "undefined", "NaN", "Infinity"):
            return None
        raise self.error(f"不是数据字面量：{word!r}")

    def identifier(self) -> str:
        self.skip()
        start = self.pos
        first = self.peek()
        if not (first.isalpha() or first in "_$"):
            raise self.error(f"标识符起始字符非法：{first!r}")
        while self.pos < len(self.text):
            char = self.text[self.pos]
            if char.isalnum() or char in "_$":
                self.pos += 1
            else:
                break
        return self.text[start: self.pos]

    def string(self) -> str:
        quote = self.peek()
        self.pos += 1
        chunks: list[str] = []
        while True:
            if self.pos >= len(self.text):
                raise self.error("字符串没有闭合")
            char = self.text[self.pos]
            if char == "\\":
                self.pos += 1
                if self.pos >= len(self.text):
                    raise self.error("转义符后内容结束")
                escape = self.text[self.pos]
                if escape == "u":
                    digits = self.text[self.pos + 1: self.pos + 5]
                    if len(digits) < 4:
                        raise self.error("\\u 转义不完整")
                    try:
                        chunks.append(chr(int(digits, 16)))
                    except ValueError as exc:
                        raise self.error(f"\\u 转义非法：{digits!r}") from exc
                    self.pos += 5
                    continue
                mapping = {
                    "n": "\n", "t": "\t", "r": "\r", "b": "\b",
                    "f": "\f", "v": "\v", "0": "\0",
                }
                chunks.append(mapping.get(escape, escape))
                self.pos += 1
                continue
            if char == quote:
                self.pos += 1
                return "".join(chunks)
            chunks.append(char)
            self.pos += 1

    def number(self) -> Any:
        start = self.pos
        if self.peek() == "-":
            self.pos += 1
        while self.pos < len(self.text) and self.text[self.pos].isdigit():
            self.pos += 1
        is_float = False
        if self.peek() == ".":
            is_float = True
            self.pos += 1
            while self.pos < len(self.text) and self.text[self.pos].isdigit():
                self.pos += 1
        if self.peek() in ("e", "E"):
            is_float = True
            self.pos += 1
            if self.peek() in ("+", "-"):
                self.pos += 1
            while self.pos < len(self.text) and self.text[self.pos].isdigit():
                self.pos += 1
        raw = self.text[start: self.pos]
        try:
            return float(raw) if is_float else int(raw)
        except ValueError as exc:
            raise self.error(f"数字非法：{raw!r}") from exc

    def arr(self) -> list:
        self.pos += 1  # [
        items: list = []
        self.skip()
        if self.peek() == "]":
            self.pos += 1
            return items
        while True:
            items.append(self.value())
            self.skip()
            char = self.peek()
            if char == ",":
                self.pos += 1
                self.skip()
                if self.peek() == "]":
                    self.pos += 1
                    return items
                continue
            if char == "]":
                self.pos += 1
                return items
            raise self.error(f"数组里期望 , 或 ]，实际是 {char!r}")

    def obj(self) -> dict:
        self.pos += 1  # {
        result: dict = {}
        self.skip()
        if self.peek() == "}":
            self.pos += 1
            return result
        while True:
            self.skip()
            char = self.peek()
            if char in "'\"":
                key = self.string()
            else:
                key = self.identifier()
            self.skip()
            if self.peek() != ":":
                raise self.error(f"对象里期望 :，实际是 {self.peek()!r}")
            self.pos += 1
            result[key] = self.value()
            self.skip()
            char = self.peek()
            if char == ",":
                self.pos += 1
                self.skip()
                if self.peek() == "}":
                    self.pos += 1
                    return result
                continue
            if char == "}":
                self.pos += 1
                return result
            raise self.error(f"对象里期望 , 或 }}，实际是 {char!r}")


def parse_js_literal(text: str) -> Any:
    """解析一个 JS 数据字面量（对象/数组/字符串/数字/布尔/null）。"""
    parser = _JsParser(text)
    result = parser.value()
    parser.skip()
    if parser.pos != len(text):
        raise JsLiteralError(f"字面量后有多余内容：{text[parser.pos: parser.pos + 40]!r}")
    return result


def _slice_balanced(text: str, start: int) -> str | None:
    """从 ``text[start] == '{'`` 起按括号配平切出对象文本，跳过字符串与转义。"""
    if start >= len(text) or text[start] != "{":
        return None
    depth = 0
    quote = ""
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in "'\"":
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start: index + 1]
    return None


def extract_plan_model(html: str):
    """从页面 HTML 里抽出内联的培养计划模型。"""
    pattern = re.compile(r"var\s+" + _JS_OBJECT_VAR + r"\s*=\s*\{")
    for match in pattern.finditer(html):
        brace = html.find("{", match.start())
        snippet = _slice_balanced(html, brace)
        if snippet is None:
            continue
        try:
            parsed = parse_js_literal(snippet)
        except JsLiteralError:
            continue
        if isinstance(parsed, dict) and "moduleList" in parsed:
            return parsed
    return None


# ---------------------------------------------------------------------------
# 计划解析
# ---------------------------------------------------------------------------

#: 未通过的结课结果。教务实际取值是 UNREPAIRED（挂科未重修），不是 FAILED。
FAILED_RESULTS = frozenset({"UNREPAIRED", "FAILED", "FAIL", "NOT_PASSED", "UNPASSED"})
PASSED_RESULTS = frozenset({"PASSED", "PASS", "RECOGNIZED"})
TAKING_RESULTS = frozenset({"TAKING", "INPROGRESS", "IN_PROGRESS"})


def _f(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _i(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _result_name(value: Any) -> str:
    """从 ``{'$type': 'ResultType', '$name': 'PASSED'}`` 里取结果名。"""
    if isinstance(value, dict):
        return str(value.get("$name") or "").strip()
    if value is None:
        return ""
    return str(value).strip()


def _terms(value: Any) -> list[int]:
    if not isinstance(value, list):
        return []
    found: set[int] = set()
    for item in value:
        text = _result_name(item) if isinstance(item, dict) else str(item)
        digits = "".join(ch for ch in text if ch.isdigit())
        if digits:
            found.add(int(digits))
    return sorted(found)


def parse_course(raw: Any) -> dict | None:
    """解析 ``allCourseList`` 里的一门课。"""
    if not isinstance(raw, dict):
        return None
    name = str(raw.get("nameZh") or raw.get("name") or "").strip()
    code = str(raw.get("code") or "").strip()
    if not name and not code:
        return None
    gp_raw = raw.get("gp")
    try:
        gp = None if gp_raw is None else float(gp_raw)
    except (TypeError, ValueError):
        gp = None
    result = _result_name(raw.get("resultType") or raw.get("finalResultType"))
    upper = result.upper()
    return {
        "code": code,
        "name": name,
        "credits": _f(raw.get("credits")),
        "compulsory": bool(raw.get("compulsory")),
        "terms": _terms(raw.get("terms")),
        "result": result,
        "score": str(raw.get("gradeStr") or raw.get("score") or "").strip(),
        "gp": gp,
        "passed": upper in PASSED_RESULTS,
        "failed": upper in FAILED_RESULTS,
        "taking": upper in TAKING_RESULTS,
    }


def _collect_modules(node: Any, out: list[dict]) -> None:
    """递归收集学分模块。

    父模块与子模块都是独立学分桶，因此有子模块也要保留父模块本身，否则会丢掉
    例如「必修课」的 147 学分。每个节点只产出一份，不会重复计数。
    """
    if not isinstance(node, dict):
        return
    name = str(node.get("nameZh") or node.get("name") or "").strip()
    if not name:
        return

    raw_courses = node.get("allCourseList") or node.get("courseList")
    courses = []
    for item in raw_courses if isinstance(raw_courses, list) else []:
        course = parse_course(item)
        if course is not None:
            courses.append(course)

    info = node.get("requireInfo")
    info = info if isinstance(info, dict) else {}
    required = _f(info.get("credits"))
    summary = node.get("completionSummary")
    summary = summary if isinstance(summary, dict) else {}

    if courses or required > 0:
        note = ""
        if required > 0 and not courses:
            note = "该模块未列出课程，无法逐课核对，以教务系统为准"
        passed = _f(summary.get("passedCredits"))
        out.append(
            {
                "id": _i(node.get("moduleId") or node.get("id")),
                "name": name,
                "required_credits": required,
                "required_sub_modules": _i(info.get("subModuleNum")),
                "passed_credits": passed,
                "taking_credits": _f(summary.get("takingCredits")),
                "failed_credits": _f(summary.get("failedCredits")),
                "missing": max(0.0, required - passed),
                "done": passed + 1e-9 >= required,
                "ratio": (passed / required) if required > 0 else 1.0,
                "courses": courses,
                "note": note,
            }
        )

    children = node.get("children")
    for child in children if isinstance(children, list) else []:
        _collect_modules(child, out)


def parse_plan(payload: Any) -> dict:
    """把页面模型解析成可直接 JSON 化的字典。

    Raises:
        ValueError: 顶层不是对象，或没有可识别的模块。
    """
    if not isinstance(payload, dict):
        raise ValueError("培养计划响应不是对象")

    info = payload.get("requireInfo")
    info = info if isinstance(info, dict) else {}
    summary = payload.get("completionSummary")
    summary = summary if isinstance(summary, dict) else {}

    modules: list[dict] = []
    raw_modules = payload.get("moduleList")
    for item in raw_modules if isinstance(raw_modules, list) else []:
        _collect_modules(item, modules)

    if not modules:
        raise ValueError("培养计划里没有可识别的学分模块")

    required = _f(info.get("credits"))
    passed = _f(summary.get("passedCredits"))
    return {
        "id": _i(payload.get("id")),
        "required_credits": required,
        "required_sub_modules": _i(info.get("subModuleNum")),
        "passed_credits": passed,
        "taking_credits": _f(summary.get("takingCredits")),
        "failed_credits": _f(summary.get("failedCredits")),
        "missing": max(0.0, required - passed),
        "ratio": (passed / required) if required > 0 else 0.0,
        "modules": modules,
    }


def parse_plan_page(html: str) -> dict:
    """从培养计划页面 HTML 直接解析。

    Raises:
        ValueError: 页面里找不到计划模型。
    """
    model = extract_plan_model(html)
    if model is None:
        raise ValueError("未能从页面解析出培养计划模型（页面结构可能已更新）")
    return parse_plan(model)


def _dedupe_courses(modules: list[dict], key: str) -> list[dict]:
    """按结课结果收集课程并去重，保持出现顺序。"""
    seen: set = set()
    found: list[dict] = []
    for module in modules:
        for course in module.get("courses") or []:
            if not course.get(key):
                continue
            identity = (course.get("code") or course.get("name"), course.get("name"))
            if identity in seen:
                continue
            seen.add(identity)
            item = dict(course)
            item["module"] = module.get("name", "")
            found.append(item)
    return found


def _all_courses(modules: list[dict]) -> list[dict]:
    """汇总所有计划课程并去重。

    同一门课可能被多个模块各列一次（例如「专业综合实践」既在专业模块又在实践
    模块），按 ``(课程编号, 课程名, 学期)`` 去重——同一门课在不同学期各修一次
    是正常的，不能并掉。
    """
    seen: set = set()
    found: list[dict] = []
    for module in modules:
        for course in module.get("courses") or []:
            terms = tuple(course.get("terms") or ())
            identity = (
                course.get("code") or course.get("name"),
                course.get("name"),
                terms,
            )
            if identity in seen:
                continue
            seen.add(identity)
            item = dict(course)
            item["module"] = module.get("name", "")
            found.append(item)
    return found


def _classify(course: dict) -> str:
    """给课程打一个展示用状态。"""
    if course.get("passed"):
        return "passed"
    if course.get("taking"):
        return "taking"
    if course.get("failed"):
        return "failed"
    return "unknown"


def group_by_semester(modules: list[dict]) -> list[dict]:
    """把计划课程按学期分组，供界面分学期展示。

    学期来自课程自己的 ``terms``（例如 ``TERM_4`` → 第 4 学期）。一门课可能对应
    多个学期（如「形势与政策」跨 3/4/5/6/8 学期），会在每个学期各出现一次。
    没有学期信息的课程归入「未标注学期」，不丢弃。

    Returns:
        按学期序号升序排列的列表，每项含 ``semester``、``label``、``courses``、
        ``total_credits``、``earned_credits`` 与各状态计数。
    """
    buckets: dict[int, list[dict]] = {}
    unscheduled: list[dict] = []

    for course in _all_courses(modules):
        terms = list(course.get("terms") or ())
        if not terms:
            unscheduled.append(course)
            continue
        for term in terms:
            item = dict(course)
            item["status"] = _classify(course)
            item["planned_term"] = term
            buckets.setdefault(int(term), []).append(item)

    groups: list[dict] = []
    for term in sorted(buckets):
        courses = buckets[term]
        courses.sort(
            key=lambda c: (c.get("compulsory") is not True, c.get("name") or "")
        )
        groups.append(_semester_payload(term, f"第 {term} 学期", courses))

    if unscheduled:
        for course in unscheduled:
            course["status"] = _classify(course)
            course["planned_term"] = 0
        unscheduled.sort(key=lambda c: c.get("name") or "")
        groups.append(_semester_payload(0, "未标注学期", unscheduled))

    return groups


def _semester_payload(term: int, label: str, courses: list[dict]) -> dict:
    earned = sum(c.get("credits") or 0 for c in courses if c.get("passed"))
    total = sum(c.get("credits") or 0 for c in courses)

    # 平均绩点必须**按学分加权**：同一学期里 2 学分的课和 0.5 学分的课不能等权。
    # 只统计「已通过且有绩点」的课程；没有这样的课时给 None，不能给 0
    # （0 会被误读成成绩很差）。
    graded = [
        c
        for c in courses
        if c.get("passed") and c.get("gp") is not None and (c.get("credits") or 0) > 0
    ]
    graded_credits = sum(float(c["credits"]) for c in graded)
    average_gp = (
        sum(float(c["gp"]) * float(c["credits"]) for c in graded) / graded_credits
        if graded_credits > 0
        else None
    )

    return {
        "semester": term,
        "label": label,
        "courses": courses,
        "course_count": len(courses),
        "total_credits": round(total, 2),
        "earned_credits": round(earned, 2),
        "passed_count": sum(1 for c in courses if c.get("passed")),
        "taking_count": sum(1 for c in courses if c.get("taking")),
        "failed_count": sum(1 for c in courses if c.get("failed")),
        "average_gp": None if average_gp is None else round(average_gp, 3),
        "graded_credits": round(graded_credits, 2),
    }


def summarize_plan(plan: dict) -> dict:
    """补充未通过/在修课程清单与分学期视图，供界面直接展示。"""
    modules = plan.get("modules") or []
    result = dict(plan)
    result["failed_courses"] = _dedupe_courses(modules, "failed")
    result["taking_courses"] = _dedupe_courses(modules, "taking")
    result["semesters"] = group_by_semester(modules)
    result["ok"] = True
    return result

