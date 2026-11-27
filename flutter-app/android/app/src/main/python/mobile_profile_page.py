"""教务首页 / 门户个人信息与个人头像解析（Android 端，不含学籍证件照）。

仅依赖标准库与 ``mobile_plan_page``，刻意不引入 ``gmalg`` / ``loguru``，
便于通过 ``scripts/test_mobile_profile.py`` 进行纯离线回归验证。
"""

from __future__ import annotations

import base64
import re
from typing import Any

import mobile_plan_page

MAX_AVATAR_BYTES = 10 * 1024 * 1024

_HAS_PORTRAIT_RE = re.compile(r"\bhasPortrait\s*=\s*(true|false)\b")
_PERSON_NAME_RE = re.compile(
    r"""\bpersonName\s*=\s*('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|null|undefined)"""
)
_DEFAULT_AVATAR_RE = re.compile(
    r"""\bdefaultAvatar\s*=\s*('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")"""
)
_DATA_URI_RE = re.compile(r"^data:image/[A-Za-z0-9.+-]+;base64,(.+)$", re.I | re.S)

_NAME_KEYS = ("name", "userName", "realName", "studentName", "nickName", "personName")
_AVATAR_KEYS = (
    "imageUrl",
    "avatar",
    "avatarUrl",
    "portrait",
    "portraitUrl",
    "headImg",
    "headImgUrl",
    "photoUrl",
    "headPortrait",
)


def decode_data_uri_image(value: str) -> bytes:
    """解码 ``data:image/...;base64,...``；无效或非受支持图片返回空字节串。"""
    text = (value or "").strip()
    match = _DATA_URI_RE.match(text)
    if not match:
        return b""
    raw_b64 = re.sub(r"\s+", "", match.group(1))
    try:
        decoded = base64.b64decode(raw_b64, validate=False)
    except (ValueError, TypeError):
        return b""
    return decoded if looks_like_image(decoded) else b""


def parse_home_profile(html: str) -> dict:
    """解析教务系统 ``/student/home`` 中的姓名、个人头像标记及默认占位图字节。"""
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

    default_avatar_bytes = b""
    default_match = _DEFAULT_AVATAR_RE.search(source)
    if default_match:
        try:
            parsed_default = mobile_plan_page.parse_js_literal(default_match.group(1))
            if isinstance(parsed_default, str):
                default_avatar_bytes = decode_data_uri_image(parsed_default)
        except mobile_plan_page.JsLiteralError:
            default_avatar_bytes = b""

    return {
        "name": name,
        "has_portrait": has_portrait,
        "default_avatar_bytes": default_avatar_bytes,
    }


def extract_profile_from_json(payload: Any) -> dict:
    """从门户或教务接口 JSON 中提取姓名与头像引用（URL / 相对路径 / data URI）。"""
    name = ""
    avatar_ref = ""

    def visit(node: Any, depth: int = 0) -> None:
        nonlocal name, avatar_ref
        if depth > 5 or (name and avatar_ref):
            return
        if isinstance(node, dict):
            if not name:
                for key in _NAME_KEYS:
                    val = node.get(key)
                    if isinstance(val, str) and val.strip():
                        name = val.strip()
                        break
            if not avatar_ref:
                for key in _AVATAR_KEYS:
                    val = node.get(key)
                    if isinstance(val, str) and val.strip():
                        avatar_ref = val.strip()
                        break
            for key in ("user", "data", "userInfo", "account"):
                child = node.get(key)
                if isinstance(child, (dict, list)):
                    visit(child, depth + 1)
            for child in node.values():
                if isinstance(child, (dict, list)):
                    visit(child, depth + 1)
        elif isinstance(node, list):
            for item in node:
                visit(item, depth + 1)

    visit(payload)
    return {"name": name, "avatar_ref": avatar_ref}


def detect_image_mime(data: bytes) -> str:
    """根据文件魔数识别常见图片格式（含 GIF/WebP 动图），未知或超大内容返回空字符串。"""
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
    """判断响应体是否为受支持的图片二进制，防止误把 HTML/SVG/JSON 当作头像。"""
    del content_type
    return bool(detect_image_mime(data))
