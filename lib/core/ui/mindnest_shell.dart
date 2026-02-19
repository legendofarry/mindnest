import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class MindNestShell extends StatefulWidget {
  const MindNestShell({
    super.key,
    required this.child,
    this.appBar,
    this.padding = const EdgeInsets.all(20),
    this.maxWidth = 460,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final EdgeInsets padding;
  final double maxWidth;

  @override
  State<MindNestShell> createState() => _MindNestShellState();
}

class _MindNestShellState extends State<MindNestShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 2 * math.pi;
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFE5FAF6),
                  Color(0xFFD5EEF8),
                  Color(0xFFCFE8FF),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                _AnimatedBlob(
                  left: -120 + math.sin(t) * 30,
                  top: 20 + math.cos(t * 1.2) * 20,
                  size: 260,
                  color: const Color(0x550EA5A0),
                ),
                _AnimatedBlob(
                  right: -90 + math.cos(t * 0.8) * 24,
                  top: 220 + math.sin(t * 1.4) * 20,
                  size: 220,
                  color: const Color(0x553B82F6),
                ),
                _AnimatedBlob(
                  left: 130 + math.cos(t * 1.1) * 14,
                  bottom: -100 + math.sin(t * 0.7) * 30,
                  size: 260,
                  color: const Color(0x5599F6E4),
                ),
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: widget.padding,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: widget.maxWidth),
                        child: FadeSlideIn(child: widget.child),
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

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x33FFFFFF)),
            color: const Color(0xAAFFFFFF),
            boxShadow: const [
              BoxShadow(
                color: Color(0x200F172A),
                offset: Offset(0, 18),
                blurRadius: 36,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 520),
  });

  final Widget child;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.05),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class _AnimatedBlob extends StatelessWidget {
  const _AnimatedBlob({
    this.left,
    this.top,
    this.right,
    this.bottom,
    required this.size,
    required this.color,
  });

  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 80, spreadRadius: 10),
          ],
        ),
      ),
    );
  }
}
