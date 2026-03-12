import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
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
      _showModernBanner(
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

  void _showModernBanner(
    BuildContext context, {
    required String message,
    IconData icon = Icons.info_outline_rounded,
    Color color = const Color(0xFF0E9B90),
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.white,
        elevation: 8,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: const EdgeInsets.only(right: 12),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Dismiss'),
          ),
        ],
        surfaceTintColor: Colors.transparent,
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  Future<void> _handleContinue(UserProfile? profile) async {
    if (_isContinuing) return;
    setState(() => _isContinuing = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.reloadCurrentUser();
      final user = authRepo.currentAuthUser;
      if (user == null) {
        if (!mounted) return;
        await confirmAndLogout(context: context, ref: ref);
        return;
      }
      if (!(user.emailVerified)) {
        if (!mounted) return;
        _showModernBanner(
          context,
          message: 'Still not verified. Check your inbox then tap Continue.',
          icon: Icons.mark_email_unread_outlined,
          color: const Color(0xFFBE123C),
        );
        return;
      }
      // Refresh profile so role/institution is current before routing.
      await ref.refresh(currentUserProfileProvider.future);
      final refreshedProfile =
          ref.read(currentUserProfileProvider).valueOrNull ?? profile;
      if (!mounted) return;
      context.go(_resolveNextRoute(refreshedProfile));
    } finally {
      if (mounted) {
        setState(() => _isContinuing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).valueOrNull;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;

    return AuthBackgroundScaffold(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFCFFFFFF),
          borderRadius: BorderRadius.circular(34),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
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
            const SizedBox(height: 22),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F3F1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                color: Color(0xFF0E9B90),
                size: 33,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Verify Email',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF071937),
                fontSize: 48 / 2,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Link sent to ${user?.email ?? 'your email address'}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF516784),
                height: 1,
                fontWeight: FontWeight.w800,
                fontSize: 38 / 2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Didn't receive the email? Please check your Spam or Junk folder. If you find it there, mark it as \"Not Spam\" so future emails arrive in your inbox.",
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
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
            if (!_hasInviteContext &&
                (profile?.isCounselorRegistrationIntentPending ??
                    _isCounselorIntentFallback)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFFFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFB3ECDD)),
                ),
                child: const Text(
                  "Didn't receive the email? Please check your Spam or Junk folder. "
                  "If you find it there, mark it as \"Not Spam\" so future emails arrive in your inbox.",
                  style: TextStyle(
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
                onPressed: _isContinuing
                    ? null
                    : () => _handleContinue(profile),
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
      ),
    );
  }
}
