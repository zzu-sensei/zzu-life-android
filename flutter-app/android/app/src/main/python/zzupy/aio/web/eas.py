"""异步本科教务网页端客户端。"""

from __future__ import annotations

import json
import re
from typing import Final

import httpx2

from zzupy.aio.app.interfaces import ICASClient
from zzupy.exception import (
    LoginError,
    NetworkError,
    NotLoggedInError,
    OperationError,
    ParsingError,
)
from zzupy.logging import build_http_event_hooks, logger
from zzupy.utils import require_auth


class StudentWebEASClient:
    """异步访问官方总成绩单、最好成绩和成绩排名报告。"""

    SECONDARY_PORTAL_URL: Final = (
        "https://jwxt.zzu.edu.cn/manager/secondary-portal"
    )
    SHEET_BASE_URL: Final = (
        "https://jwxt.zzu.edu.cn/student/for-std/grade/sheet"
    )
    _STUDENT_ID_PATTERNS: Final = (
        re.compile(r"/semester-index/(\d+)"),
        re.compile(r"\bstudentId\s*=\s*['\"]?(\d+)"),
    )

    def __init__(self, cas_client: ICASClient) -> None:
        if not cas_client.logged_in:
            raise NotLoggedInError("CASClient 必须已经登录")
        user_token = cas_client.user_token
        if not user_token:
            raise NotLoggedInError("CASClient 缺少 userToken")

        self._client = httpx2.AsyncClient(
            follow_redirects=True,
            event_hooks=build_http_event_hooks(async_client=True),
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
                    "Chrome/131.0 Mobile Safari/537.36"
                )
            },
        )
        self._client.cookies.set("userToken", user_token, ".zzu.edu.cn", "/")
        self._logged_in = False
        self._student_id: int | None = None

    async def __aenter__(self) -> "StudentWebEASClient":
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        await self.close()

    @property
    def student_id(self) -> int:
        if self._student_id is None:
            raise NotLoggedInError("尚未取得教务网页端学生 ID")
        return self._student_id

    @staticmethod
    def _looks_like_login_page(response: httpx2.Response) -> bool:
        if "application/pdf" in response.headers.get("content-type", "").lower():
            return False
        url = str(response.url).lower()
        body = response.text[:4000].lower()
        return (
            "/login" in url
            or "统一身份认证" in response.text[:4000]
            or "passwordlogin" in body
        )

    @classmethod
    def _extract_student_id(cls, response: httpx2.Response) -> int | None:
        for value in (str(response.url), response.text):
            for pattern in cls._STUDENT_ID_PATTERNS:
                if match := pattern.search(value):
                    return int(match.group(1))
        return None

    async def login(self) -> None:
        try:
            portal = await self._client.get(self.SECONDARY_PORTAL_URL)
            portal.raise_for_status()
            if self._looks_like_login_page(portal):
                raise LoginError("教务网页登录失败，统一认证会话未被接受。")

            sheet = await self._client.get(self.SHEET_BASE_URL)
            sheet.raise_for_status()
            if self._looks_like_login_page(sheet):
                raise LoginError("教务网页会话已失效，请重新登录。")
            student_id = self._extract_student_id(sheet)
            if student_id is None:
                raise ParsingError(
                    "未能从成绩页面解析学生内部 ID，教务页面结构可能已更新。",
                    context={"url": str(sheet.url)},
                )
        except (LoginError, ParsingError):
            raise
        except httpx2.HTTPStatusError as exc:
            raise OperationError.from_http_status(
                exc, "教务网页登录失败", context={"url": self.SECONDARY_PORTAL_URL}
            ) from exc
        except httpx2.RequestError as exc:
            raise NetworkError.from_exception(
                exc,
                "无法连接本科教务网页端。",
                context={"url": self.SECONDARY_PORTAL_URL},
            ) from exc

        self._student_id = student_id
        self._logged_in = True
        logger.info("教务网页端登录成功")

    async def _get(self, path: str, **kwargs) -> httpx2.Response:
        url = f"{self.SHEET_BASE_URL}/{path.lstrip('/')}"
        try:
            response = await self._client.get(url, **kwargs)
            response.raise_for_status()
            if self._looks_like_login_page(response):
                raise LoginError("教务网页会话已失效，请重新登录。")
            return response
        except LoginError:
            raise
        except httpx2.HTTPStatusError as exc:
            raise OperationError.from_http_status(
                exc, "教务网页请求失败", context={"url": url}
            ) from exc
        except httpx2.RequestError as exc:
            raise NetworkError.from_exception(
                exc, "无法连接本科教务网页端。", context={"url": url}
            ) from exc

    @require_auth
    async def get_best_attempt_grade_ids(self) -> list[int]:
        response = await self._get(f"get-not-retake-grade/{self.student_id}")
        try:
            payload = response.json()
            values = payload.get("notRetakeGradeIds", [])
            if not isinstance(values, list):
                raise TypeError("notRetakeGradeIds 不是列表")
            return [int(value) for value in values]
        except (json.JSONDecodeError, TypeError, ValueError, AttributeError) as exc:
            raise ParsingError.from_exception(
                exc,
                "最好成绩响应格式不正确。",
                context={"url": str(response.url)},
            ) from exc

    @require_auth
    async def get_transcript(self) -> tuple[bytes, str]:
        response = await self._get(
            "print-grade-zh",
            params={
                "studentId": self.student_id,
                "printType": "学生成绩总表",
            },
        )
        return response.content, response.headers.get(
            "content-type", "text/html; charset=utf-8"
        )

    @require_auth
    async def get_grade_rank_report(self) -> bytes:
        response = await self._get(
            "pdf-grade-rank-zh", params={"studentId": self.student_id}
        )
        content_type = response.headers.get("content-type", "").lower()
        if (
            not response.content.startswith(b"%PDF")
            and "application/pdf" not in content_type
        ):
            raise OperationError(
                "教务系统暂未返回可用的排名 PDF。",
                context={"url": str(response.url), "content_type": content_type},
            )
        return response.content

    def logout(self) -> None:
        self._client.cookies.clear()
        self._student_id = None
        self._logged_in = False

    async def close(self) -> None:
        if self._logged_in:
            self.logout()
        await self._client.aclose()


__all__ = ["StudentWebEASClient"]
