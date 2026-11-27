"""教务首页 / 门户个人信息与个人头像解析的离线回归自检（不联网、不依赖原生扩展）。

    python scripts/run_tests.py
    python scripts/test_mobile_profile.py
"""

from __future__ import annotations

import base64
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

import mobile_profile_page as profile  # noqa: E402

SAMPLE_PNG = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
SAMPLE_PNG_B64 = base64.b64encode(SAMPLE_PNG).decode("ascii")

SAMPLE_HOME_NO_PORTRAIT = rf"""
<!DOCTYPE html>
<html lang="zh">
<head><title id="home_page_title">首页</title>
<script>
  window.CONTEXT_PATH = '/student';
  window.personName = '\u5f20\u4e09';
  window.accountId = 10001;
  window.hasPortrait = false;
  window.defaultAvatar = 'data:image/png;base64,{SAMPLE_PNG_B64}';
</script>
</head>
<body><div id="app"></div></body>
</html>
"""

SAMPLE_HOME_WITH_PORTRAIT = """
<script>
  window.personName = "李四";
  window.hasPortrait = true;
</script>
"""

SAMPLE_HOME_NULL = """
<script>
  window.personName = null;
</script>
"""


def test_parse_home_profile_no_portrait_unicode_and_default_bytes() -> None:
    result = profile.parse_home_profile(SAMPLE_HOME_NO_PORTRAIT)
    assert result["name"] == "张三"
    assert result["has_portrait"] is False
    assert result["default_avatar_bytes"] == SAMPLE_PNG


def test_parse_home_profile_with_portrait() -> None:
    result = profile.parse_home_profile(SAMPLE_HOME_WITH_PORTRAIT)
    assert result == {
        "name": "李四",
        "has_portrait": True,
        "default_avatar_bytes": b"",
    }


def test_parse_home_profile_handles_null_and_missing() -> None:
    assert profile.parse_home_profile(SAMPLE_HOME_NULL) == {
        "name": "",
        "has_portrait": False,
        "default_avatar_bytes": b"",
    }
    assert profile.parse_home_profile("") == {
        "name": "",
        "has_portrait": False,
        "default_avatar_bytes": b"",
    }


def test_extract_profile_from_json_portal_and_eams_door() -> None:
    portal_payload = {
        "code": 0,
        "data": {
            "user": {"name": "王五", "imageUrl": "group1/M00/00/01/avatar.gif"},
            "accounts": [],
        },
    }
    assert profile.extract_profile_from_json(portal_payload) == {
        "name": "王五",
        "avatar_ref": "group1/M00/00/01/avatar.gif",
    }

    door_payload = {
        "result": 0,
        "data": {"userName": "赵六", "avatar": "https://example.com/a.webp"},
    }
    assert profile.extract_profile_from_json(door_payload) == {
        "name": "赵六",
        "avatar_ref": "https://example.com/a.webp",
    }


def test_decode_data_uri_image_and_supported_magic_bytes() -> None:
    jpeg = b"\xff\xd8\xff\xe0\x00\x10JFIF"
    gif = b"GIF89a\x01\x00\x01\x00"
    webp = b"RIFF\x18\x00\x00\x00WEBP"

    assert profile.decode_data_uri_image(f"data:image/png;base64,{SAMPLE_PNG_B64}") == SAMPLE_PNG
    assert profile.decode_data_uri_image("data:image/svg+xml;base64,PHN2Zy8+") == b""
    assert profile.looks_like_image(SAMPLE_PNG, "image/png") is True
    assert profile.detect_image_mime(SAMPLE_PNG) == "image/png"
    assert profile.looks_like_image(jpeg, "image/jpeg") is True
    assert profile.detect_image_mime(jpeg) == "image/jpeg"
    assert profile.looks_like_image(gif, "image/gif") is True
    assert profile.detect_image_mime(gif) == "image/gif"
    assert profile.looks_like_image(webp, "image/webp") is True
    assert profile.detect_image_mime(webp) == "image/webp"


def test_looks_like_image_rejects_svg_html_json_empty_and_oversized() -> None:
    assert profile.looks_like_image(b"") is False
    assert profile.looks_like_image(b"<svg xmlns='http://www.w3.org/2000/svg'></svg>") is False
    assert profile.looks_like_image(b"<!DOCTYPE html><html>login</html>", "image/png") is False
    assert profile.looks_like_image(b'{"result":1,"msg":"error"}') is False
    oversized = b"\x89PNG\r\n\x1a\n" + b"0" * profile.MAX_AVATAR_BYTES
    assert profile.looks_like_image(oversized) is False


def main() -> None:
    for check in (
        test_parse_home_profile_no_portrait_unicode_and_default_bytes,
        test_parse_home_profile_with_portrait,
        test_parse_home_profile_handles_null_and_missing,
        test_extract_profile_from_json_portal_and_eams_door,
        test_decode_data_uri_image_and_supported_magic_bytes,
        test_looks_like_image_rejects_svg_html_json_empty_and_oversized,
    ):
        check()
    print("OK: mobile_profile_page 6 checks passed")


if __name__ == "__main__":
    main()
