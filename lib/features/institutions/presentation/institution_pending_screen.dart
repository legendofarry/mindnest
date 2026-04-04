import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/config/school_catalog.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart' show GlassCard;
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
  bool _isResubmitting = false;
  String? _selectedSchoolId;
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

  Future<void> _resubmit() async {
    final schoolId = _selectedSchoolId?.trim() ?? '';
    final selectedSchool = catalogSchoolById(schoolId);
    if (selectedSchool == null) {
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Select your school to resubmit.')),
      );
      return;
    }
    setState(() => _isResubmitting = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .resubmitCurrentAdminInstitutionRequest(
            institutionCatalogId: selectedSchool.id,
            institutionName: selectedSchool.name,
          );
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Request resubmitted. Approval usually takes about 30 minutes.',
          ),
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
        setState(() => _isResubmitting = false);
      }
    }
  }

  String _statusTitle(String status) {
    if (status == 'declined') {
      return 'Action Needed';
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
    if (status == 'approved') {
      return 'Institution approved';
    }
    return 'Institution request submitted';
  }

  List<Color> _statusGradient(String status) {
    if (status == 'declined') {
      return const [Color(0xFFFFE4E6), Color(0xFFFFF1F2)];
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
    final isApproved = status == 'approved';
    final supportingCopy = isDeclined
        ? 'Your institution request needs an update before it can move '
              'forward. Fix the issue below and resubmit from this screen.'
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
                          label: isApproved ? 'WORKSPACE READY' : 'ETA ~24 HRS',
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
              title: 'In Review',
              icon: Icons.hourglass_top_rounded,
              active: status != 'approved' && status != 'declined',
            ),
            _StatusStepChip(
              title: isDeclined ? 'Needs Update' : 'Approved',
              icon: isDeclined ? Icons.refresh_rounded : Icons.verified_rounded,
              active: status == 'approved' || isDeclined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingWorkspace(String status) {
    final isDeclined = status == 'declined';
    if (isDeclined) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 820;
        final cardA = _PendingInfoCard(
          icon: Icons.timeline_rounded,
          title: 'What happens next',
          description:
              'We verify institution identity and request details. Once the review completes, access updates automatically.',
          accent: const Color(0xFF2563EB),
        );
        final cardB = _PendingInfoCard(
          icon: Icons.grid_view_rounded,
          title: 'Why stay here',
          description:
              'This screen is the live status surface for approval. You do not need to restart the flow or create another account.',
          accent: const Color(0xFF0F9D8A),
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
    final accent = isDeclined
        ? const Color(0xFFFF9AAE)
        : isApproved
        ? const Color(0xFF4BE3B6)
        : const Color(0xFF7FB3FF);

    final title = isDeclined
        ? 'Resubmission lane open'
        : isApproved
        ? 'Approval complete'
        : 'Review console active';
    final body = isDeclined
        ? 'Correct the institution selection and send the request again from this same workspace.'
        : isApproved
        ? 'Your institution is approved. The dashboard will unlock the full admin workflow automatically.'
        : 'Approval is still in progress. Stay signed in and this status surface will remain the source of truth.';

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

  Widget _buildDeclinedWorkspace(String? declineReason) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fix and Resubmit',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pick the correct institution from the approved catalog, or send a school-not-listed request if it is missing.',
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
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedSchoolId,
              decoration: const InputDecoration(
                hintText: 'Select school from approved list',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
              items: kCatalogSchools
                  .map(
                    (school) => DropdownMenuItem<String>(
                      value: school.id,
                      child: Text(school.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _isResubmitting
                  ? null
                  : (value) => setState(() => _selectedSchoolId = value),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _isResubmitting
                      ? null
                      : () => context.go(
                          AppRoute.registerInstitutionSchoolRequest,
                        ),
                  icon: const Icon(Icons.add_business_rounded, size: 18),
                  label: const Text('School not listed?'),
                ),
                FilledButton.icon(
                  onPressed: _isResubmitting ? null : _resubmit,
                  icon: Icon(
                    _isResubmitting
                        ? Icons.hourglass_top_rounded
                        : Icons.refresh_rounded,
                  ),
                  label: Text(
                    _isResubmitting ? 'Resubmitting...' : 'Resubmit Request',
                  ),
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
                                              )
                                            : isApproved
                                            ? _buildApprovedWorkspace(
                                                institutionName,
                                              )
                                            : _buildPendingWorkspace(status),
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

class _ConsolePill extends StatelessWidget {
  const _ConsolePill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE8F1FF),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
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
