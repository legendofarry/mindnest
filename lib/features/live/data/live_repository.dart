import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const Set<String> _allowedCreatorRoles = <String>{
    'student',
    'staff',
    'counselor',
  };
  static const String _liveKitUrl = String.fromEnvironment(
    'LIVEKIT_URL',
    defaultValue: '',
  );
  static const String _liveKitApiKey = String.fromEnvironment(
    'LIVEKIT_API_KEY',
    defaultValue: '',
  );
  static const String _liveKitApiSecret = String.fromEnvironment(
    'LIVEKIT_API_SECRET',
    defaultValue: '',
  );

  CollectionReference<Map<String, dynamic>> get _liveCollection =>
      _firestore.collection('live_sessions');

  Future<Map<String, dynamic>> _currentUserDoc() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!userDoc.exists || userDoc.data() == null) {
      throw Exception('User profile not found.');
    }
    return userDoc.data()!;
  }

  Future<(User, Map<String, dynamic>)> _requireSessionContext() async {
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
    return _liveCollection
        .where('institutionId', isEqualTo: institutionId)
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
    return _liveCollection.doc(sessionId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return LiveSession.fromMap(doc.id, doc.data()!);
    });
  }

  Stream<List<LiveParticipant>> watchParticipants(String sessionId) {
    return _liveCollection
        .doc(sessionId)
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
    return _liveCollection
        .doc(sessionId)
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
    return _liveCollection
        .doc(sessionId)
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
    return _liveCollection
        .doc(sessionId)
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
    return _liveCollection
        .doc(sessionId)
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

    final liveRef = _liveCollection.doc();
    final hostName =
        (userData['name'] as String?) ??
        user.displayName ??
        user.email ??
        'Host';

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
        (userData['name'] as String?) ??
        user.displayName ??
        user.email ??
        'Member';

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
    final participantRef = _liveCollection
        .doc(sessionId)
        .collection('participants')
        .doc(user.uid);
    final participantSnap = await participantRef.get();
    if (!participantSnap.exists || participantSnap.data() == null) {
      throw Exception('Join the live first.');
    }
    final participant = LiveParticipant.fromMap(participantSnap.data()!);
    if (participant.isHost || participant.isGuest) {
      return;
    }
    final userName =
        (userData['name'] as String?) ??
        user.displayName ??
        user.email ??
        'Member';
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
    final participantRef = _liveCollection
        .doc(sessionId)
        .collection('participants')
        .doc(user.uid);
    final participantSnap = await participantRef.get();
    if (!participantSnap.exists || participantSnap.data() == null) {
      throw Exception('Join the live before commenting.');
    }
    final participant = LiveParticipant.fromMap(participantSnap.data()!);
    if (participant.removed) {
      throw Exception('You were removed from this live.');
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
    final sessionSnap = await _liveCollection.doc(sessionId).get();
    if (!sessionSnap.exists || sessionSnap.data() == null) {
      return null;
    }
    final session = LiveSession.fromMap(sessionSnap.id, sessionSnap.data()!);
    final memberDoc = await _firestore
        .collection('institution_members')
        .doc('${session.institutionId}_$userId')
        .get();
    if (!memberDoc.exists || memberDoc.data() == null) {
      return null;
    }
    final data = memberDoc.data()!;
    return MemberPublicProfile(
      userId: userId,
      displayName: (data['userName'] as String?) ?? 'Member',
      role: (data['role'] as String?) ?? UserRole.other.name,
      email: (data['email'] as String?) ?? '',
      subtitle: (data['status'] as String?) ?? 'active',
    );
  }

  Future<LiveKitJoinCredentials> createLiveKitJoinCredentials({
    required String sessionId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }
    if (_liveKitUrl.isEmpty ||
        _liveKitApiKey.isEmpty ||
        _liveKitApiSecret.isEmpty) {
      throw Exception(
        'Audio backend is not configured. Missing LIVEKIT_URL, LIVEKIT_API_KEY, or LIVEKIT_API_SECRET.',
      );
    }

    final sessionSnap = await _liveCollection.doc(sessionId).get();
    if (!sessionSnap.exists || sessionSnap.data() == null) {
      throw Exception('Live session not found.');
    }
    final sessionData = sessionSnap.data()!;
    final session = LiveSession.fromMap(sessionSnap.id, sessionData);

    final participantSnap = await _liveCollection
        .doc(sessionId)
        .collection('participants')
        .doc(user.uid)
        .get();

    var canPublishAudio = false;
    if (session.createdBy == user.uid) {
      canPublishAudio = session.status == LiveSessionStatus.live;
    } else if (participantSnap.exists && participantSnap.data() != null) {
      final participantData = participantSnap.data()!;
      final canSpeak = (participantData['canSpeak'] as bool?) ?? false;
      final mutedByHost = (participantData['mutedByHost'] as bool?) ?? false;
      canPublishAudio =
          session.status == LiveSessionStatus.live && canSpeak && !mutedByHost;
    }

    final roomName = (sessionData['roomName'] as String?)?.trim();
    final resolvedRoomName =
        (roomName != null && roomName.isNotEmpty)
        ? roomName
        : 'mindnest_live_$sessionId';

    final userData = await _currentUserDoc();
    final displayName =
        (userData['name'] as String?) ??
        user.displayName ??
        user.email ??
        'MindNest Member';

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

  Future<void> _cleanupEphemeralCollections(String sessionId) async {
    final sessionRef = _liveCollection.doc(sessionId);
    await _deleteSubcollection(sessionRef.collection('comments'));
    await _deleteSubcollection(sessionRef.collection('reactions'));
    await _deleteSubcollection(sessionRef.collection('mic_requests'));
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
}
