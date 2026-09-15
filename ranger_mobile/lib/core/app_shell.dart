import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../screens/history/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/map/ranger_map_screen.dart';
import '../screens/stations/stations_list_screen.dart';
import '../screens/tasks/tasks_list_screen.dart';
import 'theme.dart';

/// Which of the 5 bottom-nav tabs is showing. Exposed as a provider (not
/// local `State`) so any screen — e.g. Home's "Camera Stations" quick
/// action — can switch tabs by index without going through go_router
/// (the tab shell itself isn't route-driven; only the full-screen flows
/// pushed on top of it are).
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

/// Root shell: bottom [NavigationBar] with 5 tabs (Home, Map, Tasks,
/// Stations, History). Patrol / Quick Report / SOS are reached from Home's
/// prominent actions rather than being separate tabs, to keep the primary
/// navigation surface small and low-cognitive-load for a field ranger.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _screens = [
    HomeScreen(),
    RangerMapScreen(),
    TasksListScreen(),
    StationsListScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(appLocalizationsProvider);
    final index = ref.watch(bottomNavIndexProvider);
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: l10n.t('nav.home'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.map_outlined),
        selectedIcon: const Icon(Icons.map_rounded),
        label: l10n.t('nav.map'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.checklist_outlined),
        selectedIcon: const Icon(Icons.checklist_rounded),
        label: l10n.t('nav.tasks'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.videocam_outlined),
        selectedIcon: const Icon(Icons.videocam_rounded),
        label: l10n.t('nav.stations'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.history_rounded),
        selectedIcon: const Icon(Icons.history_rounded),
        label: l10n.t('nav.history'),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => ref.read(bottomNavIndexProvider.notifier).state = i,
            destinations: destinations,
            height: 64,
          ),
        ),
      ),
    );
  }
}
