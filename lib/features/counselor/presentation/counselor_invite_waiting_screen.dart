import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/counselor/data/counselor_providers.dart';
import 'package:mindnest/features/counselor/models/counselor_institution_access_status.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';

class CounselorInviteWaitingScreen extends ConsumerStatefulWidget {
  const CounselorInviteWaitingScreen({super.key});

  @override
  ConsumerState<CounselorInviteWaitingScreen> createState() =>
      _CounselorInviteWaitingScreenState();
}

class _CounselorInviteWaitingScreenState
    extends ConsumerState<CounselorInviteWaitingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  bool _isCheckingWindowsInvite = false;
  bool _hasCheckedWindowsInvite = false;
  UserInvite? _windowsInvite;
  String? _banner;
  bool _bannerIsError = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _pulse = Tween<double>(
      begin: 0.96,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _showBanner(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _banner = message;
      _bannerIsError = isError;
    });
  }

  void _showCodeError(String message) {
    if (!mounted) return;
    setState(() {
      _codeError = message;
      _banner = null;
    });
  }

  String _formatInviteCodeError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Institution code is invalid or no longer active.';
    }
    if (message.contains('Dart exception thrown from converted Future')) {
      return 'Institution code is invalid or no longer active.';
    }
    return message;
  }

  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _checkWindowsInvite() async {
    final uid = ref.read(authStateChangesProvider).valueOrNull?.uid ?? '';
    if (uid.trim().isEmpty) {
      _showBanner('You are no longer signed in. Log in again.', isError: true);
      return;
    }

    setState(() {
      _isCheckingWindowsInvite = true;
      _banner = null;
      _windowsInvite = null;
    });

    try {
      final invite = await ref
          .read(institutionRepositoryProvider)
          .getPendingInviteForUid(uid);
      if (!mounted) {
        return;
      }
      setState(() {
        _hasCheckedWindowsInvite = true;
        _windowsInvite = invite;
        if (invite == null) {
          _banner =
              'No institution invite yet. Ask your institution admin to send it, then click Check Again.';
          _bannerIsError = false;
        } else {
          _banner =
              'An invite is ready for ${invite.institutionName}. Review it here and continue with counselor setup on Windows.';
          _bannerIsError = false;
        }
      });
    } catch (error) {
      _showBanner(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingWindowsInvite = false);
      }
    }
  }

  Future<void> _accept(UserInvite invite) async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showCodeError('Enter the institution code to accept the invite.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _codeError = null;
    });
    try {
      await ref
          .read(institutionRepositoryProvider)
          .acceptInvite(invite: invite, institutionCode: code);
      if (!mounted) return;
      context.go(AppRoute.counselorSetup);
    } catch (error) {
      _showCodeError(_formatInviteCodeError(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _decline(UserInvite invite) async {
    setState(() {
      _isSubmitting = true;
      _codeError = null;
    });
    try {
      await ref.read(institutionRepositoryProvider).declineInvite(invite);
      _codeController.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _windowsInvite = null;
        _hasCheckedWindowsInvite = true;
        _banner =
            'Invite declined. The original alert was resolved and follow-up notifications were sent.';
        _bannerIsError = false;
      });
    } catch (error) {
      _showBanner(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;
    final counselorAccessStatus = _isWindowsDesktop
        ? (ref
                  .watch(currentCounselorInstitutionAccessStatusProvider)
                  .valueOrNull ??
              CounselorInstitutionAccessStatus.inactive)
        : CounselorInstitutionAccessStatus.inactive;
    if (_isWindowsDesktop) {
      if (_windowsInvite != null) {
        return _buildWindowsInviteScreen(context, _windowsInvite!, isDesktop);
      }
      return _buildWindowsWaitingScreen(
        context,
        isDesktop,
        counselorAccessStatus,
      );
    }
    final inviteAsync = ref.watch(pendingUserInviteProvider);

    return MindNestShell(
      maxWidth: isDesktop ? 1360 : 780,
      backgroundMode: isDesktop
          ? MindNestBackgroundMode.homeStyle
          : MindNestBackgroundMode.defaultShell,
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 28 : 20,
        24,
        isDesktop ? 28 : 20,
        28,
      ),
      child: inviteAsync.when(
        data: (invite) => _buildContent(context, invite, isDesktop),
        loading: () => const GlassCard(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
        error: (error, _) => GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Banner(
                  message: error.toString().replaceFirst('Exception: ', ''),
                  isError: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWindowsWaitingScreen(
    BuildContext context,
    bool isDesktop,
    CounselorInstitutionAccessStatus accessStatus,
  ) {
    final removedByAdmin =
        accessStatus == CounselorInstitutionAccessStatus.removed;
    return MindNestShell(
      maxWidth: isDesktop ? 980 : 760,
      backgroundMode: isDesktop
          ? MindNestBackgroundMode.homeStyle
          : MindNestBackgroundMode.defaultShell,
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 28 : 20,
        24,
        isDesktop ? 28 : 20,
        28,
      ),
      child: GlassCard(
        child: Padding(
          padding: EdgeInsets.all(isDesktop ? 28 : 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Counselor Invite Waiting',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: const Color(0xFF071937),
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Windows keeps this as a simple waiting checkpoint. Check manually for your counselor invite, then respond here when it arrives.',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFF5E728D),
                                fontWeight: FontWeight.w500,
                                height: 1.45,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  OutlinedButton.icon(
                    onPressed: () {
                      confirmAndLogout(context: context, ref: ref);
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign Out'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF072B52), Color(0xFF0D7FA1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    ScaleTransition(
                      scale: _pulse,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.mark_email_unread_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Waiting for institution invite',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 21,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _windowsInvite == null
                                ? 'Click Check Again whenever you want to see whether the institution admin has sent your counselor invite.'
                                : 'Invite found for ${_windowsInvite!.institutionName}. Review it here and continue into counselor setup on Windows.',
                            style: const TextStyle(
                              color: Color(0xFFE5F0FF),
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (removedByAdmin) ...[
                const SizedBox(height: 16),
                const _Banner(
                  message:
                      'Your institution access was removed by the admin. Wait for a new invite, then click Check Again.',
                  isError: true,
                ),
              ] else if ((_banner ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                _Banner(message: _banner!, isError: _bannerIsError),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _PrimaryButton(
                    label: _isCheckingWindowsInvite
                        ? 'Checking...'
                        : 'Check Again',
                    onPressed: _isCheckingWindowsInvite
                        ? null
                        : _checkWindowsInvite,
                    gradient: const [Color(0xFF155EEF), Color(0xFF0E9B90)],
                    glowColor: const Color(0x33155EEF),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD8E4F1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How this works on Windows',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF071937),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '1. Stay signed in with your existing account.\n'
                      '2. Click Check Again whenever you want to look for a new invite.\n'
                      '3. When the invite is ready, review it here, respond to it, and continue into counselor setup on Windows.',
                      style: TextStyle(
                        color: Color(0xFF5E728D),
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_hasCheckedWindowsInvite && _windowsInvite == null) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'No invite was found in the latest check.',
                        style: TextStyle(
                          color: Color(0xFF0D6F69),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWindowsInviteScreen(
    BuildContext context,
    UserInvite invite,
    bool isDesktop,
  ) {
    return MindNestShell(
      maxWidth: isDesktop ? 1360 : 780,
      backgroundMode: isDesktop
          ? MindNestBackgroundMode.homeStyle
          : MindNestBackgroundMode.defaultShell,
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 28 : 20,
        24,
        isDesktop ? 28 : 20,
        28,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: _buildInviteExperience(context, invite, isDesktop),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    UserInvite? invite,
    bool isDesktop,
  ) {
    if (invite != null) {
      return _buildInviteExperience(context, invite, isDesktop);
    }

    final side = _waitingPanel(isDesktop);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _LogoutIcon(
            onTap: () {
              confirmAndLogout(context: context, ref: ref);
            },
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: isDesktop ? Alignment.centerLeft : Alignment.center,
          child: _StatusPill(
            controller: _controller,
            label: 'Pending Institution Invite',
            ready: false,
          ),
        ),
        if ((_banner ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _Banner(message: _banner!, isError: _bannerIsError),
        ],
        const SizedBox(height: 18),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 12,
                child: GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: _hero(context, false, true),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 9,
                child: GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: side,
                  ),
                ),
              ),
            ],
          )
        else
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hero(context, false, false),
                  const SizedBox(height: 22),
                  side,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInviteExperience(
    BuildContext context,
    UserInvite invite,
    bool isDesktop,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _LogoutIcon(
            onTap: () {
              confirmAndLogout(context: context, ref: ref);
            },
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: isDesktop ? Alignment.centerLeft : Alignment.center,
          child: _StatusPill(
            controller: _controller,
            label: 'Invite Arrived: Action Required',
            ready: true,
          ),
        ),
        if ((_banner ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _Banner(message: _banner!, isError: _bannerIsError),
        ],
        const SizedBox(height: 18),
        _inviteHeroCard(context, invite, isDesktop),
        const SizedBox(height: 22),
        if (isDesktop)
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: 900,
              child: GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: _invitePanel(invite, true),
                ),
              ),
            ),
          )
        else
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _invitePanel(invite, false),
            ),
          ),
      ],
    );
  }

  Widget _hero(BuildContext context, bool hasInvite, bool isDesktop) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: isDesktop ? 320 : 228,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              colors: hasInvite
                  ? const [
                      Color(0xFF082A55),
                      Color(0xFF155EEF),
                      Color(0xFF11B981),
                    ]
                  : const [
                      Color(0xFF072B52),
                      Color(0xFF0D7FA1),
                      Color(0xFF19B7A7),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22072B52),
                blurRadius: 30,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: -30,
                top: -20,
                child: _blob(118, const Color(0x33FFFFFF)),
              ),
              Positioned(
                right: -36,
                bottom: -36,
                child: _blob(
                  150,
                  hasInvite ? const Color(0x338DBEFF) : const Color(0x33A7F3D0),
                ),
              ),
              Center(
                child: ScaleTransition(
                  scale: _pulse,
                  child: Container(
                    width: hasInvite ? 124 : 110,
                    height: hasInvite ? 124 : 110,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFFFFF), Color(0xFFD9FFF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      hasInvite
                          ? Icons.mark_email_unread_rounded
                          : Icons.notifications_active_rounded,
                      size: hasInvite ? 48 : 44,
                      color: const Color(0xFF0C7E9C),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          hasInvite
              ? 'Your institution invite is here.'
              : 'Account is waiting for institution access.',
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: isDesktop ? 40 : 30,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF071937),
            height: 1.04,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          hasInvite
              ? 'Enter the institution code from the admin and accept or reject right here. Notifications still remains available as the secondary path.'
              : 'You are registered. When the institution admin invite arrives, this screen turns into a live action panel so you can respond immediately.',
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: isDesktop ? 18 : 16,
            color: const Color(0xFF4E627A),
            fontWeight: FontWeight.w500,
            height: 1.55,
          ),
        ),
      ],
    );
  }

  Widget _waitingPanel(bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('What happens next', isDesktop),
        const SizedBox(height: 14),
        _infoCard(
          isDesktop,
          '01',
          'Wait for the institution admin',
          'Your account stays locked to counselor onboarding until the invite is issued.',
          const Color(0xFF0E9B90),
        ),
        const SizedBox(height: 12),
        _infoCard(
          isDesktop,
          '02',
          'Watch this screen',
          'This screen flips into an action state at the same time.',
          const Color(0xFF0D7FA1),
        ),
        const SizedBox(height: 12),
        _infoCard(
          isDesktop,
          '03',
          'Accept and continue setup',
          'Once accepted, counselor setup opens and the institution link becomes active.',
          const Color(0xFF2563EB),
        ),
      ],
    );
  }

  Widget _invitePanel(UserInvite invite, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF1C8), Color(0xFFFFE3A1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0xFFF5C542)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.priority_high_rounded,
                color: Color(0xFF9A6700),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'RESPOND NOW',
                style: TextStyle(
                  color: const Color(0xFF7C5400),
                  fontSize: isDesktop ? 12.5 : 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This is no longer a waiting page. Review the invite, enter the institution code, and decide from this panel.',
          style: TextStyle(
            color: const Color(0xFF60748F),
            fontSize: isDesktop ? 15 : 13,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        _detailTile(
          isDesktop,
          Icons.apartment_rounded,
          'Institution',
          invite.institutionName,
          const Color(0xFF0D7FA1),
        ),
        const SizedBox(height: 12),
        if (isDesktop)
          Row(
            children: [
              Expanded(
                child: _detailTile(
                  isDesktop,
                  Icons.workspace_premium_outlined,
                  'Role',
                  invite.intendedRole.label,
                  const Color(0xFF0E9B90),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _detailTile(
                  isDesktop,
                  Icons.schedule_rounded,
                  'Expires',
                  _formatExpiry(invite.expiresAt),
                  const Color(0xFF2563EB),
                ),
              ),
            ],
          )
        else ...[
          _detailTile(
            isDesktop,
            Icons.workspace_premium_outlined,
            'Role',
            invite.intendedRole.label,
            const Color(0xFF0E9B90),
          ),
          const SizedBox(height: 12),
          _detailTile(
            isDesktop,
            Icons.schedule_rounded,
            'Expires',
            _formatExpiry(invite.expiresAt),
            const Color(0xFF2563EB),
          ),
        ],
        const SizedBox(height: 18),
        if ((_codeError ?? '').trim().isNotEmpty) ...[
          _InlineFieldError(message: _codeError!),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) {
            if ((_codeError ?? '').isEmpty) return;
            setState(() => _codeError = null);
          },
          decoration: InputDecoration(
            labelText: 'Institution code',
            hintText: 'Enter code from institution admin',
            prefixIcon: const Icon(Icons.key_rounded),
            filled: true,
            fillColor: const Color(0xFFFFFBED),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _codeError == null
                    ? const Color(0xFFF5C542)
                    : const Color(0xFFDC2626),
                width: _codeError == null ? 1.2 : 1.4,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _codeError == null
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFDC2626),
                width: 1.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Accepting or rejecting here marks the original invite notification as read automatically, then sends a fresh decision notification to you and the admin.',
          style: TextStyle(
            color: const Color(0xFF64748B),
            fontSize: isDesktop ? 14.5 : 12.5,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _PrimaryButton(
                label: _isSubmitting ? 'Checking..' : 'Accept',
                onPressed: _isSubmitting ? null : () => _accept(invite),
                gradient: const [Color(0xFF155EEF), Color(0xFF0E9B90)],
                glowColor: const Color(0x33155EEF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : () => _decline(invite),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  foregroundColor: const Color(0xFFB91C1C),
                ),
                child: Text(
                  _isSubmitting ? '' : 'Reject',
                  style: TextStyle(
                    fontSize: isDesktop ? 18 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String text, bool isDesktop) {
    return Text(
      text,
      style: TextStyle(
        color: const Color(0xFF071937),
        fontSize: isDesktop ? 21 : 17,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _detailTile(
    bool isDesktop,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 18 : 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0EAF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isDesktop ? 48 : 42,
            height: isDesktop ? 48 : 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: const Color(0xFF6B7B93),
                    fontSize: isDesktop ? 11 : 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(
                    color: const Color(0xFF071937),
                    fontSize: isDesktop ? 16 : 14,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inviteHeroCard(
    BuildContext context,
    UserInvite invite,
    bool isDesktop,
  ) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          colors: [Color(0xFF071B3A), Color(0xFF155EEF), Color(0xFF13B58A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33155EEF),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -44,
            top: -30,
            child: _blob(180, const Color(0x26FFFFFF)),
          ),
          Positioned(
            right: -54,
            top: 22,
            child: _blob(156, const Color(0x26D9FFF6)),
          ),
          Positioned(
            right: 32,
            bottom: -48,
            child: _blob(164, const Color(0x1FFFFFFF)),
          ),
          Padding(
            padding: EdgeInsets.all(isDesktop ? 30 : 22),
            child: isDesktop
                ? Row(
                    children: [
                      Expanded(child: _inviteHeroCopy(theme, invite, true)),
                      const SizedBox(width: 24),
                      _inviteHeroOrb(true),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: _inviteHeroOrb(false),
                      ),
                      const SizedBox(height: 20),
                      _inviteHeroCopy(theme, invite, false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _inviteHeroCopy(ThemeData theme, UserInvite invite, bool isDesktop) {
    return Column(
      crossAxisAlignment: isDesktop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: isDesktop ? WrapAlignment.start : WrapAlignment.center,
          children: [
            _signalChip(
              'ACTION REQUIRED',
              const Color(0xFFFFE7AA),
              const Color(0xFF8A5B00),
            ),
            _signalChip(
              invite.intendedRole.label.toUpperCase(),
              const Color(0x1FFFFFFF),
              Colors.white,
            ),
            _signalChip(
              'EXPIRES ${_formatExpiry(invite.expiresAt).toUpperCase()}',
              const Color(0x1AFFFFFF),
              const Color(0xFFE0F2FE),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Invite unlocked.',
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
          style: theme.textTheme.headlineLarge?.copyWith(
            color: Colors.white,
            fontSize: isDesktop ? 46 : 31,
            height: 0.96,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          invite.institutionName,
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: const Color(0xFFFFF4C4),
            fontSize: isDesktop ? 28 : 22,
            fontWeight: FontWeight.w900,
            height: 1.05,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Your counselor registration has reached the live institution approval handoff. Review the code from the admin and respond here immediately.',
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFFE5F0FF),
            fontSize: isDesktop ? 17 : 14.5,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _inviteHeroOrb(bool isDesktop) {
    return ScaleTransition(
      scale: _pulse,
      child: Container(
        width: isDesktop ? 238 : 154,
        height: isDesktop ? 238 : 154,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFFFF3C4), Color(0x66FFFFFF)],
          ),
          border: Border.all(color: const Color(0x66FFFFFF), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55FFF0AE),
              blurRadius: 50,
              spreadRadius: 6,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mark_email_unread_rounded,
              size: isDesktop ? 74 : 48,
              color: const Color(0xFF155EEF),
            ),
            const SizedBox(height: 10),
            Text(
              'INVITE',
              style: TextStyle(
                color: const Color(0xFF0B2A52),
                fontSize: isDesktop ? 18 : 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            Text(
              'ARRIVED',
              style: TextStyle(
                color: const Color(0xFF0E9B90),
                fontSize: isDesktop ? 21 : 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signalChip(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  Widget _infoCard(
    bool isDesktop,
    String index,
    String title,
    String description,
    Color accent,
  ) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 18 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3EDF5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isDesktop ? 50 : 42,
            height: isDesktop ? 50 : 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.72)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              index,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: isDesktop ? 14.5 : 12.5,
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
                  style: TextStyle(
                    color: const Color(0xFF071937),
                    fontWeight: FontWeight.w800,
                    fontSize: isDesktop ? 17.5 : 15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    color: const Color(0xFF5D728D),
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                    fontSize: isDesktop ? 14.5 : 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 46, spreadRadius: 12)],
      ),
    );
  }

  String _formatExpiry(DateTime? value) {
    if (value == null) return 'Not specified';
    final local = value.toLocal();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${months[local.month - 1]} $local.day, $local.year $hour:${local.minute.toString().padLeft(2, '0')} $suffix';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? const Color(0xFFDC2626) : const Color(0xFF0E9B90);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFF1F2) : const Color(0xFFEFFCF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF10223E),
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineFieldError extends StatelessWidget {
  const _InlineFieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.controller,
    required this.label,
    required this.ready,
  });

  final Animation<double> controller;
  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final glow = 0.82 + (math.sin(controller.value * 2 * math.pi) * 0.12);
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 18 : 14,
            vertical: isDesktop ? 12 : 10,
          ),
          decoration: BoxDecoration(
            color: Color.lerp(
              const Color(0xFFF8FFFE),
              ready ? const Color(0xFFE8FBF5) : const Color(0xFFEAFBF8),
              glow,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: ready ? const Color(0xFF98E4D1) : const Color(0xFFA8E7DC),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0x220E9B90).withValues(alpha: glow),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ready ? Icons.campaign_rounded : Icons.hourglass_top_rounded,
                size: isDesktop ? 18 : 16,
                color: const Color(0xFF0D8E85),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: isDesktop ? 14.5 : 13,
                  color: const Color(0xFF0B6F69),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogoutIcon extends StatelessWidget {
  const _LogoutIcon({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.logout_rounded, color: const Color(0xFF6B7B93)),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.gradient = const [Color(0xFF0D7FA1), Color(0xFF0E9B90)],
    this.glowColor = const Color(0x330E9B90),
  });

  final String label;
  final VoidCallback? onPressed;
  final List<Color> gradient;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor,
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: isDesktop ? 17 : 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
