"""教务首页个人信息与个人头像解析的离线回归自检（不联网、不依赖原生扩展）。

    python scripts/run_tests.py
    python scripts/test_mobile_profile.py
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

import mobile_profile_page as profile  # noqa: E402

SAMPLE_HOME_NO_PORTRAIT = r"""
<!DOCTYPE html>
<html lang="zh">
<head><title id="home_page_title">首页</title>
<script>
  window.CONTEXT_PATH = '/student';
  window.personName = '\u5f20\u4e09';
  window.accountId = 10001;
  window.hasPortrait = false;
  window.defaultAvatar = 'data:image/png;base64,AAAA';
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


def test_parse_home_profile_no_portrait_unicode_escape() -> None:
    result = profile.parse_home_profile(SAMPLE_HOME_NO_PORTRAIT)
    assert result == {"name": "张三", "has_portrait": False}


def test_parse_home_profile_with_portrait() -> None:
    result = profile.parse_home_profile(SAMPLE_HOME_WITH_PORTRAIT)
    assert result == {"name": "李四", "has_portrait": True}


def test_parse_home_profile_handles_null_and_missing() -> None:
    assert profile.parse_home_profile(SAMPLE_HOME_NULL) == {
        "name": "",
        "has_portrait": False,
    }
    assert profile.parse_home_profile("") == {"name": "", "has_portrait": False}


def test_looks_like_image_accepts_supported_magic_bytes() -> None:
    png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
    jpeg = b"\xff\xd8\xff\xe0\x00\x10JFIF"
    gif = b"GIF89a\x01\x00\x01\x00"
    webp = b"RIFF\x18\x00\x00\x00WEBP"

    assert profile.looks_like_image(png, "image/png") is True
    assert profile.detect_image_mime(png) == "image/png"
    assert profile.looks_like_image(jpeg, "image/jpeg") is True
    assert profile.detect_image_mime(jpeg) == "image/jpeg"
    assert profile.looks_like_image(gif) is True
    assert profile.detect_image_mime(gif) == "image/gif"
    assert profile.looks_like_image(webp) is True
    assert profile.detect_image_mime(webp) == "image/webp"


def test_looks_like_image_rejects_html_json_empty_and_oversized() -> None:
    assert profile.looks_like_image(b"") is False
    assert profile.looks_like_image(b"<!DOCTYPE html><html>login</html>", "image/png") is False
    assert profile.looks_like_image(b'{"result":1,"msg":"error"}') is False
    oversized = b"\x89PNG\r\n\x1a\n" + b"0" * profile.MAX_AVATAR_BYTES
    assert profile.looks_like_image(oversized) is False


def main() -> None:
    for check in (
        test_parse_home_profile_no_portrait_unicode_escape,
        test_parse_home_profile_with_portrait,
        test_parse_home_profile_handles_null_and_missing,
        test_looks_like_image_accepts_supported_magic_bytes,
        test_looks_like_image_rejects_html_json_empty_and_oversized,
    ):
        check()
    print("OK: mobile_profile_page 5 checks passed")


if __name__ == "__main__":
    main()
