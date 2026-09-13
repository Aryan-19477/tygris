import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/theme.dart';
import '../core/motion.dart';

/// Shared building blocks every screen should reuse for visual consistency.
/// Signatures are stable — existing screens already depend on them — but
/// internals now follow the "Field Journal" premium design bible: warm
/// tinted shadows, double-bezel nesting, spring-driven press response.

/// Double-bezel nested card: an outer shell (subtle tint + hairline ring)
/// containing an inner core with its own background and inset highlight —
/// the concentric "machined hardware" look, simulated with layered
/// BoxDecorations since Flutter has no native inset shadow.
class Bezel extends StatelessWidget {
  const Bezel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.onLongPress,
    this.outerColor = AppColors.surfaceSunken,
    this.innerColor = AppColors.surface,
    this.outerRadius = AppRadius.bezelOuter,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color outerColor;
  final Color innerColor;
  final double outerRadius;

  @override
  Widget build(BuildContext context) {
    final innerRadius = outerRadius - AppRadius.bezelGap;
    final core = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: innerColor,
        borderRadius: BorderRadius.circular(innerRadius),
        border: Border.all(color: AppColors.hairline, width: 1),
        boxShadow: const [
          // Simulated inset top highlight via a tight, low-opacity
          // downward shadow inside the bezel gap (no native inset-shadow
          // support in Flutter).
          BoxShadow(
            color: AppColors.highlight,
            blurRadius: 0,
            spreadRadius: -1,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );

    final shell = Container(
      padding: const EdgeInsets.all(AppRadius.bezelGap),
      decoration: BoxDecoration(
        color: outerColor,
        borderRadius: BorderRadius.circular(outerRadius),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowTint,
            blurRadius: 18,
            spreadRadius: -6,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: core,
    );

    if (onTap == null && onLongPress == null) return shell;
    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
      child: shell,
    );
  }
}

/// Microscopic pill-shaped label preceding a headline — the "eyebrow tag"
/// from the design bible. Use sparingly, one per screen/section.
class EyebrowTag extends StatelessWidget {
  const EyebrowTag({
    super.key,
    required this.label,
    this.color = AppColors.accent,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.level});

  final String label;
  final String level; // critical/high, caution/medium, or default/low

  @override
  Widget build(BuildContext context) {
    final color = statusColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Legacy flat card kept for internal/secondary content where a full
/// double-bezel would be too heavy (e.g. dense list rows). Prefer [Bezel]
/// for anything that reads as a primary surface.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowTint,
            blurRadius: 12,
            spreadRadius: -8,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return PressableScale(onTap: onTap, child: card);
  }
}

/// Primary CTA with the "button-in-button" trailing icon pattern — the
/// icon sits in its own nested circular wrapper flush with the pill's
/// inner edge, with magnetic hover-style kinetic tension on press.
class PrimaryCTA extends StatelessWidget {
  const PrimaryCTA({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final button = PressableScale(
      onTap: loading ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.only(left: 24, right: 8, top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: onPressed == null && !loading
              ? AppColors.muted.withValues(alpha: 0.35)
              : AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.accentForeground,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.accentForeground),
                      ),
                    )
                  : Icon(icon, size: 16, color: AppColors.accentForeground),
            ),
          ],
        ),
      ),
    );
    return expand ? button : IntrinsicWidth(child: button);
  }
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.itemCount = 6, this.height = 76});
  final int itemCount;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceSunken,
      highlightColor: AppColors.surface,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpace.lg),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpace.md),
        itemBuilder: (_, __) => Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.dangerSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_off_outlined,
                  size: 26, color: AppColors.danger),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.mutedStrong, fontSize: 14, height: 1.5),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.surfaceSunken,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 13, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}

class ScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ScreenAppBar({super.key, required this.title, this.actions});
  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      centerTitle: false,
      actions: actions,
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);
}
