// features/ai/data/assistant_repository.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/ai/models/assistant_models.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

// Source-file fallback config (used when no --dart-define values are passed).
// If you prefer not to pass --dart-define during development, put values here.
const _externalAiProviderSource = 'auto'; // auto | openai | gemini

// OpenAI-compatible config
const _externalAiApiKeySource = 'AIzaSyDZUxuK1aZj-pCpX78NTXBRTJ16YhCGG9o';
const _externalAiBaseUrlSource = 'https://api.openai.com/v1';
const _externalAiModelSource = 'gpt-4o-mini';
const _externalAiChatPathSource = '/chat/completions';

// Gemini config
const _geminiApiKeySource = 'AIzaSyDZUxuK1aZj-pCpX78NTXBRTJ16YhCGG9o';
const _geminiBaseUrlSource = 'https://generativelanguage.googleapis.com';
const _geminiModelSource = 'gemini-2.5-flash';
const _geminiGeneratePathSource = '/v1beta/models/{model}:generateContent';

class AssistantRepository {
  AssistantRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required http.Client httpClient,
  }) : _firestore = firestore,
       _auth = auth,
       _httpClient = httpClient;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final http.Client _httpClient;

  static const String _externalProviderFromDefine = String.fromEnvironment(
    'EXTERNAL_AI_PROVIDER',
    defaultValue: '',
  );
  static const String _openAiApiKeyFromDefine = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );
  static const String _openAiApiKeyLegacyFromDefine = String.fromEnvironment(
    'EXTERNAL_AI_API_KEY',
    defaultValue: '',
  );
  static const String _openAiBaseUrlFromDefine = String.fromEnvironment(
    'OPENAI_BASE_URL',
    defaultValue: '',
  );
  static const String _openAiBaseUrlLegacyFromDefine = String.fromEnvironment(
    'EXTERNAL_AI_BASE_URL',
    defaultValue: '',
  );
  static const String _openAiModelFromDefine = String.fromEnvironment(
    'OPENAI_MODEL',
    defaultValue: '',
  );
  static const String _openAiModelLegacyFromDefine = String.fromEnvironment(
    'EXTERNAL_AI_MODEL',
    defaultValue: '',
  );
  static const String _openAiChatPathFromDefine = String.fromEnvironment(
    'OPENAI_CHAT_PATH',
    defaultValue: '',
  );
  static const String _openAiChatPathLegacyFromDefine = String.fromEnvironment(
    'EXTERNAL_AI_CHAT_PATH',
    defaultValue: '',
  );
  static const String _geminiApiKeyFromDefine = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );
  static const String _geminiBaseUrlFromDefine = String.fromEnvironment(
    'GEMINI_BASE_URL',
    defaultValue: '',
  );
  static const String _geminiModelFromDefine = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: '',
  );
  static const String _geminiGeneratePathFromDefine = String.fromEnvironment(
    'GEMINI_GENERATE_PATH',
    defaultValue: '',
  );

  String get _provider => _externalProviderFromDefine.isNotEmpty
      ? _externalProviderFromDefine.toLowerCase().trim()
      : _externalAiProviderSource.toLowerCase().trim();

  String get _openAiApiKey {
    if (_openAiApiKeyFromDefine.isNotEmpty) {
      return _openAiApiKeyFromDefine;
    }
    if (_openAiApiKeyLegacyFromDefine.isNotEmpty) {
      return _openAiApiKeyLegacyFromDefine;
    }
    return _externalAiApiKeySource;
  }

  String get _openAiBaseUrl {
    if (_openAiBaseUrlFromDefine.isNotEmpty) {
      return _openAiBaseUrlFromDefine;
    }
    if (_openAiBaseUrlLegacyFromDefine.isNotEmpty) {
      return _openAiBaseUrlLegacyFromDefine;
    }
    return _externalAiBaseUrlSource;
  }

  String get _openAiModel {
    if (_openAiModelFromDefine.isNotEmpty) {
      return _openAiModelFromDefine;
    }
    if (_openAiModelLegacyFromDefine.isNotEmpty) {
      return _openAiModelLegacyFromDefine;
    }
    return _externalAiModelSource;
  }

  String get _openAiChatPath {
    if (_openAiChatPathFromDefine.isNotEmpty) {
      return _openAiChatPathFromDefine;
    }
    if (_openAiChatPathLegacyFromDefine.isNotEmpty) {
      return _openAiChatPathLegacyFromDefine;
    }
    return _externalAiChatPathSource;
  }

  String get _geminiApiKey => _geminiApiKeyFromDefine.isNotEmpty
      ? _geminiApiKeyFromDefine
      : _geminiApiKeySource;

  String get _geminiBaseUrl => _geminiBaseUrlFromDefine.isNotEmpty
      ? _geminiBaseUrlFromDefine
      : _geminiBaseUrlSource;

  String get _geminiModel => _geminiModelFromDefine.isNotEmpty
      ? _geminiModelFromDefine
      : _geminiModelSource;

  String get _geminiGeneratePath => _geminiGeneratePathFromDefine.isNotEmpty
      ? _geminiGeneratePathFromDefine
      : _geminiGeneratePathSource;

  bool get _openAiConfigured => _openAiApiKey.isNotEmpty;

  bool get _geminiConfigured => _geminiApiKey.isNotEmpty;

  bool get _preferOpenAi => _provider == 'openai';

  bool get _preferGemini => _provider == 'gemini';

  bool get _autoProvider => _provider.isEmpty || _provider == 'auto';

  Future<AssistantReply> processPrompt({
    required String prompt,
    required UserProfile profile,
    List<AssistantConversationMessage> history = const [],
  }) async {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const AssistantReply(
        text: 'Please type a question so I can help.',
      );
    }

    if (_isInAppRequest(normalized)) {
      return _handleInAppPrompt(prompt: prompt.trim(), profile: profile);
    }

    return _handleExternalPrompt(
      prompt: prompt.trim(),
      profile: profile,
      history: history,
    );
  }

  bool _isInAppRequest(String text) {
    const appKeywords = <String>[
      'app',
      'mindnest',
      'live',
      'go live',
      'counselor',
      'counsellor',
      'slot',
      'session',
      'appointment',
      'notification',
      'care plan',
      'goal',
      'join institution',
      'join organization',
      'join organisation',
      'institution',
      'organization',
      'organisation',
      'privacy',
      'profile',
      'dashboard',
      'onboarding',
    ];
    return appKeywords.any(text.contains);
  }

  bool _canUseLive(UserProfile profile) {
    return profile.role == UserRole.student ||
        profile.role == UserRole.staff ||
        profile.role == UserRole.counselor;
  }

  bool _hasInstitution(UserProfile profile) {
    return (profile.institutionId ?? '').trim().isNotEmpty;
  }

  Future<AssistantReply> _handleInAppPrompt({
    required String prompt,
    required UserProfile profile,
  }) async {
    final text = prompt.toLowerCase();

    if (_containsAny(text, const ['go live', 'start live', 'create live'])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text:
              'You need to join an organization before starting a live session.',
          action: AssistantAction(
            type: AssistantActionType.openJoinInstitution,
          ),
        );
      }
      if (!_canUseLive(profile)) {
        return AssistantReply(
          text:
              'Your current role (${profile.role.label}) cannot start live sessions.',
        );
      }
      return const AssistantReply(
        text: 'Opening Live Hub and preparing the create-live form.',
        action: AssistantAction(type: AssistantActionType.goLiveCreate),
      );
    }

    if (_containsAny(text, const ['live hub', 'join live', 'live session'])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text: 'Live Hub is available after you join an organization.',
          action: AssistantAction(
            type: AssistantActionType.openJoinInstitution,
          ),
        );
      }
      if (!_canUseLive(profile)) {
        return AssistantReply(
          text:
              'Live Hub is only available for student, staff, or counselor roles. You are ${profile.role.label}.',
        );
      }
      return const AssistantReply(
        text: 'Opening Live Hub now.',
        action: AssistantAction(type: AssistantActionType.openLiveHub),
      );
    }

    if (_containsAny(text, const [
      'open slot',
      'available slot',
      'counselor slot',
      'counsellor slot',
      'free slot',
    ])) {
      return _replyWithOpenSlots(profile);
    }

    if (_containsAny(text, const [
      'counselor',
      'counsellor',
      'find counselor',
      'book counselor',
    ])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text: 'You need to join an organization before viewing counselors.',
          action: AssistantAction(
            type: AssistantActionType.openJoinInstitution,
          ),
        );
      }
      return const AssistantReply(
        text: 'Opening counselors for your organization.',
        action: AssistantAction(type: AssistantActionType.openCounselors),
      );
    }

    if (_containsAny(text, const [
      'session',
      'appointment',
      'my bookings',
      'my session',
      'book session',
    ])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text:
              'Sessions are available once you join an organization. I can open Join Institution for you.',
          action: AssistantAction(
            type: AssistantActionType.openJoinInstitution,
          ),
        );
      }
      return const AssistantReply(
        text: 'Opening your sessions.',
        action: AssistantAction(type: AssistantActionType.openSessions),
      );
    }

    if (_containsAny(text, const ['notifications', 'alerts'])) {
      return const AssistantReply(
        text: 'Opening notifications.',
        action: AssistantAction(type: AssistantActionType.openNotifications),
      );
    }

    if (_containsAny(text, const ['care plan', 'goals'])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text:
              'Care Plan is organization-linked. Join an organization first to access it.',
          action: AssistantAction(
            type: AssistantActionType.openJoinInstitution,
          ),
        );
      }
      return const AssistantReply(
        text: 'Opening your care plan.',
        action: AssistantAction(type: AssistantActionType.openCarePlan),
      );
    }

    if (_containsAny(text, const [
      'join institution',
      'join organization',
      'join organisation',
      'join school',
    ])) {
      return const AssistantReply(
        text: 'Opening Join Institution.',
        action: AssistantAction(type: AssistantActionType.openJoinInstitution),
      );
    }

    if (_containsAny(text, const ['privacy', 'data settings'])) {
      return const AssistantReply(
        text: 'Opening privacy controls.',
        action: AssistantAction(type: AssistantActionType.openPrivacy),
      );
    }

    if (_containsAny(text, const ['how to book', 'book a slot'])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text:
              'To book a counselor slot, first join your organization from Join Institution.',
          action: AssistantAction(
            type: AssistantActionType.openJoinInstitution,
          ),
        );
      }
      return const AssistantReply(
        text:
            'To book: open Counselors, select a counselor profile, choose an available slot, and confirm booking.',
        action: AssistantAction(type: AssistantActionType.openCounselors),
      );
    }

    return const AssistantReply(
      text:
          'I can handle app actions like opening Live Hub, finding counselor slots, opening sessions, notifications, privacy controls, or guiding organization join.',
    );
  }

  Future<AssistantReply> _replyWithOpenSlots(UserProfile profile) async {
    if (!_hasInstitution(profile)) {
      return const AssistantReply(
        text:
            'I cannot check counselor slots yet because you are not in an organization.',
        action: AssistantAction(type: AssistantActionType.openJoinInstitution),
      );
    }

    final institutionId = (profile.institutionId ?? '').trim();
    try {
      final now = DateTime.now().toUtc();
      final availability = await _firestore
          .collection('counselor_availability')
          .where('institutionId', isEqualTo: institutionId)
          .where('status', isEqualTo: 'available')
          .limit(50)
          .get();

      final slots = availability.docs
          .map((entry) => entry.data())
          .where((data) {
            final endRaw = data['endAt'];
            if (endRaw is Timestamp) {
              return endRaw.toDate().toUtc().isAfter(now);
            }
            return false;
          })
          .toList(growable: false);

      if (slots.isEmpty) {
        return const AssistantReply(
          text:
              'I found no open counselor slots right now. Please check again later.',
          action: AssistantAction(type: AssistantActionType.openCounselors),
        );
      }

      slots.sort((a, b) {
        final aStart =
            (a['startAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bStart =
            (b['startAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aStart.compareTo(bStart);
      });

      final counselorIds = slots
          .map((data) => (data['counselorId'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      final counselorNames = await _fetchCounselorNames(counselorIds);

      final top = slots.take(5).toList(growable: false);
      final lines = top
          .map((slot) {
            final counselorId = (slot['counselorId'] as String?) ?? '';
            final name = counselorNames[counselorId] ?? 'Counselor';
            final start = (slot['startAt'] as Timestamp?)?.toDate().toLocal();
            final end = (slot['endAt'] as Timestamp?)?.toDate().toLocal();
            if (start == null || end == null) {
              return '$name: time not available';
            }
            return '$name: ${_formatSlotTime(start)} - ${_formatSlotTime(end)}';
          })
          .join('\n');

      return AssistantReply(
        text: 'Here are the next open counselor slots:\n$lines',
        action: const AssistantAction(type: AssistantActionType.openCounselors),
      );
    } catch (_) {
      return const AssistantReply(
        text:
            'I could not load slots right now. Opening counselors so you can check manually.',
        action: AssistantAction(type: AssistantActionType.openCounselors),
      );
    }
  }

  Future<Map<String, String>> _fetchCounselorNames(
    List<String> counselorIds,
  ) async {
    if (counselorIds.isEmpty) {
      return const <String, String>{};
    }
    final names = <String, String>{};
    final chunks = <List<String>>[];
    for (var i = 0; i < counselorIds.length; i += 10) {
      final end = (i + 10 < counselorIds.length) ? i + 10 : counselorIds.length;
      chunks.add(counselorIds.sublist(i, end));
    }
    for (final chunk in chunks) {
      final snap = await _firestore
          .collection('counselor_profiles')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        names[doc.id] = (doc.data()['displayName'] as String?) ?? 'Counselor';
      }
    }
    return names;
  }

  String _formatSlotTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hour:$minute $suffix';
  }

  Future<AssistantReply> _handleExternalPrompt({
    required String prompt,
    required UserProfile profile,
    required List<AssistantConversationMessage> history,
  }) async {
    if (_auth.currentUser == null) {
      return const AssistantReply(text: 'Please sign in to use AI chat.');
    }

    final hasOpenAi = _openAiConfigured;
    final hasGemini = _geminiConfigured;

    if ((_preferOpenAi && !hasOpenAi) ||
        (_preferGemini && !hasGemini) ||
        (_autoProvider && !hasOpenAi && !hasGemini)) {
      return AssistantReply(
        text: 'External AI is not configured yet. ${_configuredHint()}',
      );
    }

    final providerOrder = _providerSequence(
      hasOpenAi: hasOpenAi,
      hasGemini: hasGemini,
    );
    if (providerOrder.isEmpty) {
      return const AssistantReply(text: 'External AI is not configured yet.');
    }

    _ExternalCallResult? lastFailure;
    for (final provider in providerOrder) {
      final result = provider == _ProviderType.openAi
          ? await _callOpenAi(
              prompt: prompt,
              profile: profile,
              history: history,
            )
          : await _callGemini(
              prompt: prompt,
              profile: profile,
              history: history,
            );
      if (result.isSuccess) {
        return AssistantReply(text: result.text!, usedExternalModel: true);
      }
      lastFailure = result;
    }

    if (lastFailure?.timedOut == true) {
      return AssistantReply(
        text:
            '${_providerLabel(providerOrder)} request timed out. Please try again.',
      );
    }

    final statusText = lastFailure?.statusCode != null
        ? ' (status ${lastFailure!.statusCode})'
        : '';
    return AssistantReply(
      text:
          '${_providerLabel(providerOrder)} is unavailable right now$statusText. Please try again shortly.',
    );
  }

  String _systemPrompt(UserProfile profile) {
    return 'You are MindNest assistant. Provide supportive, calm responses. '
        'For emergency self-harm/violence risk, advise immediate local emergency/crisis support. '
        'Do not claim to be a licensed therapist. '
        'User context: role=${profile.role.name}, institutionId=${profile.institutionId ?? ''}.';
  }

  List<_ProviderType> _providerSequence({
    required bool hasOpenAi,
    required bool hasGemini,
  }) {
    if (_preferOpenAi) {
      return <_ProviderType>[
        if (hasOpenAi) _ProviderType.openAi,
        if (hasGemini) _ProviderType.gemini,
      ];
    }
    if (_preferGemini) {
      return <_ProviderType>[
        if (hasGemini) _ProviderType.gemini,
        if (hasOpenAi) _ProviderType.openAi,
      ];
    }
    // auto: default order is OpenAI then Gemini fallback.
    return <_ProviderType>[
      if (hasOpenAi) _ProviderType.openAi,
      if (hasGemini) _ProviderType.gemini,
    ];
  }

  String _providerLabel(List<_ProviderType> providers) {
    if (providers.length == 1) {
      return providers.first == _ProviderType.openAi ? 'OpenAI' : 'Gemini';
    }
    return 'External AI';
  }

  String _configuredHint() {
    if (_preferOpenAi) {
      return 'Set OPENAI_API_KEY (or EXTERNAL_AI_API_KEY).';
    }
    if (_preferGemini) {
      return 'Set GEMINI_API_KEY.';
    }
    return 'Set OPENAI_API_KEY/EXTERNAL_AI_API_KEY or GEMINI_API_KEY.';
  }

  Future<_ExternalCallResult> _callOpenAi({
    required String prompt,
    required UserProfile profile,
    required List<AssistantConversationMessage> history,
  }) async {
    final chatUrl = Uri.parse('$_openAiBaseUrl$_openAiChatPath');
    final recentHistory = history.length > 8
        ? history.sublist(history.length - 8)
        : history;

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt(profile)},
      ...recentHistory.map(
        (entry) => {'role': entry.role, 'content': entry.text},
      ),
      {'role': 'user', 'content': prompt},
    ];

    try {
      final response = await _httpClient
          .post(
            chatUrl,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_openAiApiKey',
            },
            body: jsonEncode({
              'model': _openAiModel,
              'messages': messages,
              'temperature': 0.6,
            }),
          )
          .timeout(const Duration(seconds: 22));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _ExternalCallResult.failure(statusCode: response.statusCode);
      }

      final payload = jsonDecode(response.body);
      final content =
          (((payload is Map ? payload['choices'] : null) as List?)?.firstOrNull
                  as Map?)?['message']?['content']
              as String?;

      if (content == null || content.trim().isEmpty) {
        return const _ExternalCallResult.failure();
      }

      return _ExternalCallResult.success(content.trim());
    } on TimeoutException {
      return const _ExternalCallResult.timeout();
    } catch (_) {
      return const _ExternalCallResult.failure();
    }
  }

  Future<_ExternalCallResult> _callGemini({
    required String prompt,
    required UserProfile profile,
    required List<AssistantConversationMessage> history,
  }) async {
    final recentHistory = history.length > 8
        ? history.sublist(history.length - 8)
        : history;

    final resolvedPath = _geminiGeneratePath.replaceAll(
      '{model}',
      Uri.encodeComponent(_geminiModel),
    );
    final baseUri = Uri.parse('$_geminiBaseUrl$resolvedPath');
    final query = <String, String>{...baseUri.queryParameters};
    query['key'] = _geminiApiKey;
    final requestUri = baseUri.replace(queryParameters: query);

    final contents = <Map<String, dynamic>>[
      ...recentHistory.map((entry) {
        final role = entry.role == 'assistant' ? 'model' : 'user';
        return <String, dynamic>{
          'role': role,
          'parts': <Map<String, String>>[
            {'text': entry.text},
          ],
        };
      }),
      <String, dynamic>{
        'role': 'user',
        'parts': <Map<String, String>>[
          {'text': prompt},
        ],
      },
    ];

    try {
      final response = await _httpClient
          .post(
            requestUri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': _systemPrompt(profile)},
                ],
              },
              'contents': contents,
              'generationConfig': {'temperature': 0.6},
            }),
          )
          .timeout(const Duration(seconds: 22));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _ExternalCallResult.failure(statusCode: response.statusCode);
      }

      final payload = jsonDecode(response.body);
      final candidate =
          ((payload is Map ? payload['candidates'] : null) as List?)
                  ?.firstOrNull
              as Map?;
      final parts =
          ((candidate?['content'] as Map?)?['parts'] as List?)?.cast<Map?>() ??
          const <Map?>[];
      final text = parts
          .map((part) => part?['text'])
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .join('\n')
          .trim();

      if (text.isEmpty) {
        return const _ExternalCallResult.failure();
      }

      return _ExternalCallResult.success(text);
    } on TimeoutException {
      return const _ExternalCallResult.timeout();
    } catch (_) {
      return const _ExternalCallResult.failure();
    }
  }

  bool _containsAny(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }
}

extension _ListFirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

enum _ProviderType { openAi, gemini }

class _ExternalCallResult {
  const _ExternalCallResult.success(this.text)
    : statusCode = null,
      timedOut = false;

  const _ExternalCallResult.failure({this.statusCode})
    : text = null,
      timedOut = false;

  const _ExternalCallResult.timeout()
    : text = null,
      statusCode = null,
      timedOut = true;

  final String? text;
  final int? statusCode;
  final bool timedOut;

  bool get isSuccess => text != null && text!.isNotEmpty;
}
