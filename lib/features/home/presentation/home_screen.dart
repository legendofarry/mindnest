import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return MindNestShell(
      maxWidth: 760,
      appBar: AppBar(
        title: const Text('MindNest Dashboard'),
        actions: [
          TextButton(
            onPressed: () => confirmAndLogout(context: context, ref: ref),
            child: const Text('Logout'),
          ),
        ],
      ),
      child: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Profile not found.'),
              ),
            );
          }

          final hasInstitution = (profile.institutionId ?? '').isNotEmpty;
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
                        'Welcome, ${profile.name.isNotEmpty ? profile.name : profile.email}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text('Role: ${profile.role.label}'),
                      const SizedBox(height: 6),
                      Text(
                        hasInstitution
                            ? 'Institution: ${profile.institutionName ?? profile.institutionId}'
                            : 'Institution: Not joined',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (profile.role == UserRole.student ||
                  profile.role == UserRole.staff ||
                  profile.role == UserRole.individual)
                GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Counseling',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: hasInstitution
                              ? () => context.go(AppRoute.counselorDirectory)
                              : null,
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('Find counselors'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: hasInstitution
                              ? () => context.go(AppRoute.studentAppointments)
                              : null,
                          icon: const Icon(Icons.event_note_rounded),
                          label: const Text('My appointments'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Institution Access',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: hasInstitution
                            ? null
                            : () => context.go(AppRoute.joinInstitution),
                        child: const Text('Join institution'),
                      ),
                      const SizedBox(height: 8),
                      if (profile.role == UserRole.institutionAdmin)
                        OutlinedButton(
                          onPressed: () =>
                              context.go(AppRoute.institutionAdmin),
                          child: const Text('Open institution admin'),
                        ),
                      if (hasInstitution)
                        OutlinedButton(
                          onPressed: () async {
                            await ref
                                .read(institutionRepositoryProvider)
                                .leaveInstitution();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('You left the institution.'),
                                ),
                              );
                            }
                          },
                          child: const Text('Leave institution'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(error.toString()),
          ),
        ),
      ),
    );
  }
}
