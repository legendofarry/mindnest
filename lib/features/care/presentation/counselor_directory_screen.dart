import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';

enum _CounselorSort { earliestAvailable, ratingHigh, experienceHigh }

class CounselorDirectoryScreen extends ConsumerStatefulWidget {
  const CounselorDirectoryScreen({super.key});

  @override
  ConsumerState<CounselorDirectoryScreen> createState() =>
      _CounselorDirectoryScreenState();
}

class _CounselorDirectoryScreenState
    extends ConsumerState<CounselorDirectoryScreen> {
  final _searchController = TextEditingController();
  _CounselorSort _sort = _CounselorSort.earliestAvailable;
  String _specializationFilter = 'all';
  String _languageFilter = 'all';
  String _modeFilter = 'all';
  int _refreshTick = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _sortLabel(_CounselorSort sort) {
    switch (sort) {
      case _CounselorSort.earliestAvailable:
        return 'Earliest available';
      case _CounselorSort.ratingHigh:
        return 'Highest rated';
      case _CounselorSort.experienceHigh:
        return 'Most experience';
    }
  }

  String _formatSlot(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        title: const Text('Counselor Directory'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => setState(() => _refreshTick++),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Find a Counselor',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search by name, specialization, language...',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DropdownButtonHideUnderline(
                        child: DropdownButton<_CounselorSort>(
                          value: _sort,
                          items: _CounselorSort.values
                              .map(
                                (sort) => DropdownMenuItem(
                                  value: sort,
                                  child: Text(_sortLabel(sort)),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() => _sort = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (institutionId.isEmpty)
            const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Join an institution first to view counselors.'),
              ),
            )
          else
            StreamBuilder<List<CounselorProfile>>(
              key: ValueKey(_refreshTick),
              stream: ref
                  .read(careRepositoryProvider)
                  .watchCounselors(institutionId: institutionId),
              builder: (context, counselorSnapshot) {
                if (counselorSnapshot.hasError) {
                  return GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            counselorSnapshot.error.toString().replaceFirst(
                              'Exception: ',
                              '',
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () => setState(() => _refreshTick++),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final counselors = counselorSnapshot.data ?? const [];
                if (counselorSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    counselors.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                return StreamBuilder<List<AvailabilitySlot>>(
                  stream: ref
                      .read(careRepositoryProvider)
                      .watchInstitutionPublicAvailability(
                        institutionId: institutionId,
                      ),
                  builder: (context, availabilitySnapshot) {
                    final availability = availabilitySnapshot.data ?? const [];
                    final earliestSlotByCounselor = <String, DateTime>{};
                    for (final slot in availability) {
                      final existing =
                          earliestSlotByCounselor[slot.counselorId];
                      if (existing == null || slot.startAt.isBefore(existing)) {
                        earliestSlotByCounselor[slot.counselorId] =
                            slot.startAt;
                      }
                    }

                    final specializations = <String>{'all'};
                    final languages = <String>{'all'};
                    final modes = <String>{'all'};
                    for (final counselor in counselors) {
                      specializations.add(counselor.specialization);
                      modes.add(counselor.sessionMode);
                      for (final lang in counselor.languages) {
                        languages.add(lang);
                      }
                    }

                    if (!specializations.contains(_specializationFilter)) {
                      _specializationFilter = 'all';
                    }
                    if (!languages.contains(_languageFilter)) {
                      _languageFilter = 'all';
                    }
                    if (!modes.contains(_modeFilter)) {
                      _modeFilter = 'all';
                    }

                    final query = _searchController.text.trim().toLowerCase();
                    final filtered = counselors
                        .where((entry) {
                          final matchesSearch =
                              query.isEmpty ||
                              ('${entry.displayName} ${entry.specialization} ${entry.languages.join(' ')}'
                                      .toLowerCase())
                                  .contains(query);
                          final matchesSpecialization =
                              _specializationFilter == 'all' ||
                              entry.specialization == _specializationFilter;
                          final matchesLanguage =
                              _languageFilter == 'all' ||
                              entry.languages.contains(_languageFilter);
                          final matchesMode =
                              _modeFilter == 'all' ||
                              entry.sessionMode == _modeFilter;
                          return matchesSearch &&
                              matchesSpecialization &&
                              matchesLanguage &&
                              matchesMode;
                        })
                        .toList(growable: false);

                    filtered.sort((a, b) {
                      switch (_sort) {
                        case _CounselorSort.earliestAvailable:
                          final aSlot = earliestSlotByCounselor[a.id];
                          final bSlot = earliestSlotByCounselor[b.id];
                          if (aSlot == null && bSlot == null) {
                            return a.displayName.compareTo(b.displayName);
                          }
                          if (aSlot == null) {
                            return 1;
                          }
                          if (bSlot == null) {
                            return -1;
                          }
                          return aSlot.compareTo(bSlot);
                        case _CounselorSort.ratingHigh:
                          return b.ratingAverage.compareTo(a.ratingAverage);
                        case _CounselorSort.experienceHigh:
                          return b.yearsExperience.compareTo(a.yearsExperience);
                      }
                    });

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _StringFilterDropdown(
                                  label: 'Specialization',
                                  value: _specializationFilter,
                                  options: specializations.toList()..sort(),
                                  onChanged: (value) => setState(
                                    () => _specializationFilter = value,
                                  ),
                                ),
                                _StringFilterDropdown(
                                  label: 'Language',
                                  value: _languageFilter,
                                  options: languages.toList()..sort(),
                                  onChanged: (value) =>
                                      setState(() => _languageFilter = value),
                                ),
                                _StringFilterDropdown(
                                  label: 'Mode',
                                  value: _modeFilter,
                                  options: modes.toList()..sort(),
                                  onChanged: (value) =>
                                      setState(() => _modeFilter = value),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _specializationFilter = 'all';
                                      _languageFilter = 'all';
                                      _modeFilter = 'all';
                                    });
                                  },
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (filtered.isEmpty)
                          (query.isNotEmpty ||
                                  _specializationFilter != 'all' ||
                                  _languageFilter != 'all' ||
                                  _modeFilter != 'all')
                              ? const GlassCard(
                                  child: Padding(
                                    padding: EdgeInsets.all(18),
                                    child: Text(
                                      'No counselors match your filters. Try broadening your search.',
                                    ),
                                  ),
                                )
                              : _PendingCounselorFallback(
                                  institutionId: institutionId,
                                )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: filtered
                                .map(
                                  (counselor) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _CounselorCard(
                                      counselor: counselor,
                                      earliestAvailable:
                                          earliestSlotByCounselor[counselor.id],
                                      formatSlot: _formatSlot,
                                      onTap: () {
                                        context.push(
                                          '${AppRoute.counselorProfile}?counselorId=${counselor.id}',
                                        );
                                      },
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StringFilterDropdown extends StatelessWidget {
  const _StringFilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        items: options
            .map(
              (option) => DropdownMenuItem(
                value: option,
                child: Text(option == 'all' ? '$label: All' : option),
              ),
            )
            .toList(growable: false),
        onChanged: (changed) {
          if (changed != null) {
            onChanged(changed);
          }
        },
      ),
    );
  }
}

class _CounselorCard extends StatelessWidget {
  const _CounselorCard({
    required this.counselor,
    required this.onTap,
    required this.formatSlot,
    this.earliestAvailable,
  });

  final CounselorProfile counselor;
  final VoidCallback onTap;
  final DateTime? earliestAvailable;
  final String Function(DateTime value) formatSlot;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.health_and_safety_rounded,
                    color: Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        counselor.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${counselor.title} - ${counselor.specialization}',
                        style: const TextStyle(color: Color(0xFF5E728D)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${counselor.yearsExperience} yrs - ${counselor.sessionMode}',
                        style: const TextStyle(color: Color(0xFF5E728D)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        earliestAvailable == null
                            ? 'No open slots yet'
                            : 'Earliest: ${formatSlot(earliestAvailable!)}',
                        style: const TextStyle(
                          color: Color(0xFF0E9B90),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFF59E0B),
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          counselor.ratingAverage.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    Text(
                      '${counselor.ratingCount} ratings',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingCounselorFallback extends ConsumerWidget {
  const _PendingCounselorFallback({required this.institutionId});

  final String institutionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firestore = ref.watch(firestoreProvider);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('institution_members')
          .where('institutionId', isEqualTo: institutionId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                snapshot.error.toString().replaceFirst('Exception: ', ''),
              ),
            ),
          );
        }

        final counselorMembers = (snapshot.data?.docs ?? const [])
            .where(
              (doc) =>
                  (doc.data()['role'] as String?) == UserRole.counselor.name,
            )
            .toList(growable: false);

        if (counselorMembers.isEmpty) {
          return const GlassCard(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'No counselors are available yet in your institution.',
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: counselorMembers
              .map((doc) {
                final data = doc.data();
                final userId = (data['userId'] as String?) ?? doc.id;
                final userName =
                    (data['userName'] as String?) ??
                    (data['name'] as String?) ??
                    'Counselor ${userId.length > 6 ? userId.substring(0, 6) : userId}';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          context.push(
                            '${AppRoute.counselorProfile}?counselorId=$userId',
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F6FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.health_and_safety_rounded,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      userName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Profile setup in progress',
                                      style: TextStyle(
                                        color: Color(0xFF5E728D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }
}
