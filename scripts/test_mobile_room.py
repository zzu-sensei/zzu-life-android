"""空闲教室页面与一卡通余额解析的离线回归自检（不联网、不依赖原生扩展）。

    python scripts/run_tests.py
    python scripts/test_mobile_room.py
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

import mobile_room_page as room  # noqa: E402

SAMPLE_HTML = """
<html><body>
<script>
  var _campusList = [
    {'text':'\\u4E3B\\u6821\\u533A','value':2},
    {'text':'\\u5357\\u6821\\u533A','value':3},
    {'text':'\\u5317\\u6821\\u533A','value':4}
  ];
  var _roomTypeList = [
    {'text':'\\u666E\\u901A\\u6559\\u5BA4','value':1},
    {'text':'\\u591A\\u5A92\\u4F53\\u6559\\u5BA4','value':2}
  ];
  var _units = [
    {'changeTime':null,'dayPart':{'$type':'DayPart','$name':'MORNING'},'name':'1','segmentIndex':1,'time':'08:00-08:45','value':'1'},
    {'changeTime':null,'dayPart':{'$type':'DayPart','$name':'AFTERNOON'},'name':'5','segmentIndex':3,'time':'14:00-14:45','value':'5'}
  ];
  var _semesterStart = '2026-09-07';
  var _semesterWeeks = 19;
</script>
</body></html>
"""


def test_parse_room_free_meta() -> None:
    meta = room.parse_room_free_meta(SAMPLE_HTML)
    assert [c["name"] for c in meta["campuses"]] == ["主校区", "南校区", "北校区"]
    assert meta["campuses"][0]["id"] == 2
    assert [t["name"] for t in meta["room_types"]] == ["普通教室", "多媒体教室"]
    assert len(meta["units"]) == 2
    assert meta["units"][0]["day_part"] == "MORNING"
    assert meta["units"][0]["value"] == 1
    assert meta["semester_start"] == "2026-09-07"
    assert meta["semester_weeks"] == 19


def test_normalize_buildings_filters_disabled() -> None:
    buildings = room.normalize_buildings(
        [
            {"id": 5, "nameZh": "北1", "enabled": True},
            {"id": 6, "nameZh": "北2", "enabled": False},
            {"id": 7, "nameZh": "北3", "enabled": True},
        ]
    )
    assert buildings == [{"id": 5, "name": "北1"}, {"id": 7, "name": "北3"}]


def test_normalize_free_rooms_sorts_and_skips_virtual() -> None:
    rooms = room.normalize_free_rooms(
        [
            {
                "id": 2,
                "nameZh": "北2_201",
                "code": "B2201",
                "floor": 2,
                "virtual": False,
                "seatsForLesson": 120,
                "building": {"id": 6, "nameZh": "北2", "campus": {"nameZh": "主校区"}},
                "roomType": {"nameZh": "多媒体教室"},
            },
            {
                "id": 99,
                "nameZh": "虚拟教室",
                "virtual": True,
                "building": {"id": 5, "nameZh": "北1", "campus": {"nameZh": "主校区"}},
            },
            {
                "id": 3,
                "nameZh": "北1_301",
                "floor": 3,
                "virtual": False,
                "seatsForLesson": 80,
                "building": {"id": 5, "nameZh": "北1", "campus": {"nameZh": "主校区"}},
                "roomType": {"nameZh": "普通教室"},
            },
            {
                "id": 1,
                "nameZh": "北1_102",
                "floor": 1,
                "virtual": False,
                "seatsForLesson": 219,
                "building": {"id": 5, "nameZh": "北1", "campus": {"nameZh": "主校区"}},
                "roomType": {"nameZh": "多媒体教室"},
            },
        ]
    )
    assert [r["name"] for r in rooms] == ["北1_102", "北1_301", "北2_201"]
    assert rooms[0]["seats"] == 219
    assert rooms[0]["building_id"] == 5


def test_parse_portal_cards() -> None:
    parsed = room.parse_portal_cards(
        {
            "code": 0,
            "data": [
                {"name": "我的邮箱", "amount": "12", "unit": "封"},
                {"name": "其他卡片", "amount": "", "unit": ""},
                {"name": "一卡通余额", "amount": "58.40", "unit": "元"},
            ],
        }
    )
    assert parsed["balance"] == 58.4
    assert parsed["unit"] == "元"
    assert parsed["email_unread"] == 12

    try:
        room.parse_portal_cards({"data": [{"name": "我的邮箱", "amount": "3", "unit": "封"}]})
        raise AssertionError("expected RuntimeError when card balance is missing")
    except RuntimeError:
        pass


def main() -> None:
    test_parse_room_free_meta()
    test_normalize_buildings_filters_disabled()
    test_normalize_free_rooms_sorts_and_skips_virtual()
    test_parse_portal_cards()


if __name__ == "__main__":
    main()
