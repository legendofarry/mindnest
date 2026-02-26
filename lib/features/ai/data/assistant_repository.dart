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
const _externalAiProviderSource =
    'auto'; // auto | openai | gemini | groq | openrouter

// OpenAI-compatible config
const _externalAiApiKeySource = 'AIzaSyDZUxuK1aZj-pCpX78NTXBRTJ16YhCGG9o';
const _externalAiBaseUrlSource = 'https://api.openai.com/v1';
const _externalAiModelSource = 'gpt-4o-mini';
const _externalAiChatPathSource = '/chat/completions';

// Gemini config
const _geminiApiKeysSource = <String>[
  'AIzaSyDZUxuK1aZj-pCpX78NTXBRTJ16YhCGG9o',
];
const _geminiBaseUrlSource = 'https://generativelanguage.googleapis.com';
const _geminiModelSource = 'gemini-2.5-flash';
const _geminiGeneratePathSource = '/v1beta/models/{model}:generateContent';

// Groq (OpenAI-compatible) config
const _groqApiKeySource =
    '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';
const _groqBaseUrlSource = 'https://api.groq.com/openai/v1';
const _groqModelSource = 'llama-3.1-8b-instant';
const _groqChatPathSource = '/chat/completions';

// OpenRouter (OpenAI-compatible) config
const _openRouterApiKeySource =
    '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';
const _openRouterBaseUrlSource = 'https://openrouter.ai/api/v1';
const _openRouterModelSource = 'nvidia/nemotron-3-nano-30b-a3b:free';
const _openRouterChatPathSource = '/chat/completions';
const _openRouterHttpRefererSource = 'https://mindnest.app';
const _openRouterTitleSource = 'MindNest';

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
  static const String _geminiApiKeysFromDefine = String.fromEnvironment(
    'GEMINI_API_KEYS',
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
  static const String _groqApiKeyFromDefine = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );
  static const String _groqBaseUrlFromDefine = String.fromEnvironment(
    'GROQ_BASE_URL',
    defaultValue: '',
  );
  static const String _groqModelFromDefine = String.fromEnvironment(
    'GROQ_MODEL',
    defaultValue: '',
  );
  static const String _groqChatPathFromDefine = String.fromEnvironment(
    'GROQ_CHAT_PATH',
    defaultValue: '',
  );
  static const String _openRouterApiKeyFromDefine = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue: '',
  );
  static const String _openRouterBaseUrlFromDefine = String.fromEnvironment(
    'OPENROUTER_BASE_URL',
    defaultValue: '',
  );
  static const String _openRouterModelFromDefine = String.fromEnvironment(
    'OPENROUTER_MODEL',
    defaultValue: '',
  );
  static const String _openRouterChatPathFromDefine = String.fromEnvironment(
    'OPENROUTER_CHAT_PATH',
    defaultValue: '',
  );
  static const String _openRouterHttpRefererFromDefine = String.fromEnvironment(
    'OPENROUTER_HTTP_REFERER',
    defaultValue: '',
  );
  static const String _openRouterTitleFromDefine = String.fromEnvironment(
    'OPENROUTER_TITLE',
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

  List<String> get _geminiApiKeys {
    if (_geminiApiKeysFromDefine.isNotEmpty) {
      final keys = _parseApiKeys(_geminiApiKeysFromDefine);
      if (keys.isNotEmpty) {
        return keys;
      }
    }
    if (_geminiApiKeyFromDefine.isNotEmpty) {
      return <String>[_geminiApiKeyFromDefine.trim()];
    }
    return _geminiApiKeysSource
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
  }

  String get _geminiBaseUrl => _geminiBaseUrlFromDefine.isNotEmpty
      ? _geminiBaseUrlFromDefine
      : _geminiBaseUrlSource;

  String get _geminiModel => _geminiModelFromDefine.isNotEmpty
      ? _geminiModelFromDefine
      : _geminiModelSource;

  String get _geminiGeneratePath => _geminiGeneratePathFromDefine.isNotEmpty
      ? _geminiGeneratePathFromDefine
      : _geminiGeneratePathSource;

  String get _groqApiKey => _groqApiKeyFromDefine.isNotEmpty
      ? _groqApiKeyFromDefine
      : _groqApiKeySource;

  String get _groqBaseUrl => _groqBaseUrlFromDefine.isNotEmpty
      ? _groqBaseUrlFromDefine
      : _groqBaseUrlSource;

  String get _groqModel =>
      _groqModelFromDefine.isNotEmpty ? _groqModelFromDefine : _groqModelSource;

  String get _groqChatPath => _groqChatPathFromDefine.isNotEmpty
      ? _groqChatPathFromDefine
      : _groqChatPathSource;

  String get _openRouterApiKey => _openRouterApiKeyFromDefine.isNotEmpty
      ? _openRouterApiKeyFromDefine
      : _openRouterApiKeySource;

  String get _openRouterBaseUrl => _openRouterBaseUrlFromDefine.isNotEmpty
      ? _openRouterBaseUrlFromDefine
      : _openRouterBaseUrlSource;

  String get _openRouterModel => _openRouterModelFromDefine.isNotEmpty
      ? _openRouterModelFromDefine
      : _openRouterModelSource;

  String get _openRouterChatPath => _openRouterChatPathFromDefine.isNotEmpty
      ? _openRouterChatPathFromDefine
      : _openRouterChatPathSource;

  String get _openRouterHttpReferer =>
      _openRouterHttpRefererFromDefine.isNotEmpty
      ? _openRouterHttpRefererFromDefine
      : _openRouterHttpRefererSource;

  String get _openRouterTitle => _openRouterTitleFromDefine.isNotEmpty
      ? _openRouterTitleFromDefine
      : _openRouterTitleSource;

  bool get _openAiConfigured => _openAiApiKey.isNotEmpty;

  bool get _geminiConfigured => _geminiApiKeys.isNotEmpty;

  bool get _groqConfigured => _groqApiKey.isNotEmpty;

  bool get _openRouterConfigured => _openRouterApiKey.isNotEmpty;

  bool get _preferOpenAi => _provider == 'openai';

  bool get _preferGemini => _provider == 'gemini';

  bool get _preferGroq => _provider == 'groq';

  bool get _preferOpenRouter => _provider == 'openrouter';

  bool get _autoProvider => _provider.isEmpty || _provider == 'auto';

  Future<AssistantReply> processPrompt({
    required String prompt,
    required UserProfile profile,
    List<AssistantConversationMessage> history = const [],
    String memorySummary = '',
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
      memorySummary: memorySummary,
    );
  }

  bool _isInAppRequest(String text) {
    const appKeywords = <String>[
      'app',
      'mindnest',
      'my name',
      'my email',
      'my phone',
      'my number',
      'account',
      'profile',
      'theme',
      'dark mode',
      'light mode',
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
      'dashboard',
      'onboarding',
      'no show',
      'no-show',
      'noshow',
      'rating',
      'filter',
      'unread',
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
    if (_containsAny(text, const [
      'dark mode',
      'dark theme',
      'switch to dark',
      'turn on dark',
      'enable dark',
    ])) {
      return const AssistantReply(
        text: 'I can switch your app to dark mode.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Switch to Dark Mode',
            action: AssistantAction(type: AssistantActionType.setThemeDark),
          ),
        ],
      );
    }

    if (_containsAny(text, const [
      'light mode',
      'light theme',
      'switch to light',
      'turn on light',
      'enable light',
    ])) {
      return const AssistantReply(
        text: 'I can switch your app to light mode.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Switch to Light Mode',
            action: AssistantAction(type: AssistantActionType.setThemeLight),
          ),
        ],
      );
    }

    if (_isPersonalOrAccountQuestion(text)) {
      return _replyWithPersonalInfo(profile: profile, normalizedPrompt: text);
    }

    if (_containsAny(text, const ['notification', 'notifications', 'alerts'])) {
      return _replyWithNotifications(profile: profile, normalizedPrompt: text);
    }

    if (_containsAny(text, const ['care plan', 'goals', 'care goals'])) {
      return _replyWithCarePlan(profile: profile, normalizedPrompt: text);
    }

    if (_containsAny(text, const [
      'which counselor',
      'which counsellor',
      'seeing more',
      'seeing less',
      'no-show',
      'no show',
      'noshow',
      'attendance',
      'my sessions stats',
      'session stats',
    ])) {
      return _replyWithSessionStats(profile: profile, normalizedPrompt: text);
    }

    if (_containsAny(text, const [
      'about counselor',
      'about counsellor',
      'tell me about counselor',
      'tell me about counsellor',
      'specific counselor',
      'specific counsellor',
    ])) {
      final insight = await _replyWithCounselorInsight(
        profile: profile,
        rawPrompt: prompt,
      );
      if (insight != null) {
        return insight;
      }
    }

    final filterReply = _replyWithFilterActions(
      profile: profile,
      normalizedPrompt: text,
    );
    if (filterReply != null) {
      return filterReply;
    }

    if (_containsAny(text, const ['go live', 'start live', 'create live'])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text:
              'You need to join an organization before starting a live session.',
          suggestedActions: <AssistantSuggestedAction>[
            AssistantSuggestedAction(
              label: 'Join Institution',
              action: AssistantAction(
                type: AssistantActionType.openJoinInstitution,
              ),
            ),
          ],
        );
      }
      if (!_canUseLive(profile)) {
        return AssistantReply(
          text:
              'Your current role (${profile.role.label}) cannot start live sessions.',
        );
      }
      return const AssistantReply(
        text: 'I can take you to Live Hub and open create-live.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Go Live',
            action: AssistantAction(type: AssistantActionType.goLiveCreate),
          ),
        ],
      );
    }

    if (_containsAny(text, const ['live hub', 'join live', 'live session'])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text: 'Live Hub is available after you join an organization.',
          suggestedActions: <AssistantSuggestedAction>[
            AssistantSuggestedAction(
              label: 'Join Institution',
              action: AssistantAction(
                type: AssistantActionType.openJoinInstitution,
              ),
            ),
          ],
        );
      }
      if (!_canUseLive(profile)) {
        return AssistantReply(
          text:
              'Live Hub is only available for student, staff, or counselor roles. You are ${profile.role.label}.',
        );
      }
      return const AssistantReply(
        text: 'I can open Live Hub now.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Live Hub',
            action: AssistantAction(type: AssistantActionType.openLiveHub),
          ),
        ],
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
          suggestedActions: <AssistantSuggestedAction>[
            AssistantSuggestedAction(
              label: 'Join Institution',
              action: AssistantAction(
                type: AssistantActionType.openJoinInstitution,
              ),
            ),
          ],
        );
      }
      return const AssistantReply(
        text: 'I can open counselors for your organization.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Counselors',
            action: AssistantAction(type: AssistantActionType.openCounselors),
          ),
        ],
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
          suggestedActions: <AssistantSuggestedAction>[
            AssistantSuggestedAction(
              label: 'Join Institution',
              action: AssistantAction(
                type: AssistantActionType.openJoinInstitution,
              ),
            ),
          ],
        );
      }
      return const AssistantReply(
        text: 'I can open your sessions.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Sessions',
            action: AssistantAction(type: AssistantActionType.openSessions),
          ),
        ],
      );
    }

    if (_containsAny(text, const ['join institution', 'join organization'])) {
      return const AssistantReply(
        text: 'I can open Join Institution for you.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Join Institution',
            action: AssistantAction(
              type: AssistantActionType.openJoinInstitution,
            ),
          ),
        ],
      );
    }

    if (_containsAny(text, const ['privacy', 'data settings'])) {
      return const AssistantReply(
        text: 'I can open privacy controls.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Privacy',
            action: AssistantAction(type: AssistantActionType.openPrivacy),
          ),
        ],
      );
    }

    if (_containsAny(text, const ['how to book', 'book a slot'])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text:
              'To book a counselor slot, first join your organization from Join Institution.',
          suggestedActions: <AssistantSuggestedAction>[
            AssistantSuggestedAction(
              label: 'Join Institution',
              action: AssistantAction(
                type: AssistantActionType.openJoinInstitution,
              ),
            ),
          ],
        );
      }
      return const AssistantReply(
        text:
            'To book: open Counselors, choose a counselor, pick an available slot, and confirm.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Counselors',
            action: AssistantAction(type: AssistantActionType.openCounselors),
          ),
        ],
      );
    }

    return const AssistantReply(
      text:
          'I can help with your profile/account details, counselor insights, sessions and no-show stats, notifications, care plans, theme switch, and smart navigation with filters.',
    );
  }

  bool _isPersonalOrAccountQuestion(String text) {
    return _containsAny(text, const [
      'my name',
      'my email',
      'my phone',
      'my number',
      'my role',
      'who am i',
      'account',
      'institution name',
      'which institution',
      'when did i join',
      'when did i create',
      'when did i sign up',
      'profile info',
      'personal information',
    ]);
  }

  Future<AssistantReply> _replyWithPersonalInfo({
    required UserProfile profile,
    required String normalizedPrompt,
  }) async {
    final userDocSnap = await _firestore
        .collection('users')
        .doc(profile.id)
        .get();
    final userData = userDocSnap.data() ?? const <String, dynamic>{};

    final displayName = (userData['name'] as String?)?.trim().isNotEmpty == true
        ? (userData['name'] as String).trim()
        : profile.name;
    final email = (userData['email'] as String?)?.trim().isNotEmpty == true
        ? (userData['email'] as String).trim()
        : profile.email;
    final phone =
        (userData['phoneNumber'] as String?)?.trim() ??
        (userData['mobileNumber'] as String?)?.trim() ??
        (userData['phone'] as String?)?.trim() ??
        '';
    final createdAt =
        _asDate(userData['createdAt']) ??
        _auth.currentUser?.metadata.creationTime;
    final institutionName = (profile.institutionName ?? '').trim().isNotEmpty
        ? profile.institutionName!.trim()
        : 'Not linked';
    final joinedAt = await _fetchInstitutionJoinedAt(profile);

    if (_containsAny(normalizedPrompt, const ['my name', 'who am i'])) {
      return AssistantReply(text: 'Your name is $displayName.');
    }
    if (_containsAny(normalizedPrompt, const ['my email', 'email'])) {
      return AssistantReply(text: 'Your email is $email.');
    }
    if (_containsAny(normalizedPrompt, const [
      'my phone',
      'my number',
      'phone number',
    ])) {
      if (phone.isEmpty) {
        return const AssistantReply(
          text: 'I do not see a phone number saved on your profile yet.',
        );
      }
      return AssistantReply(text: 'Your phone number is $phone.');
    }
    if (_containsAny(normalizedPrompt, const [
      'when did i create',
      'when did i sign up',
      'account created',
      'mindnest account',
    ])) {
      if (createdAt == null) {
        return const AssistantReply(
          text: 'I could not find your account creation date right now.',
        );
      }
      return AssistantReply(
        text: 'Your MindNest account was created on ${_formatDate(createdAt)}.',
      );
    }
    if (_containsAny(normalizedPrompt, const [
      'institution name',
      'which institution',
      'name of my institution',
    ])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text: 'You are currently not linked to an institution.',
          suggestedActions: <AssistantSuggestedAction>[
            AssistantSuggestedAction(
              label: 'Join Institution',
              action: AssistantAction(
                type: AssistantActionType.openJoinInstitution,
              ),
            ),
          ],
        );
      }
      return AssistantReply(text: 'Your institution is $institutionName.');
    }
    if (_containsAny(normalizedPrompt, const [
      'when did i join my institution',
      'when did i join institution',
      'joined institution',
    ])) {
      if (!_hasInstitution(profile)) {
        return const AssistantReply(
          text: 'You are not linked to an institution yet.',
          suggestedActions: <AssistantSuggestedAction>[
            AssistantSuggestedAction(
              label: 'Join Institution',
              action: AssistantAction(
                type: AssistantActionType.openJoinInstitution,
              ),
            ),
          ],
        );
      }
      if (joinedAt == null) {
        return const AssistantReply(
          text: 'I could not determine your institution join date.',
        );
      }
      return AssistantReply(
        text: 'You joined your institution on ${_formatDate(joinedAt)}.',
      );
    }

    final joinedText = joinedAt == null ? 'Unknown' : _formatDate(joinedAt);
    final createdText = createdAt == null ? 'Unknown' : _formatDate(createdAt);
    final phoneText = phone.isEmpty ? 'Not set' : phone;
    return AssistantReply(
      text:
          'Here is your profile summary:\n'
          'Name: $displayName\n'
          'Email: $email\n'
          'Phone: $phoneText\n'
          'Role: ${profile.role.label}\n'
          'Institution: $institutionName\n'
          'Account created: $createdText\n'
          'Institution joined: $joinedText',
    );
  }

  Future<DateTime?> _fetchInstitutionJoinedAt(UserProfile profile) async {
    final institutionId = (profile.institutionId ?? '').trim();
    if (institutionId.isEmpty) {
      return null;
    }
    final directId = '${institutionId}_${profile.id}';
    final directDoc = await _firestore
        .collection('institution_members')
        .doc(directId)
        .get();
    if (directDoc.exists) {
      final data = directDoc.data() ?? const <String, dynamic>{};
      return _asDate(data['joinedAt']) ?? _asDate(data['createdAt']);
    }
    final fallback = await _firestore
        .collection('institution_members')
        .where('institutionId', isEqualTo: institutionId)
        .where('userId', isEqualTo: profile.id)
        .limit(1)
        .get();
    if (fallback.docs.isEmpty) {
      return null;
    }
    final data = fallback.docs.first.data();
    return _asDate(data['joinedAt']) ?? _asDate(data['createdAt']);
  }

  Future<AssistantReply> _replyWithNotifications({
    required UserProfile profile,
    required String normalizedPrompt,
  }) async {
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: profile.id)
        .limit(80)
        .get();
    final docs = snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList(growable: false);
    if (docs.isEmpty) {
      return const AssistantReply(
        text: 'You currently have no notifications.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Notifications',
            action: AssistantAction(
              type: AssistantActionType.openNotifications,
            ),
          ),
        ],
      );
    }

    docs.sort((a, b) {
      final aAt =
          _asDate(a['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt =
          _asDate(b['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });

    final unreadCount = docs.where((item) => item['isRead'] != true).length;
    if (_containsAny(normalizedPrompt, const ['unread', 'new notifications'])) {
      return AssistantReply(
        text: 'You have $unreadCount unread notifications.',
        suggestedActions: const <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Notifications',
            action: AssistantAction(
              type: AssistantActionType.openNotifications,
            ),
          ),
        ],
      );
    }

    final keywords = _extractIntentKeywords(normalizedPrompt);
    if (keywords.isNotEmpty &&
        _containsAny(normalizedPrompt, const [
          'about',
          'specific',
          'related',
        ])) {
      final filtered = docs
          .where((item) {
            final haystack =
                '${item['title'] ?? ''} ${item['body'] ?? ''} ${item['type'] ?? ''}'
                    .toLowerCase();
            return keywords.every(haystack.contains);
          })
          .toList(growable: false);
      if (filtered.isEmpty) {
        return AssistantReply(
          text:
              'I did not find notifications matching "${keywords.join(' ')}".',
          suggestedActions: const <AssistantSuggestedAction>[
            AssistantSuggestedAction(
              label: 'Open Notifications',
              action: AssistantAction(
                type: AssistantActionType.openNotifications,
              ),
            ),
          ],
        );
      }
      final lines = filtered
          .take(3)
          .map((item) {
            final when = _asDate(item['createdAt']);
            final label = when == null ? 'Unknown time' : _formatDate(when);
            return '- ${item['title'] ?? 'Notification'} ($label)';
          })
          .join('\n');
      return AssistantReply(
        text: 'I found ${filtered.length} matching notifications:\n$lines',
        suggestedActions: const <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Notifications',
            action: AssistantAction(
              type: AssistantActionType.openNotifications,
            ),
          ),
        ],
      );
    }

    final latest = docs.first;
    final latestWhen = _asDate(latest['createdAt']);
    final latestLabel = latestWhen == null
        ? 'Unknown time'
        : _formatDate(latestWhen);
    return AssistantReply(
      text:
          'You have ${docs.length} total notifications ($unreadCount unread).\n'
          'Latest: ${latest['title'] ?? 'Notification'} at $latestLabel.',
      suggestedActions: const <AssistantSuggestedAction>[
        AssistantSuggestedAction(
          label: 'Open Notifications',
          action: AssistantAction(type: AssistantActionType.openNotifications),
        ),
      ],
    );
  }

  Future<AssistantReply> _replyWithCarePlan({
    required UserProfile profile,
    required String normalizedPrompt,
  }) async {
    if (!_hasInstitution(profile)) {
      return const AssistantReply(
        text: 'Care plans are available after joining an institution.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Join Institution',
            action: AssistantAction(
              type: AssistantActionType.openJoinInstitution,
            ),
          ),
        ],
      );
    }

    QuerySnapshot<Map<String, dynamic>> snapshot;
    if (profile.role == UserRole.counselor) {
      snapshot = await _firestore
          .collection('care_goals')
          .where('counselorId', isEqualTo: profile.id)
          .where('institutionId', isEqualTo: profile.institutionId)
          .limit(80)
          .get();
    } else {
      snapshot = await _firestore
          .collection('care_goals')
          .where('studentId', isEqualTo: profile.id)
          .where('institutionId', isEqualTo: profile.institutionId)
          .limit(80)
          .get();
    }

    final goals = snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList(growable: false);
    if (goals.isEmpty) {
      return const AssistantReply(
        text: 'No care goals found yet.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Care Plan',
            action: AssistantAction(type: AssistantActionType.openCarePlan),
          ),
        ],
      );
    }

    final completed = goals
        .where((g) => (g['status'] as String?) == 'completed')
        .length;
    final active = goals.length - completed;
    goals.sort((a, b) {
      final aAt =
          _asDate(a['updatedAt']) ??
          _asDate(a['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bAt =
          _asDate(b['updatedAt']) ??
          _asDate(b['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });

    if (_containsAny(normalizedPrompt, const ['incomplete', 'active goals'])) {
      final lines = goals
          .where((g) => (g['status'] as String?) != 'completed')
          .take(5)
          .map((g) => '- ${g['title'] ?? 'Goal'} (${g['status'] ?? 'active'})')
          .join('\n');
      return AssistantReply(
        text: lines.isEmpty
            ? 'All your care goals are completed.'
            : 'Here are your active goals:\n$lines',
        suggestedActions: const <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Care Plan',
            action: AssistantAction(type: AssistantActionType.openCarePlan),
          ),
        ],
      );
    }

    final latest = goals.first;
    return AssistantReply(
      text:
          'You have ${goals.length} care goals: $active active and $completed completed.\n'
          'Most recent: ${latest['title'] ?? 'Goal'} (${latest['status'] ?? 'active'}).',
      suggestedActions: const <AssistantSuggestedAction>[
        AssistantSuggestedAction(
          label: 'Open Care Plan',
          action: AssistantAction(type: AssistantActionType.openCarePlan),
        ),
      ],
    );
  }

  Future<AssistantReply> _replyWithSessionStats({
    required UserProfile profile,
    required String normalizedPrompt,
  }) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    if (profile.role == UserRole.counselor) {
      snapshot = await _firestore
          .collection('appointments')
          .where('counselorId', isEqualTo: profile.id)
          .limit(300)
          .get();
    } else {
      snapshot = await _firestore
          .collection('appointments')
          .where('studentId', isEqualTo: profile.id)
          .limit(300)
          .get();
    }

    final records = snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList(growable: false);
    if (records.isEmpty) {
      return const AssistantReply(
        text: 'I could not find any sessions for your account yet.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Sessions',
            action: AssistantAction(type: AssistantActionType.openSessions),
          ),
        ],
      );
    }

    final counselorCounts = <String, int>{};
    var noShowByUser = 0;
    var noShowByCounselor = 0;
    var unknownNoShow = 0;
    var completed = 0;
    var upcoming = 0;
    final now = DateTime.now();

    for (final item in records) {
      final status = (item['status'] as String?)?.toLowerCase() ?? 'pending';
      final counselorId = (item['counselorId'] as String?) ?? '';
      final counselorName =
          (item['counselorName'] as String?)?.trim().isNotEmpty == true
          ? (item['counselorName'] as String).trim()
          : counselorId;
      if (counselorName.isNotEmpty) {
        counselorCounts[counselorName] =
            (counselorCounts[counselorName] ?? 0) + 1;
      }
      final start = _asDate(item['startAt']);
      if (start != null &&
          start.isAfter(now) &&
          (status == 'pending' || status == 'confirmed')) {
        upcoming++;
      }
      if (status == 'completed') {
        completed++;
      }
      if (status == 'noshow' || status == 'no_show' || status == 'no-show') {
        final attendance =
            (item['attendanceStatus'] as String?)?.toLowerCase() ?? '';
        if (attendance.contains('student') ||
            attendance.contains('client') ||
            attendance.contains('user')) {
          noShowByUser++;
        } else if (attendance.contains('counselor') ||
            attendance.contains('counsellor')) {
          noShowByCounselor++;
        } else {
          unknownNoShow++;
        }
      }
    }

    if (_containsAny(normalizedPrompt, const [
      'no-show',
      'no show',
      'noshow',
    ])) {
      return AssistantReply(
        text:
            'No-show summary:\n'
            '- You: $noShowByUser\n'
            '- Counselors: $noShowByCounselor\n'
            '- Unclassified: $unknownNoShow',
        suggestedActions: const <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Sessions',
            action: AssistantAction(type: AssistantActionType.openSessions),
          ),
        ],
      );
    }

    if (_containsAny(normalizedPrompt, const [
      'seeing more',
      'most',
      'seeing less',
      'least',
    ])) {
      if (counselorCounts.isEmpty) {
        return const AssistantReply(
          text: 'I could not determine counselor history yet.',
        );
      }
      final sorted = counselorCounts.entries.toList(growable: false)
        ..sort((a, b) => b.value.compareTo(a.value));
      final most = sorted.first;
      final least = sorted.last;
      return AssistantReply(
        text:
            'Counselor frequency:\n'
            '- Most seen: ${most.key} (${most.value} sessions)\n'
            '- Least seen: ${least.key} (${least.value} sessions)',
        suggestedActions: const <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Sessions',
            action: AssistantAction(type: AssistantActionType.openSessions),
          ),
        ],
      );
    }

    return AssistantReply(
      text:
          'Session summary:\n'
          '- Total: ${records.length}\n'
          '- Upcoming: $upcoming\n'
          '- Completed: $completed\n'
          '- No-shows (you/counselor): $noShowByUser / $noShowByCounselor',
      suggestedActions: const <AssistantSuggestedAction>[
        AssistantSuggestedAction(
          label: 'Open Sessions',
          action: AssistantAction(type: AssistantActionType.openSessions),
        ),
      ],
    );
  }

  Future<AssistantReply?> _replyWithCounselorInsight({
    required UserProfile profile,
    required String rawPrompt,
  }) async {
    final institutionId = (profile.institutionId ?? '').trim();
    if (institutionId.isEmpty) {
      return const AssistantReply(
        text: 'I can show counselor details after you join an institution.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Join Institution',
            action: AssistantAction(
              type: AssistantActionType.openJoinInstitution,
            ),
          ),
        ],
      );
    }

    final prompt = rawPrompt.toLowerCase();
    final keywordTokens = _extractIntentKeywords(prompt);
    final profiles = await _firestore
        .collection('counselor_profiles')
        .where('institutionId', isEqualTo: institutionId)
        .limit(120)
        .get();
    if (profiles.docs.isEmpty) {
      return const AssistantReply(
        text: 'There are no active counselor profiles available yet.',
      );
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? selected;
    var bestScore = 0;
    for (final doc in profiles.docs) {
      final data = doc.data();
      final name = ((data['displayName'] as String?) ?? '').toLowerCase();
      final specialization = ((data['specialization'] as String?) ?? '')
          .toLowerCase();
      final bio = ((data['bio'] as String?) ?? '').toLowerCase();
      var score = 0;
      if (prompt.contains(name) && name.isNotEmpty) {
        score += 10;
      }
      for (final token in keywordTokens) {
        if (token.length < 3) {
          continue;
        }
        if (name.contains(token)) {
          score += 4;
        }
        if (specialization.contains(token)) {
          score += 2;
        }
        if (bio.contains(token)) {
          score += 1;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        selected = doc;
      }
    }

    if (selected == null || bestScore < 2) {
      return const AssistantReply(
        text:
            'Tell me the counselor name (for example: "Tell me about counselor Mercy") and I will summarize their profile here.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Counselors',
            action: AssistantAction(type: AssistantActionType.openCounselors),
          ),
        ],
      );
    }

    final data = selected.data();
    final counselorId = selected.id;
    final displayName = (data['displayName'] as String?) ?? 'Counselor';
    final title = (data['title'] as String?) ?? 'Counselor';
    final specialization = (data['specialization'] as String?) ?? 'General';
    final mode = (data['sessionMode'] as String?) ?? 'Not specified';
    final yearsExperience = (data['yearsExperience'] as num?)?.toInt() ?? 0;
    final ratingAverage = (data['ratingAverage'] as num?)?.toDouble() ?? 0.0;
    final ratingCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
    final languagesRaw = data['languages'];
    final languages = <String>[];
    if (languagesRaw is List) {
      for (final item in languagesRaw) {
        if (item is String && item.trim().isNotEmpty) {
          languages.add(item.trim());
        }
      }
    }
    final bio = ((data['bio'] as String?) ?? '').trim();

    final availability = await _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: institutionId)
        .where('counselorId', isEqualTo: counselorId)
        .where('status', isEqualTo: 'available')
        .limit(20)
        .get();
    final now = DateTime.now().toUtc();
    final upcomingSlots =
        availability.docs
            .map((doc) => doc.data())
            .where((slot) {
              final end = _asDate(slot['endAt']);
              return end != null && end.toUtc().isAfter(now);
            })
            .toList(growable: false)
          ..sort((a, b) {
            final aStart =
                _asDate(a['startAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bStart =
                _asDate(b['startAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
            return aStart.compareTo(bStart);
          });

    final nextSlotText = upcomingSlots.isEmpty
        ? 'No open slots currently'
        : _formatSlotTime(_asDate(upcomingSlots.first['startAt'])!.toLocal());
    final bioText = bio.isEmpty
        ? ''
        : '\nBio: ${bio.length > 220 ? '${bio.substring(0, 220)}...' : bio}';
    final languagesText = languages.isEmpty
        ? 'Not listed'
        : languages.join(', ');

    return AssistantReply(
      text:
          '$displayName\n'
          '$title\n'
          'Specialization: $specialization\n'
          'Mode: $mode\n'
          'Experience: $yearsExperience years\n'
          'Rating: ${ratingAverage.toStringAsFixed(1)} ($ratingCount ratings)\n'
          'Languages: $languagesText\n'
          'Next open slot: $nextSlotText$bioText',
      suggestedActions: <AssistantSuggestedAction>[
        AssistantSuggestedAction(
          label: 'View Profile',
          action: AssistantAction(
            type: AssistantActionType.openCounselorProfile,
            params: <String, String>{'counselorId': counselorId},
          ),
        ),
        const AssistantSuggestedAction(
          label: 'Open Counselors',
          action: AssistantAction(type: AssistantActionType.openCounselors),
        ),
      ],
    );
  }

  AssistantReply? _replyWithFilterActions({
    required UserProfile profile,
    required String normalizedPrompt,
  }) {
    final hasInstitution = _hasInstitution(profile);
    if (!hasInstitution) {
      return null;
    }

    final status = _parseStatusFilter(normalizedPrompt);
    final wantsTimeline = _containsAny(normalizedPrompt, const ['timeline']);
    final wantsTable = _containsAny(normalizedPrompt, const ['table']);
    final wantsSessionFilter =
        _containsAny(normalizedPrompt, const ['session', 'appointment']) &&
        (status != null ||
            wantsTimeline ||
            wantsTable ||
            normalizedPrompt.contains('filter'));

    if (wantsSessionFilter) {
      final params = <String, String>{'aiq': _newActionToken()};
      if (status != null) {
        params['status'] = status;
      }
      if (wantsTimeline) {
        params['view'] = 'timeline';
      } else if (wantsTable) {
        params['view'] = 'table';
      }
      return AssistantReply(
        text:
            'I prepared a filtered Sessions view${status == null ? '' : ' for "$status"'}'
            '${wantsTimeline ? ' in timeline mode' : ''}.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Filtered Sessions',
            action: AssistantAction(
              type: AssistantActionType.openSessions,
              params: params,
            ),
          ),
        ],
      );
    }

    final wantsCounselorFilter =
        _containsAny(normalizedPrompt, const ['counselor', 'counsellor']) &&
        (normalizedPrompt.contains('filter') ||
            normalizedPrompt.contains('rating') ||
            normalizedPrompt.contains('virtual') ||
            normalizedPrompt.contains('in-person') ||
            normalizedPrompt.contains('in person'));
    if (wantsCounselorFilter) {
      final params = <String, String>{'aiq': _newActionToken()};
      final minRating = _parseRatingFilter(normalizedPrompt);
      if (minRating != null) {
        params['minRating'] = minRating.toStringAsFixed(1);
      }
      if (_containsAny(normalizedPrompt, const ['virtual', 'online'])) {
        params['mode'] = 'virtual';
      } else if (_containsAny(normalizedPrompt, const [
        'in-person',
        'in person',
      ])) {
        params['mode'] = 'in-person';
      }
      if (_containsAny(normalizedPrompt, const [
        'highest rated',
        'top rated',
      ])) {
        params['sort'] = 'rating';
      } else if (_containsAny(normalizedPrompt, const [
        'most experience',
        'experienced',
      ])) {
        params['sort'] = 'experience';
      }

      final extractedSearch = _extractSearchPhrase(normalizedPrompt);
      if (extractedSearch.isNotEmpty) {
        params['search'] = extractedSearch;
      }

      return AssistantReply(
        text: 'I prepared counselor filters from your request.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Filtered Counselors',
            action: AssistantAction(
              type: AssistantActionType.openCounselors,
              params: params,
            ),
          ),
        ],
      );
    }

    return null;
  }

  String _newActionToken() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  String? _parseStatusFilter(String text) {
    if (text.contains('confirmed')) return 'confirmed';
    if (text.contains('pending')) return 'pending';
    if (text.contains('completed')) return 'completed';
    if (text.contains('cancelled') || text.contains('canceled')) {
      return 'cancelled';
    }
    if (text.contains('no-show') ||
        text.contains('no show') ||
        text.contains('noshow')) {
      return 'noShow';
    }
    return null;
  }

  double? _parseRatingFilter(String text) {
    final pattern = RegExp(r'([3-5](?:\.\d)?)\s*\+?');
    final match = pattern.firstMatch(text);
    if (match == null) {
      return null;
    }
    final value = double.tryParse(match.group(1) ?? '');
    if (value == null || value < 0 || value > 5) {
      return null;
    }
    return value;
  }

  String _extractSearchPhrase(String text) {
    final markerIndex = text.indexOf('for ');
    if (markerIndex < 0) {
      return '';
    }
    final raw = text.substring(markerIndex + 4).trim();
    if (raw.isEmpty) {
      return '';
    }
    final tokens = raw
        .split(RegExp(r'[^a-z0-9]+'))
        .where((item) => item.trim().length >= 3)
        .take(4)
        .toList(growable: false);
    return tokens.join(' ');
  }

  List<String> _extractIntentKeywords(String text) {
    const stop = <String>{
      'the',
      'and',
      'for',
      'with',
      'about',
      'specific',
      'notification',
      'notifications',
      'counselor',
      'counsellor',
      'my',
      'me',
      'show',
      'tell',
      'what',
      'is',
      'are',
    };
    return text
        .split(RegExp(r'[^a-z0-9]+'))
        .map((item) => item.trim())
        .where((item) => item.length >= 3 && !stop.contains(item))
        .take(6)
        .toList(growable: false);
  }

  DateTime? _asDate(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    return null;
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  Future<AssistantReply> _replyWithOpenSlots(UserProfile profile) async {
    if (!_hasInstitution(profile)) {
      return const AssistantReply(
        text:
            'I cannot check counselor slots yet because you are not in an organization.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Join Institution',
            action: AssistantAction(
              type: AssistantActionType.openJoinInstitution,
            ),
          ),
        ],
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
          suggestedActions: <AssistantSuggestedAction>[
            AssistantSuggestedAction(
              label: 'Open Counselors',
              action: AssistantAction(type: AssistantActionType.openCounselors),
            ),
          ],
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
        suggestedActions: const <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Counselors',
            action: AssistantAction(type: AssistantActionType.openCounselors),
          ),
        ],
      );
    } catch (_) {
      return const AssistantReply(
        text:
            'I could not load slots right now. Opening counselors so you can check manually.',
        suggestedActions: <AssistantSuggestedAction>[
          AssistantSuggestedAction(
            label: 'Open Counselors',
            action: AssistantAction(type: AssistantActionType.openCounselors),
          ),
        ],
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
    required String memorySummary,
  }) async {
    if (_auth.currentUser == null) {
      return const AssistantReply(text: 'Please sign in to use AI chat.');
    }

    final hasOpenAi = _openAiConfigured;
    final hasGemini = _geminiConfigured;
    final hasGroq = _groqConfigured;
    final hasOpenRouter = _openRouterConfigured;

    if ((_preferOpenAi && !hasOpenAi) ||
        (_preferGemini && !hasGemini) ||
        (_preferGroq && !hasGroq) ||
        (_preferOpenRouter && !hasOpenRouter) ||
        (_autoProvider &&
            !hasOpenAi &&
            !hasGemini &&
            !hasGroq &&
            !hasOpenRouter)) {
      return AssistantReply(
        text: 'External AI is not configured yet. ${_configuredHint()}',
      );
    }

    final providerOrder = _providerSequence(
      hasOpenAi: hasOpenAi,
      hasGemini: hasGemini,
      hasGroq: hasGroq,
      hasOpenRouter: hasOpenRouter,
    );
    if (providerOrder.isEmpty) {
      return const AssistantReply(text: 'External AI is not configured yet.');
    }

    _ExternalCallResult? lastFailure;
    for (final provider in providerOrder) {
      final result = switch (provider) {
        _ProviderType.openAi => await _callOpenAi(
          prompt: prompt,
          profile: profile,
          history: history,
          memorySummary: memorySummary,
        ),
        _ProviderType.gemini => await _callGemini(
          prompt: prompt,
          profile: profile,
          history: history,
          memorySummary: memorySummary,
        ),
        _ProviderType.groq => await _callGroq(
          prompt: prompt,
          profile: profile,
          history: history,
          memorySummary: memorySummary,
        ),
        _ProviderType.openRouter => await _callOpenRouter(
          prompt: prompt,
          profile: profile,
          history: history,
          memorySummary: memorySummary,
        ),
      };
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

  String _systemPrompt(UserProfile profile, {String memorySummary = ''}) {
    final summary = memorySummary.trim();
    final summaryText = summary.isEmpty
        ? ''
        : ' Conversation memory summary: $summary';
    return 'You are MindNest assistant. Provide supportive, calm responses. '
        'For emergency self-harm/violence risk, advise immediate local emergency/crisis support. '
        'Do not claim to be a licensed therapist. '
        'User context: role=${profile.role.name}, institutionId=${profile.institutionId ?? ''}.$summaryText';
  }

  List<_ProviderType> _providerSequence({
    required bool hasOpenAi,
    required bool hasGemini,
    required bool hasGroq,
    required bool hasOpenRouter,
  }) {
    if (_preferOpenAi) {
      return <_ProviderType>[
        if (hasOpenAi) _ProviderType.openAi,
        if (hasGemini) _ProviderType.gemini,
        if (hasGroq) _ProviderType.groq,
        if (hasOpenRouter) _ProviderType.openRouter,
      ];
    }
    if (_preferGemini) {
      return <_ProviderType>[
        if (hasGemini) _ProviderType.gemini,
        if (hasOpenAi) _ProviderType.openAi,
        if (hasGroq) _ProviderType.groq,
        if (hasOpenRouter) _ProviderType.openRouter,
      ];
    }
    if (_preferGroq) {
      return <_ProviderType>[
        if (hasGroq) _ProviderType.groq,
        if (hasOpenAi) _ProviderType.openAi,
        if (hasGemini) _ProviderType.gemini,
        if (hasOpenRouter) _ProviderType.openRouter,
      ];
    }
    if (_preferOpenRouter) {
      return <_ProviderType>[
        if (hasOpenRouter) _ProviderType.openRouter,
        if (hasOpenAi) _ProviderType.openAi,
        if (hasGemini) _ProviderType.gemini,
        if (hasGroq) _ProviderType.groq,
      ];
    }
    // auto: default order is OpenAI, then Gemini, then Groq, then OpenRouter.
    return <_ProviderType>[
      if (hasOpenAi) _ProviderType.openAi,
      if (hasGemini) _ProviderType.gemini,
      if (hasGroq) _ProviderType.groq,
      if (hasOpenRouter) _ProviderType.openRouter,
    ];
  }

  String _providerLabel(List<_ProviderType> providers) {
    if (providers.length == 1) {
      return switch (providers.first) {
        _ProviderType.openAi => 'OpenAI',
        _ProviderType.gemini => 'Gemini',
        _ProviderType.groq => 'Groq',
        _ProviderType.openRouter => 'OpenRouter',
      };
    }
    return 'External AI';
  }

  String _configuredHint() {
    if (_preferOpenAi) {
      return 'Set OPENAI_API_KEY (or EXTERNAL_AI_API_KEY).';
    }
    if (_preferGemini) {
      return 'Set GEMINI_API_KEY or GEMINI_API_KEYS.';
    }
    if (_preferGroq) {
      return 'Set GROQ_API_KEY.';
    }
    if (_preferOpenRouter) {
      return 'Set OPENROUTER_API_KEY.';
    }
    return 'Set OPENAI_API_KEY/EXTERNAL_AI_API_KEY, GEMINI_API_KEY/GEMINI_API_KEYS, GROQ_API_KEY, or OPENROUTER_API_KEY.';
  }

  Future<_ExternalCallResult> _callOpenAi({
    required String prompt,
    required UserProfile profile,
    required List<AssistantConversationMessage> history,
    required String memorySummary,
  }) async {
    final chatUrl = Uri.parse('$_openAiBaseUrl$_openAiChatPath');
    final recentHistory = history.length > 8
        ? history.sublist(history.length - 8)
        : history;

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': _systemPrompt(profile, memorySummary: memorySummary),
      },
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
    required String memorySummary,
  }) async {
    final recentHistory = history.length > 8
        ? history.sublist(history.length - 8)
        : history;

    final resolvedPath = _geminiGeneratePath.replaceAll(
      '{model}',
      Uri.encodeComponent(_geminiModel),
    );
    final baseUri = Uri.parse('$_geminiBaseUrl$resolvedPath');

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

    _ExternalCallResult? lastFailure;
    for (final apiKey in _geminiApiKeys) {
      final query = <String, String>{...baseUri.queryParameters};
      query['key'] = apiKey;
      final requestUri = baseUri.replace(queryParameters: query);

      try {
        final response = await _httpClient
            .post(
              requestUri,
              headers: const <String, String>{
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'systemInstruction': {
                  'parts': [
                    {
                      'text': _systemPrompt(
                        profile,
                        memorySummary: memorySummary,
                      ),
                    },
                  ],
                },
                'contents': contents,
                'generationConfig': {'temperature': 0.6},
              }),
            )
            .timeout(const Duration(seconds: 22));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final failed = _ExternalCallResult.failure(
            statusCode: response.statusCode,
          );
          lastFailure = failed;
          // Try next key on auth/quota/rate-limit/transient failures.
          final canTryNext =
              response.statusCode == 401 ||
              response.statusCode == 403 ||
              response.statusCode == 429 ||
              response.statusCode >= 500;
          if (canTryNext) {
            continue;
          }
          return failed;
        }

        final payload = jsonDecode(response.body);
        final candidate =
            ((payload is Map ? payload['candidates'] : null) as List?)
                    ?.firstOrNull
                as Map?;
        final parts =
            ((candidate?['content'] as Map?)?['parts'] as List?)
                ?.cast<Map?>() ??
            const <Map?>[];
        final text = parts
            .map((part) => part?['text'])
            .whereType<String>()
            .map((entry) => entry.trim())
            .where((entry) => entry.isNotEmpty)
            .join('\n')
            .trim();

        if (text.isEmpty) {
          final failed = const _ExternalCallResult.failure();
          lastFailure = failed;
          continue;
        }

        return _ExternalCallResult.success(text);
      } on TimeoutException {
        lastFailure = const _ExternalCallResult.timeout();
        continue;
      } catch (_) {
        lastFailure = const _ExternalCallResult.failure();
        continue;
      }
    }

    return lastFailure ?? const _ExternalCallResult.failure();
  }

  Future<_ExternalCallResult> _callGroq({
    required String prompt,
    required UserProfile profile,
    required List<AssistantConversationMessage> history,
    required String memorySummary,
  }) async {
    final chatUrl = Uri.parse('$_groqBaseUrl$_groqChatPath');
    final recentHistory = history.length > 8
        ? history.sublist(history.length - 8)
        : history;

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': _systemPrompt(profile, memorySummary: memorySummary),
      },
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
              'Authorization': 'Bearer $_groqApiKey',
            },
            body: jsonEncode({
              'model': _groqModel,
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

  Future<_ExternalCallResult> _callOpenRouter({
    required String prompt,
    required UserProfile profile,
    required List<AssistantConversationMessage> history,
    required String memorySummary,
  }) async {
    final chatUrl = Uri.parse('$_openRouterBaseUrl$_openRouterChatPath');
    final recentHistory = history.length > 8
        ? history.sublist(history.length - 8)
        : history;

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': _systemPrompt(profile, memorySummary: memorySummary),
      },
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
              'Authorization': 'Bearer $_openRouterApiKey',
              'HTTP-Referer': _openRouterHttpReferer,
              'X-Title': _openRouterTitle,
            },
            body: jsonEncode({
              'model': _openRouterModel,
              'messages': messages,
              'temperature': 0.6,
            }),
          )
          .timeout(const Duration(seconds: 22));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _ExternalCallResult.failure(statusCode: response.statusCode);
      }

      final payload = jsonDecode(response.body);
      final message =
          (((payload is Map ? payload['choices'] : null) as List?)?.firstOrNull
                  as Map?)?['message']
              as Map?;
      final content = (message?['content'] as String?)?.trim() ?? '';
      final reasoning = (message?['reasoning'] as String?)?.trim() ?? '';
      final text = content.isNotEmpty ? content : reasoning;

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

  List<String> _parseApiKeys(String raw) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final entry in raw.split(',')) {
      final key = entry.trim();
      if (key.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      ordered.add(key);
    }
    return ordered;
  }
}

extension _ListFirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

enum _ProviderType { openAi, gemini, groq, openRouter }

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
