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
  bool _isChecking = false;
  bool _isResending = false;

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

  Future<void> _refreshVerificationStatus(UserProfile? profile) async {
    setState(() => _isChecking = true);
    try {
      final authRepository = ref.read(authRepositoryProvider);
      await authRepository.reloadCurrentUser();
      final isVerified = authRepository.currentAuthUser?.emailVerified ?? false;

      if (!mounted) {
        return;
      }

      if (!isVerified) {
        await _showNotVerifiedModal();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email verified successfully.')),
      );
      context.go(_resolveNextRoute(profile));
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Verification email sent.')));
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _showNotVerifiedModal() {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 8),
              Text('Email Not Verified'),
            ],
          ),
          content: const Text(
            'We still cannot confirm your email. Please open the verification link from your inbox and then try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
              'A verification email was sent to\n${user?.email ?? 'your email address'}.',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF516784),
                height: 1.35,
                fontWeight: FontWeight.w500,
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
                  'After verification, we will take you to counselor invite waiting and skip basic onboarding questions.',
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
                onPressed: _isChecking
                    ? null
                    : () => _refreshVerificationStatus(profile),
                style: ElevatedButton.styleFrom(
                  shadowColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  _isChecking ? 'Checking...' : 'I Have Verified My Email',
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
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.go(_resolveNextRoute(profile)),
              child: Text(
                _hasInviteContext ? 'Continue to Invite' : 'Continue',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
