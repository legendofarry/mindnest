import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  late final Animation<double> _pulse = Tween<double>(begin: 0.96, end: 1.04)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  String? _banner;
  bool _bannerIsError = false;

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

  Future<void> _accept(UserInvite invite) async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showBanner('Enter the institution code to accept the invite.', isError: true);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .acceptInvite(invite: invite, institutionCode: code);
      if (!mounted) return;
      context.go(AppRoute.counselorSetup);
    } catch (error) {
      _showBanner(error.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _decline(UserInvite invite) async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(institutionRepositoryProvider).declineInvite(invite);
      _codeController.clear();
      _showBanner(
        'Invite declined. The original alert was resolved and follow-up notifications were sent.',
        isError: false,
      );
    } catch (error) {
      _showBanner(error.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;
    final inviteAsync = ref.watch(pendingUserInviteProvider);

    return MindNestShell(
      maxWidth: isDesktop ? 1360 : 780,
      backgroundMode: isDesktop
          ? MindNestBackgroundMode.homeStyle
          : MindNestBackgroundMode.defaultShell,
      padding: EdgeInsets.fromLTRB(isDesktop ? 28 : 20, 24, isDesktop ? 28 : 20, 28),
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
                const SizedBox(height: 16),
                _PrimaryButton(
                  label: 'Open Notifications',
                  onPressed: () => context.go(AppRoute.notifications),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, UserInvite? invite, bool isDesktop) {
    final hasInvite = invite != null;
    final side = hasInvite
        ? _invitePanel(invite, isDesktop)
        : _waitingPanel(isDesktop);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: isDesktop ? Alignment.centerLeft : Alignment.center,
          child: _StatusPill(
            controller: _controller,
            label: hasInvite ? 'Institution Invite Ready' : 'Pending Institution Invite',
            ready: hasInvite,
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
                    child: _hero(context, hasInvite, true),
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
                  _hero(context, hasInvite, false),
                  const SizedBox(height: 22),
                  side,
                ],
              ),
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
                  ? const [Color(0xFF082A55), Color(0xFF155EEF), Color(0xFF11B981)]
                  : const [Color(0xFF072B52), Color(0xFF0D7FA1), Color(0xFF19B7A7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x22072B52), blurRadius: 30, offset: Offset(0, 18)),
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
                child: _blob(150, hasInvite ? const Color(0x338DBEFF) : const Color(0x33A7F3D0)),
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
                      hasInvite ? Icons.mark_email_unread_rounded : Icons.notifications_active_rounded,
                      size: hasInvite ? 48 : 44,
                      color: const Color(0xFF0C7E9C),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Row(
                  children: [
                    _metric(isDesktop, hasInvite ? 'NOW' : '1', hasInvite ? 'REVIEW INVITE' : 'WAITING STEP'),
                    const SizedBox(width: 10),
                    _metric(isDesktop, hasInvite ? 'CODE' : 'ADMIN', hasInvite ? 'VERIFY ACCESS' : 'TRIGGERS INVITE'),
                    const SizedBox(width: 10),
                    _metric(isDesktop, hasInvite ? 'GO' : 'APP', hasInvite ? 'RESPOND HERE' : 'LIVE SWITCH HERE'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          hasInvite ? 'Your institution invite is here.' : 'Your counselor account is waiting for institution access.',
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: isDesktop ? 48 : 34,
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
            fontSize: isDesktop ? 20 : 17,
            color: const Color(0xFF4E627A),
            fontWeight: FontWeight.w500,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: isDesktop ? 330 : null,
          child: _PrimaryButton(
            label: hasInvite ? 'Open Notifications Too' : 'Open Notifications',
            onPressed: () => context.go(AppRoute.notifications),
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
        _infoCard(isDesktop, '01', 'Wait for the institution admin', 'Your account stays locked to counselor onboarding until the invite is issued.', const Color(0xFF0E9B90)),
        const SizedBox(height: 12),
        _infoCard(isDesktop, '02', 'Watch this screen or Notifications', 'The invite appears in Notifications and this screen flips into an action state at the same time.', const Color(0xFF0D7FA1)),
        const SizedBox(height: 12),
        _infoCard(isDesktop, '03', 'Accept and continue setup', 'Once accepted, counselor setup opens and the institution link becomes active.', const Color(0xFF2563EB)),
      ],
    );
  }

  Widget _invitePanel(UserInvite invite, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Review and respond', isDesktop),
        const SizedBox(height: 8),
        Text(
          'This is the same invite available in Notifications, but you can finish it here without leaving the waiting screen.',
          style: TextStyle(
            color: const Color(0xFF60748F),
            fontSize: isDesktop ? 16 : 13.5,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        _detailTile(isDesktop, Icons.apartment_rounded, 'Institution', invite.institutionName, const Color(0xFF0D7FA1)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _detailTile(isDesktop, Icons.workspace_premium_outlined, 'Role', invite.intendedRole.label, const Color(0xFF0E9B90))),
            const SizedBox(width: 12),
            Expanded(child: _detailTile(isDesktop, Icons.schedule_rounded, 'Expires', _formatExpiry(invite.expiresAt), const Color(0xFF2563EB))),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Institution code',
            hintText: 'Enter code from institution admin',
            prefixIcon: const Icon(Icons.key_rounded),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFD4E4F1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFF0E9B90), width: 1.4),
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
                label: _isSubmitting ? 'Accepting...' : 'Accept Invite',
                onPressed: _isSubmitting ? null : () => _accept(invite),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : () => _decline(invite),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  foregroundColor: const Color(0xFFB91C1C),
                ),
                child: Text(
                  _isSubmitting ? 'Working...' : 'Reject Invite',
                  style: TextStyle(fontSize: isDesktop ? 18 : 16, fontWeight: FontWeight.w800),
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
        fontSize: isDesktop ? 24 : 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _detailTile(bool isDesktop, IconData icon, String label, String value, Color color) {
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
                    fontSize: isDesktop ? 11.5 : 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(
                    color: const Color(0xFF071937),
                    fontSize: isDesktop ? 17 : 14.5,
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

  Widget _infoCard(bool isDesktop, String index, String title, String description, Color accent) {
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
              gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.72)]),
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
                    fontSize: isDesktop ? 19 : 15.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    color: const Color(0xFF5D728D),
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                    fontSize: isDesktop ? 15.5 : 13.5,
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

  Widget _metric(bool isDesktop, String value, String label) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 12 : 10,
          vertical: isDesktop ? 12 : 10,
        ),
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x26FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: isDesktop ? 19 : 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: const Color(0xD9E6FFFD),
                fontSize: isDesktop ? 12.5 : 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatExpiry(DateTime? value) {
    if (value == null) return 'Not specified';
    final local = value.toLocal();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${months[local.month - 1]} ${local.day}, ${local.year} ${hour}:${local.minute.toString().padLeft(2, '0')} $suffix';
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
          Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF10223E), fontWeight: FontWeight.w700, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.controller, required this.label, required this.ready});

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
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 18 : 14, vertical: isDesktop ? 12 : 10),
          decoration: BoxDecoration(
            color: Color.lerp(const Color(0xFFF8FFFE), ready ? const Color(0xFFE8FBF5) : const Color(0xFFEAFBF8), glow),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: ready ? const Color(0xFF98E4D1) : const Color(0xFFA8E7DC)),
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
              Icon(ready ? Icons.campaign_rounded : Icons.hourglass_top_rounded, size: isDesktop ? 18 : 16, color: const Color(0xFF0D8E85)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontSize: isDesktop ? 16 : 13.5, color: const Color(0xFF0B6F69), fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D7FA1), Color(0xFF0E9B90)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x330E9B90), blurRadius: 26, offset: Offset(0, 14)),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: isDesktop ? 18 : 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
