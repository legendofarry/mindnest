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
  bool _isClearingDatabase = false;

  @override
  void dispose() {
    _declineReasonController.dispose();
    _clearDbConfirmationController.dispose();
    super.dispose();
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
        const SnackBar(content: Text('Institution approved successfully.')),
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
        const SnackBar(content: Text('Institution declined.')),
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
            approved ? 'School request approved.' : 'School request declined.',
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

    return MindNestShell(
      maxWidth: 1200,
      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
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
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Signed in as owner (${authUser?.email ?? kOwnerEmail})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
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
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: ref
                              .read(institutionRepositoryProvider)
                              .watchOwnerPendingInstitutions(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(14),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final rows =
                                snapshot.data ?? const <Map<String, dynamic>>[];
                            if (rows.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('No pending institution requests.'),
                              );
                            }
                            return Column(
                              children: rows
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
                                                      fontWeight:
                                                          FontWeight.w700,
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
                            );
                          },
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
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: ref
                              .read(institutionRepositoryProvider)
                              .watchOwnerSchoolRequests(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(14),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final rows =
                                snapshot.data ?? const <Map<String, dynamic>>[];
                            if (rows.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('No school requests right now.'),
                              );
                            }
                            return Column(
                              children: rows
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
                                                      fontWeight:
                                                          FontWeight.w700,
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
                            );
                          },
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
