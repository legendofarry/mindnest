import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/notifications/data/push_notification_service.dart';
import 'package:mindnest/features/onboarding/data/onboarding_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OnboardingLoadingScreen extends ConsumerStatefulWidget {
  const OnboardingLoadingScreen({super.key});

  @override
  ConsumerState<OnboardingLoadingScreen> createState() =>
      _OnboardingLoadingScreenState();
}

class _OnboardingLoadingScreenState
    extends ConsumerState<OnboardingLoadingScreen>
    with TickerProviderStateMixin {
  static const Duration _holdDuration = Duration(seconds: 3);
  static const Duration _refreshInterval = Duration(milliseconds: 250);
  static const Duration _refreshTimeout = Duration(seconds: 6);

  late final AnimationController _backgroundController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();
  late final AnimationController _promptController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 540),
  );
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  UserProfile? _resolvedProfile;
  bool _showPermissionPrompt = false;
  bool _handlingPermissionDecision = false;

  @override
  void initState() {
    super.initState();
    unawaited(_goNext());
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _promptController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    final hold = Future<void>.delayed(_holdDuration);
    final startedAt = DateTime.now();
    final onboardingRepository = ref.read(onboardingRepositoryProvider);

    while (mounted) {
      await ref.read(currentUserProfileProvider.notifier).refreshProfile();
      final profile = ref.read(currentUserProfileProvider).valueOrNull;
      final needsOnboarding = onboardingRepository.requiresQuestionnaire(
        profile,
      );
      if (!needsOnboarding) {
        break;
      }
      if (DateTime.now().difference(startedAt) >= _refreshTimeout) {
        break;
      }
      await Future<void>.delayed(_refreshInterval);
    }

    await hold;
    if (!mounted) {
      return;
    }

    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    _resolvedProfile = profile;

    final needsPermissionPrompt =
        !(await PushNotificationService.hasPermission());
    if (!mounted) {
      return;
    }

    if (needsPermissionPrompt) {
      setState(() => _showPermissionPrompt = true);
      await _promptController.forward(from: 0);
      return;
    }

    context.go(_postOnboardingRoute(profile));
  }

  Future<void> _resolvePermissionPrompt({
    required bool requestPermission,
  }) async {
    if (_handlingPermissionDecision) {
      return;
    }
    setState(() => _handlingPermissionDecision = true);

    if (requestPermission) {
      await PushNotificationService.requestPermission();
    }

    if (!mounted) {
      return;
    }

    await _promptController.reverse();
    if (!mounted) {
      return;
    }

    setState(() => _showPermissionPrompt = false);
    context.go(_postOnboardingRoute(_resolvedProfile));
  }

  String _postOnboardingRoute(UserProfile? profile) {
    if (profile == null) {
      return AppRoute.home;
    }
    if (profile.role == UserRole.institutionAdmin) {
      return AppRoute.institutionAdmin;
    }
    if (profile.role == UserRole.counselor) {
      return AppRoute.counselorDashboard;
    }
    return AppRoute.home;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FBFC),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _backgroundController,
          _pulseController,
          _promptController,
        ]),
        builder: (context, _) {
          final progress = _backgroundController.value;
          final pulse = _pulseController.value;
          final promptProgress = Curves.easeOutCubic.transform(
            _promptController.value,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _OnboardingBackdropPainter(
                    progress: progress,
                    pulse: pulse,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandMark(compact: true, withBlob: true),
                      const SizedBox(height: 24),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: _LoadingHero(
                              pulse: pulse,
                              showPrompt: _showPermissionPrompt,
                            ),
                          ),
                        ),
                      ),
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        offset: _showPermissionPrompt
                            ? Offset.zero
                            : const Offset(0, 0.35),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 280),
                          opacity: _showPermissionPrompt ? 1 : 0,
                          child: IgnorePointer(
                            ignoring: !_showPermissionPrompt,
                            child: _NotificationPermissionPanel(
                              progress: promptProgress,
                              isBusy: _handlingPermissionDecision,
                              onAllow: () => _resolvePermissionPrompt(
                                requestPermission: true,
                              ),
                              onLater: () => _resolvePermissionPrompt(
                                requestPermission: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingHero extends StatelessWidget {
  const _LoadingHero({required this.pulse, required this.showPrompt});

  final double pulse;
  final bool showPrompt;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF0E9B90).withValues(alpha: 0.22),
                      const Color(0xFF0E9B90).withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.48, 1.0],
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                height: 150,
                child: Lottie.asset(
                  'assets/loading/loading.json',
                  repeat: true,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.hourglass_top_rounded,
                      size: 92,
                      color: const Color(
                        0xFF0E9B90,
                      ).withValues(alpha: 0.9 - (pulse * 0.08)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          showPrompt ? 'One last step' : 'Workspace is loading',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: const Color(0xFF071937),
            fontWeight: FontWeight.w900,
            letterSpacing: -0.9,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            showPrompt
                ? 'We can keep you updated with a calm in-app notification layer. Choose whether MindNest can send alerts in this browser or device.'
                : 'We are preparing your dashboard, reminders, and workspace context so the next screen lands cleanly.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF5E728D),
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: const [
            _StatusChip(label: 'Students'),
            _StatusChip(label: 'Staff'),
            _StatusChip(label: 'Counselors'),
            _StatusChip(label: 'Admins'),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            _LoadingPulseDot(),
            SizedBox(width: 8),
            _LoadingPulseDot(delay: 0.18),
            SizedBox(width: 8),
            _LoadingPulseDot(delay: 0.36),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBCEDE8)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0D5E58),
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _LoadingPulseDot extends StatefulWidget {
  const _LoadingPulseDot({this.delay = 0});

  final double delay;

  @override
  State<_LoadingPulseDot> createState() => _LoadingPulseDotState();
}

class _LoadingPulseDotState extends State<_LoadingPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final wave = ((_controller.value + widget.delay) % 1.0) * math.pi * 2;
        final size = 8.0 + ((math.sin(wave) + 1) * 1.8);
        final alpha = (0.35 + ((math.sin(wave) + 1) * 0.28)).clamp(0.25, 1.0);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF0E9B90).withValues(alpha: alpha),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class _NotificationPermissionPanel extends StatelessWidget {
  const _NotificationPermissionPanel({
    required this.progress,
    required this.isBusy,
    required this.onAllow,
    required this.onLater,
  });

  final double progress;
  final bool isBusy;
  final VoidCallback onAllow;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final paddingBottom = MediaQuery.viewPaddingOf(context).bottom + 12;
    return Padding(
      padding: EdgeInsets.only(bottom: paddingBottom),
      child: ClipPath(
        clipper: _WaveTopClipper(progress: progress),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF04201D).withValues(alpha: 0.95),
                const Color(0xFF0A3A35).withValues(alpha: 0.93),
                const Color(0xFF0E9B90).withValues(alpha: 0.88),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0xFF62E0D3), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2D0E9B90),
                blurRadius: 30,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _NotificationWavePainter(progress: progress),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stay in the loop',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Let MindNest send calm, useful alerts for invitations, reminders, and important updates.',
                                style: TextStyle(
                                  color: Color(0xE6EFFFFC),
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _PermissionActionButton(
                            label: isBusy
                                ? 'Opening...'
                                : 'Enable notifications',
                            primary: true,
                            icon: isBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 18,
                                  ),
                            onPressed: isBusy ? null : onAllow,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PermissionActionButton(
                            label: 'Not now',
                            primary: false,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: isBusy ? null : onLater,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      kIsWeb
                          ? 'On the web, your browser will show the final permission dialog after this step.'
                          : 'We will ask the device for permission after you tap enable.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        height: 1.35,
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

class _PermissionActionButton extends StatefulWidget {
  const _PermissionActionButton({
    required this.label,
    required this.primary,
    required this.onPressed,
    required this.icon,
  });

  final String label;
  final bool primary;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  State<_PermissionActionButton> createState() =>
      _PermissionActionButtonState();
}

class _PermissionActionButtonState extends State<_PermissionActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final bg = widget.primary
        ? Colors.white.withValues(alpha: _hovered && !disabled ? 0.98 : 0.94)
        : Colors.white.withValues(alpha: _hovered && !disabled ? 0.18 : 0.12);
    final fg = widget.primary ? const Color(0xFF071937) : Colors.white;

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.primary
                  ? Colors.white.withValues(alpha: 0.76)
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.icon,
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  color: disabled ? fg.withValues(alpha: 0.6) : fg,
                  fontWeight: FontWeight.w900,
                  fontSize: 14.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveTopClipper extends CustomClipper<Path> {
  const _WaveTopClipper({required this.progress});

  final double progress;

  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, size.height * 0.08);
    const waveCount = 2.6;
    for (var i = 0; i <= 54; i++) {
      final t = i / 54;
      final x = size.width * t;
      final wave = math.sin(
        (t * waveCount * math.pi * 2) + (progress * math.pi * 2),
      );
      final y = size.height * 0.08 + (wave * 10.5);
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _WaveTopClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}

class _NotificationWavePainter extends CustomPainter {
  const _NotificationWavePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final waveProgress = progress * math.pi * 2;

    for (var index = 0; index < 3; index++) {
      final amplitude = 12.0 + (index * 3.2);
      final baseY = size.height * (0.26 + index * 0.15);
      final path = Path();
      path.moveTo(0, baseY);

      for (var i = 0; i <= 60; i++) {
        final t = i / 60;
        final x = size.width * t;
        final y =
            baseY +
            math.sin((t * 2.8 * math.pi * 2) + waveProgress + index) *
                amplitude;
        path.lineTo(x, y);
      }

      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();

      paint.shader = ui.Gradient.linear(
        Offset(0, baseY),
        Offset(size.width, size.height),
        [
          Colors.white.withValues(alpha: 0.08 - (index * 0.016)),
          const Color(0xFF61E6D9).withValues(alpha: 0.14 - (index * 0.02)),
          const Color(0xFF0E9B90).withValues(alpha: 0.18 - (index * 0.02)),
        ],
      );
      canvas.drawPath(path, paint);
    }

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.14);
    for (var i = 0; i < 14; i++) {
      final x = (size.width / 14) * i + (math.sin(waveProgress + i) * 10);
      final y = size.height * 0.12 + math.sin(waveProgress * 1.4 + i) * 20;
      canvas.drawCircle(Offset(x, y), 1.8 + ((i % 3) * 0.5), dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NotificationWavePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _OnboardingBackdropPainter extends CustomPainter {
  const _OnboardingBackdropPainter({
    required this.progress,
    required this.pulse,
  });

  final double progress;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final baseRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(size.width, size.height),
        const [Color(0xFFF5FBFD), Color(0xFFF0F8FA), Color(0xFFEAF8F5)],
      );
    canvas.drawRect(baseRect, bgPaint);

    final shimmerCenter = Offset(
      size.width * (0.18 + (math.sin(progress * math.pi * 2) * 0.03)),
      size.height * 0.18,
    );
    final shimmerPaint = Paint()
      ..shader = ui.Gradient.radial(
        shimmerCenter,
        size.shortestSide * 0.65,
        [
          const Color(0xFF0E9B90).withValues(alpha: 0.15 + (pulse * 0.06)),
          const Color(0xFF0E9B90).withValues(alpha: 0.05),
          Colors.transparent,
        ],
        const [0.0, 0.45, 1.0],
      );
    canvas.drawCircle(shimmerCenter, size.shortestSide * 0.62, shimmerPaint);

    final lowerGlowCenter = Offset(
      size.width * (0.86 + (math.cos(progress * math.pi * 2) * 0.02)),
      size.height * 0.86,
    );
    final lowerGlowPaint = Paint()
      ..shader = ui.Gradient.radial(
        lowerGlowCenter,
        size.shortestSide * 0.55,
        [
          const Color(0xFF72ECDC).withValues(alpha: 0.12),
          const Color(0xFF72ECDC).withValues(alpha: 0.04),
          Colors.transparent,
        ],
        const [0.0, 0.42, 1.0],
      );
    canvas.drawCircle(
      lowerGlowCenter,
      size.shortestSide * 0.55,
      lowerGlowPaint,
    );

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF7CCCE2).withValues(alpha: 0.24);
    for (var index = 0; index < 120; index++) {
      final seed = index * 37.0;
      final x =
          (seed * 17.0 + math.sin(progress * math.pi * 2 + index)) % size.width;
      final y = (seed * 11.0 + (progress * size.height * 0.9)) % size.height;
      final radius = 0.6 + ((index % 5) * 0.28);
      canvas.drawCircle(Offset(x, y), radius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OnboardingBackdropPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.pulse != pulse;
  }
}
