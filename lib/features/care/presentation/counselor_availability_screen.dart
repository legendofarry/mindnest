import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';

class CounselorAvailabilityScreen extends ConsumerStatefulWidget {
  const CounselorAvailabilityScreen({super.key});

  @override
  ConsumerState<CounselorAvailabilityScreen> createState() =>
      _CounselorAvailabilityScreenState();
}

class _CounselorAvailabilityScreenState
    extends ConsumerState<CounselorAvailabilityScreen> {
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isSaving = false;
  late DateTime _weekStart;

  static const List<int> _gridHours = <int>[
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
  ];

  static const List<String> _monthNames = <String>[
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

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
  }

  DateTime _startOfWeek(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final offset = local.weekday - DateTime.monday;
    return local.subtract(Duration(days: offset));
  }

  List<DateTime> _currentWeekDays() {
    return List<DateTime>.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
      growable: false,
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _weekRangeLabel() {
    final end = _weekStart.add(const Duration(days: 6));
    final startMonth = _monthNames[_weekStart.month - 1];
    final endMonth = _monthNames[end.month - 1];
    return '$startMonth ${_weekStart.day} - $endMonth ${end.day}, ${end.year}';
  }

  String _weekdayLabel(DateTime day) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[day.weekday - 1];
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  DateTime? _composeDateTime(DateTime? date, TimeOfDay? time) {
    if (date == null || time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _saveSlot(UserProfile profile) async {
    final startLocal = _composeDateTime(_date, _startTime);
    final endLocal = _composeDateTime(_date, _endTime);
    if (startLocal == null || endLocal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose date, start, and end time.')),
      );
      return;
    }
    if (!endLocal.isAfter(startLocal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    await _createSlot(
      profile: profile,
      startLocal: startLocal,
      endLocal: endLocal,
      successText: 'Availability slot created.',
    );
  }

  Future<void> _createSlot({
    required UserProfile profile,
    required DateTime startLocal,
    required DateTime endLocal,
    required String successText,
  }) async {
    final institutionId = profile.institutionId ?? '';
    if (institutionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Counselor must be linked to institution.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .createAvailabilitySlot(
            institutionId: institutionId,
            startAtUtc: startLocal.toUtc(),
            endAtUtc: endLocal.toUtc(),
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successText)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final handled = await _handleFirestoreIndexError(error);
      if (handled) {
        return;
      }
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
        setState(() => _isSaving = false);
      }
    }
  }

  String? _extractFirebaseIndexUrl(String text) {
    final normalized = text.replaceAll('\n', ' ');
    final match = RegExp(
      r'https://console\.firebase\.google\.com/[^\s]+',
    ).firstMatch(normalized);
    return match?.group(0);
  }

  Future<bool> _handleFirestoreIndexError(Object error) async {
    if (error is! FirebaseException || error.code != 'failed-precondition') {
      return false;
    }
    final errorText = error.message ?? error.toString();
    final indexUrl = _extractFirebaseIndexUrl(errorText);
    if (indexUrl == null || !mounted) {
      return false;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Missing Firestore Index'),
          content: const Text(
            'Your project needs a composite index for this query. Copy the link and open it in your browser to create the index, then retry.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: indexUrl));
                if (!mounted) {
                  return;
                }
                Navigator.of(this.context).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Index link copied. Open it in your browser and create the index.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Link'),
            ),
          ],
        );
      },
    );
    return true;
  }

  List<AvailabilitySlot> _slotsForCell({
    required List<AvailabilitySlot> slots,
    required DateTime day,
    required int hour,
  }) {
    final cellStart = DateTime(day.year, day.month, day.day, hour);
    final cellEnd = cellStart.add(const Duration(hours: 1));
    return slots
        .where((slot) {
          final start = slot.startAt.toLocal();
          final end = slot.endAt.toLocal();
          return start.isBefore(cellEnd) && end.isAfter(cellStart);
        })
        .toList(growable: false);
  }

  Future<void> _onCellTap({
    required UserProfile profile,
    required DateTime day,
    required int hour,
    required List<AvailabilitySlot> cellSlots,
  }) async {
    if (cellSlots.isEmpty) {
      final start = DateTime(day.year, day.month, day.day, hour);
      final end = start.add(const Duration(hours: 1));
      await _createSlot(
        profile: profile,
        startLocal: start,
        endLocal: end,
        successText: 'Quick slot added to calendar.',
      );
      return;
    }

    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Scheduled Slots',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 10),
                ...cellSlots.map((slot) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_formatDateTime(slot.startAt)} - ${_formatDateTime(slot.endAt)} (${slot.status.name})',
                          ),
                        ),
                        if (slot.status == AvailabilitySlotStatus.available)
                          IconButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await ref
                                  .read(careRepositoryProvider)
                                  .deleteAvailabilitySlot(slot);
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
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

  Color _cellColor(List<AvailabilitySlot> slots) {
    if (slots.isEmpty) {
      return Colors.white;
    }
    if (slots.any((slot) => slot.status == AvailabilitySlotStatus.booked)) {
      return const Color(0xFFFFF7ED);
    }
    if (slots.any((slot) => slot.status == AvailabilitySlotStatus.blocked)) {
      return const Color(0xFFFFF1F2);
    }
    return const Color(0xFFEFFFFC);
  }

  Widget _buildWeeklyGrid(UserProfile profile, List<AvailabilitySlot> slots) {
    final days = _currentWeekDays();
    final weekControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () {
            setState(
              () => _weekStart = _weekStart.subtract(const Duration(days: 7)),
            );
          },
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Flexible(
          child: Text(
            _weekRangeLabel(),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        IconButton(
          onPressed: () {
            setState(
              () => _weekStart = _weekStart.add(const Duration(days: 7)),
            );
          },
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 520;
                if (!isMobile) {
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Weekly Calendar Grid',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 248, child: weekControls),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly Calendar Grid',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: weekControls),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap an empty cell to quick-add a 1-hour slot. Tap occupied cells to manage slots.',
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 100 + (days.length * 132),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _HeaderCell(label: 'Time', width: 100),
                        ...days.map(
                          (day) => _HeaderCell(
                            label: '${_weekdayLabel(day)} ${day.day}',
                            width: 132,
                          ),
                        ),
                      ],
                    ),
                    ..._gridHours.map((hour) {
                      return Row(
                        children: [
                          _TimeCell(hour: hour),
                          ...days.map((day) {
                            final cellSlots = _slotsForCell(
                              slots: slots,
                              day: day,
                              hour: hour,
                            );
                            return _CalendarCell(
                              width: 132,
                              color: _cellColor(cellSlots),
                              slotCount: cellSlots.length,
                              isBusy: cellSlots.isNotEmpty,
                              onTap: _isSaving
                                  ? null
                                  : () => _onCellTap(
                                      profile: profile,
                                      day: day,
                                      hour: hour,
                                      cellSlots: cellSlots,
                                    ),
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';

    return MindNestShell(
      maxWidth: 1100,
      appBar: AppBar(
        title: const Text('Manage Availability'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      child: profile == null || profile.role != UserRole.counselor
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('This page is available only for counselors.'),
              ),
            )
          : StreamBuilder<List<AvailabilitySlot>>(
              stream: ref
                  .read(careRepositoryProvider)
                  .watchCounselorSlots(
                    institutionId: institutionId,
                    counselorId: profile.id,
                  ),
              builder: (context, snapshot) {
                final slots = snapshot.data ?? const [];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Add Public Slot',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickDate,
                                  icon: const Icon(
                                    Icons.calendar_today_rounded,
                                  ),
                                  label: Text(
                                    _date == null
                                        ? 'Pick date'
                                        : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _pickStartTime,
                                  icon: const Icon(Icons.schedule_rounded),
                                  label: Text(
                                    _startTime == null
                                        ? 'Start time'
                                        : _startTime!.format(context),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _pickEndTime,
                                  icon: const Icon(Icons.schedule_send_rounded),
                                  label: Text(
                                    _endTime == null
                                        ? 'End time'
                                        : _endTime!.format(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _isSaving
                                  ? null
                                  : () => _saveSlot(profile),
                              child: Text(
                                _isSaving ? 'Saving...' : 'Publish slot',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildWeeklyGrid(profile, slots),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        slots.isEmpty)
                      const Center(child: CircularProgressIndicator())
                    else if (slots.isEmpty)
                      const GlassCard(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('No availability slots yet.'),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: slots
                            .map(
                              (slot) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: GlassCard(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _formatDateTime(slot.startAt),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                'Ends: ${_formatDateTime(slot.endAt)}',
                                              ),
                                              Text(
                                                'Status: ${slot.status.name}',
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (slot.status ==
                                            AvailabilitySlotStatus.available)
                                          IconButton(
                                            onPressed: () async {
                                              try {
                                                await ref
                                                    .read(
                                                      careRepositoryProvider,
                                                    )
                                                    .deleteAvailabilitySlot(
                                                      slot,
                                                    );
                                              } catch (error) {
                                                if (!context.mounted) {
                                                  return;
                                                }
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      error
                                                          .toString()
                                                          .replaceFirst(
                                                            'Exception: ',
                                                            '',
                                                          ),
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.hour});

  final int hour;

  String _label(int h) {
    final suffix = h >= 12 ? 'PM' : 'AM';
    final normalized = h == 0
        ? 12
        : h > 12
        ? h - 12
        : h;
    return '$normalized:00 $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Text(
        _label(hour),
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.width,
    required this.color,
    required this.slotCount,
    required this.isBusy,
    required this.onTap,
  });

  final double width;
  final Color color;
  final int slotCount;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 56,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: isBusy
                ? Text(
                    '$slotCount slot${slotCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : const Icon(
                    Icons.add_rounded,
                    color: Color(0xFF94A3B8),
                    size: 16,
                  ),
          ),
        ),
      ),
    );
  }
}
