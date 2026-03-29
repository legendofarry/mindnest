import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/core/data/windows_firestore_rest_client.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/models/app_notification.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/care_goal.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';
import 'package:mindnest/features/care/models/counselor_public_rating.dart';
import 'package:mindnest/features/care/models/session_reassignment_request.dart';
import 'package:mindnest/features/institutions/models/counselor_workflow_settings.dart';

class CareRepository {
  CareRepository({
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

  static const String _pushDispatchEndpointFromDefine = String.fromEnvironment(
    'PUSH_DISPATCH_ENDPOINT',
    defaultValue: '',
  );
  // Source fallback for local/native runs when --dart-define is omitted.
  static const String _pushDispatchEndpointFromSource =
      'https://mindnest-0o6x.onrender.com/push/dispatch';
  static String get _pushDispatchEndpoint =>
      _pushDispatchEndpointFromDefine.isNotEmpty
      ? _pushDispatchEndpointFromDefine
      : _pushDispatchEndpointFromSource;

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

  dynamic _normalizeWindowsWriteValue(dynamic value, DateTime nowUtc) {
    if (value is FieldValue) {
      return nowUtc;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is List) {
      return value
          .map((item) => _normalizeWindowsWriteValue(item, nowUtc))
          .toList(growable: false);
    }
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(
          key.toString(),
          _normalizeWindowsWriteValue(nested, nowUtc),
        ),
      );
    }
    return value;
  }

  Map<String, dynamic> _normalizeWindowsWriteData(
    Map<String, dynamic> data,
    DateTime nowUtc,
  ) {
    return data.map(
      (key, value) => MapEntry(key, _normalizeWindowsWriteValue(value, nowUtc)),
    );
  }

  Map<String, dynamic> _windowsInterestedCounselorPayload(
    ReassignmentInterestedCounselor counselor,
  ) {
    return <String, dynamic>{
      'counselorId': counselor.counselorId,
      'displayName': counselor.displayName,
      'specialization': counselor.specialization,
      'languages': counselor.languages,
      'sessionMode': counselor.sessionMode,
      'respondedAt': counselor.respondedAt.toUtc(),
      'isActive': counselor.isActive,
    };
  }

  Stream<List<CounselorProfile>> watchCounselors({
    required String institutionId,
  }) {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const <CounselorProfile>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<CounselorProfile>>(
        load: () => getCounselors(institutionId: normalized),
        signature: _counselorProfilesSignature,
      );
    }
    return _firestore
        .collection('counselor_profiles')
        .where('institutionId', isEqualTo: normalized)
        .snapshots()
        .map((snapshot) {
          final profiles = snapshot.docs
              .map((doc) => CounselorProfile.fromMap(doc.id, doc.data()))
              .where((profile) => profile.isActive)
              .toList(growable: false);
          profiles.sort((a, b) => a.displayName.compareTo(b.displayName));
          return profiles;
        });
  }

  Stream<CounselorProfile?> watchCounselorProfile(String counselorId) {
    final normalized = counselorId.trim();
    if (normalized.isEmpty) {
      return Stream.value(null);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<CounselorProfile?>(
        load: () => getCounselorProfile(normalized),
        signature: _counselorProfileSignature,
      );
    }
    return _firestore
        .collection('counselor_profiles')
        .doc(normalized)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) {
            return null;
          }
          return CounselorProfile.fromMap(doc.id, doc.data()!);
        });
  }

  Future<CounselorWorkflowSettings> getCounselorWorkflowSettings(
    String institutionId,
  ) async {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return const CounselorWorkflowSettings.disabled();
    }
    if (kUseWindowsRestAuth) {
      final document = await _windowsRest.getDocument(
        'institutions/$normalized',
      );
      return CounselorWorkflowSettings.fromInstitutionData(document?.data);
    }
    final snapshot = await _firestore
        .collection('institutions')
        .doc(normalized)
        .get();
    return CounselorWorkflowSettings.fromInstitutionData(snapshot.data());
  }

  Stream<SessionReassignmentRequest?> watchAppointmentReassignmentRequest(
    String appointmentId,
  ) {
    final normalized = appointmentId.trim();
    if (normalized.isEmpty) {
      return Stream<SessionReassignmentRequest?>.value(null);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<SessionReassignmentRequest?>(
        load: () => getAppointmentReassignmentRequest(normalized),
        signature: (request) => request == null
            ? 'null'
            : '${request.id}|${request.status.name}|${request.updatedAt.toIso8601String()}',
      );
    }
    return _firestore
        .collection('session_reassignment_requests')
        .doc(normalized)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) {
            return null;
          }
          return SessionReassignmentRequest.fromMap(doc.id, doc.data()!);
        });
  }

  Stream<List<SessionReassignmentRequest>> watchInstitutionReassignmentBoard({
    required String institutionId,
  }) {
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<SessionReassignmentRequest>>(
        load: () =>
            getInstitutionReassignmentBoard(institutionId: institutionId),
        signature: (requests) => requests
            .map(
              (request) =>
                  '${request.id}|${request.status.name}|${request.updatedAt.toIso8601String()}',
            )
            .join(';'),
      );
    }
    return _firestore
        .collection('session_reassignment_requests')
        .where('institutionId', isEqualTo: institutionId)
        .where(
          'status',
          whereIn: const <String>[
            'open_for_responses',
            'awaiting_patient_choice',
            'patient_selected',
          ],
        )
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map(
                (doc) => SessionReassignmentRequest.fromMap(doc.id, doc.data()),
              )
              .toList(growable: false);
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  Future<void> createReassignmentRequest({
    required AppointmentRecord appointment,
    Duration responseWindow = const Duration(hours: 12),
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (appointment.counselorId != currentUser.uid) {
      throw Exception('Only the assigned counselor can request reassignment.');
    }
    if (appointment.status != AppointmentStatus.pending &&
        appointment.status != AppointmentStatus.confirmed) {
      throw Exception('Only pending or confirmed sessions can be reassigned.');
    }

    final settings = await getCounselorWorkflowSettings(
      appointment.institutionId,
    );
    if (!settings.reassignmentEnabled) {
      throw Exception(
        'Counselor-to-counselor reassignment is disabled for this institution.',
      );
    }

    if (kUseWindowsRestAuth) {
      final existing = await getAppointmentReassignmentRequest(appointment.id);
      if (existing != null) {
        final current = existing;
        if (current.status != SessionReassignmentStatus.transferred &&
            current.status != SessionReassignmentStatus.declined &&
            current.status != SessionReassignmentStatus.expired &&
            current.status != SessionReassignmentStatus.cancelled) {
          throw Exception('A reassignment request is already active.');
        }
      }

      final counselorProfile = await getCounselorProfile(currentUser.uid);
      final nowUtc = DateTime.now().toUtc();
      final responseDeadlineAt = nowUtc.add(responseWindow);

      await _windowsRest
          .setDocument('session_reassignment_requests/${appointment.id}', {
            'appointmentId': appointment.id,
            'institutionId': appointment.institutionId,
            'originalCounselorId': appointment.counselorId,
            'studentId': appointment.studentId,
            'studentName': appointment.studentName ?? 'Student',
            'requiredSpecialization': counselorProfile?.specialization ?? '',
            'sessionMode': counselorProfile?.sessionMode ?? '--',
            'sessionStartAt': appointment.startAt.toUtc(),
            'sessionEndAt': appointment.endAt.toUtc(),
            'status': SessionReassignmentStatus.openForResponses.wireName,
            'maxInterestedCounselors': 5,
            'responseDeadlineAt': responseDeadlineAt,
            'interestedCounselors': const <Map<String, dynamic>>[],
            'createdAt': nowUtc,
            'updatedAt': nowUtc,
          });

      final counselorProfiles = await getCounselors(
        institutionId: appointment.institutionId,
      );
      final payloads = <Map<String, dynamic>>[
        _notificationPayload(
          userId: appointment.studentId,
          institutionId: appointment.institutionId,
          type: 'reassignment_request_created',
          title: 'Counselor transfer options are opening',
          body:
              '${appointment.counselorName ?? 'Your counselor'} is collecting alternate counselors for this session. You will be able to review them before any transfer is finalized.',
          relatedAppointmentId: appointment.id,
          relatedId: appointment.id,
          actionRequired: true,
          priority: 'high',
          route: Uri(
            path: AppRoute.sessionDetails,
            queryParameters: <String, String>{'appointmentId': appointment.id},
          ).toString(),
        ),
      ];

      for (final profile in counselorProfiles) {
        if (!profile.isActive || profile.id == currentUser.uid) {
          continue;
        }
        payloads.add(
          _notificationPayload(
            userId: profile.id,
            institutionId: appointment.institutionId,
            type: 'reassignment_request_available',
            title: 'Counselor coverage requested',
            body:
                'A counselor in your institution needs a replacement for ${_formatDateTime(appointment.startAt)}.',
            relatedAppointmentId: appointment.id,
            relatedId: appointment.id,
            actionRequired: true,
            route: AppRoute.counselorAppointments,
          ),
        );
      }

      await _createNotifications(payloads);
      return;
    }

    final requestRef = _firestore
        .collection('session_reassignment_requests')
        .doc(appointment.id);
    final existing = await requestRef.get();
    if (existing.exists && existing.data() != null) {
      final current = SessionReassignmentRequest.fromMap(
        existing.id,
        existing.data()!,
      );
      if (current.status != SessionReassignmentStatus.transferred &&
          current.status != SessionReassignmentStatus.declined &&
          current.status != SessionReassignmentStatus.expired &&
          current.status != SessionReassignmentStatus.cancelled) {
        throw Exception('A reassignment request is already active.');
      }
    }

    final counselorProfileSnapshot = await _firestore
        .collection('counselor_profiles')
        .doc(currentUser.uid)
        .get();
    final counselorProfile = counselorProfileSnapshot.data() == null
        ? null
        : CounselorProfile.fromMap(
            counselorProfileSnapshot.id,
            counselorProfileSnapshot.data()!,
          );
    final nowUtc = DateTime.now().toUtc();
    final responseDeadlineAt = nowUtc.add(responseWindow);

    await requestRef.set({
      'appointmentId': appointment.id,
      'institutionId': appointment.institutionId,
      'originalCounselorId': appointment.counselorId,
      'studentId': appointment.studentId,
      'studentName': appointment.studentName ?? 'Student',
      'requiredSpecialization': counselorProfile?.specialization ?? '',
      'sessionMode': counselorProfile?.sessionMode ?? '--',
      'sessionStartAt': Timestamp.fromDate(appointment.startAt.toUtc()),
      'sessionEndAt': Timestamp.fromDate(appointment.endAt.toUtc()),
      'status': SessionReassignmentStatus.openForResponses.wireName,
      'maxInterestedCounselors': 5,
      'responseDeadlineAt': Timestamp.fromDate(responseDeadlineAt),
      'interestedCounselors': const <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final counselorSnapshots = await _firestore
        .collection('counselor_profiles')
        .where('institutionId', isEqualTo: appointment.institutionId)
        .get();
    final payloads = <Map<String, dynamic>>[
      _notificationPayload(
        userId: appointment.studentId,
        institutionId: appointment.institutionId,
        type: 'reassignment_request_created',
        title: 'Counselor transfer options are opening',
        body:
            '${appointment.counselorName ?? 'Your counselor'} is collecting alternate counselors for this session. You will be able to review them before any transfer is finalized.',
        relatedAppointmentId: appointment.id,
        relatedId: appointment.id,
        actionRequired: true,
        priority: 'high',
        route: Uri(
          path: AppRoute.sessionDetails,
          queryParameters: <String, String>{'appointmentId': appointment.id},
        ).toString(),
      ),
    ];

    for (final doc in counselorSnapshots.docs) {
      final data = doc.data();
      final active = (data['isActive'] as bool?) ?? true;
      if (!active || doc.id == currentUser.uid) {
        continue;
      }
      payloads.add(
        _notificationPayload(
          userId: doc.id,
          institutionId: appointment.institutionId,
          type: 'reassignment_request_available',
          title: 'Counselor coverage requested',
          body:
              'A counselor in your institution needs a replacement for ${_formatDateTime(appointment.startAt)}.',
          relatedAppointmentId: appointment.id,
          relatedId: appointment.id,
          actionRequired: true,
          route: AppRoute.counselorAppointments,
        ),
      );
    }

    await _createNotifications(payloads);
  }

  Future<void> syncReassignmentLifecycle(String requestId) async {
    final normalized = requestId.trim();
    if (normalized.isEmpty) {
      return;
    }
    if (kUseWindowsRestAuth) {
      final request = await getAppointmentReassignmentRequest(normalized);
      if (request == null) {
        return;
      }
      final nowUtc = DateTime.now().toUtc();
      if (request.status == SessionReassignmentStatus.openForResponses &&
          nowUtc.isAfter(request.responseDeadlineAt)) {
        if (request.interestedCounselors.isEmpty) {
          await _windowsRest
              .updateDocument('session_reassignment_requests/$normalized', {
                'status': SessionReassignmentStatus.expired.wireName,
                'expiredAt': nowUtc,
                'updatedAt': nowUtc,
              });
          await _createNotifications([
            _notificationPayload(
              userId: request.originalCounselorId,
              institutionId: request.institutionId,
              type: 'reassignment_request_expired',
              title: 'No counselors responded in time',
              body:
                  'The reassignment request for ${_formatDateTime(request.sessionStartAt)} expired without any interested counselors.',
              relatedAppointmentId: request.appointmentId,
              relatedId: request.id,
            ),
            _notificationPayload(
              userId: request.studentId,
              institutionId: request.institutionId,
              type: 'reassignment_request_expired',
              title: 'Transfer options expired',
              body:
                  'No replacement counselor responded before the request expired. Your current counselor will handle the next step.',
              relatedAppointmentId: request.appointmentId,
              relatedId: request.id,
            ),
          ]);
        } else {
          await _windowsRest
              .updateDocument('session_reassignment_requests/$normalized', {
                'status':
                    SessionReassignmentStatus.awaitingPatientChoice.wireName,
                'choiceDeadlineAt': nowUtc.add(const Duration(hours: 12)),
                'updatedAt': nowUtc,
              });
          await _createNotifications([
            _notificationPayload(
              userId: request.studentId,
              institutionId: request.institutionId,
              type: 'reassignment_choice_ready',
              title: 'Replacement counselors are ready',
              body:
                  'You can now review the interested counselors and choose who should take this session.',
              relatedAppointmentId: request.appointmentId,
              relatedId: request.id,
              actionRequired: true,
              priority: 'high',
              route: Uri(
                path: AppRoute.sessionDetails,
                queryParameters: <String, String>{
                  'appointmentId': request.appointmentId,
                },
              ).toString(),
            ),
          ]);
        }
        return;
      }

      if (request.status == SessionReassignmentStatus.awaitingPatientChoice &&
          request.choiceDeadlineAt != null &&
          nowUtc.isAfter(request.choiceDeadlineAt!)) {
        await _windowsRest
            .updateDocument('session_reassignment_requests/$normalized', {
              'status': SessionReassignmentStatus.expired.wireName,
              'expiredAt': nowUtc,
              'updatedAt': nowUtc,
            });
        await _createNotifications([
          _notificationPayload(
            userId: request.originalCounselorId,
            institutionId: request.institutionId,
            type: 'reassignment_request_expired',
            title: 'Patient decision window expired',
            body:
                'The patient did not choose a replacement counselor before the transfer window closed.',
            relatedAppointmentId: request.appointmentId,
            relatedId: request.id,
          ),
          _notificationPayload(
            userId: request.studentId,
            institutionId: request.institutionId,
            type: 'reassignment_request_expired',
            title: 'Transfer options expired',
            body:
                'The replacement counselor options expired before a final choice was made.',
            relatedAppointmentId: request.appointmentId,
            relatedId: request.id,
          ),
        ]);
      }
      return;
    }

    final ref = _firestore
        .collection('session_reassignment_requests')
        .doc(normalized);
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.data() == null) {
      return;
    }
    final request = SessionReassignmentRequest.fromMap(
      snapshot.id,
      snapshot.data()!,
    );
    final nowUtc = DateTime.now().toUtc();
    if (request.status == SessionReassignmentStatus.openForResponses &&
        nowUtc.isAfter(request.responseDeadlineAt)) {
      if (request.interestedCounselors.isEmpty) {
        await ref.update({
          'status': SessionReassignmentStatus.expired.wireName,
          'expiredAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await _createNotifications([
          _notificationPayload(
            userId: request.originalCounselorId,
            institutionId: request.institutionId,
            type: 'reassignment_request_expired',
            title: 'No counselors responded in time',
            body:
                'The reassignment request for ${_formatDateTime(request.sessionStartAt)} expired without any interested counselors.',
            relatedAppointmentId: request.appointmentId,
            relatedId: request.id,
          ),
          _notificationPayload(
            userId: request.studentId,
            institutionId: request.institutionId,
            type: 'reassignment_request_expired',
            title: 'Transfer options expired',
            body:
                'No replacement counselor responded before the request expired. Your current counselor will handle the next step.',
            relatedAppointmentId: request.appointmentId,
            relatedId: request.id,
          ),
        ]);
      } else {
        await ref.update({
          'status': SessionReassignmentStatus.awaitingPatientChoice.wireName,
          'choiceDeadlineAt': Timestamp.fromDate(
            nowUtc.add(const Duration(hours: 12)),
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await _createNotifications([
          _notificationPayload(
            userId: request.studentId,
            institutionId: request.institutionId,
            type: 'reassignment_choice_ready',
            title: 'Replacement counselors are ready',
            body:
                'You can now review the interested counselors and choose who should take this session.',
            relatedAppointmentId: request.appointmentId,
            relatedId: request.id,
            actionRequired: true,
            priority: 'high',
            route: Uri(
              path: AppRoute.sessionDetails,
              queryParameters: <String, String>{
                'appointmentId': request.appointmentId,
              },
            ).toString(),
          ),
        ]);
      }
      return;
    }

    if (request.status == SessionReassignmentStatus.awaitingPatientChoice &&
        request.choiceDeadlineAt != null &&
        nowUtc.isAfter(request.choiceDeadlineAt!)) {
      await ref.update({
        'status': SessionReassignmentStatus.expired.wireName,
        'expiredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _createNotifications([
        _notificationPayload(
          userId: request.originalCounselorId,
          institutionId: request.institutionId,
          type: 'reassignment_request_expired',
          title: 'Patient decision window expired',
          body:
              'The patient did not choose a replacement counselor before the transfer window closed.',
          relatedAppointmentId: request.appointmentId,
          relatedId: request.id,
        ),
        _notificationPayload(
          userId: request.studentId,
          institutionId: request.institutionId,
          type: 'reassignment_request_expired',
          title: 'Transfer options expired',
          body:
              'The replacement counselor options expired before a final choice was made.',
          relatedAppointmentId: request.appointmentId,
          relatedId: request.id,
        ),
      ]);
    }
  }

  Future<void> expressInterestInReassignment(String requestId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    if (kUseWindowsRestAuth) {
      final profile = await getCounselorProfile(currentUser.uid);
      if (profile == null) {
        throw Exception('Counselor profile not found.');
      }
      final settings = await getCounselorWorkflowSettings(
        profile.institutionId,
      );
      if (!settings.reassignmentEnabled) {
        throw Exception(
          'Counselor-to-counselor reassignment is disabled for this institution.',
        );
      }

      final request = await getAppointmentReassignmentRequest(requestId.trim());
      if (request == null) {
        throw Exception('Reassignment request not found.');
      }
      final nowUtc = DateTime.now().toUtc();
      if (request.originalCounselorId == currentUser.uid) {
        throw Exception('You cannot respond to your own reassignment request.');
      }
      if (request.status != SessionReassignmentStatus.openForResponses) {
        throw Exception(
          'This reassignment request is no longer accepting responses.',
        );
      }
      if (nowUtc.isAfter(request.responseDeadlineAt)) {
        throw Exception('The response window has already closed.');
      }
      final alreadyInterested = request.interestedCounselors.any(
        (entry) => entry.counselorId == currentUser.uid,
      );
      if (alreadyInterested) {
        throw Exception('You already expressed interest in this request.');
      }
      if (request.interestedCounselors.length >=
          request.maxInterestedCounselors) {
        throw Exception(
          'The maximum number of interested counselors was reached.',
        );
      }

      final nextInterestedCounselor = ReassignmentInterestedCounselor(
        counselorId: currentUser.uid,
        displayName: profile.displayName,
        specialization: profile.specialization,
        languages: profile.languages,
        sessionMode: profile.sessionMode,
        respondedAt: nowUtc,
        isActive: profile.isActive,
      );
      final nextInterested = <ReassignmentInterestedCounselor>[
        ...request.interestedCounselors,
        nextInterestedCounselor,
      ];
      final reachedDecisionPhase =
          nextInterested.length >= request.maxInterestedCounselors;

      await _windowsRest
          .updateDocument('session_reassignment_requests/${request.id}', {
            'interestedCounselors': nextInterested
                .map(_windowsInterestedCounselorPayload)
                .toList(growable: false),
            'status': reachedDecisionPhase
                ? SessionReassignmentStatus.awaitingPatientChoice.wireName
                : SessionReassignmentStatus.openForResponses.wireName,
            if (reachedDecisionPhase)
              'choiceDeadlineAt': nowUtc.add(const Duration(hours: 12)),
            'updatedAt': nowUtc,
          });

      await _createNotifications([
        _notificationPayload(
          userId: request.originalCounselorId,
          institutionId: request.institutionId,
          type: 'reassignment_interest_received',
          title: 'A counselor is available',
          body:
              '${profile.displayName} offered to take the session on ${_formatDateTime(request.sessionStartAt)}.',
          relatedAppointmentId: request.appointmentId,
          relatedId: request.id,
          route: Uri(
            path: AppRoute.sessionDetails,
            queryParameters: <String, String>{
              'appointmentId': request.appointmentId,
            },
          ).toString(),
        ),
        _notificationPayload(
          userId: request.studentId,
          institutionId: request.institutionId,
          type: reachedDecisionPhase
              ? 'reassignment_choice_ready'
              : 'reassignment_interest_received',
          title: reachedDecisionPhase
              ? 'Replacement counselors are ready'
              : 'A new counselor is available',
          body: reachedDecisionPhase
              ? 'The request reached its response cap. You can now review the available counselors and choose one.'
              : '${profile.displayName} is now available if you want to review transfer options.',
          relatedAppointmentId: request.appointmentId,
          relatedId: request.id,
          actionRequired: true,
          priority: 'high',
          route: Uri(
            path: AppRoute.sessionDetails,
            queryParameters: <String, String>{
              'appointmentId': request.appointmentId,
            },
          ).toString(),
        ),
      ]);
      return;
    }

    final profileSnapshot = await _firestore
        .collection('counselor_profiles')
        .doc(currentUser.uid)
        .get();
    if (!profileSnapshot.exists || profileSnapshot.data() == null) {
      throw Exception('Counselor profile not found.');
    }
    final profile = CounselorProfile.fromMap(
      profileSnapshot.id,
      profileSnapshot.data()!,
    );
    final settings = await getCounselorWorkflowSettings(profile.institutionId);
    if (!settings.reassignmentEnabled) {
      throw Exception(
        'Counselor-to-counselor reassignment is disabled for this institution.',
      );
    }

    final requestRef = _firestore
        .collection('session_reassignment_requests')
        .doc(requestId.trim());
    bool reachedDecisionPhase = false;
    SessionReassignmentRequest? updatedRequest;

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Reassignment request not found.');
      }
      final request = SessionReassignmentRequest.fromMap(
        snapshot.id,
        snapshot.data()!,
      );
      final nowUtc = DateTime.now().toUtc();
      if (request.originalCounselorId == currentUser.uid) {
        throw Exception('You cannot respond to your own reassignment request.');
      }
      if (request.status != SessionReassignmentStatus.openForResponses) {
        throw Exception(
          'This reassignment request is no longer accepting responses.',
        );
      }
      if (nowUtc.isAfter(request.responseDeadlineAt)) {
        throw Exception('The response window has already closed.');
      }
      final alreadyInterested = request.interestedCounselors.any(
        (entry) => entry.counselorId == currentUser.uid,
      );
      if (alreadyInterested) {
        throw Exception('You already expressed interest in this request.');
      }
      if (request.interestedCounselors.length >=
          request.maxInterestedCounselors) {
        throw Exception(
          'The maximum number of interested counselors was reached.',
        );
      }

      final nextInterested = [
        ...request.interestedCounselors.map((entry) => entry.toMap()),
        ReassignmentInterestedCounselor(
          counselorId: currentUser.uid,
          displayName: profile.displayName,
          specialization: profile.specialization,
          languages: profile.languages,
          sessionMode: profile.sessionMode,
          respondedAt: nowUtc,
          isActive: profile.isActive,
        ).toMap(),
      ];
      final nextCount = nextInterested.length;
      reachedDecisionPhase = nextCount >= request.maxInterestedCounselors;
      transaction.update(requestRef, {
        'interestedCounselors': nextInterested,
        'status': reachedDecisionPhase
            ? SessionReassignmentStatus.awaitingPatientChoice.wireName
            : SessionReassignmentStatus.openForResponses.wireName,
        if (reachedDecisionPhase)
          'choiceDeadlineAt': Timestamp.fromDate(
            nowUtc.add(const Duration(hours: 12)),
          ),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      updatedRequest = SessionReassignmentRequest(
        id: request.id,
        appointmentId: request.appointmentId,
        institutionId: request.institutionId,
        originalCounselorId: request.originalCounselorId,
        studentId: request.studentId,
        studentName: request.studentName,
        requiredSpecialization: request.requiredSpecialization,
        sessionMode: request.sessionMode,
        sessionStartAt: request.sessionStartAt,
        sessionEndAt: request.sessionEndAt,
        status: reachedDecisionPhase
            ? SessionReassignmentStatus.awaitingPatientChoice
            : SessionReassignmentStatus.openForResponses,
        maxInterestedCounselors: request.maxInterestedCounselors,
        responseDeadlineAt: request.responseDeadlineAt,
        createdAt: request.createdAt,
        updatedAt: nowUtc,
        choiceDeadlineAt: reachedDecisionPhase
            ? nowUtc.add(const Duration(hours: 12))
            : request.choiceDeadlineAt,
        originalCounselorRecommendationId:
            request.originalCounselorRecommendationId,
        selectedCounselorId: request.selectedCounselorId,
        selectedCounselorName: request.selectedCounselorName,
        interestedCounselors: [
          ...request.interestedCounselors,
          ReassignmentInterestedCounselor(
            counselorId: currentUser.uid,
            displayName: profile.displayName,
            specialization: profile.specialization,
            languages: profile.languages,
            sessionMode: profile.sessionMode,
            respondedAt: nowUtc,
            isActive: profile.isActive,
          ),
        ],
      );
    });

    final request = updatedRequest;
    if (request == null) {
      return;
    }

    await _createNotifications([
      _notificationPayload(
        userId: request.originalCounselorId,
        institutionId: request.institutionId,
        type: 'reassignment_interest_received',
        title: 'A counselor is available',
        body:
            '${profile.displayName} offered to take the session on ${_formatDateTime(request.sessionStartAt)}.',
        relatedAppointmentId: request.appointmentId,
        relatedId: request.id,
        route: Uri(
          path: AppRoute.sessionDetails,
          queryParameters: <String, String>{
            'appointmentId': request.appointmentId,
          },
        ).toString(),
      ),
      _notificationPayload(
        userId: request.studentId,
        institutionId: request.institutionId,
        type: reachedDecisionPhase
            ? 'reassignment_choice_ready'
            : 'reassignment_interest_received',
        title: reachedDecisionPhase
            ? 'Replacement counselors are ready'
            : 'A new counselor is available',
        body: reachedDecisionPhase
            ? 'The request reached its response cap. You can now review the available counselors and choose one.'
            : '${profile.displayName} is now available if you want to review transfer options.',
        relatedAppointmentId: request.appointmentId,
        relatedId: request.id,
        actionRequired: true,
        priority: 'high',
        route: Uri(
          path: AppRoute.sessionDetails,
          queryParameters: <String, String>{
            'appointmentId': request.appointmentId,
          },
        ).toString(),
      ),
    ]);
  }

  Future<void> recommendInterestedCounselor({
    required String requestId,
    required String counselorId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    if (kUseWindowsRestAuth) {
      final request = await getAppointmentReassignmentRequest(requestId.trim());
      if (request == null) {
        throw Exception('Reassignment request not found.');
      }
      if (request.originalCounselorId != currentUser.uid) {
        throw Exception(
          'Only the original counselor can recommend a replacement.',
        );
      }
      final match = request.interestedCounselors.any(
        (entry) => entry.counselorId == counselorId,
      );
      if (!match) {
        throw Exception('That counselor has not expressed interest.');
      }
      await _windowsRest
          .updateDocument('session_reassignment_requests/${request.id}', {
            'originalCounselorRecommendationId': counselorId,
            'updatedAt': DateTime.now().toUtc(),
          });
      final counselor = request.interestedCounselors.firstWhere(
        (entry) => entry.counselorId == counselorId,
      );
      await _createNotifications([
        _notificationPayload(
          userId: request.studentId,
          institutionId: request.institutionId,
          type: 'reassignment_recommended',
          title: 'Your counselor suggested a best-fit option',
          body:
              '${counselor.displayName} was marked as the recommended transfer option for this session.',
          relatedAppointmentId: request.appointmentId,
          relatedId: request.id,
          actionRequired: true,
          priority: 'high',
          route: Uri(
            path: AppRoute.sessionDetails,
            queryParameters: <String, String>{
              'appointmentId': request.appointmentId,
            },
          ).toString(),
        ),
      ]);
      return;
    }

    final requestRef = _firestore
        .collection('session_reassignment_requests')
        .doc(requestId.trim());
    SessionReassignmentRequest? request;
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Reassignment request not found.');
      }
      request = SessionReassignmentRequest.fromMap(
        snapshot.id,
        snapshot.data()!,
      );
      if (request!.originalCounselorId != currentUser.uid) {
        throw Exception(
          'Only the original counselor can recommend a replacement.',
        );
      }
      final match = request!.interestedCounselors.any(
        (entry) => entry.counselorId == counselorId,
      );
      if (!match) {
        throw Exception('That counselor has not expressed interest.');
      }
      transaction.update(requestRef, {
        'originalCounselorRecommendationId': counselorId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final activeRequest = request;
    if (activeRequest == null) {
      return;
    }
    final counselor = activeRequest.interestedCounselors.firstWhere(
      (entry) => entry.counselorId == counselorId,
    );
    await _createNotifications([
      _notificationPayload(
        userId: activeRequest.studentId,
        institutionId: activeRequest.institutionId,
        type: 'reassignment_recommended',
        title: 'Your counselor suggested a best-fit option',
        body:
            '${counselor.displayName} was marked as the recommended transfer option for this session.',
        relatedAppointmentId: activeRequest.appointmentId,
        relatedId: activeRequest.id,
        actionRequired: true,
        priority: 'high',
        route: Uri(
          path: AppRoute.sessionDetails,
          queryParameters: <String, String>{
            'appointmentId': activeRequest.appointmentId,
          },
        ).toString(),
      ),
    ]);
  }

  Future<void> selectInterestedCounselorAsPatient({
    required String requestId,
    required String counselorId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    if (kUseWindowsRestAuth) {
      final request = await getAppointmentReassignmentRequest(requestId.trim());
      if (request == null) {
        throw Exception('Reassignment request not found.');
      }
      if (request.studentId != currentUser.uid) {
        throw Exception(
          'Only the session owner can choose a replacement counselor.',
        );
      }
      if (request.status != SessionReassignmentStatus.openForResponses &&
          request.status != SessionReassignmentStatus.awaitingPatientChoice) {
        throw Exception('This reassignment request can no longer be selected.');
      }
      final matches = request.interestedCounselors.where(
        (entry) => entry.counselorId == counselorId,
      );
      if (matches.isEmpty) {
        throw Exception(
          'That counselor is not available in the current request.',
        );
      }
      final selected = matches.first;
      final nowUtc = DateTime.now().toUtc();
      await _windowsRest
          .updateDocument('session_reassignment_requests/${request.id}', {
            'status': SessionReassignmentStatus.patientSelected.wireName,
            'selectedCounselorId': selected.counselorId,
            'selectedCounselorName': selected.displayName,
            'patientSelectedAt': nowUtc,
            'updatedAt': nowUtc,
          });

      await _createNotifications([
        _notificationPayload(
          userId: request.originalCounselorId,
          institutionId: request.institutionId,
          type: 'reassignment_patient_selected',
          title: 'Patient selected a replacement counselor',
          body:
              'The patient chose ${selected.displayName}. Review and confirm the transfer when you are ready.',
          relatedAppointmentId: request.appointmentId,
          relatedId: request.id,
          actionRequired: true,
          priority: 'high',
          route: Uri(
            path: AppRoute.sessionDetails,
            queryParameters: <String, String>{
              'appointmentId': request.appointmentId,
            },
          ).toString(),
        ),
        _notificationPayload(
          userId: selected.counselorId,
          institutionId: request.institutionId,
          type: 'reassignment_patient_selected',
          title: 'Patient wants you to take the session',
          body:
              'The patient selected you as the replacement counselor. Wait for the original counselor to finalize the transfer.',
          relatedAppointmentId: request.appointmentId,
          relatedId: request.id,
          actionRequired: true,
        ),
      ]);
      return;
    }

    final requestRef = _firestore
        .collection('session_reassignment_requests')
        .doc(requestId.trim());
    SessionReassignmentRequest? request;
    ReassignmentInterestedCounselor? selected;
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Reassignment request not found.');
      }
      request = SessionReassignmentRequest.fromMap(
        snapshot.id,
        snapshot.data()!,
      );
      if (request!.studentId != currentUser.uid) {
        throw Exception(
          'Only the session owner can choose a replacement counselor.',
        );
      }
      if (request!.status != SessionReassignmentStatus.openForResponses &&
          request!.status != SessionReassignmentStatus.awaitingPatientChoice) {
        throw Exception('This reassignment request can no longer be selected.');
      }
      final matches = request!.interestedCounselors.where(
        (entry) => entry.counselorId == counselorId,
      );
      if (matches.isEmpty) {
        throw Exception(
          'That counselor is not available in the current request.',
        );
      }
      selected = matches.first;
      transaction.update(requestRef, {
        'status': SessionReassignmentStatus.patientSelected.wireName,
        'selectedCounselorId': selected!.counselorId,
        'selectedCounselorName': selected!.displayName,
        'patientSelectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final activeRequest = request;
    final chosen = selected;
    if (activeRequest == null || chosen == null) {
      return;
    }
    await _createNotifications([
      _notificationPayload(
        userId: activeRequest.originalCounselorId,
        institutionId: activeRequest.institutionId,
        type: 'reassignment_patient_selected',
        title: 'Patient selected a replacement counselor',
        body:
            'The patient chose ${chosen.displayName}. Review and confirm the transfer when you are ready.',
        relatedAppointmentId: activeRequest.appointmentId,
        relatedId: activeRequest.id,
        actionRequired: true,
        priority: 'high',
        route: Uri(
          path: AppRoute.sessionDetails,
          queryParameters: <String, String>{
            'appointmentId': activeRequest.appointmentId,
          },
        ).toString(),
      ),
      _notificationPayload(
        userId: chosen.counselorId,
        institutionId: activeRequest.institutionId,
        type: 'reassignment_patient_selected',
        title: 'Patient wants you to take the session',
        body:
            'The patient selected you as the replacement counselor. Wait for the original counselor to finalize the transfer.',
        relatedAppointmentId: activeRequest.appointmentId,
        relatedId: activeRequest.id,
        actionRequired: true,
      ),
    ]);
  }

  Future<void> declineReassignmentAsPatient(String requestId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    if (kUseWindowsRestAuth) {
      final request = await getAppointmentReassignmentRequest(requestId.trim());
      if (request == null) {
        throw Exception('Reassignment request not found.');
      }
      if (request.studentId != currentUser.uid) {
        throw Exception('Only the session owner can decline a transfer.');
      }
      if (request.status == SessionReassignmentStatus.transferred ||
          request.status == SessionReassignmentStatus.cancelled ||
          request.status == SessionReassignmentStatus.expired ||
          request.status == SessionReassignmentStatus.declined) {
        throw Exception('This reassignment request is already closed.');
      }
      await _windowsRest
          .updateDocument('session_reassignment_requests/${request.id}', {
            'status': SessionReassignmentStatus.declined.wireName,
            'updatedAt': DateTime.now().toUtc(),
          });

      await _createNotifications([
        _notificationPayload(
          userId: request.originalCounselorId,
          institutionId: request.institutionId,
          type: 'reassignment_declined',
          title: 'Patient declined the transfer',
          body:
              'The patient declined the replacement counselor options. Keep the session or take another path.',
          relatedAppointmentId: request.appointmentId,
          relatedId: request.id,
        ),
      ]);
      return;
    }

    final requestRef = _firestore
        .collection('session_reassignment_requests')
        .doc(requestId.trim());
    SessionReassignmentRequest? request;
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Reassignment request not found.');
      }
      request = SessionReassignmentRequest.fromMap(
        snapshot.id,
        snapshot.data()!,
      );
      if (request!.studentId != currentUser.uid) {
        throw Exception('Only the session owner can decline a transfer.');
      }
      if (request!.status == SessionReassignmentStatus.transferred ||
          request!.status == SessionReassignmentStatus.cancelled ||
          request!.status == SessionReassignmentStatus.expired ||
          request!.status == SessionReassignmentStatus.declined) {
        throw Exception('This reassignment request is already closed.');
      }
      transaction.update(requestRef, {
        'status': SessionReassignmentStatus.declined.wireName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final activeRequest = request;
    if (activeRequest == null) {
      return;
    }
    await _createNotifications([
      _notificationPayload(
        userId: activeRequest.originalCounselorId,
        institutionId: activeRequest.institutionId,
        type: 'reassignment_declined',
        title: 'Patient declined the transfer',
        body:
            'The patient declined the replacement counselor options. Keep the session or take another path.',
        relatedAppointmentId: activeRequest.appointmentId,
        relatedId: activeRequest.id,
      ),
    ]);
  }

  Future<void> cancelReassignmentRequest(String requestId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    if (kUseWindowsRestAuth) {
      final request = await getAppointmentReassignmentRequest(requestId.trim());
      if (request == null) {
        throw Exception('Reassignment request not found.');
      }
      if (request.originalCounselorId != currentUser.uid) {
        throw Exception('Only the original counselor can cancel this request.');
      }
      if (request.status == SessionReassignmentStatus.transferred ||
          request.status == SessionReassignmentStatus.cancelled) {
        throw Exception('This reassignment request is already closed.');
      }
      final nowUtc = DateTime.now().toUtc();
      await _windowsRest
          .updateDocument('session_reassignment_requests/${request.id}', {
            'status': SessionReassignmentStatus.cancelled.wireName,
            'cancelledAt': nowUtc,
            'updatedAt': nowUtc,
          });
      return;
    }

    final requestRef = _firestore
        .collection('session_reassignment_requests')
        .doc(requestId.trim());
    SessionReassignmentRequest? request;
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Reassignment request not found.');
      }
      request = SessionReassignmentRequest.fromMap(
        snapshot.id,
        snapshot.data()!,
      );
      if (request!.originalCounselorId != currentUser.uid) {
        throw Exception('Only the original counselor can cancel this request.');
      }
      if (request!.status == SessionReassignmentStatus.transferred ||
          request!.status == SessionReassignmentStatus.cancelled) {
        throw Exception('This reassignment request is already closed.');
      }
      transaction.update(requestRef, {
        'status': SessionReassignmentStatus.cancelled.wireName,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> confirmReassignmentTransfer(String requestId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    if (kUseWindowsRestAuth) {
      final request = await getAppointmentReassignmentRequest(requestId.trim());
      if (request == null) {
        throw Exception('Reassignment request not found.');
      }
      if (request.originalCounselorId != currentUser.uid) {
        throw Exception(
          'Only the original counselor can confirm the transfer.',
        );
      }
      if (request.status != SessionReassignmentStatus.patientSelected) {
        throw Exception('Patient selection is required before transfer.');
      }
      final selectedCounselorId = request.selectedCounselorId ?? '';
      final selectedCounselorName =
          request.selectedCounselorName ?? 'Counselor';
      if (selectedCounselorId.isEmpty) {
        throw Exception('No replacement counselor was selected.');
      }

      final appointmentDocument = await _windowsRest.getDocument(
        'appointments/${request.appointmentId}',
      );
      if (appointmentDocument == null) {
        throw Exception('Original appointment not found.');
      }
      final appointment = AppointmentRecord.fromMap(
        appointmentDocument.id,
        appointmentDocument.data,
      );
      if (appointment.counselorId != currentUser.uid) {
        throw Exception('The session is no longer assigned to you.');
      }
      if (appointment.status != AppointmentStatus.pending &&
          appointment.status != AppointmentStatus.confirmed) {
        throw Exception(
          'Only pending or confirmed sessions can be transferred.',
        );
      }

      final selectedProfile = await getCounselorProfile(selectedCounselorId);
      if (selectedProfile == null) {
        throw Exception('Replacement counselor profile not found.');
      }
      if (!selectedProfile.isActive) {
        throw Exception('Replacement counselor is not active right now.');
      }

      final newAppointmentId = _windowsDocId('appt');
      final nowUtc = DateTime.now().toUtc();
      await _windowsRest.setDocument('appointments/$newAppointmentId', {
        'institutionId': appointment.institutionId,
        'counselorId': selectedCounselorId,
        'studentId': appointment.studentId,
        'slotId': 'reassigned_${request.id}',
        'startAt': appointment.startAt.toUtc(),
        'endAt': appointment.endAt.toUtc(),
        'status': AppointmentStatus.confirmed.name,
        'studentName': appointment.studentName,
        'counselorName': selectedCounselorName,
        'rated': false,
        'rescheduledFromAppointmentId': appointment.id,
        'createdAt': nowUtc,
        'updatedAt': nowUtc,
      });
      await _windowsRest.updateDocument('appointments/${appointment.id}', {
        'status': AppointmentStatus.cancelled.name,
        'cancelledByRole': 'counselor',
        'counselorCancelMessage':
            'Session reassigned to $selectedCounselorName after patient approval.',
        'rescheduledToAppointmentId': newAppointmentId,
        'cancelledAt': nowUtc,
        'updatedAt': nowUtc,
      });
      await _windowsRest
          .updateDocument('session_reassignment_requests/${request.id}', {
            'status': SessionReassignmentStatus.transferred.wireName,
            'transferredAppointmentId': newAppointmentId,
            'confirmedAt': nowUtc,
            'updatedAt': nowUtc,
          });

      await _createNotifications([
        _notificationPayload(
          userId: request.studentId,
          institutionId: request.institutionId,
          type: 'reassignment_transferred',
          title: 'Session moved to a new counselor',
          body:
              'Your session was transferred to $selectedCounselorName and is now confirmed.',
          relatedAppointmentId: newAppointmentId,
          relatedId: request.id,
          route: Uri(
            path: AppRoute.sessionDetails,
            queryParameters: <String, String>{
              'appointmentId': newAppointmentId,
            },
          ).toString(),
        ),
        _notificationPayload(
          userId: selectedCounselorId,
          institutionId: request.institutionId,
          type: 'reassignment_transferred',
          title: 'Session assigned to you',
          body:
              'The transfer is complete. You now own the session scheduled for ${_formatDateTime(request.sessionStartAt)}.',
          relatedAppointmentId: newAppointmentId,
          relatedId: request.id,
          route: Uri(
            path: AppRoute.sessionDetails,
            queryParameters: <String, String>{
              'appointmentId': newAppointmentId,
            },
          ).toString(),
        ),
        _notificationPayload(
          userId: request.originalCounselorId,
          institutionId: request.institutionId,
          type: 'reassignment_transferred',
          title: 'Transfer complete',
          body:
              'The session was transferred to $selectedCounselorName and all parties were notified.',
          relatedAppointmentId: newAppointmentId,
          relatedId: request.id,
        ),
      ]);
      return;
    }

    final requestRef = _firestore
        .collection('session_reassignment_requests')
        .doc(requestId.trim());
    final appointmentCollection = _firestore.collection('appointments');
    SessionReassignmentRequest? request;
    String? newAppointmentId;

    await _firestore.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestRef);
      if (!requestSnapshot.exists || requestSnapshot.data() == null) {
        throw Exception('Reassignment request not found.');
      }
      request = SessionReassignmentRequest.fromMap(
        requestSnapshot.id,
        requestSnapshot.data()!,
      );
      if (request!.originalCounselorId != currentUser.uid) {
        throw Exception(
          'Only the original counselor can confirm the transfer.',
        );
      }
      if (request!.status != SessionReassignmentStatus.patientSelected) {
        throw Exception('Patient selection is required before transfer.');
      }
      final selectedCounselorId = request!.selectedCounselorId ?? '';
      final selectedCounselorName =
          request!.selectedCounselorName ?? 'Counselor';
      if (selectedCounselorId.isEmpty) {
        throw Exception('No replacement counselor was selected.');
      }

      final originalAppointmentRef = appointmentCollection.doc(
        request!.appointmentId,
      );
      final appointmentSnapshot = await transaction.get(originalAppointmentRef);
      if (!appointmentSnapshot.exists || appointmentSnapshot.data() == null) {
        throw Exception('Original appointment not found.');
      }
      final appointment = AppointmentRecord.fromMap(
        appointmentSnapshot.id,
        appointmentSnapshot.data()!,
      );
      if (appointment.counselorId != currentUser.uid) {
        throw Exception('The session is no longer assigned to you.');
      }
      if (appointment.status != AppointmentStatus.pending &&
          appointment.status != AppointmentStatus.confirmed) {
        throw Exception(
          'Only pending or confirmed sessions can be transferred.',
        );
      }

      final selectedProfileRef = _firestore
          .collection('counselor_profiles')
          .doc(selectedCounselorId);
      final selectedProfileSnapshot = await transaction.get(selectedProfileRef);
      if (!selectedProfileSnapshot.exists ||
          selectedProfileSnapshot.data() == null) {
        throw Exception('Replacement counselor profile not found.');
      }
      final selectedProfile = CounselorProfile.fromMap(
        selectedProfileSnapshot.id,
        selectedProfileSnapshot.data()!,
      );
      if (!selectedProfile.isActive) {
        throw Exception('Replacement counselor is not active right now.');
      }

      final newAppointmentRef = appointmentCollection.doc();
      newAppointmentId = newAppointmentRef.id;
      transaction.set(newAppointmentRef, {
        'institutionId': appointment.institutionId,
        'counselorId': selectedCounselorId,
        'studentId': appointment.studentId,
        'slotId': 'reassigned_${request!.id}',
        'startAt': Timestamp.fromDate(appointment.startAt.toUtc()),
        'endAt': Timestamp.fromDate(appointment.endAt.toUtc()),
        'status': AppointmentStatus.confirmed.name,
        'studentName': appointment.studentName,
        'counselorName': selectedCounselorName,
        'rated': false,
        'rescheduledFromAppointmentId': appointment.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(originalAppointmentRef, {
        'status': AppointmentStatus.cancelled.name,
        'cancelledByRole': 'counselor',
        'counselorCancelMessage':
            'Session reassigned to $selectedCounselorName after patient approval.',
        'rescheduledToAppointmentId': newAppointmentRef.id,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(requestRef, {
        'status': SessionReassignmentStatus.transferred.wireName,
        'transferredAppointmentId': newAppointmentRef.id,
        'confirmedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final activeRequest = request;
    final transferredAppointmentId = newAppointmentId;
    if (activeRequest == null || transferredAppointmentId == null) {
      return;
    }
    final selectedCounselorId = activeRequest.selectedCounselorId ?? '';
    final selectedCounselorName =
        activeRequest.selectedCounselorName ?? 'Counselor';
    await _createNotifications([
      _notificationPayload(
        userId: activeRequest.studentId,
        institutionId: activeRequest.institutionId,
        type: 'reassignment_transferred',
        title: 'Session moved to a new counselor',
        body:
            'Your session was transferred to $selectedCounselorName and is now confirmed.',
        relatedAppointmentId: transferredAppointmentId,
        relatedId: activeRequest.id,
        route: Uri(
          path: AppRoute.sessionDetails,
          queryParameters: <String, String>{
            'appointmentId': transferredAppointmentId,
          },
        ).toString(),
      ),
      _notificationPayload(
        userId: selectedCounselorId,
        institutionId: activeRequest.institutionId,
        type: 'reassignment_transferred',
        title: 'Session assigned to you',
        body:
            'The transfer is complete. You now own the session scheduled for ${_formatDateTime(activeRequest.sessionStartAt)}.',
        relatedAppointmentId: transferredAppointmentId,
        relatedId: activeRequest.id,
        route: Uri(
          path: AppRoute.sessionDetails,
          queryParameters: <String, String>{
            'appointmentId': transferredAppointmentId,
          },
        ).toString(),
      ),
      _notificationPayload(
        userId: activeRequest.originalCounselorId,
        institutionId: activeRequest.institutionId,
        type: 'reassignment_transferred',
        title: 'Transfer complete',
        body:
            'The session was transferred to $selectedCounselorName and all parties were notified.',
        relatedAppointmentId: transferredAppointmentId,
        relatedId: activeRequest.id,
      ),
    ]);
  }

  Stream<List<AvailabilitySlot>> watchCounselorPublicAvailability({
    required String institutionId,
    required String counselorId,
  }) {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedCounselorId = counselorId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedCounselorId.isEmpty) {
      return Stream.value(const <AvailabilitySlot>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<AvailabilitySlot>>(
        load: () => getCounselorPublicAvailability(
          institutionId: normalizedInstitutionId,
          counselorId: normalizedCounselorId,
        ),
        signature: _availabilitySlotsSignature,
      );
    }
    return _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('counselorId', isEqualTo: normalizedCounselorId)
        .where('status', isEqualTo: AvailabilitySlotStatus.available.name)
        .snapshots()
        .map((snapshot) {
          final slots = snapshot.docs
              .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data()))
              .where((slot) => slot.endAt.isAfter(DateTime.now().toUtc()))
              .toList(growable: false);
          slots.sort((a, b) => a.startAt.compareTo(b.startAt));
          return slots;
        });
  }

  Stream<List<AvailabilitySlot>> watchCounselorSlots({
    required String institutionId,
    required String counselorId,
  }) {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedCounselorId = counselorId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedCounselorId.isEmpty) {
      return Stream.value(const <AvailabilitySlot>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<AvailabilitySlot>>(
        load: () => getCounselorSlots(
          institutionId: normalizedInstitutionId,
          counselorId: normalizedCounselorId,
        ),
        signature: _availabilitySlotsSignature,
      );
    }
    return _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('counselorId', isEqualTo: normalizedCounselorId)
        .snapshots()
        .map((snapshot) {
          final slots = snapshot.docs
              .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          slots.sort((a, b) => a.startAt.compareTo(b.startAt));
          return slots;
        });
  }

  Stream<List<AvailabilitySlot>> watchInstitutionPublicAvailability({
    required String institutionId,
  }) {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const <AvailabilitySlot>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<AvailabilitySlot>>(
        load: () => getInstitutionPublicAvailability(institutionId: normalized),
        signature: _availabilitySlotsSignature,
      );
    }
    return _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: normalized)
        .where('status', isEqualTo: AvailabilitySlotStatus.available.name)
        .snapshots()
        .map((snapshot) {
          final slots = snapshot.docs
              .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data()))
              .where((slot) => slot.endAt.isAfter(DateTime.now().toUtc()))
              .toList(growable: false);
          slots.sort((a, b) => a.startAt.compareTo(b.startAt));
          return slots;
        });
  }

  Future<void> createAvailabilitySlot({
    required String institutionId,
    required DateTime startAtUtc,
    required DateTime endAtUtc,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (!endAtUtc.isAfter(startAtUtc)) {
      throw Exception('End time must be after start time.');
    }

    if (kUseWindowsRestAuth) {
      final overlapping = await getCounselorSlots(
        institutionId: institutionId,
        counselorId: currentUser.uid,
      );
      for (final existing in overlapping) {
        if (existing.endAt.isAfter(startAtUtc) &&
            existing.startAt.isBefore(endAtUtc) &&
            existing.status != AvailabilitySlotStatus.blocked) {
          throw Exception('This slot overlaps with an existing schedule.');
        }
      }
      final nowUtc = DateTime.now().toUtc();
      final slotId = _windowsDocId('slot');
      await _windowsRest.setDocument('counselor_availability/$slotId', {
        'institutionId': institutionId,
        'counselorId': currentUser.uid,
        'startAt': startAtUtc.toUtc(),
        'endAt': endAtUtc.toUtc(),
        'status': AvailabilitySlotStatus.available.name,
        'createdAt': nowUtc,
        'updatedAt': nowUtc,
      });
      return;
    }

    final overlapping = await _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: institutionId)
        .where('counselorId', isEqualTo: currentUser.uid)
        .where('startAt', isLessThan: Timestamp.fromDate(endAtUtc))
        .get();

    for (final doc in overlapping.docs) {
      final data = doc.data();
      final existing = AvailabilitySlot.fromMap(doc.id, data);
      if (existing.endAt.isAfter(startAtUtc) &&
          existing.status != AvailabilitySlotStatus.blocked) {
        throw Exception('This slot overlaps with an existing schedule.');
      }
    }

    await _firestore.collection('counselor_availability').add({
      'institutionId': institutionId,
      'counselorId': currentUser.uid,
      'startAt': Timestamp.fromDate(startAtUtc),
      'endAt': Timestamp.fromDate(endAtUtc),
      'status': AvailabilitySlotStatus.available.name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAvailabilitySlot(AvailabilitySlot slot) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (slot.counselorId != currentUser.uid) {
      throw Exception('You cannot modify this slot.');
    }
    if (slot.status != AvailabilitySlotStatus.available) {
      throw Exception('Only available slots can be removed.');
    }

    if (kUseWindowsRestAuth) {
      await _windowsRest.deleteDocument('counselor_availability/${slot.id}');
      return;
    }

    await _firestore.collection('counselor_availability').doc(slot.id).delete();
  }

  Future<void> bookCounselorSlot({
    required String institutionId,
    required CounselorProfile counselor,
    required AvailabilitySlot slot,
    required UserProfile currentProfile,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (currentProfile.role != UserRole.student &&
        currentProfile.role != UserRole.staff &&
        currentProfile.role != UserRole.individual) {
      throw Exception('Your role cannot book counseling sessions.');
    }
    if (slot.status != AvailabilitySlotStatus.available) {
      throw Exception('Selected slot is no longer available.');
    }

    final appointmentId = kUseWindowsRestAuth
        ? _windowsDocId('appt')
        : _firestore.collection('appointments').doc().id;

    if (kUseWindowsRestAuth) {
      final slotDocument = await _windowsRest.getDocument(
        'counselor_availability/${slot.id}',
      );
      if (slotDocument == null) {
        throw Exception('Slot no longer exists.');
      }
      final freshSlot = AvailabilitySlot.fromMap(
        slotDocument.id,
        slotDocument.data,
      );
      if (freshSlot.status != AvailabilitySlotStatus.available) {
        throw Exception('Slot already booked.');
      }
      final nowUtc = DateTime.now().toUtc();
      await _windowsRest.setDocument('appointments/$appointmentId', {
        'institutionId': institutionId,
        'counselorId': counselor.id,
        'studentId': currentUser.uid,
        'slotId': slot.id,
        'startAt': freshSlot.startAt.toUtc(),
        'endAt': freshSlot.endAt.toUtc(),
        'status': AppointmentStatus.pending.name,
        'studentName': currentProfile.name,
        'counselorName': counselor.displayName,
        'rated': false,
        'createdAt': nowUtc,
        'updatedAt': nowUtc,
      });
      await _windowsRest.updateDocument('counselor_availability/${slot.id}', {
        'status': AvailabilitySlotStatus.booked.name,
        'bookedBy': currentUser.uid,
        'appointmentId': appointmentId,
        'updatedAt': nowUtc,
      });

      await _createNotifications([
        _notificationPayload(
          userId: currentUser.uid,
          institutionId: institutionId,
          type: 'booking_confirmed',
          title: 'Session booked',
          body:
              'You booked ${counselor.displayName} on ${_formatDateTime(slot.startAt)}.',
          relatedAppointmentId: appointmentId,
        ),
        _notificationPayload(
          userId: counselor.id,
          institutionId: institutionId,
          type: 'booking_request',
          title: 'New session request',
          body:
              '${currentProfile.name} booked ${_formatDateTime(slot.startAt)}.',
          relatedAppointmentId: appointmentId,
        ),
        _notificationPayload(
          userId: currentUser.uid,
          institutionId: institutionId,
          type: 'booking_reminder',
          title: 'Reminder scheduled',
          body: 'You will be reminded before your session starts.',
          relatedAppointmentId: appointmentId,
        ),
      ]);
      return;
    }

    final slotRef = _firestore
        .collection('counselor_availability')
        .doc(slot.id);
    final appointmentRef = _firestore
        .collection('appointments')
        .doc(appointmentId);

    await _firestore.runTransaction((transaction) async {
      final slotSnap = await transaction.get(slotRef);
      if (!slotSnap.exists || slotSnap.data() == null) {
        throw Exception('Slot no longer exists.');
      }
      final freshSlot = AvailabilitySlot.fromMap(slotSnap.id, slotSnap.data()!);
      if (freshSlot.status != AvailabilitySlotStatus.available) {
        throw Exception('Slot already booked.');
      }

      transaction.set(appointmentRef, {
        'institutionId': institutionId,
        'counselorId': counselor.id,
        'studentId': currentUser.uid,
        'slotId': slot.id,
        'startAt': Timestamp.fromDate(freshSlot.startAt.toUtc()),
        'endAt': Timestamp.fromDate(freshSlot.endAt.toUtc()),
        'status': AppointmentStatus.pending.name,
        'studentName': currentProfile.name,
        'counselorName': counselor.displayName,
        'rated': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(slotRef, {
        'status': AvailabilitySlotStatus.booked.name,
        'bookedBy': currentUser.uid,
        'appointmentId': appointmentRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await _createNotifications([
      _notificationPayload(
        userId: currentUser.uid,
        institutionId: institutionId,
        type: 'booking_confirmed',
        title: 'Session booked',
        body:
            'You booked ${counselor.displayName} on ${_formatDateTime(slot.startAt)}.',
        relatedAppointmentId: appointmentId,
      ),
      _notificationPayload(
        userId: counselor.id,
        institutionId: institutionId,
        type: 'booking_request',
        title: 'New session request',
        body: '${currentProfile.name} booked ${_formatDateTime(slot.startAt)}.',
        relatedAppointmentId: appointmentId,
      ),
      _notificationPayload(
        userId: currentUser.uid,
        institutionId: institutionId,
        type: 'booking_reminder',
        title: 'Reminder scheduled',
        body: 'You will be reminded before your session starts.',
        relatedAppointmentId: appointmentId,
      ),
    ]);
  }

  Stream<List<AppointmentRecord>> watchStudentAppointments({
    required String institutionId,
    required String studentId,
  }) {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedStudentId = studentId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedStudentId.isEmpty) {
      return Stream.value(const <AppointmentRecord>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<AppointmentRecord>>(
        load: () => getStudentAppointments(
          institutionId: normalizedInstitutionId,
          studentId: normalizedStudentId,
        ),
        signature: _appointmentsSignature,
      );
    }
    return _firestore
        .collection('appointments')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('studentId', isEqualTo: normalizedStudentId)
        .snapshots()
        .map((snapshot) {
          final appointments = snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          appointments.sort((a, b) => b.startAt.compareTo(a.startAt));
          return appointments;
        });
  }

  Stream<List<AppointmentRecord>> watchCounselorAppointments({
    required String institutionId,
    required String counselorId,
  }) {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedCounselorId = counselorId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedCounselorId.isEmpty) {
      return Stream.value(const <AppointmentRecord>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<AppointmentRecord>>(
        load: () => getCounselorAppointments(
          institutionId: normalizedInstitutionId,
          counselorId: normalizedCounselorId,
        ),
        signature: _appointmentsSignature,
      );
    }
    return _firestore
        .collection('appointments')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('counselorId', isEqualTo: normalizedCounselorId)
        .snapshots()
        .map((snapshot) {
          final appointments = snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          appointments.sort((a, b) => a.startAt.compareTo(b.startAt));
          return appointments;
        });
  }

  Future<void> cancelAppointmentAsStudent(AppointmentRecord appointment) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (appointment.studentId != currentUser.uid) {
      throw Exception('This appointment does not belong to you.');
    }
    if (appointment.status != AppointmentStatus.pending &&
        appointment.status != AppointmentStatus.confirmed) {
      throw Exception('Only pending or confirmed sessions can be cancelled.');
    }

    await _updateAppointmentAndReleaseSlot(
      appointmentId: appointment.id,
      slotId: appointment.slotId,
      newStatus: AppointmentStatus.cancelled,
      metadata: {
        'cancelledByRole': 'student',
        'counselorCancelMessage': null,
        'cancelledAt': FieldValue.serverTimestamp(),
      },
    );

    await _createNotifications([
      _notificationPayload(
        userId: appointment.studentId,
        institutionId: appointment.institutionId,
        type: 'appointment_cancelled',
        title: 'Session cancelled',
        body: 'Your session was cancelled.',
        relatedAppointmentId: appointment.id,
      ),
      _notificationPayload(
        userId: appointment.counselorId,
        institutionId: appointment.institutionId,
        type: 'appointment_cancelled',
        title: 'Student cancelled a session',
        body: '${appointment.studentName ?? 'A student'} cancelled a session.',
        relatedAppointmentId: appointment.id,
      ),
    ]);
  }

  Future<void> updateAppointmentByCounselor({
    required AppointmentRecord appointment,
    required AppointmentStatus newStatus,
    String? counselorCancelMessage,
    String? attendanceStatus,
    String? counselorSessionNote,
    List<String> counselorActionItems = const <String>[],
    List<String> recommendedGoals = const <String>[],
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (appointment.counselorId != currentUser.uid) {
      throw Exception('You cannot update this appointment.');
    }
    if (newStatus == AppointmentStatus.cancelled) {
      final normalizedMessage = counselorCancelMessage?.trim();
      await _updateAppointmentAndReleaseSlot(
        appointmentId: appointment.id,
        slotId: appointment.slotId,
        newStatus: newStatus,
        metadata: {
          'cancelledByRole': 'counselor',
          'counselorCancelMessage':
              (normalizedMessage == null || normalizedMessage.isEmpty)
              ? null
              : normalizedMessage,
          'cancelledAt': FieldValue.serverTimestamp(),
        },
      );
      await _createNotifications([
        _notificationPayload(
          userId: appointment.studentId,
          institutionId: appointment.institutionId,
          type: 'appointment_cancelled',
          title: 'Session cancelled by counselor',
          body: (normalizedMessage == null || normalizedMessage.isEmpty)
              ? 'Your counselor cancelled the session.'
              : normalizedMessage,
          relatedAppointmentId: appointment.id,
        ),
      ]);
      return;
    }

    final cleanedActionItems = counselorActionItems
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final normalizedSessionNote = counselorSessionNote?.trim();
    final cleanedGoals = recommendedGoals
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    if (kUseWindowsRestAuth) {
      final nowUtc = DateTime.now().toUtc();
      await _windowsRest.updateDocument('appointments/${appointment.id}', {
        'status': newStatus.name,
        'updatedAt': nowUtc,
        if (newStatus == AppointmentStatus.completed) 'completedAt': nowUtc,
        if (newStatus == AppointmentStatus.noShow) 'noShowAt': nowUtc,
        if (attendanceStatus != null && attendanceStatus.trim().isNotEmpty)
          'attendanceStatus': attendanceStatus.trim(),
        if (newStatus == AppointmentStatus.completed)
          'counselorSessionNote': normalizedSessionNote ?? '',
        if (newStatus == AppointmentStatus.completed)
          'counselorActionItems': cleanedActionItems,
      });

      if (newStatus == AppointmentStatus.completed && cleanedGoals.isNotEmpty) {
        for (final goal in cleanedGoals) {
          final goalId = _windowsDocId('goal');
          await _windowsRest.setDocument('care_goals/$goalId', {
            'studentId': appointment.studentId,
            'counselorId': appointment.counselorId,
            'institutionId': appointment.institutionId,
            'title': goal,
            'status': 'active',
            'sourceAppointmentId': appointment.id,
            'createdAt': nowUtc,
            'updatedAt': nowUtc,
          });
        }
      }

      if (newStatus == AppointmentStatus.confirmed) {
        await _createNotifications([
          _notificationPayload(
            userId: appointment.studentId,
            institutionId: appointment.institutionId,
            type: 'booking_confirmed',
            title: 'Session confirmed',
            body: 'Your counselor confirmed your upcoming session.',
            relatedAppointmentId: appointment.id,
          ),
        ]);
        return;
      }

      if (newStatus == AppointmentStatus.completed) {
        await _createNotifications([
          _notificationPayload(
            userId: appointment.studentId,
            institutionId: appointment.institutionId,
            type: 'session_completed',
            title: 'Session completed',
            body:
                'Your counselor completed the session and shared follow-up notes.',
            relatedAppointmentId: appointment.id,
          ),
        ]);
        return;
      }

      if (newStatus == AppointmentStatus.noShow) {
        final noShowBody = attendanceStatus == 'counselor_no_show'
            ? 'Your counselor marked this session as counselor no-show.'
            : 'Your counselor marked this session as student no-show.';
        await _createNotifications([
          _notificationPayload(
            userId: appointment.studentId,
            institutionId: appointment.institutionId,
            type: 'session_no_show',
            title: 'Attendance update',
            body: noShowBody,
            relatedAppointmentId: appointment.id,
          ),
        ]);
      }
      return;
    }

    final batch = _firestore.batch();
    final appointmentRef = _firestore
        .collection('appointments')
        .doc(appointment.id);
    batch.update(appointmentRef, {
      'status': newStatus.name,
      'updatedAt': FieldValue.serverTimestamp(),
      if (newStatus == AppointmentStatus.completed)
        'completedAt': FieldValue.serverTimestamp(),
      if (newStatus == AppointmentStatus.noShow)
        'noShowAt': FieldValue.serverTimestamp(),
      if (attendanceStatus != null && attendanceStatus.trim().isNotEmpty)
        'attendanceStatus': attendanceStatus.trim(),
      if (newStatus == AppointmentStatus.completed)
        'counselorSessionNote': normalizedSessionNote ?? '',
      if (newStatus == AppointmentStatus.completed)
        'counselorActionItems': cleanedActionItems,
    });

    if (newStatus == AppointmentStatus.completed && cleanedGoals.isNotEmpty) {
      for (final goal in cleanedGoals) {
        batch.set(_firestore.collection('care_goals').doc(), {
          'studentId': appointment.studentId,
          'counselorId': appointment.counselorId,
          'institutionId': appointment.institutionId,
          'title': goal,
          'status': 'active',
          'sourceAppointmentId': appointment.id,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();

    if (newStatus == AppointmentStatus.confirmed) {
      await _createNotifications([
        _notificationPayload(
          userId: appointment.studentId,
          institutionId: appointment.institutionId,
          type: 'booking_confirmed',
          title: 'Session confirmed',
          body: 'Your counselor confirmed your upcoming session.',
          relatedAppointmentId: appointment.id,
        ),
      ]);
      return;
    }

    if (newStatus == AppointmentStatus.completed) {
      await _createNotifications([
        _notificationPayload(
          userId: appointment.studentId,
          institutionId: appointment.institutionId,
          type: 'session_completed',
          title: 'Session completed',
          body:
              'Your counselor completed the session and shared follow-up notes.',
          relatedAppointmentId: appointment.id,
        ),
      ]);
      return;
    }

    if (newStatus == AppointmentStatus.noShow) {
      final noShowBody = attendanceStatus == 'counselor_no_show'
          ? 'Your counselor marked this session as counselor no-show.'
          : 'Your counselor marked this session as student no-show.';
      await _createNotifications([
        _notificationPayload(
          userId: appointment.studentId,
          institutionId: appointment.institutionId,
          type: 'session_no_show',
          title: 'Attendance update',
          body: noShowBody,
          relatedAppointmentId: appointment.id,
        ),
      ]);
    }
  }

  Future<void> rescheduleAppointmentAsStudent({
    required AppointmentRecord appointment,
    required AvailabilitySlot newSlot,
    required UserProfile currentProfile,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (appointment.studentId != currentUser.uid) {
      throw Exception('This appointment does not belong to you.');
    }
    if (appointment.status != AppointmentStatus.pending &&
        appointment.status != AppointmentStatus.confirmed) {
      throw Exception('Only pending or confirmed sessions can be rescheduled.');
    }
    if (newSlot.status != AvailabilitySlotStatus.available) {
      throw Exception('Selected new slot is no longer available.');
    }

    final newAppointmentId = kUseWindowsRestAuth
        ? _windowsDocId('appt')
        : _firestore.collection('appointments').doc().id;

    if (kUseWindowsRestAuth) {
      final freshNewSlotDocument = await _windowsRest.getDocument(
        'counselor_availability/${newSlot.id}',
      );
      if (freshNewSlotDocument == null) {
        throw Exception('Selected new slot does not exist.');
      }
      final freshNewSlot = AvailabilitySlot.fromMap(
        freshNewSlotDocument.id,
        freshNewSlotDocument.data,
      );
      if (freshNewSlot.status != AvailabilitySlotStatus.available) {
        throw Exception('Selected new slot is already booked.');
      }

      final oldAppointmentDocument = await _windowsRest.getDocument(
        'appointments/${appointment.id}',
      );
      if (oldAppointmentDocument == null) {
        throw Exception('Original appointment no longer exists.');
      }
      final freshOldAppointment = AppointmentRecord.fromMap(
        oldAppointmentDocument.id,
        oldAppointmentDocument.data,
      );
      if (freshOldAppointment.status != AppointmentStatus.pending &&
          freshOldAppointment.status != AppointmentStatus.confirmed) {
        throw Exception('This appointment can no longer be rescheduled.');
      }

      final nowUtc = DateTime.now().toUtc();
      await _windowsRest.setDocument('appointments/$newAppointmentId', {
        'institutionId': appointment.institutionId,
        'counselorId': appointment.counselorId,
        'studentId': appointment.studentId,
        'slotId': freshNewSlot.id,
        'startAt': freshNewSlot.startAt.toUtc(),
        'endAt': freshNewSlot.endAt.toUtc(),
        'status': AppointmentStatus.pending.name,
        'studentName': appointment.studentName ?? currentProfile.name,
        'counselorName': appointment.counselorName,
        'rated': false,
        'rescheduledFromAppointmentId': appointment.id,
        'createdAt': nowUtc,
        'updatedAt': nowUtc,
      });

      await _windowsRest
          .updateDocument('counselor_availability/${newSlot.id}', {
            'status': AvailabilitySlotStatus.booked.name,
            'bookedBy': appointment.studentId,
            'appointmentId': newAppointmentId,
            'updatedAt': nowUtc,
          });

      final oldSlotDocument = await _windowsRest.getDocument(
        'counselor_availability/${appointment.slotId}',
      );
      if (oldSlotDocument != null) {
        await _windowsRest
            .updateDocument('counselor_availability/${appointment.slotId}', {
              'status': AvailabilitySlotStatus.available.name,
              'bookedBy': null,
              'appointmentId': null,
              'updatedAt': nowUtc,
            });
      }

      await _windowsRest.updateDocument('appointments/${appointment.id}', {
        'status': AppointmentStatus.cancelled.name,
        'cancelledByRole': 'student',
        'counselorCancelMessage': 'Session rescheduled by student.',
        'rescheduledToAppointmentId': newAppointmentId,
        'cancelledAt': nowUtc,
        'updatedAt': nowUtc,
      });

      await _createNotifications([
        _notificationPayload(
          userId: appointment.studentId,
          institutionId: appointment.institutionId,
          type: 'appointment_rescheduled',
          title: 'Session rescheduled',
          body:
              'Your session was moved to ${_formatDateTime(newSlot.startAt)}.',
          relatedAppointmentId: newAppointmentId,
        ),
        _notificationPayload(
          userId: appointment.counselorId,
          institutionId: appointment.institutionId,
          type: 'appointment_rescheduled',
          title: 'Student rescheduled a session',
          body:
              '${appointment.studentName ?? 'A student'} moved to ${_formatDateTime(newSlot.startAt)}.',
          relatedAppointmentId: newAppointmentId,
        ),
      ]);
      return;
    }

    final oldSlotRef = _firestore
        .collection('counselor_availability')
        .doc(appointment.slotId);
    final newSlotRef = _firestore
        .collection('counselor_availability')
        .doc(newSlot.id);
    final oldAppointmentRef = _firestore
        .collection('appointments')
        .doc(appointment.id);
    final newAppointmentRef = _firestore
        .collection('appointments')
        .doc(newAppointmentId);

    await _firestore.runTransaction((transaction) async {
      final freshNewSlotSnap = await transaction.get(newSlotRef);
      if (!freshNewSlotSnap.exists || freshNewSlotSnap.data() == null) {
        throw Exception('Selected new slot does not exist.');
      }
      final freshNewSlot = AvailabilitySlot.fromMap(
        freshNewSlotSnap.id,
        freshNewSlotSnap.data()!,
      );
      if (freshNewSlot.status != AvailabilitySlotStatus.available) {
        throw Exception('Selected new slot is already booked.');
      }

      final oldAppointmentSnap = await transaction.get(oldAppointmentRef);
      if (!oldAppointmentSnap.exists || oldAppointmentSnap.data() == null) {
        throw Exception('Original appointment no longer exists.');
      }
      final freshOldAppointment = AppointmentRecord.fromMap(
        oldAppointmentSnap.id,
        oldAppointmentSnap.data()!,
      );
      if (freshOldAppointment.status != AppointmentStatus.pending &&
          freshOldAppointment.status != AppointmentStatus.confirmed) {
        throw Exception('This appointment can no longer be rescheduled.');
      }

      transaction.set(newAppointmentRef, {
        'institutionId': appointment.institutionId,
        'counselorId': appointment.counselorId,
        'studentId': appointment.studentId,
        'slotId': freshNewSlot.id,
        'startAt': Timestamp.fromDate(freshNewSlot.startAt.toUtc()),
        'endAt': Timestamp.fromDate(freshNewSlot.endAt.toUtc()),
        'status': AppointmentStatus.pending.name,
        'studentName': appointment.studentName ?? currentProfile.name,
        'counselorName': appointment.counselorName,
        'rated': false,
        'rescheduledFromAppointmentId': appointment.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(newSlotRef, {
        'status': AvailabilitySlotStatus.booked.name,
        'bookedBy': appointment.studentId,
        'appointmentId': newAppointmentRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final oldSlotSnap = await transaction.get(oldSlotRef);
      if (oldSlotSnap.exists) {
        transaction.update(oldSlotRef, {
          'status': AvailabilitySlotStatus.available.name,
          'bookedBy': null,
          'appointmentId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.update(oldAppointmentRef, {
        'status': AppointmentStatus.cancelled.name,
        'cancelledByRole': 'student',
        'counselorCancelMessage': 'Session rescheduled by student.',
        'rescheduledToAppointmentId': newAppointmentRef.id,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await _createNotifications([
      _notificationPayload(
        userId: appointment.studentId,
        institutionId: appointment.institutionId,
        type: 'appointment_rescheduled',
        title: 'Session rescheduled',
        body: 'Your session was moved to ${_formatDateTime(newSlot.startAt)}.',
        relatedAppointmentId: newAppointmentId,
      ),
      _notificationPayload(
        userId: appointment.counselorId,
        institutionId: appointment.institutionId,
        type: 'appointment_rescheduled',
        title: 'Student rescheduled a session',
        body:
            '${appointment.studentName ?? 'A student'} moved to ${_formatDateTime(newSlot.startAt)}.',
        relatedAppointmentId: newAppointmentId,
      ),
    ]);
  }

  Future<void> _updateAppointmentAndReleaseSlot({
    required String appointmentId,
    required String slotId,
    required AppointmentStatus newStatus,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (kUseWindowsRestAuth) {
      final nowUtc = DateTime.now().toUtc();
      final slotDocument = await _windowsRest.getDocument(
        'counselor_availability/$slotId',
      );
      if (slotDocument != null) {
        await _windowsRest.updateDocument('counselor_availability/$slotId', {
          'status': AvailabilitySlotStatus.available.name,
          'bookedBy': null,
          'appointmentId': null,
          'updatedAt': nowUtc,
        });
      }
      await _windowsRest.updateDocument('appointments/$appointmentId', {
        'status': newStatus.name,
        'updatedAt': nowUtc,
        ..._normalizeWindowsWriteData(metadata, nowUtc),
      });
      return;
    }

    final appointmentRef = _firestore
        .collection('appointments')
        .doc(appointmentId);
    final slotRef = _firestore.collection('counselor_availability').doc(slotId);

    await _firestore.runTransaction((transaction) async {
      final slotSnap = await transaction.get(slotRef);
      if (slotSnap.exists) {
        transaction.update(slotRef, {
          'status': AvailabilitySlotStatus.available.name,
          'bookedBy': null,
          'appointmentId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.update(appointmentRef, {
        'status': newStatus.name,
        'updatedAt': FieldValue.serverTimestamp(),
        ...metadata,
      });
    });
  }

  Future<void> submitRating({
    required AppointmentRecord appointment,
    required int rating,
    required String feedback,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (appointment.studentId != currentUser.uid) {
      throw Exception('This appointment does not belong to you.');
    }
    if (appointment.status != AppointmentStatus.completed) {
      throw Exception('You can only rate completed sessions.');
    }
    if (appointment.rated) {
      throw Exception('This appointment is already rated.');
    }
    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be between 1 and 5.');
    }

    if (kUseWindowsRestAuth) {
      final freshAppointmentDocument = await _windowsRest.getDocument(
        'appointments/${appointment.id}',
      );
      if (freshAppointmentDocument == null) {
        throw Exception('Appointment not found.');
      }
      final fresh = AppointmentRecord.fromMap(
        freshAppointmentDocument.id,
        freshAppointmentDocument.data,
      );
      if (fresh.studentId != currentUser.uid) {
        throw Exception('This appointment does not belong to you.');
      }
      if (fresh.status != AppointmentStatus.completed) {
        throw Exception('You can only rate completed sessions.');
      }
      if (fresh.rated) {
        throw Exception('This appointment is already rated.');
      }

      final nowUtc = DateTime.now().toUtc();
      await _windowsRest.setDocument('counselor_ratings/${appointment.id}', {
        'appointmentId': appointment.id,
        'institutionId': appointment.institutionId,
        'counselorId': appointment.counselorId,
        'studentId': appointment.studentId,
        'rating': rating,
        'feedback': feedback.trim(),
        'createdAt': nowUtc,
        'updatedAt': nowUtc,
      });
      await _windowsRest.updateDocument('appointments/${appointment.id}', {
        'rated': true,
        'privateRatingId': appointment.id,
        'updatedAt': nowUtc,
      });
      return;
    }

    final ratingRef = _firestore
        .collection('counselor_ratings')
        .doc(appointment.id);
    final appointmentRef = _firestore
        .collection('appointments')
        .doc(appointment.id);

    await _firestore.runTransaction((transaction) async {
      final freshAppointment = await transaction.get(appointmentRef);
      if (!freshAppointment.exists || freshAppointment.data() == null) {
        throw Exception('Appointment not found.');
      }
      final fresh = AppointmentRecord.fromMap(
        freshAppointment.id,
        freshAppointment.data()!,
      );
      if (fresh.studentId != currentUser.uid) {
        throw Exception('This appointment does not belong to you.');
      }
      if (fresh.status != AppointmentStatus.completed) {
        throw Exception('You can only rate completed sessions.');
      }
      if (fresh.rated) {
        throw Exception('This appointment is already rated.');
      }

      transaction.set(ratingRef, {
        'appointmentId': appointment.id,
        'institutionId': appointment.institutionId,
        'counselorId': appointment.counselorId,
        'studentId': appointment.studentId,
        'rating': rating,
        'feedback': feedback.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(appointmentRef, {
        'rated': true,
        'privateRatingId': ratingRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<List<CounselorPublicRating>> watchCounselorPublicRatings({
    required String institutionId,
    required String counselorId,
  }) {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedCounselorId = counselorId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedCounselorId.isEmpty) {
      return Stream.value(const <CounselorPublicRating>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<CounselorPublicRating>>(
        load: () => getCounselorPublicRatings(
          institutionId: normalizedInstitutionId,
          counselorId: normalizedCounselorId,
        ),
        signature: _publicRatingsSignature,
      );
    }
    return _firestore
        .collection('counselor_public_ratings')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('counselorId', isEqualTo: normalizedCounselorId)
        .snapshots()
        .map((snapshot) {
          final ratings = snapshot.docs
              .map((doc) => CounselorPublicRating.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          ratings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return ratings;
        });
  }

  Stream<List<CounselorPublicRating>> watchInstitutionCounselorPublicRatings({
    required String institutionId,
  }) {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const <CounselorPublicRating>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<CounselorPublicRating>>(
        load: () =>
            getInstitutionCounselorPublicRatings(institutionId: normalized),
        signature: _publicRatingsSignature,
      );
    }
    return _firestore
        .collection('counselor_public_ratings')
        .where('institutionId', isEqualTo: normalized)
        .snapshots()
        .map((snapshot) {
          final ratings = snapshot.docs
              .map((doc) => CounselorPublicRating.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          ratings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return ratings;
        });
  }

  Future<void> submitCounselorPublicRating({
    required AppointmentRecord appointment,
    required int rating,
    required String feedback,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (currentUser.uid != appointment.studentId) {
      throw Exception(
        'Only the student from this session can submit this review.',
      );
    }
    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be between 1 and 5.');
    }

    if (kUseWindowsRestAuth) {
      final appointmentDocument = await _windowsRest.getDocument(
        'appointments/${appointment.id}',
      );
      if (appointmentDocument == null) {
        throw Exception('Appointment not found.');
      }
      final freshAppointment = AppointmentRecord.fromMap(
        appointmentDocument.id,
        appointmentDocument.data,
      );
      if (freshAppointment.studentId != currentUser.uid) {
        throw Exception('This appointment does not belong to you.');
      }
      if (freshAppointment.status != AppointmentStatus.completed) {
        throw Exception('Only completed sessions can be publicly reviewed.');
      }

      final nowUtc = DateTime.now().toUtc();
      await _windowsRest
          .setDocument('counselor_public_ratings/${appointment.id}', {
            'appointmentId': appointment.id,
            'institutionId': appointment.institutionId,
            'counselorId': appointment.counselorId,
            'studentId': appointment.studentId,
            'rating': rating,
            'feedback': feedback.trim(),
            'createdAt': nowUtc,
            'updatedAt': nowUtc,
          });
      return;
    }

    final appointmentRef = _firestore
        .collection('appointments')
        .doc(appointment.id);
    final publicRatingRef = _firestore
        .collection('counselor_public_ratings')
        .doc(appointment.id);

    await _firestore.runTransaction((transaction) async {
      final appointmentSnap = await transaction.get(appointmentRef);
      if (!appointmentSnap.exists || appointmentSnap.data() == null) {
        throw Exception('Appointment not found.');
      }
      final freshAppointment = AppointmentRecord.fromMap(
        appointmentSnap.id,
        appointmentSnap.data()!,
      );
      if (freshAppointment.studentId != currentUser.uid) {
        throw Exception('This appointment does not belong to you.');
      }
      if (freshAppointment.status != AppointmentStatus.completed) {
        throw Exception('Only completed sessions can be publicly reviewed.');
      }

      transaction.set(publicRatingRef, {
        'appointmentId': appointment.id,
        'institutionId': appointment.institutionId,
        'counselorId': appointment.counselorId,
        'studentId': appointment.studentId,
        'rating': rating,
        'feedback': feedback.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<List<AppNotification>> watchUserNotifications(String userId) {
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<AppNotification>>(
        load: () => getUserNotifications(userId),
        signature: (items) => items
            .map(
              (item) =>
                  '${item.id}|${item.isRead}|${item.isArchived}|${item.isPinned}|${item.createdAt.toIso8601String()}|${item.pinnedAt?.toIso8601String() ?? ''}',
            )
            .join(';'),
      );
    }
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => AppNotification.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          items.sort((a, b) {
            if (a.isPinned != b.isPinned) {
              return a.isPinned ? -1 : 1;
            }
            if (a.isPinned && b.isPinned) {
              final aPinned = a.pinnedAt ?? a.createdAt;
              final bPinned = b.pinnedAt ?? b.createdAt;
              final pinnedCompare = bPinned.compareTo(aPinned);
              if (pinnedCompare != 0) {
                return pinnedCompare;
              }
            }
            return b.createdAt.compareTo(a.createdAt);
          });
          return items;
        });
  }

  Future<void> markNotificationRead(String notificationId) async {
    if (kUseWindowsRestAuth) {
      final existing = await _windowsRest.getDocument(
        'notifications/$notificationId',
      );
      if (existing == null) {
        return;
      }
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('notifications/$notificationId', {
        ...existing.data,
        'isRead': true,
        'readAt': now,
        'updatedAt': now,
      });
      return;
    }
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<SessionReassignmentRequest?> getAppointmentReassignmentRequest(
    String appointmentId,
  ) async {
    final normalized = appointmentId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (kUseWindowsRestAuth) {
      final document = await _windowsRest.getDocument(
        'session_reassignment_requests/$normalized',
      );
      if (document == null) {
        return null;
      }
      return SessionReassignmentRequest.fromMap(document.id, document.data);
    }
    final doc = await _firestore
        .collection('session_reassignment_requests')
        .doc(normalized)
        .get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return SessionReassignmentRequest.fromMap(doc.id, doc.data()!);
  }

  Future<List<SessionReassignmentRequest>> getInstitutionReassignmentBoard({
    required String institutionId,
  }) async {
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'session_reassignment_requests',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', institutionId),
          WindowsFirestoreFieldFilter.inList('status', const <String>[
            'open_for_responses',
            'awaiting_patient_choice',
            'patient_selected',
          ]),
        ],
      );
      final requests = documents
          .map((doc) => SessionReassignmentRequest.fromMap(doc.id, doc.data))
          .toList(growable: false);
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    }
    final snapshot = await _firestore
        .collection('session_reassignment_requests')
        .where('institutionId', isEqualTo: institutionId)
        .where(
          'status',
          whereIn: const <String>[
            'open_for_responses',
            'awaiting_patient_choice',
            'patient_selected',
          ],
        )
        .get();
    final requests = snapshot.docs
        .map((doc) => SessionReassignmentRequest.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return requests;
  }

  Future<List<CounselorProfile>> getCounselors({
    required String institutionId,
  }) async {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return const <CounselorProfile>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'counselor_profiles',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', normalized),
        ],
      );
      final profiles = documents
          .map((doc) => CounselorProfile.fromMap(doc.id, doc.data))
          .where((profile) => profile.isActive)
          .toList(growable: false);
      profiles.sort((a, b) => a.displayName.compareTo(b.displayName));
      return profiles;
    }
    final snapshot = await _firestore
        .collection('counselor_profiles')
        .where('institutionId', isEqualTo: normalized)
        .get();
    final profiles = snapshot.docs
        .map((doc) => CounselorProfile.fromMap(doc.id, doc.data()))
        .where((profile) => profile.isActive)
        .toList(growable: false);
    profiles.sort((a, b) => a.displayName.compareTo(b.displayName));
    return profiles;
  }

  Future<CounselorProfile?> getCounselorProfile(String counselorId) async {
    final normalized = counselorId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (kUseWindowsRestAuth) {
      final document = await _windowsRest.getDocument(
        'counselor_profiles/$normalized',
      );
      if (document == null) {
        return null;
      }
      return CounselorProfile.fromMap(document.id, document.data);
    }
    final doc = await _firestore
        .collection('counselor_profiles')
        .doc(normalized)
        .get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return CounselorProfile.fromMap(doc.id, doc.data()!);
  }

  Future<List<AvailabilitySlot>> getCounselorPublicAvailability({
    required String institutionId,
    required String counselorId,
  }) async {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedCounselorId = counselorId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedCounselorId.isEmpty) {
      return const <AvailabilitySlot>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'counselor_availability',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal(
            'institutionId',
            normalizedInstitutionId,
          ),
          WindowsFirestoreFieldFilter.equal(
            'counselorId',
            normalizedCounselorId,
          ),
          WindowsFirestoreFieldFilter.equal(
            'status',
            AvailabilitySlotStatus.available.name,
          ),
        ],
      );
      final slots = documents
          .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data))
          .where((slot) => slot.endAt.isAfter(DateTime.now().toUtc()))
          .toList(growable: false);
      slots.sort((a, b) => a.startAt.compareTo(b.startAt));
      return slots;
    }
    final snapshot = await _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('counselorId', isEqualTo: normalizedCounselorId)
        .where('status', isEqualTo: AvailabilitySlotStatus.available.name)
        .get();
    final slots = snapshot.docs
        .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data()))
        .where((slot) => slot.endAt.isAfter(DateTime.now().toUtc()))
        .toList(growable: false);
    slots.sort((a, b) => a.startAt.compareTo(b.startAt));
    return slots;
  }

  Future<List<AvailabilitySlot>> getCounselorSlots({
    required String institutionId,
    required String counselorId,
  }) async {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedCounselorId = counselorId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedCounselorId.isEmpty) {
      return const <AvailabilitySlot>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'counselor_availability',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal(
            'institutionId',
            normalizedInstitutionId,
          ),
          WindowsFirestoreFieldFilter.equal(
            'counselorId',
            normalizedCounselorId,
          ),
        ],
      );
      final slots = documents
          .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data))
          .toList(growable: false);
      slots.sort((a, b) => a.startAt.compareTo(b.startAt));
      return slots;
    }
    final snapshot = await _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('counselorId', isEqualTo: normalizedCounselorId)
        .get();
    final slots = snapshot.docs
        .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    slots.sort((a, b) => a.startAt.compareTo(b.startAt));
    return slots;
  }

  Future<List<AvailabilitySlot>> getInstitutionPublicAvailability({
    required String institutionId,
  }) async {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return const <AvailabilitySlot>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'counselor_availability',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', normalized),
          WindowsFirestoreFieldFilter.equal(
            'status',
            AvailabilitySlotStatus.available.name,
          ),
        ],
      );
      final slots = documents
          .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data))
          .where((slot) => slot.endAt.isAfter(DateTime.now().toUtc()))
          .toList(growable: false);
      slots.sort((a, b) => a.startAt.compareTo(b.startAt));
      return slots;
    }
    final snapshot = await _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: normalized)
        .where('status', isEqualTo: AvailabilitySlotStatus.available.name)
        .get();
    final slots = snapshot.docs
        .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data()))
        .where((slot) => slot.endAt.isAfter(DateTime.now().toUtc()))
        .toList(growable: false);
    slots.sort((a, b) => a.startAt.compareTo(b.startAt));
    return slots;
  }

  Future<List<AppointmentRecord>> getStudentAppointments({
    required String institutionId,
    required String studentId,
  }) async {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedStudentId = studentId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedStudentId.isEmpty) {
      return const <AppointmentRecord>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'appointments',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal(
            'institutionId',
            normalizedInstitutionId,
          ),
          WindowsFirestoreFieldFilter.equal('studentId', normalizedStudentId),
        ],
      );
      final appointments = documents
          .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data))
          .toList(growable: false);
      appointments.sort((a, b) => b.startAt.compareTo(a.startAt));
      return appointments;
    }
    final snapshot = await _firestore
        .collection('appointments')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('studentId', isEqualTo: normalizedStudentId)
        .get();
    final appointments = snapshot.docs
        .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    appointments.sort((a, b) => b.startAt.compareTo(a.startAt));
    return appointments;
  }

  Future<List<AppointmentRecord>> getCounselorAppointments({
    required String institutionId,
    required String counselorId,
  }) async {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedCounselorId = counselorId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedCounselorId.isEmpty) {
      return const <AppointmentRecord>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'appointments',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal(
            'institutionId',
            normalizedInstitutionId,
          ),
          WindowsFirestoreFieldFilter.equal(
            'counselorId',
            normalizedCounselorId,
          ),
        ],
      );
      final appointments = documents
          .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data))
          .toList(growable: false);
      appointments.sort((a, b) => a.startAt.compareTo(b.startAt));
      return appointments;
    }
    final snapshot = await _firestore
        .collection('appointments')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('counselorId', isEqualTo: normalizedCounselorId)
        .get();
    final appointments = snapshot.docs
        .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    appointments.sort((a, b) => a.startAt.compareTo(b.startAt));
    return appointments;
  }

  Future<List<CounselorPublicRating>> getCounselorPublicRatings({
    required String institutionId,
    required String counselorId,
  }) async {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedCounselorId = counselorId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedCounselorId.isEmpty) {
      return const <CounselorPublicRating>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'counselor_public_ratings',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal(
            'institutionId',
            normalizedInstitutionId,
          ),
          WindowsFirestoreFieldFilter.equal(
            'counselorId',
            normalizedCounselorId,
          ),
        ],
      );
      final ratings = documents
          .map((doc) => CounselorPublicRating.fromMap(doc.id, doc.data))
          .toList(growable: false);
      ratings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ratings;
    }
    final snapshot = await _firestore
        .collection('counselor_public_ratings')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('counselorId', isEqualTo: normalizedCounselorId)
        .get();
    final ratings = snapshot.docs
        .map((doc) => CounselorPublicRating.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    ratings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ratings;
  }

  Future<List<CounselorPublicRating>> getInstitutionCounselorPublicRatings({
    required String institutionId,
  }) async {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return const <CounselorPublicRating>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'counselor_public_ratings',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', normalized),
        ],
      );
      final ratings = documents
          .map((doc) => CounselorPublicRating.fromMap(doc.id, doc.data))
          .toList(growable: false);
      ratings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ratings;
    }
    final snapshot = await _firestore
        .collection('counselor_public_ratings')
        .where('institutionId', isEqualTo: normalized)
        .get();
    final ratings = snapshot.docs
        .map((doc) => CounselorPublicRating.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    ratings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ratings;
  }

  Future<List<AppNotification>> getUserNotifications(String userId) async {
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'notifications',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('userId', userId),
        ],
      );
      final items = documents
          .map((doc) => AppNotification.fromMap(doc.id, doc.data))
          .toList(growable: false);
      items.sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        if (a.isPinned && b.isPinned) {
          final aPinned = a.pinnedAt ?? a.createdAt;
          final bPinned = b.pinnedAt ?? b.createdAt;
          final pinnedCompare = bPinned.compareTo(aPinned);
          if (pinnedCompare != 0) {
            return pinnedCompare;
          }
        }
        return b.createdAt.compareTo(a.createdAt);
      });
      return items;
    }
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .get();
    final items = snapshot.docs
        .map((doc) => AppNotification.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    items.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      if (a.isPinned && b.isPinned) {
        final aPinned = a.pinnedAt ?? a.createdAt;
        final bPinned = b.pinnedAt ?? b.createdAt;
        final pinnedCompare = bPinned.compareTo(aPinned);
        if (pinnedCompare != 0) {
          return pinnedCompare;
        }
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return items;
  }

  Future<List<CareGoal>> getStudentGoals({
    required String institutionId,
    required String studentId,
  }) async {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedStudentId = studentId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedStudentId.isEmpty) {
      return const <CareGoal>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'care_goals',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal(
            'institutionId',
            normalizedInstitutionId,
          ),
          WindowsFirestoreFieldFilter.equal('studentId', normalizedStudentId),
        ],
      );
      final goals = documents
          .map((doc) => CareGoal.fromMap(doc.id, doc.data))
          .toList(growable: false);
      goals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return goals;
    }
    final snapshot = await _firestore
        .collection('care_goals')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('studentId', isEqualTo: normalizedStudentId)
        .get();
    final goals = snapshot.docs
        .map((doc) => CareGoal.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    goals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return goals;
  }

  Future<Map<String, dynamic>> getNotificationSettings(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      return const <String, dynamic>{};
    }
    if (kUseWindowsRestAuth) {
      final document = await _windowsRest.getDocument(
        'user_notification_settings/$normalized',
      );
      return document?.data ?? const <String, dynamic>{};
    }
    final doc = await _firestore
        .collection('user_notification_settings')
        .doc(normalized)
        .get();
    return doc.data() ?? const <String, dynamic>{};
  }

  Future<void> markAllNotificationsRead(String userId) async {
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'notifications',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('userId', userId),
          WindowsFirestoreFieldFilter.equal('isRead', false),
        ],
      );
      final now = DateTime.now().toUtc();
      for (final document in documents) {
        await _windowsRest.setDocument('notifications/${document.id}', {
          ...document.data,
          'isRead': true,
          'readAt': now,
          'updatedAt': now,
        });
      }
      return;
    }
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> setNotificationPinned({
    required String notificationId,
    required bool pinned,
  }) async {
    if (kUseWindowsRestAuth) {
      final existing = await _windowsRest.getDocument(
        'notifications/$notificationId',
      );
      if (existing == null) {
        return;
      }
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('notifications/$notificationId', {
        ...existing.data,
        'isPinned': pinned,
        'pinnedAt': pinned ? now : null,
        'updatedAt': now,
      });
      return;
    }
    await _firestore.collection('notifications').doc(notificationId).update({
      'isPinned': pinned,
      'pinnedAt': pinned ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setNotificationArchived({
    required String notificationId,
    required bool archived,
  }) async {
    if (kUseWindowsRestAuth) {
      final existing = await _windowsRest.getDocument(
        'notifications/$notificationId',
      );
      if (existing == null) {
        return;
      }
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('notifications/$notificationId', {
        ...existing.data,
        'isArchived': archived,
        'archivedAt': archived ? now : null,
        'updatedAt': now,
      });
      return;
    }
    await _firestore.collection('notifications').doc(notificationId).update({
      'isArchived': archived,
      'archivedAt': archived ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNotification(String notificationId) async {
    if (kUseWindowsRestAuth) {
      await _windowsRest.deleteDocument('notifications/$notificationId');
      return;
    }
    await _firestore.collection('notifications').doc(notificationId).delete();
  }

  Future<void> clearAllNotifications(String userId) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      return;
    }

    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'notifications',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('userId', trimmedUserId),
        ],
      );
      for (final document in documents) {
        await _windowsRest.deleteDocument('notifications/${document.id}');
      }
      return;
    }

    const batchSize = 400;
    while (true) {
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: trimmedUserId)
          .limit(batchSize)
          .get();
      if (snapshot.docs.isEmpty) {
        break;
      }

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) {
        break;
      }
    }
  }

  Stream<List<CareGoal>> watchStudentGoals({
    required String institutionId,
    required String studentId,
  }) {
    final normalizedInstitutionId = institutionId.trim();
    final normalizedStudentId = studentId.trim();
    if (normalizedInstitutionId.isEmpty || normalizedStudentId.isEmpty) {
      return Stream.value(const <CareGoal>[]);
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<CareGoal>>(
        load: () => getStudentGoals(
          institutionId: normalizedInstitutionId,
          studentId: normalizedStudentId,
        ),
        signature: _careGoalsSignature,
      );
    }
    return _firestore
        .collection('care_goals')
        .where('institutionId', isEqualTo: normalizedInstitutionId)
        .where('studentId', isEqualTo: normalizedStudentId)
        .snapshots()
        .map((snapshot) {
          final goals = snapshot.docs
              .map((doc) => CareGoal.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          goals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return goals;
        });
  }

  Future<void> updateGoalCompletion({
    required String goalId,
    required bool completed,
  }) async {
    if (kUseWindowsRestAuth) {
      final existing = await _windowsRest.getDocument('care_goals/$goalId');
      if (existing == null) {
        throw Exception('Goal not found.');
      }
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('care_goals/$goalId', {
        ...existing.data,
        'status': completed ? 'completed' : 'active',
        'updatedAt': now,
        'completedAt': completed ? now : null,
      });
      return;
    }
    await _firestore.collection('care_goals').doc(goalId).update({
      'status': completed ? 'completed' : 'active',
      'updatedAt': FieldValue.serverTimestamp(),
      'completedAt': completed ? FieldValue.serverTimestamp() : null,
    });
  }

  Future<void> saveNotificationSettings({
    required String userId,
    required bool bookingUpdates,
    required bool reminders,
    required bool cancellations,
  }) async {
    if (kUseWindowsRestAuth) {
      final existing =
          (await _windowsRest.getDocument(
            'user_notification_settings/$userId',
          ))?.data ??
          const <String, dynamic>{};
      await _windowsRest.setDocument('user_notification_settings/$userId', {
        ...existing,
        'userId': userId,
        'bookingUpdates': bookingUpdates,
        'reminders': reminders,
        'cancellations': cancellations,
        'updatedAt': DateTime.now().toUtc(),
      });
      return;
    }
    await _firestore.collection('user_notification_settings').doc(userId).set({
      'userId': userId,
      'bookingUpdates': bookingUpdates,
      'reminders': reminders,
      'cancellations': cancellations,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<Map<String, dynamic>> watchNotificationSettings(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const <String, dynamic>{});
    }
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<Map<String, dynamic>>(
        load: () => getNotificationSettings(normalized),
        signature: (value) => jsonEncode(value),
      );
    }
    return _firestore
        .collection('user_notification_settings')
        .doc(normalized)
        .snapshots()
        .map((doc) => doc.data() ?? const <String, dynamic>{});
  }

  Map<String, dynamic> _notificationPayload({
    required String userId,
    required String institutionId,
    required String type,
    required String title,
    required String body,
    String? relatedAppointmentId,
    String? relatedId,
    String? route,
    String priority = 'normal',
    bool actionRequired = false,
  }) {
    return <String, dynamic>{
      'userId': userId,
      'institutionId': institutionId,
      'type': type,
      'title': title,
      'body': body,
      'priority': priority,
      'actionRequired': actionRequired,
      'route': route,
      'isRead': false,
      'isPinned': false,
      'isArchived': false,
      'relatedAppointmentId': relatedAppointmentId,
      'relatedId': relatedId,
      'createdAt': kUseWindowsRestAuth
          ? DateTime.now().toUtc()
          : FieldValue.serverTimestamp(),
      'updatedAt': kUseWindowsRestAuth
          ? DateTime.now().toUtc()
          : FieldValue.serverTimestamp(),
    };
  }

  Future<void> _createNotifications(List<Map<String, dynamic>> payloads) async {
    if (payloads.isEmpty) {
      return;
    }
    if (kUseWindowsRestAuth) {
      final now = DateTime.now().toUtc();
      for (var index = 0; index < payloads.length; index++) {
        final payload = payloads[index];
        await _windowsRest.setDocument(
          'notifications/notif_${now.microsecondsSinceEpoch}_$index',
          <String, dynamic>{
            ...payload,
            'createdAt': payload['createdAt'] is DateTime
                ? payload['createdAt']
                : now,
            'updatedAt': payload['updatedAt'] is DateTime
                ? payload['updatedAt']
                : now,
          },
        );
      }
      unawaited(_dispatchPushNotifications(payloads));
      return;
    }
    final batch = _firestore.batch();
    for (final payload in payloads) {
      batch.set(_firestore.collection('notifications').doc(), payload);
    }
    await batch.commit();
    unawaited(_dispatchPushNotifications(payloads));
  }

  Future<void> _dispatchPushNotifications(
    List<Map<String, dynamic>> payloads,
  ) async {
    if (_pushDispatchEndpoint.isEmpty) {
      return;
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return;
    }

    try {
      final idToken = await _auth.getIdToken();
      final uri = Uri.tryParse(_pushDispatchEndpoint);
      if (uri == null) {
        return;
      }

      final notifications = payloads
          .map(
            (payload) => <String, dynamic>{
              'userId': payload['userId'],
              'institutionId': payload['institutionId'],
              'title': payload['title'],
              'body': payload['body'],
              'type': payload['type'],
              'relatedAppointmentId': payload['relatedAppointmentId'],
              'relatedId': payload['relatedId'],
              'route': payload['route'],
              'priority': payload['priority'],
              'actionRequired': payload['actionRequired'],
            },
          )
          .toList(growable: false);

      await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(<String, dynamic>{'notifications': notifications}),
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      // Ignore push dispatch timeout so primary app flow remains responsive.
    } catch (_) {
      // Ignore push dispatch failures; in-app notifications are still written.
    }
  }

  String _counselorProfileSignature(CounselorProfile? profile) {
    if (profile == null) {
      return 'null';
    }
    return '${profile.id}|${profile.institutionId}|${profile.displayName}|${profile.title}|${profile.specialization}|${profile.sessionMode}|${profile.timezone}|${profile.yearsExperience}|${profile.ratingAverage}|${profile.ratingCount}|${profile.isActive}|${profile.languages.join(',')}';
  }

  String _counselorProfilesSignature(List<CounselorProfile> profiles) =>
      profiles.map(_counselorProfileSignature).join(';');

  String _availabilitySlotsSignature(List<AvailabilitySlot> slots) => slots
      .map(
        (slot) =>
            '${slot.id}|${slot.counselorId}|${slot.status.name}|${slot.startAt.toIso8601String()}|${slot.endAt.toIso8601String()}|${slot.bookedBy ?? ''}|${slot.appointmentId ?? ''}',
      )
      .join(';');

  String _appointmentsSignature(
    List<AppointmentRecord> appointments,
  ) => appointments
      .map(
        (appointment) =>
            '${appointment.id}|${appointment.status.name}|${appointment.startAt.toIso8601String()}|${appointment.endAt.toIso8601String()}|${appointment.slotId}|${appointment.counselorId}|${appointment.studentId}|${appointment.attendanceStatus ?? ''}|${appointment.rescheduledToAppointmentId ?? ''}|${appointment.rescheduledFromAppointmentId ?? ''}',
      )
      .join(';');

  String _publicRatingsSignature(List<CounselorPublicRating> ratings) => ratings
      .map(
        (rating) =>
            '${rating.id}|${rating.counselorId}|${rating.rating}|${rating.createdAt.toIso8601String()}',
      )
      .join(';');

  String _careGoalsSignature(List<CareGoal> goals) => goals
      .map(
        (goal) =>
            '${goal.id}|${goal.status}|${goal.title}|${goal.createdAt.toIso8601String()}|${goal.updatedAt?.toIso8601String() ?? ''}|${goal.completedAt?.toIso8601String() ?? ''}',
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
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
