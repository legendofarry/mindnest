import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/back_to_home_button.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/live/data/live_providers.dart';
import 'package:mindnest/features/live/models/live_participant.dart';
import 'package:mindnest/features/live/models/live_session.dart';

class LiveHubScreen extends ConsumerStatefulWidget {
  const LiveHubScreen({super.key, this.autoOpenCreate = false});

  final bool autoOpenCreate;

  @override
  ConsumerState<LiveHubScreen> createState() => _LiveHubScreenState();
}

class _LiveHubScreenState extends ConsumerState<LiveHubScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _allowStudents = true;
  bool _allowStaff = true;
  bool _allowCounselors = true;
  bool _creating = false;
  bool _autoCreateHandled = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool _canUseLive(UserProfile profile) {
    return profile.role == UserRole.student ||
        profile.role == UserRole.staff ||
        profile.role == UserRole.counselor;
  }

  String _statusLabel(LiveSessionStatus status) {
    switch (status) {
      case LiveSessionStatus.live:
        return 'Live';
      case LiveSessionStatus.paused:
        return 'Paused';
      case LiveSessionStatus.ended:
        return 'Ended';
    }
  }

  Color _statusColor(LiveSessionStatus status) {
    switch (status) {
      case LiveSessionStatus.live:
        return const Color(0xFF16A34A);
      case LiveSessionStatus.paused:
        return const Color(0xFFD97706);
      case LiveSessionStatus.ended:
        return const Color(0xFF64748B);
    }
  }

  Future<void> _openCreateLiveDialog(UserProfile profile) async {
    _titleController.clear();
    _descriptionController.clear();
    setState(() {
      _allowStudents = true;
      _allowStaff = true;
      _allowCounselors = true;
      _creating = false;
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              final title = _titleController.text.trim();
              if (title.length < 4) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('Title must be at least 4 characters.'),
                  ),
                );
                return;
              }
              final allowedRoles = <UserRole>[
                if (_allowStudents) UserRole.student,
                if (_allowStaff) UserRole.staff,
                if (_allowCounselors) UserRole.counselor,
              ];
              if (allowedRoles.isEmpty) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('Select at least one allowed role.'),
                  ),
                );
                return;
              }
              setModalState(() => _creating = true);
              try {
                final live = await ref
                    .read(liveRepositoryProvider)
                    .createLiveSession(
                      title: title,
                      description: _descriptionController.text,
                      allowedRoles: allowedRoles,
                    );
                if (!sheetContext.mounted) {
                  return;
                }
                Navigator.of(sheetContext).pop();
                if (!mounted) {
                  return;
                }
                this.context.push('${AppRoute.liveRoom}?sessionId=${live.id}');
              } catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      error.toString().replaceFirst('Exception: ', ''),
                    ),
                  ),
                );
              } finally {
                if (sheetContext.mounted) {
                  setModalState(() => _creating = false);
                }
              }
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Start Live Audio',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      maxLength: 70,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.mic_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 220,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Role Access',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF334155),
                      ),
                    ),
                    CheckboxListTile(
                      value: _allowStudents,
                      onChanged: (value) =>
                          setModalState(() => _allowStudents = value ?? false),
                      title: const Text('Allow Students'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: _allowStaff,
                      onChanged: (value) =>
                          setModalState(() => _allowStaff = value ?? false),
                      title: const Text('Allow Staff'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: _allowCounselors,
                      onChanged: (value) => setModalState(
                        () => _allowCounselors = value ?? false,
                      ),
                      title: const Text('Allow Counselors'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 6),
                    ElevatedButton.icon(
                      onPressed: _creating ? null : submit,
                      icon: const Icon(Icons.play_circle_fill_rounded),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      label: Text(
                        _creating ? 'Creating...' : 'Start Live Session',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final institutionId = profile?.institutionId ?? '';
    final canUse = profile != null && _canUseLive(profile);

    if (widget.autoOpenCreate && !_autoCreateHandled && profile != null) {
      _autoCreateHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (!canUse || institutionId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You cannot start a live session from this account right now.',
              ),
            ),
          );
          return;
        }
        _openCreateLiveDialog(profile);
      });
    }

    return MindNestShell(
      maxWidth: 980,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Live Audio Hub'),
        leading: const BackToHomeButton(),
        actions: [
          if (canUse && institutionId.isNotEmpty)
            TextButton.icon(
              onPressed: () => _openCreateLiveDialog(profile),
              icon: const Icon(Icons.podcasts_rounded),
              label: const Text('Go Live'),
            ),
        ],
      ),
      child: profile == null
          ? const Center(child: CircularProgressIndicator())
          : !canUse
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Live Audio Hub is available for students, staff, and counselors.',
                ),
              ),
            )
          : institutionId.isEmpty
          ? const GlassCard(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Join an institution to access live sessions.'),
              ),
            )
          : StreamBuilder<List<LiveSession>>(
              stream: ref
                  .read(liveRepositoryProvider)
                  .watchInstitutionLives(institutionId: institutionId),
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? const <LiveSession>[];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    sessions.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const GlassCard(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Institution-only live audio sessions. Join to listen, request mic access, comment, and react in real time.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (sessions.isEmpty)
                      const GlassCard(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'No active lives right now. Start one from "Go Live".',
                          ),
                        ),
                      )
                    else
                      ...sessions.map((session) {
                        final statusColor = _statusColor(session.status);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => context.push(
                                '${AppRoute.liveRoom}?sessionId=${session.id}',
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                              alpha: 0.14,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            _statusLabel(session.status),
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Color(0xFF64748B),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      session.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    if (session.description.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        session.description,
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Text(
                                      'Host: ${session.hostName} (${session.hostRole.label})',
                                      style: const TextStyle(
                                        color: Color(0xFF334155),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        StreamBuilder<List<LiveParticipant>>(
                                          stream: ref
                                              .read(liveRepositoryProvider)
                                              .watchParticipants(session.id),
                                          builder: (context, participantSnap) {
                                            final listeners =
                                                participantSnap.data?.length ??
                                                0;
                                            return _MetricChip(
                                              icon: Icons.headphones_rounded,
                                              text: '$listeners listening',
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        _MetricChip(
                                          icon: Icons.favorite_rounded,
                                          text: '${session.likeCount} likes',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475569)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
