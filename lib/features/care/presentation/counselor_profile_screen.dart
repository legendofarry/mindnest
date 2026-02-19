import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:mindnest/features/care/models/counselor_public_rating.dart';

enum _SpotPeriod { any, morning, afternoon, evening }

class CounselorProfileScreen extends ConsumerStatefulWidget {
  const CounselorProfileScreen({super.key, required this.counselorId});

  final String counselorId;

  @override
  ConsumerState<CounselorProfileScreen> createState() =>
      _CounselorProfileScreenState();
}

class _CounselorProfileScreenState
    extends ConsumerState<CounselorProfileScreen> {
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

  late DateTime _weekStart;
  DateTime? _selectedDay;
  _SpotPeriod _period = _SpotPeriod.any;

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

  List<DateTime> _weekDays() {
    return List<DateTime>.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
      growable: false,
    );
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

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final twoMonth = local.month.toString().padLeft(2, '0');
    final twoDay = local.day.toString().padLeft(2, '0');
    final twoHour = local.hour.toString().padLeft(2, '0');
    final twoMinute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$twoMonth-$twoDay $twoHour:$twoMinute';
  }

  String _periodLabel(_SpotPeriod period) {
    switch (period) {
      case _SpotPeriod.any:
        return 'Any time';
      case _SpotPeriod.morning:
        return 'Morning';
      case _SpotPeriod.afternoon:
        return 'Afternoon';
      case _SpotPeriod.evening:
        return 'Evening';
    }
  }

  bool _canCurrentUserBook(UserProfile? profile) {
    if (profile == null) {
      return false;
    }
    return profile.role == UserRole.student ||
        profile.role == UserRole.staff ||
        profile.role == UserRole.individual;
  }

  bool _matchesSpotFilters(AvailabilitySlot slot) {
    final start = slot.startAt.toLocal();
    if (_selectedDay != null) {
      final day = _selectedDay!;
      if (start.year != day.year ||
          start.month != day.month ||
          start.day != day.day) {
        return false;
      }
    }

    switch (_period) {
      case _SpotPeriod.any:
        return true;
      case _SpotPeriod.morning:
        return start.hour < 12;
      case _SpotPeriod.afternoon:
        return start.hour >= 12 && start.hour < 17;
      case _SpotPeriod.evening:
        return start.hour >= 17;
    }
  }

  List<AvailabilitySlot> _filterAndSortSlots(List<AvailabilitySlot> slots) {
    final filtered = slots
        .where((slot) => _matchesSpotFilters(slot))
        .toList(growable: false);
    filtered.sort((a, b) => a.startAt.compareTo(b.startAt));
    return filtered;
  }

  List<AvailabilitySlot> _weekSlots(List<AvailabilitySlot> slots) {
    final weekEnd = _weekStart.add(const Duration(days: 7));
    return slots
        .where((slot) {
          final local = slot.startAt.toLocal();
          return !local.isBefore(_weekStart) && local.isBefore(weekEnd);
        })
        .toList(growable: false);
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

  Future<void> _pickSpotDay() async {
    final now = DateTime.now();
    final initial = _selectedDay ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDay = picked);
    }
  }

  Future<void> _bookSlot({
    required CounselorProfile counselor,
    required AvailabilitySlot slot,
    required UserProfile currentProfile,
  }) async {
    final institutionId = currentProfile.institutionId ?? '';
    if (institutionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join an institution first.')),
      );
      return;
    }

    try {
      await ref
          .read(careRepositoryProvider)
          .bookCounselorSlot(
            institutionId: institutionId,
            counselor: counselor,
            slot: slot,
            currentProfile: currentProfile,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session booked successfully.')),
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

  double _averageRating(List<CounselorPublicRating> ratings) {
    if (ratings.isEmpty) {
      return 0;
    }
    final total = ratings.fold<int>(
      0,
      (runningTotal, entry) => runningTotal + entry.rating,
    );
    return total / ratings.length;
  }

  Future<void> _rateCounselorPublic({
    required List<AppointmentRecord> eligibleAppointments,
  }) async {
    if (eligibleAppointments.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete a session with this counselor to leave a public rating.',
          ),
        ),
      );
      return;
    }

    final commentController = TextEditingController();
    int selectedRating = 5;
    AppointmentRecord selectedAppointment = eligibleAppointments.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Rate Counselor (Public)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'This review is visible to students in your institution.',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedAppointment.id,
                      decoration: const InputDecoration(
                        labelText: 'Session',
                        prefixIcon: Icon(Icons.event_note_rounded),
                      ),
                      items: eligibleAppointments
                          .map(
                            (appointment) => DropdownMenuItem(
                              value: appointment.id,
                              child: Text(_formatDateTime(appointment.startAt)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        final match = eligibleAppointments.firstWhere(
                          (appointment) => appointment.id == value,
                        );
                        setState(() => selectedAppointment = match);
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      children: List<Widget>.generate(5, (index) {
                        final value = index + 1;
                        return IconButton(
                          onPressed: () =>
                              setState(() => selectedRating = value),
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
                      controller: commentController,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 250,
                      decoration: const InputDecoration(
                        labelText: 'Public comment (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Submit Review'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      commentController.dispose();
      return;
    }

    try {
      await ref
          .read(careRepositoryProvider)
          .submitCounselorPublicRating(
            appointment: selectedAppointment,
            rating: selectedRating,
            feedback: commentController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public counselor rating submitted.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      String message;
      if (error is FirebaseException) {
        message = error.message ?? error.code;
      } else {
        message = error.toString().replaceFirst('Exception: ', '');
        if (message.contains('Dart exception thrown from converted Future')) {
          message = 'Could not submit review right now. Please try again.';
        }
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      commentController.dispose();
    }
  }

  Future<void> _showCellSlots({
    required CounselorProfile counselor,
    required UserProfile? currentProfile,
    required List<AvailabilitySlot> cellSlots,
  }) async {
    final canBook = _canCurrentUserBook(currentProfile);
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
                  'Available Spots',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 10),
                ...cellSlots.map((slot) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_formatDateTime(slot.startAt)} - ${_formatDateTime(slot.endAt)}',
                          ),
                        ),
                        ElevatedButton(
                          onPressed: !canBook || currentProfile == null
                              ? null
                              : () async {
                                  Navigator.of(context).pop();
                                  await _bookSlot(
                                    counselor: counselor,
                                    slot: slot,
                                    currentProfile: currentProfile,
                                  );
                                },
                          child: const Text('Book'),
                        ),
                      ],
                    ),
                  );
                }),
                if (!canBook)
                  const Text(
                    'Only students, staff, and individual users can book sessions.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeeklyGrid({
    required CounselorProfile counselor,
    required List<AvailabilitySlot> slots,
    required UserProfile? profile,
  }) {
    final weekSlots = _weekSlots(slots);
    final days = _weekDays();
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                final isMobile = constraints.maxWidth < 560;
                if (!isMobile) {
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Counselor Weekly Schedule',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 250, child: weekControls),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Counselor Weekly Schedule',
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
              'Tap a highlighted cell to view available spots and book.',
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
                              slots: weekSlots,
                              day: day,
                              hour: hour,
                            );
                            return _ScheduleCell(
                              width: 132,
                              slots: cellSlots,
                              onTap: cellSlots.isEmpty
                                  ? null
                                  : () => _showCellSlots(
                                      counselor: counselor,
                                      currentProfile: profile,
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

  Widget _buildPendingCounselorHeader({
    required String institutionId,
    required String counselorId,
  }) {
    if (institutionId.isEmpty) {
      return const GlassCard(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Counselor profile setup is in progress.',
            style: TextStyle(color: Color(0xFF5E728D)),
          ),
        ),
      );
    }

    final firestore = ref.watch(firestoreProvider);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('institution_members')
          .doc('${institutionId}_$counselorId')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final displayName =
            (data?['userName'] as String?) ??
            (data?['name'] as String?) ??
            'Counselor';
        return GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text('Counselor profile setup in progress'),
                const SizedBox(height: 4),
                const Text(
                  'Basic scheduling is available while this profile is being completed.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final canBook = _canCurrentUserBook(profile);

    return MindNestShell(
      maxWidth: 1080,
      appBar: AppBar(
        title: const Text('Counselor Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          if (canBook)
            TextButton.icon(
              onPressed: () => context.go(AppRoute.studentAppointments),
              icon: const Icon(Icons.event_note_rounded),
              label: const Text('My Sessions'),
            ),
        ],
      ),
      child: StreamBuilder<CounselorProfile?>(
        stream: ref
            .read(careRepositoryProvider)
            .watchCounselorProfile(widget.counselorId),
        builder: (context, counselorSnapshot) {
          final profileReadDenied =
              counselorSnapshot.error is FirebaseException &&
              (counselorSnapshot.error as FirebaseException).code ==
                  'permission-denied';
          if (counselorSnapshot.hasError && !profileReadDenied) {
            return GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  counselorSnapshot.error.toString().replaceFirst(
                    'Exception: ',
                    '',
                  ),
                ),
              ),
            );
          }
          final counselor = counselorSnapshot.data;
          final effectiveCounselor =
              counselor ??
              CounselorProfile(
                id: widget.counselorId,
                institutionId: institutionId,
                displayName: 'Counselor',
                title: 'Counselor',
                specialization: 'Profile setup in progress',
                sessionMode: '--',
                timezone: 'UTC',
                bio: '',
                yearsExperience: 0,
                languages: const <String>[],
                ratingAverage: 0,
                ratingCount: 0,
                isActive: true,
              );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              counselor == null
                  ? _buildPendingCounselorHeader(
                      institutionId: institutionId,
                      counselorId: widget.counselorId,
                    )
                  : GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              counselor.displayName,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${counselor.title} - ${counselor.specialization}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${counselor.yearsExperience} years experience - ${counselor.sessionMode}',
                            ),
                            const SizedBox(height: 4),
                            Text('Timezone: ${counselor.timezone}'),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFF59E0B),
                                  size: 20,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${counselor.ratingAverage.toStringAsFixed(1)} (${counselor.ratingCount} ratings)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            if (counselor.languages.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Languages: ${counselor.languages.join(', ')}',
                              ),
                            ],
                            if (counselor.bio.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(counselor.bio),
                            ],
                          ],
                        ),
                      ),
                    ),
              const SizedBox(height: 12),
              const GlassCard(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Expectation: cancel/reschedule early when possible. Counselors should confirm sessions promptly and share updates if schedules change.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (institutionId.isNotEmpty)
                StreamBuilder<List<CounselorPublicRating>>(
                  stream: ref
                      .read(careRepositoryProvider)
                      .watchCounselorPublicRatings(
                        institutionId: institutionId,
                        counselorId: effectiveCounselor.id,
                      ),
                  builder: (context, publicRatingsSnapshot) {
                    final publicRatings =
                        publicRatingsSnapshot.data ?? const [];
                    final publicAverage = _averageRating(publicRatings);
                    final canLeavePublicRating =
                        profile?.role == UserRole.student;
                    final myRatedAppointments = profile == null
                        ? <String>{}
                        : publicRatings
                              .where((entry) => entry.studentId == profile.id)
                              .map((entry) => entry.appointmentId)
                              .toSet();

                    return GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Public Counselor Ratings',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              publicRatings.isEmpty
                                  ? 'No public ratings yet.'
                                  : 'Average: ${publicAverage.toStringAsFixed(1)} from ${publicRatings.length} ratings.',
                            ),
                            if (canLeavePublicRating) ...[
                              const SizedBox(height: 10),
                              StreamBuilder<List<AppointmentRecord>>(
                                stream: ref
                                    .read(careRepositoryProvider)
                                    .watchStudentAppointments(
                                      institutionId: institutionId,
                                      studentId: profile!.id,
                                    ),
                                builder: (context, appointmentSnapshot) {
                                  final eligible =
                                      (appointmentSnapshot.data ??
                                              const <AppointmentRecord>[])
                                          .where(
                                            (appointment) =>
                                                appointment.counselorId ==
                                                    effectiveCounselor.id &&
                                                appointment.status ==
                                                    AppointmentStatus
                                                        .completed &&
                                                !myRatedAppointments.contains(
                                                  appointment.id,
                                                ),
                                          )
                                          .toList(growable: false);
                                  eligible.sort(
                                    (a, b) => b.startAt.compareTo(a.startAt),
                                  );
                                  return ElevatedButton.icon(
                                    onPressed: eligible.isEmpty
                                        ? null
                                        : () => _rateCounselorPublic(
                                            eligibleAppointments: eligible,
                                          ),
                                    icon: const Icon(Icons.rate_review_rounded),
                                    label: Text(
                                      eligible.isEmpty
                                          ? 'No eligible session to rate publicly'
                                          : 'Rate Counselor Publicly',
                                    ),
                                  );
                                },
                              ),
                            ],
                            if (publicRatings.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ...publicRatings.take(5).map((rating) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.star_rounded,
                                              color: Color(0xFFF59E0B),
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              rating.rating.toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _formatDateTime(rating.createdAt),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (rating.feedback
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(rating.feedback.trim()),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              if (institutionId.isNotEmpty) const SizedBox(height: 12),
              if (institutionId.isEmpty)
                const GlassCard(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Join an institution to view and book counselor schedules.',
                    ),
                  ),
                )
              else
                StreamBuilder<List<AvailabilitySlot>>(
                  stream: ref
                      .read(careRepositoryProvider)
                      .watchCounselorPublicAvailability(
                        institutionId: institutionId,
                        counselorId: effectiveCounselor.id,
                      ),
                  builder: (context, availabilitySnapshot) {
                    if (availabilitySnapshot.hasError) {
                      return GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            availabilitySnapshot.error.toString().replaceFirst(
                              'Exception: ',
                              '',
                            ),
                          ),
                        ),
                      );
                    }

                    final slots = availabilitySnapshot.data ?? const [];
                    final filtered = _filterAndSortSlots(slots);

                    if (availabilitySnapshot.connectionState ==
                            ConnectionState.waiting &&
                        slots.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Find a Spot',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _pickSpotDay,
                                      icon: const Icon(
                                        Icons.calendar_today_rounded,
                                      ),
                                      label: Text(
                                        _selectedDay == null
                                            ? 'Any day'
                                            : '${_selectedDay!.year}-${_selectedDay!.month.toString().padLeft(2, '0')}-${_selectedDay!.day.toString().padLeft(2, '0')}',
                                      ),
                                    ),
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<_SpotPeriod>(
                                        value: _period,
                                        items: _SpotPeriod.values
                                            .map(
                                              (period) => DropdownMenuItem(
                                                value: period,
                                                child: Text(
                                                  _periodLabel(period),
                                                ),
                                              ),
                                            )
                                            .toList(growable: false),
                                        onChanged: (value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() => _period = value);
                                        },
                                      ),
                                    ),
                                    OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          _selectedDay = null;
                                          _period = _SpotPeriod.any;
                                        });
                                      },
                                      child: const Text('Clear filters'),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: filtered.isEmpty || !canBook
                                          ? null
                                          : () => _bookSlot(
                                              counselor: effectiveCounselor,
                                              slot: filtered.first,
                                              currentProfile: profile!,
                                            ),
                                      icon: const Icon(Icons.bolt_rounded),
                                      label: const Text('Book next available'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${filtered.length} matching spots found.',
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                if (!canBook)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Only students, staff, and individual users can book sessions.',
                                      style: TextStyle(
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildWeeklyGrid(
                          counselor: effectiveCounselor,
                          slots: slots,
                          profile: profile,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Available Spots',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        if (slots.isEmpty)
                          const GlassCard(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No public available slots yet.'),
                            ),
                          )
                        else if (filtered.isEmpty)
                          const GlassCard(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No available spots match the current filters.',
                              ),
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: filtered
                                .take(30)
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
                                                    _formatDateTime(
                                                      slot.startAt,
                                                    ),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Ends: ${_formatDateTime(slot.endAt)}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF64748B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            ElevatedButton(
                                              onPressed:
                                                  !canBook || profile == null
                                                  ? null
                                                  : () => _bookSlot(
                                                      counselor:
                                                          effectiveCounselor,
                                                      slot: slot,
                                                      currentProfile: profile,
                                                    ),
                                              child: const Text('Book'),
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

class _ScheduleCell extends StatelessWidget {
  const _ScheduleCell({
    required this.width,
    required this.slots,
    required this.onTap,
  });

  final double width;
  final List<AvailabilitySlot> slots;
  final VoidCallback? onTap;

  Color _background() {
    if (slots.isEmpty) {
      return Colors.white;
    }
    return const Color(0xFFEFFFFC);
  }

  @override
  Widget build(BuildContext context) {
    final count = slots.length;
    return Container(
      width: width,
      height: 56,
      decoration: BoxDecoration(
        color: _background(),
        border: Border.all(color: const Color(0xFFD9E4F0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: slots.isEmpty
                ? const Icon(
                    Icons.remove_rounded,
                    color: Color(0xFFB8C3D3),
                    size: 16,
                  )
                : Text(
                    '$count open',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E9B90),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
