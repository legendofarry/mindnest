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
    final hasInviteContext = AppRoute.inviteQuery(
      inviteId: inviteId ?? '',
      invitedEmail: invitedEmail,
      invitedName: invitedName,
      institutionName: institutionName,
      intendedRole: intendedRole,
    ).isNotEmpty;

    if (isDesktop) {
      return AuthDesktopShell(
        heroHighlightText: 'Start your journey',
        heroBaseText: 'to better mental wellness.',
        heroDescription: '',
        heroSupplement: _RegisterDesktopSupportPanel(
          hasInviteContext: hasInviteContext,
          institutionName: institutionName,
        ),
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
    final showSideBySideChoices = !_hasInviteContext;
    final createAccountCard = _AccountTypeCard(
      icon: Icons.account_circle_outlined,
      title: 'Create Account',
      description: 'For students and staff joining an institution.',
      compact: showSideBySideChoices,
      onTap: () => context.go(_registerDetailsRoute()),
    );
    final counselorCard = _AccountTypeCard(
      icon: Icons.psychology_alt_outlined,
      title: "I'm a Counselor",
      description: 'For counselors joining an institution.',
      compact: showSideBySideChoices,
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
          BrandMark(
            compact: true,
            withBlob: true,
            showText: isDesktop, // hide MindNest text on mobile, keep glyph
          ),
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFFFFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFB3ECDD)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E9B90).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.tips_and_updates_outlined,
                  color: Color(0xFF0E9B90),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _inviteQuery.isNotEmpty
                      ? 'Finish registration to accept your invitation${(institutionName ?? '').trim().isNotEmpty ? ' to ${(institutionName ?? '').trim()}' : ''}.'
                      : "Students and staff: choose Create Account.\nCounselors: choose I'm a Counselor.",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF0D6F69),
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
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
        if (showSideBySideChoices) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: createAccountCard),
              const SizedBox(width: 12),
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
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account? ',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: const Color(0xFF4A607C)),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
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
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () => context.go(AppRoute.registerInstitution),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF0E9B90), // button background
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Register Institution',
              style: TextStyle(color: Colors.white), // text color
            ),
          ),
        ),
      ],
    );
  }
}

class _RegisterDesktopSupportPanel extends StatelessWidget {
  const _RegisterDesktopSupportPanel({
    required this.hasInviteContext,
    this.institutionName,
  });

  final bool hasInviteContext;
  final String? institutionName;

  @override
  Widget build(BuildContext context) {
    return _DesktopSupportCard(
      eyebrow: hasInviteContext ? 'What Happens Next' : 'How Sign Up Works',
      title: hasInviteContext
          ? 'Finish sign up in three guided steps.'
          : 'Get started in three simple steps.',
      child: Column(
        children: hasInviteContext
            ? [
                _DesktopStepRow(
                  number: '1',
                  title: 'Use the invited email',
                  description:
                      'Create your account with the same email that received the invitation.',
                ),
                const SizedBox(height: 14),
                _DesktopStepRow(
                  number: '2',
                  title: 'Verify your email',
                  description:
                      'We will send a verification email before you continue.',
                ),
                const SizedBox(height: 14),
                _DesktopStepRow(
                  number: '3',
                  title: 'Join the workspace',
                  description: (institutionName ?? '').trim().isEmpty
                      ? 'After you sign in, you can accept the invitation and enter your workspace.'
                      : 'After you sign in, you can join ${(institutionName ?? '').trim()}.',
                ),
              ]
            : const [
                _DesktopStepRow(
                  number: '1',
                  title: 'Choose your account type',
                  description:
                      'Pick Create Account for students and staff, or I\'m a Counselor if you will join as a counselor.',
                ),
                SizedBox(height: 14),
                _DesktopStepRow(
                  number: '2',
                  title: 'Enter your details',
                  description:
                      'Add your name, email, phone number, and password on the next screen.',
                ),
                SizedBox(height: 14),
                _DesktopStepRow(
                  number: '3',
                  title: 'Verify your email',
                  description:
                      'Open the verification email we send you, then continue into MindNest.',
                ),
              ],
      ),
    );
  }
}

class _DesktopSupportCard extends StatelessWidget {
  const _DesktopSupportCard({
    required this.eyebrow,
    required this.title,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD5E8EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: Color(0xFF0E9B90),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DesktopStepRow extends StatelessWidget {
  const _DesktopStepRow({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F7F4),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFF0D6F69),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF516784),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
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
      cursor: SystemMouseCursors.click,
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
                maxLines: widget.compact ? 4 : null,
                overflow: widget.compact ? TextOverflow.ellipsis : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
