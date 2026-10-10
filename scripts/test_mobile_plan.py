"""解析器的离线回归自检（不联网、不需要账号）。

覆盖 ``mobile_plan_page.py`` 里几条容易被「顺手简化」掉的规则：教务页面用的是
JS 对象字面量而不是 JSON、未通过的结课结果叫 ``UNREPAIRED``、绩点必须按学分加权、
课程要按学期分组。

    python scripts/run_tests.py
    python scripts/test_mobile_plan.py

这些断言来自对着真实教务响应调试的结果，不是构造着玩的。改动解析器后请先跑它。
"""

from __future__ import annotations

import sys
from pathlib import Path

PYTHON_SOURCE = (
    Path(__file__).resolve().parents[1]
    / "flutter-app"
    / "android"
    / "app"
    / "src"
    / "main"
    / "python"
)
sys.path.insert(0, str(PYTHON_SOURCE))

import mobile_plan_page as mobile  # noqa: E402


# ---------------------------------------------------------------------------
# 夹具：按真实页面结构构造（JS 写法：单引号、裸键、$ 键）
# ---------------------------------------------------------------------------


def _as_js(value: object) -> str:
    """渲染成 JS 对象字面量的近似写法，用来喂给解析器。"""
    if isinstance(value, dict):
        parts = []
        for key, item in value.items():
            rendered = key if key.replace("_", "").isalnum() else f"'{key}'"
            parts.append(f"{rendered}:{_as_js(item)}")
        return "{" + ",".join(parts) + "}"
    if isinstance(value, list):
        return "[" + ",".join(_as_js(item) for item in value) + "]"
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace("'", "\\'")
        return f"'{escaped}'"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _result(name: str) -> dict:
    return {"$type": "ResultType", "$name": name}


def _course(code, name, credits, result, *, compulsory=True, term=1, score="", gp=None):
    return {
        "code": code,
        "nameZh": name,
        "credits": credits,
        "compulsory": compulsory,
        "resultType": _result(result),
        "finalResultType": _result(result),
        "gradeStr": score,
        "gp": gp,
        "terms": [{"$type": "Term", "$name": f"TERM_{term}"}],
    }


def _summary(passed=0.0, taking=0.0, failed=0.0):
    return {
        "passedCredits": passed,
        "takingCredits": taking,
        "failedCredits": failed,
        "passedSubModuleNum": 0,
        "inCredits": 0,
        "logicCredits": 0,
    }


def _module(module_id, name, required, courses, summary, children=None):
    return {
        "moduleId": module_id,
        "nameZh": name,
        "requireInfo": {"credits": required, "subModuleNum": 0},
        "completionSummary": summary,
        "allCourseList": courses,
        "courseList": courses,
        "children": children or [],
    }


def _html(model: dict) -> str:
    return "<html><script>var model = " + _as_js(model) + ";</script></html>"


#: 精简版真实模型：总要求 175 学分，含在修与未通过（UNREPAIRED）。
MODEL = {
    "id": 123456,
    "requireInfo": {"credits": 175, "subModuleNum": 4},
    "completionSummary": _summary(passed=102.5, taking=24.0, failed=72.5),
    "moduleList": [
        _module(
            112940,
            "必修课",
            147,
            [
                _course("371061", "大学英语（IV）", 2, "PASSED", term=4, score="84", gp=3.2),
                _course("022056", "微机原理与单片机应用", 3, "TAKING", term=4),
                _course("022015", "电磁场", 2, "UNREPAIRED", term=4, score="45", gp=0.0),
            ],
            _summary(passed=83.5, taking=18.0, failed=63.5),
        ),
        _module(112942, "校_任选课", 5, [], _summary(passed=6.0)),
        _module(
            112943,
            "院_任选课",
            12,
            [
                _course("024061", "电气工程导论", 1, "PASSED", term=4, score="90"),
                _course("023031", "热力发电厂", 2, "TAKING", compulsory=False, term=7),
            ],
            _summary(passed=7.0, taking=4.0),
        ),
        _module(
            114396,
            "限选课",
            11,
            [
                _course("491003", "体育（III）", 1, "PASSED", term=3, score="85"),
                _course("331002", "国家安全教育", 3, "TAKING", term=1),
            ],
            _summary(passed=7.0, taking=2.0),
        ),
    ],
}


# ---------------------------------------------------------------------------
# JS 字面量解析
# ---------------------------------------------------------------------------


def test_js_literal_basics() -> None:
    assert mobile.parse_js_literal("{'a':1,'b':'x'}") == {"a": 1, "b": "x"}
    # 裸键与 $ 开头的键（教务真实写法）
    assert mobile.parse_js_literal("{credits:147,'$type':'ResultType'}") == {
        "credits": 147,
        "$type": "ResultType",
    }
    # \uXXXX 转义
    assert mobile.parse_js_literal(r"'\u5FC5\u4FEE\u8BFE'") == "必修课"
    assert mobile.parse_js_literal(r"'it\'s ok'") == "it's ok"
    assert mobile.parse_js_literal("{a:[1,2,{b:null,c:true}]}") == {
        "a": [1, 2, {"b": None, "c": True}]
    }
    assert mobile.parse_js_literal("[-1.5, 2e3, ]") == [-1.5, 2000.0]
    assert mobile.parse_js_literal("{a:1,}") == {"a": 1}


def test_js_literal_rejects_non_literals() -> None:
    """不是数据字面量必须报错，绝不求值。"""
    for bad in ("new Date()", "someVariable", "function(){}", "{a: alert(1)}", "{a:1", "[1,2", ""):
        try:
            mobile.parse_js_literal(bad)
        except mobile.JsLiteralError:
            pass
        else:
            raise AssertionError(f"{bad!r} 应该被拒绝")


# ---------------------------------------------------------------------------
# 计划解析
# ---------------------------------------------------------------------------


def test_plan_summary_and_modules() -> None:
    plan = mobile.summarize_plan(mobile.parse_plan_page(_html(MODEL)))
    assert plan["id"] == 123456
    assert plan["required_credits"] == 175.0
    assert plan["required_sub_modules"] == 4
    assert plan["passed_credits"] == 102.5
    assert plan["taking_credits"] == 24.0
    assert plan["failed_credits"] == 72.5
    assert plan["missing"] == 72.5

    names = [m["name"] for m in plan["modules"]]
    assert names == ["必修课", "校_任选课", "院_任选课", "限选课"]
    # 模块学分之和必须等于总要求
    assert sum(m["required_credits"] for m in plan["modules"]) == 175.0

    by_name = {m["name"]: m for m in plan["modules"]}
    assert by_name["必修课"]["passed_credits"] == 83.5
    assert by_name["必修课"]["missing"] == 63.5
    assert by_name["必修课"]["done"] is False
    assert by_name["校_任选课"]["done"] is True  # 6 >= 5


def test_unrepaired_is_recognised_as_failed() -> None:
    """未通过的取值是 UNREPAIRED；只匹配 FAILED 会一门都列不出来。"""
    plan = mobile.summarize_plan(mobile.parse_plan_page(_html(MODEL)))
    failed = plan["failed_courses"]
    assert [c["code"] for c in failed] == ["022015"], [c["name"] for c in failed]
    assert failed[0]["name"] == "电磁场"

    taking = sorted(c["code"] for c in plan["taking_courses"])
    assert taking == ["022056", "023031", "331002"], taking
    # 课程要带所属模块，便于界面标注
    assert all(c["module"] for c in failed + plan["taking_courses"])


def test_result_classification_constants() -> None:
    assert "UNREPAIRED" in mobile.FAILED_RESULTS
    assert "FAILED" in mobile.FAILED_RESULTS
    assert "PASSED" in mobile.PASSED_RESULTS
    assert "TAKING" in mobile.TAKING_RESULTS
    # 三个集合不能互相重叠
    assert not (mobile.PASSED_RESULTS & mobile.FAILED_RESULTS)
    assert not (mobile.PASSED_RESULTS & mobile.TAKING_RESULTS)
    assert not (mobile.FAILED_RESULTS & mobile.TAKING_RESULTS)
    assert "" not in mobile.PASSED_RESULTS | mobile.FAILED_RESULTS | mobile.TAKING_RESULTS


def test_nested_modules_are_kept() -> None:
    """父模块与子模块都是独立学分桶，都不能丢。"""
    child = _module(
        116340,
        "实践教学",
        25,
        [_course("025032", "毕业设计", 16, "TAKING", term=8)],
        _summary(taking=16.0),
    )
    model = {**MODEL}
    model["moduleList"] = [
        dict(MODEL["moduleList"][0], children=[child]),
        *MODEL["moduleList"][1:],
    ]
    plan = mobile.parse_plan_page(_html(model))
    names = [m["name"] for m in plan["modules"]]
    assert "必修课" in names and "实践教学" in names
    assert names.index("必修课") < names.index("实践教学")


def test_empty_module_gets_note() -> None:
    model = {**MODEL}
    model["moduleList"] = [*MODEL["moduleList"]]
    model["moduleList"][1] = dict(MODEL["moduleList"][1])
    model["moduleList"][1]["requireInfo"] = {"credits": 12, "subModuleNum": 0}
    plan = mobile.parse_plan_page(_html(model))
    module = next(m for m in plan["modules"] if m["name"] == "校_任选课")
    assert module["required_credits"] == 12.0
    assert "未列出课程" in module["note"]


def test_rejects_bad_input() -> None:
    for bad in ("<html>空</html>", "<script>var model = {};</script>"):
        try:
            mobile.parse_plan_page(bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"应该拒绝 {bad!r}")

    for bad in ([], "x", 42, None, {"requireInfo": {}}):
        try:
            mobile.parse_plan(bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"应该拒绝 {bad!r}")


# ---------------------------------------------------------------------------
# 学期分组与绩点
# ---------------------------------------------------------------------------


def test_semester_grouping() -> None:
    plan = mobile.summarize_plan(mobile.parse_plan_page(_html(MODEL)))
    semesters = plan["semesters"]
    assert [s["label"] for s in semesters] == [
        "第 1 学期", "第 3 学期", "第 4 学期", "第 7 学期",
    ], [s["label"] for s in semesters]

    by_term = {s["semester"]: s for s in semesters}
    term4 = by_term[4]
    assert term4["course_count"] == 4
    assert term4["failed_count"] == 1
    assert term4["taking_count"] == 1
    assert term4["passed_count"] == 2
    assert term4["earned_credits"] == 3.0  # 大学英语 2 + 电气工程导论 1

    english = next(c for c in term4["courses"] if c["code"] == "371061")
    assert (english["score"], english["gp"], english["status"]) == ("84", 3.2, "passed")
    assert english["module"] == "必修课"

    assert next(c for c in term4["courses"] if c["code"] == "022056")["status"] == "taking"
    assert next(c for c in term4["courses"] if c["code"] == "022015")["status"] == "failed"

    # 必修课排在选修课前面
    assert term4["courses"][0]["name"] == "大学英语（IV）"


def test_average_gp_is_credit_weighted() -> None:
    """平均绩点必须按学分加权。

    4 学分课绩点 4.0 + 1 学分课绩点 1.0：
      算术平均 = 2.5（错）   学分加权 = 3.4（对）
    """
    model = {**MODEL}
    model["moduleList"] = [
        _module(
            112940,
            "必修课",
            147,
            [
                _course("A001", "四学分课", 4, "PASSED", term=2, score="95", gp=4.0),
                _course("A002", "一学分课", 1, "PASSED", term=2, score="61", gp=1.0),
            ],
            _summary(passed=5.0),
        )
    ]
    plan = mobile.summarize_plan(mobile.parse_plan_page(_html(model)))
    semester = plan["semesters"][0]
    assert semester["average_gp"] == 3.4, semester["average_gp"]
    assert semester["average_gp"] != 2.5, "退化成了算术平均"
    assert semester["graded_credits"] == 5.0


def test_average_gp_ignores_unweightable() -> None:
    """无绩点、在修、未通过、零学分的课都不能进入平均。"""
    model = {**MODEL}
    model["moduleList"] = [
        _module(
            112940,
            "必修课",
            147,
            [
                _course("B001", "有三学分的课", 3, "PASSED", term=2, gp=3.0, score="85"),
                _course("B002", "通过但无绩点", 2, "PASSED", term=2, score="合格"),
                _course("B003", "在修", 4, "TAKING", term=2),
                _course("B004", "未通过", 4, "UNREPAIRED", term=2, score="30", gp=0.0),
                _course("B005", "零学分课", 0, "PASSED", term=2, gp=4.0, score="90"),
            ],
            _summary(passed=5.0, taking=4.0, failed=4.0),
        )
    ]
    plan = mobile.summarize_plan(mobile.parse_plan_page(_html(model)))
    semester = plan["semesters"][0]
    assert semester["average_gp"] == 3.0, semester["average_gp"]
    assert semester["graded_credits"] == 3.0


def test_no_gradeable_course_gives_none() -> None:
    """没有可统计的课时给 None，不能给 0（0 会被误读为成绩很差）。"""
    model = {**MODEL}
    model["moduleList"] = [
        _module(
            112940,
            "必修课",
            147,
            [_course("C001", "只有成绩没有绩点", 2, "PASSED", term=1, score="85")],
            _summary(passed=2.0),
        )
    ]
    plan = mobile.summarize_plan(mobile.parse_plan_page(_html(model)))
    assert plan["semesters"][0]["average_gp"] is None


def test_multi_term_course_appears_in_each_semester() -> None:
    course = _course("12801", "形势与政策", 2, "TAKING")
    course["terms"] = [{"$type": "Term", "$name": f"TERM_{t}"} for t in (3, 4, 5, 6, 8)]
    model = {**MODEL}
    model["moduleList"] = [_module(112940, "必修课", 147, [course], _summary(taking=2.0))]
    plan = mobile.summarize_plan(mobile.parse_plan_page(_html(model)))
    assert [s["semester"] for s in plan["semesters"]] == [3, 4, 5, 6, 8]


def test_course_without_terms_is_not_dropped() -> None:
    course = _course("999999", "没学期信息的课", 1, "PASSED", score="80", gp=3.0)
    course["terms"] = []
    model = {**MODEL}
    model["moduleList"] = [_module(112940, "必修课", 147, [course], _summary(passed=1.0))]
    plan = mobile.summarize_plan(mobile.parse_plan_page(_html(model)))
    assert len(plan["semesters"]) == 1
    assert plan["semesters"][0]["label"] == "未标注学期"
    assert plan["semesters"][0]["courses"][0]["code"] == "999999"


def test_same_course_across_modules_deduped_per_semester() -> None:
    course = _course("025032", "毕业设计", 16, "TAKING", term=8)
    model = {**MODEL}
    model["moduleList"] = [
        _module(112940, "必修课", 147, [course], _summary(taking=16.0)),
        _module(116340, "实践教学", 0, [dict(course)], _summary(taking=16.0)),
    ]
    plan = mobile.summarize_plan(mobile.parse_plan_page(_html(model)))
    term8 = next(s for s in plan["semesters"] if s["semester"] == 8)
    assert term8["course_count"] == 1


def main() -> None:
    test_js_literal_basics()
    test_js_literal_rejects_non_literals()
    test_plan_summary_and_modules()
    test_unrepaired_is_recognised_as_failed()
    test_result_classification_constants()
    test_nested_modules_are_kept()
    test_empty_module_gets_note()
    test_rejects_bad_input()
    test_semester_grouping()
    test_average_gp_is_credit_weighted()
    test_average_gp_ignores_unweightable()
    test_no_gradeable_course_gives_none()
    test_multi_term_course_appears_in_each_semester()
    test_course_without_terms_is_not_dropped()
    test_same_course_across_modules_deduped_per_semester()
    print("手机端培养计划解析自检全部通过。")


if __name__ == "__main__":
    main()
