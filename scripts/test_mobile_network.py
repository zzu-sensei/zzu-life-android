"""校园网自助服务页面解析的离线回归自检（不联网、不需要账号）。

覆盖 ``mobile_network_page.py`` 里两条容易踩的规则：账户对象是**内联的 JS 字面量**
（不是 JSON 接口），登录历史是**位置数组**（没有字段名）。另外断言解析器**不会**
把页面里明文暴露的账户密码解析出来。

    python scripts/run_tests.py
    python scripts/test_mobile_network.py

这些断言来自对着真实响应调试的结果，不是构造着玩的。改动解析器后请先跑它。
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

import mobile_network_page as net  # noqa: E402

PAGE = """
<html><body>
<script>
(function (user) {
    window.user = user || {};
})({"bindCmFlag":"0","downloadBand":65535,"installDate":1725033600000,
"internetDownFlow":1902.419,"internetUpFlow":10505.808,"ipCount":1,
"leftFlow":0,"leftMoney":0,"leftTime":0,
"macAddress":"AABBCCDDEEFF;001122334455","multiLogin":3,
"serviceDefault":{"defaultName":"\\u5B66\\u751F"},
"startDate":1725033600000,"stopDate":1725033600000,"stopReason":"开始计费",
"uploadBand":65535,"useFlow":12.5,"useMoney":0,"useTime":30,
"userGroup":{"ipMaxCount":3,"userGroupName":"学生|ug=stu|"},
"userId":100000000,"userIp":"10.0.0.1",
"userName":"202400000000","userPassword":"<dummy>","userRealName":"测试用户",
"vlanId":0});
</script>
</body></html>
"""

HISTORY = """[
[1791346991000,1791347427000,"10.0.0.11","AABBCCDDEE01",0,0,2,0,null,"#PC","PC",1],
[1790731066000,1791347415000,"10.0.0.12","AABBCCDDEE02",0,0,2,0,null,"#移动终端","移动终端",2],
[1790818269000,1790819382000,"10.0.0.13","AABBCCDDEE01",0,0,2,0,null,"#PC",null,3]
]"""


def test_parse_account() -> None:
    account = net.parse_account_page(PAGE)
    assert account["user_name"] == "202400000000"
    assert account["real_name"] == "测试用户"
    assert account["user_id"] == 100000000
    assert account["user_ip"] == "10.0.0.1"
    assert account["mac_address"] == "AABBCCDDEEFF;001122334455"
    assert account["service_name"] == "学生"
    assert account["group_name"] == "学生|ug=stu|"
    assert account["use_flow"] == 12.5
    assert account["use_time"] == 30
    assert account["down_flow"] == 1902.419
    assert account["up_flow"] == 10505.808
    assert account["multi_login"] == 3
    assert account["ip_max_count"] == 3
    assert account["ip_count"] == 1
    # 毫秒时间戳要转成东八区的日期。
    assert account["install_date"] == "2024-08-31"
    assert account["stop_reason"] == "开始计费"


def test_password_is_never_parsed() -> None:
    """页面明文暴露了密码，但解析结果里不该出现它。"""
    account = net.parse_account_page(PAGE)
    assert "user_password" not in account
    assert "userPassword" not in account
    assert all("dummy" not in str(value) for value in account.values())


def test_missing_account_object_raises() -> None:
    try:
        net.parse_account_page("<html><body>没有账户对象</body></html>")
    except RuntimeError as error:
        assert "没有找到账户对象" in str(error)
    else:  # pragma: no cover - 走到这里说明解析器没有报错
        raise AssertionError("缺少账户对象时应当报错")


def test_parse_login_history() -> None:
    records = net.parse_login_history(HISTORY)
    assert len(records) == 3, records

    first = records[0]
    assert first["ip"] == "10.0.0.11"
    assert first["mac"] == "AABBCCDDEE01"
    assert first["terminal_type"] == "PC"
    assert first["index"] == 1
    assert first["duration_seconds"] == 436.0
    assert first["start_time"].startswith("2026-")
    # 未知位置原样保留，方便日后确认含义。
    assert first["raw"][6] == 2 and first["raw"][9] == "#PC"

    assert records[1]["terminal_type"] == "移动终端"
    # 第 11 项缺失时回退到第 10 项的 "#PC"，去掉前缀。
    assert records[2]["terminal_type"] == "PC"


def test_login_history_shape_error() -> None:
    try:
        net.parse_login_history('{"not": "a list"}')
    except RuntimeError as error:
        assert "不是数组" in str(error)
    else:  # pragma: no cover
        raise AssertionError("不是数组时应当报错")

    try:
        net.parse_login_history("not json at all")
    except RuntimeError as error:
        assert "合法 JSON" in str(error)
    else:  # pragma: no cover
        raise AssertionError("非 JSON 时应当报错")


def main() -> None:
    test_parse_account()
    test_password_is_never_parsed()
    test_missing_account_object_raises()
    test_parse_login_history()
    test_login_history_shape_error()
    print("安卓端校园网解析自检通过：账户字段、密码不解析、日期换算、登录历史与报错均正常。")


if __name__ == "__main__":
    main()
