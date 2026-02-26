import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class BlanketPullToRefresh extends StatefulWidget {
  const BlanketPullToRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  final Widget child;
  final Future<void> Function() onRefresh;

  @override
  State<BlanketPullToRefresh> createState() => _BlanketPullToRefreshState();
}

class _BlanketPullToRefreshState extends State<BlanketPullToRefresh>
    with TickerProviderStateMixin {
  static const double _maxPullDistance = 110;
  static const double _refreshHoldDistance = 54;

  late final AnimationController _fxController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  double _targetPull = 0;
  bool _refreshing = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _fxController.repeat();
  }

  @override
  void dispose() {
    _fxController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_refreshing) {
      return false;
    }

    final metrics = notification.metrics;
    final atTopEdge =
        metrics.axis == Axis.vertical &&
        metrics.pixels <= metrics.minScrollExtent;

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        atTopEdge) {
      _dragging = true;
    }

    if ((notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        notification is OverscrollNotification) {
      if (!atTopEdge) {
        return false;
      }
      final overscroll = (metrics.minScrollExtent - metrics.pixels)
          .clamp(0, _maxPullDistance)
          .toDouble();
      if (overscroll != _targetPull) {
        setState(() => _targetPull = overscroll);
      }
    }

    if (notification is ScrollEndNotification) {
      _dragging = false;
      if (!_refreshing && _targetPull > 0) {
        setState(() => _targetPull = 0);
      }
    }

    return false;
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _refreshing = true;
      _targetPull = _refreshHoldDistance;
    });

    await widget.onRefresh();

    if (!mounted) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) {
      return;
    }

    _glowController
      ..stop()
      ..value = 0
      ..forward();

    setState(() {
      _refreshing = false;
      _targetPull = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _handleRefresh,
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            strokeWidth: 0.001,
            displacement: _refreshHoldDistance,
            child: widget.child,
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _targetPull),
                duration: _dragging
                    ? const Duration(milliseconds: 40)
                    : const Duration(milliseconds: 340),
                curve: _dragging ? Curves.linear : Curves.easeOutBack,
                builder: (context, pull, _) {
                  final progress = (pull / _maxPullDistance).clamp(0.0, 1.0);
                  if (progress <= 0.001 && !_refreshing) {
                    return const SizedBox.shrink();
                  }
                  return AnimatedBuilder(
                    animation: Listenable.merge([
                      _fxController,
                      _glowController,
                    ]),
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _BlanketFoldPainter(
                          progress: progress,
                          shimmerT: _fxController.value,
                          glowT: Curves.easeOut.transform(
                            _glowController.value,
                          ),
                          refreshing: _refreshing,
                          primary: scheme.primary,
                          secondary: scheme.secondary,
                        ),
                        size: Size(MediaQuery.sizeOf(context).width, 140),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlanketFoldPainter extends CustomPainter {
  const _BlanketFoldPainter({
    required this.progress,
    required this.shimmerT,
    required this.glowT,
    required this.refreshing,
    required this.primary,
    required this.secondary,
  });

  final double progress;
  final double shimmerT;
  final double glowT;
  final bool refreshing;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) {
      return;
    }

    final foldDepth = ui.lerpDouble(0, 86, progress)!;
    final wave = refreshing ? math.sin(shimmerT * 2 * math.pi) : 0.0;
    final bottomY = foldDepth + (wave * 4);

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, bottomY * 0.55)
      ..quadraticBezierTo(
        size.width * 0.74,
        bottomY + 12 + (wave * 3),
        size.width * 0.5,
        bottomY + 15 + (wave * 4),
      )
      ..quadraticBezierTo(
        size.width * 0.26,
        bottomY + 12 + (wave * 3),
        0,
        bottomY * 0.55,
      )
      ..close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, bottomY + 22),
        [
          primary.withValues(alpha: 0.22 * progress),
          secondary.withValues(alpha: 0.14 * progress),
          secondary.withValues(alpha: 0.06 * progress),
        ],
        const [0, 0.55, 1],
      );
    canvas.drawPath(path, fillPaint);

    final edgePath = Path()
      ..moveTo(0, bottomY * 0.55)
      ..quadraticBezierTo(
        size.width * 0.74,
        bottomY + 12 + (wave * 3),
        size.width * 0.5,
        bottomY + 15 + (wave * 4),
      )
      ..quadraticBezierTo(
        size.width * 0.26,
        bottomY + 12 + (wave * 3),
        0,
        bottomY * 0.55,
      );

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = primary.withValues(alpha: 0.30 * progress);
    canvas.drawPath(edgePath, edgePaint);

    if (refreshing) {
      final shimmerCenter = (size.width * shimmerT);
      final shimmerPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(shimmerCenter - 90, 0),
          Offset(shimmerCenter + 90, 0),
          [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.16),
            Colors.transparent,
          ],
          const [0, 0.5, 1],
        )
        ..blendMode = BlendMode.plus;

      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, bottomY + 30),
        shimmerPaint,
      );
      canvas.restore();
    }

    if (glowT > 0) {
      final glowRadius = ui.lerpDouble(6, 28, glowT)!;
      final glowPaint = Paint()
        ..color = secondary.withValues(alpha: (1 - glowT) * 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(
        Offset(size.width / 2, bottomY + 6),
        glowRadius,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BlanketFoldPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.shimmerT != shimmerT ||
        oldDelegate.glowT != glowT ||
        oldDelegate.refreshing != refreshing ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary;
  }
}
