import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Settings screen: server connection is the primary feature here (mobile
/// devices can't rely on 127.0.0.1 like the web dev build can), followed by
/// read-only model/connectivity/about info — mirrors the scope of
/// frontend-v2's SettingsView but reframed around field-device networking.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

enum _TestResult { none, success, failure }

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;
  final _formKey = GlobalKey<FormState>();

  bool _testing = false;
  bool _saving = false;
  _TestResult _testResult = _TestResult.none;
  String? _testMessage;

  Future<ModelStatus>? _modelStatusFuture;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ApiClient.instance.baseUrl);
    _loadModelStatus();
  }

  void _loadModelStatus() {
    setState(() {
      _modelStatusFuture = ref.read(repositoryProvider).modelStatus();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter a server URL';
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Enter a valid URL, e.g. http://192.168.1.20:8420';
    }
    return null;
  }

  Future<void> _testConnection() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _testing = true;
      _testResult = _TestResult.none;
      _testMessage = null;
    });

    final url = _urlController.text.trim();
    // Use a temporary Dio instance so a failed test never mutates the
    // working ApiClient config — only Save commits the change.
    final probeDio = Dio(BaseOptions(
      baseUrl: url,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
    ));

    try {
      try {
        await probeDio.get('/api/model-status');
      } on DioException catch (e) {
        if (e.response != null) {
          // Server answered, even with an error status — reachable.
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
      setState(() {
        _testResult = _TestResult.success;
        _testMessage = 'Server reachable at $url';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = _TestResult.failure;
        _testMessage = _describeDioError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = _TestResult.failure;
        _testMessage = 'Could not connect: $e';
      });
    } finally {
      probeDio.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  String _describeDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Connection timed out. Check the IP/port and that the device is on the same network as the server.';
      case DioExceptionType.connectionError:
        return 'Could not reach that address. Check the IP, port, and Wi-Fi connection.';
      default:
        return e.message ?? 'Connection failed.';
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _saving = true);
    final url = _urlController.text.trim();
    try {
      ApiClient.instance.configureBaseUrl(url);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kBaseUrlPrefKey, url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Server URL saved: $url'),
          backgroundColor: AppColors.accent,
        ),
      );
      _loadModelStatus();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ScreenAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.xxl,
        ),
        children: [
          const EyebrowTag(
            label: 'Device configuration',
            icon: Icons.tune_rounded,
          ),
          const SizedBox(height: AppSpace.lg),
          SpringEntry(
            delay: staggerDelay(0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader('Server Connection'),
                const SizedBox(height: AppSpace.sm),
                _ServerConnectionCard(
                  formKey: _formKey,
                  controller: _urlController,
                  validator: _validateUrl,
                  testing: _testing,
                  saving: _saving,
                  testResult: _testResult,
                  testMessage: _testMessage,
                  onTest: _testConnection,
                  onSave: _save,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SpringEntry(
            delay: staggerDelay(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader('Model Status'),
                const SizedBox(height: AppSpace.sm),
                _ModelStatusCard(
                    future: _modelStatusFuture, onRetry: _loadModelStatus),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SpringEntry(
            delay: staggerDelay(2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader('Connectivity'),
                const SizedBox(height: AppSpace.sm),
                const _ConnectivityCard(),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SpringEntry(
            delay: staggerDelay(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader('About'),
                const SizedBox(height: AppSpace.sm),
                const _AboutCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Restrained section label — Work Sans semibold with letter-spacing, not
/// Fraunces; this is a dense utility form, not an editorial moment.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.workSans(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.mutedStrong,
        ),
      ),
    );
  }
}

class _ServerConnectionCard extends StatelessWidget {
  const _ServerConnectionCard({
    required this.formKey,
    required this.controller,
    required this.validator,
    required this.testing,
    required this.saving,
    required this.testResult,
    required this.testMessage,
    required this.onTest,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final bool testing;
  final bool saving;
  final _TestResult testResult;
  final String? testMessage;
  final VoidCallback onTest;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final busy = testing || saving;
    return Bezel(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.dns_rounded,
                      size: 17, color: AppColors.accent),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    'TYGRIS Backend Address',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'Point this at the machine running the TYGRIS backend. Use its '
              'LAN IP for a real device on the same Wi-Fi (e.g. '
              'http://192.168.x.x:8420), 10.0.2.2:8420 for the Android '
              'emulator, or 127.0.0.1:8420 for the iOS simulator.',
              style: GoogleFonts.workSans(
                fontSize: 12.5,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            TextFormField(
              controller: controller,
              enabled: !busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://192.168.1.20:8420',
                prefixIcon: Icon(Icons.link_rounded, size: 18),
                isDense: true,
              ),
              validator: validator,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSpace.md),
            AnimatedSwitcher(
              duration: AppMotionDuration.standard,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
              child: testResult == _TestResult.none
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : Padding(
                      key: const ValueKey('banner'),
                      padding: const EdgeInsets.only(bottom: AppSpace.md),
                      child: _TestResultBanner(
                        success: testResult == _TestResult.success,
                        message: testMessage ?? '',
                      ),
                    ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onTest,
                    icon: testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 16),
                    label: Text(testing ? 'Testing…' : 'Test Connection'),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: PrimaryCTA(
                    label: saving ? 'Saving…' : 'Save',
                    icon: Icons.save_rounded,
                    loading: saving,
                    onPressed: busy ? null : onSave,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TestResultBanner extends StatelessWidget {
  const _TestResultBanner({required this.success, required this.message});
  final bool success;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = success ? AppColors.positive : AppColors.danger;
    final soft = success ? AppColors.positiveSoft : AppColors.dangerSoft;
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.workSans(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelStatusCard extends StatelessWidget {
  const _ModelStatusCard({required this.future, required this.onRetry});
  final Future<ModelStatus>? future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (future == null) {
      return const Bezel(
        child: SizedBox(
          height: 60,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
        ),
      );
    }
    return Bezel(
      padding: EdgeInsets.zero,
      child: FutureBuilder<ModelStatus>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: ErrorState(
                message: 'Could not load model status.\n${snapshot.error}',
                onRetry: onRetry,
              ),
            );
          }
          final status = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Icon(Icons.memory_rounded,
                          size: 17, color: AppColors.accent),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        'Pipeline weights',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    StatusBadge(
                      label: status.isFullyTrained
                          ? 'Fully trained'
                          : 'Untrained stage(s)',
                      level: status.isFullyTrained ? 'low' : 'medium',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                if (status.weightsLoaded.isEmpty)
                  Text(
                    'No component status reported.',
                    style: GoogleFonts.workSans(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  )
                else
                  ...status.weightsLoaded.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            e.value
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            size: 16,
                            color:
                                e.value ? AppColors.positive : AppColors.danger,
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Text(
                              e.key,
                              style: GoogleFonts.workSans(fontSize: 13.5),
                            ),
                          ),
                          Text(
                            e.value ? 'Loaded' : 'Not loaded',
                            style: GoogleFonts.workSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: e.value
                                  ? AppColors.positive
                                  : AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (status.checkpointsDir.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.md),
                  const Divider(),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'CHECKPOINTS DIR',
                    style: GoogleFonts.workSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  SelectableText(
                    status.checkpointsDir,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.foreground,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConnectivityCard extends StatefulWidget {
  const _ConnectivityCard();

  @override
  State<_ConnectivityCard> createState() => _ConnectivityCardState();
}

class _ConnectivityCardState extends State<_ConnectivityCard> {
  final Connectivity _connectivity = Connectivity();
  List<ConnectivityResult> _result = const [ConnectivityResult.none];
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _connectivity.checkConnectivity().then((r) {
      if (mounted) setState(() => _result = r);
    });
    _sub = _connectivity.onConnectivityChanged.listen((r) {
      if (mounted) setState(() => _result = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  ({IconData icon, String label, Color color, bool offline}) _describe() {
    if (_result.contains(ConnectivityResult.wifi)) {
      return (
        icon: Icons.wifi_rounded,
        label: 'Connected via Wi-Fi',
        color: AppColors.positive,
        offline: false,
      );
    }
    if (_result.contains(ConnectivityResult.mobile)) {
      return (
        icon: Icons.signal_cellular_alt_rounded,
        label: 'Connected via mobile data',
        color: AppColors.caution,
        offline: false,
      );
    }
    if (_result.contains(ConnectivityResult.ethernet)) {
      return (
        icon: Icons.lan_rounded,
        label: 'Connected via Ethernet',
        color: AppColors.positive,
        offline: false,
      );
    }
    if (_result.contains(ConnectivityResult.none) || _result.isEmpty) {
      return (
        icon: Icons.wifi_off_rounded,
        label: 'Offline — no network connection',
        color: AppColors.danger,
        offline: true,
      );
    }
    return (
      icon: Icons.device_unknown_outlined,
      label: 'Unknown connection',
      color: AppColors.muted,
      offline: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _describe();
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: d.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(d.icon, size: 16, color: d.color),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              d.label,
              style: GoogleFonts.workSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
          ),
          if (d.offline)
            Text(
              'Server unreachable',
              style: GoogleFonts.workSans(
                fontSize: 11.5,
                color: AppColors.muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.pets_rounded,
                    size: 19, color: AppColors.accent),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TYGRIS Field',
                      style: GoogleFonts.fraunces(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mobile companion for Pench Tiger Reserve wildlife monitoring',
                      style: GoogleFonts.workSans(
                        fontSize: 12,
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const Divider(),
          const SizedBox(height: AppSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Version',
                style: GoogleFonts.workSans(
                  fontSize: 12.5,
                  color: AppColors.muted,
                ),
              ),
              const Text(
                '1.0.0',
                style: TextStyle(
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: AppColors.foreground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
