"""教务首页个人信息与个人头像解析（Android 端，不含学籍证件照）。

仅依赖标准库与 ``mobile_plan_page``，刻意不引入 ``gmalg`` / ``loguru``，
便于通过 ``scripts/test_mobile_profile.py`` 进行纯离线回归验证。
"""

from __future__ import annotations

import re

import mobile_plan_page

MAX_AVATAR_BYTES = 5 * 1024 * 1024

_HAS_PORTRAIT_RE = re.compile(r"\bhasPortrait\s*=\s*(true|false)\b")
_PERSON_NAME_RE = re.compile(
    r"""\bpersonName\s*=\s*('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|null|undefined)"""
)


def parse_home_profile(html: str) -> dict:
    """解析教务系统 ``/student/home`` 中的姓名与是否上传过个人头像。"""
    source = html or ""
    portrait_match = _HAS_PORTRAIT_RE.search(source)
    has_portrait = bool(portrait_match and portrait_match.group(1) == "true")

    name = ""
    name_match = _PERSON_NAME_RE.search(source)
    if name_match:
        literal = name_match.group(1)
        try:
            parsed = mobile_plan_page.parse_js_literal(literal)
            if isinstance(parsed, str):
                name = parsed.strip()
        except mobile_plan_page.JsLiteralError:
            name = ""

    return {
        "name": name,
        "has_portrait": has_portrait,
    }


def detect_image_mime(data: bytes) -> str:
    """根据文件魔数识别常见图片格式，未知或超大内容返回空字符串。"""
    if not data or len(data) > MAX_AVATAR_BYTES:
        return ""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if data.startswith(b"BM"):
        return "image/bmp"
    return ""


def looks_like_image(data: bytes, content_type: str = "") -> bool:
    """判断响应体是否为受支持的图片二进制，防止误把 HTML/JSON 当作头像。"""
    del content_type
    return bool(detect_image_mime(data))
