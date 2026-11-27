"""整学期课表离线缓存分组逻辑的自检脚本（不联网、不依赖原生扩展）。

    python scripts/run_tests.py
    python scripts/test_mobile_schedule_cache.py
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

from mobile_schedule_cache import group_semester_lessons  # noqa: E402


def test_week_indexes_expansion() -> None:
    lessons = [
        {
            "course": "高等数学",
            "code": "MATH101",
            "weekday": 1,
            "start_unit": 1,
            "end_unit": 2,
            "start_time": "08:00",
            "place": "核心区 101",
            "week_indexes": [1, 2, 4],
        }
    ]
    result = group_semester_lessons(lessons, "2026-09-07", list(range(1, 17)))
    assert result["max_week"] == 16
    assert result["total_lessons"] == 3
    assert set(result["weeks"].keys()) == {"1", "2", "4"}
    assert result["weeks"]["2"][0]["course"] == "高等数学"


def test_date_fallback_when_week_indexes_empty() -> None:
    lessons = [
        {
            "course": "大学物理实验",
            "code": "PHYS102",
            "weekday": 3,
            "start_unit": 5,
            "end_unit": 6,
            "start_time": "14:00",
            "place": "实验楼 203",
            "date": "2026-09-23",
            "week_indexes": [],
        },
        {
            "course": "未定时间",
            "code": "NONE00",
            "weekday": 2,
            "start_unit": 1,
            "end_unit": 2,
            "start_time": "08:00",
            "place": "",
            "date": "",
            "week_indexes": [],
        },
    ]
    result = group_semester_lessons(lessons, "2026-09-07T00:00:00", None)
    # 2026-09-23 - 2026-09-07 = 16 days -> // 7 + 1 = week 3
    assert set(result["weeks"].keys()) == {"3"}
    assert result["total_lessons"] == 1
    assert result["max_week"] == 3
    assert result["weeks"]["3"][0]["course"] == "大学物理实验"


def test_dedup_and_sorting_per_week() -> None:
    lessons = [
        {
            "course": "数据结构",
            "code": "CS201",
            "weekday": 3,
            "start_unit": 3,
            "end_unit": 4,
            "start_time": "10:10",
            "place": "中101",
            "week_indexes": [2],
        },
        {
            "course": "数据结构",
            "code": "CS201",
            "weekday": 3,
            "start_unit": 3,
            "end_unit": 4,
            "start_time": "10:10",
            "place": "中101",
            "week_indexes": [2],
        },
        {
            "course": "线性代数",
            "code": "MATH102",
            "weekday": 1,
            "start_unit": 1,
            "end_unit": 2,
            "start_time": "08:00",
            "place": "南202",
            "week_indexes": [2],
        },
        {
            "course": "面向对象",
            "code": "CS202",
            "weekday": 3,
            "start_unit": 1,
            "end_unit": 2,
            "start_time": "08:00",
            "place": "北303",
            "week_indexes": [2],
        },
    ]
    result = group_semester_lessons(lessons, "2026-09-07", None)
    week2 = result["weeks"]["2"]
    assert len(week2) == 3, f"expected 3 deduped lessons, got {len(week2)}"
    assert [item["course"] for item in week2] == [
        "线性代数",
        "面向对象",
        "数据结构",
    ]


def test_max_week_handles_empty_semester() -> None:
    result = group_semester_lessons([], "", None)
    assert result["weeks"] == {}
    assert result["max_week"] == 1
    assert result["total_lessons"] == 0


def main() -> None:
    test_week_indexes_expansion()
    test_date_fallback_when_week_indexes_empty()
    test_dedup_and_sorting_per_week()
    test_max_week_handles_empty_semester()


if __name__ == "__main__":
    main()
