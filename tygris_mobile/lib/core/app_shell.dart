import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'motion.dart';
import '../widgets/common.dart';

import '../screens/reserve_map_screen.dart';
import '../screens/identify_screen.dart';
import '../screens/attention_queue_screen.dart';
import '../screens/tiger_catalogue_screen.dart';
import '../screens/station_health_screen.dart';
import '../screens/blank_frame_trash_screen.dart';
import '../screens/settings_screen.dart';

class _NavItem {
  const _NavItem(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Root shell: a floating "fluid island" nav pill (glass, detached from
/// system chrome) for the 5 primary tabs, with Trash/Settings reachable
/// from an overflow sheet — the mobile-appropriate ergonomic limit vs. the
/// web's 7-item vertical sidebar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _primaryScreens = [
    ReserveMapScreen(),
    IdentifyScreen(),
    AttentionQueueScreen(),
    TigerCatalogueScreen(),
    StationHealthScreen(),
  ];

  static const _items = [
    _NavItem(Icons.map_outlined, Icons.map_rounded, 'Map'),
    _NavItem(
        Icons.fingerprint_outlined, Icons.fingerprint, 'Identify'),
    _NavItem(
        Icons.notifications_outlined, Icons.notifications_rounded, 'Alerts'),
    _NavItem(Icons.pets_outlined, Icons.pets_rounded, 'Tigers'),
    _NavItem(Icons.videocam_outlined, Icons.videocam_rounded, 'Stations'),
  ];

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  void _openMore(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MoreSheet(
        onTrash: () {
          Navigator.pop(ctx);
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const BlankFrameTrashScreen()));
        },
        onSettings: () {
          Navigator.pop(ctx);
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _primaryScreens),
      bottomNavigationBar: _FloatingNavIsland(
        items: _items,
        selectedIndex: _index,
        onSelect: _select,
        onMore: () => _openMore(context),
        showMore: _index == 0,
      ),
    );
  }
}

class _FloatingNavIsland extends StatelessWidget {
  const _FloatingNavIsland({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.onMore,
    required this.showMore,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onMore;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                          color: AppColors.borderStrong.withValues(alpha: 0.5)),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.shadowTintStrong,
                          blurRadius: 24,
                          spreadRadius: -8,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < items.length; i++)
                          _NavPillButton(
                            item: items[i],
                            selected: i == selectedIndex,
                            onTap: () => onSelect(i),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (showMore) ...[
              const SizedBox(width: 10),
              _MoreFab(onTap: onMore),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavPillButton extends StatelessWidget {
  const _NavPillButton(
      {required this.item, required this.selected, required this.onTap});
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scaleDown: 0.9,
      child: AnimatedContainer(
        duration: AppMotionDuration.standard,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? item.activeIcon : item.icon,
              size: 20,
              color: selected ? AppColors.accentForeground : AppColors.navMuted,
            ),
            AnimatedSize(
              duration: AppMotionDuration.standard,
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          color: AppColors.accentForeground,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreFab extends StatelessWidget {
  const _MoreFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.foreground,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowTintStrong,
              blurRadius: 20,
              spreadRadius: -6,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(Icons.more_horiz_rounded,
            color: AppColors.background, size: 24),
      ),
    );
  }
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.onTrash, required this.onSettings});
  final VoidCallback onTrash;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpace.lg),
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Bezel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SheetTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Blank Frame Trash',
                    onTap: onTrash,
                  ),
                  const Divider(height: 1, indent: 56),
                  _SheetTile(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: onSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scaleDown: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg, vertical: AppSpace.lg),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.foreground),
            const SizedBox(width: AppSpace.md),
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
