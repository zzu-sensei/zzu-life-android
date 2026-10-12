# 郑大生活助手（Android）

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.5-54C5F8.svg)](flutter-app/README.md)

郑州大学生活助手安卓客户端。Flutter 负责界面，业务逻辑用 Chaquopy 内嵌的
Python 3.12 实现，所有请求都从手机直接发往学校服务，不经过自建服务器。

> [!IMPORTANT]
> 本项目由社区独立维护，与郑州大学及相关服务提供方无隶属或授权关系。接口可能随学校系统调整而失效；请仅在本人账号和授权范围内使用，并遵守学校规定。

## 功能

| 功能 | 说明 |
| --- | --- |
| 成绩 | 按学期查看成绩与绩点，可导出成绩单、成绩排名并打印 |
| 考试 | 按学期查看考试时间、地点、座位号与考试类型（底部「学习」入口） |
| 培养计划 | 从教务读取官方学分要求与完成情况；按学期展示课程、成绩、绩点，另有按学分模块视图 |
| 课表 | 今日课程、周课表，支持导出 ICS 日历 |
| 电费 | 宿舍电量查询、低电量提醒（本地通知 + 邮件）、耗电速度估算 |
| 校园网 | 账户余额/流量/同时在线上限、在线设备与登录历史（需在校园网内，每次输入网络密码；入口在顶部「更多」菜单） |
| 桌面小组件 | 课表 / 电量组件，长按桌面空白处手动添加；App 内不再提供一键添加入口（顶部「更多」菜单有一行提示） |
| 更新提醒 | 每 48 小时静默检查一次新版本；发现新版本时发一条通知，点开可下载安装（顶部「更多」菜单里也能手动检查） |
| 后台监测 | 成绩变化与电量预警按用户设置定时检查 |

> [!WARNING]
> 当前仅适配本科教务新系统，研究生教务暂未支持。

## 环境

- Flutter 3.47.5（stable，Dart 3.13.4）
- JDK 17
- Android SDK 35（`compileSdk 35`，`minSdk 26`，仅构建 `arm64-v8a`）
- Python **3.12**——Chaquopy 构建时需要，`PATH` 里没有就设置 `CHAQUOPY_BUILD_PYTHON`

## 开发检查

```bash
python scripts/run_tests.py      # Python 侧解析逻辑的离线自检（不联网、不需要账号）
cd flutter-app
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
```

## 签名

`flutter-app/android/keystore.properties` 是 gitignored 的，模板见
`keystore.properties.example`。**密钥库要妥善保管**：换一个密钥签出来的包无法覆盖
安装已有版本，用户必须卸载重装，应用数据会丢失。文件缺失时 Gradle 会退回 debug
签名，构建仍可用。

## 发布 APK

推送 `v*` 标签即触发 [Build APK](.github/workflows/build-apk.yaml)：构建、跑
`flutter analyze`、把 APK 附到 GitHub Release 供下载。也可以在 Actions 页面手动触发
并填标签名。

想让 CI 产出的包与本地一致，需要配置这些 Secrets（不配也能构建，只是用 debug 签名）：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 密钥库文件的 base64（`base64 -w0 xxx.keystore`） |
| `ANDROID_STORE_PASSWORD` | 密钥库口令 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥口令 |

> `release/` 与 `*.apk` 都在 `.gitignore` 里，APK **不进版本库**，通过 Release 附件分发。

## 数据与安全

- 统一认证密码不落盘；会话令牌用 Android Keystore 加密后存储。
- 业务逻辑全部在手机本地执行，不上传账号、成绩、电量等数据到第三方。
- 邮件发信使用你自己的发信服务 API Key，密钥只存本机。

## 许可证

MIT，见 [LICENSE](LICENSE)。隐私与安全说明见 [PRIVACY.md](PRIVACY.md)、
[SECURITY.md](SECURITY.md)。
