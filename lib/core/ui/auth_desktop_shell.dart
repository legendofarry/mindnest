import 'package:flutter/material.dart';

class AuthDesktopShell extends StatelessWidget {
  const AuthDesktopShell({
    super.key,
    required this.formChild,
    required this.heroHighlightText,
    required this.heroBaseText,
    required this.heroDescription,
    required this.metrics,
    this.formMaxWidth = 560,
  });

  final Widget formChild;
  final String heroHighlightText;
  final String heroBaseText;
  final String heroDescription;
  final List<AuthDesktopMetric> metrics;
  final double formMaxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFC),
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthDesktopAmbientBackground()),
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
                          metrics: metrics,
                        ),
                      ),
                      const SizedBox(width: 54),
                      Expanded(
                        flex: 5,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: formMaxWidth),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: const Color(0xFFBEE9E4),
                                  width: 1.1,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x140F172A),
                                    blurRadius: 36,
                                    offset: Offset(0, 18),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  34,
                                  28,
                                  34,
                                  26,
                                ),
                                child: formChild,
                              ),
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
        ],
      ),
    );
  }
}

class AuthDesktopMetric {
  const AuthDesktopMetric({required this.value, required this.label});

  final String value;
  final String label;
}

class _AuthDesktopHero extends StatelessWidget {
  const _AuthDesktopHero({
    required this.heroHighlightText,
    required this.heroBaseText,
    required this.heroDescription,
    required this.metrics,
  });

  final String heroHighlightText;
  final String heroBaseText;
  final String heroDescription;
  final List<AuthDesktopMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 28, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _AuthDesktopBrandIcon(),
              SizedBox(width: 14),
              Text(
                'MindNest',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 41,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 42),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$heroHighlightText\n',
                  style: const TextStyle(
                    color: Color(0xFF0E9B90),
                    fontSize: 74,
                    fontWeight: FontWeight.w800,
                    height: 0.98,
                    letterSpacing: -1.9,
                  ),
                ),
                TextSpan(
                  text: heroBaseText,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 74,
                    fontWeight: FontWeight.w800,
                    height: 0.98,
                    letterSpacing: -1.9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Text(
              heroDescription,
              style: const TextStyle(
                color: Color(0xFF4C607A),
                fontSize: 31,
                height: 1.38,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 54),
          Row(
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                _AuthDesktopMetricItem(metric: metrics[i]),
                if (i < metrics.length - 1) const SizedBox(width: 54),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthDesktopBrandIcon extends StatelessWidget {
  const _AuthDesktopBrandIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF15CFC2),
      ),
      child: const Icon(
        Icons.psychology_alt_rounded,
        color: Color(0xFF0A3B37),
        size: 25,
      ),
    );
  }
}

class _AuthDesktopMetricItem extends StatelessWidget {
  const _AuthDesktopMetricItem({required this.metric});

  final AuthDesktopMetric metric;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric.value,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 49,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          metric.label,
          style: const TextStyle(
            color: Color(0xFF0E9B90),
            fontSize: 15,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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
