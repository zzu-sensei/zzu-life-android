import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Miuix 风格连续圆角卡片，支持可选点击波纹与浅色模式微投影。
class MiuixCard extends StatelessWidget {
  const MiuixCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.color,
    this.borderColor,
    this.onTap,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = context.isDark;
    final bgColor = color ?? palette.card;
    final shape = miuixShape(
      radius,
      side: BorderSide(color: borderColor ?? palette.border, width: 1),
    );

    final content = Padding(padding: padding, child: child);

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: !isDark && showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: bgColor,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                child: content,
              ),
      ),
    );
  }
}

/// HyperOS 分组列表卡片：将多个条目收纳于同一连续圆角容器并用缩进分割线隔开。
class MiuixGroupedCard extends StatelessWidget {
  const MiuixGroupedCard({
    super.key,
    required this.children,
    this.radius = 20,
    this.dividerIndent = 56,
  });

  final List<Widget> children;
  final double radius;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MiuixCard(
      radius: radius,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: dividerIndent,
                endIndent: 16,
                color: palette.divider,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// HyperOS 设置 / 服务列表项。
class MiuixTile extends StatelessWidget {
  const MiuixTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.iconBackground,
    this.trailingText,
    this.trailing,
    this.showBadgeDot = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Color? iconBackground;
  final String? trailingText;
  final Widget? trailing;
  final bool showBadgeDot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = iconColor ?? palette.primary;
    final wellBg = iconBackground ?? tint.withValues(alpha: 0.12);

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: wellBg,
              shape: miuixShape(11),
            ),
            child: Icon(icon, color: tint, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (showBadgeDot) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: palette.danger,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.inkSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (trailing != null)
            trailing!
          else ...[
            if (trailingText != null && trailingText!.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  trailingText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.inkMuted,
                size: 20,
              ),
            ],
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// 分组小标题。
class MiuixSectionHeader extends StatelessWidget {
  const MiuixSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 8),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: palette.inkSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 顶部页面标题栏。
class MiuixPageHeader extends StatelessWidget {
  const MiuixPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 16, 10),
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.inkSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// HyperOS 胶囊滑块分段控制器。
class MiuixSegmentedControl<T> extends StatelessWidget {
  const MiuixSegmentedControl({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.height = 40,
  });

  final List<({T value, String label})> items;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = context.isDark;
    final selectedIndex = items.indexWhere((item) => item.value == value);
    final activeIndex = selectedIndex < 0 ? 0 : selectedIndex;

    final trackColor = isDark ? const Color(0xFF1A1D24) : palette.cardSubtle;
    final thumbColor = isDark ? const Color(0xFF2D3340) : palette.card;

    return Container(
      height: height,
      padding: const EdgeInsets.all(3.5),
      decoration: ShapeDecoration(
        color: trackColor,
        shape: miuixShape(14, side: BorderSide(color: palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = items.length;
          if (count == 0) return const SizedBox.shrink();
          final segmentWidth = constraints.maxWidth / count;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: segmentWidth * activeIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: thumbColor,
                    shape: miuixShape(11),
                    shadows: !isDark
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (item.value != value) {
                            HapticFeedback.selectionClick();
                            onChanged(item.value);
                          }
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: item.value == value
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: item.value == value
                                  ? palette.ink
                                  : palette.inkSecondary,
                            ),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 语义胶囊标签。
class MiuixTag extends StatelessWidget {
  const MiuixTag(
    this.text, {
    super.key,
    this.color,
    this.backgroundColor,
    this.icon,
  });

  final String text;
  final Color? color;
  final Color? backgroundColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = color ?? palette.onPrimarySoft;
    final bg = backgroundColor ?? palette.primarySoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// 关键指标数值展示（等宽数字）。
class MiuixMetric extends StatelessWidget {
  const MiuixMetric({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.labelColor,
    this.fontSize = 26,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Color? labelColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            color: valueColor ?? palette.primary,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: labelColor ?? palette.inkSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 顶部蓝色渐变 Hero 卡片。
class MiuixHeroBanner extends StatelessWidget {
  const MiuixHeroBanner({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final shape = miuixShape(radius);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF2B6EE8), Color(0xFF1B4EC0)]
              : const [Color(0xFF4790FF), Color(0xFF2368EC)],
        ),
        shadows: !isDark
            ? [
                BoxShadow(
                  color: const Color(0xFF3482FF).withValues(alpha: 0.24),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 统一的 Miuix 底部弹窗容器，自动处理顶部把手、连续圆角、键盘遮挡与安全区。
Future<T?> showMiuixSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Container(
          decoration: ShapeDecoration(
            color: palette.card,
            shape: ContinuousRectangleBorder(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(52),
              ),
              side: BorderSide(color: palette.border),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.inkMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: builder(sheetContext),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 底部弹窗标题头。
class MiuixSheetHeader extends StatelessWidget {
  const MiuixSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: palette.inkSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 图标 + 文本行。
class InfoRow extends StatelessWidget {
  const InfoRow(
    this.icon,
    this.text, {
    super.key,
    this.trailing,
  });

  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, color: palette.inkSecondary, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: palette.ink,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 二次确认键值对行。
class ConfirmRow extends StatelessWidget {
  const ConfirmRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(color: palette.inkSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一加载指示器。
class Loader extends StatelessWidget {
  const Loader({super.key, this.size = 28, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          color: color ?? context.palette.primary,
          strokeWidth: 2.6,
        ),
      );
}

/// 错误状态卡片。
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.retry});
  final String message;
  final Future<void> Function() retry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: MiuixCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: ShapeDecoration(
                  color: palette.dangerSoft,
                  shape: miuixShape(16),
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  color: palette.danger,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.inkSecondary,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空状态展示。
class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.text, {super.key, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: ShapeDecoration(
                color: palette.cardSubtle,
                shape: miuixShape(18),
              ),
              child: Icon(icon, size: 28, color: palette.inkMuted),
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.inkSecondary,
                fontSize: 14,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
