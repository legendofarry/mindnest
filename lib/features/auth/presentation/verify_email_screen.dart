import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_desktop_shell.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/modern_banner.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.inviteId,
    this.invitedEmail,
    this.invitedName,
    this.institutionName,
    this.intendedRole,
    this.registrationIntent,
  });

  final String? inviteId;
  final String? invitedEmail;
  final String? invitedName;
  final String? institutionName;
  final String? intendedRole;
  final String? registrationIntent;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  static const _desktopBreakpoint = 1100.0;
  bool _isResending = false;
  bool _isContinuing = false;

  Map<String, String> get _inviteQuery => AppRoute.inviteQuery(
    inviteId: widget.inviteId ?? '',
    invitedEmail: widget.invitedEmail,
    invitedName: widget.invitedName,
    institutionName: widget.institutionName,
    intendedRole: widget.intendedRole,
  );

  bool get _hasInviteContext => _inviteQuery.isNotEmpty;
  bool get _isCounselorIntentFallback {
    return (widget.registrationIntent ?? '').trim() ==
        UserProfile.counselorRegistrationIntent;
  }

  String _resolveNextRoute(UserProfile? profile) {
    if (_hasInviteContext) {
      return AppRoute.withInviteQuery(AppRoute.inviteAccept, _inviteQuery);
    }
    final hasCounselorIntent =
        profile?.isCounselorRegistrationIntentPending ??
        _isCounselorIntentFallback;
    if (hasCounselorIntent) {
      return AppRoute.counselorInviteWaiting;
    }
    final role = profile?.role;
    if (role == UserRole.institutionAdmin) {
      return AppRoute.institutionAdmin;
    }
    if (role == UserRole.counselor) {
      return AppRoute.counselorSetup;
    }
    if (role == null || role == UserRole.other) {
      return AppRoute.home;
    }
    return AppRoute.home;
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await ref.read(authRepositoryProvider).sendEmailVerification();
      if (!mounted) {
        return;
      }
      showModernBanner(
        context,
        message: 'Verification email sent. Check your inbox.',
        icon: Icons.mark_email_read_rounded,
        color: const Color(0xFF0E9B90),
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _handleContinue(UserProfile? profile) async {
    if (_isContinuing) return;
    setState(() => _isContinuing = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.reloadCurrentUser();
      await syncAuthSessionState(ref);
      final user = authRepo.currentAuthUser;
      if (user == null) {
        if (!mounted) return;
        await confirmAndLogout(context: context, ref: ref);
        return;
      }
      if (!(user.emailVerified)) {
        if (!mounted) return;
        showModernBanner(
          context,
          message: 'Still not verified. Check your inbox then tap Continue.',
          icon: Icons.mark_email_unread_outlined,
          color: const Color(0xFFBE123C),
        );
        return;
      }
      // Refresh profile so role/institution is current before routing.
      final refreshedProfile = ref.read(currentUserProfileProvider).valueOrNull;
      if (!mounted) return;
      context.go(_resolveNextRoute(refreshedProfile ?? profile));
    } finally {
      if (mounted) {
        setState(() => _isContinuing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    if (isDesktop) {
      return AuthDesktopShell(
        heroHighlightText: '',
        heroBaseText: '',
        heroDescription:
            'We sent a verification link to your inbox. Confirm it to continue into the right workspace with the right role.',
        heroSupplement: const _VerifyEmailDesktopSupplement(),
        formChild: _buildContent(context, profile),
      );
    }

    return AuthBackgroundScaffold(
      maxWidth: double.infinity,
      child: _buildContent(context, profile),
    );
  }

  Widget _buildContent(BuildContext context, UserProfile? profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => confirmAndLogout(context: context, ref: ref),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: Color(0xFF93A3BA),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        color: Color(0xFF93A3BA),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F3F1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFB3ECDD)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x140F172A),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  Text(
                    'Link sent',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF0D3A3A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              final showCounselorHint =
                  !_hasInviteContext &&
                  (profile?.isCounselorRegistrationIntentPending ??
                      _isCounselorIntentFallback);

              if (showCounselorHint) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFFFFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB3ECDD)),
                  ),
                  child: const Text(
                    "Didn't receive the email? Please check your Spam or Junk folder. If you find it there, mark it as \"Not Spam\" so future emails arrive in your inbox.",
                    style: TextStyle(
                      color: Color(0xFF0D6F69),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }

              return const Text(
                "Didn't receive the email? Please check your Spam or Junk folder. If you find it there, mark it as \"Not Spam\" so future emails arrive in your inbox.",
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
          if (_hasInviteContext) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFFFFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB3ECDD)),
              ),
              child: Text(
                'After verification, you will continue to your invite${(widget.institutionName ?? '').trim().isNotEmpty ? ' for ${widget.institutionName!.trim()}' : ''}.',
                style: const TextStyle(
                  color: Color(0xFF0D6F69),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF0E9B90), Color(0xFF18A89D)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D72ECDC),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isContinuing ? null : () => _handleContinue(profile),
              style: ElevatedButton.styleFrom(
                shadowColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                _isContinuing ? 'Checking...' : 'Continue',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _isResending ? null : _resend,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              foregroundColor: const Color(0xFF0E9B90),
            ),
            child: Text(
              _isResending ? 'Sending...' : 'Resend verification email',
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifyEmailDesktopSupplement extends StatelessWidget {
  const _VerifyEmailDesktopSupplement();

  @override
  Widget build(BuildContext context) {
    return const _DesktopSupportCard(
      eyebrow: 'Why verify now',
      title: 'Verification unlocks the next step.',
      child: Column(
        children: [
          _DesktopStepRow(
            number: '1',
            title: 'Open the email',
            description: 'Find the verification link in your inbox.',
          ),
          SizedBox(height: 14),
          _DesktopStepRow(
            number: '2',
            title: 'Confirm ownership',
            description: 'Click the link so MindNest can trust the account.',
          ),
          SizedBox(height: 14),
          _DesktopStepRow(
            number: '3',
            title: 'Continue securely',
            description: 'Return here and continue into the correct workspace.',
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD5E7E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF0E9B90),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 20,
              height: 1.15,
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
            color: const Color(0xFFE6F3F1),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFF0E9B90),
              fontWeight: FontWeight.w800,
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
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(color: Color(0xFF5D7291), height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
