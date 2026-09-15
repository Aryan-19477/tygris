import 'package:flutter/material.dart';

import '../core/sync_status.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

/// Simple press-to-scale wrapper used throughout the app for large tap
/// targets (cards, tiles, buttons) so interactions feel tactile.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleDown = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: AppMotionDuration.quick,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// A soft, bordered card container — the app's base surface treatment.
class Bezel extends StatelessWidget {
  const Bezel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Small uppercase section eyebrow label.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.muted,
          ),
    );
  }
}

/// Generic colored status pill used for sync status, station status,
/// severity, etc.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.softColor,
    this.icon,
  });

  final String label;
  final Color color;
  final Color? softColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: softColor ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sync status pill wired to [SyncStatus] tokens + localized labels. The
/// caller (always a `ConsumerWidget`/`ConsumerState` with a `ref` in
/// scope) passes in [l10n] — kept explicit rather than self-fetched so this
/// stays a plain `StatelessWidget` with no Riverpod context lookups of its
/// own, avoiding any chance of clashing with `package:flutter_riverpod`'s
/// own `Provider` symbol.
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({
    super.key,
    required this.status,
    required this.l10n,
  });

  final SyncStatus status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: l10n.t(status.labelKey()),
      color: status.color,
      softColor: status.softColor,
      icon: status.icon,
    );
  }
}

/// Empty-state placeholder used across list screens.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: AppSpace.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Large selectable icon chip — used for patrol type / method / severity /
/// quick-log category pickers to keep input tap-first, not typing-first.
class IconChoiceChip extends StatelessWidget {
  const IconChoiceChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotionDuration.quick,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.12) : AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? c : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? c : AppColors.mutedStrong),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? c : AppColors.foreground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big square tile used in the quick-log category sheet / home quick
/// action grid — min 56dp height satisfied comfortably.
class BigTile extends StatelessWidget {
  const BigTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return PressableScale(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: c, size: 20),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              label,
              maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
