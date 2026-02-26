// core/ui/mindnest_shell.dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mindnest/core/ui/blanket_pull_to_refresh.dart';

enum MindNestBackgroundMode { defaultShell, homeStyle }

class MindNestShell extends StatefulWidget {
  const MindNestShell({
    super.key,
    required this.child,
    this.appBar,
    this.padding = const EdgeInsets.all(20),
    this.maxWidth = 460,
    this.backgroundMode = MindNestBackgroundMode.defaultShell,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.onRefresh,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final EdgeInsets padding;
  final double maxWidth;
  final MindNestBackgroundMode backgroundMode;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Future<void> Function()? onRefresh;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasAppBar = widget.appBar != null;
    final effectivePadding = hasAppBar
        ? widget.padding.copyWith(top: widget.appBar!.preferredSize.height - 30)
        : widget.padding;
    return Scaffold(
      appBar: widget.appBar,
      extendBodyBehindAppBar: true,
      floatingActionButton: widget.floatingActionButton,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 2 * math.pi;
          final gradientColors =
              widget.backgroundMode == MindNestBackgroundMode.homeStyle
              ? (isDark
                    ? const [Color(0xFF0B1220), Color(0xFF0E1A2E)]
                    : const [Color(0xFFF4F7FB), Color(0xFFF1F5F9)])
              : const [Color(0xFFE5FAF6), Color(0xFFD5EEF8), Color(0xFFCFE8FF)];
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                if (widget.backgroundMode ==
                    MindNestBackgroundMode.homeStyle) ...[
                  _AnimatedBlob(
                    left: -70 + math.sin(t) * 28,
                    top: -10 + math.cos(t * 1.2) * 20,
                    size: 320,
                    color: isDark
                        ? const Color(0x2E38BDF8)
                        : const Color(0x300BA4FF),
                  ),
                  _AnimatedBlob(
                    right: -70 + math.cos(t * 0.9) * 24,
                    top: 150 + math.sin(t * 1.3) * 18,
                    size: 340,
                    color: isDark
                        ? const Color(0x2E14B8A6)
                        : const Color(0x2A15A39A),
                  ),
                  _AnimatedBlob(
                    left: 70 + math.cos(t * 1.1) * 18,
                    bottom: -90 + math.sin(t * 0.75) * 22,
                    size: 280,
                    color: isDark
                        ? const Color(0x2E22D3EE)
                        : const Color(0x2418A89D),
                  ),
                ] else ...[
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
                ],
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: (widget.onRefresh == null
                        ? SingleChildScrollView(
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding: effectivePadding,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: widget.maxWidth,
                              ),
                              child: FadeSlideIn(child: widget.child),
                            ),
                          )
                        : BlanketPullToRefresh(
                            onRefresh: widget.onRefresh!,
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: effectivePadding,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: widget.maxWidth,
                                ),
                                child: FadeSlideIn(child: widget.child),
                              ),
                            ),
                          )),
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
