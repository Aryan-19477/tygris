import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/motion.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// idle: no photo picked yet.
/// preview: photo picked, awaiting station input / submit.
/// loading: request in flight.
/// result: identify response received.
/// error: request failed.
enum _Phase { idle, preview, loading, result, error }

/// Camera-first "Identify" tab — the single most important mobile flow:
/// a ranger in the field photographs a tiger and gets a match back.
class IdentifyScreen extends ConsumerStatefulWidget {
  const IdentifyScreen({super.key});

  @override
  ConsumerState<IdentifyScreen> createState() => _IdentifyScreenState();
}

class _IdentifyScreenState extends ConsumerState<IdentifyScreen> {
  final _picker = ImagePicker();
  final _stationController = TextEditingController();

  _Phase _phase = _Phase.idle;
  File? _pickedFile;
  IdentifyResult? _result;
  String? _errorMessage;

  @override
  void dispose() {
    _stationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 90,
      );
      if (xfile == null) return; // user cancelled
      setState(() {
        _pickedFile = File(xfile.path);
        _phase = _Phase.preview;
        _result = null;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not open camera/gallery. Check app permissions.';
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _submit() async {
    final file = _pickedFile;
    if (file == null) return;
    setState(() => _phase = _Phase.loading);
    try {
      final station = _stationController.text.trim();
      final result = await ref.read(repositoryProvider).identify(
            file,
            station: station.isEmpty ? null : station,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(e);
        _phase = _Phase.error;
      });
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection')) {
      return "Couldn't reach the identification service. Check your connection to the server.";
    }
    return "Identification failed. Please try again.";
  }

  void _reset() {
    setState(() {
      _phase = _Phase.idle;
      _pickedFile = null;
      _result = null;
      _errorMessage = null;
      _stationController.clear();
    });
  }

  void _retryFromPreview() {
    setState(() {
      _phase = _pickedFile != null ? _Phase.preview : _Phase.idle;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _IdentifyHeader()),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _buildBody(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.idle:
        return _IdleCapture(
          key: const ValueKey('idle'),
          onTakePhoto: () => _pickImage(ImageSource.camera),
          onChooseGallery: () => _pickImage(ImageSource.gallery),
        );
      case _Phase.preview:
        return _PreviewForm(
          key: const ValueKey('preview'),
          file: _pickedFile!,
          stationController: _stationController,
          onRetake: () => _pickImage(ImageSource.camera),
          onSubmit: _submit,
          onClear: _reset,
        );
      case _Phase.loading:
        return _AnalyzingState(key: const ValueKey('loading'), file: _pickedFile);
      case _Phase.result:
        return _ResultCard(
          key: const ValueKey('result'),
          result: _result!,
          onReset: _reset,
        );
      case _Phase.error:
        return Center(
          key: const ValueKey('error'),
          child: ErrorState(
            message: _errorMessage ?? 'Something went wrong.',
            onRetry: _pickedFile != null ? _retryFromPreview : _reset,
          ),
        );
    }
  }
}

class _IdentifyHeader extends StatelessWidget {
  const _IdentifyHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.fingerprint, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Identify Tiger',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Photograph a stripe pattern to match against the gallery',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Idle state: big camera-first capture buttons.
class _IdleCapture extends StatelessWidget {
  const _IdleCapture({
    super.key,
    required this.onTakePhoto,
    required this.onChooseGallery,
  });

  final VoidCallback onTakePhoto;
  final VoidCallback onChooseGallery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SpringEntry(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EyebrowTag(
                  label: 'Field Identification',
                  icon: Icons.fingerprint,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            SpringEntry(
              delay: staggerDelay(1),
              child: Bezel(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: AppColors.accentSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          color: AppColors.accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        'No photo yet',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Capture a clear flank/stripe photo for the\nbest match accuracy',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SpringEntry(
              delay: staggerDelay(2),
              child: PrimaryCTA(
                label: 'Take Photo',
                icon: Icons.camera_alt_rounded,
                onPressed: onTakePhoto,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            SpringEntry(
              delay: staggerDelay(3),
              child: SizedBox(
                width: double.infinity,
                child: PressableScale(
                  onTap: onChooseGallery,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: const Border.fromBorderSide(
                        BorderSide(color: AppColors.borderStrong),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_library_outlined,
                            size: 19, color: AppColors.foreground),
                        const SizedBox(width: 10),
                        Text(
                          'Choose from Gallery',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: AppColors.foreground,
                                fontSize: 15,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Preview state: shows the picked photo, an optional station field, and
/// Identify / retake / clear actions.
class _PreviewForm extends StatelessWidget {
  const _PreviewForm({
    super.key,
    required this.file,
    required this.stationController,
    required this.onRetake,
    required this.onSubmit,
    required this.onClear,
  });

  final File file;
  final TextEditingController stationController;
  final VoidCallback onRetake;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SpringEntry(
            child: Align(
              alignment: Alignment.centerLeft,
              child: EyebrowTag(
                label: 'Field Identification',
                icon: Icons.fingerprint,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          SpringEntry(
            delay: staggerDelay(1),
            child: Bezel(
              padding: const EdgeInsets.all(AppRadius.bezelGap),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.bezelInner - AppRadius.bezelGap),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(file, fit: BoxFit.cover),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _RoundIconButton(
                          icon: Icons.close,
                          onTap: onClear,
                          tooltip: 'Clear photo',
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: _RoundIconButton(
                          icon: Icons.camera_alt_outlined,
                          onTap: onRetake,
                          tooltip: 'Retake',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SpringEntry(
            delay: staggerDelay(2),
            child: Bezel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STATION (OPTIONAL)',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.muted,
                        ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  TextField(
                    controller: stationController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: 14, color: AppColors.foreground),
                    decoration: InputDecoration(
                      hintText: 'e.g. PCH-07',
                      hintStyle: const TextStyle(color: AppColors.muted),
                      prefixIcon: const Icon(Icons.videocam_outlined, size: 20),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          SpringEntry(
            delay: staggerDelay(3),
            child: PrimaryCTA(
              label: 'Identify',
              icon: Icons.fingerprint,
              onPressed: onSubmit,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          SpringEntry(
            delay: staggerDelay(4),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Choose a different photo'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accentDeep.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// Loading state while the ML inference runs.
class _AnalyzingState extends StatefulWidget {
  const _AnalyzingState({super.key, this.file});
  final File? file;

  @override
  State<_AnalyzingState> createState() => _AnalyzingStateState();
}

class _AnalyzingStateState extends State<_AnalyzingState>
    with SingleTickerProviderStateMixin {
  static const _messages = [
    'Analyzing stripe pattern...',
    'Comparing against enrolled tigers...',
    'Scoring candidate matches...',
  ];
  int _msgIndex = 0;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    value: 0,
  );

  @override
  void initState() {
    super.initState();
    _cycle();
    _pulse();
  }

  void _cycle() {
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _msgIndex = (_msgIndex + 1) % _messages.length);
      _cycle();
    });
  }

  Future<void> _pulse() async {
    while (mounted) {
      await AppSpring.drive(_pulseController, AppSpring.gentle, from: 0, to: 1);
      if (!mounted) return;
      await AppSpring.drive(_pulseController, AppSpring.gentle, from: 1, to: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final t = _pulseController.value;
              final scale = 1.0 + (t * 0.05);
              return Transform.scale(scale: scale, child: child);
            },
            child: Bezel(
              outerRadius: AppRadius.xl,
              padding: const EdgeInsets.all(AppRadius.bezelGap),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  AppRadius.bezelInner - AppRadius.bezelGap,
                ),
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (file != null)
                        Opacity(
                          opacity: 0.32,
                          child: Image.file(file, fit: BoxFit.cover, width: 180, height: 180),
                        )
                      else
                        Container(color: AppColors.surfaceSunken),
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, _) => Opacity(
                          opacity: 0.55 + (_pulseController.value * 0.45),
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.2,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              _messages[_msgIndex],
              key: ValueKey(_msgIndex),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          const Text(
            'This can take a few seconds',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Result state: auto-match (positive) or needs-review (caution) card.
class _ResultCard extends StatelessWidget {
  const _ResultCard({super.key, required this.result, required this.onReset});

  final IdentifyResult result;
  final VoidCallback onReset;

  bool get _isKnown => result.status == 'KNOWN' && result.decision == 'auto_match';

  @override
  Widget build(BuildContext context) {
    final color = _isKnown ? AppColors.positive : AppColors.caution;
    final softColor = _isKnown ? AppColors.positiveSoft : AppColors.cautionSoft;
    final displayId = _isKnown
        ? (result.tigerId ?? 'Unknown')
        : (result.predictedTigerId ?? 'Unrecognized');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpringEntry(
            child: Bezel(
              outerColor: softColor,
              innerColor: softColor,
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _isKnown ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                          color: AppColors.accentForeground,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isKnown ? 'CONFIDENT MATCH' : 'NEEDS A DECISION',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: color,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              displayId,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  _ConfidenceMeter(confidence: result.confidence, color: color),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Compared against ${result.gallerySize} enrolled tigers',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          if (!_isKnown && result.candidates.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xl),
            SpringEntry(
              delay: staggerDelay(1),
              child: Text(
                'CLOSEST CANDIDATES',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            ...result.candidates.take(3).toList().asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: SpringEntry(
                      delay: staggerDelay(entry.key + 2),
                      child: _CandidateRow(candidate: entry.value),
                    ),
                  ),
                ),
            SpringEntry(
              delay: staggerDelay(5),
              child: Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.cautionSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.caution.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.person_add_alt_rounded, size: 16, color: AppColors.caution),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'No candidate is confident enough to auto-match. Use your own '
                        'judgment, or flag this as a possible new tiger when logging the sighting.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.caution.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (result.recordedStatus == 'SAVED_TO_GRAPH' &&
              result.recordedEventId != null) ...[
            const SizedBox(height: AppSpace.lg),
            SpringEntry(
              delay: staggerDelay(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.positive),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'Sighting logged as ${result.recordedEventId}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.xxl),
          SpringEntry(
            delay: staggerDelay(7),
            child: PrimaryCTA(
              label: 'Identify Another Photo',
              icon: Icons.refresh_rounded,
              onPressed: onReset,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceMeter extends StatefulWidget {
  const _ConfidenceMeter({required this.confidence, required this.color});
  final double confidence;
  final Color color;

  @override
  State<_ConfidenceMeter> createState() => _ConfidenceMeterState();
}

class _ConfidenceMeterState extends State<_ConfidenceMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppSpring.drive(
        _controller,
        AppSpring.settle,
        from: 0,
        to: widget.confidence.clamp(0, 1).toDouble(),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (widget.confidence.clamp(0, 1) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Confidence',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: widget.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => LinearProgressIndicator(
              value: _controller.value.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.surface.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation(widget.color),
            ),
          ),
        ),
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate});
  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final pct = (candidate.similarity.clamp(0, 1) * 100);
    return PressableScale(
      onTap: () {},
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Text(
              candidate.tigerId,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceSunken,
                  valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 40,
              child: Text(
                '${pct.toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
