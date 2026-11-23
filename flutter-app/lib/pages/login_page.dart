import 'package:flutter/material.dart';

import '../core/native_api.dart';
import '../theme/app_theme.dart';
import '../widgets/miuix_components.dart';

/// 统一身份认证登录页面。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});
  final ValueChanged<String> onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final account = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool showPassword = false;
  String? error;

  @override
  void initState() {
    super.initState();
    account.addListener(_onAccountChanged);
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    account.removeListener(_onAccountChanged);
    account.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final trimmedAccount = account.text.trim();
    if (trimmedAccount.isEmpty || password.text.isEmpty) {
      setState(() => error = '请输入学号和统一认证密码');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await NativeApi.call('beginLogin', {
        'account': trimmedAccount,
        'password': password.text,
      });
      if (!mounted) return;
      if (result['mfa_required'] == true) {
        await _showMfaSheet(trimmedAccount);
      } else {
        password.clear();
        widget.onLogin(trimmedAccount);
      }
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showMfaSheet(String trimmedAccount) async {
    final codeController = TextEditingController();
    var verifying = false;
    var resending = false;
    String? sheetError;

    try {
      final loggedIn = await showMiuixSheet<bool>(
        context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, update) {
            final palette = sheetContext.palette;

            Future<void> submit() async {
              final code = codeController.text.trim();
              if (code.isEmpty) {
                update(() => sheetError = '请输入短信验证码');
                return;
              }
              update(() {
                verifying = true;
                sheetError = null;
              });
              try {
                await NativeApi.call('completeMfa', {'code': code});
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(true);
                }
              } catch (caught) {
                if (sheetContext.mounted) {
                  update(() {
                    verifying = false;
                    sheetError = caught.toString();
                  });
                }
              }
            }

            Future<void> resend() async {
              update(() {
                resending = true;
                sheetError = null;
              });
              try {
                final retry = await NativeApi.call('beginLogin', {
                  'account': trimmedAccount,
                  'password': password.text,
                });
                if (!sheetContext.mounted) return;
                if (retry['mfa_required'] != true) {
                  Navigator.of(sheetContext).pop(true);
                  return;
                }
                update(() {
                  resending = false;
                  codeController.clear();
                });
              } catch (caught) {
                if (sheetContext.mounted) {
                  update(() {
                    resending = false;
                    sheetError = caught.toString();
                  });
                }
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MiuixSheetHeader(
                  title: '短信二次验证',
                  subtitle: '已向统一认证绑定手机发送验证码，请输入以完成登录',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  enabled: !verifying && !resending,
                  onSubmitted: (_) => submit(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.sms_outlined),
                    hintText: '6 位短信验证码',
                  ),
                ),
                if (sheetError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: ShapeDecoration(
                      color: palette.dangerSoft,
                      shape: miuixShape(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: palette.danger,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sheetError!,
                            style: TextStyle(
                              color: palette.danger,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: verifying || resending ? null : resend,
                        child: resending
                            ? const Loader(size: 16)
                            : const Text('重新发送'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: verifying || resending ? null : submit,
                        child: verifying
                            ? const Loader(size: 18, color: Colors.white)
                            : const Text('验证并登录'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      if (loggedIn == true && mounted) {
        password.clear();
        widget.onLogin(trimmedAccount);
      }
    } finally {
      codeController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = context.isDark;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 78,
                    height: 78,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      shape: miuixShape(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4C95FF), Color(0xFF266CEB)],
                      ),
                      shadows: !isDark
                          ? [
                              BoxShadow(
                                color: palette.primary.withValues(alpha: 0.28),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ]
                          : const [],
                    ),
                    child: const Text(
                      '郑',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '郑大生活助手',
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '本机直连学校服务 · 轻量原生客户端',
                    style: TextStyle(
                      color: palette.inkSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 30),
                  MiuixCard(
                    radius: 24,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: account,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          enabled: !busy,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.badge_outlined),
                            hintText: '学号',
                            suffixIcon: account.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: busy ? null : account.clear,
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: password,
                          obscureText: !showPassword,
                          enabled: !busy,
                          onSubmitted: (_) => login(),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            hintText: '统一认证密码',
                            suffixIcon: IconButton(
                              tooltip: showPassword ? '隐藏密码' : '显示密码',
                              onPressed: () =>
                                  setState(() => showPassword = !showPassword),
                              icon: Icon(
                                showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: ShapeDecoration(
                              color: palette.dangerSoft,
                              shape: miuixShape(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: palette.danger,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    error!,
                                    style: TextStyle(
                                      color: palette.danger,
                                      fontSize: 12.5,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed: busy ? null : login,
                            child: busy
                                ? const Loader(size: 20, color: Colors.white)
                                : const Text('安全登录'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: palette.inkMuted,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '密码仅用于本机直连验证，不保存明文',
                        style: TextStyle(
                          color: palette.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
