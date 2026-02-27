// features/care/presentation/counselor_directory_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/app/theme_mode_controller.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/desktop_section_shell.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/ai/models/assistant_models.dart';
import 'package:mindnest/features/ai/presentation/assistant_fab.dart';
import 'package:mindnest/features/ai/presentation/home_ai_assistant_section.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:mindnest/features/care/models/counselor_public_rating.dart';

enum _CounselorSort { earliestAvailable, ratingHigh, experienceHigh }

const _sourceQueryKey = 'from';
const _counselorsSourceValue = 'counselors';

String _counselorProfileRouteFromCounselors(String counselorId) {
  return Uri(
    path: AppRoute.counselorProfile,
    queryParameters: <String, String>{
      'counselorId': counselorId,
      _sourceQueryKey: _counselorsSourceValue,
    },
  ).toString();
}

class CounselorDirectoryScreen extends ConsumerStatefulWidget {
  const CounselorDirectoryScreen({
    super.key,
    this.embeddedInDesktopShell = false,
  });

  final bool embeddedInDesktopShell;

  @override
  ConsumerState<CounselorDirectoryScreen> createState() =>
      _CounselorDirectoryScreenState();
}

class _CounselorDirectoryScreenState
    extends ConsumerState<CounselorDirectoryScreen> {
  final _searchController = TextEditingController();
  _CounselorSort _sort = _CounselorSort.earliestAvailable;
  String _specializationFilter = 'all';
  String _modeFilter = 'all';
  double? _minimumRatingFilter;
  int _refreshTick = 0;
  int _rowsPerPage = 6;
  int _currentPage = 0;
  String? _appliedAssistantFilterToken;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyAssistantQueryFilters();
  }

  void _applyAssistantQueryFilters() {
    final uri = GoRouterState.of(context).uri;
    final token = uri.queryParameters['aiq']?.trim() ?? '';
    if (token.isEmpty || token == _appliedAssistantFilterToken) {
      return;
    }

    final sortRaw = uri.queryParameters['sort']?.trim().toLowerCase();
    final modeRaw = uri.queryParameters['mode']?.trim().toLowerCase();
    final minRatingRaw = uri.queryParameters['minRating']?.trim() ?? '';
    final search = uri.queryParameters['search']?.trim() ?? '';
    final specialization = uri.queryParameters['specialization']?.trim() ?? '';

    setState(() {
      if (sortRaw == 'rating') {
        _sort = _CounselorSort.ratingHigh;
      } else if (sortRaw == 'experience') {
        _sort = _CounselorSort.experienceHigh;
      } else if (sortRaw == 'earliest') {
        _sort = _CounselorSort.earliestAvailable;
      }

      if (modeRaw == 'virtual' || modeRaw == 'online') {
        _modeFilter = 'virtual';
      } else if (modeRaw == 'in-person' || modeRaw == 'in person') {
        _modeFilter = 'in-person';
      }

      final parsedMinRating = double.tryParse(minRatingRaw);
      if (parsedMinRating != null) {
        _minimumRatingFilter = parsedMinRating;
      }

      if (search.isNotEmpty) {
        _searchController.text = search;
      }

      if (specialization.isNotEmpty) {
        _specializationFilter = specialization;
      }

      _currentPage = 0;
      _appliedAssistantFilterToken = token;
    });
  }

  bool _canUseLive(UserProfile profile) {
    final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
    return hasInstitution &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.counselor);
  }

  Future<void> _runAssistantAction({
    required BuildContext context,
    required UserProfile profile,
    required AssistantAction action,
  }) async {
    final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
    final canUseLive = _canUseLive(profile);

    void showMessage(String text) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }

    String withQuery(String path, Map<String, String> params) {
      if (params.isEmpty) {
        return path;
      }
      return Uri(path: path, queryParameters: params).toString();
    }

    switch (action.type) {
      case AssistantActionType.openLiveHub:
        if (!hasInstitution) {
          showMessage('Join an organization to access Live Hub.');
          return;
        }
        if (!canUseLive) {
          showMessage('Your role cannot access Live Hub.');
          return;
        }
        context.go(AppRoute.liveHub);
        return;
      case AssistantActionType.goLiveCreate:
        if (!hasInstitution) {
          showMessage('Join an organization before creating a live session.');
          return;
        }
        if (!canUseLive) {
          showMessage('Your role cannot create live sessions.');
          return;
        }
        context.go('${AppRoute.liveHub}?openCreate=1&source=ai');
        return;
      case AssistantActionType.openCounselors:
        if (!hasInstitution) {
          showMessage('Join an organization to view counselors.');
          return;
        }
        context.go(withQuery(AppRoute.counselorDirectory, action.params));
        return;
      case AssistantActionType.openCounselorProfile:
        final counselorId = action.params['counselorId']?.trim() ?? '';
        if (counselorId.isEmpty) {
          context.go(AppRoute.counselorDirectory);
          return;
        }
        context.go(
          Uri(
            path: AppRoute.counselorProfile,
            queryParameters: <String, String>{'counselorId': counselorId},
          ).toString(),
        );
        return;
      case AssistantActionType.openSessions:
        if (!hasInstitution) {
          showMessage('Join an organization to manage sessions.');
          return;
        }
        context.go(withQuery(AppRoute.studentAppointments, action.params));
        return;
      case AssistantActionType.openNotifications:
        context.go(AppRoute.notifications);
        return;
      case AssistantActionType.openCarePlan:
        if (!hasInstitution) {
          showMessage('Join an organization to access Care Plan.');
          return;
        }
        context.go(AppRoute.carePlan);
        return;
      case AssistantActionType.openJoinInstitution:
        context.go(AppRoute.joinInstitution);
        return;
      case AssistantActionType.openPrivacy:
        context.go(AppRoute.privacyControls);
        return;
      case AssistantActionType.setThemeLight:
        await ref
            .read(themeModeControllerProvider.notifier)
            .setMode(ThemeMode.light);
        showMessage('Switched to light mode.');
        return;
      case AssistantActionType.setThemeDark:
        await ref
            .read(themeModeControllerProvider.notifier)
            .setMode(ThemeMode.dark);
        showMessage('Switched to dark mode.');
        return;
    }
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

  bool _isSameLocalDate(DateTime a, DateTime b) {
    final first = a.toLocal();
    final second = b.toLocal();
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String _formatNextOpenSlotSummary(DateTime? value) {
    if (value == null) {
      return 'No open slots';
    }
    final local = value.toLocal();
    final now = DateTime.now();
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (_isSameLocalDate(local, now)) {
      return 'Today $clock';
    }
    return '${local.month}/${local.day} $clock';
  }

  int _activeFilterCount() {
    var count = 0;
    if (_sort != _CounselorSort.earliestAvailable) count++;
    if (_specializationFilter != 'all') count++;
    if (_modeFilter != 'all') count++;
    if (_minimumRatingFilter != null) count++;
    return count;
  }

  Future<void> _openFilterSheet({
    required List<String> specializationOptions,
    required List<String> modeOptions,
  }) async {
    var tempSort = _sort;
    var tempSpecialization = _specializationFilter;
    var tempMode = _modeFilter;
    double? tempRating = _minimumRatingFilter;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD3DFEC),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          color: Color(0xFF0E9B90),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Filters',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ModalDropdownField<_CounselorSort>(
                      icon: Icons.schedule_rounded,
                      label: 'Sort',
                      value: tempSort,
                      items: _CounselorSort.values
                          .map(
                            (sortValue) => DropdownMenuItem(
                              value: sortValue,
                              child: Text(_sortLabel(sortValue)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => tempSort = value);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    _ModalDropdownField<String>(
                      icon: Icons.psychology_alt_rounded,
                      label: 'Specialization',
                      value: tempSpecialization,
                      items: specializationOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option,
                              child: Text(option == 'all' ? 'All' : option),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => tempSpecialization = value);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    _ModalDropdownField<String>(
                      icon: Icons.videocam_rounded,
                      label: 'Mode',
                      value: tempMode,
                      items: modeOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option,
                              child: Text(option == 'all' ? 'All' : option),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => tempMode = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Minimum Rating',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF445A75),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _RatingChip(
                          label: 'All',
                          selected: tempRating == null,
                          onTap: () => setSheetState(() => tempRating = null),
                        ),
                        _RatingChip(
                          label: '4.5+',
                          selected: tempRating == 4.5,
                          onTap: () => setSheetState(() => tempRating = 4.5),
                        ),
                        _RatingChip(
                          label: '4.0+',
                          selected: tempRating == 4.0,
                          onTap: () => setSheetState(() => tempRating = 4.0),
                        ),
                        _RatingChip(
                          label: '3.5+',
                          selected: tempRating == 3.5,
                          onTap: () => setSheetState(() => tempRating = 3.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setSheetState(() {
                                tempSort = _CounselorSort.earliestAvailable;
                                tempSpecialization = 'all';
                                tempMode = 'all';
                                tempRating = null;
                              });
                            },
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              size: 16,
                            ),
                            label: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _sort = tempSort;
                                _specializationFilter = tempSpecialization;
                                _modeFilter = tempMode;
                                _minimumRatingFilter = tempRating;
                                _currentPage = 0;
                              });
                              Navigator.of(sheetContext).pop();
                            },
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundMode: widget.embeddedInDesktopShell && isDesktop
          ? MindNestBackgroundMode.plainWhite
          : MindNestBackgroundMode.homeStyle,
      appBar: null,
      floatingActionButton: profile == null
          ? null
          : AssistantFab(
              heroTag: 'assistant-fab-counselors',
              onPressed: () => showMindNestAssistantSheet(
                context: context,
                profile: profile,
                onActionRequested: (action) => _runAssistantAction(
                  context: context,
                  profile: profile,
                  action: action,
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      child: DesktopSectionBody(
        isDesktop: isDesktop && !widget.embeddedInDesktopShell,
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
                          final modes = <String>{'all'};
                          for (final counselor in counselors) {
                            specializations.add(counselor.specialization);
                            modes.add(counselor.sessionMode);
                          }

                          final hasSpecialization = specializations.any(
                            (item) =>
                                item.toLowerCase() ==
                                _specializationFilter.toLowerCase(),
                          );
                          if (!hasSpecialization) {
                            _specializationFilter = 'all';
                          }
                          final hasMode = modes.any(
                            (item) =>
                                item.toLowerCase() == _modeFilter.toLowerCase(),
                          );
                          if (!hasMode) {
                            _modeFilter = 'all';
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
                                    entry.specialization.toLowerCase() ==
                                        _specializationFilter.toLowerCase();
                                final matchesMode =
                                    _modeFilter == 'all' ||
                                    entry.sessionMode.toLowerCase() ==
                                        _modeFilter.toLowerCase();
                                final matchesRating =
                                    _minimumRatingFilter == null ||
                                    ratingAverageFor(entry) >=
                                        _minimumRatingFilter!;
                                return matchesSearch &&
                                    matchesSpecialization &&
                                    matchesMode &&
                                    matchesRating;
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
                              _specializationFilter != 'all' ||
                              _modeFilter != 'all' ||
                              _minimumRatingFilter != null;
                          final specializationOptions = specializations.toList()
                            ..sort();
                          final modeOptions = modes.toList()..sort();
                          final totalRows = filtered.length;
                          final totalPages = totalRows == 0
                              ? 1
                              : ((totalRows + _rowsPerPage - 1) ~/
                                    _rowsPerPage);
                          final pageIndex = _currentPage >= totalPages
                              ? totalPages - 1
                              : _currentPage;
                          final pagedRows = filtered
                              .skip(pageIndex * _rowsPerPage)
                              .take(_rowsPerPage)
                              .toList(growable: false);

                          final filteredCounselorIds = filtered
                              .map((entry) => entry.id)
                              .toSet();
                          final activeNowCount = filtered
                              .where(
                                (entry) =>
                                    earliestSlotByCounselor[entry.id] != null,
                              )
                              .length;
                          DateTime? nextOpenSlot;
                          for (final slot in availability) {
                            if (!filteredCounselorIds.contains(
                              slot.counselorId,
                            )) {
                              continue;
                            }
                            if (nextOpenSlot == null ||
                                slot.startAt.isBefore(nextOpenSlot)) {
                              nextOpenSlot = slot.startAt;
                            }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CounselorOverviewStrip(
                                activeNowCount: activeNowCount,
                                nextOpenSlotLabel: _formatNextOpenSlotSummary(
                                  nextOpenSlot,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _CounselorDirectoryTable(
                                rows: pagedRows
                                    .map(
                                      (counselor) => _CounselorTableRowData(
                                        counselorId: counselor.id,
                                        displayName: counselor.displayName,
                                        title: counselor.title,
                                        specialization:
                                            counselor.specialization,
                                        sessionMode: counselor.sessionMode,
                                        languages: counselor.languages,
                                        yearsExperience:
                                            counselor.yearsExperience,
                                        ratingAverage: ratingAverageFor(
                                          counselor,
                                        ),
                                        ratingCount: ratingCountFor(counselor),
                                        earliestAvailable:
                                            earliestSlotByCounselor[counselor
                                                .id],
                                      ),
                                    )
                                    .toList(growable: false),
                                formatSlot: _formatSlot,
                                onOpenProfile: (counselorId) {
                                  context.push(
                                    _counselorProfileRouteFromCounselors(
                                      counselorId,
                                    ),
                                  );
                                },
                                searchController: _searchController,
                                onSearchChanged: (_) => setState(() {
                                  _currentPage = 0;
                                }),
                                onOpenFilters: () => _openFilterSheet(
                                  specializationOptions: specializationOptions,
                                  modeOptions: modeOptions,
                                ),
                                activeFilterCount: _activeFilterCount(),
                                rowsPerPage: _rowsPerPage,
                                onRowsPerPageChanged: (value) => setState(() {
                                  _rowsPerPage = value;
                                  _currentPage = 0;
                                }),
                                currentPage: pageIndex,
                                totalPages: totalPages,
                                totalRows: totalRows,
                                onPreviousPage: () => setState(() {
                                  if (pageIndex > 0) {
                                    _currentPage = pageIndex - 1;
                                  }
                                }),
                                onNextPage: () => setState(() {
                                  if (pageIndex < totalPages - 1) {
                                    _currentPage = pageIndex + 1;
                                  }
                                }),
                                hasActiveFilters: hasActiveFilters,
                                noDataWidget: hasActiveFilters
                                    ? const Text(
                                        'No counselors match your filters. Try broadening your search.',
                                      )
                                    : _PendingCounselorFallback(
                                        institutionId: institutionId,
                                      ),
                              ),
                            ],
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

class _ModalDropdownField<T> extends StatelessWidget {
  const _ModalDropdownField({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E4F2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF5E728D)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
          const Spacer(),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              menuMaxHeight: 320,
              borderRadius: BorderRadius.circular(12),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0E9B90) : const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF0E9B90) : const Color(0xFFD6E4F2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              size: 14,
              color: selected ? Colors.white : const Color(0xFFF59E0B),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF475569),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounselorOverviewStrip extends StatelessWidget {
  const _CounselorOverviewStrip({
    required this.activeNowCount,
    required this.nextOpenSlotLabel,
  });

  final int activeNowCount;
  final String nextOpenSlotLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OverviewCard(
            title: 'Active now',
            value: '$activeNowCount',
            icon: Icons.bolt_rounded,
            primary: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OverviewCard(
            title: 'Next open slot',
            value: nextOpenSlotLabel,
            icon: Icons.schedule_rounded,
          ),
        ),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.title,
    required this.value,
    required this.icon,
    this.primary = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      fontSize: 12,
      letterSpacing: 0.9,
      fontWeight: FontWeight.w800,
      color: primary ? const Color(0xFFEEF2FF) : const Color(0xFF8698B2),
    );
    final valueStyle = TextStyle(
      fontSize: 35 / 2,
      fontWeight: FontWeight.w800,
      color: primary ? Colors.white : const Color(0xFF0F172A),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: primary
            ? const LinearGradient(
                colors: [Color(0xFF5146FF), Color(0xFF4639E6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: primary ? null : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: primary ? const Color(0xFF5B4FFF) : const Color(0xFFDCE5EF),
        ),
        boxShadow: [
          BoxShadow(
            color: primary ? const Color(0x4D4338DC) : const Color(0x1A0F172A),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: primary
                  ? const Color(0x40FFFFFF)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              size: 18,
              color: primary ? Colors.white : const Color(0xFF0E9B90),
            ),
          ),
          const SizedBox(height: 12),
          Text(title.toUpperCase(), style: titleStyle),
          const SizedBox(height: 3),
          Text(
            value,
            style: valueStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CounselorDirectoryTable extends StatelessWidget {
  const _CounselorDirectoryTable({
    required this.rows,
    required this.formatSlot,
    required this.onOpenProfile,
    required this.searchController,
    required this.onSearchChanged,
    required this.onOpenFilters,
    required this.activeFilterCount,
    required this.rowsPerPage,
    required this.onRowsPerPageChanged,
    required this.currentPage,
    required this.totalPages,
    required this.totalRows,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.hasActiveFilters,
    required this.noDataWidget,
  });

  final List<_CounselorTableRowData> rows;
  final String Function(DateTime value) formatSlot;
  final ValueChanged<String> onOpenProfile;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onOpenFilters;
  final int activeFilterCount;
  final int rowsPerPage;
  final ValueChanged<int> onRowsPerPageChanged;
  final int currentPage;
  final int totalPages;
  final int totalRows;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
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
                    hintText: 'Search...',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x66FFFFFF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD0DFEE)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: rowsPerPage,
                          isDense: true,
                          borderRadius: BorderRadius.circular(10),
                          items: const [
                            DropdownMenuItem(value: 4, child: Text('4 / page')),
                            DropdownMenuItem(value: 6, child: Text('6 / page')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              onRowsPerPageChanged(value);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$totalRows total',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: onOpenFilters,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          width: 1.5,
                          color: Color(0xFF0E7490),
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 12),
                      label: const Text('Filters'),
                    ),
                    if (activeFilterCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E9B90),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$activeFilterCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    Text(
                      'Page ${currentPage + 1} / $totalPages',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF5E728D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Previous',
                      onPressed: currentPage > 0 ? onPreviousPage : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    IconButton(
                      tooltip: 'Next',
                      onPressed: currentPage < totalPages - 1
                          ? onNextPage
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
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
                                child: Padding(
                                  padding: EdgeInsets.only(right: 40),
                                  child: Text(
                                    'Earliest Slot',
                                    style: _headerTextStyle,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 12,
                                child: Text('Rating', style: _headerTextStyle),
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
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 32,
                                        ),
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
                                              color:
                                                  row.earliestAvailable == null
                                                  ? const Color(0xFFD8E3EE)
                                                  : const Color(0xFF99F6E4),
                                            ),
                                          ),
                                          child: Text(
                                            earliest,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  row.earliestAvailable == null
                                                  ? const Color(0xFF64748B)
                                                  : const Color(0xFF0F766E),
                                            ),
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
                            _counselorProfileRouteFromCounselors(userId),
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
