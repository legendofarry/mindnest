// features/care/presentation/student_appointments_screen.dart
import 'dart:math' as math;

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
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';

enum _AppointmentSort { newest, oldest, counselorAz, status }

const _sourceQueryKey = 'from';
const _studentAppointmentsSourceValue = 'studentAppointments';

String _sessionDetailsRouteFromStudentAppointments(String appointmentId) {
  return Uri(
    path: AppRoute.sessionDetails,
    queryParameters: <String, String>{
      'appointmentId': appointmentId,
      _sourceQueryKey: _studentAppointmentsSourceValue,
    },
  ).toString();
}

class StudentAppointmentsScreen extends ConsumerStatefulWidget {
  const StudentAppointmentsScreen({super.key});

  @override
  ConsumerState<StudentAppointmentsScreen> createState() =>
      _StudentAppointmentsScreenState();
}

class _StudentAppointmentsScreenState
    extends ConsumerState<StudentAppointmentsScreen> {
  TextEditingController? _searchController;
  bool _timelineView = false;
  int _refreshTick = 0;
  _AppointmentSort _tableSort = _AppointmentSort.newest;
  AppointmentStatus? _tableStatusFilter;
  AppointmentStatus? _timelineStatusFilter;
  int _tableRowsPerPage = 6;
  int _tableCurrentPage = 0;
  String? _expandedTimelineDateKey;

  @override
  void dispose() {
    _searchController?.dispose();
    super.dispose();
  }

  TextEditingController get _effectiveSearchController =>
      _searchController ??= TextEditingController();

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime value) {
    final date = value.toLocal();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _dateKey(DateTime value) {
    final date = value.toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateHeader(DateTime value) {
    const months = <String>[
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
    final local = value.toLocal();
    final month = months[math.max(0, math.min(local.month - 1, 11))];
    return '$month ${local.day}, ${local.year}';
  }

  String _statusLabel(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return 'Pending';
      case AppointmentStatus.confirmed:
        return 'Confirmed';
      case AppointmentStatus.completed:
        return 'Completed';
      case AppointmentStatus.cancelled:
        return 'Cancelled';
      case AppointmentStatus.noShow:
        return 'No-show';
    }
  }

  String _sortLabel(_AppointmentSort sort) {
    switch (sort) {
      case _AppointmentSort.newest:
        return 'Newest first';
      case _AppointmentSort.oldest:
        return 'Oldest first';
      case _AppointmentSort.counselorAz:
        return 'Counselor A-Z';
      case _AppointmentSort.status:
        return 'Status';
    }
  }

  int _activeTableFilterCount() {
    var count = 0;
    if (_tableSort != _AppointmentSort.newest) count++;
    if (_tableStatusFilter != null) count++;
    return count;
  }

  List<AppointmentRecord> _applyTableFilters(List<AppointmentRecord> source) {
    final query = (_searchController?.text ?? '').trim().toLowerCase();
    final filtered = source
        .where((appointment) {
          final counselorName =
              (appointment.counselorName ?? appointment.counselorId)
                  .toLowerCase();
          final statusText = _statusLabel(appointment.status).toLowerCase();
          final dateText = _formatDate(appointment.startAt).toLowerCase();
          final matchesSearch =
              query.isEmpty ||
              ('$counselorName $statusText $dateText').contains(query);
          final matchesStatus =
              _tableStatusFilter == null ||
              appointment.status == _tableStatusFilter;
          return matchesSearch && matchesStatus;
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      switch (_tableSort) {
        case _AppointmentSort.newest:
          return b.startAt.compareTo(a.startAt);
        case _AppointmentSort.oldest:
          return a.startAt.compareTo(b.startAt);
        case _AppointmentSort.counselorAz:
          return (a.counselorName ?? a.counselorId).compareTo(
            b.counselorName ?? b.counselorId,
          );
        case _AppointmentSort.status:
          return _statusLabel(a.status).compareTo(_statusLabel(b.status));
      }
    });
    return filtered;
  }

  List<AppointmentRecord> _applyTimelineFilters(
    List<AppointmentRecord> source,
  ) {
    final filtered = source
        .where((appointment) {
          if (_timelineStatusFilter == null) return true;
          return appointment.status == _timelineStatusFilter;
        })
        .toList(growable: false);
    filtered.sort((a, b) => b.startAt.compareTo(a.startAt));
    return filtered;
  }

  Future<void> _openTableFilterSheet() async {
    var tempSort = _tableSort;
    AppointmentStatus? tempStatus = _tableStatusFilter;

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
                    DropdownButtonFormField<_AppointmentSort>(
                      initialValue: tempSort,
                      decoration: const InputDecoration(
                        labelText: 'Sort',
                        prefixIcon: Icon(Icons.swap_vert_rounded),
                      ),
                      items: _AppointmentSort.values
                          .map(
                            (sort) => DropdownMenuItem(
                              value: sort,
                              child: Text(_sortLabel(sort)),
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
                    DropdownButtonFormField<AppointmentStatus?>(
                      initialValue: tempStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        prefixIcon: Icon(Icons.flag_rounded),
                      ),
                      items: [
                        const DropdownMenuItem<AppointmentStatus?>(
                          value: null,
                          child: Text('All'),
                        ),
                        ...AppointmentStatus.values.map(
                          (status) => DropdownMenuItem<AppointmentStatus?>(
                            value: status,
                            child: Text(_statusLabel(status)),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setSheetState(() => tempStatus = value),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setSheetState(() {
                                tempSort = _AppointmentSort.newest;
                                tempStatus = null;
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
                                _tableSort = tempSort;
                                _tableStatusFilter = tempStatus;
                                _tableCurrentPage = 0;
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

  Color _statusColor(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return const Color(0xFFD97706);
      case AppointmentStatus.confirmed:
        return const Color(0xFF0369A1);
      case AppointmentStatus.completed:
        return const Color(0xFF059669);
      case AppointmentStatus.cancelled:
        return const Color(0xFFDC2626);
      case AppointmentStatus.noShow:
        return const Color(0xFF7C3AED);
    }
  }

  Future<void> _cancelAppointment(
    BuildContext context,
    WidgetRef ref,
    AppointmentRecord appointment,
  ) async {
    try {
      await ref
          .read(careRepositoryProvider)
          .cancelAppointmentAsStudent(appointment);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Appointment cancelled.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _rescheduleAppointment(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    AppointmentRecord appointment,
  ) async {
    final institutionId = profile.institutionId ?? '';
    if (institutionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join an institution first.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: StreamBuilder<List<AvailabilitySlot>>(
              stream: ref
                  .read(careRepositoryProvider)
                  .watchCounselorPublicAvailability(
                    institutionId: institutionId,
                    counselorId: appointment.counselorId,
                  ),
              builder: (context, snapshot) {
                final slots = (snapshot.data ?? const [])
                    .where((slot) => slot.id != appointment.slotId)
                    .toList(growable: false);
                if (snapshot.connectionState == ConnectionState.waiting &&
                    slots.isEmpty) {
                  return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Reschedule Session',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pick a new available slot from this counselor.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    if (slots.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No alternate slots available right now.'),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: slots.length.clamp(0, 18),
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final slot = slots[index];
                            return ListTile(
                              tileColor: const Color(0xFFF8FAFC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              title: Text(_formatDate(slot.startAt)),
                              subtitle: Text(
                                'Ends: ${_formatDate(slot.endAt)}',
                              ),
                              trailing: ElevatedButton(
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(careRepositoryProvider)
                                        .rescheduleAppointmentAsStudent(
                                          appointment: appointment,
                                          newSlot: slot,
                                          currentProfile: profile,
                                        );
                                    if (!mounted) {
                                      return;
                                    }
                                    Navigator.of(this.context).pop();
                                    ScaffoldMessenger.of(
                                      this.context,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Appointment rescheduled.',
                                        ),
                                      ),
                                    );
                                  } catch (error) {
                                    if (!mounted) {
                                      return;
                                    }
                                    ScaffoldMessenger.of(
                                      this.context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          error.toString().replaceFirst(
                                            'Exception: ',
                                            '',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Choose'),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _rateAppointment(
    BuildContext context,
    WidgetRef ref,
    AppointmentRecord appointment,
  ) async {
    int selectedRating = 5;
    final feedbackController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Rate Session'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    children: List<Widget>.generate(5, (index) {
                      final value = index + 1;
                      return IconButton(
                        onPressed: () => setState(() => selectedRating = value),
                        icon: Icon(
                          value <= selectedRating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFF59E0B),
                        ),
                      );
                    }),
                  ),
                  TextField(
                    controller: feedbackController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Feedback (optional)',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref
          .read(careRepositoryProvider)
          .submitRating(
            appointment: appointment,
            rating: selectedRating,
            feedback: feedbackController.text,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rating submitted.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Widget _buildTimeline(List<AppointmentRecord> appointments) {
    Widget timelineFilterChip({
      required String label,
      required AppointmentStatus? status,
      required Color activeColor,
    }) {
      final selected = _timelineStatusFilter == status;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() {
          _timelineStatusFilter = status;
          _expandedTimelineDateKey = null;
        }),
        selectedColor: activeColor.withValues(alpha: 0.16),
        side: BorderSide(
          color: selected ? activeColor : const Color(0xFFD3E0EE),
          width: selected ? 1.2 : 1,
        ),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? activeColor : const Color(0xFF475569),
        ),
      );
    }

    final timelineFilterBar = GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            timelineFilterChip(
              label: 'All',
              status: null,
              activeColor: const Color(0xFF0E7490),
            ),
            timelineFilterChip(
              label: 'Cancelled',
              status: AppointmentStatus.cancelled,
              activeColor: const Color(0xFFDC2626),
            ),
            timelineFilterChip(
              label: 'No-show',
              status: AppointmentStatus.noShow,
              activeColor: const Color(0xFF7C3AED),
            ),
            timelineFilterChip(
              label: 'Completed',
              status: AppointmentStatus.completed,
              activeColor: const Color(0xFF059669),
            ),
          ],
        ),
      ),
    );

    final filtered = _applyTimelineFilters(appointments);
    if (filtered.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          timelineFilterBar,
          const SizedBox(height: 10),
          const GlassCard(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No sessions match the selected timeline filter.'),
            ),
          ),
        ],
      );
    }

    final grouped = <String, List<AppointmentRecord>>{};
    final dateByKey = <String, DateTime>{};
    for (final appointment in filtered) {
      final key = _dateKey(appointment.startAt);
      grouped.putIfAbsent(key, () => <AppointmentRecord>[]).add(appointment);
      dateByKey.putIfAbsent(key, () {
        final local = appointment.startAt.toLocal();
        return DateTime(local.year, local.month, local.day);
      });
    }
    final orderedKeys = grouped.keys.toList(growable: false);
    for (final key in orderedKeys) {
      grouped[key]!.sort((a, b) => a.startAt.compareTo(b.startAt));
    }
    final todayKey = _dateKey(DateTime.now());
    final defaultExpandedKey = grouped.containsKey(todayKey)
        ? todayKey
        : orderedKeys.first;

    Widget statusChip(AppointmentStatus status) {
      final color = _statusColor(status);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(
          _statusLabel(status),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        timelineFilterBar,
        const SizedBox(height: 10),
        ...orderedKeys.map((key) {
          final date = dateByKey[key]!;
          final events = grouped[key]!;
          final expandedKey = _expandedTimelineDateKey ?? defaultExpandedKey;
          final expanded = key == expandedKey;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          if (_expandedTimelineDateKey == key) {
                            _expandedTimelineDateKey = null;
                          } else {
                            _expandedTimelineDateKey = key;
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              expanded
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.chevron_right_rounded,
                              color: const Color(0xFF334155),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_formatDateHeader(date)} (${events.length} events)',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (expanded) ...[
                      const SizedBox(height: 4),
                      ...events.map((appointment) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () =>
                              _openSessionDetails(context, appointment),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 7,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _formatTime(appointment.startAt),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '•',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                statusChip(appointment.status),
                                const Spacer(),
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                  color: Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _actionIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    Color color = const Color(0xFF0E7490),
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  Widget _buildTable(
    List<AppointmentRecord> appointments,
    UserProfile? profile,
  ) {
    final filtered = _applyTableFilters(appointments);
    final totalRows = filtered.length;
    final totalPages = totalRows == 0
        ? 1
        : ((totalRows + _tableRowsPerPage - 1) ~/ _tableRowsPerPage);
    final pageIndex = _tableCurrentPage >= totalPages
        ? totalPages - 1
        : _tableCurrentPage;
    final pagedRows = filtered
        .skip(pageIndex * _tableRowsPerPage)
        .take(_tableRowsPerPage)
        .toList(growable: false);
    final hasActiveFilters =
        (_searchController?.text.trim().isNotEmpty ?? false) ||
        _tableStatusFilter != null;

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
                  'Appointments ($totalRows)',
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
                  controller: _effectiveSearchController,
                  onChanged: (_) => setState(() => _tableCurrentPage = 0),
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
                          value: _tableRowsPerPage,
                          isDense: true,
                          borderRadius: BorderRadius.circular(10),
                          items: const [
                            DropdownMenuItem(value: 4, child: Text('4 / page')),
                            DropdownMenuItem(value: 6, child: Text('6 / page')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _tableRowsPerPage = value;
                                _tableCurrentPage = 0;
                              });
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
                      onPressed: _openTableFilterSheet,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          width: 1.5,
                          color: Color(0xFF0E7490),
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 12),
                      label: const Text('Filters'),
                    ),
                    if (_activeTableFilterCount() > 0) ...[
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
                          '${_activeTableFilterCount()}',
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
                      'Page ${pageIndex + 1} / $totalPages',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF5E728D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Previous',
                      onPressed: pageIndex > 0
                          ? () => setState(
                              () => _tableCurrentPage = pageIndex - 1,
                            )
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    IconButton(
                      tooltip: 'Next',
                      onPressed: pageIndex < totalPages - 1
                          ? () => setState(
                              () => _tableCurrentPage = pageIndex + 1,
                            )
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0x22A5B4C8)),
          if (pagedRows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                hasActiveFilters
                    ? 'No sessions match your search or filter criteria.'
                    : 'No sessions available.',
                style: const TextStyle(color: Color(0xFF4A607C), fontSize: 14),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const tableColumnGap = 12.0;
                final minWidth = constraints.maxWidth < 980
                    ? 980.0
                    : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: minWidth,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          color: const Color(0x66EEF6FF),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 20,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: tableColumnGap,
                                  ),
                                  child: const Text(
                                    'Counselor',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF5B6E87),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 12,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: tableColumnGap,
                                  ),
                                  child: const Text(
                                    'Status',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF5B6E87),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 20,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: tableColumnGap,
                                  ),
                                  child: const Text(
                                    'Start',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF5B6E87),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 20,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: tableColumnGap,
                                  ),
                                  child: const Text(
                                    'End',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF5B6E87),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 28,
                                child: const Text(
                                  'Actions',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF5B6E87),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0x22A5B4C8),
                        ),
                        ...pagedRows.asMap().entries.map((entry) {
                          final index = entry.key;
                          final appointment = entry.value;
                          final statusColor = _statusColor(appointment.status);
                          final rowBg = index.isEven
                              ? Colors.transparent
                              : const Color(0x1AF8FAFC);
                          return Material(
                            color: rowBg,
                            child: InkWell(
                              onTap: () =>
                                  _openSessionDetails(context, appointment),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 20,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: tableColumnGap,
                                        ),
                                        child: Text(
                                          appointment.counselorName ??
                                              appointment.counselorId,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 12,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: tableColumnGap,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                              alpha: 0.14,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            _statusLabel(appointment.status),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 20,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: tableColumnGap,
                                        ),
                                        child: Text(
                                          _formatDate(appointment.startAt),
                                          style: const TextStyle(
                                            color: Color(0xFF445A75),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 20,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: tableColumnGap,
                                        ),
                                        child: Text(
                                          _formatDate(appointment.endAt),
                                          style: const TextStyle(
                                            color: Color(0xFF445A75),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 28,
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _actionIconButton(
                                            icon: Icons.open_in_new_rounded,
                                            tooltip: 'Open details',
                                            onTap: () => _openSessionDetails(
                                              context,
                                              appointment,
                                            ),
                                            color: const Color(0xFF0E7490),
                                          ),
                                          if (appointment.status ==
                                                  AppointmentStatus.pending ||
                                              appointment.status ==
                                                  AppointmentStatus.confirmed)
                                            _actionIconButton(
                                              icon: Icons.event_repeat_rounded,
                                              tooltip: 'Reschedule',
                                              onTap: profile == null
                                                  ? null
                                                  : () =>
                                                        _rescheduleAppointment(
                                                          context,
                                                          ref,
                                                          profile,
                                                          appointment,
                                                        ),
                                              color: const Color(0xFF0F766E),
                                            ),
                                          if (appointment.status ==
                                                  AppointmentStatus.pending ||
                                              appointment.status ==
                                                  AppointmentStatus.confirmed)
                                            _actionIconButton(
                                              icon: Icons.cancel_rounded,
                                              tooltip: 'Cancel',
                                              onTap: () => _cancelAppointment(
                                                context,
                                                ref,
                                                appointment,
                                              ),
                                              color: const Color(0xFFB91C1C),
                                            ),
                                          if (appointment.status ==
                                                  AppointmentStatus.completed &&
                                              !appointment.rated)
                                            _actionIconButton(
                                              icon: Icons.star_rounded,
                                              tooltip: 'Rate session',
                                              onTap: () => _rateAppointment(
                                                context,
                                                ref,
                                                appointment,
                                              ),
                                              color: const Color(0xFFD97706),
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

  void _openSessionDetails(
    BuildContext context,
    AppointmentRecord appointment,
  ) {
    context.go(_sessionDetailsRouteFromStudentAppointments(appointment.id));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final userId = profile?.id ?? '';
    final canAccessLive =
        profile != null &&
        (profile.role == UserRole.student ||
            profile.role == UserRole.staff ||
            profile.role == UserRole.counselor);

    return MindNestShell(
      maxWidth: isDesktop ? 1240 : 980,
      appBar: AppBar(
        title: Text(
          'My Counseling Sessions',
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
            tooltip: 'Retry',
            onPressed: () => setState(() => _refreshTick++),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: DesktopSectionBody(
        isDesktop: isDesktop,
        hasInstitution: institutionId.isNotEmpty,
        canAccessLive: canAccessLive,
        child: institutionId.isEmpty || userId.isEmpty
            ? const GlassCard(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Join an institution to manage appointments.'),
                ),
              )
            : StreamBuilder<List<AppointmentRecord>>(
                key: ValueKey(_refreshTick),
                stream: ref
                    .read(careRepositoryProvider)
                    .watchStudentAppointments(
                      institutionId: institutionId,
                      studentId: userId,
                    ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              snapshot.error.toString().replaceFirst(
                                'Exception: ',
                                '',
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () => setState(() => _refreshTick++),
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final appointments = snapshot.data ?? const [];
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      appointments.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (appointments.isEmpty) {
                    return const GlassCard(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'No appointments yet. Open Find Counselors and book your first session.',
                        ),
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassCard(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFFBEB), Color(0xFFFFEDD5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFFFDBA74),
                              width: 1.2,
                            ),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFB45309),
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Cancellation policy: cancel early when possible so the counselor can reopen the slot for other students.',
                                  style: TextStyle(
                                    color: Color(0xFF9A3412),
                                    fontWeight: FontWeight.w700,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.view_module_rounded,
                              size: 16,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Table'),
                            selected: !_timelineView,
                            onSelected: (_) =>
                                setState(() => _timelineView = false),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Timeline'),
                            selected: _timelineView,
                            onSelected: (_) =>
                                setState(() => _timelineView = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_timelineView)
                        _buildTimeline(appointments)
                      else
                        _buildTable(appointments, profile),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
