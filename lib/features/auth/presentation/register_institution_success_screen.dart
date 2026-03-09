import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class RegisterInstitutionSuccessScreen extends ConsumerStatefulWidget {
  const RegisterInstitutionSuccessScreen({super.key, this.institutionName});

  final String? institutionName;

  @override
  ConsumerState<RegisterInstitutionSuccessScreen> createState() =>
      _RegisterInstitutionSuccessScreenState();
}

class _RegisterInstitutionSuccessScreenState
    extends ConsumerState<RegisterInstitutionSuccessScreen>
    with SingleTickerProviderStateMixin {
  static const _desktopBreakpoint = 1040.0;

  late final AnimationController _ambientController;
  bool _showContent = false;
  bool _isContinuing = false;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _showContent = true);
      }
    });
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  Future<void> _continueToWorkspace() async {
    if (_isContinuing || !mounted) {
      return;
    }
    setState(() => _isContinuing = true);
    try {
      await ref.read(institutionRepositoryProvider).dismissInstitutionWelcome();
      if (!mounted) {
        return;
      }
      context.go(AppRoute.institutionAdmin);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
      setState(() => _isContinuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    final institutionName = (widget.institutionName ?? '').trim();

    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      body: AnimatedBuilder(
        animation: _ambientController,
        builder: (context, child) {
          final tick = _ambientController.value;
          return Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF07111F),
                        Color(0xFF0E1F3D),
                        Color(0xFF0B2848),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      _AmbientOrb(
                        top: 56 + math.sin(tick * math.pi * 2) * 24,
                        left: -90 + math.cos(tick * math.pi * 2) * 20,
                        size: 240,
                        colors: const [Color(0xFF2ED3C6), Color(0x0040E0D0)],
                      ),
                      _AmbientOrb(
                        top: 120 + math.cos(tick * math.pi * 2) * 20,
                        right: -80 + math.sin(tick * math.pi * 2) * 18,
                        size: 280,
                        colors: const [Color(0xFFFF8B6A), Color(0x00FF8B6A)],
                      ),
                      _AmbientOrb(
                        bottom: -110 + math.sin(tick * math.pi * 2) * 18,
                        left: 120 + math.cos(tick * math.pi * 2) * 24,
                        size: 320,
                        colors: const [Color(0xFF7E8CFF), Color(0x007E8CFF)],
                      ),
                      _AmbientOrb(
                        bottom: 40 + math.cos(tick * math.pi * 2) * 14,
                        right: 60 + math.sin(tick * math.pi * 2) * 18,
                        size: 160,
                        colors: const [Color(0xFFFFD66B), Color(0x00FFD66B)],
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 32 : 18,
                      vertical: isDesktop ? 28 : 16,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 13,
                                  child: _Reveal(
                                    show: _showContent,
                                    delay: 0,
                                    child: _HeroPanel(
                                      institutionName: institutionName,
                                      pulse: tick,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 10,
                                  child: _Reveal(
                                    show: _showContent,
                                    delay: 120,
                                    child: _ActionPanel(
                                      institutionName: institutionName,
                                      isContinuing: _isContinuing,
                                      onContinue: _continueToWorkspace,
                                      pulse: tick,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Reveal(
                                  show: _showContent,
                                  delay: 0,
                                  child: _HeroPanel(
                                    institutionName: institutionName,
                                    pulse: tick,
                                    compact: true,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _Reveal(
                                  show: _showContent,
                                  delay: 120,
                                  child: _ActionPanel(
                                    institutionName: institutionName,
                                    isContinuing: _isContinuing,
                                    onContinue: _continueToWorkspace,
                                    pulse: tick,
                                    compact: true,
                                  ),
                                ),
                              ],
                            ),
                    ),
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

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.institutionName,
    required this.pulse,
    this.compact = false,
  });

  final String institutionName;
  final double pulse;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hasInstitution = institutionName.isNotEmpty;
    final panelPadding = compact ? 22.0 : 30.0;
    final badgeScale = 1 + (math.sin(pulse * math.pi * 2) * 0.035);

    return Container(
      padding: EdgeInsets.all(panelPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 28 : 34),
        gradient: const LinearGradient(
          colors: [Color(0xFFF9FBFF), Color(0xFFF7FCFF), Color(0xFFF5FFFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x40FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 40,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Transform.scale(
                scale: badgeScale,
                child: Container(
                  width: compact ? 64 : 78,
                  height: compact ? 64 : 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF19C3B0), Color(0xFF2E86FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF24C6B7).withValues(alpha: 0.28),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: compact ? 44 : 56,
                        height: compact ? 44 : 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              _SoftChip(
                label: 'ONE-TIME WELCOME',
                color: const Color(0xFF0D8F83),
                background: const Color(0xFFE3FFFB),
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 28),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetaPill(
                icon: Icons.mark_email_read_rounded,
                label: 'Email Verified',
              ),
              _MetaPill(
                icon: Icons.space_dashboard_rounded,
                label: 'Workspace Unlocked',
              ),
              if (hasInstitution)
                _MetaPill(
                  icon: Icons.account_balance_rounded,
                  label: institutionName,
                ),
            ],
          ),
          SizedBox(height: compact ? 18 : 24),
          Text(
            hasInstitution
                ? '$institutionName is live in MindNest.'
                : 'Your institution workspace is live.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontSize: compact ? 32 : 48,
              height: 1.02,
              letterSpacing: -1.3,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF071937),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'You are past verification. From here you can review institution '
            'status, prepare your onboarding flow, and step into the admin '
            'workspace when you are ready.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF5C708A),
              height: 1.5,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 16 : 18,
            ),
          ),
          SizedBox(height: compact ? 22 : 28),
          Container(
            padding: EdgeInsets.all(compact ? 18 : 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                colors: [Color(0xFF0E203D), Color(0xFF15335B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 28,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SoftChip(
                  label: 'CONTROL CENTER READY',
                  color: Color(0xFFFFFFFF),
                  background: Color(0x1FFFFFFF),
                ),
                const SizedBox(height: 14),
                Text(
                  'Everything important is staged in one place',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 21 : 26,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Track approval, manage join access, and prepare counselor '
                  'or staff invitations without leaving the workspace.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFC7D8F6),
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: compact ? 18 : 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: const [
                    _MiniStatCard(
                      value: 'READY',
                      label: 'Account state',
                      accent: Color(0xFF3FE3C4),
                    ),
                    _MiniStatCard(
                      value: 'LIVE',
                      label: 'Welcome access',
                      accent: Color(0xFF7BA8FF),
                    ),
                    _MiniStatCard(
                      value: 'NEXT',
                      label: 'Workspace review',
                      accent: Color(0xFFFFC96C),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.institutionName,
    required this.isContinuing,
    required this.onContinue,
    required this.pulse,
    this.compact = false,
  });

  final String institutionName;
  final bool isContinuing;
  final Future<void> Function() onContinue;
  final double pulse;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 20 : 26),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(compact ? 28 : 34),
        border: Border.all(color: const Color(0x24FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 38,
            offset: Offset(0, 22),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SoftChip(
                label: 'NEXT STEPS',
                color: Color(0xFF0E746E),
                background: Color(0xFFE7FFFA),
              ),
              const Spacer(),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD66B), Color(0xFFFF9767)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFFFFB56B,
                      ).withValues(alpha: 0.30 + (pulse * 0.10)),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Finish the handoff cleanly',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF071937),
              fontSize: compact ? 25 : 31,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            institutionName.isEmpty
                ? 'Read the launch summary, then continue into your institution '
                      'workspace.'
                : 'Read the launch summary for $institutionName, then continue '
                      'into your institution workspace.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF5E738C),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: compact ? 20 : 24),
          const _StepCard(
            step: '01',
            title: 'Review institution status',
            description:
                'Check whether the institution is approved already or still under review.',
            accent: Color(0xFF2E86FF),
          ),
          const SizedBox(height: 12),
          const _StepCard(
            step: '02',
            title: 'Prepare access and team setup',
            description:
                'Join codes, counselor invites, and member workflows are all staged in one place.',
            accent: Color(0xFF17C3B2),
          ),
          const SizedBox(height: 12),
          const _StepCard(
            step: '03',
            title: 'Move into the workspace',
            description:
                'Continue only when you are done reading this screen. It will not flash away anymore.',
            accent: Color(0xFFFF9B71),
          ),
          SizedBox(height: compact ? 18 : 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFFF8FBFF), Color(0xFFF7FFFD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0xFFDCEAFE)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_rounded, color: Color(0xFF2E86FF), size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This welcome screen now stays visible until you press continue. '
                    'That makes it a real acknowledgment step instead of a transient redirect.',
                    style: TextStyle(
                      color: Color(0xFF4C617C),
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 20 : 26),
          _ContinueButton(
            isLoading: isContinuing,
            onPressed: isContinuing ? null : onContinue,
          ),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF19C3B0), Color(0xFF2E86FF), Color(0xFFFF8B6A)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332E86FF),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed == null ? null : () => onPressed!.call(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue to Institution Workspace',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.6,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ],
              ),
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.show, required this.child, required this.delay});

  final bool show;
  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: show ? 1 : 0),
      duration: Duration(milliseconds: 700 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, builtChild) {
        final eased = Curves.easeOutCubic.transform(value);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, (1 - eased) * 28),
            child: builtChild,
          ),
        );
      },
      child: child,
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({
    required this.size,
    required this.colors,
    this.top,
    this.right,
    this.bottom,
    this.left,
  });

  final double size;
  final List<Color> colors;
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: colors),
          ),
        ),
      ),
    );
  }
}

class _SoftChip extends StatelessWidget {
  const _SoftChip({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E9F5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF1B8A80)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF314661),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.value,
    required this.label,
    required this.accent,
  });

  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFBFD0EC),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.description,
    required this.accent,
  });

  final String step;
  final String title;
  final String description;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFFF9FBFF),
        border: Border.all(color: const Color(0xFFE4EDF7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: accent.withValues(alpha: 0.14),
            ),
            child: Center(
              child: Text(
                step,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF091C39),
                    fontWeight: FontWeight.w800,
                    fontSize: 15.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF5F738C),
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
