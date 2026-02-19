import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/data/care_providers.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';

class CounselorDirectoryScreen extends ConsumerStatefulWidget {
  const CounselorDirectoryScreen({super.key});

  @override
  ConsumerState<CounselorDirectoryScreen> createState() =>
      _CounselorDirectoryScreenState();
}

class _CounselorDirectoryScreenState
    extends ConsumerState<CounselorDirectoryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        title: const Text('Counselor Directory'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Find a Counselor',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search by name, specialization, language...',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (institutionId.isEmpty)
            const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Join an institution first to view counselors.'),
              ),
            )
          else
            StreamBuilder<List<CounselorProfile>>(
              stream: ref
                  .read(careRepositoryProvider)
                  .watchCounselors(institutionId: institutionId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        snapshot.error.toString().replaceFirst(
                          'Exception: ',
                          '',
                        ),
                      ),
                    ),
                  );
                }
                final counselors = snapshot.data ?? const [];
                final query = _searchController.text.trim().toLowerCase();
                final filtered = counselors
                    .where((profile) {
                      if (query.isEmpty) {
                        return true;
                      }
                      final target =
                          '${profile.displayName} ${profile.specialization} ${profile.languages.join(' ')}'
                              .toLowerCase();
                      return target.contains(query);
                    })
                    .toList(growable: false);

                if (snapshot.connectionState == ConnectionState.waiting &&
                    counselors.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (filtered.isEmpty) {
                  final hasSearch = query.isNotEmpty;
                  if (hasSearch) {
                    return const GlassCard(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('No counselors match your search.'),
                      ),
                    );
                  }
                  return _PendingCounselorFallback(
                    institutionId: institutionId,
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: filtered
                      .map(
                        (counselor) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CounselorCard(
                            counselor: counselor,
                            onTap: () {
                              context.push(
                                '${AppRoute.counselorProfile}?counselorId=${counselor.id}',
                              );
                            },
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CounselorCard extends StatelessWidget {
  const _CounselorCard({required this.counselor, required this.onTap});

  final CounselorProfile counselor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.health_and_safety_rounded,
                    color: Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        counselor.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${counselor.title} · ${counselor.specialization}',
                        style: const TextStyle(color: Color(0xFF5E728D)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${counselor.yearsExperience} yrs · ${counselor.sessionMode}',
                        style: const TextStyle(color: Color(0xFF5E728D)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFF59E0B),
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          counselor.ratingAverage.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    Text(
                      '${counselor.ratingCount} ratings',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingCounselorFallback extends ConsumerWidget {
  const _PendingCounselorFallback({required this.institutionId});

  final String institutionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firestore = ref.watch(firestoreProvider);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('institution_members')
          .where('institutionId', isEqualTo: institutionId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                snapshot.error.toString().replaceFirst('Exception: ', ''),
              ),
            ),
          );
        }

        final counselorMembers = (snapshot.data?.docs ?? const [])
            .where(
              (doc) =>
                  (doc.data()['role'] as String?) == UserRole.counselor.name,
            )
            .toList(growable: false);

        if (counselorMembers.isEmpty) {
          return const GlassCard(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'No counselors are available yet in your institution.',
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: counselorMembers
              .map((doc) {
                final data = doc.data();
                final userId = (data['userId'] as String?) ?? doc.id;
                final userName =
                    (data['userName'] as String?) ??
                    (data['name'] as String?) ??
                    'Counselor ${userId.length > 6 ? userId.substring(0, 6) : userId}';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          context.push(
                            '${AppRoute.counselorProfile}?counselorId=$userId',
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F6FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.health_and_safety_rounded,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      userName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Profile setup in progress',
                                      style: TextStyle(
                                        color: Color(0xFF5E728D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }
}
