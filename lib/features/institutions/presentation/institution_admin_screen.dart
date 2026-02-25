import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

enum AdminWorkspaceView {
  overview,
  members,
  pendingInvites,
  students,
  staff,
  counselors,
  allInvites,
}

class InstitutionAdminScreen extends ConsumerStatefulWidget {
  const InstitutionAdminScreen({super.key});

  @override
  ConsumerState<InstitutionAdminScreen> createState() =>
      _InstitutionAdminScreenState();
}

class _InstitutionAdminScreenState
    extends ConsumerState<InstitutionAdminScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _searchController = TextEditingController();

  UserRole _inviteRole = UserRole.counselor;
  AdminWorkspaceView _activeView = AdminWorkspaceView.overview;
  String _activeFilter = 'all';
  bool _isSubmitting = false;
  bool _isRegeneratingJoinCode = false;
  int _rowsPerPage = PaginatedDataTable.defaultRowsPerPage;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createInvite() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.length < 2 || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid name and email.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .createRoleInvite(
            invitedName: name,
            invitedEmail: email,
            role: _inviteRole,
          );
      if (!mounted) {
        return;
      }
      _nameController.clear();
      _emailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_inviteRole.label} invite created.')),
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
        setState(() => _isSubmitting = false);
      }
    }
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

  String _escapeCsv(String value) {
    final shouldQuote =
        value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!shouldQuote) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  Future<void> _exportCsv(List<_WorkspaceEntry> entries) async {
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No rows to export in this view.')),
      );
      return;
    }

    final lines = <String>[
      'name,contact_or_id,type,status,source,created_at',
      ...entries.map((entry) {
        final created = entry.createdAt?.toIso8601String() ?? '';
        return [
          _escapeCsv(entry.primary),
          _escapeCsv(entry.secondary),
          _escapeCsv(entry.type),
          _escapeCsv(entry.status),
          _escapeCsv(entry.source),
          _escapeCsv(created),
        ].join(',');
      }),
    ];

    final csv = lines.join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'CSV exported (${entries.length} rows). A copy is in your clipboard.',
        ),
      ),
    );
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
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
              primary: displayName,
              secondary: secondary,
              type: roleName,
              status: 'active',
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
            return (doc.data()['status'] as String? ?? '') == 'pending';
          })
          .map((doc) {
            final data = doc.data();
            return _WorkspaceEntry(
              primary: (data['invitedName'] as String?) ?? '--',
              secondary: (data['invitedEmail'] as String?) ?? '--',
              type: (data['intendedRole'] as String?) ?? 'invite',
              status: (data['status'] as String?) ?? 'pending',
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
    showDialog<void>(
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final firestore = ref.watch(firestoreProvider);

    return MindNestShell(
      maxWidth: 1200,
      appBar: AppBar(
        title: const Text('Institution Admin Dashboard'),
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
      child: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const _MessageCard(message: 'Profile not found.');
          }

          final institutionId = profile.institutionId ?? '';
          if (profile.role != UserRole.institutionAdmin ||
              institutionId.isEmpty) {
            return const _MessageCard(
              message: 'This page is available only for institution admins.',
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
                        (doc) => (doc.data()['role'] as String?) == 'student',
                      )
                      .length;
                  final staffCount = members
                      .where(
                        (doc) => (doc.data()['role'] as String?) == 'staff',
                      )
                      .length;
                  final counselorCount = members
                      .where(
                        (doc) => (doc.data()['role'] as String?) == 'counselor',
                      )
                      .length;
                  final pendingCount = invites
                      .where(
                        (doc) => (doc.data()['status'] as String?) == 'pending',
                      )
                      .length;

                  final stats = [
                    _DashboardStat(
                      label: 'Members',
                      value: '${members.length}',
                      icon: Icons.groups_rounded,
                      view: AdminWorkspaceView.members,
                    ),
                    _DashboardStat(
                      label: 'Pending Invites',
                      value: '$pendingCount',
                      icon: Icons.mark_email_unread_rounded,
                      view: AdminWorkspaceView.pendingInvites,
                    ),
                    _DashboardStat(
                      label: 'Students',
                      value: '$studentCount',
                      icon: Icons.school_rounded,
                      view: AdminWorkspaceView.students,
                    ),
                    _DashboardStat(
                      label: 'Staff',
                      value: '$staffCount',
                      icon: Icons.badge_rounded,
                      view: AdminWorkspaceView.staff,
                    ),
                    _DashboardStat(
                      label: 'Counselors',
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

                      final content = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeroCard(
                            institutionRef: institutionRef,
                            fallbackName:
                                profile.institutionName ?? 'Institution',
                            isRegeneratingJoinCode: _isRegeneratingJoinCode,
                            onRegenerateJoinCode: () => _regenerateJoinCode(),
                          ),
                          const SizedBox(height: 14),
                          _StatsRow(
                            stats: stats,
                            activeView: _activeView,
                            onTap: _setWorkspace,
                          ),
                          const SizedBox(height: 14),
                          _WorkspacePanel(
                            activeView: _activeView,
                            onViewChange: _setWorkspace,
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
                            onExportCsv: _exportCsv,
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
                                      nameController: _nameController,
                                      emailController: _emailController,
                                      selectedRole: _inviteRole,
                                      isSubmitting: _isSubmitting,
                                      onRoleChanged: (role) {
                                        setState(() => _inviteRole = role);
                                      },
                                      onCreateInvite: _createInvite,
                                    ),
                                    const SizedBox(height: 14),
                                    _ActionComponents(
                                      onOpenInvites: () {
                                        _setWorkspace(
                                          AdminWorkspaceView.allInvites,
                                        );
                                      },
                                      onOpenMembers: () {
                                        _setWorkspace(
                                          AdminWorkspaceView.members,
                                        );
                                      },
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _InviteComposer(
                                      nameController: _nameController,
                                      emailController: _emailController,
                                      selectedRole: _inviteRole,
                                      isSubmitting: _isSubmitting,
                                      onRoleChanged: (role) {
                                        setState(() => _inviteRole = role);
                                      },
                                      onCreateInvite: _createInvite,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    flex: 4,
                                    child: _ActionComponents(
                                      onOpenInvites: () {
                                        _setWorkspace(
                                          AdminWorkspaceView.allInvites,
                                        );
                                      },
                                      onOpenMembers: () {
                                        _setWorkspace(
                                          AdminWorkspaceView.members,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      );

                      if (!isWide) {
                        return content;
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 240,
                            child: _SideNav(
                              activeView: _activeView,
                              onViewSelected: _setWorkspace,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: content),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MessageCard(message: error.toString()),
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
    const items = [
      _NavItem(
        'Overview',
        Icons.dashboard_rounded,
        AdminWorkspaceView.overview,
      ),
      _NavItem('Members', Icons.groups_rounded, AdminWorkspaceView.members),
      _NavItem(
        'Pending Invites',
        Icons.mark_email_unread_rounded,
        AdminWorkspaceView.pendingInvites,
      ),
      _NavItem('Students', Icons.school_rounded, AdminWorkspaceView.students),
      _NavItem('Staff', Icons.badge_rounded, AdminWorkspaceView.staff),
      _NavItem(
        'Counselors',
        Icons.health_and_safety_rounded,
        AdminWorkspaceView.counselors,
      ),
      _NavItem(
        'All Invites',
        Icons.send_rounded,
        AdminWorkspaceView.allInvites,
      ),
    ];

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Navigation',
              style: TextStyle(
                color: Color(0xFF60738D),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            ...items.map(
              (item) => _SideNavButton(
                item: item,
                selected: activeView == item.view,
                onTap: () => onViewSelected(item.view),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.view);

  final String label;
  final IconData icon;
  final AdminWorkspaceView view;
}

class _SideNavButton extends StatelessWidget {
  const _SideNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF0E9B90) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xFF0E9B90)
                    : const Color(0xFFD9E4F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: selected ? Colors.white : const Color(0xFF415A77),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF415A77),
                      fontWeight: FontWeight.w700,
                    ),
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
                  child: Row(
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
                      FilledButton.tonalIcon(
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
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
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
                      ),
                    ],
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
    required this.primary,
    required this.secondary,
    required this.type,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.raw,
  });

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
    required this.activeView,
    required this.onViewChange,
    required this.searchController,
    required this.onSearchChanged,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.filterOptions,
    required this.entries,
    required this.rowsPerPage,
    required this.onRowsPerPageChanged,
    required this.onRowTap,
    required this.onExportCsv,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
  });

  final AdminWorkspaceView activeView;
  final ValueChanged<AdminWorkspaceView> onViewChange;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;
  final List<String> filterOptions;
  final List<_WorkspaceEntry> entries;
  final int rowsPerPage;
  final ValueChanged<int?> onRowsPerPageChanged;
  final ValueChanged<_WorkspaceEntry> onRowTap;
  final ValueChanged<List<_WorkspaceEntry>> onExportCsv;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending) onSort;

  String _titleForView(AdminWorkspaceView view) {
    switch (view) {
      case AdminWorkspaceView.overview:
        return 'Overview Workspace';
      case AdminWorkspaceView.members:
        return 'Members Table';
      case AdminWorkspaceView.pendingInvites:
        return 'Pending Invites Table';
      case AdminWorkspaceView.students:
        return 'Students Table';
      case AdminWorkspaceView.staff:
        return 'Staff Table';
      case AdminWorkspaceView.counselors:
        return 'Counselors Table';
      case AdminWorkspaceView.allInvites:
        return 'All Invites Table';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _titleForView(activeView),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (activeView != AdminWorkspaceView.overview)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: entries.isEmpty
                            ? null
                            : () => onExportCsv(entries),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Export CSV'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            onViewChange(AdminWorkspaceView.overview),
                        icon: const Icon(Icons.dashboard_rounded, size: 18),
                        label: const Text('Back to overview'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (activeView == AdminWorkspaceView.overview)
              const _OverviewEmptyState()
            else ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Search by name, email, role, status, source',
                      ),
                      onChanged: onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: activeFilter,
                      items: filterOptions
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value == 'all' ? 'All filters' : value,
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
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD9E4F0)),
                  ),
                  child: const Text(
                    'No records match your current search/filter.',
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
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: const [
        _MiniHint(
          icon: Icons.touch_app_rounded,
          text: 'Tap any stat card to open its live table.',
        ),
        _MiniHint(
          icon: Icons.manage_search_rounded,
          text: 'Use search + filters for fast admin operations.',
        ),
        _MiniHint(
          icon: Icons.table_rows_rounded,
          text: 'Rows are clickable to open detailed records.',
        ),
      ],
    );
  }
}

class _MiniHint extends StatelessWidget {
  const _MiniHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0284C7), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
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
    return Theme(
      data: Theme.of(context).copyWith(
        cardTheme: const CardThemeData(color: Colors.transparent, elevation: 0),
      ),
      child: PaginatedDataTable(
        header: const Text('Records'),
        rowsPerPage: rowsPerPage,
        availableRowsPerPage: const [5, 10, 20, 50],
        onRowsPerPageChanged: onRowsPerPageChanged,
        sortColumnIndex: sortColumnIndex,
        sortAscending: sortAscending,
        columns: [
          DataColumn(
            label: const Text('Name'),
            onSort: (columnIndex, ascending) => onSort(columnIndex, ascending),
          ),
          DataColumn(
            label: const Text('Contact / ID'),
            onSort: (columnIndex, ascending) => onSort(columnIndex, ascending),
          ),
          DataColumn(
            label: const Text('Type'),
            onSort: (columnIndex, ascending) => onSort(columnIndex, ascending),
          ),
          DataColumn(
            label: const Text('Status'),
            onSort: (columnIndex, ascending) => onSort(columnIndex, ascending),
          ),
          DataColumn(
            label: const Text('Source'),
            onSort: (columnIndex, ascending) => onSort(columnIndex, ascending),
          ),
          DataColumn(
            label: const Text('Created'),
            onSort: (columnIndex, ascending) => onSort(columnIndex, ascending),
          ),
        ],
        source: source,
        showFirstLastButtons: true,
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

  @override
  DataRow? getRow(int index) {
    if (index >= entries.length) {
      return null;
    }
    final entry = entries[index];
    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Text(entry.primary), onTap: () => onRowTap(entry)),
        DataCell(Text(entry.secondary), onTap: () => onRowTap(entry)),
        DataCell(Text(entry.type), onTap: () => onRowTap(entry)),
        DataCell(Text(entry.status), onTap: () => onRowTap(entry)),
        DataCell(Text(entry.source), onTap: () => onRowTap(entry)),
        DataCell(
          Text(_formatDate(entry.createdAt)),
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
    required this.nameController,
    required this.emailController,
    required this.selectedRole,
    required this.isSubmitting,
    required this.onRoleChanged,
    required this.onCreateInvite,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final UserRole selectedRole;
  final bool isSubmitting;
  final ValueChanged<UserRole> onRoleChanged;
  final VoidCallback onCreateInvite;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create Invite',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text('Choose role, then send invite by email.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _RoleChip(
                  label: 'Student',
                  selected: selectedRole == UserRole.student,
                  onTap: () => onRoleChanged(UserRole.student),
                ),
                _RoleChip(
                  label: 'Staff',
                  selected: selectedRole == UserRole.staff,
                  onTap: () => onRoleChanged(UserRole.staff),
                ),
                _RoleChip(
                  label: 'Counselor',
                  selected: selectedRole == UserRole.counselor,
                  onTap: () => onRoleChanged(UserRole.counselor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Invitee full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Invitee email',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: isSubmitting ? null : onCreateInvite,
              icon: const Icon(Icons.send_rounded),
              label: Text(
                isSubmitting ? 'Creating invite...' : 'Create invite',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF0E9B90),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF415A77),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ActionComponents extends StatelessWidget {
  const _ActionComponents({
    required this.onOpenInvites,
    required this.onOpenMembers,
  });

  final VoidCallback onOpenInvites;
  final VoidCallback onOpenMembers;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quick Components',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _ClickableComponentTile(
              icon: Icons.table_rows_rounded,
              title: 'Open Members Table',
              subtitle: 'Navigate directly to full member records.',
              onTap: onOpenMembers,
            ),
            const SizedBox(height: 10),
            _ClickableComponentTile(
              icon: Icons.mail_outline_rounded,
              title: 'Open Invites Table',
              subtitle: 'View all invite statuses and role targets.',
              onTap: onOpenInvites,
            ),
            const SizedBox(height: 10),
            _ClickableComponentTile(
              icon: Icons.event_note_rounded,
              title: 'Appointments Overview',
              subtitle: 'Placeholder module for counselor scheduling.',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Appointments module coming soon.'),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            _ClickableComponentTile(
              icon: Icons.library_books_rounded,
              title: 'Resource Library',
              subtitle: 'Placeholder module for institution resources.',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Resource module coming soon.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ClickableComponentTile extends StatelessWidget {
  const _ClickableComponentTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD9E4F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFF0284C7)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF5E728D),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF8FA0B6)),
            ],
          ),
        ),
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
