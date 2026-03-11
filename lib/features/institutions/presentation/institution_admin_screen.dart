import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/institutions/data/institution_repository.dart';
import 'package:mindnest/features/institutions/models/counselor_workflow_settings.dart';
import 'package:url_launcher/url_launcher.dart';

enum AdminWorkspaceView {
  overview,
  members,
  pendingInvites,
  students,
  staff,
  counselors,
  allInvites,
}

extension AdminWorkspaceViewX on AdminWorkspaceView {
  String get navLabel {
    switch (this) {
      case AdminWorkspaceView.overview:
        return 'Overview';
      case AdminWorkspaceView.members:
        return 'Members';
      case AdminWorkspaceView.pendingInvites:
        return 'Pending Invites';
      case AdminWorkspaceView.students:
        return 'Students';
      case AdminWorkspaceView.staff:
        return 'Staff';
      case AdminWorkspaceView.counselors:
        return 'Counselors';
      case AdminWorkspaceView.allInvites:
        return 'All Invites';
    }
  }

  IconData get navIcon {
    switch (this) {
      case AdminWorkspaceView.overview:
        return Icons.dashboard_rounded;
      case AdminWorkspaceView.members:
        return Icons.groups_rounded;
      case AdminWorkspaceView.pendingInvites:
        return Icons.mark_email_unread_rounded;
      case AdminWorkspaceView.students:
        return Icons.school_rounded;
      case AdminWorkspaceView.staff:
        return Icons.badge_rounded;
      case AdminWorkspaceView.counselors:
        return Icons.health_and_safety_rounded;
      case AdminWorkspaceView.allInvites:
        return Icons.send_rounded;
    }
  }

  String get workspaceTitle {
    switch (this) {
      case AdminWorkspaceView.overview:
        return 'Institution Admin';
      case AdminWorkspaceView.members:
        return 'Members';
      case AdminWorkspaceView.pendingInvites:
        return 'Pending Invites';
      case AdminWorkspaceView.students:
        return 'Students';
      case AdminWorkspaceView.staff:
        return 'Staff';
      case AdminWorkspaceView.counselors:
        return 'Counselors';
      case AdminWorkspaceView.allInvites:
        return 'All Invites';
    }
  }

  String get workspaceSubtitle {
    switch (this) {
      case AdminWorkspaceView.overview:
        return 'Control join code, invites, members, and institution operations from one persistent workspace.';
      case AdminWorkspaceView.members:
        return 'Review the full institution roster, inspect records, and take lifecycle actions from a single table.';
      case AdminWorkspaceView.pendingInvites:
        return 'Track outstanding invite demand and revoke pending role access when needed.';
      case AdminWorkspaceView.students:
        return 'Monitor the student population linked to this institution and inspect individual records quickly.';
      case AdminWorkspaceView.staff:
        return 'Keep staff membership visible and maintain operational access with fewer clicks.';
      case AdminWorkspaceView.counselors:
        return 'Watch counselor roster health and move quickly into detail records when changes are needed.';
      case AdminWorkspaceView.allInvites:
        return 'Review every invite state across the institution, not just the ones still pending.';
    }
  }
}

class InstitutionAdminScreen extends ConsumerStatefulWidget {
  const InstitutionAdminScreen({super.key});

  @override
  ConsumerState<InstitutionAdminScreen> createState() =>
      _InstitutionAdminScreenState();
}

class _InstitutionAdminScreenState
    extends ConsumerState<InstitutionAdminScreen> {
  static const _kenyaPrefix = '+254';
  final _phoneController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _tableKey = GlobalKey();

  UserRole _inviteRole = UserRole.counselor;
  AdminWorkspaceView _activeView = AdminWorkspaceView.overview;
  String _activeFilter = 'all';
  bool _isSubmitting = false;
  bool _isRegeneratingJoinCode = false;
  String? _inlineError;
  int _rowsPerPage = PaginatedDataTable.defaultRowsPerPage;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _phoneController.text = _kenyaPrefix;
    _phoneController.addListener(_enforceInvitePhonePrefix);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_enforceInvitePhonePrefix);
    _phoneController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _enforceInvitePhonePrefix() {
    final normalized = _normalizeKenyaPhoneInput(_phoneController.text);
    if (_phoneController.text == normalized) {
      return;
    }
    _phoneController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  String _normalizeKenyaPhoneInput(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('254')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '$_kenyaPrefix$digits';
  }

  bool _isValidKenyaPhone(String value) {
    return RegExp(r'^\+254\d{9}$').hasMatch(value);
  }

  void _showInlineError(String message) {
    setState(() => _inlineError = message);
  }

  Future<void> _createInvite() async {
    final phone = _phoneController.text.trim();
    if (!_isValidKenyaPhone(phone)) {
      _showInlineError(
        'Enter a valid phone number after +254 (example: +254712345678).',
      );
      return;
    }

    setState(() => _inlineError = null);
    setState(() => _isSubmitting = true);
    try {
      final inviteDraft = await ref
          .read(institutionRepositoryProvider)
          .createRoleInvite(inviteePhoneNumber: phone, role: _inviteRole);
      if (!mounted) {
        return;
      }
      _phoneController.text = _kenyaPrefix;
      _inlineError = null;
      await _showInviteDeliveryDialog(inviteDraft);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showInlineError(
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _copyTextWithFeedback({
    required String text,
    required String successMessage,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  Future<void> _openWhatsAppDraft(String deepLink) async {
    final uri = Uri.tryParse(deepLink);
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid WhatsApp link.')));
      return;
    }
    final launched = await launchUrl(uri);
    if (!mounted) {
      return;
    }
    if (launched) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open WhatsApp. Copy message and send manually.',
        ),
      ),
    );
  }

  Future<void> _showInviteDeliveryDialog(InAppInviteDraft inviteDraft) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Created'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${inviteDraft.invitedName} was invited as ${inviteDraft.role.label}.',
              ),
              const SizedBox(height: 6),
              Text('Phone: ${inviteDraft.inviteePhoneE164}'),
              const SizedBox(height: 10),
              SelectableText('Institution code: ${inviteDraft.joinCode}'),
              const SizedBox(height: 6),
              const Text('Invite is highlighted in-app for the target user.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _copyTextWithFeedback(
              text: inviteDraft.joinCode,
              successMessage: 'Institution code copied.',
            ),
            child: const Text('Copy Code'),
          ),
          TextButton(
            onPressed: () => _copyTextWithFeedback(
              text: inviteDraft.whatsAppMessage,
              successMessage: 'WhatsApp message copied.',
            ),
            child: const Text('Copy WhatsApp Message'),
          ),
          TextButton(
            onPressed: () => _openWhatsAppDraft(inviteDraft.whatsAppDeepLink),
            child: const Text('Open WhatsApp'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _regenerateJoinCode({bool silent = false}) async {
    if (_isRegeneratingJoinCode) {
      return;
    }
    setState(() => _isRegeneratingJoinCode = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .regenerateJoinCodeForCurrentAdminInstitution();
      if (!mounted || silent) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Join code regenerated.')));
    } catch (error) {
      if (!mounted || silent) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRegeneratingJoinCode = false);
      }
    }
  }

  void _setWorkspace(AdminWorkspaceView view) {
    setState(() {
      _activeView = view;
      _activeFilter = 'all';
      _searchController.clear();
      _sortColumnIndex = null;
      _sortAscending = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _tableKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.05,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _setSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  int _compareString(String a, String b) {
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  List<_WorkspaceEntry> _sortEntries(List<_WorkspaceEntry> entries) {
    if (_sortColumnIndex == null) {
      return entries;
    }

    final columnIndex = _sortColumnIndex!;
    entries.sort((a, b) {
      late final int comparison;
      switch (columnIndex) {
        case 0:
          comparison = _compareString(a.primary, b.primary);
          break;
        case 1:
          comparison = _compareString(a.secondary, b.secondary);
          break;
        case 2:
          comparison = _compareString(a.type, b.type);
          break;
        case 3:
          comparison = _compareString(a.status, b.status);
          break;
        case 4:
          comparison = _compareString(a.source, b.source);
          break;
        case 5:
          final aMs = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bMs = b.createdAt?.millisecondsSinceEpoch ?? 0;
          comparison = aMs.compareTo(bMs);
          break;
        default:
          comparison = 0;
      }
      return _sortAscending ? comparison : -comparison;
    });

    return entries;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  bool _isPendingInviteData(Map<String, dynamic> data) {
    final status = (data['status'] as String?) ?? '';
    if (status != 'pending') {
      return false;
    }
    final expiresAt = _parseDate(data['expiresAt']);
    if (expiresAt == null) {
      return true;
    }
    return expiresAt.toUtc().isAfter(DateTime.now().toUtc());
  }

  String _inviteStatusLabel(Map<String, dynamic> data) {
    final status = (data['status'] as String?) ?? 'pending';
    if (status != 'pending') {
      return status;
    }
    final expiresAt = _parseDate(data['expiresAt']);
    if (expiresAt != null &&
        !expiresAt.toUtc().isAfter(DateTime.now().toUtc())) {
      return 'expired';
    }
    return status;
  }

  Future<void> _revokeInvite(_WorkspaceEntry entry) async {
    final inviteId = entry.recordId;
    if (inviteId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite id missing.')));
      return;
    }
    try {
      await ref
          .read(institutionRepositoryProvider)
          .revokeInvite(inviteId: inviteId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite revoked.')));
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

  Future<void> _updateMemberStatus(
    _WorkspaceEntry entry,
    String nextStatus,
  ) async {
    final userId = (entry.raw['userId'] as String?) ?? '';
    if (userId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Member user id missing.')));
      return;
    }
    try {
      await ref
          .read(institutionRepositoryProvider)
          .updateMemberLifecycleStatus(
            memberUserId: userId,
            status: nextStatus,
            reason: 'admin_dashboard',
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Member marked as $nextStatus.')));
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

  List<_WorkspaceEntry> _entriesForView({
    required AdminWorkspaceView view,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> members,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> invites,
  }) {
    List<_WorkspaceEntry> memberEntries({String? role}) {
      return members
          .where((doc) {
            if (role == null) {
              return true;
            }
            return (doc.data()['role'] as String? ?? '') == role;
          })
          .map((doc) {
            final data = doc.data();
            final userId = (data['userId'] as String?) ?? '--';
            final roleName = (data['role'] as String?) ?? 'member';
            final displayName =
                (data['userName'] as String?) ??
                (data['name'] as String?) ??
                'Member ${userId.length > 6 ? userId.substring(0, 6) : userId}';
            final secondary =
                (data['email'] as String?) ??
                (data['userId'] as String?) ??
                '--';
            return _WorkspaceEntry(
              recordId: doc.id,
              primary: displayName,
              secondary: secondary,
              type: roleName,
              status: (data['status'] as String?) ?? 'active',
              source: 'member',
              createdAt: _parseDate(data['joinedAt'] ?? data['createdAt']),
              raw: data,
            );
          })
          .toList(growable: false);
    }

    List<_WorkspaceEntry> inviteEntries({bool pendingOnly = false}) {
      return invites
          .where((doc) {
            if (!pendingOnly) {
              return true;
            }
            return _isPendingInviteData(doc.data());
          })
          .map((doc) {
            final data = doc.data();
            final invitedName =
                ((data['invitedName'] as String?) ?? '').trim().isNotEmpty
                ? ((data['invitedName'] as String?) ?? '').trim()
                : ((data['inviteeUid'] as String?) ?? '--');
            final invitePhone = ((data['inviteePhoneE164'] as String?) ?? '')
                .trim();
            final inviteEmail = ((data['invitedEmail'] as String?) ?? '')
                .trim();
            return _WorkspaceEntry(
              recordId: doc.id,
              primary: invitedName,
              secondary: invitePhone.isNotEmpty
                  ? invitePhone
                  : (inviteEmail.isNotEmpty ? inviteEmail : '--'),
              type: (data['intendedRole'] as String?) ?? 'invite',
              status: _inviteStatusLabel(data),
              source: 'invite',
              createdAt: _parseDate(data['createdAt']),
              raw: data,
            );
          })
          .toList(growable: false);
    }

    switch (view) {
      case AdminWorkspaceView.members:
        return memberEntries();
      case AdminWorkspaceView.students:
        return memberEntries(role: 'student');
      case AdminWorkspaceView.staff:
        return memberEntries(role: 'staff');
      case AdminWorkspaceView.counselors:
        return memberEntries(role: 'counselor');
      case AdminWorkspaceView.pendingInvites:
        return inviteEntries(pendingOnly: true);
      case AdminWorkspaceView.allInvites:
        return inviteEntries();
      case AdminWorkspaceView.overview:
        return const [];
    }
  }

  void _openEntryDetails(_WorkspaceEntry entry) {
    final currentUid = ref.read(firebaseAuthProvider).currentUser?.uid;
    final isOwnAdminMember =
        entry.source == 'member' &&
        entry.type == UserRole.institutionAdmin.name &&
        ((entry.raw['userId'] as String?) ?? '') == (currentUid ?? '');
    final canRevokeInvite =
        entry.source == 'invite' && entry.status == 'pending';
    final canActivateMember =
        entry.source == 'member' &&
        entry.type != UserRole.institutionAdmin.name &&
        entry.status != 'active' &&
        entry.status != 'removed' &&
        !isOwnAdminMember;
    final canSuspendMember =
        entry.source == 'member' &&
        entry.type != UserRole.institutionAdmin.name &&
        entry.status == 'active' &&
        !isOwnAdminMember;
    final canRemoveMember =
        entry.source == 'member' &&
        entry.type != UserRole.institutionAdmin.name &&
        entry.status != 'removed' &&
        !isOwnAdminMember;

    showDialog<String>(
      context: context,
      builder: (context) {
        final keys = entry.raw.keys.toList()..sort();
        return AlertDialog(
          title: Text(entry.primary),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailLine(label: 'Secondary', value: entry.secondary),
                  _DetailLine(label: 'Type', value: entry.type),
                  _DetailLine(label: 'Status', value: entry.status),
                  _DetailLine(label: 'Source', value: entry.source),
                  _DetailLine(
                    label: 'Created',
                    value: entry.createdAt == null
                        ? '--'
                        : entry.createdAt!.toLocal().toString(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Raw record',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  ...keys.map(
                    (key) => _DetailLine(
                      label: key,
                      value: (entry.raw[key] ?? '--').toString(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (canRevokeInvite)
              TextButton(
                onPressed: () => Navigator.of(context).pop('revoke_invite'),
                child: const Text('Revoke Invite'),
              ),
            if (canActivateMember)
              TextButton(
                onPressed: () => Navigator.of(context).pop('activate_member'),
                child: const Text('Activate'),
              ),
            if (canSuspendMember)
              TextButton(
                onPressed: () => Navigator.of(context).pop('suspend_member'),
                child: const Text('Suspend'),
              ),
            if (canRemoveMember)
              TextButton(
                onPressed: () => Navigator.of(context).pop('remove_member'),
                child: const Text('Remove'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ).then((action) {
      if (action == null) {
        return;
      }
      switch (action) {
        case 'revoke_invite':
          _revokeInvite(entry);
          break;
        case 'activate_member':
          _updateMemberStatus(entry, 'active');
          break;
        case 'suspend_member':
          _updateMemberStatus(entry, 'suspended');
          break;
        case 'remove_member':
          _updateMemberStatus(entry, 'removed');
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final firestore = ref.watch(firestoreProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: _AdminWorkspaceBackdrop(
        child: SafeArea(
          child: profileAsync.when(
            data: (profile) {
              if (profile == null) {
                return const Center(
                  child: _MessageCard(message: 'Profile not found.'),
                );
              }

              final institutionId = profile.institutionId ?? '';
              if (profile.role != UserRole.institutionAdmin ||
                  institutionId.isEmpty) {
                return const Center(
                  child: _MessageCard(
                    message:
                        'This page is available only for institution admins.',
                  ),
                );
              }

              final institutionRef = firestore
                  .collection('institutions')
                  .doc(institutionId);
              final membersQuery = firestore
                  .collection('institution_members')
                  .where('institutionId', isEqualTo: institutionId)
                  .limit(1000);
              final invitesQuery = firestore
                  .collection('user_invites')
                  .where('institutionId', isEqualTo: institutionId)
                  .limit(1000);

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: membersQuery.snapshots(),
                builder: (context, membersSnapshot) {
                  final members = membersSnapshot.data?.docs ?? const [];
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: invitesQuery.snapshots(),
                    builder: (context, invitesSnapshot) {
                      final invites = invitesSnapshot.data?.docs ?? const [];

                      final studentCount = members
                          .where(
                            (doc) =>
                                (doc.data()['role'] as String?) == 'student',
                          )
                          .length;
                      final staffCount = members
                          .where(
                            (doc) => (doc.data()['role'] as String?) == 'staff',
                          )
                          .length;
                      final counselorCount = members
                          .where(
                            (doc) =>
                                (doc.data()['role'] as String?) == 'counselor',
                          )
                          .length;
                      final pendingCount = invites
                          .where((doc) => _isPendingInviteData(doc.data()))
                          .length;

                      final stats = [
                        _DashboardStat(
                          label: AdminWorkspaceView.members.navLabel,
                          value: '${members.length}',
                          icon: Icons.groups_rounded,
                          view: AdminWorkspaceView.members,
                        ),
                        _DashboardStat(
                          label: AdminWorkspaceView.pendingInvites.navLabel,
                          value: '$pendingCount',
                          icon: Icons.mark_email_unread_rounded,
                          view: AdminWorkspaceView.pendingInvites,
                        ),
                        _DashboardStat(
                          label: AdminWorkspaceView.students.navLabel,
                          value: '$studentCount',
                          icon: Icons.school_rounded,
                          view: AdminWorkspaceView.students,
                        ),
                        _DashboardStat(
                          label: AdminWorkspaceView.staff.navLabel,
                          value: '$staffCount',
                          icon: Icons.badge_rounded,
                          view: AdminWorkspaceView.staff,
                        ),
                        _DashboardStat(
                          label: AdminWorkspaceView.counselors.navLabel,
                          value: '$counselorCount',
                          icon: Icons.health_and_safety_rounded,
                          view: AdminWorkspaceView.counselors,
                        ),
                      ];

                      final allEntries = _entriesForView(
                        view: _activeView,
                        members: members,
                        invites: invites,
                      );
                      final normalizedSearch = _searchController.text
                          .trim()
                          .toLowerCase();
                      final filteredEntries = allEntries
                          .where((entry) {
                            final passesFilter =
                                _activeFilter == 'all' ||
                                entry.type == _activeFilter ||
                                entry.status == _activeFilter ||
                                entry.source == _activeFilter;
                            if (!passesFilter) {
                              return false;
                            }
                            if (normalizedSearch.isEmpty) {
                              return true;
                            }
                            final target =
                                '${entry.primary} ${entry.secondary} ${entry.type} ${entry.status} ${entry.source}'
                                    .toLowerCase();
                            return target.contains(normalizedSearch);
                          })
                          .toList(growable: false);
                      final sortedEntries = _sortEntries(
                        List<_WorkspaceEntry>.from(filteredEntries),
                      );

                      final filterOptions = <String>{'all'};
                      for (final entry in allEntries) {
                        filterOptions.add(entry.type);
                        filterOptions.add(entry.status);
                        filterOptions.add(entry.source);
                      }

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 980;
                          final title = _activeView.workspaceTitle;
                          final subtitle = _activeView.workspaceSubtitle;
                          final institutionName =
                              profile.institutionName ?? 'Institution';
                          final adminName = profile.name.isNotEmpty
                              ? profile.name
                              : profile.email;
                          void onLogout() =>
                              confirmAndLogout(context: context, ref: ref);

                          final content = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _HeroCard(
                                institutionRef: institutionRef,
                                fallbackName: institutionName,
                                isRegeneratingJoinCode: _isRegeneratingJoinCode,
                                onRegenerateJoinCode: () =>
                                    _regenerateJoinCode(),
                              ),
                              const SizedBox(height: 14),
                              _StatsRow(
                                stats: stats,
                                activeView: _activeView,
                                onTap: _setWorkspace,
                              ),
                              const SizedBox(height: 14),
                              _WorkspacePanel(
                                key: _tableKey,
                                activeView: _activeView,
                                searchController: _searchController,
                                onSearchChanged: (_) => setState(() {}),
                                activeFilter: _activeFilter,
                                onFilterChanged: (value) {
                                  setState(() => _activeFilter = value);
                                },
                                filterOptions: filterOptions.toList()..sort(),
                                entries: sortedEntries,
                                rowsPerPage: _rowsPerPage,
                                onRowsPerPageChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() => _rowsPerPage = value);
                                },
                                onRowTap: _openEntryDetails,
                                sortColumnIndex: _sortColumnIndex,
                                sortAscending: _sortAscending,
                                onSort: _setSort,
                              ),
                              const SizedBox(height: 14),
                              LayoutBuilder(
                                builder: (context, innerConstraints) {
                                  if (innerConstraints.maxWidth < 860) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _InviteComposer(
                                          phoneController: _phoneController,
                                          selectedRole: _inviteRole,
                                          isSubmitting: _isSubmitting,
                                          errorMessage: _inlineError,
                                          onRoleChanged: (role) {
                                            setState(() => _inviteRole = role);
                                          },
                                          onCreateInvite: _createInvite,
                                        ),
                                        const SizedBox(height: 14),
                                        _CounselorWorkflowSettingsCard(
                                          institutionRef: institutionRef,
                                          onChanged: (settings) {
                                            return ref
                                                .read(
                                                  institutionRepositoryProvider,
                                                )
                                                .updateCounselorWorkflowSettings(
                                                  settings: settings,
                                                );
                                          },
                                        ),
                                      ],
                                    );
                                  }

                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: _InviteComposer(
                                          phoneController: _phoneController,
                                          selectedRole: _inviteRole,
                                          isSubmitting: _isSubmitting,
                                          errorMessage: _inlineError,
                                          onRoleChanged: (role) {
                                            setState(() => _inviteRole = role);
                                          },
                                          onCreateInvite: _createInvite,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          children: [
                                            _CounselorWorkflowSettingsCard(
                                              institutionRef: institutionRef,
                                              onChanged: (settings) {
                                                return ref
                                                    .read(
                                                      institutionRepositoryProvider,
                                                    )
                                                    .updateCounselorWorkflowSettings(
                                                      settings: settings,
                                                    );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );

                          if (!isWide) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                14,
                                14,
                                20,
                              ),
                              child: Column(
                                children: [
                                  _AdminWorkspaceHeader(
                                    title: title,
                                    subtitle: subtitle,
                                    institutionName: institutionName,
                                    adminName: adminName,
                                    desktop: false,
                                    onLogout: onLogout,
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    height: 52,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _adminNavViews.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(width: 10),
                                      itemBuilder: (context, index) {
                                        final view = _adminNavViews[index];
                                        return _AdminMobileNavChip(
                                          view: view,
                                          selected: _activeView == view,
                                          onTap: () => _setWorkspace(view),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      controller: _scrollController,
                                      child: content,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 272,
                                  child: _AdminSidebarShell(
                                    institutionName: institutionName,
                                    adminName: adminName,
                                    activeView: _activeView,
                                    onViewSelected: _setWorkspace,
                                    onLogout: onLogout,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFF8F8F3,
                                      ).withValues(alpha: 0.92),
                                      borderRadius: BorderRadius.circular(32),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x120F172A),
                                          blurRadius: 30,
                                          offset: Offset(0, 18),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        _AdminWorkspaceHeader(
                                          title: title,
                                          subtitle: subtitle,
                                          institutionName: institutionName,
                                          adminName: adminName,
                                          desktop: true,
                                          onLogout: onLogout,
                                        ),
                                        Expanded(
                                          child: SingleChildScrollView(
                                            controller: _scrollController,
                                            padding: const EdgeInsets.fromLTRB(
                                              28,
                                              10,
                                              28,
                                              28,
                                            ),
                                            child: content,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: _MessageCard(message: error.toString())),
          ),
        ),
      ),
    );
  }
}

class _AdminWorkspaceBackdrop extends StatelessWidget {
  const _AdminWorkspaceBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEDF6FB), Color(0xFFEAF4F2), Color(0xFFF7F8F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          const _AdminBlurOrb(
            size: 300,
            color: Color(0x5538BDF8),
            offset: Offset(-90, 50),
          ),
          const _AdminBlurOrb(
            size: 250,
            color: Color(0x5514B8A6),
            offset: Offset(1180, 240),
          ),
          const _AdminBlurOrb(
            size: 220,
            color: Color(0x55A7F3D0),
            offset: Offset(140, 760),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _AdminBlurOrb extends StatelessWidget {
  const _AdminBlurOrb({
    required this.size,
    required this.color,
    required this.offset,
  });

  final double size;
  final Color color;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 120, spreadRadius: 10),
          ],
        ),
      ),
    );
  }
}

class _AdminWorkspaceHeader extends StatelessWidget {
  const _AdminWorkspaceHeader({
    required this.title,
    required this.subtitle,
    required this.institutionName,
    required this.adminName,
    required this.desktop,
    required this.onLogout,
  });

  final String title;
  final String subtitle;
  final String institutionName;
  final String adminName;
  final bool desktop;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        desktop ? 28 : 18,
        desktop ? 24 : 18,
        desktop ? 28 : 18,
        18,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: desktop ? 0 : 0.9),
        border: desktop
            ? const Border(bottom: BorderSide(color: Color(0xFFE6EAF0)))
            : null,
        borderRadius: desktop ? null : BorderRadius.circular(28),
        boxShadow: desktop
            ? null
            : const [
                BoxShadow(
                  color: Color(0x120F172A),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFF081A30),
                        fontSize: desktop ? 31 : 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: desktop ? -1.2 : -0.9,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: desktop ? 1 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6A7C93),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: desktop ? 20 : 18,
                backgroundColor: const Color(0xFF0E9B90),
                child: Text(
                  _adminInitials(adminName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
                tooltip: 'Logout',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      adminName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF081A30),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      institutionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7B8CA4),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminSidebarShell extends StatelessWidget {
  const _AdminSidebarShell({
    required this.institutionName,
    required this.adminName,
    required this.activeView,
    required this.onViewSelected,
    required this.onLogout,
  });

  final String institutionName;
  final String adminName;
  final AdminWorkspaceView activeView;
  final ValueChanged<AdminWorkspaceView> onViewSelected;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C2233),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180F172A),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.domain_add_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MindNest',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      Text(
                        institutionName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7FA0B5),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            _SideNav(activeView: activeView, onViewSelected: onViewSelected),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF132D41),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF1F415A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ADMIN STATUS',
                    style: TextStyle(
                      color: Color(0xFF7FA0B5),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Institution sync active',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    adminName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFBBD0DC),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onLogout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF325068)),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Logout'),
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

class _AdminMobileNavChip extends StatelessWidget {
  const _AdminMobileNavChip({
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final AdminWorkspaceView view;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF0E9B90)
                : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0E9B90)
                  : const Color(0xFFD8E3EC),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                view.navIcon,
                color: selected ? Colors.white : const Color(0xFF4D647B),
              ),
              const SizedBox(width: 8),
              Text(
                view.navLabel,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF0C2233),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.activeView, required this.onViewSelected});

  final AdminWorkspaceView activeView;
  final ValueChanged<AdminWorkspaceView> onViewSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _adminNavViews
          .map(
            (view) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SideNavButton(
                view: view,
                selected: activeView == view,
                onTap: () => onViewSelected(view),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

const List<AdminWorkspaceView> _adminNavViews = [
  AdminWorkspaceView.overview,
  AdminWorkspaceView.members,
  AdminWorkspaceView.pendingInvites,
  AdminWorkspaceView.students,
  AdminWorkspaceView.staff,
  AdminWorkspaceView.counselors,
  AdminWorkspaceView.allInvites,
];

String _adminInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return 'AD';
  }
  if (parts.length == 1) {
    return parts.first
        .substring(0, parts.first.length >= 2 ? 2 : 1)
        .toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class _SideNavButton extends StatelessWidget {
  const _SideNavButton({
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final AdminWorkspaceView view;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF243746) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? const Color(0xFF314A5C) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                view.navIcon,
                size: 18,
                color: selected
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF89A3B6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  view.navLabel,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFD3DEE7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatefulWidget {
  const _HeroCard({
    required this.institutionRef,
    required this.fallbackName,
    required this.isRegeneratingJoinCode,
    required this.onRegenerateJoinCode,
  });

  final DocumentReference<Map<String, dynamic>> institutionRef;
  final String fallbackName;
  final bool isRegeneratingJoinCode;
  final VoidCallback onRegenerateJoinCode;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  String? _autoRefreshedCode;

  DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) {
      return '--';
    }
    final local = value.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: widget.institutionRef.snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final name = (data?['name'] as String?) ?? widget.fallbackName;
          final joinCode = (data?['joinCode'] as String?) ?? '--';
          final usageCount =
              (data?['joinCodeUsageCount'] as num?)?.toInt() ?? 0;
          final expiresAt = _parseTimestamp(data?['joinCodeExpiresAt']);
          final now = DateTime.now();
          final isExpired =
              expiresAt == null || !expiresAt.toUtc().isAfter(now.toUtc());
          if (isExpired &&
              !widget.isRegeneratingJoinCode &&
              _autoRefreshedCode != joinCode &&
              joinCode != '--') {
            _autoRefreshedCode = joinCode;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              widget.onRegenerateJoinCode();
            });
          }

          return Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0D9488).withValues(alpha: 0.22),
                  const Color(0xFF38BDF8).withValues(alpha: 0.16),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF052E2B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage invites, onboarding intake, and institution setup from one workspace.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF1F5B57),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x220F172A)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 560;
                      final copyButton = FilledButton.tonalIcon(
                        onPressed: widget.isRegeneratingJoinCode
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: joinCode),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Join code copied.'),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy'),
                      );
                      final regenerateButton = OutlinedButton.icon(
                        onPressed: widget.isRegeneratingJoinCode
                            ? null
                            : widget.onRegenerateJoinCode,
                        icon: widget.isRegeneratingJoinCode
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.autorenew_rounded, size: 18),
                        label: const Text('Regenerate'),
                      );

                      if (isCompact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.groups_rounded,
                                  color: Color(0xFF0D9488),
                                ),
                                const SizedBox(width: 8),
                                const Text('Join code'),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    joinCode,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          letterSpacing: 2,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [copyButton, regenerateButton],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          const Icon(
                            Icons.groups_rounded,
                            color: Color(0xFF0D9488),
                          ),
                          const SizedBox(width: 8),
                          const Text('Join code'),
                          const SizedBox(width: 10),
                          Text(
                            joinCode,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const Spacer(),
                          copyButton,
                          const SizedBox(width: 8),
                          regenerateButton,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaPill(
                      icon: Icons.timer_outlined,
                      label: isExpired
                          ? 'Expired'
                          : 'Expires ${_formatTimestamp(expiresAt)}',
                    ),
                    _MetaPill(
                      icon: Icons.group_add_rounded,
                      label: 'Usage $usageCount / 50',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x220F172A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF0F766E)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStat {
  const _DashboardStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.view,
  });

  final String label;
  final String value;
  final IconData icon;
  final AdminWorkspaceView view;
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.stats,
    required this.activeView,
    required this.onTap,
  });

  final List<_DashboardStat> stats;
  final AdminWorkspaceView activeView;
  final ValueChanged<AdminWorkspaceView> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 5
            : constraints.maxWidth >= 760
            ? 3
            : 2;
        final totalSpacing = 12.0 * (columns - 1);
        final width = (constraints.maxWidth - totalSpacing) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: stats
              .map(
                (stat) => SizedBox(
                  width: width,
                  child: _StatTile(
                    stat: stat,
                    selected: activeView == stat.view,
                    onTap: () => onTap(stat.view),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.stat,
    required this.selected,
    required this.onTap,
  });

  final _DashboardStat stat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF0E9B90)
                        : const Color(0xFFE8F6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    stat.icon,
                    color: selected ? Colors.white : const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stat.value,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800, height: 1),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        stat.label,
                        style: const TextStyle(
                          color: Color(0xFF5E728D),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceEntry {
  const _WorkspaceEntry({
    required this.recordId,
    required this.primary,
    required this.secondary,
    required this.type,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.raw,
  });

  final String recordId;
  final String primary;
  final String secondary;
  final String type;
  final String status;
  final String source;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;
}

class _WorkspacePanel extends StatelessWidget {
  const _WorkspacePanel({
    super.key,
    required this.activeView,
    required this.searchController,
    required this.onSearchChanged,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.filterOptions,
    required this.entries,
    required this.rowsPerPage,
    required this.onRowsPerPageChanged,
    required this.onRowTap,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
  });

  final AdminWorkspaceView activeView;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;
  final List<String> filterOptions;
  final List<_WorkspaceEntry> entries;
  final int rowsPerPage;
  final ValueChanged<int?> onRowsPerPageChanged;
  final ValueChanged<_WorkspaceEntry> onRowTap;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending) onSort;

  @override
  Widget build(BuildContext context) {
    final isOverview = activeView == AdminWorkspaceView.overview;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDE6EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isOverview)
              const _OverviewEmptyState()
            else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5FAFF),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFD8E6F2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.manage_search_rounded,
                          color: Color(0xFF0284C7),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Search and narrow this dataset before opening records.',
                            style: TextStyle(
                              color: Color(0xFF415A77),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 620;
                        final searchField = TextField(
                          controller: searchController,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Search',
                          ),
                          onChanged: onSearchChanged,
                        );
                        final filterField = DropdownButtonFormField<String>(
                          initialValue: activeFilter,
                          isExpanded: true,
                          items: filterOptions
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value == 'all' ? 'All' : value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          selectedItemBuilder: (context) => filterOptions
                              .map(
                                (value) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    value == 'all' ? 'All' : value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) {
                              onFilterChanged(value);
                            }
                          },
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.filter_alt_rounded),
                          ),
                        );

                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              searchField,
                              const SizedBox(height: 12),
                              filterField,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: searchField,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: filterField,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TableHintPill(
                          icon: Icons.ads_click_rounded,
                          label: 'Row tap enabled',
                        ),
                        _TableHintPill(
                          icon: Icons.hub_rounded,
                          label: 'Raw record detail',
                        ),
                        _TableHintPill(
                          icon: Icons.swap_vert_rounded,
                          label: 'Sortable columns',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (entries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFD8E6F2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search_off_rounded, color: Color(0xFF2563EB)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No records match the current control state. Adjust the search terms or reset the filter to reopen the table feed.',
                          style: TextStyle(
                            color: Color(0xFF5E728D),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                _PaginatedWorkspaceTable(
                  entries: entries,
                  rowsPerPage: rowsPerPage,
                  onRowsPerPageChanged: onRowsPerPageChanged,
                  onRowTap: onRowTap,
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: sortAscending,
                  onSort: onSort,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OverviewEmptyState extends StatelessWidget {
  const _OverviewEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8E6F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Overview Workspace',
            style: TextStyle(
              color: Color(0xFF081A30),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'This panel turns stats into action. Open a live table, filter the dataset, and inspect detailed records without leaving the workspace shell.',
            style: TextStyle(color: Color(0xFF5E728D), height: 1.45),
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MiniHint(
                icon: Icons.touch_app_rounded,
                title: 'Jump into records',
                text: 'Tap any stat card to open its live table immediately.',
              ),
              _MiniHint(
                icon: Icons.manage_search_rounded,
                title: 'Narrow the table',
                text:
                    'Use search and filters to reach the exact admin target faster.',
              ),
              _MiniHint(
                icon: Icons.table_rows_rounded,
                title: 'Inspect raw details',
                text:
                    'Open rows to review the underlying data without leaving the dashboard.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniHint extends StatelessWidget {
  const _MiniHint({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF0284C7), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF16324F),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF415A77),
                    fontWeight: FontWeight.w600,
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
}

class _PaginatedWorkspaceTable extends StatelessWidget {
  const _PaginatedWorkspaceTable({
    required this.entries,
    required this.rowsPerPage,
    required this.onRowsPerPageChanged,
    required this.onRowTap,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
  });

  final List<_WorkspaceEntry> entries;
  final int rowsPerPage;
  final ValueChanged<int?> onRowsPerPageChanged;
  final ValueChanged<_WorkspaceEntry> onRowTap;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending) onSort;

  @override
  Widget build(BuildContext context) {
    final source = _WorkspaceDataSource(entries: entries, onRowTap: onRowTap);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FBFF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.dataset_linked_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Records',
                        style: TextStyle(
                          color: Color(0xFF081A30),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Sortable rows, tap-to-open details, and export-ready admin data.',
                        style: TextStyle(
                          color: Color(0xFF5E728D),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFD9E4F0)),
                  ),
                  child: Text(
                    '${entries.length} visible',
                    style: const TextStyle(
                      color: Color(0xFF415A77),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(
              cardTheme: const CardThemeData(
                color: Colors.transparent,
                elevation: 0,
              ),
              dividerColor: const Color(0xFFE2EAF3),
              textTheme: Theme.of(context).textTheme.apply(
                bodyColor: const Color(0xFF16324F),
                displayColor: const Color(0xFF16324F),
              ),
            ),
            child: PaginatedDataTable(
              header: const Text(
                'Records',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF5FAFF)),
              rowsPerPage: rowsPerPage,
              availableRowsPerPage: const [5, 10, 20, 50],
              onRowsPerPageChanged: onRowsPerPageChanged,
              sortColumnIndex: sortColumnIndex,
              sortAscending: sortAscending,
              columnSpacing: 24,
              horizontalMargin: 20,
              columns: [
                DataColumn(
                  label: const Text('Name'),
                  onSort: (columnIndex, ascending) =>
                      onSort(columnIndex, ascending),
                ),
                DataColumn(
                  label: const Text('Contact / ID'),
                  onSort: (columnIndex, ascending) =>
                      onSort(columnIndex, ascending),
                ),
                DataColumn(
                  label: const Text('Type'),
                  onSort: (columnIndex, ascending) =>
                      onSort(columnIndex, ascending),
                ),
                DataColumn(
                  label: const Text('Status'),
                  onSort: (columnIndex, ascending) =>
                      onSort(columnIndex, ascending),
                ),
                DataColumn(
                  label: const Text('Source'),
                  onSort: (columnIndex, ascending) =>
                      onSort(columnIndex, ascending),
                ),
                DataColumn(
                  label: const Text('Created'),
                  onSort: (columnIndex, ascending) =>
                      onSort(columnIndex, ascending),
                ),
              ],
              source: source,
              showFirstLastButtons: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceDataSource extends DataTableSource {
  _WorkspaceDataSource({required this.entries, required this.onRowTap});

  final List<_WorkspaceEntry> entries;
  final ValueChanged<_WorkspaceEntry> onRowTap;

  String _formatDate(DateTime? dt) {
    if (dt == null) {
      return '--';
    }
    final date = dt.toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _metaPill(
    String label, {
    Color background = const Color(0xFFF4F7FB),
    Color foreground = const Color(0xFF415A77),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  DataRow? getRow(int index) {
    if (index >= entries.length) {
      return null;
    }
    final entry = entries[index];
    final status = entry.status.toLowerCase();
    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Text(
            entry.primary,
            style: const TextStyle(
              color: Color(0xFF081A30),
              fontWeight: FontWeight.w700,
            ),
          ),
          onTap: () => onRowTap(entry),
        ),
        DataCell(
          Text(
            entry.secondary,
            style: const TextStyle(
              color: Color(0xFF5E728D),
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => onRowTap(entry),
        ),
        DataCell(_metaPill(entry.type), onTap: () => onRowTap(entry)),
        DataCell(
          _metaPill(
            entry.status,
            background: status == 'active' || status == 'accepted'
                ? const Color(0xFFE8FBF5)
                : status == 'pending'
                ? const Color(0xFFFFF4DE)
                : const Color(0xFFF3F4F6),
            foreground: status == 'active' || status == 'accepted'
                ? const Color(0xFF0E9B90)
                : status == 'pending'
                ? const Color(0xFFB45309)
                : const Color(0xFF475569),
          ),
          onTap: () => onRowTap(entry),
        ),
        DataCell(_metaPill(entry.source), onTap: () => onRowTap(entry)),
        DataCell(
          Text(
            _formatDate(entry.createdAt),
            style: const TextStyle(
              color: Color(0xFF5E728D),
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => onRowTap(entry),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => entries.length;

  @override
  int get selectedRowCount => 0;
}

class _InviteComposer extends StatelessWidget {
  const _InviteComposer({
    required this.phoneController,
    required this.selectedRole,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onRoleChanged,
    required this.onCreateInvite,
  });

  final TextEditingController phoneController;
  final UserRole selectedRole;
  final bool isSubmitting;
  final String? errorMessage;
  final ValueChanged<UserRole> onRoleChanged;
  final VoidCallback onCreateInvite;

  String _roleSummary(UserRole role) {
    switch (role) {
      case UserRole.student:
        return 'Student invite uses enrollment via institution code.';
      case UserRole.staff:
        return 'Staff invite grants operational team access.';
      case UserRole.counselor:
        return 'Counselor invite enters approval into the care workspace.';
      default:
        return 'Select a role and send the in-app invite.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDE6EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0D1B2A),
                    Color(0xFF173D63),
                    Color(0xFF1AA9A1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x24FFFFFF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x50FFFFFF)),
                    ),
                    child: const Text(
                      'INVITE FLOW',
                      style: TextStyle(
                        color: Color(0xFFFDE68A),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Create Invite',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose a target role, enter the phone number, and send a highlighted in-app institution invite from the same control surface.',
                    style: TextStyle(
                      color: Color(0xFFD7E5F0),
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InviteMetaPill(
                        icon: Icons.flash_on_rounded,
                        label: 'In-app delivery',
                      ),
                      _InviteMetaPill(
                        icon: Icons.verified_user_rounded,
                        label: 'One-time use',
                      ),
                      _InviteMetaPill(
                        icon: Icons.password_rounded,
                        label: 'Code-protected onboarding',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5FAFF),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFD8E6F2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: Color(0xFF0284C7),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Role and delivery target',
                          style: TextStyle(
                            color: Color(0xFF16324F),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFFD8E6F2),
                          ),
                        ),
                        child: Text(
                          selectedRole.label,
                          style: const TextStyle(
                            color: Color(0xFF0C2233),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _roleSummary(selectedRole),
                    style: TextStyle(
                      color: Color(0xFF5E728D),
                      fontSize: 12.8,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CompactRoleChoice(
                        label: 'Student',
                        icon: Icons.school_rounded,
                        selected: selectedRole == UserRole.student,
                        onTap: () => onRoleChanged(UserRole.student),
                      ),
                      _CompactRoleChoice(
                        label: 'Staff',
                        icon: Icons.badge_rounded,
                        selected: selectedRole == UserRole.staff,
                        onTap: () => onRoleChanged(UserRole.staff),
                      ),
                      _CompactRoleChoice(
                        label: 'Counselor',
                        icon: Icons.health_and_safety_rounded,
                        selected: selectedRole == UserRole.counselor,
                        onTap: () => onRoleChanged(UserRole.counselor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (errorMessage != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Color(0xFFDC2626)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage ?? '',
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: '+254712345678',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0E9B90), Color(0xFF18A89D)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3372ECDC),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: isSubmitting ? null : onCreateInvite,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: Icon(
                  isSubmitting
                      ? Icons.hourglass_top_rounded
                      : Icons.send_rounded,
                ),
                label: Text(
                  isSubmitting ? 'Creating invite...' : 'Create Invite',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactRoleChoice extends StatelessWidget {
  const _CompactRoleChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0E9B90) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFF0E9B90) : const Color(0xFFD8E6F2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : const Color(0xFF0284C7),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF16324F),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CounselorWorkflowSettingsCard extends StatefulWidget {
  const _CounselorWorkflowSettingsCard({
    required this.institutionRef,
    required this.onChanged,
  });

  final DocumentReference<Map<String, dynamic>> institutionRef;
  final Future<void> Function(CounselorWorkflowSettings settings) onChanged;

  @override
  State<_CounselorWorkflowSettingsCard> createState() =>
      _CounselorWorkflowSettingsCardState();
}

class _CounselorWorkflowSettingsCardState
    extends State<_CounselorWorkflowSettingsCard> {
  bool _savingDirectory = false;
  bool _savingReassignment = false;

  Future<void> _toggleDirectory(CounselorWorkflowSettings current) async {
    if (_savingDirectory) {
      return;
    }
    setState(() => _savingDirectory = true);
    try {
      await widget.onChanged(
        CounselorWorkflowSettings(
          directoryEnabled: !current.directoryEnabled,
          reassignmentEnabled: current.reassignmentEnabled,
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !current.directoryEnabled
                ? 'Internal counselor directory enabled.'
                : 'Internal counselor directory disabled.',
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
    } finally {
      if (mounted) {
        setState(() => _savingDirectory = false);
      }
    }
  }

  Future<void> _toggleReassignment(CounselorWorkflowSettings current) async {
    if (_savingReassignment) {
      return;
    }
    setState(() => _savingReassignment = true);
    try {
      await widget.onChanged(
        CounselorWorkflowSettings(
          directoryEnabled: current.directoryEnabled,
          reassignmentEnabled: !current.reassignmentEnabled,
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !current.reassignmentEnabled
                ? 'Counselor reassignment requests enabled.'
                : 'Counselor reassignment requests disabled.',
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
    } finally {
      if (mounted) {
        setState(() => _savingReassignment = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.institutionRef.snapshots(),
      builder: (context, snapshot) {
        final settings = CounselorWorkflowSettings.fromInstitutionData(
          snapshot.data?.data(),
        );
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDDE6EE)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ModuleEyebrow(
                label: 'COUNSELOR OPERATIONS',
                color: Color(0xFF0E9B90),
                background: Color(0xFFE7FAF8),
                border: Color(0xFFB8F0E9),
              ),
              const SizedBox(height: 12),
              const Text(
                'Counselor collaboration controls',
                style: TextStyle(
                  color: Color(0xFF081A30),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Turn on the internal counselor directory and counselor-to-counselor reassignment requests only if this institution wants that collaboration model.',
                style: TextStyle(
                  color: Color(0xFF6A7C93),
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              _SettingToggleTile(
                title: 'Allow counselors to view internal counselor directory',
                subtitle:
                    'Counselors in this institution can browse a limited internal directory with professional identity details only.',
                value: settings.directoryEnabled,
                busy: _savingDirectory,
                onTap: () => _toggleDirectory(settings),
              ),
              const SizedBox(height: 12),
              _SettingToggleTile(
                title: 'Allow counselor-to-counselor reassignment requests',
                subtitle:
                    'Assigned counselors can open controlled replacement requests, collect interested counselors, and finalize the handoff only after patient approval.',
                value: settings.reassignmentEnabled,
                busy: _savingReassignment,
                onTap: () => _toggleReassignment(settings),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingToggleTile extends StatelessWidget {
  const _SettingToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: busy ? null : onTap,
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFE),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: value ? const Color(0xFF93E2D8) : const Color(0xFFD9E5EF),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF0C2233),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6A7C93),
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Switch.adaptive(value: value, onChanged: (_) => onTap()),
          ],
        ),
      ),
    );
  }
}

class _ModuleEyebrow extends StatelessWidget {
  const _ModuleEyebrow({
    required this.label,
    required this.color,
    required this.background,
    required this.border,
  });

  final String label;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _TableHintPill extends StatelessWidget {
  const _TableHintPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E6F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF0284C7)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF415A77),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteMetaPill extends StatelessWidget {
  const _InviteMetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x24FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x40FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFFDE68A)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
