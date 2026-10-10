"""CI 签名步骤的自检：base64 清洗逻辑必须容错，且能拒绝真正的垃圾输入。

这不是可有可无的测试。2026-10 的一次发布就是因为从终端复制 3492 字符的
base64 时带进了折行，GNU `base64 -d` 直接报 `invalid input`，整个构建失败，
而 GitHub 上的报错只有这一行、看不出原因。之后 workflow 里加了
`tr -d '[:space:]'`，这个脚本负责守住它。

用 Git Bash 跑（本机无 WSL 发行版）：

    python scripts/test_ci_signing.py
"""

from __future__ import annotations

import base64
import os
import subprocess
import sys
from pathlib import Path

#: 密钥库默认位置；可用 ZZU_KEYSTORE 覆盖。
KEYSTORE = Path(os.environ.get("ZZU_KEYSTORE", r"E:\dev-tools\keys\zzu-life-debug.keystore"))

BASH_CANDIDATES = [
    r"C:\Program Files\Git\bin\bash.exe",
    r"C:\Program Files\Git\usr\bin\bash.exe",
]

#: 与 .github/workflows/build-apk.yaml 的 Prepare signing key 保持一致的逻辑。
WORKFLOW_SCRIPT = r"""
if [ -z "$KEYSTORE_BASE64" ]; then
  echo "NO_SECRET"
  exit 0
fi
cleaned="$(printf '%s' "$KEYSTORE_BASE64" | tr -d '[:space:]')"
if ! printf '%s' "$cleaned" | base64 -d > "$OUT" 2>/dev/null; then
  echo "DECODE_FAILED raw=${#KEYSTORE_BASE64} cleaned=${#cleaned}"
  exit 1
fi
if [ ! -s "$OUT" ]; then
  echo "EMPTY"
  exit 1
fi
echo "OK $(wc -c < "$OUT")"
"""


def find_bash() -> str:
    for path in BASH_CANDIDATES:
        if Path(path).is_file():
            return path
    raise SystemExit("未找到 Git Bash；本测试需要 GNU bash 与 coreutils")


def run(script: str, value: str, out_file: Path) -> str:
    env = dict(os.environ)
    env["KEYSTORE_BASE64"] = value
    env["OUT"] = str(out_file)
    result = subprocess.run(
        [find_bash(), "-c", script],
        capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
    )
    return (result.stdout or "").strip()


def main() -> int:
    if not KEYSTORE.is_file():
        print(f"找不到密钥库: {KEYSTORE}（可用 ZZU_KEYSTORE 指定）")
        return 2

    raw = KEYSTORE.read_bytes()
    clean = base64.b64encode(raw).decode("ascii")
    out = Path(os.environ.get("TEMP", "/tmp")) / "zzu-ci-signing-check.keystore"
    print(f"密钥库 {len(raw)} 字节 -> base64 {len(clean)} 字符\n")

    expected = f"OK {len(raw)}"

    # 各种「粘贴事故」都必须被容忍：它们曾被真实触发过。
    tolerated = {
        "干净": clean,
        "尾部换行": clean + "\n",
        "CRLF 折行（从终端复制）":
            "\r\n".join(clean[i:i + 76] for i in range(0, len(clean), 76)) + "\r\n",
        "LF 折行": "\n".join(clean[i:i + 76] for i in range(0, len(clean), 76)) + "\n",
        "中间夹空格": clean[:100] + " " + clean[100:],
        "尾部多余空格": clean + "   ",
    }

    failed = 0
    for label, value in tolerated.items():
        output = run(WORKFLOW_SCRIPT, value, out)
        ok = output == expected
        failed += 0 if ok else 1
        print(f"  [{'通过' if ok else '失败'}] {label:<26} -> {output}")

    # 未配置 secret 时应安全退出，而不是让构建挂掉。
    output = run(WORKFLOW_SCRIPT, "", out)
    ok = output == "NO_SECRET"
    failed += 0 if ok else 1
    print(f"  [{'通过' if ok else '失败'}] 未配置 secret 应安全跳过      -> {output}")

    # 真正的垃圾输入必须被明确拒绝，而不是解出半截文件。
    output = run(WORKFLOW_SCRIPT, "这不是 base64！！！", out)
    ok = output.startswith("DECODE_FAILED")
    failed += 0 if ok else 1
    print(f"  [{'通过' if ok else '失败'}] 非法输入应被拒绝              -> {output}")

    print()
    if failed:
        print(f"{failed} 个用例未通过")
        return 1
    print("CI 签名步骤的 base64 清洗逻辑全部通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
