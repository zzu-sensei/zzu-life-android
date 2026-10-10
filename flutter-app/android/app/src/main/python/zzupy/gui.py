"""基于 Tkinter 的郑州大学生活与教务桌面客户端。"""

from __future__ import annotations

import base64
import ctypes
import json
import os
import queue
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk
from typing import Any, Callable

# 兼容 `python path/to/zzupy/gui.py` 直接运行。正常安装或使用
# `python -m zzupy.gui` 时不修改模块搜索路径。
if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from zzupy.app import CASClient, ECardClient, UndergradEASClient  # noqa: E402
from zzupy.exception import ParsingError, ZZUError  # noqa: E402
from zzupy.web import SelfServiceSystem  # noqa: E402



class _DataBlob(ctypes.Structure):
    """Windows DPAPI 使用的数据缓冲区。"""

    _fields_ = [("size", ctypes.c_ulong), ("data", ctypes.c_void_p)]


def _protect_password(password: str) -> str:
    """使用当前 Windows 用户的 DPAPI 加密密码。"""
    if os.name != "nt":
        raise OSError("记住密码功能仅支持 Windows")
    raw = password.encode("utf-8")
    buffer = ctypes.create_string_buffer(raw)
    input_blob = _DataBlob(len(raw), ctypes.cast(buffer, ctypes.c_void_p))
    output_blob = _DataBlob()
    succeeded = ctypes.windll.crypt32.CryptProtectData(
        ctypes.byref(input_blob),
        ctypes.c_wchar_p("ZZU.Py unified authentication password"),
        None,
        None,
        None,
        1,
        ctypes.byref(output_blob),
    )
    if not succeeded:
        raise ctypes.WinError()
    try:
        encrypted = ctypes.string_at(output_blob.data, output_blob.size)
        return base64.b64encode(encrypted).decode("ascii")
    finally:
        local_free = ctypes.windll.kernel32.LocalFree
        local_free.argtypes = [ctypes.c_void_p]
        local_free.restype = ctypes.c_void_p
        local_free(output_blob.data)


def _unprotect_password(encrypted_password: str) -> str:
    """使用当前 Windows 用户的 DPAPI 解密密码。"""
    if os.name != "nt":
        raise OSError("记住密码功能仅支持 Windows")
    raw = base64.b64decode(encrypted_password, validate=True)
    buffer = ctypes.create_string_buffer(raw)
    input_blob = _DataBlob(len(raw), ctypes.cast(buffer, ctypes.c_void_p))
    output_blob = _DataBlob()
    succeeded = ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(input_blob),
        None,
        None,
        None,
        None,
        1,
        ctypes.byref(output_blob),
    )
    if not succeeded:
        raise ctypes.WinError()
    try:
        decrypted = ctypes.string_at(output_blob.data, output_blob.size)
        return decrypted.decode("utf-8")
    finally:
        local_free = ctypes.windll.kernel32.LocalFree
        local_free.argtypes = [ctypes.c_void_p]
        local_free.restype = ctypes.c_void_p
        local_free(output_blob.data)
def meter_level_id_for_type(default_room_id: str, meter_type: str) -> str:
    """根据默认寝室 ID 得到照明(41)或空调(42)目录 ID。"""
    level_codes = {"照明": "41", "空调": "42"}
    try:
        target_code = level_codes[meter_type]
    except KeyError as exc:
        raise ValueError(f"无法识别电费类型：{meter_type}") from exc
    if "--" not in default_room_id:
        raise ValueError(f"默认寝室 ID 格式不完整：{default_room_id}")
    prefix, suffix = default_room_id.split("--", 1)
    source_code = suffix.split("-", 1)[0]
    if not source_code.isdigit():
        raise ValueError(f"默认寝室 ID 格式不完整：{default_room_id}")
    return f"{prefix}--{target_code.zfill(len(source_code))}"


def full_room_id(level_id: str, room_id: object) -> str:
    """兼容服务器返回的局部或完整房间记录 ID。"""
    room_id = str(room_id).strip()
    prefix = f"{level_id}-"
    return room_id if room_id.startswith(prefix) else f"{prefix}{room_id}"


def full_level_id(building_id: str, level_id: object) -> str:
    """兼容服务器返回的局部或完整电表目录 ID。"""
    level_id = str(level_id).strip()
    prefix = f"{building_id}--"
    return level_id if level_id.startswith(prefix) else f"{prefix}{level_id}"

def room_match_key(name: object) -> str:
    """优先提取末尾房间数字，否则忽略类型文字后匹配名称。"""
    normalized = str(name)
    digit_groups: list[str] = []
    current_digits = ""
    for character in normalized:
        if character.isdigit():
            current_digits += character
        elif current_digits:
            digit_groups.append(current_digits)
            current_digits = ""
    if current_digits:
        digit_groups.append(current_digits)
    if digit_groups:
        return digit_groups[-1].lstrip("0") or "0"

    for token in ("照明", "空调", "电表", "房间", "宿舍", "寝室"):
        normalized = normalized.replace(token, "")
    return "".join(
        character.casefold() for character in normalized if character.isalnum()
    )

def room_keys_match(source_key: str, target_key: str) -> bool:
    """匹配 233 与空调目录中的楼栋前缀编号 8233。"""
    if source_key == target_key:
        return True
    return (
        source_key.isdigit()
        and target_key.isdigit()
        and len(source_key) >= 3
        and target_key.endswith(source_key)
    )

class ZzuGui:
    """郑大生活与教务桌面客户端。"""

    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("郑大生活与教务助手")
        self.root.geometry("1040x720")
        self.root.minsize(900, 620)

        self.cas: CASClient | None = None
        self.ecard: ECardClient | None = None
        self.self_service: SelfServiceSystem | None = None
        self.semester_choices: dict[str, tuple[int, int]] = {}
        self.device_sessions: dict[str, Any] = {}
        self.working = False
        self.closed = False
        self.auto_login_ready = False

        self.grade_details: dict[str, str] = {}
        self.settings_path = self._default_settings_path()

        self._create_variables()
        self._load_account_preference()
        self._configure_style()
        self._build_ui()
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        if self.auto_login_ready:
            self.root.after(500, self._auto_login)

    def _create_variables(self) -> None:
        self.account_var = tk.StringVar()
        self.remember_account_var = tk.BooleanVar(value=False)
        self.remember_password_var = tk.BooleanVar(value=False)
        self.password_var = tk.StringVar()
        self.device_var = tk.StringVar(value="ZZU.Py")
        self.user_token_var = tk.StringVar()
        self.refresh_token_var = tk.StringVar()
        self.login_status_var = tk.StringVar(value="尚未登录")
        self.status_var = tk.StringVar(value="就绪")

        self.default_room_var = tk.StringVar(value="登录后自动读取账号绑定寝室")
        self.lighting_room_var = tk.StringVar(value="电表 ID：--")
        self.air_conditioning_room_var = tk.StringVar(value="电表 ID：--")
        self.lighting_energy_var = tk.StringVar(value="--")
        self.air_conditioning_energy_var = tk.StringVar(value="--")
        self.grade_detail_var = tk.StringVar(value="选择一条成绩可查看分项信息")
        self.grade_rank_var = tk.StringVar(
            value="总排名、各学期排名：当前接口未提供班级或专业对比数据"
        )

        self.semester_var = tk.StringVar()
        self.week_var = tk.IntVar(value=1)
        self.schedule_status_var = tk.StringVar(value="请先加载学期")

        self.network_url_var = tk.StringVar(value="http://10.2.7.16:8080")
        self.network_account_var = tk.StringVar()
        self.network_password_var = tk.StringVar()
        self.network_status_var = tk.StringVar(value="尚未连接校园网自助服务")

    @staticmethod
    def _default_settings_path() -> Path:
        if appdata := os.environ.get("APPDATA"):
            base = Path(appdata)
        else:
            base = Path.home() / ".config"
        return base / "ZZU.Py" / "settings.json"

    def _load_account_preference(self) -> None:
        try:
            settings = json.loads(self.settings_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, OSError, json.JSONDecodeError, TypeError):
            return
        if not isinstance(settings, dict):
            return
        account = settings.get("account")
        if not isinstance(account, str) or not account.strip():
            return
        if settings.get("remember_account") is True:
            self.account_var.set(account.strip())
            self.network_account_var.set(account.strip())
            self.remember_account_var.set(True)
        encrypted_password = settings.get("password_dpapi")
        if (
            settings.get("remember_password") is True
            and isinstance(encrypted_password, str)
            and encrypted_password
        ):
            try:
                password = _unprotect_password(encrypted_password)
            except (OSError, ValueError, UnicodeError) as exc:
                self.status_var.set(f"已记住账号，但密码解密失败：{exc}")
                return
            self.account_var.set(account.strip())
            self.network_account_var.set(account.strip())
            self.password_var.set(password)
            self.remember_account_var.set(True)
            self.remember_password_var.set(True)
            self.auto_login_ready = True

    def _delete_account_preference(self) -> None:
        self.settings_path.unlink(missing_ok=True)

    def _save_account_preference(self, account: str, password: str) -> None:
        try:
            if not self.remember_account_var.get():
                self._delete_account_preference()
                return
            settings: dict[str, Any] = {
                "remember_account": True,
                "account": account,
                "remember_password": False,
            }
            if self.remember_password_var.get():
                settings["remember_password"] = True
                settings["password_dpapi"] = _protect_password(password)
            self.settings_path.parent.mkdir(parents=True, exist_ok=True)
            temporary_path = self.settings_path.with_suffix(".tmp")
            temporary_path.write_text(
                json.dumps(settings, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            temporary_path.replace(self.settings_path)
        except (OSError, ValueError) as exc:
            messagebox.showwarning(
                "登录信息未保存",
                f"登录已经成功，但无法加密或保存登录信息：{exc}",
                parent=self.root,
            )

    def _remember_account_changed(self) -> None:
        if not self.remember_account_var.get():
            self.remember_password_var.set(False)

    def _remember_password_changed(self) -> None:
        if self.remember_password_var.get():
            self.remember_account_var.set(True)

    def _auto_login(self) -> None:
        self.auto_login_ready = False
        if self.closed or self.working or self.cas is not None:
            return
        if self.account_var.get().strip() and self.password_var.get():
            self.login_status_var.set("正在自动登录...")
            self.login()

    def forget_account(self) -> None:
        try:
            self._delete_account_preference()
        except OSError as exc:
            messagebox.showerror(
                "清除失败", f"无法清除已记住的账号和密码：{exc}", parent=self.root
            )
            return
        self.remember_account_var.set(False)
        self.remember_password_var.set(False)
        self.password_var.set("")
        self.status_var.set("已清除记住的账号和密码")
    def _configure_style(self) -> None:
        style = ttk.Style(self.root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Title.TLabel", font=("Microsoft YaHei UI", 19, "bold"))
        style.configure("Subtitle.TLabel", font=("Microsoft YaHei UI", 10))
        style.configure("Value.TLabel", font=("Microsoft YaHei UI", 27, "bold"))
        style.configure("TButton", padding=(10, 6))
        style.configure("Treeview", rowheight=28)

    def _build_ui(self) -> None:
        shell = ttk.Frame(self.root, padding=14)
        shell.pack(fill="both", expand=True)

        ttk.Label(
            shell, text="郑大生活与教务助手", style="Title.TLabel"
        ).pack(anchor="w")
        ttk.Label(
            shell,
            text="统一认证 · 寝室电量 · 本科成绩 · 课表 · 校园网设备",
            style="Subtitle.TLabel",
        ).pack(anchor="w", pady=(0, 12))

        self.notebook = ttk.Notebook(shell)
        self.notebook.pack(fill="both", expand=True)
        self.login_tab = ttk.Frame(self.notebook, padding=18)
        self.energy_tab = ttk.Frame(self.notebook, padding=18)
        self.grades_tab = ttk.Frame(self.notebook, padding=18)
        self.schedule_tab = ttk.Frame(self.notebook, padding=18)
        self.network_tab = ttk.Frame(self.notebook, padding=18)
        self.notebook.add(self.login_tab, text="登录")
        self.notebook.add(self.energy_tab, text="寝室电量")
        self.notebook.add(self.grades_tab, text="成绩")
        self.notebook.add(self.schedule_tab, text="课表")
        self.notebook.add(self.network_tab, text="网络设备")
        for tab in (self.energy_tab, self.grades_tab, self.schedule_tab):
            self.notebook.tab(tab, state="disabled")

        self._build_login_tab()
        self._build_energy_tab()
        self._build_grades_tab()
        self._build_schedule_tab()
        self._build_network_tab()

        ttk.Separator(shell).pack(fill="x", pady=(10, 6))
        ttk.Label(shell, textvariable=self.status_var).pack(anchor="w")
    def _build_login_tab(self) -> None:
        form = ttk.LabelFrame(self.login_tab, text="统一认证", padding=16)
        form.pack(fill="x")
        form.columnconfigure(1, weight=1)

        ttk.Label(form, text="学号").grid(row=0, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.account_var, width=48).grid(
            row=0, column=1, sticky="ew", padx=(12, 0), pady=6
        )
        ttk.Label(form, text="统一认证密码").grid(
            row=1, column=0, sticky="w", pady=6
        )
        ttk.Entry(form, textvariable=self.password_var, show="●").grid(
            row=1, column=1, sticky="ew", padx=(12, 0), pady=6
        )
        ttk.Label(form, text="设备 ID").grid(row=2, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.device_var).grid(
            row=2, column=1, sticky="ew", padx=(12, 0), pady=6
        )

        token_frame = ttk.LabelFrame(
            self.login_tab, text="已有 Token（可选，仅保存在本次运行内存中）", padding=16
        )
        token_frame.pack(fill="x", pady=(14, 0))
        token_frame.columnconfigure(1, weight=1)
        ttk.Label(token_frame, text="userToken").grid(row=0, column=0, sticky="w")
        ttk.Entry(token_frame, textvariable=self.user_token_var, show="●").grid(
            row=0, column=1, sticky="ew", padx=(12, 0), pady=5
        )
        ttk.Label(token_frame, text="refreshToken").grid(
            row=1, column=0, sticky="w"
        )
        ttk.Entry(token_frame, textvariable=self.refresh_token_var, show="●").grid(
            row=1, column=1, sticky="ew", padx=(12, 0), pady=5
        )

        actions = ttk.Frame(self.login_tab)
        actions.pack(fill="x", pady=16)
        self.login_button = ttk.Button(actions, text="登录", command=self.login)
        self.login_button.pack(side="left")
        ttk.Button(actions, text="退出登录", command=self.logout).pack(
            side="left", padx=8
        )
        ttk.Checkbutton(
            actions,
            text="记住账号",
            variable=self.remember_account_var,
            command=self._remember_account_changed,
        ).pack(side="left", padx=(8, 0))
        ttk.Checkbutton(
            actions,
            text="记住密码并自动登录",
            variable=self.remember_password_var,
            command=self._remember_password_changed,
        ).pack(side="left", padx=(8, 0))
        ttk.Button(
            actions, text="清除登录信息", command=self.forget_account
        ).pack(side="left", padx=8)
        ttk.Label(actions, textvariable=self.login_status_var).pack(
            side="left", padx=12
        )

        warning = (
            "说明：登录顺序严格遵循认证文档。程序先检测 MFA，需要时发送并验证短信，"
            "随后调用 login()。记住的密码使用 Windows DPAPI 加密，仅当前 Windows 用户可解密；"
            "自动登录仍可能要求短信验证码。"
        )
        ttk.Label(
            self.login_tab, text=warning, wraplength=850, foreground="#8a4b08"
        ).pack(
            anchor="w"
        )

    def _build_energy_tab(self) -> None:
        header = ttk.Frame(self.energy_tab)
        header.pack(fill="x", pady=(0, 14))
        ttk.Label(
            header,
            text="账号绑定寝室",
            font=("Microsoft YaHei UI", 11, "bold"),
        ).pack(anchor="w")
        ttk.Label(header, textvariable=self.default_room_var).pack(anchor="w", pady=4)
        ttk.Button(
            header, text="同时查询照明和空调", command=self.query_all_energy
        ).pack(anchor="w", pady=(6, 0))

        cards = ttk.Frame(self.energy_tab)
        cards.pack(fill="both", expand=True)
        cards.columnconfigure(0, weight=1)
        cards.columnconfigure(1, weight=1)
        cards.rowconfigure(0, weight=1)

        lighting = ttk.LabelFrame(cards, text="照明房间", padding=24)
        lighting.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        ttk.Label(
            lighting, textvariable=self.lighting_energy_var, style="Value.TLabel"
        ).pack(pady=(30, 12))
        ttk.Label(lighting, textvariable=self.lighting_room_var).pack()
        ttk.Button(
            lighting,
            text="查询照明剩余电量",
            command=lambda: self.query_meter_energy("照明"),
        ).pack(pady=24)

        air_conditioning = ttk.LabelFrame(cards, text="空调房间", padding=24)
        air_conditioning.grid(row=0, column=1, sticky="nsew", padx=(8, 0))
        ttk.Label(
            air_conditioning,
            textvariable=self.air_conditioning_energy_var,
            style="Value.TLabel",
        ).pack(pady=(30, 12))
        ttk.Label(
            air_conditioning, textvariable=self.air_conditioning_room_var
        ).pack()
        ttk.Button(
            air_conditioning,
            text="查询空调剩余电量",
            command=lambda: self.query_meter_energy("空调"),
        ).pack(pady=24)

        ttk.Label(
            self.energy_tab,
            text=(
                "无需手动选择区域、楼栋、楼层和房间。程序先读取账号默认寝室名称，"
                "再扫描同楼栋电表目录，按寝室名称自动识别照明和空调记录 ID。"
            ),
            foreground="#8a4b08",
            wraplength=850,
        ).pack(anchor="w", pady=(14, 0))

    def _build_schedule_tab(self) -> None:
        self.schedule_tab.columnconfigure(0, weight=1)
        self.schedule_tab.rowconfigure(1, weight=1)

        controls = ttk.Frame(self.schedule_tab)
        controls.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        ttk.Label(controls, text="学期").pack(side="left")
        self.semester_box = ttk.Combobox(
            controls,
            textvariable=self.semester_var,
            state="readonly",
            width=31,
        )
        self.semester_box.pack(side="left", padx=(8, 14))
        self.semester_box.bind("<<ComboboxSelected>>", self._semester_selected)
        ttk.Label(controls, text="教学周").pack(side="left")
        self.week_spinbox = ttk.Spinbox(
            controls,
            textvariable=self.week_var,
            from_=1,
            to=30,
            width=6,
        )
        self.week_spinbox.pack(side="left", padx=(8, 14))
        ttk.Button(
            controls, text="加载学期", command=self.load_semesters
        ).pack(side="left")
        ttk.Button(
            controls, text="查询本周课表", command=self.query_schedule
        ).pack(side="left", padx=8)
        ttk.Button(
            controls, text="下载 iCalendar", command=self.export_calendar
        ).pack(side="left")
        ttk.Label(
            controls, textvariable=self.schedule_status_var
        ).pack(side="left", padx=8)

        table = ttk.Frame(self.schedule_tab)
        table.grid(row=1, column=0, sticky="nsew")
        columns = ("weekday", "units", "date", "course", "teacher", "place")
        self.schedule_tree = ttk.Treeview(
            table, columns=columns, show="headings", selectmode="browse"
        )
        headings = {
            "weekday": "星期",
            "units": "节次",
            "date": "日期",
            "course": "课程",
            "teacher": "教师",
            "place": "地点",
        }
        widths = {
            "weekday": 70,
            "units": 70,
            "date": 105,
            "course": 240,
            "teacher": 100,
            "place": 250,
        }
        for key in columns:
            self.schedule_tree.heading(key, text=headings[key])
            self.schedule_tree.column(key, width=widths[key], anchor="center")
        self.schedule_tree.column("course", anchor="w")
        self.schedule_tree.column("place", anchor="w")
        yscroll = ttk.Scrollbar(
            table, orient="vertical", command=self.schedule_tree.yview
        )
        xscroll = ttk.Scrollbar(
            table, orient="horizontal", command=self.schedule_tree.xview
        )
        self.schedule_tree.configure(
            yscrollcommand=yscroll.set, xscrollcommand=xscroll.set
        )
        self.schedule_tree.grid(row=0, column=0, sticky="nsew")
        yscroll.grid(row=0, column=1, sticky="ns")
        xscroll.grid(row=1, column=0, sticky="ew")
        table.columnconfigure(0, weight=1)
        table.rowconfigure(0, weight=1)

    def _build_network_tab(self) -> None:
        self.network_tab.columnconfigure(0, weight=1)
        self.network_tab.rowconfigure(2, weight=1)

        form = ttk.LabelFrame(
            self.network_tab, text="校园网自助服务", padding=12
        )
        form.grid(row=0, column=0, sticky="ew")
        form.columnconfigure(1, weight=1)
        ttk.Label(form, text="服务地址").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Entry(form, textvariable=self.network_url_var).grid(
            row=0, column=1, columnspan=3, sticky="ew", padx=(10, 0), pady=4
        )
        ttk.Label(form, text="网络账号").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(form, textvariable=self.network_account_var).grid(
            row=1, column=1, sticky="ew", padx=(10, 14), pady=4
        )
        ttk.Label(form, text="网络密码").grid(row=1, column=2, sticky="w", pady=4)
        ttk.Entry(
            form, textvariable=self.network_password_var, show="●", width=28
        ).grid(row=1, column=3, sticky="ew", padx=(10, 0), pady=4)

        actions = ttk.Frame(self.network_tab)
        actions.grid(row=1, column=0, sticky="ew", pady=10)
        ttk.Button(
            actions, text="登录并刷新", command=self.connect_network_devices
        ).pack(side="left")
        ttk.Button(
            actions, text="刷新设备", command=self.refresh_network_devices
        ).pack(side="left", padx=8)
        ttk.Button(
            actions, text="下线所选设备", command=self.kick_selected_device
        ).pack(side="left")
        ttk.Label(
            actions, textvariable=self.network_status_var
        ).pack(side="left", padx=14)

        table = ttk.Frame(self.network_tab)
        table.grid(row=2, column=0, sticky="nsew")
        columns = (
            "host", "ip", "mac", "type", "login", "duration", "up", "down"
        )
        self.device_tree = ttk.Treeview(
            table, columns=columns, show="headings", selectmode="browse"
        )
        headings = {
            "host": "设备名",
            "ip": "IP",
            "mac": "MAC",
            "type": "类型",
            "login": "登录时间",
            "duration": "在线时长",
            "up": "上行",
            "down": "下行",
        }
        widths = {
            "host": 110,
            "ip": 105,
            "mac": 130,
            "type": 80,
            "login": 145,
            "duration": 90,
            "up": 80,
            "down": 80,
        }
        for key in columns:
            self.device_tree.heading(key, text=headings[key])
            self.device_tree.column(key, width=widths[key], anchor="center")
        yscroll = ttk.Scrollbar(
            table, orient="vertical", command=self.device_tree.yview
        )
        xscroll = ttk.Scrollbar(
            table, orient="horizontal", command=self.device_tree.xview
        )
        self.device_tree.configure(
            yscrollcommand=yscroll.set, xscrollcommand=xscroll.set
        )
        self.device_tree.grid(row=0, column=0, sticky="nsew")
        yscroll.grid(row=0, column=1, sticky="ns")
        xscroll.grid(row=1, column=0, sticky="ew")
        table.columnconfigure(0, weight=1)
        table.rowconfigure(0, weight=1)
        ttk.Label(
            self.network_tab,
            text=(
                "下线操作只作用于当前选中的会话，并会再次确认。"
                "网络密码只用于本次登录，不会写入配置文件。"
            ),
            foreground="#8a4b08",
        ).grid(row=3, column=0, sticky="w", pady=(10, 0))
    def _build_grades_tab(self) -> None:
        self.grades_tab.columnconfigure(0, weight=1)
        self.grades_tab.rowconfigure(1, weight=1)

        actions = ttk.Frame(self.grades_tab)
        actions.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        ttk.Button(actions, text="刷新成绩", command=self.query_grades).pack(
            side="left"
        )
        ttk.Label(actions, textvariable=self.grade_rank_var).pack(
            side="left", padx=16
        )

        table = ttk.Frame(self.grades_tab)
        table.grid(row=1, column=0, sticky="nsew")
        columns = ("course", "score", "gp", "credits", "status")
        self.grade_tree = ttk.Treeview(
            table,
            columns=columns,
            show="tree headings",
            selectmode="browse",
        )
        self.grade_tree.heading("#0", text="学期")
        self.grade_tree.column("#0", width=180, anchor="w")
        headings = {
            "course": "课程",
            "score": "成绩",
            "gp": "绩点",
            "credits": "学分",
            "status": "状态",
        }
        widths = {
            "course": 310,
            "score": 90,
            "gp": 70,
            "credits": 70,
            "status": 80,
        }
        for key in columns:
            self.grade_tree.heading(key, text=headings[key])
            self.grade_tree.column(key, width=widths[key], anchor="center")
        self.grade_tree.column("course", anchor="w")
        self.grade_tree.tag_configure(
            "semester", background="#eef3f8", font=("Microsoft YaHei UI", 10, "bold")
        )
        scrollbar = ttk.Scrollbar(
            table, orient="vertical", command=self.grade_tree.yview
        )
        self.grade_tree.configure(yscrollcommand=scrollbar.set)
        self.grade_tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="left", fill="y")
        self.grade_tree.bind("<<TreeviewSelect>>", self._show_grade_detail)

        detail = ttk.LabelFrame(self.grades_tab, text="成绩明细", padding=10)
        detail.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        ttk.Label(detail, textvariable=self.grade_detail_var, wraplength=850).pack(
            anchor="w"
        )

    def _require_ecard(self) -> ECardClient:
        if self.ecard is None:
            raise ValueError("请先登录。")
        return self.ecard

    def _run(
        self,
        label: str,
        action: Callable[[], Any],
        on_success: Callable[[Any], None] | None = None,
    ) -> None:
        if self.working:
            messagebox.showinfo("请稍候", "另一个操作正在执行。")
            return
        self.working = True
        self.status_var.set(label)

        def worker() -> None:
            try:
                result = action()
            except BaseException as exc:
                if not self.closed:
                    self.root.after(0, lambda error=exc: self._finish_error(error))
            else:
                if not self.closed:
                    self.root.after(
                        0, lambda: self._finish_success(label, result, on_success)
                    )

        threading.Thread(target=worker, daemon=True).start()

    def _finish_success(
        self,
        label: str,
        result: Any,
        callback: Callable[[Any], None] | None,
    ) -> None:
        self.working = False
        self.status_var.set(f"{label}完成")
        if callback is not None:
            callback(result)

    def _finish_error(self, exc: BaseException) -> None:
        self.working = False
        self.status_var.set("操作失败")
        if isinstance(exc, ZZUError):
            detail = exc.message
            validation_errors = exc.context.get("validation_errors")
            if validation_errors:
                detail += f"\n\n解析详情：{validation_errors}"
        else:
            detail = str(exc) or type(exc).__name__
        messagebox.showerror("操作失败", detail)

    def _ask_sms_code(self) -> str:
        answers: queue.Queue[str | None] = queue.Queue(maxsize=1)

        def ask() -> None:
            answers.put(
                simpledialog.askstring(
                    "短信验证",
                    "验证码已发送，请输入短信验证码：",
                    show="●",
                    parent=self.root,
                )
            )

        self.root.after(0, ask)
        code = answers.get()
        if not code or not code.strip():
            raise ValueError("已取消短信验证。")
        return code.strip()

    def login(self) -> None:
        account = self.account_var.get().strip()
        password = self.password_var.get()
        device_id = self.device_var.get().strip() or "ZZU.Py"
        user_token = self.user_token_var.get().strip()
        refresh_token = self.refresh_token_var.get().strip()
        if not account or not password:
            messagebox.showwarning("信息不完整", "请输入学号和统一认证密码。")
            return
        if bool(user_token) != bool(refresh_token):
            messagebox.showwarning("Token 不完整", "userToken 和 refreshToken 必须同时填写。")
            return

        def action() -> tuple[str, CASClient, ECardClient]:
            cas = CASClient(account, password)
            ecard: ECardClient | None = None
            try:
                cas.set_device(device_id)
                if user_token and refresh_token:
                    cas.set_token(user_token, refresh_token)
                if cas.mfa.is_required():
                    cas.mfa.send_sms()
                    cas.mfa.verify_sms(self._ask_sms_code())
                cas.login()
                ecard = ECardClient(cas)
                ecard.login()
                return account, cas, ecard
            except BaseException:
                if ecard is not None:
                    ecard.close()
                cas.close()
                raise

        self._run("正在登录并连接一卡通...", action, self._login_succeeded)

    def _login_succeeded(
        self, clients: tuple[str, CASClient, ECardClient]
    ) -> None:
        account, cas, ecard = clients
        password = self.password_var.get()
        self._close_clients()
        self.cas, self.ecard = cas, ecard
        self.user_token_var.set(self.cas.user_token or "")
        self.refresh_token_var.set(self.cas.refresh_token or "")
        self.login_status_var.set("已登录")
        if not self.network_account_var.get().strip():
            self.network_account_var.set(account)
        self._save_account_preference(account, password)
        self.password_var.set("")
        for tab in (self.energy_tab, self.grades_tab, self.schedule_tab):
            self.notebook.tab(tab, state="normal")
        self.notebook.select(self.energy_tab)
        self.query_all_energy()
    def logout(self) -> None:
        if self.working:
            messagebox.showinfo("请稍候", "当前操作完成后再退出登录。")
            return
        self._close_clients()
        self.login_status_var.set("尚未登录")
        for tab in (self.energy_tab, self.grades_tab, self.schedule_tab):
            self.notebook.tab(tab, state="disabled")
        self.default_room_var.set("登录后自动读取账号绑定寝室")
        self.lighting_room_var.set("电表 ID：-")
        self.air_conditioning_room_var.set("电表 ID：-")
        self.lighting_energy_var.set("--")
        self.air_conditioning_energy_var.set("--")
        self.semester_choices.clear()
        self.semester_var.set("")
        self.schedule_status_var.set("请先加载学期")
        for tree in (self.schedule_tree, self.device_tree):
            for item in tree.get_children():
                tree.delete(item)
        self.device_sessions.clear()
        self.network_status_var.set("尚未连接校园网自助服务")
        self.status_var.set("已退出登录")
    def _close_clients(self) -> None:
        self._close_self_service()
        if self.ecard is not None:
            try:
                self.ecard.close()
            finally:
                self.ecard = None
        if self.cas is not None:
            try:
                self.cas.close()
            finally:
                self.cas = None
    @staticmethod
    def _energy_variables(meter_type: str) -> tuple[str, str]:
        if meter_type == "照明":
            return "lighting_room_var", "lighting_energy_var"
        if meter_type == "空调":
            return "air_conditioning_room_var", "air_conditioning_energy_var"
        raise ValueError(f"无法识别电费类型：{meter_type}")

    @staticmethod
    def _read_remaining_energy(
        ecard: ECardClient, meter_id: str, meter_type: str
    ) -> float:
        try:
            return ecard.get_remaining_energy(meter_id)
        except ParsingError as exc:
            if "quantity" not in exc.message:
                raise
            raise ValueError(
                f"学校服务器没有返回{meter_type}电表 {meter_id} 的剩余电量。"
            ) from exc

    def _fetch_meter_energy(
        self, ecard: ECardClient, default_room_id: str, meter_type: str
    ) -> tuple[str, float]:
        source_level, separator, _ = default_room_id.rpartition("-")
        if not separator or "--" not in source_level:
            raise ValueError(f"默认寝室 ID 格式不完整：{default_room_id}")

        source_rooms = {
            full_room_id(source_level, room_id): str(room_name)
            for room_id, room_name in ecard.get_room_dict(source_level).items()
        }
        source_name = source_rooms.get(default_room_id)
        if source_name is None:
            raise ValueError(
                f"默认寝室 {default_room_id} 不在服务器房间目录中，无法识别实际寝室。"
            )

        preferred_level = meter_level_id_for_type(default_room_id, meter_type)
        if preferred_level == source_level:
            remaining = self._read_remaining_energy(
                ecard, default_room_id, meter_type
            )
            return default_room_id, remaining

        building_id = source_level.split("--", 1)[0]
        levels = {
            full_level_id(building_id, level_id): str(level_name)
            for level_id, level_name in ecard.get_room_dict(building_id).items()
        }
        levels.setdefault(preferred_level, "按 41/42 规则推定")
        ordered_levels = sorted(
            levels.items(),
            key=lambda item: (
                0 if meter_type in item[1] else 1,
                0 if item[0] == preferred_level else 1,
                item[0],
            ),
        )

        source_key = room_match_key(source_name)
        candidate_matches: list[tuple[str, str, str]] = []
        scanned_rooms: dict[str, dict[str, str]] = {}
        for level_id, level_name in ordered_levels:
            if level_id == source_level:
                continue
            rooms = {
                full_room_id(level_id, room_id): str(room_name)
                for room_id, room_name in ecard.get_room_dict(level_id).items()
            }
            scanned_rooms[level_id] = rooms
            for room_id, room_name in rooms.items():
                target_key = room_match_key(room_name)
                if room_keys_match(source_key, target_key):
                    candidate_matches.append(
                        (room_id, level_name, target_key)
                    )

        exact_candidates = [
            (room_id, level_name)
            for room_id, level_name, target_key in candidate_matches
            if target_key == source_key
        ]
        candidates = exact_candidates or [
            (room_id, level_name)
            for room_id, level_name, _target_key in candidate_matches
        ]
        typed_candidates = [
            candidate for candidate in candidates if meter_type in candidate[1]
        ]
        if typed_candidates:
            candidates = typed_candidates
        if len(candidates) > 1:
            candidate_text = "、".join(
                f"{room_id}（{level_name}）"
                for room_id, level_name in candidates
            )
            raise ValueError(
                f"房间号 {source_key} 匹配到多个{meter_type}候选，"
                f"无法安全确定：{candidate_text}"
            )

        if not candidates:
            available_levels = "、".join(
                f"{level_id}（{level_name}）"
                for level_id, level_name in ordered_levels
            )
            relevant_levels = {
                level_id
                for level_id, level_name in ordered_levels
                if level_id == preferred_level or meter_type in level_name
            }
            room_samples = "；".join(
                f"{level_id}: "
                + "、".join(
                    f"{room_id.rsplit('-', 1)[-1]}={room_name}"
                    for room_id, room_name in list(rooms.items())[:20]
                )
                for level_id, rooms in scanned_rooms.items()
                if level_id in relevant_levels
            )
            raise ValueError(
                f"同楼栋目录中没有与“{source_name}”（匹配键 {source_key}）"
                f"对应的{meter_type}房间。服务器返回的目录："
                f"{available_levels or '空'}\n{meter_type}目录房间样例："
                f"{room_samples or '空'}"
            )

        quantity_errors: list[str] = []
        for meter_id, level_name in candidates:
            try:
                remaining = self._read_remaining_energy(
                    ecard, meter_id, meter_type
                )
            except ValueError as exc:
                quantity_errors.append(f"{meter_id}（{level_name}）：{exc}")
                continue
            return meter_id, remaining

        raise ValueError(
            f"找到了 {len(candidates)} 个与“{source_name}”同名的候选房间，"
            "但学校服务器均未返回剩余电量：\n" + "\n".join(quantity_errors)
        )
    def query_meter_energy(self, meter_type: str) -> None:
        room_variable, energy_variable = self._energy_variables(meter_type)
        getattr(self, energy_variable).set("查询中...")

        def action() -> tuple[str, str, float]:
            ecard = self._require_ecard()
            default_room_id = ecard.get_default_room()
            meter_id, remaining = self._fetch_meter_energy(
                ecard, default_room_id, meter_type
            )
            return default_room_id, meter_id, remaining

        def success(result: tuple[str, str, float]) -> None:
            default_room_id, meter_id, remaining = result
            self.default_room_var.set(f"默认寝室：{default_room_id}")
            getattr(self, room_variable).set(f"电表 ID：{meter_id}")
            getattr(self, energy_variable).set(f"{remaining:g} 度")

        self._run(f"正在查询{meter_type}剩余电量...", action, success)

    def query_all_energy(self) -> None:
        self.lighting_energy_var.set("查询中...")
        self.air_conditioning_energy_var.set("查询中...")

        def action() -> tuple[
            str, dict[str, tuple[str | None, float | None, str | None]]
        ]:
            ecard = self._require_ecard()
            default_room_id = ecard.get_default_room()
            results: dict[str, tuple[str | None, float | None, str | None]] = {}
            for meter_type in ("照明", "空调"):
                try:
                    meter_id, remaining = self._fetch_meter_energy(
                        ecard, default_room_id, meter_type
                    )
                    results[meter_type] = (meter_id, remaining, None)
                except (ZZUError, ValueError) as exc:
                    results[meter_type] = (None, None, str(exc))
            return default_room_id, results

        def success(
            result: tuple[
                str, dict[str, tuple[str | None, float | None, str | None]]
            ]
        ) -> None:
            default_room_id, results = result
            self.default_room_var.set(f"默认寝室：{default_room_id}")
            errors: list[str] = []
            for meter_type, (meter_id, remaining, error) in results.items():
                room_variable, energy_variable = self._energy_variables(meter_type)
                getattr(self, room_variable).set(f"电表 ID：{meter_id or '--'}")
                if error is None and remaining is not None:
                    getattr(self, energy_variable).set(f"{remaining:g} 度")
                else:
                    getattr(self, energy_variable).set("查询失败")
                    errors.append(error or f"{meter_type}电量未知")
            if errors:
                messagebox.showwarning(
                    "部分电量查询失败", "\n\n".join(errors), parent=self.root
                )

        self._run("正在查询照明和空调剩余电量...", action, success)

    def load_semesters(self) -> None:
        if self.cas is None:
            messagebox.showwarning("尚未登录", "请先登录统一认证。")
            return
        cas = self.cas

        def action() -> list[Any]:
            with UndergradEASClient(cas) as eas:
                eas.login()
                return eas.get_semesters()

        self._run("正在加载学期...", action, self._show_semesters)

    def _show_semesters(self, semesters: list[Any]) -> None:
        ordered = sorted(
            semesters, key=lambda semester: str(semester.start_date), reverse=True
        )
        self.semester_choices.clear()
        labels: list[str] = []
        for semester in ordered:
            label = (
                f"{semester.school_year} {semester.name_zh} "
                f"[{semester.id}]"
            )
            total_weeks = max(semester.week_indices, default=1)
            self.semester_choices[label] = (semester.id, total_weeks)
            labels.append(label)
        self.semester_box.configure(values=labels)
        if not labels:
            self.semester_var.set("")
            self.schedule_status_var.set("没有可用学期")
            return
        self.semester_var.set(labels[0])
        self.week_var.set(1)
        self._semester_selected()
        self.schedule_status_var.set(f"已加载 {len(labels)} 个学期")

    def _semester_selected(self, _event: tk.Event[Any] | None = None) -> None:
        choice = self.semester_choices.get(self.semester_var.get())
        if choice is None:
            return
        _semester_id, total_weeks = choice
        self.week_spinbox.configure(to=max(total_weeks, 1))
        if not 1 <= self.week_var.get() <= total_weeks:
            self.week_var.set(1)

    def query_schedule(self) -> None:
        if self.cas is None:
            messagebox.showwarning("尚未登录", "请先登录统一认证。")
            return
        choice = self.semester_choices.get(self.semester_var.get())
        if choice is None:
            messagebox.showwarning("尚未选择学期", "请先点击“加载学期”。")
            return
        semester_id, total_weeks = choice
        try:
            week_number = int(self.week_var.get())
        except (tk.TclError, ValueError):
            messagebox.showwarning("教学周不正确", "教学周必须是整数。")
            return
        if not 1 <= week_number <= total_weeks:
            messagebox.showwarning(
                "教学周不正确", f"该学期教学周范围为 1–{total_weeks}。"
            )
            return
        cas = self.cas

        def action() -> Any:
            with UndergradEASClient(cas) as eas:
                eas.login()
                return eas.get_teaching_week(week_number, semester_id)

        def success(teaching_week: Any) -> None:
            self._show_schedule(teaching_week, week_number)

        self._run(f"正在查询第 {week_number} 周课表...", action, success)

    def export_calendar(self) -> None:
        if self.cas is None:
            messagebox.showwarning("尚未登录", "请先登录统一认证。")
            return
        choice = self.semester_choices.get(self.semester_var.get())
        if choice is None:
            messagebox.showwarning("尚未选择学期", "请先点击“加载学期”。")
            return
        semester_id, _total_weeks = choice
        raw_name = self.semester_var.get() or f"semester-{semester_id}"
        safe_name = "".join(
            character if character.isalnum() or character in "-_" else "_"
            for character in raw_name
        ).strip("_")
        destination = filedialog.asksaveasfilename(
            parent=self.root,
            title="保存 iCalendar 课表",
            defaultextension=".ics",
            initialfile=f"郑大课表_{safe_name}.ics",
            filetypes=(("iCalendar 文件", "*.ics"), ("所有文件", "*.*")),
        )
        if not destination:
            return
        cas = self.cas

        def action() -> tuple[str, int]:
            with UndergradEASClient(cas) as eas:
                eas.login()
                teaching_weeks = eas.get_teaching_weeks(semester_id)
            calendar = teaching_weeks.to_calendar()
            payload = calendar.to_ical()
            Path(destination).write_bytes(payload)
            event_count = len(calendar.walk("VEVENT"))
            return destination, event_count

        def success(result: tuple[str, int]) -> None:
            path, event_count = result
            messagebox.showinfo(
                "导出成功",
                f"已导出 {event_count} 个课程日程：\n{path}",
                parent=self.root,
            )

        self._run("正在下载完整学期课表...", action, success)
    @staticmethod
    def _schedule_place(schedule: Any) -> str:
        room = schedule.room
        if room is None:
            return schedule.custom_place or "-"
        parts = [
            getattr(getattr(room, "campus", None), "name_zh", ""),
            getattr(getattr(room, "building", None), "name_zh", ""),
            getattr(room, "name_zh", ""),
        ]
        return " ".join(part for part in parts if part) or "-"

    def _show_schedule(self, teaching_week: Any, week_number: int) -> None:
        for item in self.schedule_tree.get_children():
            self.schedule_tree.delete(item)
        weekdays = ("", "周一", "周二", "周三", "周四", "周五", "周六", "周日")
        unique: dict[tuple[Any, ...], Any] = {}
        for lesson in teaching_week.lessons.values():
            schedule = lesson.schedule
            key = (
                schedule.schedule_group_id,
                str(schedule.date),
                schedule.start_unit,
                schedule.end_unit,
                lesson.course.code,
            )
            unique[key] = lesson
        lessons = sorted(
            unique.values(),
            key=lambda lesson: (
                lesson.schedule.weekday,
                lesson.schedule.start_unit,
                lesson.course.name_zh,
            ),
        )
        for lesson in lessons:
            schedule = lesson.schedule
            weekday = (
                weekdays[schedule.weekday]
                if 1 <= schedule.weekday <= 7
                else str(schedule.weekday)
            )
            self.schedule_tree.insert(
                "",
                "end",
                values=(
                    weekday,
                    f"{schedule.start_unit}-{schedule.end_unit}",
                    str(schedule.date),
                    lesson.course.name_zh,
                    schedule.teacher_name or "-",
                    self._schedule_place(schedule),
                ),
            )
        self.schedule_status_var.set(
            f"第 {week_number} 周，共 {len(lessons)} 次课"
        )

    def connect_network_devices(self) -> None:
        base_url = self.network_url_var.get().strip().rstrip("/")
        account = self.network_account_var.get().strip()
        password = self.network_password_var.get()
        if not base_url or not account or not password:
            messagebox.showwarning(
                "信息不完整", "请填写服务地址、网络账号和网络密码。"
            )
            return
        if not base_url.startswith(("http://", "https://")):
            messagebox.showwarning(
                "服务地址不正确", "服务地址必须以 http:// 或 https:// 开头。"
            )
            return

        def action() -> tuple[SelfServiceSystem, list[Any]]:
            service = SelfServiceSystem(base_url)
            try:
                service.login(account, password)
                return service, service.get_online_devices()
            except BaseException:
                service.close()
                raise

        def success(result: tuple[SelfServiceSystem, list[Any]]) -> None:
            service, devices = result
            self._close_self_service()
            self.self_service = service
            self.network_password_var.set("")
            self._show_online_devices(devices)

        self._run("正在登录校园网自助服务...", action, success)

    def refresh_network_devices(self) -> None:
        if self.self_service is None:
            messagebox.showwarning(
                "尚未连接", "请先填写网络账号和密码，然后点击“登录并刷新”。"
            )
            return
        service = self.self_service
        self._run(
            "正在刷新在线设备...",
            service.get_online_devices,
            self._show_online_devices,
        )

    def _show_online_devices(self, devices: list[Any]) -> None:
        for item in self.device_tree.get_children():
            self.device_tree.delete(item)
        self.device_sessions.clear()
        for device in devices:
            item = self.device_tree.insert(
                "",
                "end",
                values=(
                    device.host_name or "-",
                    device.ip,
                    device.mac,
                    device.terminal_type,
                    device.login_time,
                    device.use_time,
                    device.up_flow,
                    device.down_flow,
                ),
            )
            self.device_sessions[item] = device
        self.network_status_var.set(f"当前在线设备：{len(devices)} 台")

    def kick_selected_device(self) -> None:
        selected = self.device_tree.selection()
        if not selected:
            messagebox.showwarning("未选择设备", "请先在列表中选择一台设备。")
            return
        if self.self_service is None:
            messagebox.showwarning("尚未连接", "请先登录校园网自助服务。")
            return
        device = self.device_sessions.get(selected[0])
        if device is None:
            messagebox.showwarning("设备已失效", "请刷新设备列表后重试。")
            return
        description = device.host_name or device.ip or device.mac
        confirmed = messagebox.askyesno(
            "确认设备下线",
            f"确定让设备“{description}”下线吗？\nIP：{device.ip}\nMAC：{device.mac}",
            parent=self.root,
        )
        if not confirmed:
            return
        service = self.self_service

        def action() -> None:
            service.kick_device(device.session_id)

        def success(_result: None) -> None:
            messagebox.showinfo("操作成功", "所选设备已提交下线。")
            self.refresh_network_devices()

        self._run("正在下线所选设备...", action, success)

    def _close_self_service(self) -> None:
        if self.self_service is None:
            return
        try:
            self.self_service.close()
        except BaseException:
            pass
        finally:
            self.self_service = None
    def query_grades(self) -> None:
        if self.cas is None:
            messagebox.showwarning("尚未登录", "请先登录。")
            return
        cas = self.cas

        def action() -> list[Any]:
            with UndergradEASClient(cas) as eas:
                eas.login()
                return eas.get_grades()

        self._run("正在查询成绩...", action, self._show_grades)

    def _show_grades(self, grades: list[Any]) -> None:
        for item in self.grade_tree.get_children():
            self.grade_tree.delete(item)
        self.grade_details.clear()

        grouped: dict[str, list[Any]] = {}
        for grade in grades:
            semester = grade.semester.name_zh or "未知学期"
            grouped.setdefault(semester, []).append(grade)

        for semester in sorted(grouped, reverse=True):
            semester_grades = grouped[semester]
            parent = self.grade_tree.insert(
                "",
                "end",
                text=f"{semester}（{len(semester_grades)} 门）",
                values=("", "", "", "", ""),
                open=True,
                tags=("semester",),
            )
            for grade in semester_grades:
                item = self.grade_tree.insert(
                    parent,
                    "end",
                    text="",
                    values=(
                        grade.course_name_zh,
                        grade.final_grade or "未发布",
                        "-" if grade.gp is None else f"{grade.gp:g}",
                        f"{grade.credits:g}",
                        (
                            "未知"
                            if grade.passed is None
                            else "通过" if grade.passed else "未通过"
                        ),
                    ),
                )
                self.grade_details[item] = grade.grade_detail or "无分项成绩"
        self.grade_detail_var.set(
            f"共 {len(grouped)} 个学期，{len(grades)} 条成绩"
        )

    def _show_grade_detail(self, _event: tk.Event[Any]) -> None:
        selected = self.grade_tree.selection()
        if selected:
            self.grade_detail_var.set(self.grade_details.get(selected[0], "无分项成绩"))

    def close(self) -> None:
        self.closed = True
        self._close_clients()
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    ZzuGui(root)
    root.mainloop()


if __name__ == "__main__":
    main()