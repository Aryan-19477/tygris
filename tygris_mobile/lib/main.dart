import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/app_shell.dart';
import 'core/repository.dart';

void main() {
  runApp(const ProviderScope(child: TygrisApp()));
}

class TygrisApp extends ConsumerWidget {
  const TygrisApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrlInit = ref.watch(baseUrlInitProvider);

    return MaterialApp(
      title: 'TYGRIS Field',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: baseUrlInit.when(
        data: (_) => const AppShell(),
        loading: () => const Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          ),
        ),
        error: (_, __) => const AppShell(),
      ),
    );
  }
}
