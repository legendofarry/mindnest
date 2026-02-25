// features/auth/presentation/register_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/auth_desktop_shell.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  static const _desktopBreakpoint = 1100.0;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    if (isDesktop) {
      return const AuthDesktopShell(
        heroHighlightText: 'Start your journey',
        heroBaseText: 'to better mental wellness.',
        heroDescription:
            'Create one account first, then join your institution later with '
            'a join code from your admin.',
        metrics: [
          AuthDesktopMetric(value: '3+', label: 'USERS HELPED'),
          AuthDesktopMetric(value: '1+', label: 'INSTITUTIONS'),
        ],
        formChild: _RegisterContent(showBrand: false, isDesktop: true),
      );
    }

    return const AuthBackgroundScaffold(
      fallingSnow: true,
      maxWidth: 460,
      child: _RegisterContent(showBrand: true, isDesktop: false),
    );
  }
}

class _RegisterContent extends StatelessWidget {
  const _RegisterContent({required this.showBrand, required this.isDesktop});

  final bool showBrand;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBrand) ...[
          const SizedBox(height: 6),
          const BrandMark(compact: true),
          const SizedBox(height: 20),
        ] else ...[
          const SizedBox(height: 8),
        ],
        Text(
          'Create Account',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF071937),
            letterSpacing: -0.7,
          ),
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Create your MindNest account first, then join your institution from Home if you have a join code.',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF516784),
            height: 1.35,
          ),
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
        ),
        const SizedBox(height: 26),
        _AccountTypeCard(
          icon: Icons.account_circle_outlined,
          title: 'Create Account',
          description:
              'Use wellness tools, track your mood, and access resources. You can connect to an institution after sign-up.',
          onTap: () => context.go(AppRoute.registerDetails),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account? ',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: const Color(0xFF4A607C)),
            ),
            GestureDetector(
              onTap: () => context.go(AppRoute.login),
              child: const Text(
                'Log In',
                style: TextStyle(
                  color: Color(0xFF0E9B90),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccountTypeCard extends StatefulWidget {
  const _AccountTypeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  State<_AccountTypeCard> createState() => _AccountTypeCardState();
}

class _AccountTypeCardState extends State<_AccountTypeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.diagonal3Values(
            _hovered ? 1.01 : 1,
            _hovered ? 1.01 : 1,
            1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFDDE6F1)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F3F1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  widget.icon,
                  size: 36,
                  color: const Color(0xFF0E9B90),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF071937),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.description,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF516784),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
