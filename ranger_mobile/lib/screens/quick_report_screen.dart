import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/observation_meta.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../models/observation.dart';
import '../widgets/common.dart';

/// Stand-alone entry point into the same structured logging form used
/// mid-patrol — pick a category, then fill the shared
/// `QuickLogFormScreen` with `patrolId: null` (an ad hoc Report; see the
/// design note in `models/observation.dart`).
class QuickReportScreen extends ConsumerWidget {
  const QuickReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(appLocalizationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('report.quickReport'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.t('patrol.logSheetTitle'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpace.lg),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSpace.md,
                  crossAxisSpacing: AppSpace.md,
                  childAspectRatio: 0.95,
                  children: [
                    for (final type in ObservationType.values)
                      PressableScale(
                        onTap: () => context.push('/quick-report/form', extra: {'category': type}),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(observationTypeIcon(type), color: AppColors.accent, size: 26),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  l10n.t(observationTypeLabelKey(type)),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
