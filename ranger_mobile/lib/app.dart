import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_shell.dart';
import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'models/observation.dart';
import 'screens/patrol/active_patrol_screen.dart';
import 'screens/patrol/patrol_review_screen.dart';
import 'screens/patrol/patrol_setup_screen.dart';
import 'screens/patrol/quick_log_form_screen.dart';
import 'screens/quick_report_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stations/camera_inspection_form_screen.dart';
import 'screens/stations/station_detail_screen.dart';
import 'screens/tasks/task_detail_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AppShell()),
    GoRoute(
      path: '/patrol/setup',
      builder: (context, state) => const PatrolSetupScreen(),
    ),
    GoRoute(
      path: '/patrol/active',
      builder: (context, state) => const ActivePatrolScreen(),
    ),
    GoRoute(
      path: '/patrol/review',
      builder: (context, state) => const PatrolReviewScreen(),
    ),
    GoRoute(
      path: '/patrol/detail/:patrolId',
      builder: (context, state) => PatrolReviewScreen(patrolId: state.pathParameters['patrolId']),
    ),
    GoRoute(
      path: '/patrol/quick-log',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? const {};
        return QuickLogFormScreen(
          category: extra['category'] as ObservationType? ?? ObservationType.wildlifeSighting,
          patrolId: extra['patrolId'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/quick-report',
      builder: (context, state) => const QuickReportScreen(),
    ),
    GoRoute(
      path: '/quick-report/form',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? const {};
        return QuickLogFormScreen(
          category: extra['category'] as ObservationType? ?? ObservationType.wildlifeSighting,
          patrolId: null,
        );
      },
    ),
    GoRoute(
      path: '/stations/:cameraId',
      builder: (context, state) => StationDetailScreen(cameraId: state.pathParameters['cameraId']!),
    ),
    GoRoute(
      path: '/stations/:cameraId/inspect',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? const {};
        return CameraInspectionFormScreen(
          cameraId: state.pathParameters['cameraId']!,
          reason: extra['reason'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/tasks/:taskId',
      builder: (context, state) => TaskDetailScreen(taskId: state.pathParameters['taskId']!),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

class TygrisRangerApp extends ConsumerWidget {
  const TygrisRangerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild the whole tree on locale change so every already-built
    // screen picks up the new strings immediately (per §5 of the spec —
    // language switch must relabel the app instantly, app-wide).
    ref.watch(localeControllerProvider);

    return MaterialApp.router(
      title: 'Tygris Ranger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
    );
  }
}
