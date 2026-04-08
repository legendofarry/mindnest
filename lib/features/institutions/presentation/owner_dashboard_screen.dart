import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/config/owner_config.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/core/ui/modern_banner.dart';

class OwnerDashboardScreen extends ConsumerStatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  ConsumerState<OwnerDashboardScreen> createState() =>
      _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  final _declineReasonController = TextEditingController();
  final _clearDbConfirmationController = TextEditingController();
  final _institutionSearchController = TextEditingController();
  List<Map<String, dynamic>> _ownerInstitutions = const [];
  List<Map<String, dynamic>> _ownerSchoolRequests = const [];
  bool _isOwnerDataLoading = true;
  bool _isOwnerDataRefreshing = false;
  String? _ownerDataError;
  DateTime? _ownerLastRefreshedAt;
  bool _isClearingDatabase = false;
  String _institutionStatusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadOwnerData();
  }

  @override
  void dispose() {
    _declineReasonController.dispose();
    _clearDbConfirmationController.dispose();
    _institutionSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadOwnerData({bool manualRefresh = false}) async {
    if (manualRefresh && _isOwnerDataRefreshing) {
      return;
    }
    setState(() {
      if (manualRefresh) {
        _isOwnerDataRefreshing = true;
      } else {
        _isOwnerDataLoading = true;
      }
      _ownerDataError = null;
    });

    try {
      final repository = ref.read(institutionRepositoryProvider);
      final results = await Future.wait<List<Map<String, dynamic>>>([
        repository.getOwnerInstitutions(),
        repository.getOwnerSchoolRequests(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _ownerInstitutions = results[0];
        _ownerSchoolRequests = results[1];
        _ownerLastRefreshedAt = DateTime.now();
        _ownerDataError = null;
      });
      if (manualRefresh) {
        showModernBannerFromSnackBar(
          context,
          const SnackBar(content: Text('Owner data refreshed.')),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _ownerDataError = message;
      });
      showModernBannerFromSnackBar(context, SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _isOwnerDataLoading = false;
          _isOwnerDataRefreshing = false;
        });
      }
    }
  }

  Future<void> _approveInstitution(String institutionId) async {
    try {
      await ref
          .read(institutionRepositoryProvider)
          .approveInstitutionRequest(institutionId: institutionId);
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Institution approved. Click Refresh to update owner records.',
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
    }
  }

  Future<void> _declineInstitution(String institutionId) async {
    _declineReasonController.clear();
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline institution request'),
        content: TextField(
          controller: _declineReasonController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Decline reason',
            hintText: 'Reason shown to institution admin',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (shouldProceed != true) {
      return;
    }
    final reason = _declineReasonController.text.trim();
    if (reason.length < 3) {
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Enter a valid decline reason.')),
      );
      return;
    }

    try {
      await ref
          .read(institutionRepositoryProvider)
          .declineInstitutionRequest(
            institutionId: institutionId,
            declineReason: reason,
          );
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        const SnackBar(
          content: Text('Institution declined. Click Refresh to sync changes.'),
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
    }
  }

  Future<void> _resolveSchoolRequest({
    required String requestId,
    required bool approved,
  }) async {
    try {
      await ref
          .read(institutionRepositoryProvider)
          .resolveSchoolRequest(requestId: requestId, approved: approved);
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(
            approved
                ? 'School request approved. Click Refresh to sync.'
                : 'School request declined. Click Refresh to sync.',
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
    }
  }

  String _formatDate(dynamic value) {
    if (value is Timestamp) {
      final local = value.toDate().toLocal();
      return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '--';
  }

  String _formatRefreshStamp(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')} ${_monthLabel(local.month)} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatShortDate(dynamic value) {
    if (value is Timestamp) {
      final local = value.toDate().toLocal();
      return '${local.day.toString().padLeft(2, '0')} ${_monthLabel(local.month)} ${local.year}';
    }
    return '--';
  }

  String _monthLabel(int month) {
    const labels = <String>[
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
    final monthIndex = month < 1
        ? 1
        : month > 12
        ? 12
        : month;
    return labels[monthIndex - 1];
  }

  String _statusLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'approved':
        return 'Approved';
      case 'declined':
        return 'Declined';
      case 'pending':
        return 'Pending';
      default:
        return 'Unknown';
    }
  }

  IconData _statusIcon(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'approved':
        return Icons.verified_rounded;
      case 'declined':
        return Icons.block_rounded;
      case 'pending':
        return Icons.hourglass_top_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color _statusBackground(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'approved':
        return const Color(0xFFE0F7F3);
      case 'declined':
        return const Color(0xFFFFE8EA);
      case 'pending':
        return const Color(0xFFFFF1D8);
      default:
        return const Color(0xFFE8EEF7);
    }
  }

  Color _statusForeground(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'approved':
        return const Color(0xFF0B8E7D);
      case 'declined':
        return const Color(0xFFCC304D);
      case 'pending':
        return const Color(0xFFB56A08);
      default:
        return const Color(0xFF4C6484);
    }
  }

  List<Map<String, dynamic>> _applyInstitutionFilters(
    List<Map<String, dynamic>> institutions,
  ) {
    final query = _institutionSearchController.text.trim().toLowerCase();
    return institutions
        .where((institution) {
          final status = (institution['status'] as String? ?? '').trim();
          if (_institutionStatusFilter != 'all' &&
              status.toLowerCase() != _institutionStatusFilter) {
            return false;
          }

          if (query.isEmpty) {
            return true;
          }

          final fields = <String>[
            (institution['name'] as String? ?? ''),
            (institution['institutionCatalogId'] as String? ?? ''),
            (institution['adminPhoneNumber'] as String? ?? ''),
            (institution['contactPhone'] as String? ?? ''),
            (institution['additionalAdminPhoneNumber'] as String? ?? ''),
            status,
          ];
          return fields.any((field) => field.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  List<_OwnerActivityItem> _buildRecentActivities({
    required List<Map<String, dynamic>> institutions,
    required List<Map<String, dynamic>> schoolRequests,
  }) {
    final items = <_OwnerActivityItem>[];

    for (final institution in institutions) {
      final name = (institution['name'] as String? ?? 'Institution').trim();
      final status = (institution['status'] as String? ?? '')
          .trim()
          .toLowerCase();
      final createdAt = institution['createdAt'];
      final review = institution['review'] as Map<String, dynamic>?;
      final decision = (review?['decision'] as String? ?? '')
          .trim()
          .toLowerCase();
      final reviewedAt = review?['reviewedAt'];
      final updatedAt = institution['updatedAt'];

      if (createdAt != null) {
        items.add(
          _OwnerActivityItem(
            icon: Icons.apartment_rounded,
            title: '$name registered',
            subtitle: 'Institution request entered the owner review queue.',
            occurredAt: createdAt,
            tone: _statusForeground('pending'),
          ),
        );
      }

      if (decision == 'approved' && reviewedAt != null) {
        items.add(
          _OwnerActivityItem(
            icon: Icons.verified_rounded,
            title: '$name approved',
            subtitle: 'Institution is now cleared to onboard members.',
            occurredAt: reviewedAt,
            tone: _statusForeground('approved'),
          ),
        );
      } else if (decision == 'declined' && reviewedAt != null) {
        items.add(
          _OwnerActivityItem(
            icon: Icons.block_rounded,
            title: '$name declined',
            subtitle: 'The institution request was closed by owner review.',
            occurredAt: reviewedAt,
            tone: _statusForeground('declined'),
          ),
        );
      } else if (status == 'pending' && updatedAt != null) {
        items.add(
          _OwnerActivityItem(
            icon: Icons.hourglass_top_rounded,
            title: '$name awaiting review',
            subtitle: 'Still sitting in the live owner approvals queue.',
            occurredAt: updatedAt,
            tone: _statusForeground('pending'),
          ),
        );
      }
    }

    for (final request in schoolRequests) {
      final schoolName = (request['schoolName'] as String? ?? 'School request')
          .trim();
      items.add(
        _OwnerActivityItem(
          icon: Icons.school_rounded,
          title: '$schoolName requested',
          subtitle: 'A school-not-listed request is waiting for owner review.',
          occurredAt: request['createdAt'],
          tone: const Color(0xFF2C6BE5),
        ),
      );
    }

    items.sort((a, b) => b.sortDate.compareTo(a.sortDate));
    return items.take(8).toList(growable: false);
  }

  Future<void> _confirmAndClearDatabase() async {
    if (!kIsWeb || _isClearingDatabase) {
      return;
    }

    _clearDbConfirmationController.clear();
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 10),
              Expanded(child: Text('Clear Firestore DB')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This web-only development action deletes MindNest app data from Firestore, including users, invites, sessions, notifications, live session content, and institution records.',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Firebase Authentication accounts are not deleted here. Type CLEAR DB to continue.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF991B1B),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _clearDbConfirmationController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmation phrase',
                    hintText: 'CLEAR DB',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _clearDbConfirmationController,
              builder: (context, value, _) {
                final canConfirm =
                    value.text.trim().toUpperCase() == 'CLEAR DB';
                return FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: canConfirm
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Clear DB'),
                );
              },
            ),
          ],
        );
      },
    );

    if (shouldProceed != true) {
      return;
    }

    setState(() => _isClearingDatabase = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .clearAllDataForDevelopment();
      if (!mounted) {
        return;
      }
      showModernBannerFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Firestore development data cleared. Firebase Auth accounts were left intact.',
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
        setState(() => _isClearingDatabase = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateChangesProvider).valueOrNull;
    final isOwner = isOwnerEmail(authUser?.email);
    final institutions = _ownerInstitutions;
    final pendingInstitutions = institutions
        .where(
          (item) =>
              ((item['status'] as String?) ?? '').trim().toLowerCase() ==
              'pending',
        )
        .toList(growable: false);
    final filteredInstitutions = _applyInstitutionFilters(institutions);
    final activities = _buildRecentActivities(
      institutions: institutions,
      schoolRequests: _ownerSchoolRequests,
    );
    final pendingCount = pendingInstitutions.length;
    final approvedCount = institutions
        .where(
          (item) =>
              ((item['status'] as String?) ?? '').trim().toLowerCase() ==
              'approved',
        )
        .length;
    final declinedCount = institutions
        .where(
          (item) =>
              ((item['status'] as String?) ?? '').trim().toLowerCase() ==
              'declined',
        )
        .length;

    return MindNestShell(
      maxWidth: 1200,
      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _isOwnerDataRefreshing
                ? null
                : () => _loadOwnerData(manualRefresh: true),
            icon: _isOwnerDataRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => confirmAndLogout(context: context, ref: ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      child: !isOwner
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Access denied. This dashboard is for the owner account only.',
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(Icons.admin_panel_settings_rounded),
                        Text(
                          'Signed in as owner (${authUser?.email ?? kOwnerEmail})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (_ownerLastRefreshedAt != null)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                'Last refreshed ${_formatRefreshStamp(_ownerLastRefreshedAt!)}',
                                style: const TextStyle(
                                  color: Color(0xFF365176),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFE8F8F2),
                            borderRadius: BorderRadius.all(
                              Radius.circular(999),
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Text(
                              'Manual refresh mode',
                              style: TextStyle(
                                color: Color(0xFF0A8A78),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_ownerDataError != null) ...[
                  const SizedBox(height: 14),
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFB91C1C),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _ownerDataError!,
                              style: const TextStyle(color: Color(0xFF7F1D1D)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _isOwnerDataLoading && institutions.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Owner overview',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Live institution telemetry and owner records in one place so you can govern beyond simple approve/decline flows.',
                                style: TextStyle(
                                  color: Color(0xFF5D7291),
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _OwnerStatChip(
                                    icon: Icons.apartment_rounded,
                                    label:
                                        'Institutions ${institutions.length}',
                                    background: const Color(0xFFE6F8FF),
                                    foreground: const Color(0xFF0F6D96),
                                  ),
                                  _OwnerStatChip(
                                    icon: Icons.hourglass_top_rounded,
                                    label: 'Pending $pendingCount',
                                    background: const Color(0xFFFFF3DE),
                                    foreground: const Color(0xFFB56A08),
                                  ),
                                  _OwnerStatChip(
                                    icon: Icons.verified_rounded,
                                    label: 'Approved $approvedCount',
                                    background: const Color(0xFFE3F8F1),
                                    foreground: const Color(0xFF0A8A78),
                                  ),
                                  _OwnerStatChip(
                                    icon: Icons.block_rounded,
                                    label: 'Declined $declinedCount',
                                    background: const Color(0xFFFFEBEF),
                                    foreground: const Color(0xFFC93552),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 340,
                                    child: TextField(
                                      controller: _institutionSearchController,
                                      onChanged: (_) => setState(() {}),
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Search institution records...',
                                        prefixIcon: Icon(Icons.search_rounded),
                                      ),
                                    ),
                                  ),
                                  for (final option in const <String>[
                                    'all',
                                    'pending',
                                    'approved',
                                    'declined',
                                  ])
                                    ChoiceChip(
                                      label: Text(
                                        option == 'all'
                                            ? 'All'
                                            : _statusLabel(option),
                                      ),
                                      selected:
                                          _institutionStatusFilter == option,
                                      onSelected: (_) => setState(() {
                                        _institutionStatusFilter = option;
                                      }),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _OwnerInstitutionRecordsTable(
                                rows: filteredInstitutions,
                                formatStatus: _statusLabel,
                                formatDate: _formatShortDate,
                                statusBackground: _statusBackground,
                                statusForeground: _statusForeground,
                                statusIcon: _statusIcon,
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent owner activity',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_isOwnerDataLoading && activities.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (activities.isEmpty)
                          const Text(
                            'Activity will appear here as institutions and school requests move.',
                            style: TextStyle(color: Color(0xFF5D7291)),
                          )
                        else
                          Column(
                            children: activities
                                .map(
                                  (item) => _OwnerActivityTile(
                                    item: item,
                                    formatDate: _formatDate,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (kIsWeb) ...[
                  GlassCard(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFFF1F2),
                            const Color(0xFFFFFBEB),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFECDD3),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.delete_forever_rounded,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Danger Zone',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                      color: Color(0xFF7F1D1D),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Development-only Firestore wipe for the owner dashboard on web. This clears app collections and nested live-session content, but leaves Firebase Authentication accounts untouched.',
                                    style: TextStyle(
                                      color: Color(0xFF7C2D12),
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFDC2626,
                                          ),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 14,
                                          ),
                                        ),
                                        onPressed: _isClearingDatabase
                                            ? null
                                            : _confirmAndClearDatabase,
                                        icon: _isClearingDatabase
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.cleaning_services_rounded,
                                              ),
                                        label: Text(
                                          _isClearingDatabase
                                              ? 'Clearing DB...'
                                              : 'Clear DB',
                                        ),
                                      ),
                                      const Text(
                                        'Type CLEAR DB in the confirmation dialog to run it.',
                                        style: TextStyle(
                                          color: Color(0xFF991B1B),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pending Institution Requests',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_isOwnerDataLoading && pendingInstitutions.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (pendingInstitutions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No pending institution requests.'),
                          )
                        else
                          Column(
                            children: pendingInstitutions
                                .map((item) {
                                  final id = (item['id'] as String?) ?? '';
                                  final name =
                                      (item['name'] as String?) ??
                                      'Institution';
                                  final createdBy =
                                      (item['createdBy'] as String?) ?? '--';
                                  final contactNumber =
                                      (item['adminPhoneNumber'] as String?) ??
                                      (item['contactPhone'] as String?) ??
                                      (item['mobileNumber'] as String?) ??
                                      '--';
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text('Created by: $createdBy'),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.phone_rounded,
                                                size: 16,
                                                color: Color(0xFF0E7490),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Admin contact: $contactNumber',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            'Submitted: ${_formatDate(item['createdAt'])}',
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              FilledButton.icon(
                                                onPressed: () =>
                                                    _approveInstitution(id),
                                                icon: const Icon(
                                                  Icons.check_rounded,
                                                ),
                                                label: const Text('Approve'),
                                              ),
                                              const SizedBox(width: 8),
                                              OutlinedButton.icon(
                                                onPressed: () =>
                                                    _declineInstitution(id),
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                ),
                                                label: const Text('Decline'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'School Not Listed Requests',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_isOwnerDataLoading && _ownerSchoolRequests.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_ownerSchoolRequests.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No school requests right now.'),
                          )
                        else
                          Column(
                            children: _ownerSchoolRequests
                                .map((item) {
                                  final id = (item['id'] as String?) ?? '';
                                  final schoolName =
                                      (item['schoolName'] as String?) ?? '--';
                                  final contactNumber =
                                      (item['mobileNumber'] as String?) ??
                                      (item['phoneNumber'] as String?) ??
                                      (item['mobile'] as String?) ??
                                      '--';
                                  final requesterEmail =
                                      (item['requesterEmail'] as String?) ??
                                      '--';
                                  final requesterName =
                                      (item['requesterName'] as String?) ??
                                      '--';
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            schoolName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.phone_rounded,
                                                size: 16,
                                                color: Color(0xFF0E7490),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Contact: $contactNumber',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text('Requester: $requesterName'),
                                          Text('Email: $requesterEmail'),
                                          Text(
                                            'Submitted: ${_formatDate(item['createdAt'])}',
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              FilledButton.icon(
                                                onPressed: () =>
                                                    _resolveSchoolRequest(
                                                      requestId: id,
                                                      approved: true,
                                                    ),
                                                icon: const Icon(
                                                  Icons.check_rounded,
                                                ),
                                                label: const Text('Approve'),
                                              ),
                                              const SizedBox(width: 8),
                                              OutlinedButton.icon(
                                                onPressed: () =>
                                                    _resolveSchoolRequest(
                                                      requestId: id,
                                                      approved: false,
                                                    ),
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                ),
                                                label: const Text('Decline'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OwnerActivityItem {
  const _OwnerActivityItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.occurredAt,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final dynamic occurredAt;
  final Color tone;

  DateTime get sortDate {
    if (occurredAt is Timestamp) {
      return (occurredAt as Timestamp).toDate().toLocal();
    }
    if (occurredAt is DateTime) {
      return (occurredAt as DateTime).toLocal();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _OwnerStatChip extends StatelessWidget {
  const _OwnerStatChip({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerInstitutionRecordsTable extends StatelessWidget {
  const _OwnerInstitutionRecordsTable({
    required this.rows,
    required this.formatStatus,
    required this.formatDate,
    required this.statusBackground,
    required this.statusForeground,
    required this.statusIcon,
  });

  final List<Map<String, dynamic>> rows;
  final String Function(String status) formatStatus;
  final String Function(dynamic value) formatDate;
  final Color Function(String status) statusBackground;
  final Color Function(String status) statusForeground;
  final IconData Function(String status) statusIcon;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No institutions match the current filter.',
          style: TextStyle(color: Color(0xFF5D7291)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const minTableWidth = 980.0;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minTableWidth;
        final tableWidth = math.max(minTableWidth, availableWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6FAFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD6E5F4)),
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 3, child: _OwnerHeader('Institution')),
                      Expanded(
                        flex: 3,
                        child: _OwnerHeader('Catalog / Contact'),
                      ),
                      Expanded(flex: 2, child: _OwnerHeader('Status')),
                      Expanded(flex: 2, child: _OwnerHeader('Created')),
                      Expanded(flex: 2, child: _OwnerHeader('Updated')),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...rows.map((row) {
                  final status = (row['status'] as String? ?? '').trim();
                  final contact =
                      (row['adminPhoneNumber'] as String?) ??
                      (row['contactPhone'] as String?) ??
                      '--';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFDCE8F5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (row['name'] as String? ?? 'Institution')
                                    .trim(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F233F),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                (row['id'] as String? ?? '--').trim(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF7B92AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (row['institutionCatalogId'] as String? ?? '--')
                                    .trim(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF203854),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                contact,
                                style: const TextStyle(
                                  color: Color(0xFF5D7291),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: statusBackground(status),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      statusIcon(status),
                                      size: 14,
                                      color: statusForeground(status),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      formatStatus(status),
                                      style: TextStyle(
                                        color: statusForeground(status),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            formatDate(row['createdAt']),
                            style: const TextStyle(color: Color(0xFF2D4360)),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            formatDate(row['updatedAt']),
                            style: const TextStyle(color: Color(0xFF2D4360)),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OwnerHeader extends StatelessWidget {
  const _OwnerHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: Color(0xFF5D7391),
      ),
    );
  }
}

class _OwnerActivityTile extends StatelessWidget {
  const _OwnerActivityTile({required this.item, required this.formatDate});

  final _OwnerActivityItem item;
  final String Function(dynamic value) formatDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE8F5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: item.tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.tone, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF142842),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF5D7291),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatDate(item.occurredAt),
                  style: const TextStyle(
                    color: Color(0xFF8096B2),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
