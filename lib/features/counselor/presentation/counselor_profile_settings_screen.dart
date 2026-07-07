// ignore_for_file: unnecessary_string_interpolations, deprecated_member_use

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/no_scrollbar_scroll_behavior.dart';
import 'package:mindnest/core/ui/modern_banner.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/account_export_sheet.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/auth/presentation/passkey_management_dialog.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:mindnest/features/care/presentation/notification_center_screen.dart';
import 'package:mindnest/features/counselor/data/counselor_providers.dart';
import 'package:mindnest/features/counselor/models/counselor_language_catalog.dart';
import 'package:mindnest/features/counselor/presentation/counselor_workspace_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

// =============================================================================
// Public API — unchanged: router uses this section enum + constructor.
// =============================================================================

enum CounselorProfileSettingsSection {
  identity,
  professionalDetails,
  specializations,
  languages,
  bio,
  sessionRhythm,
  passwordSignIn,
  privacyData,
}

// =============================================================================
// Design tokens — one place, one language.
// =============================================================================

class _T {
  // Surfaces
  static const bg = Color(0xFF080E19);
  static const surface = Color(0xFF10192A);
  static const surfaceInput = Color(0xFF0F1A2C);
  static const hairline = Color(0x14FFFFFF);

  // Text
  static const text = Color(0xFFF3F6FB);
  static const textMuted = Color(0xFF9AAAC1);
  static const textFaint = Color(0xFF6D7F97);

  // Primary brand
  static const brand = Color(0xFF13D0C7);

  // Motion
  static const dEnter = Duration(milliseconds: 480);
  static const dQuick = Duration(milliseconds: 220);
  static const dPage = Duration(milliseconds: 420);
  static const easeOut = Cubic(0.16, 1.0, 0.3, 1.0); // out-expo-ish
}

// =============================================================================
// Screen
// =============================================================================

class CounselorProfileSettingsScreen extends ConsumerStatefulWidget {
  const CounselorProfileSettingsScreen({
    super.key,
    this.initialSection = CounselorProfileSettingsSection.identity,
    this.embeddedInCounselorShell = false,
  });

  final CounselorProfileSettingsSection initialSection;
  final bool embeddedInCounselorShell;

  @override
  ConsumerState<CounselorProfileSettingsScreen> createState() =>
      _CounselorProfileSettingsScreenState();
}

class _CounselorProfileSettingsScreenState
    extends ConsumerState<CounselorProfileSettingsScreen> {
  // ---- form controllers ------------------------------------------------------
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _years = TextEditingController();
  final _bio = TextEditingController();
  final _search = TextEditingController();

  bool _seeded = false;

  // ---- editable model --------------------------------------------------------
  Set<String> _specializations = {_specs.first};
  String _mode = 'Hybrid';
  String _timezone = 'Africa/Nairobi';
  bool _active = true;
  int _duration = 50;
  int _breakMins = 10;
  bool _direct = true;
  bool _followUps = false;
  Set<int> _workingWeekdays = {1, 2, 3, 4, 5};
  int _workingDayStartMinutes = 7 * 60;
  int _workingDayEndMinutes = 20 * 60;
  bool _lunchBreakEnabled = false;
  int _lunchBreakStartMinutes = 12 * 60 + 30;
  int _lunchBreakEndMinutes = 13 * 60;

  bool _savingProfile = false;
  bool _sendingReset = false;
  String _query = '';

  Set<String>? _languages;

  // Ensures we push the deep-linked detail only once.
  bool _deepLinkHandled = false;

  static const _specs = <String>[
    'Academic Stress',
    'Career Guidance',
    'Anxiety',
    'Depression',
    'Relationship Issues',
    'Family Problems',
    'Self-Esteem',
    'Trauma',
    'Substance Abuse',
    'Bullying',
    'Grief & Loss',
  ];
  static const _modes = <String>['In-person', 'Online', 'Hybrid'];
  static const _zones = <String>[
    'UTC',
    'Africa/Nairobi',
    'Europe/London',
    'America/New_York',
    'America/Los_Angeles',
    'Asia/Dubai',
  ];
  static const _durations = <int>[30, 45, 50, 60, 75, 90];

  @override
  void initState() {
    super.initState();
    assert(() {
      debugPaintBaselinesEnabled = false;
      debugPaintSizeEnabled = false;
      debugPaintPointersEnabled = false;
      debugPaintLayerBordersEnabled = false;
      return true;
    }());
    _search.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _search.removeListener(_handleSearchChanged);
    _search.dispose();
    _name.dispose();
    _title.dispose();
    _years.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (_query == _search.text) return;
    setState(() => _query = _search.text);
  }

  void _clearSearch() {
    if (_search.text.isEmpty) return;
    _search.clear();
  }

  List<int> _parseIntList(dynamic raw) {
    if (raw is! List) {
      return const <int>[];
    }
    final values = <int>[];
    for (final entry in raw) {
      final parsed = entry is num
          ? entry.toInt()
          : int.tryParse(entry.toString().trim());
      if (parsed != null &&
          parsed >= DateTime.monday &&
          parsed <= DateTime.sunday) {
        values.add(parsed);
      }
    }
    values.sort();
    return values;
  }

  String _formatMinutesOfDay(int minutes) {
    final normalized = minutes.clamp(0, 24 * 60).toInt();
    final hour24 = normalized ~/ 60;
    final minute = normalized % 60;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:${minute.toString().padLeft(2, '0')} $suffix';
  }

  String _weekdayShort(int weekday) {
    const labels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[weekday - 1];
  }

  String _weekdayRangeLabel() {
    final sorted = [..._workingWeekdays]..sort();
    if (sorted.isEmpty) {
      return 'No working days selected';
    }
    final labels = sorted.map(_weekdayShort).toList(growable: false);
    if (labels.length == 1) {
      return labels.first;
    }
    if (labels.length == 2) {
      return '${labels.first} and ${labels.last}';
    }
    return '${labels.take(labels.length - 1).join(', ')} and ${labels.last}';
  }

  String _scheduleSummary() {
    final lunch = _lunchBreakEnabled
        ? 'Lunch ${_formatMinutesOfDay(_lunchBreakStartMinutes)}-${_formatMinutesOfDay(_lunchBreakEndMinutes)}'
        : 'No lunch break';
    return '${_weekdayRangeLabel()} · ${_formatMinutesOfDay(_workingDayStartMinutes)}-${_formatMinutesOfDay(_workingDayEndMinutes)} · $_duration min sessions · $_breakMins min breaks · $lunch';
  }

  // ---- data seeding ---------------------------------------------------------
  void _seed(UserProfile profile, CounselorProfile? cp) {
    if (_seeded) return;
    final setup = profile.counselorSetupData;
    final prefs = profile.counselorPreferences;

    _name.text = cp?.displayName ?? profile.name;
    _title.text = cp?.title ?? (setup['title'] as String? ?? '');
    _years.text =
        ((cp?.yearsExperience ??
                (setup['yearsExperience'] as num?)?.toInt() ??
                0))
            .toString();

    final langs = cp?.languages.isNotEmpty == true
        ? normalizeCounselorLanguages(cp!.languages)
        : normalizeCounselorLanguages(switch (setup['languages']) {
            final List<dynamic> values => values,
            final String value => value.split(','),
            _ => const <dynamic>[],
          });
    _languages = langs.isNotEmpty
        ? langs.toSet()
        : {counselorLanguageOptions.first};

    _bio.text = cp?.bio ?? (setup['bio'] as String? ?? '');

    final specializationRaw =
        cp?.specialization ?? (setup['specialization'] as String? ?? '');
    final parsedSpecs = specializationRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && _specs.contains(e))
        .toSet();
    _specializations = parsedSpecs.isNotEmpty ? parsedSpecs : {_specs.first};

    _mode = cp?.sessionMode ?? (setup['sessionMode'] as String? ?? _mode);
    if (!_modes.contains(_mode)) _mode = _modes.first;

    _timezone = cp?.timezone ?? (setup['timezone'] as String? ?? _timezone);
    if (!_zones.contains(_timezone)) _timezone = _zones.first;

    _active = cp?.isActive ?? (setup['isActive'] as bool? ?? true);
    final d = (prefs['defaultSessionMinutes'] as num?)?.toInt();
    if (d != null && _durations.contains(d)) _duration = d;
    final b = (prefs['breakBetweenSessionsMins'] as num?)?.toInt();
    if (b != null && b >= 0 && b <= 60) _breakMins = b;
    _direct = (prefs['allowDirectBooking'] as bool?) ?? true;
    _followUps = (prefs['autoApproveFollowUps'] as bool?) ?? false;
    final weekdays = cp?.workingWeekdays.isNotEmpty == true
        ? cp!.workingWeekdays
        : _parseIntList(prefs['workingWeekdays']).isNotEmpty
        ? _parseIntList(prefs['workingWeekdays'])
        : _parseIntList(setup['workingWeekdays']);
    if (weekdays.isNotEmpty) {
      _workingWeekdays = weekdays.toSet();
    }
    _workingDayStartMinutes =
        cp?.workingDayStartMinutes ??
        (prefs['workingDayStartMinutes'] as num?)?.toInt() ??
        (setup['workingDayStartMinutes'] as num?)?.toInt() ??
        _workingDayStartMinutes;
    _workingDayEndMinutes =
        cp?.workingDayEndMinutes ??
        (prefs['workingDayEndMinutes'] as num?)?.toInt() ??
        (setup['workingDayEndMinutes'] as num?)?.toInt() ??
        _workingDayEndMinutes;
    _lunchBreakEnabled =
        cp?.lunchBreakEnabled ??
        (prefs['lunchBreakEnabled'] as bool?) ??
        (setup['lunchBreakEnabled'] as bool?) ??
        _lunchBreakEnabled;
    _lunchBreakStartMinutes =
        cp?.lunchBreakStartMinutes ??
        (prefs['lunchBreakStartMinutes'] as num?)?.toInt() ??
        (setup['lunchBreakStartMinutes'] as num?)?.toInt() ??
        _lunchBreakStartMinutes;
    _lunchBreakEndMinutes =
        cp?.lunchBreakEndMinutes ??
        (prefs['lunchBreakEndMinutes'] as num?)?.toInt() ??
        (setup['lunchBreakEndMinutes'] as num?)?.toInt() ??
        _lunchBreakEndMinutes;
    _seeded = true;
  }

  // ---- data mutations -------------------------------------------------------
  Future<void> _save(UserProfile profile) async {
    if (!_formKey.currentState!.validate()) return;
    _languages ??= {counselorLanguageOptions.first};
    setState(() => _savingProfile = true);
    try {
      final years = int.tryParse(_years.text.trim()) ?? 0;
      final languages = normalizeCounselorLanguages(_languages!);
      final workingWeekdays = [..._workingWeekdays]..sort();
      await ref
          .read(counselorRepositoryProvider)
          .updateProfileAndSettings(
            displayName: _name.text,
            title: _title.text,
            specialization: _specializations.join(', '),
            yearsExperience: years,
            sessionMode: _mode,
            timezone: _timezone,
            bio: _bio.text,
            languages: languages,
            isActive: _active,
            defaultSessionMinutes: _duration,
            breakBetweenSessionsMins: _breakMins,
            allowDirectBooking: _direct,
            autoApproveFollowUps: _followUps,
            workingWeekdays: workingWeekdays,
            workingDayStartMinutes: _workingDayStartMinutes,
            workingDayEndMinutes: _workingDayEndMinutes,
            lunchBreakEnabled: _lunchBreakEnabled,
            lunchBreakStartMinutes: _lunchBreakStartMinutes,
            lunchBreakEndMinutes: _lunchBreakEndMinutes,
          );
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        const SnackBar(content: Text('Counselor profile updated.')),
      );
      _seeded = false;
    } catch (error) {
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _sendReset(UserProfile profile) async {
    setState(() => _sendingReset = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(profile.email);
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        SnackBar(content: Text('Password reset sent to ${profile.email}.')),
      );
    } catch (error) {
      if (!mounted) return;
      showModernBannerFromSnackBar(
        context,
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  // ---- workspace navigation (non-embedded fallback) -------------------------
  void _navigateSection(
    BuildContext context,
    CounselorWorkspaceNavSection section,
  ) {
    switch (section) {
      case CounselorWorkspaceNavSection.dashboard:
        context.go(AppRoute.counselorDashboard);
      case CounselorWorkspaceNavSection.sessions:
        context.go(AppRoute.counselorAppointments);
      case CounselorWorkspaceNavSection.live:
        context.go(AppRoute.counselorLiveHub);
      case CounselorWorkspaceNavSection.availability:
        context.go(AppRoute.counselorAvailability);
      case CounselorWorkspaceNavSection.counselors:
        context.go(AppRoute.counselorDirectory);
    }
  }

  Future<void> _openCounselorNotificationsOverlay(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: AppRoute.counselorNotifications),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const NotificationCenterScreen(embeddedInCounselorShell: true);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide =
              Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          );
          return SlideTransition(
            position: slide,
            child: FadeTransition(opacity: fade, child: child),
          );
        },
      ),
    );
  }

  // ---- section metadata -----------------------------------------------------
  List<_NavItem> _navItems(UserProfile profile) {
    final displayName = profile.name.trim().isNotEmpty
        ? profile.name.trim()
        : 'Counselor';
    final institution = profile.institutionName?.trim().isNotEmpty == true
        ? profile.institutionName!.trim()
        : 'Counselor workspace';
    return <_NavItem>[
      _NavItem(
        section: CounselorProfileSettingsSection.identity,
        group: 'PROFILE',
        title: 'Identity',
        subtitle: '$displayName · $institution',
        icon: Icons.person_rounded,
        accent: const Color(0xFF14B8A6),
        searchTerms: [
          displayName,
          institution,
          'name',
          'display name',
          'identity',
          'institution',
          'school',
          'university',
          'profile basics',
        ],
      ),
      _NavItem(
        section: CounselorProfileSettingsSection.professionalDetails,
        group: 'PROFILE',
        title: 'Professional profile',
        subtitle:
            '${_title.text.trim().isEmpty ? 'Licensed counselor' : _title.text.trim()} · ${_years.text.trim().isEmpty ? '—' : '${_years.text.trim()} yrs'} · $_mode',
        icon: Icons.work_history_rounded,
        accent: const Color(0xFF34D399),
        searchTerms: [
          _title.text,
          _years.text,
          _mode,
          _timezone,
          _bio.text,
          ..._specializations,
          ...(_languages ?? {counselorLanguageOptions.first}),
          'professional title',
          'years experience',
          'experience',
          'mode',
          'session mode',
          'timezone',
          'time zone',
          'specializations',
          'specialties',
          'languages',
          'bio',
          'about',
          'profile',
        ],
      ),
      _NavItem(
        section: CounselorProfileSettingsSection.sessionRhythm,
        group: 'PRACTICE',
        title: 'Session rhythm',
        subtitle:
            '${_weekdayRangeLabel()} · ${_formatMinutesOfDay(_workingDayStartMinutes)}-${_formatMinutesOfDay(_workingDayEndMinutes)} · $_duration min',
        icon: Icons.graphic_eq_rounded,
        accent: const Color(0xFF22D3EE),
        searchTerms: [
          'duration',
          'default session',
          'session minutes',
          'break',
          'break between sessions',
          'direct booking',
          'follow ups',
          'auto approve',
          'booking preferences',
          'weekdays',
          'weekend',
          'weekends',
          'working hours',
          'daily schedule',
          'lunch',
          'lunch break',
          'work start',
          'work end',
          'cadence',
          'rhythm',
        ],
      ),
      _NavItem(
        section: CounselorProfileSettingsSection.passwordSignIn,
        group: 'ACCOUNT',
        title: 'Password & sign-in',
        subtitle: profile.email,
        icon: Icons.key_rounded,
        accent: const Color(0xFF60A5FA),
        searchTerms: [
          profile.email,
          'password',
          'reset password',
          'sign in',
          'signin',
          'login',
          'security',
          'passkeys',
          'fingerprint',
          'account access',
        ],
      ),
      _NavItem(
        section: CounselorProfileSettingsSection.privacyData,
        group: 'ACCOUNT',
        title: 'Privacy & data',
        subtitle: _active ? 'Visible to students' : 'Hidden',
        icon: Icons.privacy_tip_rounded,
        accent: const Color(0xFFC084FC),
        searchTerms: [
          'privacy',
          'data',
          'visibility',
          'visible',
          'hidden',
          'directory',
          'students',
          'export',
          'download data',
          'passkeys',
          'sign out',
          'logout',
          'log out',
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Search — powerful multi-token + fuzzy scoring.
  //
  // For each item we build a haystack of {title, subtitle, group, section,
  // searchTerms}. The query is split into tokens; every token must match
  // (via substring OR fuzzy subsequence within ~1 typo) somewhere. Items are
  // then ranked by a composite score so the best matches float to the top.
  // If nothing scores above 0 we return an empty list and the empty-state
  // shows the *closest* items as tappable suggestions.
  // ---------------------------------------------------------------------------

  List<String> _itemHaystack(_NavItem item) => [
    item.title,
    item.subtitle,
    item.group,
    item.section.name,
    ...item.searchTerms,
  ];

  /// Composite score. 0 = no match. Higher is better.
  double _scoreItem(_NavItem item, String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return 1; // no query -> everything shows
    final tokens = q
        .split(RegExp(r'[\s,;/]+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return 1;

    final title = item.title.toLowerCase();
    final subtitle = item.subtitle.toLowerCase();
    final terms = item.searchTerms.map((e) => e.toLowerCase()).toList();
    final allFields = <String>[
      title,
      subtitle,
      item.group.toLowerCase(),
      item.section.name.toLowerCase(),
      ...terms,
    ];
    final joined = allFields.join(' ');

    double total = 0;
    for (final tok in tokens) {
      final tokScore = _bestTokenScore(tok, title, subtitle, terms, joined);
      if (tokScore <= 0) return 0; // every token must land somewhere
      total += tokScore;
    }
    // Small bonus for exact whole-query match on the title.
    if (title == q) total += 6;
    if (title.startsWith(q)) total += 2;
    return total;
  }

  double _bestTokenScore(
    String tok,
    String title,
    String subtitle,
    List<String> terms,
    String joined,
  ) {
    double best = 0;

    void bump(double v) {
      if (v > best) best = v;
    }

    // Exact whole-word / prefix hits weigh most.
    if (title == tok) bump(10);
    if (title.startsWith(tok)) bump(6);
    if (title.contains(tok)) bump(4);
    if (subtitle.contains(tok)) bump(3);
    for (final t in terms) {
      if (t == tok) {
        bump(5);
      } else if (t.startsWith(tok)) {
        bump(3.5);
      } else if (t.contains(tok)) {
        bump(2);
      }
    }
    if (best > 0) return best;

    // Fuzzy fallbacks — subsequence (typing letters in order) and small typos.
    if (_isSubsequence(tok, title)) bump(1.6);
    if (_isSubsequence(tok, joined)) bump(1.0);
    if (tok.length >= 4) {
      for (final t in terms) {
        if (_within1Edit(tok, t)) {
          bump(1.4);
          break;
        }
      }
      if (_within1Edit(tok, title)) bump(1.5);
    }
    return best;
  }

  static bool _isSubsequence(String needle, String hay) {
    if (needle.isEmpty) return true;
    var i = 0;
    for (var j = 0; j < hay.length && i < needle.length; j++) {
      if (hay.codeUnitAt(j) == needle.codeUnitAt(i)) i++;
    }
    return i == needle.length;
  }

  /// Damerau-ish: true if strings are equal, differ by one insert/delete/sub,
  /// or one adjacent transposition. Cheap and effective for short queries.
  static bool _within1Edit(String a, String b) {
    if (a == b) return true;
    final la = a.length, lb = b.length;
    if ((la - lb).abs() > 1) return false;
    var i = 0, j = 0, edits = 0;
    while (i < la && j < lb) {
      if (a.codeUnitAt(i) == b.codeUnitAt(j)) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (la == lb) {
        // sub or transposition
        if (i + 1 < la &&
            j + 1 < lb &&
            a.codeUnitAt(i) == b.codeUnitAt(j + 1) &&
            a.codeUnitAt(i + 1) == b.codeUnitAt(j)) {
          i += 2;
          j += 2;
        } else {
          i++;
          j++;
        }
      } else if (la > lb) {
        i++;
      } else {
        j++;
      }
    }
    if (i < la || j < lb) edits++;
    return edits <= 1;
  }

  /// Suggestions shown in the empty state — the top items by a relaxed score.
  List<_NavItem> _suggestionsFor(String query, List<_NavItem> all) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final scored = <MapEntry<_NavItem, double>>[];
    for (final item in all) {
      // Relaxed score: subsequence / edit-distance / partial-token match.
      final s = _relaxedScore(item, q.toLowerCase());
      if (s > 0) scored.add(MapEntry(item, s));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(3).map((e) => e.key).toList(growable: false);
  }

  double _relaxedScore(_NavItem item, String q) {
    double best = 0;
    for (final field in _itemHaystack(item)) {
      final f = field.toLowerCase();
      if (f.contains(q)) best = math.max(best, 5);
      if (_isSubsequence(q, f)) best = math.max(best, 3);
      if (q.length >= 3 && _within1Edit(q, f)) best = math.max(best, 4);
      // partial-prefix: any word in f starts with first 3 letters of q
      final pref = q.length >= 3 ? q.substring(0, 3) : q;
      for (final word in f.split(RegExp(r'\s+'))) {
        if (word.startsWith(pref)) best = math.max(best, 2);
      }
    }
    return best;
  }

  // =========================================================================
  // Detail navigation — each section as its own full-screen route.
  // =========================================================================

  Future<void> _openDetail(_NavItem item) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: _T.dPage,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (ctx, anim, sec) => _DetailHost(item: item, state: this),
        transitionsBuilder: (ctx, anim, sec, child) {
          final curved = CurvedAnimation(parent: anim, curve: _T.easeOut);
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved);
          final scale = Tween<double>(begin: 0.985, end: 1.0).animate(curved);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {}); // refresh subtitles after edits
  }

  // ---- build ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Belt-and-suspenders: some other screens may flip these on. Force them
    // off every rebuild so the yellow baseline underlines never leak in.
    assert(() {
      debugPaintBaselinesEnabled = false;
      debugPaintSizeEnabled = false;
      debugPaintPointersEnabled = false;
      debugPaintLayerBordersEnabled = false;
      return true;
    }());
    final profileAsync = ref.watch(currentUserProfileProvider);
    return profileAsync.when(
      loading: () => const ColoredBox(
        color: _T.bg,
        child: Center(child: CircularProgressIndicator(color: _T.brand)),
      ),
      error: (error, _) => ColoredBox(
        color: _T.bg,
        child: Center(
          child: Text(
            error.toString(),
            style: const TextStyle(color: _T.textMuted),
          ),
        ),
      ),
      data: (profile) {
        if (profile == null || profile.role != UserRole.counselor) {
          return const ColoredBox(
            color: _T.bg,
            child: Center(
              child: Text(
                'Only counselors can access this page.',
                style: TextStyle(color: _T.textMuted),
              ),
            ),
          );
        }

        final unread =
            ref.watch(unreadNotificationCountProvider(profile.id)).value ?? 0;
        final showDirectory =
            ref
                .watch(
                  counselorWorkflowSettingsProvider(
                    profile.institutionId ?? '',
                  ),
                )
                .valueOrNull
                ?.directoryEnabled ??
            false;

        final body = StreamBuilder<CounselorProfile?>(
          stream: ref
              .read(careRepositoryProvider)
              .watchCounselorProfile(profile.id),
          builder: (context, snap) {
            _seed(profile, snap.data);
            _maybeHandleDeepLink(profile);
            return _buildLanding(profile, unread, showDirectory);
          },
        );

        final wrapped = Material(
          type: MaterialType.canvas,
          color: _T.bg,
          child: ScrollConfiguration(
            behavior: const NoScrollbarScrollBehavior(),
            child: body,
          ),
        );

        if (widget.embeddedInCounselorShell) return wrapped;

        return CounselorWorkspaceScaffold(
          profile: profile,
          activeSection: CounselorWorkspaceNavSection.dashboard,
          showCounselorDirectory: showDirectory,
          unreadNotifications: unread,
          profileHighlighted: true,
          title: 'Profile settings',
          subtitle:
              'Manage the profile students see, tune booking rules, and update account controls.',
          onSelectSection: (section) => _navigateSection(context, section),
          onNotifications: () => _openCounselorNotificationsOverlay(context),
          onProfile: () {},
          onLogout: () => confirmAndLogout(context: context, ref: ref),
          child: wrapped,
        );
      },
    );
  }

  void _maybeHandleDeepLink(UserProfile profile) {
    if (_deepLinkHandled) return;
    if (widget.initialSection == CounselorProfileSettingsSection.identity) {
      _deepLinkHandled = true;
      return;
    }
    _deepLinkHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final items = _navItems(profile);
      final match = items.firstWhere(
        (i) => i.section == widget.initialSection,
        orElse: () => items.first,
      );
      _openDetail(match);
    });
  }

  // =========================================================================
  // Landing — modern, calm, iOS-like large title over a soft accent glow.
  // =========================================================================

  Widget _buildLanding(UserProfile profile, int unread, bool showDirectory) {
    final normalizedQuery = _query.trim();
    final all = _navItems(profile);
    // Score, filter, and sort — highest score first when a query is active.
    final scored = <MapEntry<_NavItem, double>>[];
    for (final it in all) {
      final s = _scoreItem(it, normalizedQuery);
      if (s > 0) scored.add(MapEntry(it, s));
    }
    if (normalizedQuery.isNotEmpty) {
      scored.sort((a, b) => b.value.compareTo(a.value));
    }
    final items = scored.map((e) => e.key).toList(growable: false);
    final suggestions = items.isEmpty
        ? _suggestionsFor(normalizedQuery, all)
        : const <_NavItem>[];
    final grouped = <String, List<_NavItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.group, () => []).add(item);
    }

    return DecoratedBox(
      decoration: const BoxDecoration(color: _T.bg),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _LandingHero(profile: profile, active: _active),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: _SearchField(
                  controller: _search,
                  query: normalizedQuery,
                  onClear: _clearSearch,
                ),
              ),
            ),
            if (items.isEmpty)
              SliverToBoxAdapter(
                child: _SettingsSearchEmptyState(
                  query: normalizedQuery,
                  suggestions: suggestions,
                  onTapSuggestion: _openDetail,
                  onClear: _clearSearch,
                ),
              )
            else
              for (final group in const ['PROFILE', 'PRACTICE', 'ACCOUNT'])
                if ((grouped[group] ?? const []).isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 18, 20, 10),
                      child: Text(
                        group,
                        style: const TextStyle(
                          color: _T.textFaint,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _RowGroup(
                        items: grouped[group]!,
                        onTap: _openDetail,
                      ),
                    ),
                  ),
                ],
            // Directory status removed per UX request.
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Landing hero — big soft radial glow + name + status pill.
// =============================================================================

class _LandingHero extends StatelessWidget {
  const _LandingHero({required this.profile, required this.active});
  final UserProfile profile;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final name = profile.name.trim().isNotEmpty
        ? profile.name.trim()
        : 'Counselor';
    final initials = _initials(name);
    return _AccentGlow(
      color: _T.brand,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: back/collapse button
            Row(
              children: [
                _CircleIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Hero(
                  tag: 'counselor-avatar',
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF13D0C7), Color(0xFF0E9B90)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x5513D0C7),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: TextStyle(
                          color: _T.text,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _T.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _StatusPill(active: active),
          ],
        ),
      ),
    );
  }

  static String _initials(String n) {
    final parts = n.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF10E3B0) : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            active ? 'Visible to students' : 'Hidden from students',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Search field
// =============================================================================

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.query,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _T.brand,
          selectionColor: Color(0x3313D0C7),
          selectionHandleColor: _T.brand,
        ),
      ),
      child: TextField(
        controller: controller,
        autocorrect: false,
        enableSuggestions: false,
        spellCheckConfiguration: SpellCheckConfiguration.disabled(),
        style: const TextStyle(
          color: _T.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: _T.brand,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          filled: true,
          fillColor: _T.surfaceInput,
          hintText: 'Search settings',
          hintStyle: const TextStyle(color: _T.textFaint),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: _T.textFaint,
            size: 20,
          ),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: _T.textFaint,
                    size: 20,
                  ),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _T.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _T.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _T.brand, width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Row group — inset grouped list with staggered fade-in.
// =============================================================================

class _NavItem {
  const _NavItem({
    required this.section,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.searchTerms = const <String>[],
  });

  final CounselorProfileSettingsSection section;
  final String group;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<String> searchTerms;
}

class _SettingsSearchEmptyState extends StatelessWidget {
  const _SettingsSearchEmptyState({
    required this.query,
    this.suggestions = const [],
    this.onTapSuggestion,
    this.onClear,
  });

  final String query;
  final List<_NavItem> suggestions;
  final ValueChanged<_NavItem>? onTapSuggestion;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasSuggestions = suggestions.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _T.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _T.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _T.brand.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.manage_search_rounded,
                    color: _T.brand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No exact match',
                        style: TextStyle(
                          color: _T.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasSuggestions
                            ? 'Nothing exactly matched "$query" — did you mean:'
                            : 'Nothing matched "$query". Try password, language, bio, timezone, export, or sign out.',
                        style: const TextStyle(
                          color: _T.textMuted,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasSuggestions) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in suggestions)
                    _SuggestionChip(
                      item: s,
                      onTap: () => onTapSuggestion?.call(s),
                    ),
                ],
              ),
            ],
            if (onClear != null) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    foregroundColor: _T.brand,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text(
                    'Clear search',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.item, required this.onTap});
  final _NavItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: item.accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: item.accent.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 14, color: item.accent),
              const SizedBox(width: 6),
              Text(
                item.title,
                style: TextStyle(
                  color: _T.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, size: 13, color: _T.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowGroup extends StatelessWidget {
  const _RowGroup({required this.items, required this.onTap});
  final List<_NavItem> items;
  final ValueChanged<_NavItem> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _T.hairline),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _StaggeredIn(
              delay: Duration(milliseconds: 40 * i),
              child: _Row(item: items[i], onTap: () => onTap(items[i])),
            ),
            if (i != items.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 66),
                child: Divider(
                  height: 1,
                  thickness: 0.6,
                  color: Color(0x14FFFFFF),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.item, required this.onTap});
  final _NavItem item;
  final VoidCallback onTap;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _scale = 0.98),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: _T.dQuick,
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              Hero(
                tag: 'section-icon-${widget.item.section.name}',
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.item.accent.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.item.accent.withOpacity(0.28),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.item.icon,
                    color: widget.item.accent,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      style: const TextStyle(
                        color: _T.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _T.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                color: _T.textFaint,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Staggered fade+translate on mount
// =============================================================================

class _StaggeredIn extends StatefulWidget {
  const _StaggeredIn({required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;
  @override
  State<_StaggeredIn> createState() => _StaggeredInState();
}

class _StaggeredInState extends State<_StaggeredIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _T.dEnter,
  );
  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: _T.easeOut);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        final t = curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// =============================================================================
// Detail host — full-screen route per section.
// =============================================================================

class _DetailHost extends StatefulWidget {
  const _DetailHost({required this.item, required this.state});
  final _NavItem item;
  final _CounselorProfileSettingsScreenState state;
  @override
  State<_DetailHost> createState() => _DetailHostState();
}

class _DetailHostState extends State<_DetailHost> {
  final _scroll = ScrollController();
  double _t = 0.0; // 0 = expanded, 1 = collapsed

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final v = (_scroll.offset / 80).clamp(0.0, 1.0);
    if ((v - _t).abs() > 0.005) setState(() => _t = v);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final s = widget.state;
    final needsSave = _sectionSaves(item.section);

    // Build a stable profile ref from the outer state.
    final profileAsync = s.ref.watch(currentUserProfileProvider);
    final profile = profileAsync.valueOrNull;
    if (profile == null) {
      return const Scaffold(
        backgroundColor: _T.bg,
        body: Center(child: CircularProgressIndicator(color: _T.brand)),
      );
    }

    return Scaffold(
      backgroundColor: _T.bg,
      body: Stack(
        children: [
          _AccentGlow(color: item.accent, child: const SizedBox.expand()),
          SafeArea(
            child: Form(
              key: s._formKey,
              child: CustomScrollView(
                controller: _scroll,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: _DetailHeader(
                      item: item,
                      progress: _t,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        needsSave ? 120 : 40,
                      ),
                      child: _StaggeredIn(
                        delay: const Duration(milliseconds: 80),
                        child: _SectionBody(
                          section: item.section,
                          state: s,
                          profile: profile,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (needsSave)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _StickySaveBar(
                saving: s._savingProfile,
                onSave: s._savingProfile ? null : () => s._save(profile),
                accent: item.accent,
              ),
            ),
        ],
      ),
    );
  }

  bool _sectionSaves(CounselorProfileSettingsSection s) {
    return s != CounselorProfileSettingsSection.passwordSignIn;
  }
}

// =============================================================================
// Detail header — animated large-title that collapses on scroll.
// =============================================================================

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.item,
    required this.progress,
    required this.onBack,
  });
  final _NavItem item;
  final double progress;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final iconSize = ui.lerpDouble(56, 36, progress)!;
    final radius = ui.lerpDouble(18, 11, progress)!;
    final iconGlyph = ui.lerpDouble(26, 18, progress)!;
    final titleSize = ui.lerpDouble(32, 20, progress)!;
    final gap = ui.lerpDouble(18, 10, progress)!;
    final descOpacity = (1 - progress * 1.6).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CircleIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              const Spacer(),
              // Reserved for future actions.
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Hero(
                  tag: 'section-icon-${item.section.name}',
                  child: Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: item.accent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: item.accent.withOpacity(0.30)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(item.icon, color: item.accent, size: iconGlyph),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          color: _T.text,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AnimatedOpacity(
            duration: _T.dQuick,
            opacity: descOpacity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _description(item.section),
                style: const TextStyle(
                  color: _T.textMuted,
                  fontSize: 14.5,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  String _description(CounselorProfileSettingsSection s) => switch (s) {
    CounselorProfileSettingsSection.identity =>
      'How your counselor identity appears to students.',
    CounselorProfileSettingsSection.professionalDetails =>
      'Title, years of practice, session mode, and timezone.',
    CounselorProfileSettingsSection.specializations =>
      'The areas students can book you for.',
    CounselorProfileSettingsSection.languages =>
      'Languages you provide sessions in.',
    CounselorProfileSettingsSection.bio =>
      'A calm, human summary that helps students know what to expect.',
    CounselorProfileSettingsSection.sessionRhythm =>
      'Your default cadence, breaks, and booking preferences.',
    CounselorProfileSettingsSection.passwordSignIn =>
      'Send yourself a password reset or manage passkeys.',
    CounselorProfileSettingsSection.privacyData =>
      'Visibility, exports, and account data controls.',
  };
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _T.surface,
            shape: BoxShape.circle,
            border: Border.all(color: _T.hairline),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: _T.text, size: 20),
        ),
      ),
    );
  }
}

// =============================================================================
// Sticky save bar with animated state
// =============================================================================

class _StickySaveBar extends StatelessWidget {
  const _StickySaveBar({
    required this.saving,
    required this.onSave,
    required this.accent,
  });
  final bool saving;
  final VoidCallback? onSave;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: _T.bg.withOpacity(0.72),
            border: const Border(
              top: BorderSide(color: _T.hairline, width: 0.6),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: AnimatedContainer(
              duration: _T.dQuick,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [accent, Color.lerp(accent, Colors.white, 0.15)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onSave,
                  borderRadius: BorderRadius.circular(18),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: _T.dQuick,
                      child: saving
                          ? const Row(
                              key: ValueKey('saving'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Saving…',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : const Row(
                              key: ValueKey('save'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Save changes',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Accent radial glow behind the top of a screen.
// =============================================================================

class _AccentGlow extends StatelessWidget {
  const _AccentGlow({required this.color, required this.child});
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _GlowPainter(color)),
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, -size.height * 0.05),
        math.max(size.width, size.height) * 0.75,
        [color.withOpacity(0.20), color.withOpacity(0.00)],
        const [0.0, 1.0],
      );
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) => old.color != color;
}

// =============================================================================
// Section bodies — clean, calm, no card-on-card.
// =============================================================================

class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.section,
    required this.state,
    required this.profile,
  });
  final CounselorProfileSettingsSection section;
  final _CounselorProfileSettingsScreenState state;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case CounselorProfileSettingsSection.identity:
        return _IdentityBody(state: state, profile: profile);
      case CounselorProfileSettingsSection.professionalDetails:
        return _ProfessionalProfileBody(state: state);
      case CounselorProfileSettingsSection.specializations:
        return _SpecializationsBody(state: state);
      case CounselorProfileSettingsSection.languages:
        return _LanguagesBody(state: state);
      case CounselorProfileSettingsSection.bio:
        return _BioBody(state: state);
      case CounselorProfileSettingsSection.sessionRhythm:
        return _SessionRhythmBody(state: state);
      case CounselorProfileSettingsSection.passwordSignIn:
        return _PasswordBody(state: state, profile: profile);
      case CounselorProfileSettingsSection.privacyData:
        return _PrivacyBody(state: state, profile: profile);
    }
  }
}

// ---- shared input decoration ------------------------------------------------

InputDecoration _fieldDecoration({
  required String label,
  Widget? prefix,
  bool alignLabelWithHint = false,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: _T.hairline),
  );
  return InputDecoration(
    filled: true,
    fillColor: _T.surfaceInput,
    labelText: label,
    labelStyle: const TextStyle(color: _T.textMuted),
    floatingLabelStyle: const TextStyle(color: _T.brand),
    prefixIcon: prefix == null
        ? null
        : IconTheme(
            data: const IconThemeData(color: _T.textFaint),
            child: prefix,
          ),
    alignLabelWithHint: alignLabelWithHint,
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _T.brand, width: 1.4),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

// ---- Identity ---------------------------------------------------------------

class _IdentityBody extends StatelessWidget {
  const _IdentityBody({required this.state, required this.profile});
  final _CounselorProfileSettingsScreenState state;
  final UserProfile profile;
  @override
  Widget build(BuildContext context) {
    final name = profile.name.trim().isNotEmpty
        ? profile.name.trim()
        : 'Counselor';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _T.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _T.hairline),
          ),
          child: Row(
            children: [
              Hero(
                tag: 'counselor-avatar',
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF13D0C7), Color(0xFF0E9B90)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: _T.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.institutionName ?? 'Institution workspace',
                      style: const TextStyle(color: _T.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              _StatusPill(active: state._active),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: state._name,
          style: const TextStyle(color: _T.text),
          cursorColor: _T.brand,
          decoration: _fieldDecoration(
            label: 'Display name',
            prefix: const Icon(Icons.person_rounded),
          ),
          validator: (v) => (v ?? '').trim().length < 2
              ? 'Enter at least 2 characters.'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: profile.institutionName ?? '',
          readOnly: true,
          style: const TextStyle(color: _T.textMuted),
          decoration: _fieldDecoration(
            label: 'Institution',
            prefix: const Icon(Icons.apartment_rounded),
          ),
        ),
      ],
    );
  }

  static String _initials(String n) {
    final parts = n.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

// ---- Professional -----------------------------------------------------------

class _ProfessionalBody extends StatefulWidget {
  const _ProfessionalBody({required this.state});
  final _CounselorProfileSettingsScreenState state;
  @override
  State<_ProfessionalBody> createState() => _ProfessionalBodyState();
}

class _ProfessionalBodyState extends State<_ProfessionalBody> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: s._title,
          style: const TextStyle(color: _T.text),
          cursorColor: _T.brand,
          decoration: _fieldDecoration(
            label: 'Professional title',
            prefix: const Icon(Icons.badge_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: s._years,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: _T.text),
                cursorColor: _T.brand,
                decoration: _fieldDecoration(
                  label: 'Years',
                  prefix: const Icon(Icons.timeline_rounded),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DropdownField<String>(
                label: 'Mode',
                icon: Icons.video_call_rounded,
                value: s._mode,
                items: _CounselorProfileSettingsScreenState._modes,
                onChanged: (v) => setState(() => s._mode = v ?? s._mode),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DropdownField<String>(
          label: 'Timezone',
          icon: Icons.public_rounded,
          value: s._timezone,
          items: _CounselorProfileSettingsScreenState._zones,
          onChanged: (v) => setState(() => s._timezone = v ?? s._timezone),
        ),
      ],
    );
  }
}

class _ProfessionalProfileBody extends StatelessWidget {
  const _ProfessionalProfileBody({required this.state});

  final _CounselorProfileSettingsScreenState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailSectionLabel('Core profile'),
        const SizedBox(height: 10),
        _ProfessionalBody(state: state),
        const SizedBox(height: 18),
        _DetailSectionLabel('Specializations'),
        const SizedBox(height: 10),
        _SpecializationsBody(state: state),
        const SizedBox(height: 18),
        _DetailSectionLabel('Languages'),
        const SizedBox(height: 10),
        _LanguagesBody(state: state),
        const SizedBox(height: 18),
        _DetailSectionLabel('Bio'),
        const SizedBox(height: 10),
        _BioBody(state: state),
      ],
    );
  }
}

class _DetailSectionLabel extends StatelessWidget {
  const _DetailSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _T.textFaint,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final IconData icon;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      dropdownColor: _T.surface,
      isExpanded: true,
      iconEnabledColor: _T.textFaint,
      style: const TextStyle(color: _T.text, fontSize: 15),
      decoration: _fieldDecoration(label: label, prefix: Icon(icon)),
      items: items
          .map((e) => DropdownMenuItem<T>(value: e, child: Text('$e')))
          .toList(growable: false),
      onChanged: onChanged,
    );
  }
}

// ---- Specializations --------------------------------------------------------

class _SpecializationsBody extends StatefulWidget {
  const _SpecializationsBody({required this.state});
  final _CounselorProfileSettingsScreenState state;
  @override
  State<_SpecializationsBody> createState() => _SpecializationsBodyState();
}

class _SpecializationsBodyState extends State<_SpecializationsBody> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _CounselorProfileSettingsScreenState._specs
          .map(
            (item) => _ChoiceChip(
              label: item,
              selected: s._specializations.contains(item),
              onTap: () => setState(() {
                final next = Set<String>.from(s._specializations);
                if (next.contains(item)) {
                  next.remove(item);
                } else {
                  next.add(item);
                }
                s._specializations = next.isEmpty
                    ? {_CounselorProfileSettingsScreenState._specs.first}
                    : next;
              }),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _T.dQuick,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: selected
            ? const LinearGradient(
                colors: [Color(0xFF13D0C7), Color(0xFF0E9B90)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: selected ? null : _T.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? _T.brand : _T.hairline),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: _T.brand.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: _T.dQuick,
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: Icon(
                    selected ? Icons.check_rounded : Icons.add_rounded,
                    key: ValueKey(selected),
                    size: 16,
                    color: selected ? Colors.white : _T.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : _T.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
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

// ---- Languages --------------------------------------------------------------

class _LanguagesBody extends StatefulWidget {
  const _LanguagesBody({required this.state});
  final _CounselorProfileSettingsScreenState state;
  @override
  State<_LanguagesBody> createState() => _LanguagesBodyState();
}

class _LanguagesBodyState extends State<_LanguagesBody> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final selected = s._languages ?? {counselorLanguageOptions.first};
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: counselorLanguageOptions
          .map(
            (lang) => _ChoiceChip(
              label: lang,
              selected: selected.contains(lang),
              onTap: () => setState(() {
                s._languages ??= {counselorLanguageOptions.first};
                if (s._languages!.contains(lang)) {
                  s._languages!.remove(lang);
                } else {
                  s._languages!.add(lang);
                }
                if (s._languages!.isEmpty) {
                  s._languages = {counselorLanguageOptions.first};
                }
              }),
            ),
          )
          .toList(growable: false),
    );
  }
}

// ---- Bio --------------------------------------------------------------------

class _BioBody extends StatelessWidget {
  const _BioBody({required this.state});
  final _CounselorProfileSettingsScreenState state;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: state._bio,
      minLines: 6,
      maxLines: 12,
      style: const TextStyle(color: _T.text, height: 1.5),
      cursorColor: _T.brand,
      decoration: _fieldDecoration(
        label: 'Bio',
        prefix: const Icon(Icons.short_text_rounded),
        alignLabelWithHint: true,
      ),
    );
  }
}

// ---- Session rhythm ---------------------------------------------------------

class _SessionRhythmBody extends StatefulWidget {
  const _SessionRhythmBody({required this.state});
  final _CounselorProfileSettingsScreenState state;
  @override
  State<_SessionRhythmBody> createState() => _SessionRhythmBodyState();
}

class _SessionRhythmBodyState extends State<_SessionRhythmBody> {
  static const _weekdayLabels = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  Future<void> _pickTime({
    required int initialMinutes,
    required ValueChanged<int> onPicked,
  }) async {
    final initial = TimeOfDay(
      hour: initialMinutes ~/ 60,
      minute: initialMinutes % 60,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) {
      return;
    }
    onPicked(picked.hour * 60 + picked.minute);
  }

  void _ensureWorkingRange(_CounselorProfileSettingsScreenState s) {
    if (s._workingDayEndMinutes > s._workingDayStartMinutes) {
      return;
    }
    s._workingDayEndMinutes = (s._workingDayStartMinutes + 60)
        .clamp(1, 24 * 60)
        .toInt();
  }

  void _ensureLunchRange(_CounselorProfileSettingsScreenState s) {
    if (!s._lunchBreakEnabled) {
      return;
    }
    if (s._lunchBreakEndMinutes > s._lunchBreakStartMinutes) {
      return;
    }
    s._lunchBreakEndMinutes = (s._lunchBreakStartMinutes + 30)
        .clamp(1, 24 * 60)
        .toInt();
  }

  Widget _timeChip({
    required String label,
    required String value,
    required VoidCallback onTap,
    required Color accent,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _T.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _T.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: _T.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _T.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _T.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _MutedLabel('Default weekly rhythm'),
              const SizedBox(height: 8),
              Text(
                s._scheduleSummary(),
                style: const TextStyle(
                  color: _T.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'These defaults shape the weekly grid, quick-add slots, and the student-facing booking options.',
                style: TextStyle(color: _T.textMuted, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _MutedLabel('Working days'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List<Widget>.generate(_weekdayLabels.length, (index) {
            final day = index + 1;
            final selected = s._workingWeekdays.contains(day);
            return _ChoiceChip(
              label: _weekdayLabels[index],
              selected: selected,
              onTap: () => setState(() {
                if (selected && s._workingWeekdays.length == 1) {
                  return;
                }
                if (selected) {
                  s._workingWeekdays.remove(day);
                } else {
                  s._workingWeekdays.add(day);
                }
              }),
            );
          }),
        ),
        const SizedBox(height: 18),
        const _MutedLabel('Working hours'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _timeChip(
              label: 'Start',
              value: s._formatMinutesOfDay(s._workingDayStartMinutes),
              icon: Icons.wb_sunny_outlined,
              accent: const Color(0xFFF59E0B),
              onTap: () async {
                await _pickTime(
                  initialMinutes: s._workingDayStartMinutes,
                  onPicked: (minutes) {
                    setState(() {
                      s._workingDayStartMinutes = minutes;
                      _ensureWorkingRange(s);
                    });
                  },
                );
              },
            ),
            _timeChip(
              label: 'End',
              value: s._formatMinutesOfDay(s._workingDayEndMinutes),
              icon: Icons.nightlight_round,
              accent: const Color(0xFF7C3AED),
              onTap: () async {
                await _pickTime(
                  initialMinutes: s._workingDayEndMinutes,
                  onPicked: (minutes) {
                    setState(() {
                      s._workingDayEndMinutes = minutes;
                      _ensureWorkingRange(s);
                    });
                  },
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: _T.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _T.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Lunch break',
                      style: TextStyle(
                        color: _T.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: _T.dQuick,
                    child: Text(
                      s._lunchBreakEnabled ? 'On' : 'Off',
                      key: ValueKey(s._lunchBreakEnabled),
                      style: TextStyle(
                        color: s._lunchBreakEnabled ? _T.brand : _T.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ToggleTile(
                title: 'Reserve a midday break',
                subtitle:
                    'This break is subtracted from all generated booking options.',
                value: s._lunchBreakEnabled,
                onChanged: (v) => setState(() {
                  s._lunchBreakEnabled = v;
                  _ensureLunchRange(s);
                }),
              ),
              if (s._lunchBreakEnabled) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _timeChip(
                      label: 'Break start',
                      value: s._formatMinutesOfDay(s._lunchBreakStartMinutes),
                      icon: Icons.free_breakfast_outlined,
                      accent: const Color(0xFF0E9B90),
                      onTap: () async {
                        await _pickTime(
                          initialMinutes: s._lunchBreakStartMinutes,
                          onPicked: (minutes) {
                            setState(() {
                              s._lunchBreakStartMinutes = minutes;
                              _ensureLunchRange(s);
                            });
                          },
                        );
                      },
                    ),
                    _timeChip(
                      label: 'Break end',
                      value: s._formatMinutesOfDay(s._lunchBreakEndMinutes),
                      icon: Icons.lunch_dining_outlined,
                      accent: const Color(0xFFEF4444),
                      onTap: () async {
                        await _pickTime(
                          initialMinutes: s._lunchBreakEndMinutes,
                          onPicked: (minutes) {
                            setState(() {
                              s._lunchBreakEndMinutes = minutes;
                              _ensureLunchRange(s);
                            });
                          },
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _MutedLabel('Default session duration'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _CounselorProfileSettingsScreenState._durations
              .map((d) {
                final sel = s._duration == d;
                return _ChoiceChip(
                  label: '$d min',
                  selected: sel,
                  onTap: () => setState(() => s._duration = d),
                );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          decoration: BoxDecoration(
            color: _T.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _T.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Break between sessions',
                      style: TextStyle(
                        color: _T.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: _T.dQuick,
                    child: Text(
                      '${s._breakMins} min',
                      key: ValueKey(s._breakMins),
                      style: const TextStyle(
                        color: _T.brand,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _T.brand,
                  inactiveTrackColor: _T.hairline,
                  thumbColor: Colors.white,
                  overlayColor: _T.brand.withOpacity(0.15),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: s._breakMins.toDouble(),
                  min: 0,
                  max: 30,
                  divisions: 6,
                  onChanged: (v) => setState(() => s._breakMins = v.round()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ToggleTile(
          title: 'Allow direct booking',
          subtitle: 'Let students book without a manual approval step.',
          value: s._direct,
          onChanged: (v) => setState(() => s._direct = v),
        ),
        const SizedBox(height: 10),
        _ToggleTile(
          title: 'Auto-approve follow-ups',
          subtitle: 'Keep repeat sessions moving without extra admin.',
          value: s._followUps,
          onChanged: (v) => setState(() => s._followUps = v),
        ),
      ],
    );
  }
}

class _MutedLabel extends StatelessWidget {
  const _MutedLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _T.textFaint,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    ),
  );
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _T.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _T.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _T.textMuted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: _T.brand,
          ),
        ],
      ),
    );
  }
}

// ---- Password ---------------------------------------------------------------

class _PasswordBody extends StatelessWidget {
  const _PasswordBody({required this.state, required this.profile});
  final _CounselorProfileSettingsScreenState state;
  final UserProfile profile;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _T.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _T.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Signed in as',
                style: TextStyle(
                  color: _T.textFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                profile.email,
                style: const TextStyle(
                  color: _T.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'We will email a secure reset link to this address.',
                style: TextStyle(color: _T.textMuted, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _BigActionButton(
          icon: Icons.lock_reset_rounded,
          label: state._sendingReset ? 'Sending…' : 'Send reset link',
          onTap: state._sendingReset ? null : () => state._sendReset(profile),
          primary: true,
        ),
        const SizedBox(height: 12),
        _BigActionButton(
          icon: Icons.fingerprint_rounded,
          label: 'Manage passkeys',
          onTap: () => showPasskeyManagementDialog(context: context),
          primary: false,
        ),
      ],
    );
  }
}

class _BigActionButton extends StatelessWidget {
  const _BigActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.primary,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: primary
                ? const LinearGradient(
                    colors: [Color(0xFF13D0C7), Color(0xFF0E9B90)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: primary ? null : _T.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: primary ? Colors.transparent : _T.hairline,
            ),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: _T.brand.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: primary ? Colors.white : _T.text, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: primary ? Colors.white : _T.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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

// ---- Privacy ----------------------------------------------------------------

class _PrivacyBody extends StatefulWidget {
  const _PrivacyBody({required this.state, required this.profile});
  final _CounselorProfileSettingsScreenState state;
  final UserProfile profile;
  @override
  State<_PrivacyBody> createState() => _PrivacyBodyState();
}

class _PrivacyBodyState extends State<_PrivacyBody> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ToggleTile(
          title: 'Visible to students',
          subtitle: s._active
              ? 'You appear in the counselor directory.'
              : 'Your listing is hidden from students.',
          value: s._active,
          onChanged: (v) => setState(() => s._active = v),
        ),
        const SizedBox(height: 14),
        _BigActionButton(
          icon: Icons.download_rounded,
          label: 'Export my data',
          primary: false,
          onTap: () => showAccountExportSheet(
            context: context,
            ref: s.ref,
            title: 'Download your counselor data',
            subtitle:
                'Choose a polished PDF summary, spreadsheet-ready CSV tables, or advanced raw JSON.',
          ),
        ),
        const SizedBox(height: 12),
        _BigActionButton(
          icon: Icons.security_rounded,
          label: 'Manage passkeys',
          primary: false,
          onTap: () => showPasskeyManagementDialog(context: context),
        ),
        const SizedBox(height: 12),
        _BigActionButton(
          icon: Icons.logout_rounded,
          label: 'Sign out',
          primary: false,
          onTap: () => confirmAndLogout(context: context, ref: s.ref),
        ),
      ],
    );
  }
}
