// features/auth/presentation/register_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/auth_desktop_shell.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({
    super.key,
    this.inviteId,
    this.invitedEmail,
    this.invitedName,
    this.institutionName,
    this.intendedRole,
    this.registrationIntent,
  });
  static const _desktopBreakpoint = 1100.0;

  final String? inviteId;
  final String? invitedEmail;
  final String? invitedName;
  final String? institutionName;
  final String? intendedRole;
  final String? registrationIntent;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    if (isDesktop) {
      return AuthDesktopShell(
        heroHighlightText: 'Start your journey',
        heroBaseText: 'to better mental wellness.',
        heroDescription:
            'Create one account first, then join your institution later with '
            'a join code from your admin.',
        metrics: [
          AuthDesktopMetric(value: '3+', label: 'USERS HELPED'),
          AuthDesktopMetric(value: '1+', label: 'INSTITUTIONS'),
        ],
        formChild: _RegisterContent(
          showBrand: false,
          isDesktop: true,
          inviteId: inviteId,
          invitedEmail: invitedEmail,
          invitedName: invitedName,
          institutionName: institutionName,
          intendedRole: intendedRole,
          registrationIntent: registrationIntent,
        ),
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      maxWidth: 460,
      child: _RegisterContent(
        showBrand: true,
        isDesktop: false,
        inviteId: inviteId,
        invitedEmail: invitedEmail,
        invitedName: invitedName,
        institutionName: institutionName,
        intendedRole: intendedRole,
        registrationIntent: registrationIntent,
      ),
    );
  }
}

class _RegisterContent extends StatelessWidget {
  const _RegisterContent({
    required this.showBrand,
    required this.isDesktop,
    this.inviteId,
    this.invitedEmail,
    this.invitedName,
    this.institutionName,
    this.intendedRole,
    this.registrationIntent,
  });

  final bool showBrand;
  final bool isDesktop;
  final String? inviteId;
  final String? invitedEmail;
  final String? invitedName;
  final String? institutionName;
  final String? intendedRole;
  final String? registrationIntent;

  Map<String, String> get _inviteQuery => AppRoute.inviteQuery(
    inviteId: inviteId ?? '',
    invitedEmail: invitedEmail,
    invitedName: invitedName,
    institutionName: institutionName,
    intendedRole: intendedRole,
  );
  String get _normalizedRegistrationIntent => (registrationIntent ?? '').trim();
  bool get _hasInviteContext => _inviteQuery.isNotEmpty;

  String _registerDetailsRoute({String? routeRegistrationIntent}) {
    return AppRoute.withInviteAndRegistrationIntent(
      AppRoute.registerDetails,
      _inviteQuery,
      registrationIntent: routeRegistrationIntent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showSideBySideMobileChoices = !isDesktop && !_hasInviteContext;
    final createAccountCard = _AccountTypeCard(
      icon: Icons.account_circle_outlined,
      title: 'Create Account',
      description: 'Use wellness tools and access resources.',
      compact: showSideBySideMobileChoices,
      onTap: () => context.go(_registerDetailsRoute()),
    );
    final counselorCard = _AccountTypeCard(
      icon: Icons.psychology_alt_outlined,
      title: 'I am a Counselor',
      description: 'Create your account for institution counselor.',
      compact: showSideBySideMobileChoices,
      onTap: () => context.go(
        _registerDetailsRoute(
          routeRegistrationIntent: UserProfile.counselorRegistrationIntent,
        ),
      ),
    );

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
          _inviteQuery.isNotEmpty
              ? 'Finish registration to accept your invitation${(institutionName ?? '').trim().isNotEmpty ? ' to ${(institutionName ?? '').trim()}' : ''}.'
              : 'Create your MindNest account first, then join your institution from Home if you have a join code.',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF516784),
            height: 1.35,
          ),
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
        ),
        const SizedBox(height: 26),
        if (_inviteQuery.isNotEmpty) ...[
          _AccountTypeCard(
            icon: Icons.mark_email_unread_rounded,
            title: 'Continue Invite Registration',
            description:
                'Create your account with the invited email, then accept the invite instantly.',
            onTap: () => context.go(
              AppRoute.withInviteAndRegistrationIntent(
                AppRoute.registerDetails,
                _inviteQuery,
                registrationIntent: _normalizedRegistrationIntent,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showSideBySideMobileChoices) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: createAccountCard),
              const SizedBox(width: 10),
              Expanded(child: counselorCard),
            ],
          ),
        ] else ...[
          createAccountCard,
          if (!_hasInviteContext) ...[
            const SizedBox(height: 12),
            counselorCard,
          ],
        ],
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
              onTap: () => context.go(
                AppRoute.withInviteQuery(AppRoute.login, _inviteQuery),
              ),
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
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () => context.go(AppRoute.registerInstitution),
            child: const Text(
              'Institution Admin? Register Institution',
              style: TextStyle(color: Color(0xFF6A7D96)),
            ),
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
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_AccountTypeCard> createState() => _AccountTypeCardState();
}

class _AccountTypeCardState extends State<_AccountTypeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cardPadding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 16)
        : const EdgeInsets.symmetric(horizontal: 22, vertical: 24);
    final borderRadius = widget.compact ? 22.0 : 30.0;
    final iconSize = widget.compact ? 52.0 : 72.0;
    final iconGlyphSize = widget.compact ? 28.0 : 36.0;
    final titleStyle = widget.compact
        ? Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF071937),
            letterSpacing: -0.2,
          )
        : Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF071937),
            letterSpacing: -0.4,
          );
    final descriptionStyle = widget.compact
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF516784),
            height: 1.35,
          )
        : Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF516784),
            height: 1.45,
          );

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
          padding: cardPadding,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(borderRadius),
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
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F3F1),
                  borderRadius: BorderRadius.circular(widget.compact ? 14 : 18),
                ),
                child: Icon(
                  widget.icon,
                  size: iconGlyphSize,
                  color: const Color(0xFF0E9B90),
                ),
              ),
              SizedBox(height: widget.compact ? 14 : 22),
              Text(widget.title, style: titleStyle),
              SizedBox(height: widget.compact ? 8 : 12),
              Text(
                widget.description,
                style: descriptionStyle,
                maxLines: widget.compact ? 5 : null,
                overflow: widget.compact ? TextOverflow.ellipsis : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
