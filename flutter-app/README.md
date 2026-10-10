# 郑大生活助手（Flutter）

这是 ZZU.Py 的 Android 客户端，所有学校接口均由手机本地直接访问，不依赖已部署的网站。

## 环境

- Flutter 3.47.5 / Dart 3.13.4
- JDK 17
- Python 3.12（供 Chaquopy 构建）
- Android SDK 35，最低支持 Android 8.0（API 26）

若 Python 3.12 不在 `PATH`，请先设置 `CHAQUOPY_BUILD_PYTHON` 为解释器的绝对路径。该变量只在本机生效，不应提交到仓库。

## 开发检查

```bash
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
```

当前默认构建仅包含 `arm64-v8a`。未配置发布密钥时，项目会沿用调试证书，适合开发和侧载测试，不适合应用商店发布。

## 数据与安全

- 统一认证密码不落盘；会话令牌使用 Android Keystore 支持的加密存储。
- 电费支付密码仅用于当次请求，不保存。
- 成绩监测和电量预警由 Android 后台任务按用户设置发起。
- 低电量邮件：手机把读数 POST 到你自建的转发端点，由该端点调用发信服务。
  **手机上只保存端点地址与共享密钥，不保存邮件服务商的 API Key**。
- 邮件功能需要你自己部署转发端点（本仓库不再包含该端点的实现）。
- 提交问题时请勿上传学号、密码、Token、完整响应或包含个人信息的截图。

完整说明见仓库根目录的 `README.md`、`PRIVACY.md` 与 `SECURITY.md`。
