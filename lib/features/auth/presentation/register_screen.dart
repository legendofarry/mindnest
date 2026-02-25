import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  static const _desktopBreakpoint = 1100.0;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(
          children: [
            Container(
              height: 52,
              color: const Color(0xFF171717),
              alignment: Alignment.center,
              child: const Text(
                'MindNest V1 - Mental Wellness Platform',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  const Expanded(child: _DesktopMarketingPanel()),
                  Expanded(
                    child: Container(
                      color: const Color(0xFFF8FAFC),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 24,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: _RegisterContent(
                              showBrand: false,
                              isDesktop: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

class _DesktopMarketingPanel extends StatelessWidget {
  const _DesktopMarketingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(76, 74, 76, 68),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF118F88), Color(0xFF0D6E6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _DesktopBrandIcon(),
              SizedBox(width: 16),
              Text(
                'MindNest',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'Start your journey to\nbetter mental wellness.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 43,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 26),
          const Text(
            'Create one account first, then join your institution\nlater with a join code from your admin.',
            style: TextStyle(
              color: Color(0xFFA9EFE8),
              fontSize: 23,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          const Row(
            children: [
              _MetricItem(value: '120k+', label: 'USERS HELPED'),
              SizedBox(width: 48),
              _MetricItem(value: '450+', label: 'INSTITUTIONS'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopBrandIcon extends StatelessWidget {
  const _DesktopBrandIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFECFDF5),
      ),
      child: const Icon(Icons.psychology_alt_rounded, color: Color(0xFF0E9B90)),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFA9EFE8),
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w800,
          ),
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
