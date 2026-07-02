import 'package:cloud_firestore/cloud_firestore.dart';

enum AvailabilitySlotStatus { available, booked, blocked }

class AvailabilitySlot {
  const AvailabilitySlot({
    required this.id,
    required this.institutionId,
    required this.counselorId,
    required this.startAt,
    required this.endAt,
    required this.status,
    this.bookedBy,
    this.appointmentId,
    this.sourceSlotId,
    this.generated = false,
  });

  factory AvailabilitySlot.generated({
    required AvailabilitySlot source,
    required DateTime startAt,
    required DateTime endAt,
  }) {
    return AvailabilitySlot(
      id: '${source.id}_${startAt.toUtc().millisecondsSinceEpoch}_${endAt.toUtc().millisecondsSinceEpoch}',
      institutionId: source.institutionId,
      counselorId: source.counselorId,
      startAt: startAt.toUtc(),
      endAt: endAt.toUtc(),
      status: AvailabilitySlotStatus.available,
      sourceSlotId: source.sourceSlotId ?? source.id,
      generated: true,
    );
  }

  final String id;
  final String institutionId;
  final String counselorId;
  final DateTime startAt;
  final DateTime endAt;
  final AvailabilitySlotStatus status;
  final String? bookedBy;
  final String? appointmentId;
  final String? sourceSlotId;
  final bool generated;

  factory AvailabilitySlot.fromMap(String id, Map<String, dynamic> data) {
    final startRaw = data['startAt'];
    final endRaw = data['endAt'];

    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final statusRaw = (data['status'] as String?) ?? 'available';
    final status = AvailabilitySlotStatus.values.firstWhere(
      (value) => value.name == statusRaw,
      orElse: () => AvailabilitySlotStatus.available,
    );

    return AvailabilitySlot(
      id: id,
      institutionId: (data['institutionId'] as String?) ?? '',
      counselorId: (data['counselorId'] as String?) ?? '',
      startAt: parseDate(startRaw),
      endAt: parseDate(endRaw),
      status: status,
      bookedBy: data['bookedBy'] as String?,
      appointmentId: data['appointmentId'] as String?,
      sourceSlotId: data['sourceSlotId'] as String?,
      generated: (data['generated'] as bool?) ?? false,
    );
  }
}
