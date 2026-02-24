import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/back_to_home_button.dart';
import 'package:mindnest/core/ui/desktop_section_shell.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:mindnest/features/care/models/counselor_public_rating.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final canAccessLive =
        profile != null &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.counselor);

    return MindNestShell(
      maxWidth: isDesktop ? 1240 : 980,
      backgroundMode: MindNestBackgroundMode.homeStyle,
      appBar: AppBar(
        title: Text(
          'Counselor Directory',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF071937),
            fontSize: 20,
            letterSpacing: -0.4,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackToHomeButton(),
        actions: [
          IconButton(
            onPressed: () => setState(() => _refreshTick++),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: DesktopSectionBody(
        isDesktop: isDesktop,
        hasInstitution: institutionId.isNotEmpty,
        canAccessLive: canAccessLive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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

                  return StreamBuilder<List<CounselorPublicRating>>(
                    stream: ref
                        .read(careRepositoryProvider)
                        .watchInstitutionCounselorPublicRatings(
                          institutionId: institutionId,
                        ),
                    builder: (context, publicRatingsSnapshot) {
                      final publicRatings =
                          publicRatingsSnapshot.data ?? const [];
                      final ratingSumByCounselor = <String, int>{};
                      final ratingCountByCounselor = <String, int>{};
                      for (final rating in publicRatings) {
                        final counselorId = rating.counselorId;
                        ratingSumByCounselor[counselorId] =
                            (ratingSumByCounselor[counselorId] ?? 0) +
                            rating.rating;
                        ratingCountByCounselor[counselorId] =
                            (ratingCountByCounselor[counselorId] ?? 0) + 1;
                      }

                      return StreamBuilder<List<AvailabilitySlot>>(
                        stream: ref
                            .read(careRepositoryProvider)
                            .watchInstitutionPublicAvailability(
                              institutionId: institutionId,
                            ),
                        builder: (context, availabilitySnapshot) {
                          final availability =
                              availabilitySnapshot.data ?? const [];
                          final earliestSlotByCounselor = <String, DateTime>{};
                          for (final slot in availability) {
                            final existing =
                                earliestSlotByCounselor[slot.counselorId];
                            if (existing == null ||
                                slot.startAt.isBefore(existing)) {
                              earliestSlotByCounselor[slot.counselorId] =
                                  slot.startAt;
                            }
                          }

                          double ratingAverageFor(CounselorProfile counselor) {
                            final count = ratingCountByCounselor[counselor.id];
                            if (count == null || count == 0) {
                              return counselor.ratingAverage;
                            }
                            final total =
                                ratingSumByCounselor[counselor.id] ?? 0;
                            return total / count;
                          }

                          int ratingCountFor(CounselorProfile counselor) {
                            return ratingCountByCounselor[counselor.id] ??
                                counselor.ratingCount;
                          }

                          final specializations = <String>{'all'};
                          for (final counselor in counselors) {
                            specializations.add(counselor.specialization);
                          }

                          if (!specializations.contains(
                            _specializationFilter,
                          )) {
                            _specializationFilter = 'all';
                          }

                          final query = _searchController.text
                              .trim()
                              .toLowerCase();
                          final filtered = counselors
                              .where((entry) {
                                final matchesSearch =
                                    query.isEmpty ||
                                    ('${entry.displayName} ${entry.specialization} ${entry.languages.join(' ')}'
                                            .toLowerCase())
                                        .contains(query);
                                final matchesSpecialization =
                                    _specializationFilter == 'all' ||
                                    entry.specialization ==
                                        _specializationFilter;
                                return matchesSearch && matchesSpecialization;
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
                                return ratingAverageFor(
                                  b,
                                ).compareTo(ratingAverageFor(a));
                              case _CounselorSort.experienceHigh:
                                return b.yearsExperience.compareTo(
                                  a.yearsExperience,
                                );
                            }
                          });

                          final hasActiveFilters =
                              query.isNotEmpty ||
                              _specializationFilter != 'all';
                          final specializationOptions = specializations.toList()
                            ..sort();

                          return _CounselorDirectoryTable(
                            rows: filtered
                                .map(
                                  (counselor) => _CounselorTableRowData(
                                    counselorId: counselor.id,
                                    displayName: counselor.displayName,
                                    title: counselor.title,
                                    specialization: counselor.specialization,
                                    sessionMode: counselor.sessionMode,
                                    languages: counselor.languages,
                                    yearsExperience: counselor.yearsExperience,
                                    ratingAverage: ratingAverageFor(counselor),
                                    ratingCount: ratingCountFor(counselor),
                                    earliestAvailable:
                                        earliestSlotByCounselor[counselor.id],
                                  ),
                                )
                                .toList(growable: false),
                            formatSlot: _formatSlot,
                            onOpenProfile: (counselorId) {
                              context.push(
                                '${AppRoute.counselorProfile}?counselorId=$counselorId',
                              );
                            },
                            searchController: _searchController,
                            onSearchChanged: (_) => setState(() {}),
                            sort: _sort,
                            sortLabelBuilder: _sortLabel,
                            onSortChanged: (value) =>
                                setState(() => _sort = value),
                            specializationFilter: _specializationFilter,
                            specializationOptions: specializationOptions,
                            onSpecializationChanged: (value) =>
                                setState(() => _specializationFilter = value),
                            onResetFilters: () {
                              setState(() {
                                _specializationFilter = 'all';
                                _sort = _CounselorSort.earliestAvailable;
                                _searchController.clear();
                              });
                            },
                            hasActiveFilters: hasActiveFilters,
                            noDataWidget: hasActiveFilters
                                ? const Text(
                                    'No counselors match your filters. Try broadening your search.',
                                  )
                                : _PendingCounselorFallback(
                                    institutionId: institutionId,
                                  ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _StringFilterDropdown extends StatelessWidget {
  const _StringFilterDropdown({
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x66FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0DFEE)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          menuMaxHeight: 320,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.arrow_drop_down_rounded),
          selectedItemBuilder: (context) {
            return options
                .map(
                  (option) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: const Color(0xFF5E728D)),
                      const SizedBox(width: 6),
                      Text(option == 'all' ? 'All' : option),
                    ],
                  ),
                )
                .toList(growable: false);
          },
          items: options
              .map(
                (option) => DropdownMenuItem(
                  value: option,
                  child: Text(option == 'all' ? 'All' : option),
                ),
              )
              .toList(growable: false),
          onChanged: (changed) {
            if (changed != null) {
              onChanged(changed);
            }
          },
        ),
      ),
    );
  }
}

class _SortFilterDropdown extends StatelessWidget {
  const _SortFilterDropdown({
    required this.value,
    required this.sortLabelBuilder,
    required this.onChanged,
  });

  final _CounselorSort value;
  final String Function(_CounselorSort sort) sortLabelBuilder;
  final ValueChanged<_CounselorSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x66FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0DFEE)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_CounselorSort>(
          value: value,
          menuMaxHeight: 320,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.arrow_drop_down_rounded),
          selectedItemBuilder: (context) {
            return _CounselorSort.values
                .map(
                  (sortValue) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: Color(0xFF5E728D),
                      ),
                      const SizedBox(width: 6),
                      Text(sortLabelBuilder(sortValue)),
                    ],
                  ),
                )
                .toList(growable: false);
          },
          items: _CounselorSort.values
              .map(
                (sortValue) => DropdownMenuItem(
                  value: sortValue,
                  child: Text(sortLabelBuilder(sortValue)),
                ),
              )
              .toList(growable: false),
          onChanged: (changed) {
            if (changed != null) {
              onChanged(changed);
            }
          },
        ),
      ),
    );
  }
}

class _CounselorTableRowData {
  const _CounselorTableRowData({
    required this.counselorId,
    required this.displayName,
    required this.title,
    required this.specialization,
    required this.sessionMode,
    required this.languages,
    required this.yearsExperience,
    required this.ratingAverage,
    required this.ratingCount,
    required this.earliestAvailable,
  });

  final String counselorId;
  final String displayName;
  final String title;
  final String specialization;
  final String sessionMode;
  final List<String> languages;
  final int yearsExperience;
  final double ratingAverage;
  final int ratingCount;
  final DateTime? earliestAvailable;
}

class _CounselorDirectoryTable extends StatelessWidget {
  const _CounselorDirectoryTable({
    required this.rows,
    required this.formatSlot,
    required this.onOpenProfile,
    required this.searchController,
    required this.onSearchChanged,
    required this.sort,
    required this.sortLabelBuilder,
    required this.onSortChanged,
    required this.specializationFilter,
    required this.specializationOptions,
    required this.onSpecializationChanged,
    required this.onResetFilters,
    required this.hasActiveFilters,
    required this.noDataWidget,
  });

  final List<_CounselorTableRowData> rows;
  final String Function(DateTime value) formatSlot;
  final ValueChanged<String> onOpenProfile;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final _CounselorSort sort;
  final String Function(_CounselorSort sort) sortLabelBuilder;
  final ValueChanged<_CounselorSort> onSortChanged;
  final String specializationFilter;
  final List<String> specializationOptions;
  final ValueChanged<String> onSpecializationChanged;
  final VoidCallback onResetFilters;
  final bool hasActiveFilters;
  final Widget noDataWidget;

  static const _headerTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: Color(0xFF5B6E87),
    letterSpacing: 0.2,
  );

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.table_chart_rounded,
                  size: 18,
                  color: Color(0xFF0E9B90),
                ),
                const SizedBox(width: 8),
                Text(
                  'Counselors (${rows.length})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
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
                    _SortFilterDropdown(
                      value: sort,
                      sortLabelBuilder: sortLabelBuilder,
                      onChanged: onSortChanged,
                    ),
                    _StringFilterDropdown(
                      icon: Icons.psychology_alt_rounded,
                      value: specializationFilter,
                      options: specializationOptions,
                      onChanged: onSpecializationChanged,
                    ),
                    OutlinedButton.icon(
                      onPressed: onResetFilters,
                      icon: const Icon(Icons.restart_alt_rounded, size: 16),
                      label: const Text('Reset'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0x22A5B4C8)),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: hasActiveFilters
                  ? DefaultTextStyle(
                      style: const TextStyle(
                        color: Color(0xFF4A607C),
                        fontSize: 14,
                      ),
                      child: noDataWidget,
                    )
                  : noDataWidget,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final tableMinWidth = constraints.maxWidth < 880
                    ? 880.0
                    : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableMinWidth,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          color: const Color(0x66EEF6FF),
                          child: const Row(
                            children: [
                              Expanded(
                                flex: 23,
                                child: Text(
                                  'Counselor',
                                  style: _headerTextStyle,
                                ),
                              ),
                              Expanded(
                                flex: 19,
                                child: Text(
                                  'Specialization',
                                  style: _headerTextStyle,
                                ),
                              ),
                              Expanded(
                                flex: 16,
                                child: Text(
                                  'Mode & Languages',
                                  style: _headerTextStyle,
                                ),
                              ),
                              Expanded(
                                flex: 18,
                                child: Text(
                                  'Earliest Slot',
                                  style: _headerTextStyle,
                                ),
                              ),
                              Expanded(
                                flex: 12,
                                child: Text('Rating', style: _headerTextStyle),
                              ),
                              Expanded(
                                flex: 12,
                                child: Text('Action', style: _headerTextStyle),
                              ),
                            ],
                          ),
                        ),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0x22A5B4C8),
                        ),
                        ...rows.asMap().entries.map((entry) {
                          final index = entry.key;
                          final row = entry.value;
                          final altBg = index.isEven
                              ? Colors.transparent
                              : const Color(0x1AF8FAFC);
                          final languages = row.languages.isEmpty
                              ? 'N/A'
                              : row.languages.join(', ');
                          final earliest = row.earliestAvailable == null
                              ? 'No open slots'
                              : formatSlot(row.earliestAvailable!);
                          return Material(
                            color: altBg,
                            child: InkWell(
                              onTap: () => onOpenProfile(row.counselorId),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  14,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 23,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE8F6FF),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.health_and_safety_rounded,
                                              color: Color(0xFF0284C7),
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  row.displayName,
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF0F172A),
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  row.title,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF6B7D95),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 19,
                                      child: Text(
                                        '${row.specialization}\n${row.yearsExperience} yrs experience',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.45,
                                          color: Color(0xFF445A75),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 16,
                                      child: Text(
                                        '${row.sessionMode}\n$languages',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.45,
                                          color: Color(0xFF445A75),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 18,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: row.earliestAvailable == null
                                              ? const Color(0xFFF1F5F9)
                                              : const Color(0xFFE6FFFA),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: row.earliestAvailable == null
                                                ? const Color(0xFFD8E3EE)
                                                : const Color(0xFF99F6E4),
                                          ),
                                        ),
                                        child: Text(
                                          earliest,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: row.earliestAvailable == null
                                                ? const Color(0xFF64748B)
                                                : const Color(0xFF0F766E),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 12,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.star_rounded,
                                                color: Color(0xFFF59E0B),
                                                size: 16,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                row.ratingAverage
                                                    .toStringAsFixed(1),
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF1E293B),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            '${row.ratingCount} ratings',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFF6B7D95),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 12,
                                      child: Align(
                                        alignment: Alignment.topLeft,
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              onOpenProfile(row.counselorId),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(
                                              0xFF0E9B90,
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFF8DDCD4),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 9,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.open_in_new_rounded,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'Open',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
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
