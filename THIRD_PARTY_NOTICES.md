# 第三方组件声明

本项目依赖或在 Android 源码中包含以下第三方组件。完整依赖版本见 `uv.lock`、`package-lock.json` 和 `flutter-app/pubspec.lock`。

| 组件 | 用途 | 许可证 | 来源 |
| --- | --- | --- | --- |
| ZZU.Py | 学校服务 API 客户端 | MIT | 本仓库及上游 `Illustar0/ZZU.Py` |
| gmalg | 国密算法实现 | MIT | <https://github.com/ww-rm/gmalg> |
| pycparser | C 语法解析，供 CFFI 使用 | BSD-3-Clause | <https://github.com/eliben/pycparser> |
| Flutter | 客户端框架 | BSD-3-Clause | <https://github.com/flutter/flutter> |
| Chaquopy | Android Python 运行时与构建插件 | 见项目许可证与使用条款 | <https://chaquo.com/chaquopy/> |

Android 源码中随附的 `gmalg` 与 `pycparser` 许可证分别位于对应源码目录的 `LICENSE` 文件。
