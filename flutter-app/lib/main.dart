import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'core/native_api.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'theme/app_theme.dart';
import 'widgets/miuix_components.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Never expose Flutter's visual debugging overlays in an installable build.
  debugPaintBaselinesEnabled = false;
  debugPaintSizeEnabled = false;
  debugPaintPointersEnabled = false;
  debugRepaintRainbowEnabled = false;
  runApp(const ZzuLifeApp());
}

/// 郑大生活助手 Flutter 根组件。
class ZzuLifeApp extends StatefulWidget {
  const ZzuLifeApp({super.key});

  @override
  State<ZzuLifeApp> createState() => _ZzuLifeAppState();
}

class _ZzuLifeAppState extends State<ZzuLifeApp> {
  final ThemeController _themeController = ThemeController();
  String? _account;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _themeController.load();
    await _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final data = await NativeApi.call('getSession');
      _account = data['logged_in'] == true ? data['account']?.toString() : null;
    } catch (_) {
      _account = null;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    await NativeApi.call('logout');
    if (mounted) setState(() => _account = null);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeController,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '郑大生活助手',
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: themeMode,
          builder: (context, child) {
            // Some devices keep Flutter's baseline overlay after replacing a
            // debug build. Force it off here as well as in main, and never
            // inherit a text underline from the platform theme.
            debugPaintBaselinesEnabled = false;
            final brightness = Theme.of(context).brightness;
            final palette = context.palette;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: systemOverlayStyleFor(brightness, palette),
              child: DefaultTextStyle.merge(
                style: const TextStyle(
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: _loading
              ? const Scaffold(body: Center(child: Loader()))
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  child: _account == null
                      ? LoginPage(
                          key: const ValueKey('login'),
                          onLogin: (value) => setState(() => _account = value),
                        )
                      : HomeShell(
                          key: const ValueKey('home'),
                          account: _account!,
                          themeController: _themeController,
                          onLogout: _logout,
                        ),
                ),
        );
      },
    );
  }
}
