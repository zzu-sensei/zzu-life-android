# 贡献指南

感谢参与 ZZU.Py / 郑大生活助手。

## 提交前

1. 先搜索现有 Issue，确认问题没有重复。
2. 不要提交真实学号、密码、Token、Cookie、设备标识、宿舍号或含个人信息的抓包数据。
3. 不要绕过学校认证、访问他人数据、批量枚举账号或增加违反学校规定的功能。
4. 修改同步客户端时检查 `zzupy/aio` 的异步实现是否也需要同步。

## 本地检查

Python：

```bash
uv sync --extra develop,docs
uv run python scripts/run_tests.py      # 全部离线自检
uv run python scripts/run_tests.py plan # 只跑名字含 plan 的
uv run ruff check zzupy
uv run ty check zzupy
uv build
```

自检是 `scripts/test_*.py` 下的独立脚本（不用 pytest），`run_tests.py` 会自动发现并
运行。它们**不联网、不需要账号**，改动后请确保全绿再加新功能。

修 bug 时请先让新断言真的失败一次（例如临时改回旧实现），确认测试能抓住问题，
再恢复修复——不会失败的测试没有意义。

需要真实登录的排查脚本放在 `scripts/dev/`，不属于自检范围：

```bash
python scripts/dev/session.py <页面URL>              # 建立会话并抓页面
python scripts/dev/diagnose_plan_page.py <页面文件>   # 离线分析页面结构
```

这些脚本会产生含个人信息与会话凭据的临时文件，**用完请删除，不要提交**。

网页：

```bash
npm ci
npm run build
```

文档用 Zensical 构建（`zensical.toml`）：

```bash
uv run zensical build
```

Android：

```bash
cd flutter-app
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
```

Android 构建需要 JDK 17、Android SDK 35 和 Python 3.12。若 Python 不在 `PATH`，可在本机设置 `CHAQUOPY_BUILD_PYTHON`，不要把本机绝对路径提交到仓库。

签名配置见 `flutter-app/android/keystore.properties.example`：`keystore.properties` 是
gitignored 的，不要提交真实密钥库。**签名密钥一旦更换，已安装用户必须卸载重装
（会丢失应用数据）**，所以请妥善保管，不要重新生成。

手机端 Python（`flutter-app/android/app/src/main/python/`）与主机端 `zzupy` 是**两套
并行实现**，规则必须一致。`zzupy.logging` 依赖 `loguru`，未打包进 App，手机端不要
导入它。修改两端共有的规则时，请加一个把同一份夹具喂给两边、断言结果相同的
一致性测试（参考 `scripts/test_mobile_plan_page.py`）。


## Pull Request

- 每个 PR 聚焦一个问题，说明行为变化、验证方式和可能影响。
- UI 变化请附脱敏截图；接口变化请提供脱敏后的响应结构，不要提供完整响应。
- 新增依赖必须说明用途、许可证和为什么不能使用现有依赖完成。
- 提交即表示你有权贡献相应代码，并同意代码按本仓库 MIT 许可证发布。
