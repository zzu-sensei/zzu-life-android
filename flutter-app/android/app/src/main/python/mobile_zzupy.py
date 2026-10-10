"""Small Android runtime for the ZZU.Py protocols.

This module mirrors the network behavior of ZZU.Py's CAS, EAS and ECard
clients, while returning plain dictionaries so it doesn't need binary data
model packages which aren't published for Android.
"""

from __future__ import annotations

import base64
import http.cookiejar
import json
import re
import time
import urllib.error
import urllib.request
from datetime import date as date_type
from urllib.parse import parse_qs, urlencode, urlparse

import gmalg
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding

import mobile_plan_page


def _message(data: dict, fallback: str) -> str:
    return str(data.get("message") or data.get("msg") or fallback)


def _records(value, depth: int = 0) -> list:
    if depth > 6:
        return []
    if isinstance(value, list):
        return value
    if not isinstance(value, dict):
        return []
    for key in ("data", "records", "rows", "content", "list", "items"):
        if key in value:
            found = _records(value[key], depth + 1)
            if found or isinstance(value[key], list):
                return found
    return []


class HttpResponse:
    def __init__(self, response):
        self.status_code = response.getcode()
        self.url = response.geturl()
        self.headers = response.headers
        self.content = response.read()
        self.text = self.content.decode("utf-8", errors="replace")

    def json(self):
        return json.loads(self.text)

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"学校服务器返回 HTTP {self.status_code}")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class HttpClient:
    def __init__(self, timeout: int = 25):
        self.timeout = timeout
        self.cookies = http.cookiejar.CookieJar()

    def _open(self, request, follow_redirects: bool):
        handlers = [urllib.request.HTTPCookieProcessor(self.cookies)]
        if not follow_redirects:
            handlers.append(_NoRedirect())
        opener = urllib.request.build_opener(*handlers)
        try:
            return HttpResponse(opener.open(request, timeout=self.timeout))
        except urllib.error.HTTPError as error:
            # A disabled redirect handler surfaces 30x as HTTPError; preserve headers.
            if 300 <= error.code < 400:
                return HttpResponse(error)
            raise RuntimeError(f"学校服务器返回 HTTP {error.code}") from error
        except urllib.error.URLError as error:
            raise RuntimeError(f"无法连接学校服务器：{error.reason}") from error

    def get(self, url: str, *, headers=None, params=None, follow_redirects=True):
        if params:
            url += ("&" if "?" in url else "?") + urlencode(params)
        request = urllib.request.Request(url, headers=headers or {}, method="GET")
        return self._open(request, follow_redirects)

    def post(self, url: str, *, headers=None, params=None, json=None):
        if params:
            url += ("&" if "?" in url else "?") + urlencode(params)
        actual_headers = dict(headers or {})
        body = None
        if json is not None:
            body = globals()["json"].dumps(json, ensure_ascii=False).encode()
            actual_headers["Content-Type"] = "application/json; charset=utf-8"
        request = urllib.request.Request(url, data=body, headers=actual_headers, method="POST")
        return self._open(request, True)

    def close(self):
        return None


class MobileCASClient:
    APP_VERSION = "SWSuperApp/1.1.1"
    PUBLIC_KEY_URL = "https://cas.s.zzu.edu.cn/token/jwt/publicKey"
    LOGIN_URL = "https://cas.s.zzu.edu.cn/token/password/passwordLogin"
    MFA_DETECT_URL = "https://cas.s.zzu.edu.cn/token/mfa/detect"
    MFA_INIT_URL = "https://cas.s.zzu.edu.cn/token/mfa/initByType/securephone"
    MFA_ATTEST_URL = "https://cas.s.zzu.edu.cn/attest/api/guard"

    def __init__(self, account: str, password: str):
        self.account = account
        self.password = password
        self.device_id = "ZZU Life Android"
        self.user_token: str | None = None
        self.refresh_token: str | None = None
        self.client = HttpClient(timeout=20)
        self.public_key = None
        self.logged_in = False
        self.mfa = self.MFA(self)

    def set_device(self, value: str):
        self.device_id = value

    def set_token(self, user_token: str, refresh_token: str):
        self.user_token = user_token
        self.refresh_token = refresh_token

    def _key(self):
        if self.public_key is None:
            response = self.client.get(
                self.PUBLIC_KEY_URL, headers={"User-Agent": "okhttp/3.12.1"}
            )
            response.raise_for_status()
            self.public_key = serialization.load_pem_public_key(response.content)
        return self.public_key

    def _encrypt(self, value: str) -> str:
        encrypted = self._key().encrypt(value.encode(), padding.PKCS1v15())
        return "__RSA__" + base64.b64encode(encrypted).decode()

    def login(self):
        if self.user_token and self.refresh_token:
            try:
                body = self.user_token.split(".")[1]
                body += "=" * (-len(body) % 4)
                payload = json.loads(base64.urlsafe_b64decode(body))
                if float(payload.get("exp", 0)) <= time.time() + 60:
                    raise RuntimeError("登录令牌已过期，请重新登录。")
            except (ValueError, KeyError, IndexError, json.JSONDecodeError):
                raise RuntimeError("登录令牌格式无效，请重新登录。")
            self.logged_in = True
            return
        if self.mfa.required and not self.mfa.verified:
            raise RuntimeError("需要先完成短信验证。")
        response = self.client.post(
            self.LOGIN_URL,
            params={
                "username": self._encrypt(self.account),
                "password": self._encrypt(self.password),
                "appId": "com.supwisdom.zzu",
                "osType": "android",
                "geo": "",
                "deviceId": self.device_id,
                "clientId": "",
                "mfaState": self.mfa.state,
            },
            headers={"User-Agent": f"{self.APP_VERSION}()"},
        )
        response.raise_for_status()
        data = response.json()
        if data.get("code") != 0:
            raise RuntimeError("登录失败：" + _message(data, "未知错误"))
        self.user_token = data["data"]["idToken"]
        self.refresh_token = data["data"]["refreshToken"]
        self.logged_in = True

    def close(self):
        self.client.close()

    class MFA:
        def __init__(self, cas: "MobileCASClient"):
            self.cas = cas
            self.state = ""
            self.gid = ""
            self.attest_url = ""
            self.required = False
            self.verified = False

        @property
        def headers(self):
            return {"User-Agent": f"{self.cas.APP_VERSION}()"}

        def is_required(self) -> bool:
            response = self.cas.client.post(
                self.cas.MFA_DETECT_URL,
                params={
                    "username": self.cas._encrypt(self.cas.account),
                    "password": self.cas._encrypt(self.cas.password),
                    "deviceId": self.cas.device_id,
                },
                headers=self.headers,
            )
            response.raise_for_status()
            data = response.json()
            if data.get("code") != 0:
                raise RuntimeError("MFA 检测失败：" + _message(data, "未知错误"))
            detail = data["data"]
            self.state = detail["state"]
            self.required = bool(detail["need"])
            self.secure_phone = bool(detail.get("mfaTypeSecurePhone", False))
            return self.required

        def send_sms(self):
            if not self.secure_phone:
                raise RuntimeError("当前账号不支持手机号短信验证。")
            response = self.cas.client.get(
                self.cas.MFA_INIT_URL,
                params={"state": self.state},
                headers=self.headers,
            )
            response.raise_for_status()
            data = response.json()
            if data.get("code") != 0:
                raise RuntimeError("短信验证初始化失败：" + _message(data, "未知错误"))
            detail = data["data"]
            self.gid = detail["gid"]
            self.attest_url = detail.get("attestServerUrl") or self.cas.MFA_ATTEST_URL
            response = self.cas.client.post(
                self.attest_url.rstrip("/") + "/api/guard/securephone/send",
                json={"gid": self.gid},
                headers=self.headers,
            )
            response.raise_for_status()
            data = response.json()
            if data.get("code") != 0:
                raise RuntimeError("验证码发送失败：" + _message(data, "未知错误"))

        def verify_sms(self, code: str):
            response = self.cas.client.post(
                self.attest_url.rstrip("/") + "/api/guard/securephone/valid",
                json={"gid": self.gid, "code": code},
                headers=self.headers,
            )
            response.raise_for_status()
            data = response.json()
            if data.get("code") != 0 or data.get("data", {}).get("status") != 2:
                raise RuntimeError("短信验证码校验失败。")
            self.verified = True


class MobileEASClient:
    USER_INFO = "https://jwxt.zzu.edu.cn/eams-door/api/v1/portal/home/user-info"
    COURSE = "https://jwxt.zzu.edu.cn/eams-micro-server/api/v1/lesson/student/course-table"
    GRADES = "https://jwxt.zzu.edu.cn/eams-micro-server/api/v1/grade/student/grades"
    CURRENT = "https://jwxt.zzu.edu.cn/eams-micro-server/api/v1/semester/current-semester"
    SEMESTERS = "https://jwxt.zzu.edu.cn/eams-door/api/v1/calendar/get-all-semesters"
    WEEK = "https://info.s.zzu.edu.cn/portal-api/v1/calendar/share/schedule/getWeekOfTeaching"

    def __init__(self, cas: MobileCASClient):
        self.token = cas.user_token
        self.client = HttpClient(timeout=25)
        self.current_semester: dict | None = None

    @property
    def headers(self):
        return {"Authorization": self.token}

    def login(self):
        response = self.client.get(self.USER_INFO, headers=self.headers)
        response.raise_for_status()
        data = response.json()
        if data.get("result") != 0:
            raise RuntimeError(_message(data, "教务登录失败"))
        response = self.client.get(self.CURRENT, headers=self.headers)
        response.raise_for_status()
        data = response.json()
        if data.get("result") != 0:
            raise RuntimeError(_message(data, "无法读取当前学期"))
        self.current_semester = data["data"]

    def get_grades(self) -> list[dict]:
        response = self.client.get(self.GRADES, headers=self.headers)
        response.raise_for_status()
        data = response.json()
        if isinstance(data, dict) and data.get("result", 0) != 0:
            raise RuntimeError(_message(data, "成绩查询失败"))
        return _records(data)

    def get_semesters(self) -> list[dict]:
        response = self.client.get(self.SEMESTERS, headers=self.headers)
        response.raise_for_status()
        data = response.json()
        if data.get("result") != 0:
            raise RuntimeError(_message(data, "学期查询失败"))
        return _records(data)

    def get_week_index(self, iso_date: str) -> int | None:
        response = self.client.get(
            self.WEEK, headers={"X-Id-Token": self.token}, params={"today": iso_date}
        )
        response.raise_for_status()
        data = response.json()
        value = data.get("data", {}).get("data", {}).get("date", [""])[0]
        return int(value) if str(value).strip() else None

    def resolve_current_week(self, iso_date: str) -> int:
        """Resolve the current teaching week from semester dates first.

        The portal's shared-calendar endpoint occasionally returns a stale week.
        The EAS current-semester response is authoritative for the term boundary,
        so calculate from its start date and only use the portal as a fallback.
        """
        semester = self.current_semester or {}
        try:
            start = date_type.fromisoformat(str(semester["startDate"])[:10])
            today = date_type.fromisoformat(iso_date)
            calculated = (today - start).days // 7 + 1
            week_indices = semester.get("weekIndices") or []
            maximum = max((int(value) for value in week_indices), default=0)
            if calculated >= 1 and (maximum == 0 or calculated <= maximum):
                return calculated
        except (KeyError, TypeError, ValueError):
            pass
        return self.get_week_index(iso_date) or 1

    def get_teaching_week(self, week: int | None, semester_id: int | None) -> list[dict]:
        if semester_id is None:
            semester_id = int(self.current_semester["id"])
        response = self.client.get(f"{self.COURSE}/{semester_id}", headers=self.headers)
        response.raise_for_status()
        data = response.json()
        if data.get("result") != 0:
            raise RuntimeError(_message(data, "课表查询失败"))
        lessons: list[dict] = []
        for datum in _records(data):
            course = datum.get("course") or {}
            schedules: list[dict] = []
            seen_schedules: set[tuple] = set()

            def collect_schedules(node, key_hint: str = ""):
                if isinstance(node, dict):
                    looks_like_schedule = (
                        any(
                            key in node
                            for key in ("date", "originalDate", "weekIndex", "weekIndexes")
                        )
                        and any(key in node for key in ("startUnit", "startTime", "weekday"))
                    )
                    if looks_like_schedule:
                        marker = (
                            node.get("id"), node.get("date"), node.get("originalDate"),
                            node.get("weekday"), node.get("startUnit"), node.get("endUnit"),
                            node.get("startTime"), node.get("endTime"),
                        )
                        if marker not in seen_schedules:
                            seen_schedules.add(marker)
                            schedules.append(node)
                    for key, value in node.items():
                        if isinstance(value, (dict, list)) and (
                            "schedule" in key.lower()
                            or "lesson" in key.lower()
                            or key in {"children", "items", "data"}
                        ):
                            collect_schedules(value, key)
                elif isinstance(node, list):
                    for item in node:
                        collect_schedules(item, key_hint)

            collect_schedules(datum.get("schedules") or [], "schedules")
            for key, value in datum.items():
                if key != "schedules" and isinstance(value, (dict, list)) and (
                    "schedule" in key.lower() or "lesson" in key.lower()
                ):
                    collect_schedules(value, key)

            for schedule in schedules:
                raw_week = schedule.get("weekIndex")
                if week is None:
                    matches_week = True
                elif raw_week in (None, "", 0, "0"):
                    week_indexes = schedule.get("weekIndexes") or []
                    if week_indexes:
                        matches_week = week in {
                            int(value) for value in week_indexes if str(value).strip()
                        }
                    else:
                        matches_week = False
                        try:
                            semester_start = date_type.fromisoformat(
                                str((self.current_semester or {})["startDate"])[:10]
                            )
                            schedule_date = date_type.fromisoformat(
                                str(schedule.get("date") or schedule.get("originalDate"))[:10]
                            )
                            matches_week = (schedule_date - semester_start).days // 7 + 1 == week
                        except (KeyError, TypeError, ValueError):
                            pass
                else:
                    try:
                        matches_week = int(raw_week) == week
                    except (TypeError, ValueError):
                        matches_week = False
                if matches_week:
                    lessons.append({"course": course, "schedule": schedule})
        return lessons

    def close(self):
        self.client.close()


class MobileWebEASClient:
    # This endpoint performs the CAS service-ticket exchange and creates the
    # /student SESSION cookie. Visiting the manager portal does not authenticate
    # the student application, even when the App userToken is valid.
    TOKEN_LOGIN = "https://cas.s.zzu.edu.cn/cas/t/login"
    STUDENT_SSO = "https://jwxt.zzu.edu.cn/student/sso/login"
    SHEET_BASE = "https://jwxt.zzu.edu.cn/student/for-std/grade/sheet"
    #: 培养计划完成情况预览。数据内联在页面里，不是单独的 XHR 接口。
    PROGRAM_PREVIEW = (
        "https://jwxt.zzu.edu.cn/student/for-std/program-completion-preview"
    )
    USER_AGENT = (
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
        "Chrome/131.0 Mobile Safari/537.36"
    )
    STUDENT_PATTERNS = (
        re.compile(r"/semester-index/(\d+)"),
        re.compile(r"\bstudentId\s*=\s*['\"]?(\d+)"),
    )

    def __init__(self, cas: MobileCASClient):
        if not cas.user_token:
            raise RuntimeError("登录已失效，请重新登录。")
        self.client = HttpClient(timeout=35)
        self.headers = {
            "User-Agent": self.USER_AGENT,
            "Authorization": cas.user_token,
            "X-Id-Token": cas.user_token,
        }
        self.student_id: int | None = None
        cookie = http.cookiejar.Cookie(
            version=0,
            name="userToken",
            value=cas.user_token,
            port=None,
            port_specified=False,
            domain=".zzu.edu.cn",
            domain_specified=True,
            domain_initial_dot=True,
            path="/",
            path_specified=True,
            secure=True,
            expires=None,
            discard=True,
            comment=None,
            comment_url=None,
            rest={},
            rfc2109=False,
        )
        self.client.cookies.set_cookie(cookie)

    @staticmethod
    def _looks_like_login(response: HttpResponse) -> bool:
        content_type = str(response.headers.get("content-type", "")).lower()
        if "application/pdf" in content_type:
            return False
        body = response.text[:4000]
        lowered = body.lower()
        return (
            "/login" in str(response.url).lower()
            or "统一身份认证" in body
            or "passwordlogin" in lowered
        )

    @classmethod
    def _student_id(cls, *values: str) -> int | None:
        for value in values:
            for pattern in cls.STUDENT_PATTERNS:
                match = pattern.search(value)
                if match:
                    return int(match.group(1))
        return None

    def login(self):
        sso = self.client.get(
            self.TOKEN_LOGIN,
            headers=self.headers,
            params={"service": self.STUDENT_SSO},
        )
        sso.raise_for_status()
        if self._looks_like_login(sso):
            raise RuntimeError("教务网页登录失败，统一认证会话未被接受。")
        sheet = self.client.get(self.SHEET_BASE, headers=self.headers)
        sheet.raise_for_status()
        if self._looks_like_login(sheet):
            raise RuntimeError("教务网页会话已失效，请重新登录。")
        self.student_id = self._student_id(
            str(sheet.url), sheet.text, str(sso.url), sso.text
        )
        if self.student_id is None:
            raise RuntimeError("未能解析教务系统学生 ID。")

    def _get(self, path: str, params=None) -> HttpResponse:
        response = self.client.get(
            f"{self.SHEET_BASE}/{path.lstrip('/')}",
            headers=self.headers,
            params=params,
        )
        response.raise_for_status()
        if self._looks_like_login(response):
            raise RuntimeError("教务网页会话已失效，请重新登录。")
        return response

    def get_program_plan(self, student_id: int | None = None) -> dict:
        """获取培养计划（学分要求、各模块完成度、未通过/在修课程）。

        计划数据是**服务端渲染**在该页面里的，以 JavaScript 对象字面量内联在
        ``<script>var model = {...}</script>`` 中（不是 JSON，也不是另外的
        XHR 接口），因此这里取页面后用 ``mobile_plan_page`` 解析。

        Args:
            student_id: 教务网页端的学生内部 ID。不传时先访问一次基础地址，
                从重定向后的 URL 里解析。
        """
        target = student_id or self.student_id
        if target is None:
            # 基础地址通常会重定向到 .../info/{studentId}，从中解析出 ID。
            probe = self.client.get(self.PROGRAM_PREVIEW, headers=self.headers)
            probe.raise_for_status()
            if self._looks_like_login(probe):
                raise RuntimeError("教务网页会话已失效，请重新登录。")
            target = self._student_id(str(probe.url), probe.text)
            if target is None:
                raise RuntimeError("未能确定培养计划页面的学生 ID。")

        url = f"{self.PROGRAM_PREVIEW}/info/{target}"
        response = self.client.get(url, headers=self.headers)
        response.raise_for_status()
        if self._looks_like_login(response):
            raise RuntimeError("教务网页会话已失效，请重新登录。")

        plan = mobile_plan_page.parse_plan_page(response.text)
        return mobile_plan_page.summarize_plan(plan)

    def get_transcript(self) -> tuple[bytes, str]:
        response = self._get(
            "print-grade-zh",
            params={"studentId": self.student_id, "printType": "学生成绩总表"},
        )
        return response.content, str(
            response.headers.get("content-type", "text/html; charset=utf-8")
        )

    def get_grade_rank_report(self) -> bytes:
        response = self._get(
            "pdf-grade-rank-zh", params={"studentId": self.student_id}
        )
        content_type = str(response.headers.get("content-type", "")).lower()
        if not response.content.startswith(b"%PDF") and "application/pdf" not in content_type:
            raise RuntimeError("教务系统暂未返回可用的排名 PDF。")
        return response.content

    def close(self):
        self.client.close()


class MobileECardClient:
    TID = "https://ecard.v.zzu.edu.cn/server/auth/host/open"
    TOKEN = "https://ecard.v.zzu.edu.cn/server/auth/getToken"
    CONFIG = "https://ecard.v.zzu.edu.cn/server/utilities/config"
    LOCATION = "https://ecard.v.zzu.edu.cn/server/utilities/location"
    ACCOUNT = "https://ecard.v.zzu.edu.cn/server/utilities/account"
    ENCRYPT = "https://ecard.v.zzu.edu.cn/server/auth/getEncrypt"
    PAY = "https://ecard.v.zzu.edu.cn/server/utilities/pay"
    SM4_KEY = bytes.fromhex("773638372d392b33435f48266a655f35")

    def __init__(self, cas: MobileCASClient):
        self.user_token = cas.user_token
        self.client = HttpClient(timeout=25)
        self.access_token = ""

    def login(self):
        response = self.client.get(
            self.TID,
            params={"host": "11", "org": "2", "token": self.user_token},
            follow_redirects=False,
        )
        tid = parse_qs(urlparse(response.headers.get("location", "")).query).get("tid", [""])[0]
        if not tid:
            raise RuntimeError("校园卡服务未返回登录标识。")
        response = self.client.post(self.TOKEN, json={"tid": tid})
        response.raise_for_status()
        self.access_token = response.json().get("resultData", {}).get("accessToken", "")
        if not self.access_token:
            raise RuntimeError("校园卡服务未返回访问令牌。")

    @property
    def headers(self):
        return {"Authorization": self.access_token}

    def get_default_room(self) -> str:
        response = self.client.post(
            self.CONFIG, headers=self.headers, json={"utilityType": "electric"}
        )
        response.raise_for_status()
        return str(response.json()["resultData"]["location"]["room"])

    def get_room_dict(self, room_id: str) -> dict[str, str]:
        count = room_id.count("-")
        if not room_id:
            area = building = level = ""
            location_type = "bigArea"
        elif count == 0:
            area, building, level, location_type = room_id, "", "", "building"
        elif count == 1:
            area, building = room_id.split("-")
            level, location_type = "", "unit"
        elif count == 3:
            area, building = room_id.split("--")[0].split("-")
            level, location_type = room_id.split("--")[1], "room"
        else:
            raise RuntimeError("房间 ID 格式不正确：" + room_id)
        response = self.client.post(
            self.LOCATION,
            headers=self.headers,
            json={
                "utilityType": "electric", "locationType": location_type,
                "bigArea": "", "area": area, "building": building,
                "unit": "", "level": level, "room": "", "subArea": "",
            },
        )
        response.raise_for_status()
        items = response.json().get("resultData", {}).get("locationList", [])
        return {str(item["id"]): str(item["name"]) for item in items}

    def get_remaining_energy(self, room: str) -> float:
        area, building = room.split("--")[0].split("-")
        level = room.split("--")[1].split("-")[0]
        response = self.client.post(
            self.ACCOUNT,
            headers=self.headers,
            json={
                "utilityType": "electric", "bigArea": "", "area": area,
                "building": building, "unit": "", "level": level,
                "room": room, "subArea": "",
            },
        )
        response.raise_for_status()
        templates = response.json().get("resultData", {}).get("templateList", [])
        for item in templates:
            if item.get("code") == "quantity" and item.get("value") is not None:
                return float(item["value"])
        raise RuntimeError("学校服务器未返回该电表的剩余电量。")

    @staticmethod
    def _sm4_decrypt(ciphertext: bytes, key: bytes) -> str:
        if not ciphertext or len(ciphertext) % 16:
            raise RuntimeError("校园卡加密参数长度无效。")
        sm4 = gmalg.SM4(key)
        padded = b"".join(
            sm4.decrypt(ciphertext[index : index + 16])
            for index in range(0, len(ciphertext), 16)
        )
        padding_length = padded[-1]
        if not 1 <= padding_length <= 16 or padded[-padding_length:] != bytes(
            [padding_length]
        ) * padding_length:
            raise RuntimeError("校园卡加密参数填充无效。")
        return padded[:-padding_length].decode()

    def recharge_energy(self, payment_password: str, amt: int, room: str) -> str:
        if amt <= 0:
            raise RuntimeError("充值金额必须为正整数。")
        if not payment_password:
            raise RuntimeError("请输入校园卡支付密码。")
        try:
            area, building = room.split("--", 1)[0].split("-", 1)
            level = room.split("--", 1)[1].split("-", 1)[0]
        except (IndexError, ValueError) as error:
            raise RuntimeError("电表 ID 格式不正确，已阻止充值。") from error

        response = self.client.post(self.ENCRYPT, headers=self.headers)
        response.raise_for_status()
        envelope = response.json().get("resultData") or {}
        pay_id = envelope.get("id")
        encrypted_public_key = envelope.get("publicKey")
        if not pay_id or not encrypted_public_key:
            raise RuntimeError("校园卡服务未返回支付加密参数。")
        try:
            public_key = self._sm4_decrypt(
                base64.b64decode(encrypted_public_key), self.SM4_KEY
            )
            payload = {
                "utilityType": "electric",
                "payCode": "06",
                "password": payment_password,
                "amt": str(amt),
                "timestamp": int(round(time.time() * 1000)),
                "bigArea": "",
                "area": area,
                "building": building,
                "unit": "",
                "level": level,
                "room": room,
                "subArea": "",
                "customfield": {},
            }
            plaintext = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
            encrypted = gmalg.SM2(pk=bytes.fromhex(public_key)).encrypt(
                plaintext.encode()
            )
        except (ValueError, TypeError, UnicodeError) as error:
            raise RuntimeError("支付参数加密失败，已阻止充值。") from error
        response = self.client.post(
            self.PAY,
            headers=self.headers,
            json={"id": pay_id, "params": encrypted.hex()[2:]},
        )
        response.raise_for_status()
        result = response.json()
        if result.get("success") is False:
            raise RuntimeError(_message(result, "充值失败"))
        return _message(result, "充值请求已提交")

    def close(self):
        self.client.close()


def meter_level_id(default_room_id: str, meter_type: str) -> str:
    codes = {"照明": "41", "空调": "42"}
    prefix, suffix = default_room_id.split("--", 1)
    source = suffix.split("-", 1)[0]
    return f"{prefix}--{codes[meter_type].zfill(len(source))}"


def full_room_id(level_id: str, value) -> str:
    value = str(value).strip()
    return value if value.startswith(level_id + "-") else level_id + "-" + value


def full_level_id(building_id: str, value) -> str:
    value = str(value).strip()
    return value if value.startswith(building_id + "--") else building_id + "--" + value


def room_key(name) -> str:
    groups = re.findall(r"\d+", str(name))
    if groups:
        return groups[-1].lstrip("0") or "0"
    value = str(name)
    for token in ("照明", "空调", "电表", "房间", "宿舍", "寝室"):
        value = value.replace(token, "")
    return "".join(c.casefold() for c in value if c.isalnum())


def keys_match(source: str, target: str) -> bool:
    return source == target or (
        source.isdigit() and target.isdigit() and len(source) >= 3 and target.endswith(source)
    )


def get_meter_energy(ecard: MobileECardClient, default_room: str, meter_type: str):
    source_level, separator, _ = default_room.rpartition("-")
    if not separator or "--" not in source_level:
        raise RuntimeError("默认寝室 ID 格式不完整。")
    source_rooms = {
        full_room_id(source_level, rid): name
        for rid, name in ecard.get_room_dict(source_level).items()
    }
    source_name = source_rooms.get(default_room)
    if source_name is None:
        raise RuntimeError("默认寝室不在服务器房间目录中。")
    preferred = meter_level_id(default_room, meter_type)
    if preferred == source_level:
        return default_room, ecard.get_remaining_energy(default_room)
    building = source_level.split("--", 1)[0]
    levels = {
        full_level_id(building, lid): name
        for lid, name in ecard.get_room_dict(building).items()
    }
    levels.setdefault(preferred, "按 41/42 规则推定")
    ordered = sorted(
        levels.items(),
        key=lambda item: (0 if meter_type in item[1] else 1, 0 if item[0] == preferred else 1, item[0]),
    )
    source_key = room_key(source_name)
    matches = []
    for level_id, level_name in ordered:
        if level_id == source_level:
            continue
        for rid, name in ecard.get_room_dict(level_id).items():
            target_key = room_key(name)
            if keys_match(source_key, target_key):
                matches.append((full_room_id(level_id, rid), level_name, target_key))
    exact = [(rid, name) for rid, name, key in matches if key == source_key]
    candidates = exact or [(rid, name) for rid, name, _key in matches]
    typed = [item for item in candidates if meter_type in item[1]]
    if typed:
        candidates = typed
    if not candidates:
        raise RuntimeError(f"没有找到与“{source_name}”对应的{meter_type}电表。")
    if len(candidates) > 1:
        raise RuntimeError(f"匹配到多个{meter_type}候选，无法安全确定。")
    meter_id = candidates[0][0]
    return meter_id, ecard.get_remaining_energy(meter_id)


def discover_meter_energy(ecard: MobileECardClient, default_room: str) -> list[dict]:
    """Discover valid meters without assuming area or level IDs such as 99/41/42."""
    results: list[dict] = []
    seen: set[str] = set()

    def classify(label: str, fallback: str = "电表") -> str:
        normalized = str(label)
        if any(token in normalized for token in ("空调", "冷气", "制冷")):
            return "空调电表"
        if any(token in normalized for token in ("照明", "灯", "普通用电")):
            return "照明电表"
        return fallback

    def add_meter(meter_id: str, label: str, fallback: str = "电表") -> None:
        if not meter_id or meter_id in seen:
            return
        try:
            remaining = ecard.get_remaining_energy(meter_id)
        except BaseException:
            return
        seen.add(meter_id)
        results.append(
            {
                "label": classify(label, fallback),
                "source_label": str(label),
                "meter_id": meter_id,
                "remaining": float(remaining),
            }
        )

    # The documented API explicitly supports querying the configured room directly.
    add_meter(default_room, "默认房间", "寝室电表")

    source_level, separator, room_suffix = default_room.rpartition("-")
    if not separator or "--" not in source_level:
        return results
    try:
        source_rooms = {
            full_room_id(source_level, room_id): str(room_name)
            for room_id, room_name in ecard.get_room_dict(source_level).items()
        }
    except BaseException:
        source_rooms = {}
    source_name = source_rooms.get(default_room, room_suffix)
    source_key = room_key(source_name)
    building_id = source_level.split("--", 1)[0]
    try:
        levels = {
            full_level_id(building_id, level_id): str(level_name)
            for level_id, level_name in ecard.get_room_dict(building_id).items()
        }
    except BaseException:
        levels = {}

    for level_id, level_name in levels.items():
        if level_id == source_level:
            continue
        try:
            rooms = ecard.get_room_dict(level_id)
        except BaseException:
            continue
        for room_id, room_name in rooms.items():
            if keys_match(source_key, room_key(room_name)):
                add_meter(full_room_id(level_id, room_id), level_name)
    return results
