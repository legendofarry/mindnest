import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:url_launcher/url_launcher.dart';

class WindowsWebSetupRequiredScreen extends ConsumerStatefulWidget {
  const WindowsWebSetupRequiredScreen({super.key, this.reason});

  final String? reason;

  @override
  ConsumerState<WindowsWebSetupRequiredScreen> createState() =>
      _WindowsWebSetupRequiredScreenState();
}

class _WindowsWebSetupRequiredScreenState
    extends ConsumerState<WindowsWebSetupRequiredScreen> {
  static final Uri _webAppUri = Uri.parse('https://mindnestke.netlify.app/');

  bool _isOpeningWeb = false;
  bool _isSigningOut = false;
  String? _error;

  _WindowsSetupCopy get _copy => _WindowsSetupCopy.forReason(widget.reason);

  Future<void> _openWeb() async {
    if (_isOpeningWeb) {
      return;
    }
    setState(() {
      _isOpeningWeb = true;
      _error = null;
    });
    try {
      final launched = await launchUrl(
        _webAppUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched || !mounted) {
        return;
      }
      setState(() {
        _error =
            'We could not open MindNest on the web. Visit mindnestke.netlify.app in your browser.';
      });
    } finally {
      if (mounted) {
        setState(() => _isOpeningWeb = false);
      }
    }
  }

  Future<void> _signOutNow() async {
    if (_isSigningOut) {
      return;
    }
    setState(() {
      _isSigningOut = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signOut();
      await syncAuthSessionState(ref);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthBackgroundScaffold(
      maxWidth: 560,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFCFFFFFF),
          borderRadius: BorderRadius.circular(30),
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
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0E9B90), Color(0xFF18A89D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x330E9B90),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.language_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              _copy.title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF071937),
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _copy.description,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF5E728D),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFFFFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFB3ECDD)),
              ),
              child: Text(
                'Windows access starts after the account is fully ready. Finish this step on the web, then come back here and log in again.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF0D6F69),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
            if ((_error ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFECDD3)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFF9F1239),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Container(
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
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
              child: ElevatedButton.icon(
                onPressed: _isOpeningWeb ? null : _openWeb,
                style: ElevatedButton.styleFrom(
                  shadowColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                icon: const Icon(Icons.open_in_browser_rounded),
                label: Text(
                  _isOpeningWeb ? 'Opening web...' : _copy.primaryActionLabel,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSigningOut ? null : _signOutNow,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                foregroundColor: const Color(0xFF5E728D),
                side: const BorderSide(color: Color(0xFFD2DCE9)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: Text(_isSigningOut ? 'Signing out...' : 'Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowsSetupCopy {
  const _WindowsSetupCopy({
    required this.title,
    required this.description,
    required this.primaryActionLabel,
  });

  final String title;
  final String description;
  final String primaryActionLabel;

  factory _WindowsSetupCopy.forReason(String? reason) {
    switch ((reason ?? '').trim()) {
      case 'verify-email':
        return const _WindowsSetupCopy(
          title: 'Finish Email Verification on the Web',
          description:
              'Email verification is handled on the web. Open MindNest in your browser, verify the account there, then come back to Windows and log in again.',
          primaryActionLabel: 'Open Web to Verify Email',
        );
      case 'onboarding':
        return const _WindowsSetupCopy(
          title: 'Finish Onboarding on the Web',
          description:
              'This account still needs onboarding. Open MindNest on the web, finish the onboarding steps there, then return to Windows when setup is complete.',
          primaryActionLabel: 'Open Web to Finish Onboarding',
        );
      case 'institution-approval':
        return const _WindowsSetupCopy(
          title: 'Track Institution Approval on the Web',
          description:
              'Institution approval and related review steps are handled on the web. Open MindNest in your browser to monitor progress or continue the workflow there.',
          primaryActionLabel: 'Open Web for Approval Status',
        );
      case 'counselor-setup':
        return const _WindowsSetupCopy(
          title: 'Finish Counselor Setup on the Web',
          description:
              'Counselor setup is completed on the web. Open MindNest in your browser, finish the setup flow there, then come back to Windows when the account is ready.',
          primaryActionLabel: 'Open Web to Finish Setup',
        );
      default:
        return const _WindowsSetupCopy(
          title: 'Finish Account Setup on the Web',
          description:
              'This account still has setup steps to complete. Open MindNest in your browser, finish the remaining work there, then return to Windows and log in again.',
          primaryActionLabel: 'Open MindNest on the Web',
        );
    }
  }
}
