import 'dart:convert';

import 'package:flutter/services.dart';

/// 原生平台通道调用封装。
///
/// 所有校园接口请求都在 Android 原生侧（Chaquopy Python / Java）执行，Flutter 层
/// 仅通过 `MethodChannel` 交换 JSON 字符串。
class NativeApi {
  static const MethodChannel channel = MethodChannel('cn.edu.zzu.life/api');

  static Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    try {
      final raw = await channel.invokeMethod<String>(method, arguments);
      final data = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw ApiException((data['error'] ?? '请求失败').toString());
      }
      return data;
    } on PlatformException catch (error) {
      throw ApiException(error.message ?? '本地服务调用失败');
    }
  }
}

/// 原生通道或远端接口返回的业务异常。
class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
