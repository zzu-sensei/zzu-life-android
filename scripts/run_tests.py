"""运行 scripts/ 下的离线自检。

这些自检不联网、不需要账号，只验证 Python 侧解析逻辑（目前是培养计划页面解析）。
改动 ``flutter-app/android/app/src/main/python/`` 下的解析代码后请先跑它，再构建 APK。

    python scripts/run_tests.py
    python scripts/run_tests.py plan     # 只跑文件名匹配的自检
    python scripts/run_tests.py -v       # 显示完整输出
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent


def discover(keyword: str | None = None) -> list[Path]:
    found = sorted(p for p in SCRIPTS_DIR.glob("test_*.py") if p.is_file())
    if keyword:
        found = [p for p in found if keyword.lower() in p.stem.lower()]
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description="运行所有离线自检")
    parser.add_argument("keyword", nargs="?", help="只跑文件名包含该关键词的自检")
    parser.add_argument("--verbose", "-v", action="store_true", help="显示完整输出")
    args = parser.parse_args()

    cases = discover(args.keyword)
    if not cases:
        print(f"没有找到匹配的自检（关键词：{args.keyword!r}）")
        return 1

    print(f"共 {len(cases)} 个自检\n")
    failures: list[tuple[str, str]] = []
    total = 0.0

    for case in cases:
        started = time.perf_counter()
        completed = subprocess.run(
            [sys.executable, str(case)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        elapsed = time.perf_counter() - started
        total += elapsed
        output = (completed.stdout or "") + (completed.stderr or "")
        ok = completed.returncode == 0
        print(f"  [{'通过' if ok else '失败'}] {case.name:<32} {elapsed:5.2f}s")
        if args.verbose:
            print(output.rstrip())
        if not ok:
            failures.append((case.name, output))

    print()
    if failures:
        print("=" * 72)
        for name, output in failures:
            print(f"\n### {name} 的输出\n")
            print(output.rstrip())
        print("\n" + "=" * 72)

    print(f"结果：{len(cases) - len(failures)}/{len(cases)} 通过，总耗时 {total:.2f}s")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
