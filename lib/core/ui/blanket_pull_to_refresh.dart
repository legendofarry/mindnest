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
  static const double _maxPullDistance = 132;
  static const double _refreshHoldDistance = 66;
  static const double _overlayHeight = 188;

  late final AnimationController _fxController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
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
    await Future<void>.delayed(const Duration(milliseconds: 120));
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
                    : const Duration(milliseconds: 350),
                curve: _dragging ? Curves.linear : Curves.easeOutBack,
                builder: (context, pull, _) {
                  final progress = (pull / _maxPullDistance).clamp(0.0, 1.0);
                  final glowT = Curves.easeOut.transform(_glowController.value);
                  if (progress <= 0.001 && !_refreshing && glowT <= 0.001) {
                    return const SizedBox.shrink();
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : MediaQuery.sizeOf(context).width;
                      final metrics = _FoldMetrics.compute(
                        width: width,
                        progress: progress,
                        shimmerT: _fxController.value,
                        refreshing: _refreshing,
                      );

                      final handOpacity = (0.24 + (progress * 0.9)).clamp(
                        0.0,
                        1.0,
                      );
                      final handScale = ui.lerpDouble(0.82, 1.06, progress)!;
                      final handSize = ui.lerpDouble(40, 58, progress)!;
                      final dotScale = _refreshing
                          ? 0.86 +
                                (math.sin(_fxController.value * math.pi * 2) *
                                    0.10)
                          : (1 - glowT * 0.35);
                      final showDot = _refreshing || glowT > 0.01;

                      return SizedBox(
                        height: _overlayHeight,
                        child: Stack(
                          children: [
                            AnimatedBuilder(
                              animation: Listenable.merge([
                                _fxController,
                                _glowController,
                              ]),
                              builder: (context, _) {
                                return CustomPaint(
                                  size: Size(width, _overlayHeight),
                                  painter: _BlanketFoldPainter(
                                    metrics: metrics,
                                    progress: progress,
                                    shimmerT: _fxController.value,
                                    glowT: glowT,
                                    refreshing: _refreshing,
                                    primary: scheme.primary,
                                    secondary: scheme.secondary,
                                  ),
                                );
                              },
                            ),
                            Positioned(
                              left: metrics.centerX - (handSize / 2),
                              top: metrics.handY,
                              child: Opacity(
                                opacity: handOpacity,
                                child: Transform.scale(
                                  scale: handScale,
                                  child: _GrabHand(size: handSize),
                                ),
                              ),
                            ),
                            if (showDot)
                              Positioned(
                                left: metrics.centerX - 5,
                                top: metrics.pinchY + 30,
                                child: Transform.scale(
                                  scale: dotScale,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: scheme.onSurface.withValues(
                                        alpha: _refreshing ? 0.40 : 0.28,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: scheme.secondary.withValues(
                                            alpha: 0.22 * (1 - glowT),
                                          ),
                                          blurRadius: 10,
                                          spreadRadius: 1.5,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
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

class _FoldMetrics {
  const _FoldMetrics({
    required this.centerX,
    required this.rimY,
    required this.pinchY,
    required this.handY,
  });

  final double centerX;
  final double rimY;
  final double pinchY;
  final double handY;

  static _FoldMetrics compute({
    required double width,
    required double progress,
    required double shimmerT,
    required bool refreshing,
  }) {
    final eased = Curves.easeOutCubic.transform(progress);
    final travel = ui.lerpDouble(0, 116, eased)!;
    final rimY = ui.lerpDouble(0, 28, progress)!;
    final wave = refreshing ? math.sin(shimmerT * math.pi * 2) * 3.6 : 0.0;
    final drift = refreshing ? math.sin(shimmerT * math.pi * 2.2) * 5.5 : 0.0;
    final centerX = (width / 2) + drift;
    final pinchY = rimY + travel + wave;
    final handY = pinchY - ui.lerpDouble(46, 38, progress)!;

    return _FoldMetrics(
      centerX: centerX,
      rimY: rimY,
      pinchY: pinchY,
      handY: handY,
    );
  }
}

class _BlanketFoldPainter extends CustomPainter {
  const _BlanketFoldPainter({
    required this.metrics,
    required this.progress,
    required this.shimmerT,
    required this.glowT,
    required this.refreshing,
    required this.primary,
    required this.secondary,
  });

  final _FoldMetrics metrics;
  final double progress;
  final double shimmerT;
  final double glowT;
  final bool refreshing;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001 && glowT <= 0.001) {
      return;
    }

    final centerX = metrics.centerX;
    final rimY = metrics.rimY;
    final pinchY = metrics.pinchY;

    final sheetPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, rimY)
      ..cubicTo(
        size.width * 0.86,
        rimY + (pinchY * 0.36),
        centerX + 62,
        pinchY + 8,
        centerX,
        pinchY + 12,
      )
      ..cubicTo(
        centerX - 62,
        pinchY + 8,
        size.width * 0.14,
        rimY + (pinchY * 0.36),
        0,
        rimY,
      )
      ..close();

    final sheetFill = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, pinchY + 24),
        [
          Colors.white.withValues(alpha: 0.92),
          Colors.white.withValues(alpha: 0.90),
          secondary.withValues(alpha: 0.06 + (progress * 0.06)),
        ],
        const [0, 0.62, 1],
      );
    canvas.drawPath(sheetPath, sheetFill);

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = primary.withValues(alpha: 0.10 + (progress * 0.14));
    final edgePath = Path()
      ..moveTo(0, rimY)
      ..cubicTo(
        size.width * 0.86,
        rimY + (pinchY * 0.36),
        centerX + 62,
        pinchY + 8,
        centerX,
        pinchY + 12,
      )
      ..cubicTo(
        centerX - 62,
        pinchY + 8,
        size.width * 0.14,
        rimY + (pinchY * 0.36),
        0,
        rimY,
      );
    canvas.drawPath(edgePath, edgePaint);

    canvas.save();
    canvas.clipPath(sheetPath);
    _drawWrinkles(canvas, size, leftSide: true);
    _drawWrinkles(canvas, size, leftSide: false);

    if (refreshing) {
      final shimmerCenter = (size.width * shimmerT);
      final shimmerPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(shimmerCenter - 120, 0),
          Offset(shimmerCenter + 120, 0),
          [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.18),
            Colors.transparent,
          ],
          const [0, 0.5, 1],
        )
        ..blendMode = BlendMode.plus;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, pinchY + 40),
        shimmerPaint,
      );
    }
    canvas.restore();

    final pinchShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.09 * progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, pinchY + 10),
        width: 86,
        height: 24,
      ),
      pinchShadowPaint,
    );

    if (glowT > 0.001) {
      final glowRadius = ui.lerpDouble(10, 34, glowT)!;
      final glowPaint = Paint()
        ..color = secondary.withValues(alpha: (1 - glowT) * 0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(Offset(centerX, pinchY + 22), glowRadius, glowPaint);
    }
  }

  void _drawWrinkles(Canvas canvas, Size size, {required bool leftSide}) {
    final sign = leftSide ? -1.0 : 1.0;
    final lineCount = 5;
    for (var i = 0; i < lineCount; i++) {
      final spread = 34 + (i * 26);
      final endX = (metrics.centerX + (sign * spread)).clamp(0.0, size.width);
      final endY = metrics.rimY + 2 + (i * 4.0);
      final c1x = metrics.centerX + (sign * (14 + (i * 9.0)));
      final c1y = metrics.pinchY - (8 + (i * 5.2));
      final c2x = metrics.centerX + (sign * (30 + (i * 16.0)));
      final c2y = metrics.rimY + 14 + (i * 6.0);

      final wrinklePath = Path()
        ..moveTo(metrics.centerX + (sign * 7), metrics.pinchY + 2)
        ..cubicTo(c1x, c1y, c2x, c2y, endX, endY);

      final shadowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.3
        ..color = Colors.black.withValues(
          alpha: (0.08 - (i * 0.01)).clamp(0.02, 0.08) * progress,
        );
      canvas.drawPath(wrinklePath, shadowPaint);

      final highlightPath = Path()
        ..moveTo(metrics.centerX + (sign * 8.5), metrics.pinchY + 0.8)
        ..cubicTo(c1x, c1y - 1.4, c2x, c2y - 1.2, endX, endY - 1.0);
      final highlightPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(
          alpha: (0.46 - (i * 0.06)).clamp(0.12, 0.46) * progress,
        );
      canvas.drawPath(highlightPath, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlanketFoldPainter oldDelegate) {
    return oldDelegate.metrics.centerX != metrics.centerX ||
        oldDelegate.metrics.rimY != metrics.rimY ||
        oldDelegate.metrics.pinchY != metrics.pinchY ||
        oldDelegate.progress != progress ||
        oldDelegate.shimmerT != shimmerT ||
        oldDelegate.glowT != glowT ||
        oldDelegate.refreshing != refreshing ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary;
  }
}

class _GrabHand extends StatelessWidget {
  const _GrabHand({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.18,
      child: CustomPaint(painter: _GrabHandPainter()),
    );
  }
}

class _GrabHandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wristPaint = Paint()..color = const Color(0xFFF7C6BE);
    final wristRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.34,
        0,
        size.width * 0.32,
        size.height * 0.36,
      ),
      Radius.circular(size.width * 0.14),
    );
    canvas.drawRRect(wristRect, wristPaint);

    final palmPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width * 0.18, size.height * 0.30),
        Offset(size.width * 0.66, size.height * 0.96),
        const [Color(0xFFF8CEC7), Color(0xFFEFB7AE)],
      );
    final palmRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.16,
        size.height * 0.30,
        size.width * 0.68,
        size.height * 0.56,
      ),
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(palmRect, palmPaint);

    final fingerPaint = Paint()..color = const Color(0xFFF8CEC7);
    final fingerY = size.height * 0.36;
    final fingerRadius = size.width * 0.10;
    for (var i = 0; i < 4; i++) {
      final cx = size.width * (0.28 + (i * 0.14));
      final cy = fingerY + (i == 0 || i == 3 ? 2 : 0);
      canvas.drawCircle(Offset(cx, cy), fingerRadius, fingerPaint);
    }

    final thumbRect = Rect.fromCenter(
      center: Offset(size.width * 0.80, size.height * 0.56),
      width: size.width * 0.18,
      height: size.height * 0.24,
    );
    canvas.drawOval(thumbRect, Paint()..color = const Color(0xFFF2B9AF));

    final shinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.42, size.height * 0.54),
        width: size.width * 0.30,
        height: size.height * 0.18,
      ),
      shinePaint,
    );

    final handShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.52, size.height * 0.90),
        width: size.width * 0.40,
        height: size.height * 0.12,
      ),
      handShadow,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
