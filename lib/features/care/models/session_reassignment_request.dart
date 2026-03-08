import 'package:cloud_firestore/cloud_firestore.dart';

enum SessionReassignmentStatus {
  openForResponses,
  awaitingPatientChoice,
  patientSelected,
  transferred,
  declined,
  expired,
  cancelled,
}

extension SessionReassignmentStatusX on SessionReassignmentStatus {
  String get wireName {
    switch (this) {
      case SessionReassignmentStatus.openForResponses:
        return 'open_for_responses';
      case SessionReassignmentStatus.awaitingPatientChoice:
        return 'awaiting_patient_choice';
      case SessionReassignmentStatus.patientSelected:
        return 'patient_selected';
      case SessionReassignmentStatus.transferred:
        return 'transferred';
      case SessionReassignmentStatus.declined:
        return 'declined';
      case SessionReassignmentStatus.expired:
        return 'expired';
      case SessionReassignmentStatus.cancelled:
        return 'cancelled';
    }
  }

  static SessionReassignmentStatus fromWireName(String? raw) {
    for (final value in SessionReassignmentStatus.values) {
      if (value.wireName == raw) {
        return value;
      }
    }
    return SessionReassignmentStatus.openForResponses;
  }
}

class ReassignmentInterestedCounselor {
  const ReassignmentInterestedCounselor({
    required this.counselorId,
    required this.displayName,
    required this.specialization,
    required this.languages,
    required this.sessionMode,
    required this.respondedAt,
    required this.isActive,
  });

  final String counselorId;
  final String displayName;
  final String specialization;
  final List<String> languages;
  final String sessionMode;
  final DateTime respondedAt;
  final bool isActive;

  factory ReassignmentInterestedCounselor.fromMap(Map<String, dynamic> data) {
    final languages = <String>[];
    final raw = data['languages'];
    if (raw is List) {
      for (final item in raw) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          languages.add(text);
        }
      }
    }
    final respondedAtRaw = data['respondedAt'];
    DateTime respondedAt;
    if (respondedAtRaw is Timestamp) {
      respondedAt = respondedAtRaw.toDate();
    } else if (respondedAtRaw is DateTime) {
      respondedAt = respondedAtRaw;
    } else {
      respondedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return ReassignmentInterestedCounselor(
      counselorId: (data['counselorId'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? 'Counselor',
      specialization: (data['specialization'] as String?) ?? '',
      languages: languages,
      sessionMode: (data['sessionMode'] as String?) ?? '--',
      respondedAt: respondedAt,
      isActive: (data['isActive'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'counselorId': counselorId,
      'displayName': displayName,
      'specialization': specialization,
      'languages': languages,
      'sessionMode': sessionMode,
      'respondedAt': Timestamp.fromDate(respondedAt.toUtc()),
      'isActive': isActive,
    };
  }
}

class SessionReassignmentRequest {
  const SessionReassignmentRequest({
    required this.id,
    required this.appointmentId,
    required this.institutionId,
    required this.originalCounselorId,
    required this.studentId,
    required this.studentName,
    required this.requiredSpecialization,
    required this.sessionMode,
    required this.sessionStartAt,
    required this.sessionEndAt,
    required this.status,
    required this.maxInterestedCounselors,
    required this.responseDeadlineAt,
    required this.createdAt,
    required this.updatedAt,
    this.choiceDeadlineAt,
    this.originalCounselorRecommendationId,
    this.selectedCounselorId,
    this.selectedCounselorName,
    this.interestedCounselors = const <ReassignmentInterestedCounselor>[],
    this.patientSelectedAt,
    this.confirmedAt,
    this.cancelledAt,
    this.expiredAt,
    this.transferredAppointmentId,
  });

  final String id;
  final String appointmentId;
  final String institutionId;
  final String originalCounselorId;
  final String studentId;
  final String studentName;
  final String requiredSpecialization;
  final String sessionMode;
  final DateTime sessionStartAt;
  final DateTime sessionEndAt;
  final SessionReassignmentStatus status;
  final int maxInterestedCounselors;
  final DateTime responseDeadlineAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? choiceDeadlineAt;
  final String? originalCounselorRecommendationId;
  final String? selectedCounselorId;
  final String? selectedCounselorName;
  final List<ReassignmentInterestedCounselor> interestedCounselors;
  final DateTime? patientSelectedAt;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final DateTime? expiredAt;
  final String? transferredAppointmentId;

  bool get isOpenForResponses =>
      status == SessionReassignmentStatus.openForResponses;
  bool get isAwaitingPatientChoice =>
      status == SessionReassignmentStatus.awaitingPatientChoice ||
      status == SessionReassignmentStatus.patientSelected;

  factory SessionReassignmentRequest.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    DateTime? parseOptionalDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return null;
    }

    final interested = <ReassignmentInterestedCounselor>[];
    final interestedRaw = data['interestedCounselors'];
    if (interestedRaw is List) {
      for (final item in interestedRaw) {
        if (item is Map<String, dynamic>) {
          interested.add(ReassignmentInterestedCounselor.fromMap(item));
        } else if (item is Map) {
          interested.add(
            ReassignmentInterestedCounselor.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }
    }

    return SessionReassignmentRequest(
      id: id,
      appointmentId: (data['appointmentId'] as String?) ?? '',
      institutionId: (data['institutionId'] as String?) ?? '',
      originalCounselorId: (data['originalCounselorId'] as String?) ?? '',
      studentId: (data['studentId'] as String?) ?? '',
      studentName: (data['studentName'] as String?) ?? 'Student',
      requiredSpecialization: (data['requiredSpecialization'] as String?) ?? '',
      sessionMode: (data['sessionMode'] as String?) ?? '--',
      sessionStartAt: parseDate(data['sessionStartAt']),
      sessionEndAt: parseDate(data['sessionEndAt']),
      status: SessionReassignmentStatusX.fromWireName(
        data['status'] as String?,
      ),
      maxInterestedCounselors:
          (data['maxInterestedCounselors'] as num?)?.toInt() ?? 5,
      responseDeadlineAt: parseDate(data['responseDeadlineAt']),
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
      choiceDeadlineAt: parseOptionalDate(data['choiceDeadlineAt']),
      originalCounselorRecommendationId:
          data['originalCounselorRecommendationId'] as String?,
      selectedCounselorId: data['selectedCounselorId'] as String?,
      selectedCounselorName: data['selectedCounselorName'] as String?,
      interestedCounselors: interested,
      patientSelectedAt: parseOptionalDate(data['patientSelectedAt']),
      confirmedAt: parseOptionalDate(data['confirmedAt']),
      cancelledAt: parseOptionalDate(data['cancelledAt']),
      expiredAt: parseOptionalDate(data['expiredAt']),
      transferredAppointmentId: data['transferredAppointmentId'] as String?,
    );
  }
}
