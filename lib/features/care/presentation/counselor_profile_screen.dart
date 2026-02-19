import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';

class CounselorProfileScreen extends ConsumerWidget {
  const CounselorProfileScreen({super.key, required this.counselorId});

  final String counselorId;

  String _formatSlot(DateTime value) {
    final date = value.toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _bookSlot({
    required BuildContext context,
    required WidgetRef ref,
    required CounselorProfile counselor,
    required AvailabilitySlot slot,
    required UserProfile currentProfile,
  }) async {
    final institutionId = currentProfile.institutionId ?? '';
    if (institutionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join an institution first.')),
      );
      return;
    }
    try {
      await ref
          .read(careRepositoryProvider)
          .bookCounselorSlot(
            institutionId: institutionId,
            counselor: counselor,
            slot: slot,
            currentProfile: currentProfile,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session booked successfully.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        title: const Text('Counselor Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      child: StreamBuilder<CounselorProfile?>(
        stream: ref
            .read(careRepositoryProvider)
            .watchCounselorProfile(counselorId),
        builder: (context, counselorSnapshot) {
          final counselor = counselorSnapshot.data;
          if (counselor == null) {
            return const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Counselor profile not found.'),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        counselor.displayName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text('${counselor.title} · ${counselor.specialization}'),
                      const SizedBox(height: 4),
                      Text(
                        '${counselor.yearsExperience} years experience · ${counselor.sessionMode}',
                      ),
                      const SizedBox(height: 4),
                      Text('Timezone: ${counselor.timezone}'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFF59E0B),
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${counselor.ratingAverage.toStringAsFixed(1)} (${counselor.ratingCount} ratings)',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      if (counselor.languages.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Languages: ${counselor.languages.join(', ')}'),
                      ],
                      if (counselor.bio.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(counselor.bio),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Public Availability',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (institutionId.isEmpty)
                const GlassCard(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Join an institution to view and book public schedules.',
                    ),
                  ),
                )
              else
                StreamBuilder<List<AvailabilitySlot>>(
                  stream: ref
                      .read(careRepositoryProvider)
                      .watchCounselorPublicAvailability(
                        institutionId: institutionId,
                        counselorId: counselor.id,
                      ),
                  builder: (context, availabilitySnapshot) {
                    final slots = availabilitySnapshot.data ?? const [];
                    if (availabilitySnapshot.connectionState ==
                            ConnectionState.waiting &&
                        slots.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (slots.isEmpty) {
                      return const GlassCard(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No public available slots yet.'),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: slots
                          .take(30)
                          .map(
                            (slot) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: GlassCard(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _formatSlot(slot.startAt),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Ends: ${_formatSlot(slot.endAt)}',
                                              style: const TextStyle(
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      ElevatedButton(
                                        onPressed: profile == null
                                            ? null
                                            : () => _bookSlot(
                                                context: context,
                                                ref: ref,
                                                counselor: counselor,
                                                slot: slot,
                                                currentProfile: profile,
                                              ),
                                        child: const Text('Book'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
