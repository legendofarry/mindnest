import 'dart:math' as math;

import 'package:flutter/material.dart';

class AuthBackgroundScaffold extends StatefulWidget {
  const AuthBackgroundScaffold({
    super.key,
    required this.child,
    this.maxWidth = 430,
  });

  final Widget child;
  final double maxWidth;

  @override
  State<AuthBackgroundScaffold> createState() => _AuthBackgroundScaffoldState();
}

class _AuthBackgroundScaffoldState extends State<AuthBackgroundScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF4F7FB), Color(0xFFF1F5F9)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DotsPainter(progress: _controller.value),
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: widget.maxWidth),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: compact ? 56 : 66,
          height: compact ? 56 : 66,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF15A39A), Color(0xFF0E9B90)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3315A39A),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.psychology_alt_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'MindNest',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF071937),
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.progress});

  final double progress;

  static final List<_DotPoint> _points = List<_DotPoint>.generate(170, (index) {
    final random = math.Random(index * 13 + 7);
    return _DotPoint(
      x: random.nextDouble(),
      y: random.nextDouble(),
      r: random.nextDouble() * 1.7 + 0.6,
      phase: random.nextDouble() * math.pi * 2,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final animatedPhase = progress * math.pi * 2;

    for (final point in _points) {
      final pulse = (math.sin(animatedPhase + point.phase) + 1) / 2;
      paint.color =
          Color.lerp(
            const Color(0x220BA4FF),
            const Color(0x7F0BA4FF),
            0.25 + 0.4 * pulse,
          ) ??
          const Color(0x220BA4FF);

      canvas.drawCircle(
        Offset(point.x * size.width, point.y * size.height),
        point.r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _DotPoint {
  const _DotPoint({
    required this.x,
    required this.y,
    required this.r,
    required this.phase,
  });

  final double x;
  final double y;
  final double r;
  final double phase;
}
