"""考试信息页面解析的离线回归自检（不联网、不需要账号）。

覆盖 ``mobile_exam_page.py`` 里几条容易被「顺手简化」掉的规则：教务页面用的是 JS
对象字面量而不是 JSON、按学期查询、没有排考的学期返回空数组是正常的、地点字段带
首尾空白、状态是英文码要另给中文说明。

    python scripts/run_tests.py
    python scripts/test_mobile_exam.py

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

import mobile_exam_page as exam  # noqa: E402

PAGE = """
<html><body>
<select class="selectize" id="semester" name="semester">
  <option value="">...</option>
  <option selected="selected" value="194">2026-2027-1</option>
  <option value="193">2025-2026-2</option>
</select>
<script>
      var studentExamInfoVms = [
        {
          id: 10285219,
          alphabetSeatNo: '94',
          seatNo: 94,
          examTime: '2026-07-03 09:00~11:00',
          examStatusStr: 'NORMAL',
          finished: true,
          room: '\\u53171_104',
          paperCode: '2025-2026-2-022006-01',
          paperKind: 'A',
          remark: null,
          makeUpConfirmStatus: null,
          course: { code: '022006', nameZh: '\\u6A21\\u62DF\\u7535\\u5B50\\u6280\\u672F', credits: 3 },
          examType: { nameZh: '期末考试' },
          requiredCampus: { nameZh: '主校区' },
          examBatch: { name: '考试周期末考试' },
          examMngtDepartment: { nameZh: '电气与信息工程学院' },
          examPlace: { arrangedExamPlace: '主校区-北1-北1_104\\r\\n' }
        },
        {
          id: 10285220,
          examTime: '',
          examStatus: {'$type': 'ExamStatus', '$name': 'DELAY'},
          finished: false,
          room: '',
          course: { code: '022056', nameZh: '微机原理与单片机应用', credits: 3.5 },
          examType: { nameZh: '期末考试' },
          requiredCampus: { nameZh: '北校区' },
          examPlace: {}
        }
      ];
</script>
</body></html>
"""

EMPTY_PAGE = "<script>var studentExamInfoVms = [];</script>"


def test_parse_records() -> None:
    exams = exam.parse_exams(PAGE)
    assert len(exams) == 2, exams

    first = exams[0]
    assert first["id"] == 10285219
    assert first["course_name"] == "模拟电子技术", first["course_name"]
    assert first["course_code"] == "022006"
    assert first["credits"] == 3
    assert first["exam_time"] == "2026-07-03 09:00~11:00"
    assert first["date"] == "2026-07-03"
    assert first["start_time"] == "09:00"
    assert first["end_time"] == "11:00"
    assert first["exam_type"] == "期末考试"
    assert first["campus"] == "主校区"
    assert first["room"] == "北1_104", first["room"]
    # 教务给的地点带首尾空白，要清掉。
    assert first["place"] == "主校区-北1-北1_104", first["place"]
    assert first["seat_no"] == "94"
    assert first["paper_code"] == "2025-2026-2-022006-01"
    assert first["paper_kind"] == "A"
    assert first["status"] == "NORMAL"
    assert first["status_label"] == "正常"
    assert first["finished"] is True
    assert first["batch"] == "考试周期末考试"
    assert first["department"] == "电气与信息工程学院"
    assert first["remark"] is None

    second = exams[1]
    assert second["date"] == ""
    assert second["start_time"] == "" and second["end_time"] == ""
    # examStatusStr 缺失时回退到 examStatus.$name。
    assert second["status"] == "DELAY"
    assert second["status_label"] == "延期"
    assert second["credits"] == 3.5
    # 没有 arrangedExamPlace 时用 校区 + 教室 兜底。
    assert second["place"] == "北校区", second["place"]
    assert second["seat_no"] == ""
    assert second["finished"] is False


def test_empty_list_is_not_an_error() -> None:
    assert exam.parse_exams(EMPTY_PAGE) == []


def test_missing_variable_raises() -> None:
    try:
        exam.parse_exams("<html><body>没有数据</body></html>")
    except RuntimeError as error:
        assert "没有找到考试数据" in str(error)
    else:  # pragma: no cover - 走到这里说明解析器没有报错
        raise AssertionError("缺少变量时应当报错")


def test_non_array_raises() -> None:
    try:
        exam.parse_exams("<script>var studentExamInfoVms = {id: 1};</script>")
    except RuntimeError as error:
        assert "没有找到考试数据" in str(error)
    else:  # pragma: no cover
        raise AssertionError("数据不是数组时应当报错")


def test_parse_semesters() -> None:
    semesters = exam.parse_exam_semesters(PAGE)
    assert [(item["id"], item["name"]) for item in semesters] == [
        (194, "2026-2027-1"),
        (193, "2025-2026-2"),
    ], semesters


def test_missing_semester_select_raises() -> None:
    try:
        exam.parse_exam_semesters("<html>没有下拉</html>")
    except RuntimeError as error:
        assert "学期下拉" in str(error)
    else:  # pragma: no cover
        raise AssertionError("缺少学期下拉时应当报错")


def main() -> None:
    test_parse_records()
    test_empty_list_is_not_an_error()
    test_missing_variable_raises()
    test_non_array_raises()
    test_parse_semesters()
    test_missing_semester_select_raises()
    print("安卓端考试解析自检通过：字段映射、时间拆分、状态兜底、学期下拉与报错均正常。")


if __name__ == "__main__":
    main()
