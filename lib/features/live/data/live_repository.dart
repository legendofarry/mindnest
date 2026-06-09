// features/live/data/live_repository.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/core/data/windows_firestore_rest_client.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/models/app_auth_user.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/live/models/live_comment.dart';
import 'package:mindnest/features/live/models/live_mic_request.dart';
import 'package:mindnest/features/live/models/live_participant.dart';
import 'package:mindnest/features/live/models/live_reaction_event.dart';
import 'package:mindnest/features/live/models/live_session.dart';

class LiveKitJoinCredentials {
  const LiveKitJoinCredentials({
    required this.serverUrl,
    required this.token,
    required this.roomName,
    required this.canPublishAudio,
  });

  final String serverUrl;
  final String token;
  final String roomName;
  final bool canPublishAudio;
}

class MemberPublicProfile {
  const MemberPublicProfile({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.email,
    this.subtitle,
  });

  final String userId;
  final String displayName;
  final String role;
  final String email;
  final String? subtitle;
}

class LiveRepository {
  LiveRepository({
    required FirebaseFirestore Function()? firestoreFactory,
    required AppAuthClient auth,
    required http.Client httpClient,
    required WindowsFirestoreRestClient windowsRest,
  }) : _firestoreFactory = firestoreFactory,
       _auth = auth,
       _httpClient = httpClient,
       _windowsRest = windowsRest;

  final FirebaseFirestore Function()? _firestoreFactory;
  FirebaseFirestore? _cachedFirestore;
  final AppAuthClient _auth;
  final http.Client _httpClient;
  final WindowsFirestoreRestClient _windowsRest;
  int _windowsRestIdCounter = 0;
  static const Duration _windowsPollInterval = Duration(seconds: 15);

  static const Set<String> _allowedCreatorRoles = <String>{
    'student',
    'staff',
    'counselor',
  };
  static const String _liveKitUrlFromDefine = String.fromEnvironment(
    'LIVEKIT_URL',
    defaultValue: '',
  );
  static const String _liveKitApiKeyFromDefine = String.fromEnvironment(
    'LIVEKIT_API_KEY',
    defaultValue: '',
  );
  static const String _liveKitApiSecretFromDefine = String.fromEnvironment(
    'LIVEKIT_API_SECRET',
    defaultValue: '',
  );
  static const String _liveKitTokenEndpointFromDefine = String.fromEnvironment(
    'LIVEKIT_TOKEN_ENDPOINT',
    defaultValue: '',
  );
  static const String _pushDispatchEndpointFromDefine = String.fromEnvironment(
    'PUSH_DISPATCH_ENDPOINT',
    defaultValue: '',
  );
  // Source-file fallback for local/dev use when --dart-define values are absent.
  // Keep secrets blank in source; web must use LIVEKIT_TOKEN_ENDPOINT.
  static const String _liveKitUrlFromSource = '';
  static const String _liveKitApiKeyFromSource = '';
  static const String _liveKitApiSecretFromSource = '';
  static const String _liveKitTokenEndpointFromSource = '';

  static String get _liveKitUrl => _liveKitUrlFromDefine.isNotEmpty
      ? _liveKitUrlFromDefine
      : _liveKitUrlFromSource;
  static String get _liveKitApiKey => _liveKitApiKeyFromDefine.isNotEmpty
      ? _liveKitApiKeyFromDefine
      : _liveKitApiKeyFromSource;
  static String get _liveKitApiSecret => _liveKitApiSecretFromDefine.isNotEmpty
      ? _liveKitApiSecretFromDefine
      : _liveKitApiSecretFromSource;
  static String get _liveKitTokenEndpoint {
    if (_liveKitTokenEndpointFromDefine.trim().isNotEmpty) {
      return _liveKitTokenEndpointFromDefine.trim();
    }
    if (_liveKitTokenEndpointFromSource.trim().isNotEmpty) {
      return _liveKitTokenEndpointFromSource.trim();
    }
    return _deriveTokenEndpointFromPushEndpoint(
      _pushDispatchEndpointFromDefine,
    );
  }

  static String _deriveTokenEndpointFromPushEndpoint(String pushEndpoint) {
    final trimmed = pushEndpoint.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      final uri = Uri.parse(trimmed);
      if (!uri.hasScheme || uri.host.isEmpty) {
        return '';
      }
      // Replace path with a conventional livekit token endpoint path.
      return uri.replace(path: '/livekit/token').toString();
    } catch (_) {
      return '';
    }
  }

  CollectionReference<Map<String, dynamic>> get _liveCollection =>
      _firestore.collection('live_sessions');

  bool get _useWindowsPollingWorkaround =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  FirebaseFirestore get _firestore => _cachedFirestore ??=
      _firestoreFactory?.call() ??
      (throw StateError(
        'Native Firestore is disabled for Windows REST auth flows.',
      ));

  String _windowsDocId(String prefix) {
    _windowsRestIdCounter += 1;
    return '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_$_windowsRestIdCounter';
  }

  Future<Map<String, dynamic>> _currentUserDoc() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (kUseWindowsRestAuth) {
      final userDoc = await _windowsRest.getDocument('users/${user.uid}');
      if (userDoc == null) {
        throw Exception('User profile not found.');
      }
      return userDoc.data;
    }
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!userDoc.exists || userDoc.data() == null) {
      throw Exception('User profile not found.');
    }
    return userDoc.data()!;
  }

  Future<(AppAuthUser, Map<String, dynamic>)> _requireSessionContext() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    final userData = await _currentUserDoc();
    return (user, userData);
  }

  Stream<List<LiveSession>> watchInstitutionLives({
    required String institutionId,
  }) {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const <LiveSession>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<LiveSession>>(
        load: () => getInstitutionLives(institutionId: normalized),
        signature: _liveSessionsSignature,
      );
    }
    return _liveCollection
        .where('institutionId', isEqualTo: normalized)
        .where(
          'status',
          whereIn: <String>[
            LiveSessionStatus.live.name,
            LiveSessionStatus.paused.name,
          ],
        )
        .snapshots()
        .map((snapshot) {
          final lives = snapshot.docs
              .map((doc) => LiveSession.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          lives.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return lives;
        });
  }

  Stream<LiveSession?> watchLiveSession(String sessionId) {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(null);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<LiveSession?>(
        load: () => getLiveSession(normalized),
        signature: _liveSessionSignature,
      );
    }
    return _liveCollection.doc(normalized).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return LiveSession.fromMap(doc.id, doc.data()!);
    });
  }

  Stream<List<LiveParticipant>> watchParticipants(String sessionId) {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const <LiveParticipant>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<LiveParticipant>>(
        load: () => getParticipants(normalized),
        signature: _participantsSignature,
      );
    }
    return _liveCollection
        .doc(normalized)
        .collection('participants')
        .snapshots()
        .map((snapshot) {
          final participants = snapshot.docs
              .map((doc) => LiveParticipant.fromMap(doc.data()))
              .where((entry) => !entry.removed)
              .toList(growable: false);
          participants.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
          return participants;
        });
  }

  Stream<LiveParticipant?> watchMyParticipant(String sessionId) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream<LiveParticipant?>.empty();
    }
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(null);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<LiveParticipant?>(
        load: () => getMyParticipant(normalized),
        signature: _participantSignature,
      );
    }
    return _liveCollection
        .doc(normalized)
        .collection('participants')
        .doc(user.uid)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) {
            return null;
          }
          return LiveParticipant.fromMap(doc.data()!);
        });
  }

  Stream<List<LiveComment>> watchComments(String sessionId) {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const <LiveComment>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<LiveComment>>(
        load: () => getComments(normalized),
        signature: _commentsSignature,
      );
    }
    return _liveCollection
        .doc(normalized)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(120)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => LiveComment.fromMap(doc.id, doc.data()))
              .toList(growable: false);
        });
  }

  Stream<List<LiveReactionEvent>> watchReactions(String sessionId) {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const <LiveReactionEvent>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<LiveReactionEvent>>(
        load: () => getReactions(normalized),
        signature: _reactionsSignature,
      );
    }
    return _liveCollection
        .doc(normalized)
        .collection('reactions')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => LiveReactionEvent.fromMap(doc.id, doc.data()))
              .toList(growable: false);
        });
  }

  Stream<List<LiveMicRequest>> watchPendingMicRequests(String sessionId) {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const <LiveMicRequest>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<LiveMicRequest>>(
        load: () => getPendingMicRequests(normalized),
        signature: _micRequestsSignature,
      );
    }
    return _liveCollection
        .doc(normalized)
        .collection('mic_requests')
        .where('status', isEqualTo: MicRequestStatus.pending.name)
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => LiveMicRequest.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          requests.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return requests;
        });
  }

  Future<List<LiveSession>> getInstitutionLives({
    required String institutionId,
  }) async {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return const <LiveSession>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'live_sessions',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', normalized),
          WindowsFirestoreFieldFilter.inList('status', <String>[
            LiveSessionStatus.live.name,
            LiveSessionStatus.paused.name,
          ]),
        ],
      );
      final lives = documents
          .map((doc) => LiveSession.fromMap(doc.id, doc.data))
          .toList(growable: false);
      lives.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return lives;
    }
    final snapshot = await _liveCollection
        .where('institutionId', isEqualTo: normalized)
        .where(
          'status',
          whereIn: <String>[
            LiveSessionStatus.live.name,
            LiveSessionStatus.paused.name,
          ],
        )
        .get();
    final lives = snapshot.docs
        .map((doc) => LiveSession.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    lives.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return lives;
  }

  Future<LiveSession?> getLiveSession(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (kUseWindowsRestAuth) {
      final document = await _windowsRest.getDocument(
        'live_sessions/$normalized',
      );
      if (document == null) {
        return null;
      }
      return LiveSession.fromMap(document.id, document.data);
    }
    final doc = await _liveCollection.doc(normalized).get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return LiveSession.fromMap(doc.id, doc.data()!);
  }

  Future<List<LiveParticipant>> getParticipants(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return const <LiveParticipant>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        parentPath: 'live_sessions/$normalized',
        collectionId: 'participants',
      );
      final participants = documents
          .map((doc) => LiveParticipant.fromMap(doc.data))
          .where((entry) => !entry.removed)
          .toList(growable: false);
      participants.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
      return participants;
    }
    final snapshot = await _liveCollection
        .doc(normalized)
        .collection('participants')
        .get();
    final participants = snapshot.docs
        .map((doc) => LiveParticipant.fromMap(doc.data()))
        .where((entry) => !entry.removed)
        .toList(growable: false);
    participants.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    return participants;
  }

  Future<LiveParticipant?> getMyParticipant(String sessionId) async {
    final user = _auth.currentUser;
    final normalized = sessionId.trim();
    if (user == null || normalized.isEmpty) {
      return null;
    }
    if (kUseWindowsRestAuth) {
      final document = await _windowsRest.getDocument(
        'live_sessions/$normalized/participants/${user.uid}',
      );
      if (document == null) {
        return null;
      }
      return LiveParticipant.fromMap(document.data);
    }
    final doc = await _liveCollection
        .doc(normalized)
        .collection('participants')
        .doc(user.uid)
        .get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return LiveParticipant.fromMap(doc.data()!);
  }

  Future<List<LiveComment>> getComments(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return const <LiveComment>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        parentPath: 'live_sessions/$normalized',
        collectionId: 'comments',
        orderBy: const <WindowsFirestoreOrderBy>[
          WindowsFirestoreOrderBy('createdAt', descending: true),
        ],
        limit: 120,
      );
      return documents
          .map((doc) => LiveComment.fromMap(doc.id, doc.data))
          .toList(growable: false);
    }
    final snapshot = await _liveCollection
        .doc(normalized)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(120)
        .get();
    return snapshot.docs
        .map((doc) => LiveComment.fromMap(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<LiveReactionEvent>> getReactions(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return const <LiveReactionEvent>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        parentPath: 'live_sessions/$normalized',
        collectionId: 'reactions',
        orderBy: const <WindowsFirestoreOrderBy>[
          WindowsFirestoreOrderBy('createdAt', descending: true),
        ],
        limit: 80,
      );
      return documents
          .map((doc) => LiveReactionEvent.fromMap(doc.id, doc.data))
          .toList(growable: false);
    }
    final snapshot = await _liveCollection
        .doc(normalized)
        .collection('reactions')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .get();
    return snapshot.docs
        .map((doc) => LiveReactionEvent.fromMap(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<LiveMicRequest>> getPendingMicRequests(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return const <LiveMicRequest>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        parentPath: 'live_sessions/$normalized',
        collectionId: 'mic_requests',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal(
            'status',
            MicRequestStatus.pending.name,
          ),
        ],
      );
      final requests = documents
          .map((doc) => LiveMicRequest.fromMap(doc.id, doc.data))
          .toList(growable: false);
      requests.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return requests;
    }
    final snapshot = await _liveCollection
        .doc(normalized)
        .collection('mic_requests')
        .where('status', isEqualTo: MicRequestStatus.pending.name)
        .get();
    final requests = snapshot.docs
        .map((doc) => LiveMicRequest.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    requests.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return requests;
  }

  String _liveSessionsSignature(List<LiveSession> sessions) => sessions
      .map(
        (session) =>
            '${session.id}|${session.status.name}|${session.likeCount}|${session.startedAt?.toIso8601String() ?? ''}|${session.endedAt?.toIso8601String() ?? ''}',
      )
      .join(';');

  String _liveSessionSignature(LiveSession? session) {
    if (session == null) {
      return 'null';
    }
    return '${session.id}|${session.status.name}|${session.likeCount}|${session.startedAt?.toIso8601String() ?? ''}|${session.endedAt?.toIso8601String() ?? ''}';
  }

  String _participantsSignature(List<LiveParticipant> participants) =>
      participants.map(_participantSignature).join(';');

  String _participantSignature(LiveParticipant? participant) {
    if (participant == null) {
      return 'null';
    }
    return '${participant.userId}|${participant.kind.name}|${participant.canSpeak}|${participant.micEnabled}|${participant.mutedByHost}|${participant.joinedAt.toIso8601String()}|${participant.lastSeenAt.toIso8601String()}|${participant.removed}';
  }

  String _commentsSignature(List<LiveComment> comments) => comments
      .map(
        (comment) =>
            '${comment.id}|${comment.userId}|${comment.createdAt.toIso8601String()}|${comment.text}',
      )
      .join(';');

  String _reactionsSignature(List<LiveReactionEvent> reactions) => reactions
      .map(
        (reaction) =>
            '${reaction.id}|${reaction.userId}|${reaction.emoji}|${reaction.createdAt.toIso8601String()}',
      )
      .join(';');

  String _micRequestsSignature(List<LiveMicRequest> requests) => requests
      .map(
        (request) =>
            '${request.id}|${request.userId}|${request.status.name}|${request.createdAt.toIso8601String()}',
      )
      .join(';');

  Stream<T> _buildWindowsPollingStream<T>({
    required Future<T> Function() load,
    required String Function(T value) signature,
  }) {
    late final StreamController<T> controller;
    Timer? timer;
    String? lastEmissionSignature;

    Future<void> emitIfChanged() async {
      if (controller.isClosed) {
        return;
      }
      try {
        final value = await load();
        final nextSignature = 'value:${signature(value)}';
        if (nextSignature == lastEmissionSignature) {
          return;
        }
        lastEmissionSignature = nextSignature;
        if (!controller.isClosed) {
          controller.add(value);
        }
      } catch (error, stackTrace) {
        final nextSignature = 'error:$error';
        if (nextSignature == lastEmissionSignature) {
          return;
        }
        lastEmissionSignature = nextSignature;
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<T>(
      onListen: () {
        unawaited(emitIfChanged());
        timer = Timer.periodic(_windowsPollInterval, (_) {
          unawaited(emitIfChanged());
        });
      },
      onCancel: () async {
        timer?.cancel();
        await controller.close();
      },
    );

    return controller.stream;
  }

  Future<LiveSession> createLiveSession({
    required String title,
    required String description,
    required List<UserRole> allowedRoles,
  }) async {
    final (user, userData) = await _requireSessionContext();
    final institutionId = (userData['institutionId'] as String?) ?? '';
    final role = (userData['role'] as String?) ?? UserRole.other.name;

    if (institutionId.isEmpty) {
      throw Exception('Join an institution to create a live session.');
    }
    if (!_allowedCreatorRoles.contains(role)) {
      throw Exception('Your role cannot start a live session.');
    }
    final cleanTitle = title.trim();
    if (cleanTitle.length < 4) {
      throw Exception('Title must be at least 4 characters.');
    }
    if (allowedRoles.isEmpty) {
      throw Exception('Select at least one allowed role.');
    }

    final sessionId = _useWindowsPollingWorkaround
        ? _windowsDocId('live')
        : _liveCollection.doc().id;
    final hostName =
        (userData['name'] as String?) ?? user.displayName ?? user.email;

    if (_useWindowsPollingWorkaround) {
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('live_sessions/$sessionId', {
        'institutionId': institutionId,
        'createdBy': user.uid,
        'hostName': hostName,
        'hostRole': role,
        'title': cleanTitle,
        'description': description.trim(),
        'status': LiveSessionStatus.live.name,
        'allowedRoles': allowedRoles.map((entry) => entry.name).toList(),
        'maxGuests': 20,
        'likeCount': 0,
        'roomName': 'mindnest_live_$sessionId',
        'createdAt': now,
        'startedAt': now,
        'updatedAt': now,
      });
      await _windowsRest
          .setDocument('live_sessions/$sessionId/participants/${user.uid}', {
            'userId': user.uid,
            'displayName': hostName,
            'role': role,
            'kind': LiveParticipantKind.host.name,
            'canSpeak': true,
            'micEnabled': true,
            'mutedByHost': false,
            'removed': false,
            'lastReactionAt': null,
            'joinedAt': now,
            'lastSeenAt': now,
            'updatedAt': now,
          });
      final created = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      return LiveSession.fromMap(sessionId, created?.data ?? const {});
    }

    final liveRef = _liveCollection.doc(sessionId);
    await liveRef.set({
      'institutionId': institutionId,
      'createdBy': user.uid,
      'hostName': hostName,
      'hostRole': role,
      'title': cleanTitle,
      'description': description.trim(),
      'status': LiveSessionStatus.live.name,
      'allowedRoles': allowedRoles.map((entry) => entry.name).toList(),
      'maxGuests': 20,
      'likeCount': 0,
      'roomName': 'mindnest_live_${liveRef.id}',
      'createdAt': FieldValue.serverTimestamp(),
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await liveRef.collection('participants').doc(user.uid).set({
      'userId': user.uid,
      'displayName': hostName,
      'role': role,
      'kind': LiveParticipantKind.host.name,
      'canSpeak': true,
      'micEnabled': true,
      'mutedByHost': false,
      'removed': false,
      'lastReactionAt': null,
      'joinedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final created = await liveRef.get();
    return LiveSession.fromMap(created.id, created.data()!);
  }

  Future<LiveSession> joinLiveSession(String sessionId) async {
    final (user, userData) = await _requireSessionContext();
    final role = (userData['role'] as String?) ?? UserRole.other.name;
    final institutionId = (userData['institutionId'] as String?) ?? '';
    final userName =
        (userData['name'] as String?) ?? user.displayName ?? user.email;

    if (_useWindowsPollingWorkaround) {
      final sessionDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      if (sessionDoc == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionDoc.id, sessionDoc.data);
      if (!session.isActive) {
        throw Exception('This live session already ended.');
      }
      if (session.institutionId != institutionId) {
        throw Exception('This live session belongs to another institution.');
      }

      final currentRole = UserRole.values.firstWhere(
        (entry) => entry.name == role,
        orElse: () => UserRole.other,
      );
      if (!session.canRoleJoin(currentRole)) {
        throw Exception('This session is restricted for your role.');
      }

      final participantDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId/participants/${user.uid}',
      );
      final now = DateTime.now().toUtc();
      if (participantDoc != null) {
        await _windowsRest.setDocument(
          'live_sessions/$sessionId/participants/${user.uid}',
          {
            ...participantDoc.data,
            'removed': false,
            'lastSeenAt': now,
            'updatedAt': now,
          },
        );
      } else {
        final isHost = session.createdBy == user.uid;
        await _windowsRest
            .setDocument('live_sessions/$sessionId/participants/${user.uid}', {
              'userId': user.uid,
              'displayName': userName,
              'role': role,
              'kind': isHost
                  ? LiveParticipantKind.host.name
                  : LiveParticipantKind.listener.name,
              'canSpeak': isHost,
              'micEnabled': isHost,
              'mutedByHost': false,
              'removed': false,
              'lastReactionAt': null,
              'joinedAt': now,
              'lastSeenAt': now,
              'updatedAt': now,
            });
      }
      return session;
    }

    final sessionRef = _liveCollection.doc(sessionId);
    final participantRef = sessionRef.collection('participants').doc(user.uid);

    return _firestore.runTransaction((transaction) async {
      final sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists || sessionSnap.data() == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionSnap.id, sessionSnap.data()!);
      if (!session.isActive) {
        throw Exception('This live session already ended.');
      }
      if (session.institutionId != institutionId) {
        throw Exception('This live session belongs to another institution.');
      }

      final currentRole = UserRole.values.firstWhere(
        (entry) => entry.name == role,
        orElse: () => UserRole.other,
      );
      if (!session.canRoleJoin(currentRole)) {
        throw Exception('This session is restricted for your role.');
      }

      final participantSnap = await transaction.get(participantRef);
      if (participantSnap.exists && participantSnap.data() != null) {
        transaction.update(participantRef, {
          'removed': false,
          'lastSeenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final isHost = session.createdBy == user.uid;
        transaction.set(participantRef, {
          'userId': user.uid,
          'displayName': userName,
          'role': role,
          'kind': isHost
              ? LiveParticipantKind.host.name
              : LiveParticipantKind.listener.name,
          'canSpeak': isHost,
          'micEnabled': isHost,
          'mutedByHost': false,
          'removed': false,
          'lastReactionAt': null,
          'joinedAt': FieldValue.serverTimestamp(),
          'lastSeenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return session;
    });
  }

  Future<void> touchPresence(String sessionId) async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    if (_useWindowsPollingWorkaround) {
      final existing = await _windowsRest.getDocument(
        'live_sessions/$sessionId/participants/${user.uid}',
      );
      if (existing == null) {
        return;
      }
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument(
        'live_sessions/$sessionId/participants/${user.uid}',
        {...existing.data, 'lastSeenAt': now, 'updatedAt': now},
      );
      return;
    }
    await _liveCollection
        .doc(sessionId)
        .collection('participants')
        .doc(user.uid)
        .set({
          'lastSeenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> leaveLiveSession(String sessionId) async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    if (_useWindowsPollingWorkaround) {
      final sessionDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      if (sessionDoc == null) {
        return;
      }
      final session = LiveSession.fromMap(sessionDoc.id, sessionDoc.data);
      final participantDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId/participants/${user.uid}',
      );
      if (participantDoc == null) {
        return;
      }
      final participant = LiveParticipant.fromMap(participantDoc.data);
      final now = DateTime.now().toUtc();
      await _windowsRest.deleteDocument(
        'live_sessions/$sessionId/participants/${user.uid}',
      );
      await _windowsRest.deleteDocument(
        'live_sessions/$sessionId/mic_requests/${user.uid}',
      );
      await _windowsRest.setDocument('live_sessions/$sessionId', {
        ...sessionDoc.data,
        'updatedAt': now,
        if (participant.isHost && session.isActive) ...<String, dynamic>{
          'status': LiveSessionStatus.ended.name,
          'endedAt': now,
          'endedByHostDisconnect': true,
        },
      });
      if (participant.isHost && session.isActive) {
        await _cleanupEphemeralCollections(sessionId);
      }
      return;
    }
    final sessionRef = _liveCollection.doc(sessionId);
    final participantRef = sessionRef.collection('participants').doc(user.uid);

    bool shouldCleanup = false;
    await _firestore.runTransaction((transaction) async {
      final sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists || sessionSnap.data() == null) {
        return;
      }
      final session = LiveSession.fromMap(sessionSnap.id, sessionSnap.data()!);
      final participantSnap = await transaction.get(participantRef);
      if (!participantSnap.exists || participantSnap.data() == null) {
        return;
      }
      final participant = LiveParticipant.fromMap(participantSnap.data()!);

      transaction.delete(participantRef);
      transaction.delete(sessionRef.collection('mic_requests').doc(user.uid));
      transaction.update(sessionRef, {
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (participant.isHost && session.isActive) {
        transaction.update(sessionRef, {
          'status': LiveSessionStatus.ended.name,
          'endedAt': FieldValue.serverTimestamp(),
          'endedByHostDisconnect': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        shouldCleanup = true;
      }
    });

    if (shouldCleanup) {
      await _cleanupEphemeralCollections(sessionId);
    }
  }

  Future<void> togglePause({
    required String sessionId,
    required bool pause,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (_useWindowsPollingWorkaround) {
      final sessionDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      if (sessionDoc == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionDoc.id, sessionDoc.data);
      if (session.createdBy != user.uid) {
        throw Exception('Only the host can control this live.');
      }
      if (!session.isActive) {
        throw Exception('This live is already ended.');
      }
      await _windowsRest.setDocument('live_sessions/$sessionId', {
        ...sessionDoc.data,
        'status': pause
            ? LiveSessionStatus.paused.name
            : LiveSessionStatus.live.name,
        'updatedAt': DateTime.now().toUtc(),
      });
      return;
    }
    final sessionRef = _liveCollection.doc(sessionId);
    await _firestore.runTransaction((transaction) async {
      final sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists || sessionSnap.data() == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionSnap.id, sessionSnap.data()!);
      if (session.createdBy != user.uid) {
        throw Exception('Only the host can control this live.');
      }
      if (!session.isActive) {
        throw Exception('This live is already ended.');
      }
      transaction.update(sessionRef, {
        'status': pause
            ? LiveSessionStatus.paused.name
            : LiveSessionStatus.live.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> endLiveSession(String sessionId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (_useWindowsPollingWorkaround) {
      final sessionDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      if (sessionDoc == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionDoc.id, sessionDoc.data);
      if (session.createdBy != user.uid) {
        throw Exception('Only the host can end this live.');
      }
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('live_sessions/$sessionId', {
        ...sessionDoc.data,
        'status': LiveSessionStatus.ended.name,
        'endedAt': now,
        'updatedAt': now,
      });
      await _cleanupEphemeralCollections(sessionId);
      return;
    }
    final sessionRef = _liveCollection.doc(sessionId);
    await _firestore.runTransaction((transaction) async {
      final sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists || sessionSnap.data() == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionSnap.id, sessionSnap.data()!);
      if (session.createdBy != user.uid) {
        throw Exception('Only the host can end this live.');
      }
      transaction.update(sessionRef, {
        'status': LiveSessionStatus.ended.name,
        'endedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    await _cleanupEphemeralCollections(sessionId);
  }

  Future<void> requestMic(String sessionId) async {
    final (user, userData) = await _requireSessionContext();
    final participantDoc = _useWindowsPollingWorkaround
        ? await _windowsRest.getDocument(
            'live_sessions/$sessionId/participants/${user.uid}',
          )
        : null;
    final participantSnap = _useWindowsPollingWorkaround
        ? null
        : await _liveCollection
              .doc(sessionId)
              .collection('participants')
              .doc(user.uid)
              .get();
    if ((_useWindowsPollingWorkaround && participantDoc == null) ||
        (!_useWindowsPollingWorkaround &&
            (!participantSnap!.exists || participantSnap.data() == null))) {
      throw Exception('Join the live first.');
    }
    final participant = _useWindowsPollingWorkaround
        ? LiveParticipant.fromMap(participantDoc!.data)
        : LiveParticipant.fromMap(participantSnap!.data()!);
    if (participant.isHost || participant.isGuest) {
      return;
    }
    final userName =
        (userData['name'] as String?) ?? user.displayName ?? user.email;
    if (_useWindowsPollingWorkaround) {
      final existing = await _windowsRest.getDocument(
        'live_sessions/$sessionId/mic_requests/${user.uid}',
      );
      final now = DateTime.now().toUtc();
      await _windowsRest
          .setDocument('live_sessions/$sessionId/mic_requests/${user.uid}', {
            ...?existing?.data,
            'userId': user.uid,
            'displayName': userName,
            'status': MicRequestStatus.pending.name,
            'createdAt': existing?.data['createdAt'] ?? now,
            'updatedAt': now,
          });
      return;
    }
    await _liveCollection
        .doc(sessionId)
        .collection('mic_requests')
        .doc(user.uid)
        .set({
          'userId': user.uid,
          'displayName': userName,
          'status': MicRequestStatus.pending.name,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> approveMicRequest({
    required String sessionId,
    required String targetUserId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (_useWindowsPollingWorkaround) {
      final sessionDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      if (sessionDoc == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionDoc.id, sessionDoc.data);
      if (session.createdBy != user.uid) {
        throw Exception('Only the host can approve mic requests.');
      }

      final guestDocuments = await _windowsRest.queryCollection(
        parentPath: 'live_sessions/$sessionId',
        collectionId: 'participants',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal(
            'kind',
            LiveParticipantKind.guest.name,
          ),
        ],
      );
      if (guestDocuments.length >= session.maxGuests) {
        throw Exception('Podium is full (max ${session.maxGuests} guests).');
      }

      final participantDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId/participants/$targetUserId',
      );
      if (participantDoc == null) {
        throw Exception('User is no longer in this live session.');
      }
      final participant = LiveParticipant.fromMap(participantDoc.data);
      if (participant.removed) {
        throw Exception('User was removed from this live.');
      }
      final requestDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId/mic_requests/$targetUserId',
      );
      final now = DateTime.now().toUtc();
      await _windowsRest
          .setDocument('live_sessions/$sessionId/participants/$targetUserId', {
            ...participantDoc.data,
            'kind': LiveParticipantKind.guest.name,
            'canSpeak': true,
            'mutedByHost': false,
            'updatedAt': now,
          });
      await _windowsRest
          .setDocument('live_sessions/$sessionId/mic_requests/$targetUserId', {
            ...?requestDoc?.data,
            'status': MicRequestStatus.approved.name,
            'updatedAt': now,
          });
      return;
    }
    final sessionRef = _liveCollection.doc(sessionId);
    final targetParticipantRef = sessionRef
        .collection('participants')
        .doc(targetUserId);
    final requestRef = sessionRef.collection('mic_requests').doc(targetUserId);

    await _firestore.runTransaction((transaction) async {
      final sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists || sessionSnap.data() == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionSnap.id, sessionSnap.data()!);
      if (session.createdBy != user.uid) {
        throw Exception('Only the host can approve mic requests.');
      }

      final guestSnapshot = await sessionRef
          .collection('participants')
          .where('kind', isEqualTo: LiveParticipantKind.guest.name)
          .get();
      if (guestSnapshot.docs.length >= session.maxGuests) {
        throw Exception('Podium is full (max ${session.maxGuests} guests).');
      }

      final participantSnap = await transaction.get(targetParticipantRef);
      if (!participantSnap.exists || participantSnap.data() == null) {
        throw Exception('User is no longer in this live session.');
      }
      final participant = LiveParticipant.fromMap(participantSnap.data()!);
      if (participant.removed) {
        throw Exception('User was removed from this live.');
      }

      transaction.update(targetParticipantRef, {
        'kind': LiveParticipantKind.guest.name,
        'canSpeak': true,
        'mutedByHost': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(requestRef, {
        'status': MicRequestStatus.approved.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> denyMicRequest({
    required String sessionId,
    required String targetUserId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (_useWindowsPollingWorkaround) {
      final sessionDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      if (sessionDoc == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionDoc.id, sessionDoc.data);
      if (session.createdBy != user.uid) {
        throw Exception('Only the host can deny mic requests.');
      }
      final requestDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId/mic_requests/$targetUserId',
      );
      final now = DateTime.now().toUtc();
      await _windowsRest
          .setDocument('live_sessions/$sessionId/mic_requests/$targetUserId', {
            ...?requestDoc?.data,
            'status': MicRequestStatus.denied.name,
            'updatedAt': now,
          });
      return;
    }
    final sessionRef = _liveCollection.doc(sessionId);
    final sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists || sessionSnap.data() == null) {
      throw Exception('Live session not found.');
    }
    final session = LiveSession.fromMap(sessionSnap.id, sessionSnap.data()!);
    if (session.createdBy != user.uid) {
      throw Exception('Only the host can deny mic requests.');
    }

    await sessionRef.collection('mic_requests').doc(targetUserId).set({
      'status': MicRequestStatus.denied.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setMyMicEnabled({
    required String sessionId,
    required bool enabled,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (_useWindowsPollingWorkaround) {
      final existing = await _windowsRest.getDocument(
        'live_sessions/$sessionId/participants/${user.uid}',
      );
      if (existing == null) {
        throw Exception('Join the live first.');
      }
      await _windowsRest.setDocument(
        'live_sessions/$sessionId/participants/${user.uid}',
        {
          ...existing.data,
          'micEnabled': enabled,
          'updatedAt': DateTime.now().toUtc(),
        },
      );
      return;
    }
    await _liveCollection
        .doc(sessionId)
        .collection('participants')
        .doc(user.uid)
        .set({
          'micEnabled': enabled,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> muteParticipant({
    required String sessionId,
    required String targetUserId,
    required bool muted,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (_useWindowsPollingWorkaround) {
      final sessionDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      if (sessionDoc == null) {
        throw Exception('Live session not found.');
      }
      final live = LiveSession.fromMap(sessionDoc.id, sessionDoc.data);
      if (live.createdBy != user.uid) {
        throw Exception('Only the host can mute guests.');
      }
      final participantDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId/participants/$targetUserId',
      );
      if (participantDoc == null) {
        throw Exception('Participant not found.');
      }
      await _windowsRest
          .setDocument('live_sessions/$sessionId/participants/$targetUserId', {
            ...participantDoc.data,
            'mutedByHost': muted,
            if (muted) 'micEnabled': false,
            'updatedAt': DateTime.now().toUtc(),
          });
      return;
    }
    final sessionRef = _liveCollection.doc(sessionId);
    final session = await sessionRef.get();
    if (!session.exists || session.data() == null) {
      throw Exception('Live session not found.');
    }
    final live = LiveSession.fromMap(session.id, session.data()!);
    if (live.createdBy != user.uid) {
      throw Exception('Only the host can mute guests.');
    }
    await sessionRef.collection('participants').doc(targetUserId).set({
      'mutedByHost': muted,
      if (muted) 'micEnabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeParticipant({
    required String sessionId,
    required String targetUserId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (_useWindowsPollingWorkaround) {
      final sessionDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      if (sessionDoc == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionDoc.id, sessionDoc.data);
      if (session.createdBy != user.uid) {
        throw Exception('Only the host can remove users.');
      }
      final participantDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId/participants/$targetUserId',
      );
      if (participantDoc == null) {
        throw Exception('Participant not found.');
      }
      await _windowsRest
          .setDocument('live_sessions/$sessionId/participants/$targetUserId', {
            ...participantDoc.data,
            'removed': true,
            'canSpeak': false,
            'micEnabled': false,
            'updatedAt': DateTime.now().toUtc(),
          });
      await _windowsRest.deleteDocument(
        'live_sessions/$sessionId/mic_requests/$targetUserId',
      );
      return;
    }
    final sessionRef = _liveCollection.doc(sessionId);
    final sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists || sessionSnap.data() == null) {
      throw Exception('Live session not found.');
    }
    final session = LiveSession.fromMap(sessionSnap.id, sessionSnap.data()!);
    if (session.createdBy != user.uid) {
      throw Exception('Only the host can remove users.');
    }
    await sessionRef.collection('participants').doc(targetUserId).set({
      'removed': true,
      'canSpeak': false,
      'micEnabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await sessionRef.collection('mic_requests').doc(targetUserId).delete();
  }

  Future<void> sendComment({
    required String sessionId,
    required String text,
  }) async {
    final (user, userData) = await _requireSessionContext();
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return;
    }
    if (cleanText.length > 250) {
      throw Exception('Comment must be 250 characters or less.');
    }
    final participantDoc = _useWindowsPollingWorkaround
        ? await _windowsRest.getDocument(
            'live_sessions/$sessionId/participants/${user.uid}',
          )
        : null;
    final participantSnap = _useWindowsPollingWorkaround
        ? null
        : await _liveCollection
              .doc(sessionId)
              .collection('participants')
              .doc(user.uid)
              .get();
    if ((_useWindowsPollingWorkaround && participantDoc == null) ||
        (!_useWindowsPollingWorkaround &&
            (!participantSnap!.exists || participantSnap.data() == null))) {
      throw Exception('Join the live before commenting.');
    }
    final participant = _useWindowsPollingWorkaround
        ? LiveParticipant.fromMap(participantDoc!.data)
        : LiveParticipant.fromMap(participantSnap!.data()!);
    if (participant.removed) {
      throw Exception('You were removed from this live.');
    }

    if (_useWindowsPollingWorkaround) {
      await _windowsRest.setDocument(
        'live_sessions/$sessionId/comments/${_windowsDocId('comment')}',
        {
          'userId': user.uid,
          'displayName':
              (userData['name'] as String?) ?? user.displayName ?? user.email,
          'text': cleanText,
          'createdAt': DateTime.now().toUtc(),
        },
      );
      return;
    }
    await _liveCollection.doc(sessionId).collection('comments').add({
      'userId': user.uid,
      'displayName':
          (userData['name'] as String?) ?? user.displayName ?? user.email,
      'text': cleanText,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendReaction({
    required String sessionId,
    required String emoji,
  }) async {
    final (user, userData) = await _requireSessionContext();
    if (_useWindowsPollingWorkaround) {
      final sessionDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId',
      );
      if (sessionDoc == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionDoc.id, sessionDoc.data);
      if (!session.isActive) {
        throw Exception('Live session is not active.');
      }
      final participantDoc = await _windowsRest.getDocument(
        'live_sessions/$sessionId/participants/${user.uid}',
      );
      if (participantDoc == null) {
        throw Exception('Join the live before reacting.');
      }
      final participant = LiveParticipant.fromMap(participantDoc.data);
      if (participant.removed) {
        throw Exception('You were removed from this live.');
      }
      final rawLastReaction = participantDoc.data['lastReactionAt'];
      DateTime? lastReactionAt;
      if (rawLastReaction is DateTime) {
        lastReactionAt = rawLastReaction;
      }
      final now = DateTime.now().toUtc();
      if (lastReactionAt != null &&
          now.difference(lastReactionAt).inSeconds < 3) {
        throw Exception('Please wait before sending another reaction.');
      }
      await _windowsRest.setDocument(
        'live_sessions/$sessionId/reactions/${_windowsDocId('reaction')}',
        {
          'userId': user.uid,
          'displayName':
              (userData['name'] as String?) ?? user.displayName ?? user.email,
          'emoji': emoji,
          'createdAt': now,
        },
      );
      await _windowsRest.setDocument('live_sessions/$sessionId', {
        ...sessionDoc.data,
        'likeCount': session.likeCount + 1,
        'updatedAt': now,
      });
      await _windowsRest.setDocument(
        'live_sessions/$sessionId/participants/${user.uid}',
        {...participantDoc.data, 'lastReactionAt': now, 'updatedAt': now},
      );
      return;
    }
    final sessionRef = _liveCollection.doc(sessionId);
    final participantRef = sessionRef.collection('participants').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists || sessionSnap.data() == null) {
        throw Exception('Live session not found.');
      }
      final session = LiveSession.fromMap(sessionSnap.id, sessionSnap.data()!);
      if (!session.isActive) {
        throw Exception('Live session is not active.');
      }

      final participantSnap = await transaction.get(participantRef);
      if (!participantSnap.exists || participantSnap.data() == null) {
        throw Exception('Join the live before reacting.');
      }
      final participantData = participantSnap.data()!;
      final participant = LiveParticipant.fromMap(participantData);
      if (participant.removed) {
        throw Exception('You were removed from this live.');
      }

      final rawLastReaction = participantData['lastReactionAt'];
      DateTime? lastReactionAt;
      if (rawLastReaction is Timestamp) {
        lastReactionAt = rawLastReaction.toDate();
      }
      final now = DateTime.now();
      if (lastReactionAt != null &&
          now.difference(lastReactionAt).inSeconds < 3) {
        throw Exception('Please wait before sending another reaction.');
      }

      final reactionRef = sessionRef.collection('reactions').doc();
      transaction.set(reactionRef, {
        'userId': user.uid,
        'displayName':
            (userData['name'] as String?) ?? user.displayName ?? user.email,
        'emoji': emoji,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(sessionRef, {
        'likeCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(participantRef, {
        'lastReactionAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> reportComment({
    required String sessionId,
    required LiveComment comment,
    required String reason,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw Exception('Reason is required.');
    }
    if (_useWindowsPollingWorkaround) {
      await _windowsRest.setDocument(
        'live_sessions/$sessionId/comment_reports/${_windowsDocId('report')}',
        {
          'reportedBy': user.uid,
          'commentId': comment.id,
          'commentUserId': comment.userId,
          'commentText': comment.text,
          'reason': trimmedReason,
          'createdAt': DateTime.now().toUtc(),
        },
      );
      return;
    }
    await _liveCollection.doc(sessionId).collection('comment_reports').add({
      'reportedBy': user.uid,
      'commentId': comment.id,
      'commentUserId': comment.userId,
      'commentText': comment.text,
      'reason': trimmedReason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<MemberPublicProfile?> fetchMemberPublicProfile({
    required String sessionId,
    required String userId,
  }) async {
    final sessionData = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('live_sessions/$sessionId'))?.data
        : (await _liveCollection.doc(sessionId).get()).data();
    if (sessionData == null) {
      return null;
    }
    final session = LiveSession.fromMap(sessionId, sessionData);
    final memberData = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument(
            'institution_members/${session.institutionId}_$userId',
          ))?.data
        : (await _firestore
                  .collection('institution_members')
                  .doc('${session.institutionId}_$userId')
                  .get())
              .data();
    if (memberData == null) {
      return null;
    }
    return MemberPublicProfile(
      userId: userId,
      displayName: (memberData['userName'] as String?) ?? 'Member',
      role: (memberData['role'] as String?) ?? UserRole.other.name,
      email: (memberData['email'] as String?) ?? '',
      subtitle: (memberData['status'] as String?) ?? 'active',
    );
  }

  Future<LiveKitJoinCredentials> createLiveKitJoinCredentials({
    required String sessionId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    final tokenEndpoint = _liveKitTokenEndpoint;
    if (tokenEndpoint.isNotEmpty) {
      return _createLiveKitJoinCredentialsFromBackend(
        sessionId: sessionId,
        tokenEndpoint: tokenEndpoint,
      );
    }
    if (kIsWeb) {
      throw Exception(
        'Audio backend is not configured. Missing LIVEKIT_TOKEN_ENDPOINT.',
      );
    }
    if (_liveKitUrl.isEmpty ||
        _liveKitApiKey.isEmpty ||
        _liveKitApiSecret.isEmpty) {
      throw Exception(
        'Audio backend is not configured. Missing LIVEKIT_URL, LIVEKIT_API_KEY, or LIVEKIT_API_SECRET.',
      );
    }

    final sessionData = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('live_sessions/$sessionId'))?.data
        : (await _liveCollection.doc(sessionId).get()).data();
    if (sessionData == null) {
      throw Exception('Live session not found.');
    }
    final session = LiveSession.fromMap(sessionId, sessionData);

    final participantData = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument(
            'live_sessions/$sessionId/participants/${user.uid}',
          ))?.data
        : (await _liveCollection
                  .doc(sessionId)
                  .collection('participants')
                  .doc(user.uid)
                  .get())
              .data();

    var canPublishAudio = false;
    if (session.createdBy == user.uid) {
      canPublishAudio = session.status == LiveSessionStatus.live;
    } else if (participantData != null) {
      final canSpeak = (participantData['canSpeak'] as bool?) ?? false;
      final mutedByHost = (participantData['mutedByHost'] as bool?) ?? false;
      canPublishAudio =
          session.status == LiveSessionStatus.live && canSpeak && !mutedByHost;
    }

    final roomName = (sessionData['roomName'] as String?)?.trim();
    final resolvedRoomName = (roomName != null && roomName.isNotEmpty)
        ? roomName
        : 'mindnest_live_$sessionId';

    final userData = await _currentUserDoc();
    final displayName =
        (userData['name'] as String?) ?? user.displayName ?? user.email;

    final now = DateTime.now().toUtc();
    final nowEpochSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final token = JWT(
      <String, dynamic>{
        'name': displayName,
        'nbf': nowEpochSeconds,
        'video': <String, dynamic>{
          'roomJoin': true,
          'room': resolvedRoomName,
          'canPublish': canPublishAudio,
          'canSubscribe': true,
          'canPublishData': true,
        },
      },
      issuer: _liveKitApiKey,
      subject: user.uid,
      jwtId: '${user.uid}_${now.millisecondsSinceEpoch}',
    ).sign(SecretKey(_liveKitApiSecret), expiresIn: const Duration(hours: 2));

    return LiveKitJoinCredentials(
      serverUrl: _liveKitUrl,
      token: token,
      roomName: resolvedRoomName,
      canPublishAudio: canPublishAudio,
    );
  }

  Future<LiveKitJoinCredentials> _createLiveKitJoinCredentialsFromBackend({
    required String sessionId,
    required String tokenEndpoint,
  }) async {
    var idToken = await _auth.getIdToken();
    if ((idToken ?? '').trim().isEmpty) {
      idToken = await _auth.getIdToken(forceRefresh: true);
    }
    if ((idToken ?? '').trim().isEmpty) {
      throw Exception('You must be logged in.');
    }

    late final Uri endpoint;
    try {
      endpoint = Uri.parse(tokenEndpoint);
    } catch (_) {
      throw Exception('Audio backend endpoint is invalid.');
    }
    if (!endpoint.hasScheme || endpoint.host.isEmpty) {
      throw Exception('Audio backend endpoint is invalid.');
    }

    final response = await _httpClient
        .post(
          endpoint,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${idToken!.trim()}',
          },
          body: jsonEncode(<String, String>{'sessionId': sessionId}),
        )
        .timeout(const Duration(seconds: 18));

    final payload = _decodeJsonMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (payload['error'] as String?)?.trim();
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Audio backend rejected the join request.',
      );
    }

    final serverUrl = (payload['serverUrl'] as String?)?.trim() ?? '';
    final token = (payload['token'] as String?)?.trim() ?? '';
    final roomName = (payload['roomName'] as String?)?.trim() ?? '';
    final canPublishAudio = (payload['canPublishAudio'] as bool?) ?? false;
    if (serverUrl.isEmpty || token.isEmpty || roomName.isEmpty) {
      throw Exception('Audio backend returned incomplete credentials.');
    }

    return LiveKitJoinCredentials(
      serverUrl: serverUrl,
      token: token,
      roomName: roomName,
      canPublishAudio: canPublishAudio,
    );
  }

  Future<void> _cleanupEphemeralCollections(String sessionId) async {
    if (_useWindowsPollingWorkaround) {
      await _deleteWindowsSubcollection(
        parentPath: 'live_sessions/$sessionId',
        collectionId: 'comments',
      );
      await _deleteWindowsSubcollection(
        parentPath: 'live_sessions/$sessionId',
        collectionId: 'reactions',
      );
      await _deleteWindowsSubcollection(
        parentPath: 'live_sessions/$sessionId',
        collectionId: 'mic_requests',
      );
      return;
    }
    final sessionRef = _liveCollection.doc(sessionId);
    await _deleteSubcollection(sessionRef.collection('comments'));
    await _deleteSubcollection(sessionRef.collection('reactions'));
    await _deleteSubcollection(sessionRef.collection('mic_requests'));
  }

  Future<void> _deleteWindowsSubcollection({
    required String parentPath,
    required String collectionId,
  }) async {
    while (true) {
      final documents = await _windowsRest.queryCollection(
        parentPath: parentPath,
        collectionId: collectionId,
        limit: 250,
      );
      if (documents.isEmpty) {
        return;
      }
      for (final document in documents) {
        await _windowsRest.deleteDocument(document.path);
      }
    }
  }

  Future<void> _deleteSubcollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snapshot = await collection.limit(250).get();
      if (snapshot.docs.isEmpty) {
        return;
      }
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }
}
