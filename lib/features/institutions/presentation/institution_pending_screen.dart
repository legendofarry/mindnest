import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart' show GlassCard;
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/core/ui/modern_banner.dart';

class InstitutionPendingScreen extends ConsumerStatefulWidget {
  const InstitutionPendingScreen({super.key});

  @override
  ConsumerState<InstitutionPendingScreen> createState() =>
      _InstitutionPendingScreenState();
}

class _InstitutionPendingScreenState
    extends ConsumerState<InstitutionPendingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _contactSupport({
    required String institutionName,
    required String status,
  }) async {
    final useFloatingDialog =
        kIsWeb || defaultTargetPlatform == TargetPlatform.windows;
    final dialog = _OwnerSupportChatSheet(
      institutionName: institutionName,
      contextStatus: status,
    );
    if (useFloatingDialog) {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Support',
        barrierColor: const Color(0x73071A33),
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) => dialog,
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => dialog,
    );
  }

  String _formatUserFacingError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) {
      return 'Something went wrong. Please try again.';
    }
    if (!raw.contains('Dart exception thrown from converted Future')) {
      return raw;
    }

    try {
      final dynamic wrapped = error;
      final innerError = wrapped.error;
      final innerMessage = innerError?.toString().trim();
      if (innerMessage != null && innerMessage.isNotEmpty) {
        return innerMessage.replaceFirst('Exception: ', '');
      }
      final innerStack = wrapped.stack?.toString().trim();
      if (innerStack != null && innerStack.isNotEmpty) {
        return innerStack;
      }
    } catch (_) {
      // Fall through to the generic message below.
    }

    return 'This request could not be processed right now. Please try again.';
  }

  String _statusTitle(String status) {
    if (status == 'declined') {
      return 'Action Needed';
    }
    if (status == 'cancelled') {
      return 'Request Closed';
    }
    if (status == 'approved') {
      return 'Approved';
    }
    return 'Pending Review';
  }

  String _statusHeadline(String status) {
    if (status == 'declined') {
      return 'Institution request declined';
    }
    if (status == 'cancelled') {
      return 'Institution request closed';
    }
    if (status == 'approved') {
      return 'Institution approved';
    }
    return 'Institution request submitted';
  }

  List<Color> _statusGradient(String status) {
    if (status == 'declined') {
      return const [Color(0xFFFFE4E6), Color(0xFFFFF1F2)];
    }
    if (status == 'cancelled') {
      return const [Color(0xFFFFF1D8), Color(0xFFFFF8EB)];
    }
    if (status == 'approved') {
      return const [Color(0xFFD1FAE5), Color(0xFFECFDF5)];
    }
    return const [Color(0xFFDBEAFE), Color(0xFFEFF6FF)];
  }

  Color _statusAccent(String status) {
    if (status == 'declined') {
      return const Color(0xFFBE123C);
    }
    if (status == 'cancelled') {
      return const Color(0xFFB45309);
    }
    if (status == 'approved') {
      return const Color(0xFF047857);
    }
    return const Color(0xFF0C4A6E);
  }

  Widget _buildStatusHero(
    BuildContext context, {
    required String status,
    required String institutionName,
  }) {
    final accent = _statusAccent(status);
    final isDeclined = status == 'declined';
    final isCancelled = status == 'cancelled';
    final isApproved = status == 'approved';
    final supportingCopy = isDeclined
        ? 'Your institution request was declined. Contact support if you need clarification.'
        : isCancelled
        ? 'This request is no longer in the approval queue. Contact support if you need clarification.'
        : isApproved
        ? 'Approval is complete. Your institution workspace is ready and '
              'remaining access controls will unlock automatically.'
        : 'Your request is in the approval queue. Stay signed in and we will '
              'unlock the institution workspace as soon as review is complete.';

    return GlassCard(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _statusGradient(status),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.72, end: 1).animate(
                      CurvedAnimation(
                        parent: _pulseController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.95, end: 1.06).animate(
                        CurvedAnimation(
                          parent: _pulseController,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 18,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(
                          isDeclined
                              ? Icons.report_problem_rounded
                              : isCancelled
                              ? Icons.pause_circle_rounded
                              : isApproved
                              ? Icons.verified_rounded
                              : Icons.schedule_rounded,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeroPill(label: _statusTitle(status), color: accent),
                        _HeroPill(
                          label: isApproved
                              ? 'WORKSPACE READY'
                              : 'We’ll notify you once review is complete',
                          color: const Color(0xFF334155),
                          background: const Color(0x99FFFFFF),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                _statusHeadline(status),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                institutionName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                supportingCopy,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  fontSize: 15.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTimeline(String status) {
    final isDeclined = status == 'declined';
    final isCancelled = status == 'cancelled';
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatusStepChip(
              title: 'Submitted',
              icon: Icons.check_circle_rounded,
              active: true,
            ),
            _StatusStepChip(
              title: isCancelled ? 'Closed' : 'In Review',
              icon: Icons.hourglass_top_rounded,
              active: status != 'approved' && status != 'declined',
            ),
            _StatusStepChip(
              title: isDeclined
                  ? 'Needs attention'
                  : isCancelled
                  ? 'Closed'
                  : 'Approved',
              icon: isDeclined
                  ? Icons.refresh_rounded
                  : isCancelled
                  ? Icons.block_rounded
                  : Icons.verified_rounded,
              active: status == 'approved' || isDeclined || isCancelled,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingWorkspace({
    required String status,
    required String institutionName,
    required bool canContactSupport,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 820;
        final isCancelled = status == 'cancelled';
        final cardA = _PendingInfoCard(
          icon: Icons.timeline_rounded,
          title: 'What happens next',
          description: isCancelled
              ? 'This request is no longer in the review queue. Contact support if something feels off.'
              : 'Your request is under review by our team. Once the review completes, access updates automatically.',
          accent: const Color(0xFF2563EB),
        );
        final cardB = _RequestManagementCard(
          onContactSupport: canContactSupport
              ? () => _contactSupport(
                  institutionName: institutionName,
                  status: status,
                )
              : null,
        );

        if (useRow) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cardA),
              const SizedBox(width: 14),
              Expanded(child: cardB),
            ],
          );
        }

        return Column(children: [cardA, const SizedBox(height: 14), cardB]);
      },
    );
  }

  Widget _buildReviewConsole({
    required String status,
    required String institutionName,
    required bool compact,
  }) {
    final isApproved = status == 'approved';
    final isDeclined = status == 'declined';
    final isCancelled = status == 'cancelled';
    final accent = isDeclined
        ? const Color(0xFFFF9AAE)
        : isCancelled
        ? const Color(0xFFF8C471)
        : isApproved
        ? const Color(0xFF4BE3B6)
        : const Color(0xFF7FB3FF);

    final title = isDeclined
        ? 'Declined request'
        : isCancelled
        ? 'Request closed'
        : isApproved
        ? 'Approval complete'
        : 'Review console active';
    final body = isDeclined
        ? 'The request was declined. Contact support if you need help understanding the decision.'
        : isCancelled
        ? 'The request is no longer in review. Contact support if you need a hand.'
        : isApproved
        ? 'Your institution is approved. The dashboard will unlock the full admin workflow automatically.'
        : 'Approval is still in progress. You will get access once your institution is approved.';

    return GlassCard(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF0D1F3D), Color(0xFF16345D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 18 : 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                institutionName,
                style: const TextStyle(
                  color: Color(0xFFF8FBFF),
                  fontWeight: FontWeight.w800,
                  fontSize: 23,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: const TextStyle(
                  color: Color(0xFFC7D8F6),
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApprovedWorkspace(String institutionName) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 820;
        final left = Expanded(
          child: _PendingInfoCard(
            icon: Icons.verified_rounded,
            title: 'Institution cleared',
            description:
                '$institutionName is approved. The admin workspace is now the primary place for join access, members, and onboarding actions.',
            accent: const Color(0xFF0F9D8A),
          ),
        );
        final right = Expanded(
          child: _PendingInfoCard(
            icon: Icons.rocket_launch_rounded,
            title: 'What happens next',
            description:
                'Refreshes in access state happen automatically. If you are still on this screen momentarily, the admin workspace will be the next destination.',
            accent: const Color(0xFF2563EB),
          ),
        );

        if (useRow) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [left, const SizedBox(width: 14), right],
          );
        }
        return Column(children: [left, const SizedBox(height: 14), right]);
      },
    );
  }

  Widget _buildDeclinedWorkspace(
    String? declineReason, {
    required String institutionName,
    required bool canContactSupport,
  }) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Declined request',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your request was declined. Contact support if you need clarification or help with the next step.',
              style: TextStyle(
                color: Color(0xFF516784),
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            if ((declineReason ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFECDD3)),
                ),
                child: Text(
                  'Reason: ${declineReason!.trim()}',
                  style: const TextStyle(
                    color: Color(0xFF9F1239),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (canContactSupport)
                  FilledButton.icon(
                    onPressed: () => _contactSupport(
                      institutionName: institutionName,
                      status: 'declined',
                    ),
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text('Contact Support'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final institutionAsync = ref.watch(currentAdminInstitutionRequestProvider);
    final currentProfile = ref.watch(currentUserProfileProvider).valueOrNull;
    final canContactSupport = currentProfile?.role == UserRole.institutionAdmin;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: _InstitutionPendingBackdrop(
        controller: _pulseController,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 1120;
              final horizontal = isDesktop ? 20.0 : 14.0;
              return Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 20),
                child: Column(
                  children: [
                    _PendingWorkspaceHeader(
                      isDesktop: isDesktop,
                      onLogout: () =>
                          confirmAndLogout(context: context, ref: ref),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF8F8F3,
                          ).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x120F172A),
                              blurRadius: 30,
                              offset: Offset(0, 18),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            isDesktop ? 28 : 18,
                            22,
                            isDesktop ? 28 : 18,
                            28,
                          ),
                          child: institutionAsync.when(
                            data: (institution) {
                              final status =
                                  (institution?['status'] as String?) ??
                                  'pending';
                              final isDeclined = status == 'declined';
                              final isApproved = status == 'approved';
                              final review = institution?['review'];
                              final declineReason = review is Map
                                  ? (review['declineReason'] as String?)
                                  : null;
                              final institutionName =
                                  (institution?['name'] as String?) ??
                                  'Your institution';
                              return LayoutBuilder(
                                builder: (context, innerConstraints) {
                                  final useDesktopSplit =
                                      innerConstraints.maxWidth >= 980;
                                  final primaryColumn = Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildStatusHero(
                                        context,
                                        status: status,
                                        institutionName: institutionName,
                                      ),
                                      const SizedBox(height: 14),
                                      _buildStatusTimeline(status),
                                      const SizedBox(height: 14),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 350,
                                        ),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        child: isDeclined
                                            ? _buildDeclinedWorkspace(
                                                declineReason,
                                                institutionName:
                                                    institutionName,
                                                canContactSupport:
                                                    canContactSupport,
                                              )
                                            : isApproved
                                            ? _buildApprovedWorkspace(
                                                institutionName,
                                              )
                                            : _buildPendingWorkspace(
                                                status: status,
                                                institutionName:
                                                    institutionName,
                                                canContactSupport:
                                                    canContactSupport,
                                              ),
                                      ),
                                    ],
                                  );

                                  if (!useDesktopSplit) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        primaryColumn,
                                        const SizedBox(height: 14),
                                        _buildReviewConsole(
                                          status: status,
                                          institutionName: institutionName,
                                          compact: true,
                                        ),
                                      ],
                                    );
                                  }

                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 13, child: primaryColumn),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 8,
                                        child: _buildReviewConsole(
                                          status: status,
                                          institutionName: institutionName,
                                          compact: false,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            loading: () => const GlassCard(
                              child: Padding(
                                padding: EdgeInsets.all(22),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                            error: (error, _) => GlassCard(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Text(error.toString()),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StatusStepChip extends StatelessWidget {
  const _StatusStepChip({
    required this.title,
    required this.icon,
    required this.active,
  });

  final String title;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? const Color(0xFFE0F2FE)
        : const Color(0xFFF8FAFC);
    final border = active ? const Color(0xFFBAE6FD) : const Color(0xFFE2E8F0);
    final textColor = active
        ? const Color(0xFF0C4A6E)
        : const Color(0xFF64748B);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.label,
    required this.color,
    this.background = Colors.white,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _RequestManagementCard extends StatelessWidget {
  const _RequestManagementCard({required this.onContactSupport});

  final VoidCallback? onContactSupport;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0x140F9D8A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFF0F9D8A),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need help?',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'If the request needs a human review, contact support from here.',
                        style: TextStyle(
                          color: Color(0xFF516784),
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (onContactSupport != null)
                  FilledButton.icon(
                    onPressed: onContactSupport,
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text('Contact Support'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerSupportChatSheet extends ConsumerStatefulWidget {
  const _OwnerSupportChatSheet({
    required this.institutionName,
    required this.contextStatus,
  });

  final String institutionName;
  final String contextStatus;

  @override
  ConsumerState<_OwnerSupportChatSheet> createState() =>
      _OwnerSupportChatSheetState();
}

class _OwnerSupportChatSheetState
    extends ConsumerState<_OwnerSupportChatSheet> {
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = const [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final messages = await ref
          .read(institutionRepositoryProvider)
          .getCurrentUserSupportMessages();
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _isSending) {
      return;
    }
    setState(() => _isSending = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .sendCurrentUserSupportMessage(
            body: body,
            institutionName: widget.institutionName,
            contextStatus: widget.contextStatus,
          );
      _messageController.clear();
      await _loadMessages();
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        const SnackBar(
          content: Text('Support message sent. A team helper will reply here.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String _formatTimestamp(dynamic value) {
    DateTime? date;
    if (value is DateTime) {
      date = value.toLocal();
    } else {
      try {
        date = (value?.toDate() as DateTime?)?.toLocal();
      } catch (_) {
        date = null;
      }
    }
    if (date == null) {
      return 'Just now';
    }
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} ${date.hour}:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxWidth = size.width >= 1180 ? 920.0 : 760.0;
    final sheetHeight = math.min(size.height * 0.8, 700.0);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: sheetHeight,
                ),
                child: GlassCard(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 18, 18, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF14B8A6),
                                      Color(0xFF2563EB),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.support_agent_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'MindNest Support',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 22,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Ask for help here and keep everything inside the same workspace.',
                                      style: TextStyle(
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: const Color(0xFFBFDBFE),
                                    ),
                                  ),
                                  child: const Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        color: Color(0xFF2563EB),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'A team helper will chat with you here as soon as one is available. You can leave your message now and keep this same thread for follow-up.',
                                          style: TextStyle(
                                            color: Color(0xFF1E3A8A),
                                            fontWeight: FontWeight.w700,
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Expanded(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FBFF),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: const Color(0xFFD9E7F5),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        : _loadError != null
                                        ? Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(20),
                                              child: Text(
                                                _loadError!,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Color(0xFFB91C1C),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          )
                                        : _messages.isEmpty
                                        ? const Center(
                                            child: Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Text(
                                                'No messages yet. Start the conversation below and the owner team will pick it up from their dashboard.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Color(0xFF64748B),
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.5,
                                                ),
                                              ),
                                            ),
                                          )
                                        : ListView.separated(
                                            padding: const EdgeInsets.all(16),
                                            itemCount: _messages.length,
                                            separatorBuilder:
                                                (context, index) =>
                                                    const SizedBox(height: 10),
                                            itemBuilder: (context, index) {
                                              final message = _messages[index];
                                              final senderRole =
                                                  (message['senderRole']
                                                              as String? ??
                                                          'requester')
                                                      .trim()
                                                      .toLowerCase();
                                              final isOwner =
                                                  senderRole == 'owner';
                                              return Align(
                                                alignment: isOwner
                                                    ? Alignment.centerLeft
                                                    : Alignment.centerRight,
                                                child: ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                        maxWidth: 520,
                                                      ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          14,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isOwner
                                                          ? Colors.white
                                                          : const Color(
                                                              0xFF0F9D8A,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            18,
                                                          ),
                                                      border: Border.all(
                                                        color: isOwner
                                                            ? const Color(
                                                                0xFFD6E4F3,
                                                              )
                                                            : const Color(
                                                                0xFF0C8A7A,
                                                              ),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          isOwner
                                                              ? 'MindNest team'
                                                              : 'You',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: isOwner
                                                                ? const Color(
                                                                    0xFF0F172A,
                                                                  )
                                                                : Colors.white,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Text(
                                                          (message['body']
                                                                      as String? ??
                                                                  '')
                                                              .trim(),
                                                          style: TextStyle(
                                                            color: isOwner
                                                                ? const Color(
                                                                    0xFF334155,
                                                                  )
                                                                : Colors.white,
                                                            height: 1.45,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Text(
                                                          _formatTimestamp(
                                                            message['createdAt'],
                                                          ),
                                                          style: TextStyle(
                                                            color: isOwner
                                                                ? const Color(
                                                                    0xFF94A3B8,
                                                                  )
                                                                : const Color(
                                                                    0xFFD5FAF5,
                                                                  ),
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: const Color(0xFFD5E6F5),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _messageController,
                                          minLines: 1,
                                          maxLines: 5,
                                          decoration: const InputDecoration(
                                            hintText:
                                                'Describe the problem and the support team will pick it up here...',
                                            border: InputBorder.none,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      FilledButton.icon(
                                        onPressed: _isSending
                                            ? null
                                            : _sendMessage,
                                        icon: Icon(
                                          _isSending
                                              ? Icons.hourglass_top_rounded
                                              : Icons.send_rounded,
                                        ),
                                        label: Text(
                                          _isSending ? 'Sending...' : 'Send',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingInfoCard extends StatelessWidget {
  const _PendingInfoCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF516784),
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstitutionPendingBackdrop extends StatelessWidget {
  const _InstitutionPendingBackdrop({
    required this.child,
    required this.controller,
  });

  final Widget child;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tick = controller.value;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFEAF6FF), Color(0xFFF7FBF9), Color(0xFFEFF7F4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              _PendingOrb(
                size: 300,
                color: const Color(0x5538BDF8),
                left: -90 + math.cos(tick * math.pi * 2) * 18,
                top: 120 + math.sin(tick * math.pi * 2) * 14,
              ),
              _PendingOrb(
                size: 260,
                color: const Color(0x5514B8A6),
                right: -60 + math.sin(tick * math.pi * 2) * 16,
                top: 220 + math.cos(tick * math.pi * 2) * 18,
              ),
              _PendingOrb(
                size: 220,
                color: const Color(0x55A7F3D0),
                left: 140 + math.sin(tick * math.pi * 2) * 18,
                bottom: 30 + math.cos(tick * math.pi * 2) * 16,
              ),
              child,
            ],
          ),
        );
      },
    );
  }
}

class _PendingOrb extends StatelessWidget {
  const _PendingOrb({
    required this.size,
    required this.color,
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  final double size;
  final Color color;
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color, blurRadius: 120, spreadRadius: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingWorkspaceHeader extends StatelessWidget {
  const _PendingWorkspaceHeader({
    required this.isDesktop,
    required this.onLogout,
  });

  final bool isDesktop;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 22 : 18,
        vertical: isDesktop ? 18 : 16,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1E39),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 26,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Institution Approval',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Live review status and institution access controls',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFBFD0EC),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          FilledButton.icon(
            onPressed: onLogout,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0x1FFFFFFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
