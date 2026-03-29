import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
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

  Future<void> _confirmSignOut() async {
    setState(() => _error = null);
    await confirmAndLogout(context: context, ref: ref);
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
                _copy.supportingNote,
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
            if (_copy.showPrimaryAction) ...[
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
            ],
            OutlinedButton.icon(
              onPressed: _confirmSignOut,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                foregroundColor: const Color(0xFF5E728D),
                side: const BorderSide(color: Color(0xFFD2DCE9)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
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
    required this.supportingNote,
    required this.primaryActionLabel,
    this.showPrimaryAction = true,
  });

  final String title;
  final String description;
  final String supportingNote;
  final String primaryActionLabel;
  final bool showPrimaryAction;

  factory _WindowsSetupCopy.forReason(String? reason) {
    switch ((reason ?? '').trim()) {
      case 'verify-email':
        return const _WindowsSetupCopy(
          title: 'Finish Email Verification on the Web',
          description:
              'Verify your email in the browser, then return to Windows.',
          supportingNote: 'Windows opens after verification is complete.',
          primaryActionLabel: 'Open Web to Verify Email',
        );
      case 'onboarding':
        return const _WindowsSetupCopy(
          title: 'Finish Onboarding on the Web',
          description:
              'Complete onboarding in the browser, then come back here.',
          supportingNote: 'Windows opens after onboarding is done.',
          primaryActionLabel: 'Open Web to Finish Onboarding',
        );
      case 'institution-approval':
        return const _WindowsSetupCopy(
          title: 'Track Institution Approval on the Web',
          description:
              'This institution is still under review. Check progress in the browser.',
          supportingNote: 'Windows opens after approval is complete.',
          primaryActionLabel: 'Open Web for Approval Status',
          showPrimaryAction: false,
        );
      case 'counselor-invite':
        return const _WindowsSetupCopy(
          title: 'Finish Counselor Invite on the Web',
          description:
              'Review the invite and join with the institution code in the browser.',
          supportingNote: 'Windows opens after the invite handoff is complete.',
          primaryActionLabel: 'Open Web to Finish Invite',
        );
      case 'counselor-setup':
        return const _WindowsSetupCopy(
          title: 'Finish Counselor Setup on the Web',
          description:
              'Complete counselor setup in the browser, then return here.',
          supportingNote: 'Windows opens after setup is complete.',
          primaryActionLabel: 'Open Web to Finish Setup',
        );
      case 'counselor-access-removed':
        return const _WindowsSetupCopy(
          title: 'Counselor Access Changed',
          description:
              'Your institution access changed. Check the latest status in the browser.',
          supportingNote: 'Windows opens after access is active again.',
          primaryActionLabel: 'Open Web to Check Access',
        );
      default:
        return const _WindowsSetupCopy(
          title: 'Finish Account Setup on the Web',
          description: 'This account still needs setup in the browser.',
          supportingNote: 'Windows opens after account setup is complete.',
          primaryActionLabel: 'Open MindNest on the Web',
        );
    }
  }
}
