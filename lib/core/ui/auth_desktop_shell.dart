import 'package:flutter/material.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/windows_desktop_window_controls.dart';

class AuthDesktopShell extends StatelessWidget {
  const AuthDesktopShell({
    super.key,
    required this.formChild,
    required this.heroHighlightText,
    required this.heroBaseText,
    required this.heroDescription,
    this.heroSupplement,
    this.formMaxWidth = 560,
  });

  final Widget formChild;
  final String heroHighlightText;
  final String heroBaseText;
  final String heroDescription;
  final Widget? heroSupplement;
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
                          heroSupplement: heroSupplement,
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
  });

  final String heroHighlightText;
  final String heroBaseText;
  final String heroDescription;
  final Widget? heroSupplement;

  @override
  Widget build(BuildContext context) {
    final hasDescription = heroDescription.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 28, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              BrandMark(compact: true, showText: false, withBlob: false),
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
          const SizedBox(height: 36),
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
          if (hasDescription) ...[
            const SizedBox(height: 30),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Text(
                heroDescription,
                style: const TextStyle(
                  color: Color(0xFF4C607A),
                  fontSize: 31,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
          if (heroSupplement != null) ...[
            SizedBox(height: hasDescription ? 34 : 42),
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
