import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.institutionId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.isPinned,
    required this.isArchived,
    this.priority = 'normal',
    this.actionRequired = false,
    this.route,
    this.pinnedAt,
    this.archivedAt,
    this.resolvedAt,
    this.relatedAppointmentId,
    this.relatedId,
  });

  final String id;
  final String userId;
  final String institutionId;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final bool isPinned;
  final bool isArchived;
  final String priority;
  final bool actionRequired;
  final String? route;
  final DateTime? pinnedAt;
  final DateTime? archivedAt;
  final DateTime? resolvedAt;
  final String? relatedAppointmentId;
  final String? relatedId;

  AppNotification copyWith({
    String? id,
    String? userId,
    String? institutionId,
    String? type,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? isRead,
    bool? isPinned,
    bool? isArchived,
    String? priority,
    bool? actionRequired,
    String? route,
    DateTime? pinnedAt,
    DateTime? archivedAt,
    DateTime? resolvedAt,
    String? relatedAppointmentId,
    String? relatedId,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      institutionId: institutionId ?? this.institutionId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      priority: priority ?? this.priority,
      actionRequired: actionRequired ?? this.actionRequired,
      route: route ?? this.route,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      relatedAppointmentId:
          relatedAppointmentId ?? this.relatedAppointmentId,
      relatedId: relatedId ?? this.relatedId,
    );
  }

  factory AppNotification.fromMap(String id, Map<String, dynamic> data) {
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

    return AppNotification(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      institutionId: (data['institutionId'] as String?) ?? '',
      type: (data['type'] as String?) ?? 'general',
      title: (data['title'] as String?) ?? 'Notification',
      body: (data['body'] as String?) ?? '',
      createdAt: parseDate(data['createdAt']),
      isRead: (data['isRead'] as bool?) ?? false,
      isPinned: (data['isPinned'] as bool?) ?? false,
      isArchived: (data['isArchived'] as bool?) ?? false,
      priority: (data['priority'] as String?) ?? 'normal',
      actionRequired: (data['actionRequired'] as bool?) ?? false,
      route: data['route'] as String?,
      pinnedAt: parseOptionalDate(data['pinnedAt']),
      archivedAt: parseOptionalDate(data['archivedAt']),
      resolvedAt: parseOptionalDate(data['resolvedAt']),
      relatedAppointmentId: data['relatedAppointmentId'] as String?,
      relatedId: data['relatedId'] as String?,
    );
  }
}
