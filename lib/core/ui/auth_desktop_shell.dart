import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/material.dart';
import 'package:mindnest/core/ui/mindnest_logo.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';

class AuthDesktopShell extends StatelessWidget {
  const AuthDesktopShell({
    super.key,
    required this.formChild,
    required this.heroHighlightText,
    required this.heroBaseText,
    required this.heroDescription,
    this.heroSupplement,
    this.heroHighlightAfterBase = false,
    this.formMaxWidth = 560,
  });

  final Widget formChild;
  final String heroHighlightText;
  final String heroBaseText;
  final String heroDescription;
  final Widget? heroSupplement;
  final bool heroHighlightAfterBase;
  final double formMaxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFC),
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthDesktopAmbientBackground()),

          // TOP LEFT FLOATING LOGO
          Positioned(
            top: 2,
            left: 18,
            child: SafeArea(
              child: Transform.translate(
                offset: const Offset(-10, -8),
                child: const MindNestLogo(
                  width: 260,
                  height: 260,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 52,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1500),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _AuthDesktopHero(
                          heroHighlightText: heroHighlightText,
                          heroBaseText: heroBaseText,
                          heroDescription: heroDescription,
                          heroSupplement: heroSupplement,
                          heroHighlightAfterBase: heroHighlightAfterBase,
                        ),
                      ),

                      const SizedBox(width: 54),

                      Expanded(
                        flex: 5,
                        child: _AuthDesktopPhysicsFormCard(
                          alignment: Alignment.centerRight,
                          maxWidth: formMaxWidth,
                          child: formChild,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: WindowsDesktopWindowControls(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthDesktopHero extends StatelessWidget {
  const _AuthDesktopHero({
    required this.heroHighlightText,
    required this.heroBaseText,
    required this.heroDescription,
    this.heroSupplement,
    this.heroHighlightAfterBase = false,
  });

  final String heroHighlightText;
  final String heroBaseText;
  final String heroDescription;
  final Widget? heroSupplement;
  final bool heroHighlightAfterBase;

  @override
  Widget build(BuildContext context) {
    final hasDescription = heroDescription.trim().isNotEmpty;
    final hasHighlight = heroHighlightText.trim().isNotEmpty;

    const heroBaseStyle = TextStyle(
      color: Color(0xFF0F172A),
      fontSize: 74,
      fontWeight: FontWeight.w800,
      height: 0.96,
      letterSpacing: -1.9,
    );

    const heroHighlightStyle = TextStyle(
      color: Color(0xFF0E9B90),
      fontSize: 74,
      fontWeight: FontWeight.w800,
      height: 0.96,
      letterSpacing: -1.9,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasHighlight && !heroHighlightAfterBase) ...[
                  Text(heroHighlightText, style: heroHighlightStyle),
                  const SizedBox(height: 2),
                ],

                Text(heroBaseText, style: heroBaseStyle),

                if (hasHighlight && heroHighlightAfterBase) ...[
                  const SizedBox(height: 2),
                  Text(heroHighlightText, style: heroHighlightStyle),
                ],
              ],
            ),
          ),

          if (hasDescription) ...[
            const SizedBox(height: 26),

            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Text(
                heroDescription,
                style: const TextStyle(
                  color: Color(0xFF4C607A),
                  fontSize: 31,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],

          if (heroSupplement != null) ...[
            SizedBox(height: hasDescription ? 34 : 30),

            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: heroSupplement!,
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthDesktopPhysicsFormCard extends StatefulWidget {
  const _AuthDesktopPhysicsFormCard({
    required this.child,
    required this.maxWidth,
    required this.alignment,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  State<_AuthDesktopPhysicsFormCard> createState() =>
      _AuthDesktopPhysicsFormCardState();
}

class _AuthDesktopPhysicsFormCardState
    extends State<_AuthDesktopPhysicsFormCard>
    with TickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 20,
  );

  late final AnimationController _rotateX = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _rotateY = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _shiftX = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _shiftY = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void dispose() {
    _rotateX.dispose();
    _rotateY.dispose();
    _shiftX.dispose();
    _shiftY.dispose();
    super.dispose();
  }

  void _springTo(AnimationController controller, double target) {
    controller.animateWith(
      SpringSimulation(_spring, controller.value, target, 0),
    );
  }

  void _handleHover(PointerHoverEvent event, BoxConstraints constraints) {
    final width = math.max(constraints.maxWidth, 1);
    final height = math.max(constraints.maxHeight, 1);
    final dx = ((event.localPosition.dx / width) - 0.5).clamp(-0.5, 0.5) * 2;
    final dy = ((event.localPosition.dy / height) - 0.5).clamp(-0.5, 0.5) * 2;

    _springTo(_rotateX, -dy * 0.045);
    _springTo(_rotateY, dx * 0.045);
    _springTo(_shiftX, -dx * 9);
    _springTo(_shiftY, -dy * 9);
  }

  void _settle() {
    _springTo(_rotateX, 0);
    _springTo(_rotateY, 0);
    _springTo(_shiftX, 0);
    _springTo(_shiftY, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 18),
                child: Transform.scale(
                  scale: 0.982 + (value * 0.018),
                  child: child,
                ),
              ),
            );
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              return MouseRegion(
                onHover: (event) => _handleHover(event, constraints),
                onExit: (_) => _settle(),
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _rotateX,
                    _rotateY,
                    _shiftX,
                    _shiftY,
                  ]),
                  builder: (context, child) {
                    final cardTransform = Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(_rotateX.value)
                      ..rotateY(_rotateY.value);

                    return Transform(
                      alignment: Alignment.center,
                      transform: cardTransform,
                      child: Transform.translate(
                        offset: Offset(_shiftX.value, _shiftY.value),
                        child: child,
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: const Color(0xFFBEE9E4),
                        width: 1.1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A0F172A),
                          blurRadius: 40,
                          offset: Offset(0, 22),
                        ),
                        BoxShadow(
                          color: Color(0x1F7CEFE7),
                          blurRadius: 60,
                          offset: Offset(0, 30),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(34, 28, 34, 26),
                      child: widget.child,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AuthDesktopAmbientBackground extends StatelessWidget {
  const _AuthDesktopAmbientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF8FCFD),
                  const Color(0xFFF6FAFC),
                  const Color(0xFFF4F9FB),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),

        Positioned(
          left: -150,
          top: -210,
          child: _AuthDesktopGlowBlob(
            size: 680,
            color: const Color(0xFF82E9E0).withValues(alpha: 0.35),
          ),
        ),

        Positioned(
          right: -160,
          top: 130,
          child: _AuthDesktopGlowBlob(
            size: 560,
            color: const Color(0xFFB8F4EF).withValues(alpha: 0.34),
          ),
        ),

        Positioned(
          right: 150,
          bottom: -220,
          child: _AuthDesktopGlowBlob(
            size: 640,
            color: const Color(0xFF8DE8DF).withValues(alpha: 0.26),
          ),
        ),
      ],
    );
  }
}

class _AuthDesktopGlowBlob extends StatelessWidget {
  const _AuthDesktopGlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.44),
              blurRadius: size * 0.28,
              spreadRadius: size * 0.02,
            ),
          ],
        ),
      ),
    );
  }
}
