import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/config/owner_config.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class OwnerDashboardScreen extends ConsumerStatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  ConsumerState<OwnerDashboardScreen> createState() =>
      _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  final _declineReasonController = TextEditingController();

  @override
  void dispose() {
    _declineReasonController.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Institution approved successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Institution declined.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
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
