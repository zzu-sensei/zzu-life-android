"""ZZU.Py 的安全命令行入口。"""

from __future__ import annotations

import argparse
from getpass import getpass
import json
import os
import sys

from zzupy.app import CASClient, ECardClient, UndergradEASClient
from zzupy.exception import ZZUError


def _create_cas(account: str | None) -> CASClient:
    account = account or os.environ.get("ZZU_ACCOUNT") or input("学号: ").strip()
    password = os.environ.get("ZZU_PASSWORD") or getpass("统一认证密码: ")
    cas = CASClient(account, password)
    try:
        if cas.mfa.is_required():
            cas.mfa.send_sms()
            cas.mfa.verify_sms(input("短信验证码: ").strip())
        cas.login()
        return cas
    except BaseException:
        cas.close()
        raise


def _energy(cas: CASClient, room: str | None) -> None:
    with ECardClient(cas) as ecard:
        ecard.login()
        target = room or ecard.get_default_room()
        remaining = ecard.get_remaining_energy(target)
        print(f"寝室 {target} 剩余电量: {remaining:g}")


def _grades(cas: CASClient, semester: str | None, as_json: bool) -> None:
    with UndergradEASClient(cas) as eas:
        eas.login()
        grades = eas.get_grades()

    if semester:
        grades = [grade for grade in grades if semester in grade.semester.name_zh]
    if as_json:
        data = [grade.model_dump(mode="json", by_alias=True) for grade in grades]
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return
    if not grades:
        print("没有查询到符合条件的成绩。")
        return

    grouped: dict[str, list] = {}
    for grade in grades:
        grouped.setdefault(grade.semester.name_zh or "未知学期", []).append(grade)

    for semester in sorted(grouped, reverse=True):
        print(f"\n[{semester}]")
        print("课程\t成绩\t绩点\t学分\t状态")
        for grade in grouped[semester]:
            final_grade = grade.final_grade or "未发布"
            gp = "-" if grade.gp is None else f"{grade.gp:g}"
            status = (
                "未知"
                if grade.passed is None
                else "通过" if grade.passed else "未通过"
            )
            print(
                f"{grade.course_name_zh}\t{final_grade}\t{gp}\t"
                f"{grade.credits:g}\t{status}"
            )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="郑州大学生活与教务服务命令行工具")
    parser.add_argument("--account", help="学号；也可设置 ZZU_ACCOUNT")
    subparsers = parser.add_subparsers(dest="command", required=True)

    energy = subparsers.add_parser("energy", help="查询寝室剩余电量")
    energy.add_argument("--room", help="寝室 ID；不传则查询默认寝室")

    grades = subparsers.add_parser("grades", help="查询全部已发布成绩")
    grades.add_argument("--semester", help="按学期名称包含关系筛选")
    grades.add_argument("--json", action="store_true", help="输出 JSON")
    return parser


def main() -> int:
    args = build_parser().parse_args()

    cas: CASClient | None = None
    try:
        cas = _create_cas(args.account)
        if args.command == "energy":
            _energy(cas, args.room)
        else:
            _grades(cas, args.semester, args.json)
        return 0
    except (ZZUError, ValueError) as exc:
        print(f"操作失败: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\n操作已取消。", file=sys.stderr)
        return 130
    finally:
        if cas is not None:
            cas.close()


if __name__ == "__main__":
    raise SystemExit(main())