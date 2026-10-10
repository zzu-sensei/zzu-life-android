import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

const ink = Color(0xFFF2FFF9);
const muted = Color(0xFFA9C9BC);
const mint = Color(0xFF83F0BF);
const aqua = Color(0xFF6AE4E7);
const deep = Color(0xFF061E1A);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Never expose Flutter's visual debugging overlays in an installable build.
  debugPaintBaselinesEnabled = false;
  debugPaintSizeEnabled = false;
  debugPaintPointersEnabled = false;
  debugRepaintRainbowEnabled = false;
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF071B18),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ZzuLifeApp());
}

class NativeApi {
  static const channel = MethodChannel('cn.edu.zzu.life/api');

  static Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    try {
      final raw = await channel.invokeMethod<String>(method, arguments);
      final data = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      if (data['ok'] != true)
        throw ApiException((data['error'] ?? '请求失败').toString());
      return data;
    } on PlatformException catch (error) {
      throw ApiException(error.message ?? '本地服务调用失败');
    }
  }
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ZzuLifeApp extends StatefulWidget {
  const ZzuLifeApp({super.key});
  @override
  State<ZzuLifeApp> createState() => _ZzuLifeAppState();
}

class _ZzuLifeAppState extends State<ZzuLifeApp> {
  String? account;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      final data = await NativeApi.call('getSession');
      account = data['logged_in'] == true ? data['account']?.toString() : null;
    } catch (_) {
      account = null;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> logout() async {
    await NativeApi.call('logout');
    if (mounted) setState(() => account = null);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '郑大生活助手',
    builder: (context, child) {
      // Some devices keep Flutter's baseline overlay after replacing a debug
      // build. Force it off here as well as in main, and never inherit a text
      // underline from the platform theme.
      debugPaintBaselinesEnabled = false;
      return DefaultTextStyle.merge(
        style: const TextStyle(
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: child ?? const SizedBox.shrink(),
      );
    },
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: mint,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .08),
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .13)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: mint, width: 1.5),
        ),
      ),
    ),
    home: loading
        ? const LiquidBackground(child: Center(child: Loader()))
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: account == null
                ? LoginPage(
                    key: const ValueKey('login'),
                    onLogin: (value) => setState(() => account = value),
                  )
                : HomeShell(
                    key: const ValueKey('home'),
                    account: account!,
                    onLogout: logout,
                  ),
          ),
  );
}

class LiquidBackground extends StatefulWidget {
  const LiquidBackground({super.key, required this.child});
  final Widget child;
  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: deep,
    child: Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF082A25), Color(0xFF061713), Color(0xFF0A2522)],
            ),
          ),
        ),
        AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            final value = controller.value;
            return Stack(
              children: [
                Positioned(
                  top: -95 + value * 35,
                  right: -80,
                  child: const GlowOrb(280, Color(0x6656F0BA)),
                ),
                Positioned(
                  top: 330 - value * 42,
                  left: -150 + value * 30,
                  child: const GlowOrb(330, Color(0x4D21B8C7)),
                ),
                Positioned(
                  bottom: -170 + value * 28,
                  right: -130,
                  child: const GlowOrb(360, Color(0x3D8D74FF)),
                ),
              ],
            );
          },
        ),
        widget.child,
      ],
    ),
  );
}

class GlowOrb extends StatelessWidget {
  const GlowOrb(this.size, this.color, {super.key});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 26,
    this.tint,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? tint;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: .17)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              (tint ?? Colors.white).withValues(alpha: .16),
              Colors.white.withValues(alpha: .05),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

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
  String? error;

  @override
  void dispose() {
    account.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (account.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = '请输入学号和统一认证密码');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await NativeApi.call('beginLogin', {
        'account': account.text.trim(),
        'password': password.text,
      });
      password.clear();
      if (result['mfa_required'] == true) {
        await showMfa();
      } else {
        widget.onLogin(account.text.trim());
      }
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showMfa() async {
    final code = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xF012332D),
        title: const Text('短信验证'),
        content: TextField(
          controller: code,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: '短信验证码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('验证'),
          ),
        ],
      ),
    );
    if (accepted != true || code.text.trim().isEmpty) return;
    await NativeApi.call('completeMfa', {'code': code.text.trim()});
    widget.onLogin(account.text.trim());
  }

  @override
  Widget build(BuildContext context) => LiquidBackground(
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [mint, aqua]),
                    boxShadow: [
                      BoxShadow(
                        color: mint.withValues(alpha: .35),
                        blurRadius: 36,
                      ),
                    ],
                  ),
                  child: const Text(
                    '郑',
                    style: TextStyle(
                      color: deep,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '郑大生活助手',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Flutter 原生界面 · 本机直连学校服务',
                  style: TextStyle(color: muted, fontSize: 14),
                ),
                const SizedBox(height: 34),
                GlassPanel(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      TextField(
                        controller: account,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.badge_outlined),
                          hintText: '学号',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: password,
                        obscureText: true,
                        onSubmitted: (_) => login(),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.lock_outline),
                          hintText: '统一认证密码',
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            error!,
                            style: const TextStyle(
                              color: Color(0xFFFF9E94),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: busy ? null : login,
                          style: FilledButton.styleFrom(
                            backgroundColor: mint,
                            foregroundColor: deep,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: busy
                              ? const Loader(size: 22)
                              : const Text(
                                  '安全登录',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, color: muted, size: 16),
                    SizedBox(width: 6),
                    Text(
                      '密码不保存，数据不经过部署网站',
                      style: TextStyle(color: muted, fontSize: 12),
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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.account, required this.onLogout});
  final String account;
  final Future<void> Function() onLogout;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 1;

  Future<void> confirmLogout() async {
    final continueLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后需要重新输入学号和密码。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (continueLogout != true || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('再次确认'),
        content: const Text('确定退出当前账号？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const GradesHubPage(),
      const SchedulePage(),
      const EnergyPage(),
      const WidgetsPage(),
    ];
    return LiquidBackground(
      child: Scaffold(
        extendBody: false,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [mint, aqua]),
                        boxShadow: [
                          BoxShadow(
                            color: mint.withValues(alpha: .22),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: const Text(
                        '郑',
                        style: TextStyle(
                          color: deep,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ZZU LIFE',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3,
                            ),
                          ),
                          Text(
                            '${widget.account} · 本机直连',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: confirmLogout,
                      icon: const Icon(Icons.logout_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(index: index, children: pages),
              ),
            ],
          ),
        ),
        bottomNavigationBar: GlassNavigation(
          index: index,
          onChanged: (value) => setState(() => index = value),
        ),
      ),
    );
  }
}

class GlassNavigation extends StatelessWidget {
  const GlassNavigation({
    super.key,
    required this.index,
    required this.onChanged,
  });
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.school_outlined, Icons.school_rounded, '成绩'),
      (Icons.calendar_month_outlined, Icons.calendar_month_rounded, '课表'),
      (Icons.bolt_outlined, Icons.bolt_rounded, '电费'),
      (Icons.widgets_outlined, Icons.widgets_rounded, '组件'),
    ];
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: GlassPanel(
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: List.generate(items.length, (i) {
            final selected = i == index;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: selected
                        ? LinearGradient(
                            colors: [
                              mint.withValues(alpha: .24),
                              aqua.withValues(alpha: .13),
                            ],
                          )
                        : null,
                    border: selected
                        ? Border.all(color: mint.withValues(alpha: .27))
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected ? items[i].$2 : items[i].$1,
                        color: selected ? mint : muted,
                        size: 22,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[i].$3,
                        style: TextStyle(
                          color: selected ? ink : muted,
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  color: mint,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class GradesPage extends StatefulWidget {
  const GradesPage({super.key});
  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = true;
  bool monitorSaving = false;
  bool printing = false;
  bool gradeMonitorEnabled = false;
  int gradeIntervalMinutes = 720;
  String lastGradeCheck = '';
  String lastGradeMessage = '尚未检查';
  String? semesterFilter;
  @override
  void initState() {
    super.initState();
    load();
    loadMonitorSettings();
  }

  Future<void> loadMonitorSettings() async {
    try {
      final settings = await NativeApi.call('getMonitorSettings');
      if (!mounted) return;
      setState(() {
        gradeMonitorEnabled = settings['grade_enabled'] == true;
        gradeIntervalMinutes =
            (settings['grade_interval_minutes'] as num?)?.toInt() ?? 720;
        lastGradeCheck = (settings['last_grade_check'] ?? '').toString();
        lastGradeMessage = (settings['last_grade_message'] ?? '尚未检查')
            .toString();
      });
    } catch (_) {}
  }

  Future<void> saveGradeMonitor({bool? enabled, int? minutes}) async {
    setState(() {
      if (enabled != null) gradeMonitorEnabled = enabled;
      if (minutes != null) gradeIntervalMinutes = minutes;
      monitorSaving = true;
    });
    try {
      await NativeApi.call('saveMonitorSettings', {
        'grade_enabled': gradeMonitorEnabled,
        'grade_interval_minutes': gradeIntervalMinutes,
      });
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(caught.toString())));
      }
    }
    if (mounted) setState(() => monitorSaving = false);
  }

  Future<void> checkGradesNow() async {
    setState(() => monitorSaving = true);
    try {
      final result = await NativeApi.call('checkGradesNow');
      await loadMonitorSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((result['message'] ?? '检查完成').toString())),
        );
      }
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(caught.toString())));
      }
    }
    if (mounted) setState(() => monitorSaving = false);
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      data = await NativeApi.call('getGrades');
    } catch (caught) {
      error = caught.toString();
    }
    if (mounted) setState(() => loading = false);
  }


  Future<void> printGradeDocument(String method) async {
    setState(() => printing = true);
    try {
      final document = await NativeApi.call(method);
      final result = await NativeApi.call('printDocument', {
        'name': (document['name'] ?? '郑大成绩文档').toString(),
        'mime_type': (document['mime_type'] ?? '').toString(),
        'content_base64': (document['content_base64'] ?? '').toString(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((result['message'] ?? '已打开打印服务').toString())),
        );
      }
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(caught.toString())));
      }
    }
    if (mounted) setState(() => printing = false);
  }

  @override
  Widget build(BuildContext context) {
    final grades = ((data?['grades'] as List?) ?? const []).cast<Map>();
    final groups = <String, List<Map>>{};
    for (final grade in grades) {
      final semester = (grade['semester'] ?? '未标注学期').toString();
      groups.putIfAbsent(semester, () => []).add(grade);
    }
    final semesters = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    if (semesterFilter != null && !groups.containsKey(semesterFilter)) {
      semesterFilter = null;
    }
    final visibleSemesters = semesterFilter == null
        ? semesters
        : <String>[semesterFilter!];
    return Column(
      children: [
        PageHeader(
          eyebrow: 'Academic',
          title: '学业成绩',
          subtitle: '按学期整理，成绩来自本科教务',
          action: IconButton.filledTonal(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: Loader())
              : error != null
              ? ErrorState(message: error!, retry: load)
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      GlassPanel(
                        tint: mint,
                        child: Row(
                          children: [
                            Expanded(
                              child: Metric(
                                label: '累计参考绩点',
                                value: data?['gpa'] == null
                                    ? '--'
                                    : fixed4(data!['gpa']),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 46,
                              color: Colors.white.withValues(alpha: .15),
                            ),
                            Expanded(
                              child: Metric(
                                label: '计入学分',
                                value: number(data?['credits'] ?? 0),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: printing
                                  ? null
                                  : () => printGradeDocument(
                                      'getTranscriptDocument',
                                    ),
                              icon: const Icon(Icons.print_rounded, size: 19),
                              label: const Text('打印成绩表'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: printing
                                  ? null
                                  : () => printGradeDocument(
                                      'getGradeRankDocument',
                                    ),
                              icon: const Icon(
                                Icons.leaderboard_rounded,
                                size: 19,
                              ),
                              label: const Text('打印排名'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GlassPanel(
                        radius: 22,
                        padding: const EdgeInsets.all(15),
                        tint: gradeMonitorEnabled ? aqua : null,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: aqua.withValues(alpha: .14),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.notifications_active_outlined,
                                    color: aqua,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '成绩监测',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        lastGradeCheck.isEmpty
                                            ? lastGradeMessage
                                            : '$lastGradeMessage · $lastGradeCheck',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: gradeMonitorEnabled,
                                  onChanged: monitorSaving
                                      ? null
                                      : (value) =>
                                            saveGradeMonitor(enabled: value),
                                ),
                              ],
                            ),
                            if (gradeMonitorEnabled) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Text(
                                    '检查频率',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  DropdownButton<int>(
                                    value: gradeIntervalMinutes,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 15,
                                        child: Text('每 15 分钟'),
                                      ),
                                      DropdownMenuItem(
                                        value: 30,
                                        child: Text('每 30 分钟'),
                                      ),
                                      DropdownMenuItem(
                                        value: 60,
                                        child: Text('每 1 小时'),
                                      ),
                                      DropdownMenuItem(
                                        value: 180,
                                        child: Text('每 3 小时'),
                                      ),
                                      DropdownMenuItem(
                                        value: 360,
                                        child: Text('每 6 小时'),
                                      ),
                                      DropdownMenuItem(
                                        value: 720,
                                        child: Text('每 12 小时'),
                                      ),
                                      DropdownMenuItem(
                                        value: 1440,
                                        child: Text('每天'),
                                      ),
                                    ],
                                    onChanged: monitorSaving
                                        ? null
                                        : (value) {
                                            if (value != null) {
                                              saveGradeMonitor(minutes: value);
                                            }
                                          },
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: monitorSaving
                                        ? null
                                        : checkGradesNow,
                                    icon: monitorSaving
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.manage_search_rounded,
                                            size: 18,
                                          ),
                                    label: const Text('立即检查'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (semesters.length > 1) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: const Text('全部学期'),
                                  selected: semesterFilter == null,
                                  onSelected: (_) =>
                                      setState(() => semesterFilter = null),
                                ),
                              ),
                              for (final semester in semesters)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(semester),
                                    selected: semesterFilter == semester,
                                    onSelected: (_) => setState(
                                      () => semesterFilter = semester,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      for (final semester in visibleSemesters) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  semester,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              GlassTag('${groups[semester]!.length} 门'),
                            ],
                          ),
                        ),
                        for (final grade in groups[semester]!) ...[
                          GradeCard(grade),
                          const SizedBox(height: 10),
                        ],
                      ],
                      if (grades.isEmpty)
                        const EmptyState(Icons.school_outlined, '暂未查询到成绩'),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class GradeCard extends StatefulWidget {
  const GradeCard(this.grade, {super.key});
  final Map grade;

  @override
  State<GradeCard> createState() => _GradeCardState();
}

class _GradeCardState extends State<GradeCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final grade = widget.grade;
    final components = ((grade['components'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    if (components.isEmpty) {
      components.addAll([
        {'label': '平时成绩', 'value': grade['usual_score']},
        {'label': '卷面成绩', 'value': grade['paper_score']},
        {'label': '最终成绩', 'value': grade['score']},
      ]);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => expanded = !expanded),
      child: GlassPanel(
        radius: 20,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 49,
                  height: 49,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: mint.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    (grade['score'] ?? '--').toString(),
                    style: const TextStyle(
                      color: mint,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (grade['course'] ?? '未知课程').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${number(grade['credits'] ?? 0)} 学分  ·  绩点 ${grade['gp'] == null ? '--' : number(grade['gp'])}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? .5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: muted,
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: expanded
                  ? Column(
                      children: [
                        const SizedBox(height: 14),
                        Divider(color: Colors.white.withValues(alpha: .12)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final component in components)
                              Container(
                                constraints: const BoxConstraints(minWidth: 88),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .055),
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .08),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (component['label'] ?? '成绩分项').toString(),
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      fallback(component['value'], '--'),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
/// 「成绩」入口的双标签容器：成绩 / 培养计划。
///
/// 不往底部导航加第 5 个标签（窄屏会挤），而是把这个入口做成两个子页面。
class GradesHubPage extends StatefulWidget {
  const GradesHubPage({super.key});
  @override
  State<GradesHubPage> createState() => _GradesHubPageState();
}

class _GradesHubPageState extends State<GradesHubPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: GlassPanel(
            radius: 20,
            padding: const EdgeInsets.all(5),
            child: Row(
              children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () => setState(() => tab = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: tab == i
                              ? LinearGradient(
                                  colors: [
                                    mint.withValues(alpha: .26),
                                    aqua.withValues(alpha: .14),
                                  ],
                                )
                              : null,
                        ),
                        child: Text(
                          i == 0 ? '成绩' : '培养计划',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: tab == i ? ink : muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: tab,
            children: const [GradesPage(), ProgramPlanPage()],
          ),
        ),
      ],
    );
  }
}

/// 培养计划完成情况（独立页面）。
///
/// 数据来自教务「培养计划完成情况预览」，学分与完成度都是教务给出的官方口径，
/// 不再自行统计成绩。
class ProgramPlanPage extends StatefulWidget {
  const ProgramPlanPage({super.key});
  @override
  State<ProgramPlanPage> createState() => _ProgramPlanPageState();
}

class _ProgramPlanPageState extends State<ProgramPlanPage> {
  Map<String, dynamic>? plan;
  bool loading = true;
  String? error;

  /// 0 = 按学期，1 = 按学分模块。
  int viewMode = 0;

  /// 展开的学期序号（默认展开第一个有未通过/在修的学期）。
  final Set<int> expandedSemesters = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await NativeApi.call('getProgramPlan');
      if (!mounted) return;
      setState(() {
        plan = result;
        // 默认展开最早一个还有未通过/在修的学期，其余收起，避免一屏太长。
        expandedSemesters.clear();
        for (final semester in ((result['semesters'] as List?) ?? const [])
            .whereType<Map>()) {
          final pending =
              ((semester['failed_count'] as num?)?.toInt() ?? 0) +
              ((semester['taking_count'] as num?)?.toInt() ?? 0);
          if (pending > 0) {
            expandedSemesters.add((semester['semester'] as num?)?.toInt() ?? 0);
            break;
          }
        }
      });
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final modules = ((plan?['modules'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final semesters = ((plan?['semesters'] as List?) ?? const [])
        .whereType<Map>()
        .toList();

    return Column(
      children: [
        PageHeader(
          eyebrow: 'Training Plan',
          title: '培养计划',
          subtitle: plan == null
              ? '从教务读取官方学分要求与计划课程'
              : '已通过 ${number(plan!['passed_credits'])} / '
                    '${number(plan!['required_credits'])} 学分',
          action: IconButton.filledTonal(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: Loader())
              : error != null
              ? ErrorState(message: error!, retry: load)
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _planSummaryCard(),
                      const SizedBox(height: 14),
                      _viewSwitch(),
                      const SizedBox(height: 12),
                      if (viewMode == 1) ...[
                        for (final module in modules) ...[
                          _moduleCard(module),
                          const SizedBox(height: 10),
                        ],
                      ] else if (semesters.isEmpty)
                        const GlassPanel(
                          radius: 20,
                          padding: EdgeInsets.all(16),
                          child: Text(
                            '教务没有返回带学期的课程信息。',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        )
                      else
                        for (final semester in semesters) ...[
                          _semesterCard(semester),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _viewSwitch() {
    const labels = ['按学期', '按学分模块'];
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => viewMode = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: viewMode == i
                        ? LinearGradient(
                            colors: [
                              mint.withValues(alpha: .26),
                              aqua.withValues(alpha: .14),
                            ],
                          )
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: viewMode == i ? ink : muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _semesterCard(Map semester) {
    final term = (semester['semester'] as num?)?.toInt() ?? 0;
    final courses = ((semester['courses'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final expanded = expandedSemesters.contains(term);
    final averageGp = semester['average_gp'];
    final failedCount = (semester['failed_count'] as num?)?.toInt() ?? 0;
    final takingCount = (semester['taking_count'] as num?)?.toInt() ?? 0;
    final passedCount = (semester['passed_count'] as num?)?.toInt() ?? 0;

    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(14),
      tint: failedCount > 0
          ? const Color(0xFFFF796D)
          : takingCount > 0
          ? aqua
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                expandedSemesters.remove(term);
              } else {
                expandedSemesters.add(term);
              }
            }),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (semester['label'] ?? '未标注学期').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          '${courses.length} 门',
                          '已通过 ${number(semester['earned_credits'])} 学分',
                          if (failedCount > 0) '未通过 $failedCount',
                          if (takingCount > 0) '在修 $takingCount',
                        ].join(' · '),
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (averageGp != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          number(averageGp),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          // 标出参与平均的学分数，让「按学分加权」这件事可见，
                          // 否则用户会以为是无权重平均。
                          '平均绩点 · ${number(semester['graded_credits'])} 学分',
                          style: const TextStyle(color: muted, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: muted,
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < courses.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 14,
                  color: Colors.white.withValues(alpha: .07),
                ),
              _courseRow(courses[i]),
            ],
          ] else if (passedCount == courses.length && courses.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '该学期全部通过',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _courseRow(Map course) {
    final status = (course['status'] ?? 'unknown').toString();
    final gp = course['gp'];
    final score = (course['score'] ?? '').toString();
    final color = status == 'failed'
        ? const Color(0xFFFF9E94)
        : status == 'taking'
        ? aqua
        : ink;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 26,
            margin: const EdgeInsets.only(right: 9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (course['name'] ?? '未知课程').toString(),
                  style: const TextStyle(fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${number(course['credits'])} 学分',
                    if ((course['module'] ?? '').toString().isNotEmpty)
                      (course['module'] ?? '').toString(),
                    if (status == 'taking') '在修',
                    if (status == 'failed') '未通过',
                  ].join(' · '),
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                score.isEmpty ? '--' : score,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                gp == null ? '绩点 --' : '绩点 ${number(gp)}',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planSummaryCard() {
    final required = (plan?['required_credits'] as num?)?.toDouble() ?? 0;
    final passed = (plan?['passed_credits'] as num?)?.toDouble() ?? 0;
    final taking = (plan?['taking_credits'] as num?)?.toDouble() ?? 0;
    final failedCredits = (plan?['failed_credits'] as num?)?.toDouble() ?? 0;
    final missing = (plan?['missing'] as num?)?.toDouble() ?? 0;
    final ratio = required <= 0 ? 0.0 : (passed / required).clamp(0.0, 1.0);

    return GlassPanel(
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                number(passed),
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 4),
                child: Text(
                  '/ ${number(required)} 学分',
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ),
              const Spacer(),
              Text(
                '${(ratio * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: .08),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '还差 ${number(missing)} 学分',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          if (taking > 0 || failedCredits > 0) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (taking > 0) '在修 ${number(taking)}',
                if (failedCredits > 0) '未通过 ${number(failedCredits)}',
              ].join('，') +
                  ' 学分未计入已通过',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _moduleCard(Map module) {
    final required = (module['required_credits'] as num?)?.toDouble() ?? 0;
    final passed = (module['passed_credits'] as num?)?.toDouble() ?? 0;
    final taking = (module['taking_credits'] as num?)?.toDouble() ?? 0;
    final missing = (module['missing'] as num?)?.toDouble() ?? 0;
    final done = module['done'] == true;
    final ratio = required <= 0 ? 1.0 : (passed / required).clamp(0.0, 1.0);
    final note = (module['note'] ?? '').toString();

    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(14),
      tint: done ? mint : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (module['name'] ?? '模块').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                done ? '已达标' : '还差 ${number(missing)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: done ? deep : const Color(0xFFFF9E94),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: .08),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${number(passed)} / ${number(required)} 学分',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              if (taking > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '在修 ${number(taking)}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}


class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  int week = 0;
  int currentWeek = 0;
  bool loading = true;
  bool showExperiments = true;
  bool exporting = false;
  String? error;
  List<Map> lessons = const [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load([int? target]) async {
    setState(() {
      loading = true;
      error = null;
      if (target != null) week = target;
    });
    try {
      final result = await NativeApi.call('getSchedule', {
        'week': week,
        'semester_id': 0,
      });
      week = (result['week'] as num?)?.toInt() ?? 1;
      if (currentWeek == 0) currentWeek = week;
      lessons = ((result['lessons'] as List?) ?? const []).cast<Map>();
    } catch (caught) {
      error = caught.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> selectWeek() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: GlassPanel(
            radius: 30,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '选择教学周',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (currentWeek > 0)
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context, currentWeek),
                        icon: const Icon(Icons.today_rounded, size: 18),
                        label: const Text('当前周'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.45,
                  ),
                  itemCount: 30,
                  itemBuilder: (context, index) {
                    final value = index + 1;
                    final selected = value == week;
                    final current = value == currentWeek;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(context, value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? mint
                              : current
                              ? mint.withValues(alpha: .16)
                              : Colors.white.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current
                                ? mint.withValues(alpha: .65)
                                : Colors.white.withValues(alpha: .09),
                          ),
                        ),
                        child: Text(
                          '$value',
                          style: TextStyle(
                            color: selected ? deep : ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null && selected != week) await load(selected);
  }

  void showLesson(Map lesson) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: GlassPanel(
            radius: 28,
            padding: const EdgeInsets.all(22),
            tint: courseColor((lesson['course'] ?? '').toString()),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (lesson['course'] ?? '未知课程').toString(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (lesson['is_experiment'] == true) const GlassTag('实验'),
                  ],
                ),
                const SizedBox(height: 18),
                IconText(
                  Icons.schedule_rounded,
                  '${lesson['start_time'] ?? ''}–${lesson['end_time'] ?? ''} · 第 ${lesson['start_unit'] ?? ''}–${lesson['end_unit'] ?? ''} 节',
                ),
                const SizedBox(height: 12),
                IconText(
                  Icons.location_on_outlined,
                  fallback(lesson['place'], '地点未定'),
                ),
                const SizedBox(height: 12),
                IconText(
                  Icons.person_outline_rounded,
                  fallback(lesson['teacher'], '教师未定'),
                ),
                if (fallback(lesson['code'], '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  IconText(Icons.tag_rounded, fallback(lesson['code'], '')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> exportAllSchedule() async {
    setState(() => exporting = true);
    try {
      final exported = await NativeApi.call('exportSchedule');
      final saved = await NativeApi.call('saveFile', {
        'filename': (exported['filename'] ?? '郑大课表.ics').toString(),
        'content': (exported['content'] ?? '').toString(),
      });
      if (mounted && saved['cancelled'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${saved['message'] ?? '完整课表已保存'} · ${exported['count'] ?? 0} 节课',
            ),
          ),
        );
      }
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(caught.toString())));
      }
    }
    if (mounted) setState(() => exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final visibleLessons = showExperiments
        ? lessons
        : lessons.where((lesson) => lesson['is_experiment'] != true).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: GlassPanel(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                IconButton(
                  onPressed: loading
                      ? null
                      : () => load((week - 1).clamp(1, 30)),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: loading ? null : selectWeek,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              Text(
                                '第 $week 周',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                              Text(
                                week == currentWeek ? '当前教学周' : '点按快速选择',
                                style: const TextStyle(
                                  color: mint,
                                  fontSize: 9,
                                  letterSpacing: .5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: loading ? null : () => load(week + 1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                IconButton(
                  tooltip: '刷新课表',
                  onPressed: loading ? null : () => load(week),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              FilterChip(
                selected: showExperiments,
                onSelected: (value) => setState(() => showExperiments = value),
                avatar: const Icon(Icons.science_outlined, size: 17),
                label: const Text('含实验'),
              ),
              const Spacer(),
              if (week != currentWeek && currentWeek > 0)
                IconButton(
                  tooltip: '回到本周',
                  onPressed: loading ? null : () => load(currentWeek),
                  icon: const Icon(Icons.today_rounded, size: 17),
                ),
              TextButton.icon(
                onPressed: loading || exporting ? null : exportAllSchedule,
                icon: exporting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: const Text('全部课表'),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: Loader())
              : error != null
              ? ErrorState(message: error!, retry: load)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity.abs() < 250) return;
                    if (velocity < 0 && week < 30) {
                      load(week + 1);
                    } else if (velocity > 0 && week > 1) {
                      load(week - 1);
                    }
                  },
                  child: RefreshIndicator(
                    onRefresh: () => load(week),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      children: [
                        if (visibleLessons.isNotEmpty)
                          SizedBox(
                            height: 750,
                            child: ScheduleGrid(
                              lessons: visibleLessons,
                              isCurrentWeek: week == currentWeek,
                              onLessonTap: showLesson,
                            ),
                          ),
                        if (visibleLessons.isEmpty)
                          const EmptyState(
                            Icons.free_breakfast_outlined,
                            '本周暂无符合条件的课程',
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

const coursePalette = [
  Color(0xFF4F86D9),
  Color(0xFF4AA89B),
  Color(0xFFE17872),
  Color(0xFFD5A344),
  Color(0xFF7188C5),
  Color(0xFFA477BD),
  Color(0xFF3D9F78),
  Color(0xFFD16F9A),
  Color(0xFFCF7845),
  Color(0xFF598FB0),
  Color(0xFF879E4C),
  Color(0xFFB66A65),
  Color(0xFF6A76C2),
  Color(0xFFB98B43),
  Color(0xFF497FA2),
  Color(0xFF8F6FAD),
  Color(0xFF3C987F),
  Color(0xFFC26285),
  Color(0xFF7F8A45),
  Color(0xFFB76055),
];

int courseHash(String course) {
  var value = 2166136261;
  for (final unit in course.codeUnits) {
    value = ((value ^ unit) * 16777619) & 0x7fffffff;
  }
  return value;
}

Color courseColor(String course) =>
    coursePalette[courseHash(course) % coursePalette.length];

class ScheduleGrid extends StatelessWidget {
  const ScheduleGrid({
    super.key,
    required this.lessons,
    required this.isCurrentWeek,
    required this.onLessonTap,
  });

  final List<Map> lessons;
  final bool isCurrentWeek;
  final ValueChanged<Map> onLessonTap;

  Map<int, DateTime> datesForWeek() {
    DateTime? monday;
    for (final lesson in lessons) {
      final weekday = (lesson['weekday'] as num?)?.toInt() ?? 0;
      final date = DateTime.tryParse((lesson['date'] ?? '').toString());
      if (date != null && weekday >= 1 && weekday <= 7) {
        monday = date.subtract(Duration(days: weekday - 1));
        break;
      }
    }
    if (monday == null) return const {};
    return {
      for (var day = 1; day <= 7; day++)
        day: monday.add(Duration(days: day - 1)),
    };
  }

  @override
  Widget build(BuildContext context) {
    const headerHeight = 44.0;
    const unitWidth = 27.0;
    const maxUnit = 10;
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final dates = datesForWeek();
    final today = DateTime.now();
    final namesInWeek =
        lessons
            .map((lesson) => (lesson['course'] ?? '未知课程').toString())
            .toSet()
            .toList()
          ..sort();
    final usedColors = <int>{};
    final colorsByCourse = <String, Color>{};
    for (final name in namesInWeek) {
      var index = courseHash(name) % coursePalette.length;
      while (usedColors.contains(index) &&
          usedColors.length < coursePalette.length) {
        index = (index + 1) % coursePalette.length;
      }
      usedColors.add(index);
      colorsByCourse[name] = coursePalette[index];
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = (constraints.maxWidth - unitWidth) / 7;
        final scheduleWidth = dayWidth * 7;
        final totalHeight = constraints.maxHeight;
        final unitHeight = math.max(
          24.0,
          (totalHeight - headerHeight) / maxUnit,
        );
        return GlassPanel(
          radius: 24,
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: totalHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: unitWidth,
                  child: Column(
                    children: [
                      const SizedBox(height: headerHeight),
                      for (var unit = 1; unit <= maxUnit; unit++)
                        Container(
                          height: unitHeight,
                          alignment: Alignment.topCenter,
                          padding: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: Colors.white.withValues(alpha: .09),
                              ),
                            ),
                          ),
                          child: Text(
                            '$unit',
                            style: const TextStyle(
                              color: muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    width: scheduleWidth,
                    height: totalHeight,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            for (var day = 1; day <= 7; day++)
                              Container(
                                width: dayWidth,
                                height: totalHeight,
                                decoration: BoxDecoration(
                                  color:
                                      isCurrentWeek &&
                                          dates[day] != null &&
                                          DateUtils.isSameDay(dates[day], today)
                                      ? mint.withValues(alpha: .07)
                                      : null,
                                  border: Border(
                                    left: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: .08,
                                      ),
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      height: headerHeight,
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '周${names[day - 1]}',
                                            style: TextStyle(
                                              color:
                                                  isCurrentWeek &&
                                                      dates[day] != null &&
                                                      DateUtils.isSameDay(
                                                        dates[day],
                                                        today,
                                                      )
                                                  ? mint
                                                  : ink,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            dates[day] == null
                                                ? '--'
                                                : '${dates[day]!.month}/${dates[day]!.day}',
                                            style: const TextStyle(
                                              color: muted,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    for (var unit = 1; unit <= maxUnit; unit++)
                                      Container(
                                        height: unitHeight,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.white.withValues(
                                                alpha: .09,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        for (final lesson in lessons)
                          _CourseTile(
                            lesson: lesson,
                            dayWidth: dayWidth,
                            headerHeight: headerHeight,
                            unitHeight: unitHeight,
                            color:
                                colorsByCourse[(lesson['course'] ?? '未知课程')
                                    .toString()]!,
                            onTap: () => onLessonTap(lesson),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.lesson,
    required this.dayWidth,
    required this.headerHeight,
    required this.unitHeight,
    required this.color,
    required this.onTap,
  });

  final Map lesson;
  final double dayWidth;
  final double headerHeight;
  final double unitHeight;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekday = ((lesson['weekday'] as num?)?.toInt() ?? 1).clamp(1, 7);
    final start = ((lesson['start_unit'] as num?)?.toInt() ?? 1).clamp(1, 10);
    final end = ((lesson['end_unit'] as num?)?.toInt() ?? start).clamp(
      start,
      10,
    );
    final course = (lesson['course'] ?? '未知课程').toString();
    final place = fallback(lesson['place'], '地点未定');
    return Positioned(
      left: (weekday - 1) * dayWidth + 3,
      top: headerHeight + (start - 1) * unitHeight + 3,
      width: dayWidth - 6,
      height: (end - start + 1) * unitHeight - 6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color.withValues(alpha: .72)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: .18)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: .18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course,
                          maxLines: constraints.maxHeight > 80 ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            height: 1.08,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          place,
                          maxLines: constraints.maxHeight > 80 ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .92),
                            fontSize: 8,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (lesson['is_experiment'] == true)
                    const Positioned(
                      right: 3,
                      bottom: 3,
                      child: Icon(
                        Icons.science_rounded,
                        color: Colors.white,
                        size: 10,
                      ),
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

class EnergyPage extends StatefulWidget {
  const EnergyPage({super.key});
  @override
  State<EnergyPage> createState() => _EnergyPageState();
}

class _EnergyPageState extends State<EnergyPage> {
  Map<String, dynamic>? data;
  bool loading = true;
  bool alertSaving = false;
  bool energyAlertEnabled = false;
  double energyThreshold = 2;
  bool emailAlertEnabled = false;
  double emailThreshold = 2;
  bool emailSecretSet = false;
  String lastEmailStatus = '尚未发信';
  List<Map> drainSamples = const [];
  final TextEditingController emailEndpoint = TextEditingController();
  final TextEditingController emailSecret = TextEditingController();
  String? error;
  @override
  void initState() {
    super.initState();
    load();
    loadMonitorSettings();
    loadDrainSamples();
  }

  Future<void> loadDrainSamples() async {
    try {
      final result = await NativeApi.call('getEnergySamples');
      if (!mounted) return;
      setState(() {
        drainSamples = ((result['samples'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
      });
    } catch (_) {
      // 采样读取失败不影响电量展示。
    }
  }

  @override
  void dispose() {
    emailEndpoint.dispose();
    emailSecret.dispose();
    super.dispose();
  }

  Future<void> loadMonitorSettings() async {
    try {
      final settings = await NativeApi.call('getMonitorSettings');
      if (!mounted) return;
      setState(() {
        energyAlertEnabled = settings['energy_enabled'] == true;
        energyThreshold =
            (settings['energy_threshold'] as num?)?.toDouble() ?? 2;
        emailAlertEnabled = settings['energy_email_enabled'] == true;
        emailThreshold =
            (settings['energy_email_threshold'] as num?)?.toDouble() ?? 2;
        emailSecretSet = settings['energy_email_secret_set'] == true;
        lastEmailStatus =
            settings['last_email_status']?.toString() ?? '尚未发信';
        emailEndpoint.text =
            settings['energy_email_endpoint']?.toString() ?? '';
      });
    } catch (_) {}
  }

  Future<void> saveEnergyAlert({bool? enabled, double? threshold}) async {
    setState(() {
      if (enabled != null) energyAlertEnabled = enabled;
      if (threshold != null) energyThreshold = threshold;
      alertSaving = true;
    });
    await _saveMonitorSettings({
      'energy_enabled': energyAlertEnabled,
      'energy_threshold': energyThreshold,
    });
  }

  Future<void> saveEmailAlert({
    bool? enabled,
    double? threshold,
    bool includeCredentials = false,
  }) async {
    setState(() {
      if (enabled != null) emailAlertEnabled = enabled;
      if (threshold != null) emailThreshold = threshold;
      alertSaving = true;
    });
    final payload = <String, Object?>{
      'energy_email_enabled': emailAlertEnabled,
      'energy_email_threshold': emailThreshold,
    };
    if (includeCredentials) {
      final endpoint = emailEndpoint.text.trim();
      final secret = emailSecret.text.trim();
      if (emailAlertEnabled && (endpoint.isEmpty || secret.isEmpty)) {
        if (mounted) {
          setState(() => alertSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先填写发信接口地址与提醒密钥')),
          );
        }
        return;
      }
      payload['energy_email_endpoint'] = endpoint;
      // 留空表示不修改已保存的密钥。
      if (secret.isNotEmpty) payload['energy_email_secret'] = secret;
    }
    final saved = await _saveMonitorSettings(payload);
    if (saved && mounted) {
      setState(() {
        if (includeCredentials && emailSecret.text.trim().isNotEmpty) {
          emailSecretSet = true;
        }
        emailSecret.clear();
      });
    }
  }

  Future<bool> _saveMonitorSettings(Map<String, Object?> payload) async {
    try {
      final result = await NativeApi.call('saveMonitorSettings', payload);
      if (mounted) {
        final status = result['last_email_status']?.toString();
        if (status != null) setState(() => lastEmailStatus = status);
      }
      return true;
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(caught.toString())),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => alertSaving = false);
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      data = await NativeApi.call('getEnergy');
    } catch (caught) {
      error = caught.toString();
    }
    // 原生侧在查询成功时会顺手记一次采样，这里重新读一下好让估算立刻刷新。
    await loadDrainSamples();
    if (mounted) setState(() => loading = false);
  }

  Future<void> recharge() async {
    final meters = ((data?['meter_list'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final available = <String, Map>{};
    for (final meter in meters) {
      final meterId = meter['meter_id']?.toString() ?? '';
      if (meterId.isNotEmpty && meter['error'] == null) {
        available[meterId] = meter;
      }
    }
    if (available.isEmpty) return;
    final amount = TextEditingController();
    final password = TextEditingController();
    var selected = available.keys.first;
    final form = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
          ),
          child: GlassPanel(
            radius: 30,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '充值电费',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  '请选择实际电表并核对 ID',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.electric_meter_outlined),
                    labelText: '目标电表',
                  ),
                  items: [
                    for (final entry in available.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          (entry.value['label'] ?? '寝室电表').toString(),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) update(() => selected = value);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '电表 ID  $selected',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.currency_yen_rounded),
                    hintText: '充值金额（正整数元）',
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in [10, 20, 50, 100])
                      ActionChip(
                        label: Text('¥$value'),
                        onPressed: () => amount.text = '$value',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.password_rounded),
                    hintText: '校园卡支付密码',
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  '支付密码仅参与本次本地加密请求，不会保存。',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      final value = int.tryParse(amount.text.trim());
                      if (value == null || value <= 0 || password.text.isEmpty)
                        return;
                      Navigator.pop(context, {
                        'type': (available[selected]!['label'] ?? '寝室电表')
                            .toString(),
                        'meter_id': selected,
                        'amount': value,
                        'password': password.text,
                      });
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: mint,
                      foregroundColor: deep,
                    ),
                    child: const Text(
                      '下一步：核对订单',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (form == null || !mounted) return;
    final type = form['type']! as String;
    final value = form['amount']! as int;
    final meterId = form['meter_id']! as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xF213322C),
        title: const Text('确认充值'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConfirmRow('电表类型', type),
            ConfirmRow('电表 ID', meterId),
            ConfirmRow('充值金额', '¥$value'),
            const SizedBox(height: 12),
            const Text(
              '提交后不能由本应用撤销，请再次核对。',
              style: TextStyle(color: Color(0xFFFFC9A8), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回检查'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认支付'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => loading = true);
    try {
      final result = await NativeApi.call('rechargeEnergy', {
        'meter_id': meterId,
        'meter_type': type,
        'amount': value,
        'payment_password': form['password']!,
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']?.toString() ?? '充值请求已提交')),
        );
      await load();
    } catch (caught) {
      if (mounted)
        setState(() {
          loading = false;
          error = caught.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final meters = ((data?['meter_list'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final remaining = meters
        .where((meter) => meter['error'] == null && meter['remaining'] is num)
        .map((meter) => (meter['remaining'] as num).toDouble())
        .toList();
    final isLow =
        energyAlertEnabled &&
        remaining.any((value) => value <= energyThreshold);
    final drain = estimateDrain(drainSamples);
    return Column(
      children: [
        PageHeader(
          eyebrow: 'Dorm Energy',
          title: '寝室电量',
          subtitle: data == null
              ? '读取一卡通默认房间与实际电表'
              : '寝室 ${data!['room'] ?? '--'}',
          action: IconButton.filledTonal(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: Loader())
              : error != null
              ? ErrorState(message: error!, retry: load)
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      for (var index = 0; index < meters.length; index++) ...[
                        MeterCard(
                          (meters[index]['label'] ?? '寝室电表').toString(),
                          meterIcon((meters[index]['label'] ?? '').toString()),
                          meters[index],
                        ),
                        if (index < meters.length - 1)
                          const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 14),
                      GlassPanel(
                        radius: 22,
                        padding: const EdgeInsets.all(15),
                        tint: isLow
                            ? const Color(0xFFFF796D)
                            : energyAlertEnabled
                            ? mint
                            : null,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isLow
                                      ? Icons.warning_amber_rounded
                                      : Icons.notifications_none_rounded,
                                  color: isLow ? const Color(0xFFFF9E94) : mint,
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '电量余额预警',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        isLow
                                            ? '已有电表低于 ${number(energyThreshold)} 度'
                                            : energyAlertEnabled
                                            ? '低于 ${number(energyThreshold)} 度时通知'
                                            : '打开后将定时检查并发送通知',
                                        style: TextStyle(
                                          color: isLow
                                              ? const Color(0xFFFFC0BA)
                                              : muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: energyAlertEnabled,
                                  onChanged: alertSaving
                                      ? null
                                      : (value) =>
                                            saveEnergyAlert(enabled: value),
                                ),
                              ],
                            ),
                            if (energyAlertEnabled) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text(
                                    '预警额度',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: energyThreshold.clamp(0.5, 50),
                                      min: 0.5,
                                      max: 50,
                                      divisions: 99,
                                      label: '${number(energyThreshold)} 度',
                                      onChanged: alertSaving
                                          ? null
                                          : (value) => setState(
                                              () => energyThreshold = value,
                                            ),
                                      onChangeEnd: alertSaving
                                          ? null
                                          : (value) => saveEnergyAlert(
                                              threshold: value,
                                            ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      '${number(energyThreshold)} 度',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        color: ink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassPanel(
                        radius: 22,
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.speed_rounded,
                                  color: mint,
                                  size: 20,
                                ),
                                SizedBox(width: 9),
                                Text(
                                  '耗电速度',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Spacer(),
                                Text(
                                  '本次检查已记一次采样',
                                  style: TextStyle(color: muted, fontSize: 10),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (drain.isEmpty)
                              const Text(
                                '还没有采样数据。多查几次电量（或开启后台巡检）'
                                '即可估算还能用多久。',
                                style: TextStyle(color: muted, fontSize: 12),
                              )
                            else
                              for (final item in drain) ...[
                                Text(
                                  formatDrainLine(item),
                                  style: TextStyle(
                                    color: item.daysLeft == null ? muted : ink,
                                    fontSize: 12,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassPanel(
                        radius: 22,
                        padding: const EdgeInsets.all(15),
                        tint: emailAlertEnabled ? mint : null,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  emailAlertEnabled
                                      ? Icons.mark_email_read_outlined
                                      : Icons.mail_outline_rounded,
                                  color: mint,
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '低电量邮件提醒',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        emailAlertEnabled
                                            ? '低于 ${number(emailThreshold)} 度时请求服务端发信'
                                            : '打开后低于阈值会往邮箱发一封提醒',
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: emailAlertEnabled,
                                  onChanged: alertSaving
                                      ? null
                                      : (value) => saveEmailAlert(
                                          enabled: value,
                                          includeCredentials: value,
                                        ),
                                ),
                              ],
                            ),
                            if (emailAlertEnabled) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text(
                                    '发信阈值',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: emailThreshold.clamp(0.5, 50),
                                      min: 0.5,
                                      max: 50,
                                      divisions: 99,
                                      label: '${number(emailThreshold)} 度',
                                      onChanged: alertSaving
                                          ? null
                                          : (value) => setState(
                                              () => emailThreshold = value,
                                            ),
                                      onChangeEnd: alertSaving
                                          ? null
                                          : (value) => saveEmailAlert(
                                              threshold: value,
                                            ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      '${number(emailThreshold)} 度',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        color: ink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              TextField(
                                controller: emailEndpoint,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: '发信接口地址',
                                  hintText:
                                      'https://你的域名/api/energy-alert',
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: emailSecret,
                                obscureText: true,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  labelText: '提醒密钥',
                                  hintText: emailSecretSet
                                      ? '已保存，留空表示不修改'
                                      : '与服务端 ZZU_ALERT_SECRET 一致',
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '上次发信：$lastEmailStatus',
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: alertSaving
                                        ? null
                                        : () => saveEmailAlert(
                                            includeCredentials: true,
                                          ),
                                    child: const Text('保存'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: recharge,
                          style: FilledButton.styleFrom(
                            backgroundColor: mint,
                            foregroundColor: deep,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                          ),
                          icon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                          label: const Text(
                            '充值电费',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '充值前会再次显示电表类型、完整 ID 和金额。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class MeterCard extends StatelessWidget {
  const MeterCard(this.type, this.icon, this.meter, {super.key});
  final String type;
  final IconData icon;
  final Map? meter;
  @override
  Widget build(BuildContext context) {
    final failed = meter == null || meter!['error'] != null;
    final color = failed ? const Color(0xFFFF796D) : mint;
    return GlassPanel(
      tint: color,
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(19),
            ),
            child: Icon(icon, color: color, size: 29),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type, style: const TextStyle(color: muted, fontSize: 13)),
                const SizedBox(height: 3),
                Text(
                  failed ? '查询失败' : '${number(meter!['remaining'])} 度',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: failed ? const Color(0xFFFF9E94) : ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  failed
                      ? (meter?['error'] ?? '未返回数据').toString()
                      : 'ID  ${meter!['meter_id']}',
                  style: const TextStyle(color: muted, fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!failed)
            IconButton(
              tooltip: '复制电表 ID',
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: meter!['meter_id'].toString()),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('电表 ID 已复制')));
                }
              },
              icon: const Icon(Icons.copy_rounded, color: muted, size: 20),
            ),
        ],
      ),
    );
  }
}

class WidgetsPage extends StatelessWidget {
  const WidgetsPage({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const PageHeader(
        eyebrow: 'Home Screen',
        title: '桌面小组件',
        subtitle: '不用打开应用，也能快速查看',
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: const [
            FeatureCard(Icons.today_rounded, '今日课表', '显示当天课程、时间与教室，点按即可刷新。', [
              mint,
              aqua,
            ]),
            SizedBox(height: 12),
            FeatureCard(
              Icons.view_week_rounded,
              '整周课表',
              '按星期显示整周课程、地点和实验课，可调整组件高度。',
              [Color(0xFF73A7F0), Color(0xFFD16F9A)],
            ),
            SizedBox(height: 12),
            FeatureCard(
              Icons.electric_meter_outlined,
              '寝室电量',
              '分别显示照明和空调剩余电量，不混用电表 ID。',
              [aqua, Color(0xFFA594FF)],
            ),
            SizedBox(height: 18),
            GlassPanel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.touch_app_outlined, color: mint),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '长按桌面空白区域，选择“小组件”，然后搜索“郑大生活助手”。令牌失效时打开主应用重新登录。',
                      style: TextStyle(color: muted, height: 1.6, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class FeatureCard extends StatelessWidget {
  const FeatureCard(
    this.icon,
    this.title,
    this.description,
    this.colors, {
    super.key,
  });
  final IconData icon;
  final String title;
  final String description;
  final List<Color> colors;
  @override
  Widget build(BuildContext context) => GlassPanel(
    child: Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors.map((e) => e.withValues(alpha: .26)).toList(),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: colors.first, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(
                  color: muted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class Metric extends StatelessWidget {
  const Metric({super.key, required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 28,
          color: mint,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );
}

class GlassTag extends StatelessWidget {
  const GlassTag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: mint.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: mint.withValues(alpha: .2)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: mint,
        fontWeight: FontWeight.w700,
        fontSize: 11,
      ),
    ),
  );
}

class IconText extends StatelessWidget {
  const IconText(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: muted, size: 15),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(color: muted, fontSize: 12)),
    ],
  );
}

class ConfirmRow extends StatelessWidget {
  const ConfirmRow(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 75,
          child: Text(label, style: const TextStyle(color: muted)),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class Loader extends StatelessWidget {
  const Loader({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(color: mint, strokeWidth: 2.5),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.retry});
  final String message;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: GlassPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFFF9E94),
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, height: 1.5),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 70),
    child: Column(
      children: [
        Icon(icon, size: 42, color: muted),
        const SizedBox(height: 12),
        Text(text, style: const TextStyle(color: muted)),
      ],
    ),
  );
}

String number(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (parsed == null) return '--';
  if (parsed == parsed.roundToDouble()) return parsed.toInt().toString();
  return parsed
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// 电量耗电速度的估算结果，字段含义与 Python 侧
/// `zzupy.energy_history.DrainEstimate` 保持一致。
class DrainEstimate {
  const DrainEstimate({
    required this.label,
    required this.meterId,
    required this.latest,
    required this.ratePerDay,
    required this.daysLeft,
    required this.samples,
    required this.windowHours,
    this.note = '',
  });

  final String label;
  final String meterId;
  final double latest;
  final double ratePerDay;
  final double? daysLeft;
  final int samples;
  final double windowHours;
  final String note;
}

/// 采样时间跨度下限（小时）。少于这个跨度不足以拟合。
const double drainMinWindowHours = 6;

/// 回看窗口（天）。
const int drainWindowDays = 7;

/// 拟合出的速度小于该值（度/天）时视为几乎不耗电。
const double drainNegligibleRate = 0.01;

/// 把天数格式化成人能读的形式。
String formatDays(double days) {
  if (days < 1) {
    final hours = days * 24;
    if (hours < 1) return '${(hours * 60).round()} 分钟';
    return '${hours.toStringAsFixed(1)} 小时';
  }
  if (days < 10) return '${days.toStringAsFixed(1)} 天';
  return '${days.round()} 天';
}

/// 按电表分组估算耗电速度。
///
/// 算法与 Python 侧一致：以最早采样为原点做最小二乘拟合，斜率的相反数即日均
/// 耗电量；窗口内不足两点、跨度不足 6 小时、电量为上升趋势（刚充值）或几乎
/// 不耗电时都不给出天数估计，而是在 [DrainEstimate.note] 里说明原因。
List<DrainEstimate> estimateDrain(
  List<Map> samples, {
  int nowMillis = 0,
  int windowDays = drainWindowDays,
}) {
  final now = nowMillis == 0
      ? DateTime.now().millisecondsSinceEpoch
      : nowMillis;
  final cutoff = now - windowDays * 86400 * 1000;

  // 按电表归集窗口内的采样。
  final grouped = <String, List<Map>>{};
  for (final raw in samples) {
    final t = (raw['t'] as num?)?.toDouble();
    final q = (raw['q'] as num?)?.toDouble();
    if (t == null || q == null) continue;
    if (t < cutoff) continue;
    final id = (raw['id'] ?? '').toString();
    grouped.putIfAbsent(id, () => []).add({'t': t, 'q': q, 'label': raw['label']});
  }

  final results = <DrainEstimate>[];
  grouped.forEach((meterId, items) {
    items.sort((a, b) => (a['t'] as double).compareTo(b['t'] as double));
    final label = (items.last['label'] ?? '寝室电表').toString();
    final latest = items.last['q'] as double;

    if (items.length < 2) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: 0,
          daysLeft: null,
          samples: items.length,
          windowHours: 0,
          note: '只有一个采样点，多查几次即可估算',
        ),
      );
      return;
    }

    final origin = items.first['t'] as double;
    final windowHours =
        ((items.last['t'] as double) - origin) / 1000 / 3600;
    if (windowHours < drainMinWindowHours) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: 0,
          daysLeft: null,
          samples: items.length,
          windowHours: windowHours,
          note: '时间跨度不足 ${number(drainMinWindowHours)} 小时，继续采样中',
        ),
      );
      return;
    }

    final xs = items
        .map((item) => ((item['t'] as double) - origin) / 1000 / 86400)
        .toList();
    final ys = items.map((item) => item['q'] as double).toList();
    final count = xs.length;
    final meanX = xs.reduce((a, b) => a + b) / count;
    final meanY = ys.reduce((a, b) => a + b) / count;
    var denominator = 0.0;
    var numerator = 0.0;
    for (var i = 0; i < count; i++) {
      denominator += (xs[i] - meanX) * (xs[i] - meanX);
      numerator += (xs[i] - meanX) * (ys[i] - meanY);
    }
    if (denominator <= 0) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: 0,
          daysLeft: null,
          samples: count,
          windowHours: windowHours,
          note: '采样时间重合，无法拟合',
        ),
      );
      return;
    }

    final rate = -(numerator / denominator);
    if (rate.abs() < drainNegligibleRate) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: rate.abs(),
          daysLeft: null,
          samples: count,
          windowHours: windowHours,
          note: '几乎没有耗电',
        ),
      );
      return;
    }
    if (rate < 0) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: 0,
          daysLeft: null,
          samples: count,
          windowHours: windowHours,
          note: '期间电量没有下降（可能刚充值），暂不估算',
        ),
      );
      return;
    }

    results.add(
      DrainEstimate(
        label: label,
        meterId: meterId,
        latest: latest,
        ratePerDay: rate,
        daysLeft: latest > 0 ? latest / rate : 0,
        samples: count,
        windowHours: windowHours,
      ),
    );
  });

  results.sort((a, b) => a.label.compareTo(b.label));
  return results;
}

/// 把估算结果渲染成一行中文说明。
String formatDrainLine(DrainEstimate estimate) {
  if (estimate.daysLeft == null) {
    final detail = estimate.note.isEmpty ? '' : '（${estimate.note}）';
    return '${estimate.label}：${number(estimate.latest)} 度，暂无法估算耗电速度$detail';
  }
  return '${estimate.label}：${number(estimate.latest)} 度，'
      '日均 ${estimate.ratePerDay.toStringAsFixed(2)} 度，'
      '约还能用 ${formatDays(estimate.daysLeft!)}';
}

String fixed4(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return parsed == null ? '--' : parsed.toStringAsFixed(4);
}

IconData meterIcon(String label) {
  if (label.contains('空调')) return Icons.ac_unit_rounded;
  if (label.contains('照明') || label.contains('灯')) {
    return Icons.lightbulb_outline_rounded;
  }
  return Icons.electric_meter_outlined;
}

String fallback(Object? value, String replacement) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? replacement : text;
}
