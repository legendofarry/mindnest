import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/features/ai/data/assistant_providers.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class WellnessCheckInCard extends ConsumerStatefulWidget {
  const WellnessCheckInCard({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<WellnessCheckInCard> createState() =>
      _WellnessCheckInCardState();
}

class _WellnessCheckInCardState extends ConsumerState<WellnessCheckInCard> {
  bool _saving = false;
  bool _analyticsMode = false;
  bool _adviceLoading = false;
  _WellnessAnalyticsPeriod _period = _WellnessAnalyticsPeriod.weekly;
  _WellnessChartType _chartType = _WellnessChartType.bar;
  String? _adviceText;
  String _adviceResolvedKey = '';
  String _adviceInFlightKey = '';

  static const List<_MoodChoice> _moods = <_MoodChoice>[
    _MoodChoice(
      key: 'great',
      emoji: '\u{1F600}',
      label: 'Great',
      color: Color(0xFF10B981),
    ),
    _MoodChoice(
      key: 'good',
      emoji: '\u{1F642}',
      label: 'Good',
      color: Color(0xFF22C55E),
    ),
    _MoodChoice(
      key: 'okay',
      emoji: '\u{1F610}',
      label: 'Okay',
      color: Color(0xFFF59E0B),
    ),
    _MoodChoice(
      key: 'low',
      emoji: '\u{1F614}',
      label: 'Low',
      color: Color(0xFFF97316),
    ),
    _MoodChoice(
      key: 'stressed',
      emoji: '\u{1F623}',
      label: 'Stressed',
      color: Color(0xFFEF4444),
    ),
  ];

  static const Map<String, int> _moodScore = <String, int>{
    'great': 5,
    'good': 4,
    'okay': 3,
    'low': 2,
    'stressed': 1,
  };

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  IconData _energyIcon(int level) {
    switch (level) {
      case 1:
        return Icons.battery_1_bar_rounded;
      case 2:
        return Icons.battery_2_bar_rounded;
      case 3:
        return Icons.battery_3_bar_rounded;
      case 4:
        return Icons.battery_4_bar_rounded;
      default:
        return Icons.battery_full_rounded;
    }
  }

  _MoodChoice _resolveMood(String? key) {
    return _moods.firstWhere(
      (entry) => entry.key == key,
      orElse: () => _moods[2],
    );
  }

  Future<void> _save({required String mood, required int energy}) async {
    final userId = widget.profile.id.trim();
    if (userId.isEmpty || _saving) {
      return;
    }

    final firestore = ref.read(firestoreProvider);
    final todayKey = _dateKey(DateTime.now());
    final docId = '${userId}_$todayKey';

    setState(() => _saving = true);
    try {
      await firestore.collection('mood_entries').doc(docId).set({
        'userId': userId,
        'dateKey': todayKey,
        'mood': mood,
        'energy': energy.clamp(1, 5),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await firestore.collection('mood_events').add({
        'userId': userId,
        'dateKey': todayKey,
        'mood': mood,
        'energy': energy.clamp(1, 5),
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
      });
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
        setState(() => _saving = false);
      }
    }
  }

  List<_WellnessEvent> _parseEvents(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = <_WellnessEvent>[];
    for (final doc in docs) {
      final data = doc.data();
      final mood = ((data['mood'] as String?) ?? 'okay').trim().toLowerCase();
      final energyRaw = data['energy'];
      final energy = energyRaw is int ? energyRaw.clamp(1, 5) : 3;
      final createdAtRaw = data['createdAt'];
      final clientCreatedAtRaw = data['clientCreatedAt'];
      DateTime? timestamp;
      if (createdAtRaw is Timestamp) {
        timestamp = createdAtRaw.toDate().toUtc();
      } else if (clientCreatedAtRaw is Timestamp) {
        timestamp = clientCreatedAtRaw.toDate().toUtc();
      }
      if (timestamp == null) {
        continue;
      }
      out.add(_WellnessEvent(timestamp: timestamp, mood: mood, energy: energy));
    }
    return out;
  }

  _WellnessAnalyticsSummary _summarizeEvents(
    List<_WellnessEvent> events,
    _WellnessAnalyticsPeriod period,
  ) {
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(period.duration);
    final scoped = events.where((entry) => !entry.timestamp.isBefore(cutoff));

    final moodCounts = <String, int>{for (final mood in _moods) mood.key: 0};
    final energyCounts = <int, int>{
      for (var level = 1; level <= 5; level++) level: 0,
    };

    var totalEnergy = 0.0;
    var totalMoodScore = 0.0;
    var count = 0;

    for (final entry in scoped) {
      moodCounts[entry.mood] = (moodCounts[entry.mood] ?? 0) + 1;
      energyCounts[entry.energy] = (energyCounts[entry.energy] ?? 0) + 1;
      totalEnergy += entry.energy;
      totalMoodScore += (_moodScore[entry.mood] ?? 3);
      count++;
    }

    final trend = _buildTrend(events: events, period: period, now: now);

    if (count == 0) {
      return _WellnessAnalyticsSummary(
        period: period,
        totalEvents: 0,
        moodCounts: moodCounts,
        energyCounts: energyCounts,
        averageEnergy: 0,
        averageMoodScore: 0,
        trendLabels: trend.$1,
        trendValues: trend.$2,
      );
    }

    String? topMood;
    var topMoodCount = 0;
    for (final entry in moodCounts.entries) {
      if (entry.value > topMoodCount) {
        topMood = entry.key;
        topMoodCount = entry.value;
      }
    }

    int? topEnergy;
    var topEnergyCount = 0;
    for (final entry in energyCounts.entries) {
      if (entry.value > topEnergyCount) {
        topEnergy = entry.key;
        topEnergyCount = entry.value;
      }
    }

    return _WellnessAnalyticsSummary(
      period: period,
      totalEvents: count,
      moodCounts: moodCounts,
      energyCounts: energyCounts,
      averageEnergy: totalEnergy / count,
      averageMoodScore: totalMoodScore / count,
      topMoodKey: topMood,
      topEnergy: topEnergy,
      trendLabels: trend.$1,
      trendValues: trend.$2,
    );
  }

  (List<String>, List<double>) _buildTrend({
    required List<_WellnessEvent> events,
    required _WellnessAnalyticsPeriod period,
    required DateTime now,
  }) {
    DateTime start;
    Duration step;
    int bucketCount;

    switch (period) {
      case _WellnessAnalyticsPeriod.last3Hours:
        start = now.subtract(const Duration(hours: 3));
        step = const Duration(minutes: 30);
        bucketCount = 6;
      case _WellnessAnalyticsPeriod.last12Hours:
        start = now.subtract(const Duration(hours: 12));
        step = const Duration(hours: 1);
        bucketCount = 12;
      case _WellnessAnalyticsPeriod.daily:
        start = now.subtract(const Duration(hours: 24));
        step = const Duration(hours: 3);
        bucketCount = 8;
      case _WellnessAnalyticsPeriod.weekly:
        start = now.subtract(const Duration(days: 7));
        step = const Duration(days: 1);
        bucketCount = 7;
    }

    final sums = List<double>.filled(bucketCount, 0);
    final counts = List<int>.filled(bucketCount, 0);

    for (final entry in events) {
      if (entry.timestamp.isBefore(start) || entry.timestamp.isAfter(now)) {
        continue;
      }
      final delta = entry.timestamp.difference(start);
      final index = delta.inMilliseconds ~/ step.inMilliseconds;
      if (index < 0 || index >= bucketCount) {
        continue;
      }
      sums[index] += entry.energy;
      counts[index] += 1;
    }

    final labels = <String>[];
    final values = <double>[];
    const dayLetter = <int, String>{
      DateTime.monday: 'M',
      DateTime.tuesday: 'T',
      DateTime.wednesday: 'W',
      DateTime.thursday: 'T',
      DateTime.friday: 'F',
      DateTime.saturday: 'S',
      DateTime.sunday: 'S',
    };

    for (var i = 0; i < bucketCount; i++) {
      final bucketStart = start.add(step * i).toLocal();
      switch (period) {
        case _WellnessAnalyticsPeriod.last3Hours:
          labels.add(
            '${bucketStart.hour.toString().padLeft(2, '0')}:${bucketStart.minute.toString().padLeft(2, '0')}',
          );
        case _WellnessAnalyticsPeriod.last12Hours:
          labels.add('${bucketStart.hour.toString().padLeft(2, '0')}h');
        case _WellnessAnalyticsPeriod.daily:
          labels.add('${bucketStart.hour.toString().padLeft(2, '0')}h');
        case _WellnessAnalyticsPeriod.weekly:
          labels.add(dayLetter[bucketStart.weekday] ?? '-');
      }
      values.add(counts[i] == 0 ? 0 : (sums[i] / counts[i]));
    }

    return (labels, values);
  }

  void _queueAdviceUpdate(_WellnessAnalyticsSummary summary) {
    final key = '${summary.period.name}:${summary.signature}';
    if (summary.totalEvents == 0) {
      if (_adviceLoading ||
          _adviceText != null ||
          _adviceResolvedKey.isNotEmpty ||
          _adviceInFlightKey.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _adviceLoading = false;
            _adviceText = null;
            _adviceResolvedKey = '';
            _adviceInFlightKey = '';
          });
        });
      }
      return;
    }

    if (key == _adviceResolvedKey || key == _adviceInFlightKey) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _adviceInFlightKey = key;
        _adviceLoading = true;
      });
      _generateAdvice(summary)
          .then((message) {
            if (!mounted || _adviceInFlightKey != key) {
              return;
            }
            setState(() {
              _adviceText = message;
              _adviceLoading = false;
              _adviceResolvedKey = key;
              _adviceInFlightKey = '';
            });
          })
          .catchError((_) {
            if (!mounted || _adviceInFlightKey != key) {
              return;
            }
            setState(() {
              _adviceText = _fallbackAdvice(summary);
              _adviceLoading = false;
              _adviceResolvedKey = key;
              _adviceInFlightKey = '';
            });
          });
    });
  }

  Future<String> _generateAdvice(_WellnessAnalyticsSummary summary) async {
    final topMood = summary.topMoodKey == null
        ? 'unknown'
        : _resolveMood(summary.topMoodKey).label.toLowerCase();
    final topEnergy = summary.topEnergy?.toString() ?? '-';
    final prompt =
        'Write one short caring and playful wellness note (max 28 words). '
        'Period: ${summary.period.label}. '
        'Top mood: $topMood. '
        'Average energy: ${summary.averageEnergy.toStringAsFixed(1)} out of 5. '
        'Most selected energy: $topEnergy. '
        'Include one tiny practical tip.';
    final reply = await ref
        .read(assistantRepositoryProvider)
        .processPrompt(prompt: prompt, profile: widget.profile);
    final text = reply.text.trim();
    final lower = text.toLowerCase();
    if (text.isEmpty ||
        lower.contains('not configured') ||
        lower.contains('unavailable') ||
        lower.contains('timed out')) {
      return _fallbackAdvice(summary);
    }
    return text;
  }

  String _fallbackAdvice(_WellnessAnalyticsSummary summary) {
    final moodKey = summary.topMoodKey ?? 'okay';
    final avgEnergy = summary.averageEnergy;
    if (moodKey == 'great' || moodKey == 'good') {
      return avgEnergy >= 3.8
          ? 'You are riding a strong wave today. Keep that spark going with a short walk and one thing you are grateful for.'
          : 'Your mood is positive. Add a small recharge break so your energy can keep up with your momentum.';
    }
    if (moodKey == 'okay') {
      return 'You are steady. A tiny reset, like water plus five deep breaths, can shift your day from okay to better.';
    }
    if (moodKey == 'low') {
      return 'Low days happen. Be gentle with yourself, pick one easy win, and reach out to someone you trust if the heaviness stays.';
    }
    return 'Stress is loud right now. Try a 60-second pause, unclench your shoulders, and do one small task. You are doing better than you think.';
  }

  List<_MoodBarPoint> _moodBars(_WellnessAnalyticsSummary summary) {
    return _moods
        .map(
          (entry) => _MoodBarPoint(
            label: entry.label,
            value: summary.moodCounts[entry.key] ?? 0,
            color: entry.color,
          ),
        )
        .toList(growable: false);
  }

  Widget _buildBaseContent({
    required _MoodChoice selectedMood,
    required int selectedEnergy,
    required Color headingColor,
    required Color mutedColor,
    required Color borderColor,
    required Color selectedBg,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF0E9B90).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.self_improvement_rounded,
                size: 18,
                color: Color(0xFF0E9B90),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Wellness Check-in',
              style: TextStyle(
                color: headingColor,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            if (_saving)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF0E9B90),
                ),
              ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Open analytics',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _analyticsMode = true),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    size: 18,
                    color: Color(0xFF0E9B90),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Daily check-in. Update anytime today.',
          style: TextStyle(
            color: mutedColor,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Mood',
          style: TextStyle(
            color: headingColor,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _moods
              .map((entry) {
                final selected = selectedMood.key == entry.key;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _save(mood: entry.key, energy: selectedEnergy),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? selectedBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? entry.color
                              : borderColor.withValues(alpha: 0.85),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.emoji,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            entry.label,
                            style: TextStyle(
                              color: selected ? entry.color : mutedColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        Text(
          'Energy',
          style: TextStyle(
            color: headingColor,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List<Widget>.generate(5, (index) {
            final level = index + 1;
            final selected = level <= selectedEnergy;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _save(mood: selectedMood.key, energy: level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: selected ? selectedBg : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF0E9B90)
                            : borderColor.withValues(alpha: 0.85),
                      ),
                    ),
                    child: Icon(
                      _energyIcon(level),
                      size: 18,
                      color: selected ? const Color(0xFF0E9B90) : mutedColor,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildAnalyticsContent({
    required FirebaseFirestore firestore,
    required String userId,
    required bool isDark,
    required Color borderColor,
    required Color headingColor,
    required Color mutedColor,
    required Color selectedBg,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('mood_events')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        final events = _parseEvents(snapshot.data?.docs ?? const []);
        final summary = _summarizeEvents(events, _period);
        _queueAdviceUpdate(summary);
        final topMood = summary.topMoodKey == null
            ? null
            : _resolveMood(summary.topMoodKey);

        final chartWidget = summary.totalEvents == 0
            ? Center(
                child: Text(
                  'No analytics data yet. Keep checking in to unlock trends.',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : switch (_chartType) {
                _WellnessChartType.line => _WellnessTrendChart(
                  labels: summary.trendLabels,
                  values: summary.trendValues,
                  color: const Color(0xFF0E9B90),
                  mutedColor: mutedColor,
                ),
                _WellnessChartType.area => _WellnessTrendChart(
                  labels: summary.trendLabels,
                  values: summary.trendValues,
                  color: const Color(0xFF0E9B90),
                  mutedColor: mutedColor,
                  area: true,
                ),
                _WellnessChartType.bar => _WellnessBarChart(
                  labels: summary.trendLabels,
                  values: summary.trendValues,
                  color: const Color(0xFF0E9B90),
                  mutedColor: mutedColor,
                ),
                _WellnessChartType.pie => _WellnessPieChart(
                  points: _moodBars(summary),
                  mutedColor: mutedColor,
                ),
              };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E9B90).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    size: 18,
                    color: Color(0xFF0E9B90),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Wellness Analytics',
                  style: TextStyle(
                    color: headingColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _analyticsMode = false),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 19,
                      color: headingColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'See your patterns by period and chart style.',
              style: TextStyle(
                color: mutedColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _WellnessAnalyticsPeriod.values
                  .map(
                    (period) => ChoiceChip(
                      label: Text(period.shortLabel),
                      selected: _period == period,
                      onSelected: (_) => setState(() => _period = period),
                      selectedColor: selectedBg,
                      side: BorderSide(
                        color: _period == period
                            ? const Color(0xFF0E9B90)
                            : borderColor,
                      ),
                      labelStyle: TextStyle(
                        color: _period == period
                            ? const Color(0xFF0E9B90)
                            : mutedColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _WellnessChartType.values
                    .map(
                      (kind) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(
                            kind.icon,
                            size: 15,
                            color: _chartType == kind
                                ? const Color(0xFF0E9B90)
                                : mutedColor,
                          ),
                          label: Text(kind.label),
                          selected: _chartType == kind,
                          onSelected: (_) => setState(() => _chartType = kind),
                          selectedColor: selectedBg,
                          side: BorderSide(
                            color: _chartType == kind
                                ? const Color(0xFF0E9B90)
                                : borderColor,
                          ),
                          labelStyle: TextStyle(
                            color: _chartType == kind
                                ? const Color(0xFF0E9B90)
                                : mutedColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _AnalyticsStatTile(
                    label: 'Top mood',
                    value: topMood == null
                        ? '--'
                        : '${topMood.emoji} ${topMood.label}',
                    accent: topMood?.color ?? const Color(0xFF94A3B8),
                    borderColor: borderColor,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AnalyticsStatTile(
                    label: 'Top energy',
                    value: summary.topEnergy == null
                        ? '--'
                        : '${summary.topEnergy}/5',
                    accent: const Color(0xFF0E9B90),
                    borderColor: borderColor,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AnalyticsStatTile(
                    label: 'Avg mood',
                    value: summary.totalEvents == 0
                        ? '--'
                        : summary.averageMoodScore.toStringAsFixed(1),
                    accent: const Color(0xFF7C3AED),
                    borderColor: borderColor,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 170),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF101B2D)
                    : const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: chartWidget,
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF102437)
                    : const Color(0xFFE9F8F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF0E9B90).withValues(alpha: 0.32),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.tips_and_updates_rounded,
                      size: 18,
                      color: Color(0xFF0E9B90),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _adviceLoading
                        ? Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF0E9B90),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Creating your personalized check-in message...',
                                  style: TextStyle(
                                    color: mutedColor,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            _adviceText ??
                                (summary.totalEvents == 0
                                    ? 'Check in a few times and I will generate a personalized wellness insight here.'
                                    : _fallbackAdvice(summary)),
                            style: TextStyle(
                              color: headingColor,
                              fontSize: 12.8,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userId = widget.profile.id.trim();

    final cardColor = isDark ? const Color(0xFF151F31) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2A3A52)
        : const Color(0xFFDDE6F1);
    final headingColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF0F172A);
    final mutedColor = isDark
        ? const Color(0xFF9FB2CC)
        : const Color(0xFF64748B);
    final selectedBg = isDark
        ? const Color(0xFF1F2D44)
        : const Color(0xFFEAF2FB);

    if (userId.isEmpty) {
      return const SizedBox.shrink();
    }

    final firestore = ref.read(firestoreProvider);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('mood_entries')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        final byDate = <String, _WellnessEntry>{};
        for (final doc in snapshot.data?.docs ?? const []) {
          final data = doc.data();
          final key = (data['dateKey'] as String?) ?? '';
          if (key.isEmpty) {
            continue;
          }
          final moodKey = (data['mood'] as String?) ?? 'okay';
          final energyRaw = data['energy'];
          final energy = energyRaw is int ? energyRaw.clamp(1, 5) : 3;
          byDate[key] = _WellnessEntry(
            dateKey: key,
            mood: moodKey,
            energy: energy,
          );
        }

        final todayKey = _dateKey(DateTime.now());
        final today = byDate[todayKey];
        final selectedMood = _resolveMood(today?.mood);
        final selectedEnergy = today?.energy ?? 3;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0x120F172A))
                    .withValues(alpha: isDark ? 0.22 : 0.07),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _analyticsMode
              ? _buildAnalyticsContent(
                  firestore: firestore,
                  userId: userId,
                  isDark: isDark,
                  borderColor: borderColor,
                  headingColor: headingColor,
                  mutedColor: mutedColor,
                  selectedBg: selectedBg,
                )
              : _buildBaseContent(
                  selectedMood: selectedMood,
                  selectedEnergy: selectedEnergy,
                  headingColor: headingColor,
                  mutedColor: mutedColor,
                  borderColor: borderColor,
                  selectedBg: selectedBg,
                ),
        );
      },
    );
  }
}

class _AnalyticsStatTile extends StatelessWidget {
  const _AnalyticsStatTile({
    required this.label,
    required this.value,
    required this.accent,
    required this.borderColor,
    required this.isDark,
  });

  final String label;
  final String value;
  final Color accent;
  final Color borderColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111D2F) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? const Color(0xFF9FB2CC) : const Color(0xFF64748B),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WellnessTrendChart extends StatelessWidget {
  const _WellnessTrendChart({
    required this.labels,
    required this.values,
    required this.color,
    required this.mutedColor,
    this.area = false,
  });

  final List<String> labels;
  final List<double> values;
  final Color color;
  final Color mutedColor;
  final bool area;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 125,
          width: double.infinity,
          child: CustomPaint(
            painter: _WellnessTrendPainter(
              values: values,
              color: color,
              gridColor: mutedColor.withValues(alpha: 0.18),
              area: area,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: labels
              .map(
                (label) => Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _WellnessTrendPainter extends CustomPainter {
  _WellnessTrendPainter({
    required this.values,
    required this.color,
    required this.gridColor,
    required this.area,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;
  final bool area;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }

    const pad = 8.0;
    final chartRect = Rect.fromLTWH(
      pad,
      pad,
      size.width - (pad * 2),
      size.height - (pad * 2),
    );
    final maxValue = math.max(
      5.0,
      values.fold<double>(0, (max, entry) => math.max(max, entry)),
    );

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chartRect.top + (chartRect.height * i / 4);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? chartRect.center.dx
          : chartRect.left + (chartRect.width * i / (values.length - 1));
      final normalized = (values[i] / maxValue).clamp(0.0, 1.0);
      final y = chartRect.bottom - (chartRect.height * normalized);
      points.add(Offset(x, y));
    }
    if (points.isEmpty) {
      return;
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    if (area) {
      final fillPath = Path.from(linePath)
        ..lineTo(points.last.dx, chartRect.bottom)
        ..lineTo(points.first.dx, chartRect.bottom)
        ..close();
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.30),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(chartRect);
      canvas.drawPath(fillPath, fillPaint);
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.4;
    canvas.drawPath(linePath, linePaint);

    final pointPaint = Paint()..color = color;
    final pointOuterPaint = Paint()..color = Colors.white;
    for (final point in points) {
      canvas.drawCircle(point, 3.5, pointOuterPaint);
      canvas.drawCircle(point, 2, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WellnessTrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.area != area ||
        oldDelegate.gridColor != gridColor;
  }
}

class _WellnessBarChart extends StatelessWidget {
  const _WellnessBarChart({
    required this.labels,
    required this.values,
    required this.color,
    required this.mutedColor,
  });

  final List<String> labels;
  final List<double> values;
  final Color color;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    final maxValue = math.max(
      5.0,
      values.fold<double>(0, (max, entry) => math.max(max, entry)),
    );
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(values.length, (index) {
          final ratio = (values[index] / maxValue).clamp(0.0, 1.0);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: 8 + (92 * ratio),
                    decoration: BoxDecoration(
                      color: color.withValues(
                        alpha: values[index] == 0 ? 0.22 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _WellnessPieChart extends StatelessWidget {
  const _WellnessPieChart({required this.points, required this.mutedColor});

  final List<_MoodBarPoint> points;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: CustomPaint(
            painter: _WellnessPiePainter(
              points: points,
              mutedColor: mutedColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            runSpacing: 8,
            spacing: 8,
            children: points
                .where((entry) => entry.value > 0)
                .map(
                  (entry) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: entry.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: entry.color.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      '${entry.label} ${entry.value}',
                      style: TextStyle(
                        color: entry.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _WellnessPiePainter extends CustomPainter {
  _WellnessPiePainter({required this.points, required this.mutedColor});

  final List<_MoodBarPoint> points;
  final Color mutedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) / 2) - 5;
    final total = points.fold<int>(
      0,
      (currentTotal, entry) => currentTotal + entry.value,
    );

    if (total <= 0) {
      final basePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = mutedColor.withValues(alpha: 0.20);
      canvas.drawCircle(center, radius, basePaint);
      return;
    }

    var start = -math.pi / 2;
    for (final entry in points) {
      if (entry.value <= 0) {
        continue;
      }
      final sweep = (entry.value / total) * (math.pi * 2);
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 12
        ..color = entry.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        arcPaint,
      );
      start += sweep;
    }

    final holePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawCircle(center, radius - 10, holePaint);
  }

  @override
  bool shouldRepaint(covariant _WellnessPiePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.mutedColor != mutedColor;
  }
}

class _MoodChoice {
  const _MoodChoice({
    required this.key,
    required this.emoji,
    required this.label,
    required this.color,
  });

  final String key;
  final String emoji;
  final String label;
  final Color color;
}

class _WellnessEntry {
  const _WellnessEntry({
    required this.dateKey,
    required this.mood,
    required this.energy,
  });

  final String dateKey;
  final String mood;
  final int energy;
}

class _WellnessEvent {
  const _WellnessEvent({
    required this.timestamp,
    required this.mood,
    required this.energy,
  });

  final DateTime timestamp;
  final String mood;
  final int energy;
}

class _MoodBarPoint {
  const _MoodBarPoint({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

enum _WellnessAnalyticsPeriod { last3Hours, last12Hours, daily, weekly }

extension on _WellnessAnalyticsPeriod {
  String get label {
    switch (this) {
      case _WellnessAnalyticsPeriod.last3Hours:
        return 'Last 3 hours';
      case _WellnessAnalyticsPeriod.last12Hours:
        return 'Last 12 hours';
      case _WellnessAnalyticsPeriod.daily:
        return 'Last 24 hours';
      case _WellnessAnalyticsPeriod.weekly:
        return 'Last 7 days';
    }
  }

  String get shortLabel {
    switch (this) {
      case _WellnessAnalyticsPeriod.last3Hours:
        return '3h';
      case _WellnessAnalyticsPeriod.last12Hours:
        return '12h';
      case _WellnessAnalyticsPeriod.daily:
        return 'Daily';
      case _WellnessAnalyticsPeriod.weekly:
        return 'Weekly';
    }
  }

  Duration get duration {
    switch (this) {
      case _WellnessAnalyticsPeriod.last3Hours:
        return const Duration(hours: 3);
      case _WellnessAnalyticsPeriod.last12Hours:
        return const Duration(hours: 12);
      case _WellnessAnalyticsPeriod.daily:
        return const Duration(hours: 24);
      case _WellnessAnalyticsPeriod.weekly:
        return const Duration(days: 7);
    }
  }
}

enum _WellnessChartType { line, bar, pie, area }

extension on _WellnessChartType {
  String get label {
    switch (this) {
      case _WellnessChartType.line:
        return 'Line';
      case _WellnessChartType.bar:
        return 'Bar';
      case _WellnessChartType.pie:
        return 'Pie';
      case _WellnessChartType.area:
        return 'Area';
    }
  }

  IconData get icon {
    switch (this) {
      case _WellnessChartType.line:
        return Icons.show_chart_rounded;
      case _WellnessChartType.bar:
        return Icons.bar_chart_rounded;
      case _WellnessChartType.pie:
        return Icons.pie_chart_rounded;
      case _WellnessChartType.area:
        return Icons.area_chart_rounded;
    }
  }
}

class _WellnessAnalyticsSummary {
  const _WellnessAnalyticsSummary({
    required this.period,
    required this.totalEvents,
    required this.moodCounts,
    required this.energyCounts,
    required this.averageEnergy,
    required this.averageMoodScore,
    required this.trendLabels,
    required this.trendValues,
    this.topMoodKey,
    this.topEnergy,
  });

  final _WellnessAnalyticsPeriod period;
  final int totalEvents;
  final Map<String, int> moodCounts;
  final Map<int, int> energyCounts;
  final double averageEnergy;
  final double averageMoodScore;
  final String? topMoodKey;
  final int? topEnergy;
  final List<String> trendLabels;
  final List<double> trendValues;

  String get signature {
    final moodSig = moodCounts.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join('|');
    final energySig = energyCounts.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join('|');
    final trendSig = trendValues
        .map((entry) => entry.toStringAsFixed(2))
        .join(',');
    return '$moodSig#$energySig#$trendSig#${averageEnergy.toStringAsFixed(2)}#${averageMoodScore.toStringAsFixed(2)}';
  }
}
