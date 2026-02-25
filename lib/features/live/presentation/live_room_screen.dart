import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/live/data/live_providers.dart';
import 'package:mindnest/features/live/models/live_comment.dart';
import 'package:mindnest/features/live/models/live_mic_request.dart';
import 'package:mindnest/features/live/models/live_participant.dart';
import 'package:mindnest/features/live/models/live_reaction_event.dart';
import 'package:mindnest/features/live/models/live_session.dart';

class LiveRoomScreen extends ConsumerStatefulWidget {
  const LiveRoomScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends ConsumerState<LiveRoomScreen> {
  final _commentController = TextEditingController();
  final _rand = Random();

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  StreamSubscription<LiveParticipant?>? _myParticipantSub;
  Timer? _presenceTimer;

  bool _joining = true;
  bool _leaving = false;
  bool _audioConnected = false;
  bool _canPublishWithToken = false;
  bool _refreshingAudioGrant = false;
  bool _micEnabled = false;
  bool _handledLiveEnded = false;
  String? _joinError;

  LiveParticipant? _myParticipant;
  final Set<String> _seenReactions = <String>{};
  final List<_Burst> _bursts = <_Burst>[];

  bool get _isHost => _myParticipant?.kind == LiveParticipantKind.host;
  bool get _canSpeak =>
      _myParticipant?.kind == LiveParticipantKind.host ||
      (_myParticipant?.kind == LiveParticipantKind.guest &&
          _myParticipant?.canSpeak == true &&
          _myParticipant?.mutedByHost != true);

  @override
  void initState() {
    super.initState();
    _join();
    _myParticipantSub = ref
        .read(liveRepositoryProvider)
        .watchMyParticipant(widget.sessionId)
        .listen((participant) async {
          if (!mounted || participant == null) {
            return;
          }
          setState(() => _myParticipant = participant);
          if (participant.canSpeak &&
              !participant.mutedByHost &&
              !_canPublishWithToken &&
              _audioConnected) {
            await _refreshAudioGrant();
          }
          if (participant.removed) {
            await _setMic(false, syncDb: false);
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You were removed from this live.')),
            );
            await _leave(goHome: true);
          } else if (participant.mutedByHost && _micEnabled) {
            await _setMic(false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Host muted your microphone.')),
              );
            }
          }
        });
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _myParticipantSub?.cancel();
    _roomListener?.dispose();
    _room?.disconnect();
    _room?.dispose();
    _commentController.dispose();
    super.dispose();
  }

  lk.EventsListener<lk.RoomEvent> _attachRoomListener(lk.Room room) {
    final listener = room.createListener();
    listener.on<lk.RoomDisconnectedEvent>((_) {
      if (!mounted || _leaving) {
        return;
      }
      setState(() => _audioConnected = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Audio disconnected.')));
    });
    return listener;
  }

  Future<void> _refreshAudioGrant() async {
    if (_refreshingAudioGrant || _leaving) {
      return;
    }
    _refreshingAudioGrant = true;
    try {
      final repo = ref.read(liveRepositoryProvider);
      final creds = await repo.createLiveKitJoinCredentials(
        sessionId: widget.sessionId,
      );

      final shouldEnableMic = _micEnabled && creds.canPublishAudio;

      _roomListener?.dispose();
      await _room?.disconnect();
      _room?.dispose();

      final room = lk.Room(
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );
      final listener = _attachRoomListener(room);
      await room.connect(
        creds.serverUrl,
        creds.token,
        connectOptions: const lk.ConnectOptions(autoSubscribe: true),
      );

      _room = room;
      _roomListener = listener;
      _audioConnected = true;
      _canPublishWithToken = creds.canPublishAudio;
      _micEnabled = shouldEnableMic;
      await _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
      await repo.setMyMicEnabled(
        sessionId: widget.sessionId,
        enabled: _micEnabled,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _audioConnected = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to refresh audio permissions: '
            '${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      _refreshingAudioGrant = false;
    }
  }

  Future<void> _join() async {
    try {
      final repo = ref.read(liveRepositoryProvider);
      final session = await repo.joinLiveSession(widget.sessionId);
      final creds = await repo.createLiveKitJoinCredentials(
        sessionId: widget.sessionId,
      );

      final room = lk.Room(
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );
      final listener = _attachRoomListener(room);

      await room.connect(
        creds.serverUrl,
        creds.token,
        connectOptions: const lk.ConnectOptions(autoSubscribe: true),
      );

      _room = room;
      _roomListener = listener;
      _audioConnected = true;
      _canPublishWithToken = creds.canPublishAudio;
      if (session.createdBy ==
          ref.read(firebaseAuthProvider).currentUser?.uid) {
        await _setMic(_canPublishWithToken);
      } else {
        await _setMic(false);
      }
      _presenceTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        ref.read(liveRepositoryProvider).touchPresence(widget.sessionId);
      });
      if (mounted) {
        setState(() {
          _joining = false;
          _joinError = null;
        });
      }
    } catch (error) {
      _roomListener?.dispose();
      _room?.dispose();
      _room = null;
      _audioConnected = false;
      _canPublishWithToken = false;
      if (mounted) {
        setState(() {
          _joining = false;
          _joinError = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _setMic(bool enabled, {bool syncDb = true}) async {
    try {
      if (enabled && !_audioConnected) {
        throw Exception('Audio is not connected yet.');
      }
      if (enabled && !_canPublishWithToken) {
        throw Exception(
          'Mic access is not granted yet. Request mic and wait for host approval.',
        );
      }
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
      _micEnabled = enabled;
      if (syncDb) {
        await ref
            .read(liveRepositoryProvider)
            .setMyMicEnabled(sessionId: widget.sessionId, enabled: enabled);
      }
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _leave({bool goHome = false}) async {
    if (_leaving) {
      return;
    }
    _leaving = true;
    _presenceTimer?.cancel();
    try {
      await _setMic(false, syncDb: false);
      await _room?.disconnect();
      await ref.read(liveRepositoryProvider).leaveLiveSession(widget.sessionId);
    } catch (_) {
      // Ignore leave failures.
    } finally {
      _roomListener?.dispose();
      _room?.dispose();
      _room = null;
      _audioConnected = false;
      _canPublishWithToken = false;
      _leaving = false;
      if (mounted && goHome) {
        context.go(AppRoute.home);
      }
    }
  }

  Future<void> _handleHostEndedLive() async {
    if (_handledLiveEnded || _leaving || !mounted) {
      return;
    }
    _handledLiveEnded = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Live Ended'),
        content: const Text('Host has ended this live session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }
    await _leave(goHome: true);
  }

  void _syncBursts(List<LiveReactionEvent> reactions) {
    for (final reaction in reactions.take(12)) {
      if (_seenReactions.add(reaction.id)) {
        _bursts.add(
          _Burst(
            id: reaction.id,
            emoji: reaction.emoji,
            right: 20 + _rand.nextDouble() * 120,
          ),
        );
      }
    }
  }

  Future<void> _onCommentTap(LiveComment comment) async {
    final reasonController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Comment Actions',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.person_search_rounded),
                  title: const Text('View Profile'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await ref
                        .read(liveRepositoryProvider)
                        .fetchMemberPublicProfile(
                          sessionId: widget.sessionId,
                          userId: comment.userId,
                        )
                        .then((profile) {
                          if (!mounted) {
                            return;
                          }
                          showDialog<void>(
                            context: this.context,
                            builder: (context) => AlertDialog(
                              title: const Text('Member Profile'),
                              content: Text(
                                profile == null
                                    ? 'Profile unavailable.'
                                    : '${profile.displayName}\n${profile.role}\n${profile.email}',
                              ),
                            ),
                          );
                        });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flag_rounded),
                  title: const Text('Report Comment'),
                  onTap: () async {
                    final reason = await showDialog<String>(
                      context: this.context,
                      builder: (context) => AlertDialog(
                        title: const Text('Report Comment'),
                        content: TextField(
                          controller: reasonController,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(
                              context,
                            ).pop(reasonController.text.trim()),
                            child: const Text('Report'),
                          ),
                        ],
                      ),
                    );
                    if (reason == null || reason.isEmpty) {
                      return;
                    }
                    await ref
                        .read(liveRepositoryProvider)
                        .reportComment(
                          sessionId: widget.sessionId,
                          comment: comment,
                          reason: reason,
                        );
                    if (mounted) {
                      Navigator.of(this.context).pop();
                    }
                  },
                ),
                if (_isHost && comment.userId != _myParticipant?.userId)
                  ListTile(
                    leading: const Icon(Icons.volume_off_rounded),
                    title: const Text('Mute User'),
                    onTap: () async {
                      await ref
                          .read(liveRepositoryProvider)
                          .muteParticipant(
                            sessionId: widget.sessionId,
                            targetUserId: comment.userId,
                            muted: true,
                          );
                      if (mounted) {
                        Navigator.of(this.context).pop();
                      }
                    },
                  ),
                if (_isHost && comment.userId != _myParticipant?.userId)
                  ListTile(
                    leading: const Icon(
                      Icons.person_remove_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    title: const Text(
                      'Remove User',
                      style: TextStyle(color: Color(0xFFDC2626)),
                    ),
                    onTap: () async {
                      await ref
                          .read(liveRepositoryProvider)
                          .removeParticipant(
                            sessionId: widget.sessionId,
                            targetUserId: comment.userId,
                          );
                      if (mounted) {
                        Navigator.of(this.context).pop();
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
    reasonController.dispose();
  }

  Future<void> _showMicRequests(List<LiveMicRequest> requests) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Mic Requests',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 10),
                if (requests.isEmpty)
                  const Text('No pending requests.')
                else
                  ...requests.map((request) {
                    return ListTile(
                      title: Text(request.displayName),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          TextButton(
                            onPressed: () => ref
                                .read(liveRepositoryProvider)
                                .denyMicRequest(
                                  sessionId: widget.sessionId,
                                  targetUserId: request.userId,
                                ),
                            child: const Text('Deny'),
                          ),
                          ElevatedButton(
                            onPressed: () => ref
                                .read(liveRepositoryProvider)
                                .approveMicRequest(
                                  sessionId: widget.sessionId,
                                  targetUserId: request.userId,
                                ),
                            child: const Text('Approve'),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(liveRepositoryProvider);

    return MindNestShell(
      maxWidth: 1080,
      appBar: null,
      child: _joining
          ? const Center(child: CircularProgressIndicator())
          : _joinError != null
          ? GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_joinError!),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _join,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : StreamBuilder<LiveSession?>(
              stream: repo.watchLiveSession(widget.sessionId),
              builder: (context, sessionSnap) {
                final session = sessionSnap.data;
                if (session == null) {
                  return const GlassCard(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Live session not found.'),
                    ),
                  );
                }
                if (session.status == LiveSessionStatus.ended) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _handleHostEndedLive(),
                  );
                }
                if (session.status == LiveSessionStatus.paused && _micEnabled) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _setMic(false),
                  );
                }

                return StreamBuilder<List<LiveParticipant>>(
                  stream: repo.watchParticipants(widget.sessionId),
                  builder: (context, participantSnap) {
                    final participants =
                        participantSnap.data ?? const <LiveParticipant>[];
                    final guests = participants
                        .where(
                          (entry) => entry.kind == LiveParticipantKind.guest,
                        )
                        .length;
                    return StreamBuilder<List<LiveMicRequest>>(
                      stream: repo.watchPendingMicRequests(widget.sessionId),
                      builder: (context, reqSnap) {
                        final requests =
                            reqSnap.data ?? const <LiveMicRequest>[];
                        return StreamBuilder<List<LiveComment>>(
                          stream: repo.watchComments(widget.sessionId),
                          builder: (context, commentSnap) {
                            final comments =
                                commentSnap.data ?? const <LiveComment>[];
                            return StreamBuilder<List<LiveReactionEvent>>(
                              stream: repo.watchReactions(widget.sessionId),
                              builder: (context, reactionSnap) {
                                _syncBursts(
                                  reactionSnap.data ??
                                      const <LiveReactionEvent>[],
                                );
                                final commentsPanelHeight =
                                    (MediaQuery.sizeOf(context).height * 0.52)
                                        .clamp(320.0, 560.0)
                                        .toDouble();
                                return Stack(
                                  children: [
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        GlassCard(
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  session.title,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 20,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    _Pill(
                                                      text:
                                                          'Host: ${session.hostName}',
                                                      icon: Icons.person,
                                                    ),
                                                    _Pill(
                                                      text:
                                                          '${participants.length} listening',
                                                      icon: Icons
                                                          .headphones_rounded,
                                                    ),
                                                    _Pill(
                                                      text:
                                                          '$guests/${session.maxGuests} podium',
                                                      icon: Icons.mic_rounded,
                                                    ),
                                                    _Pill(
                                                      text:
                                                          '${session.likeCount} likes',
                                                      icon: Icons
                                                          .favorite_rounded,
                                                    ),
                                                    _Pill(
                                                      text: _audioConnected
                                                          ? 'Audio connected'
                                                          : 'Audio offline',
                                                      icon: _audioConnected
                                                          ? Icons
                                                                .graphic_eq_rounded
                                                          : Icons
                                                                .warning_amber_rounded,
                                                    ),
                                                  ],
                                                ),
                                                if (session.status ==
                                                    LiveSessionStatus
                                                        .paused) ...[
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                    'Paused by host.',
                                                    style: TextStyle(
                                                      color: Color(0xFFD97706),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 10),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    ElevatedButton.icon(
                                                      onPressed:
                                                          (_audioConnected &&
                                                              _canSpeak &&
                                                              session.status ==
                                                                  LiveSessionStatus
                                                                      .live)
                                                          ? () => _setMic(
                                                              !_micEnabled,
                                                            )
                                                          : null,
                                                      icon: Icon(
                                                        _micEnabled
                                                            ? Icons.mic_rounded
                                                            : Icons
                                                                  .mic_off_rounded,
                                                      ),
                                                      label: Text(
                                                        _micEnabled
                                                            ? 'Mute Mic'
                                                            : 'Enable Mic',
                                                      ),
                                                    ),
                                                    if (_myParticipant?.kind ==
                                                        LiveParticipantKind
                                                            .listener)
                                                      OutlinedButton.icon(
                                                        onPressed:
                                                            _audioConnected
                                                            ? () => repo
                                                                  .requestMic(
                                                                    widget
                                                                        .sessionId,
                                                                  )
                                                            : null,
                                                        icon: const Icon(
                                                          Icons
                                                              .record_voice_over_rounded,
                                                        ),
                                                        label: const Text(
                                                          'Request Mic',
                                                        ),
                                                      ),
                                                    if (_isHost)
                                                      OutlinedButton.icon(
                                                        onPressed: () =>
                                                            repo.togglePause(
                                                              sessionId: widget
                                                                  .sessionId,
                                                              pause:
                                                                  session
                                                                      .status ==
                                                                  LiveSessionStatus
                                                                      .live,
                                                            ),
                                                        icon: Icon(
                                                          session.status ==
                                                                  LiveSessionStatus
                                                                      .live
                                                              ? Icons
                                                                    .pause_circle_outline_rounded
                                                              : Icons
                                                                    .play_circle_outline_rounded,
                                                        ),
                                                        label: Text(
                                                          session.status ==
                                                                  LiveSessionStatus
                                                                      .live
                                                              ? 'Pause'
                                                              : 'Resume',
                                                        ),
                                                      ),
                                                    if (_isHost)
                                                      OutlinedButton.icon(
                                                        onPressed: () =>
                                                            _showMicRequests(
                                                              requests,
                                                            ),
                                                        icon: const Icon(
                                                          Icons
                                                              .manage_accounts_rounded,
                                                        ),
                                                        label: Text(
                                                          'Requests (${requests.length})',
                                                        ),
                                                      ),
                                                    if (_isHost)
                                                      ElevatedButton.icon(
                                                        onPressed: () =>
                                                            repo.endLiveSession(
                                                              widget.sessionId,
                                                            ),
                                                        style:
                                                            ElevatedButton.styleFrom(
                                                              backgroundColor:
                                                                  const Color(
                                                                    0xFFDC2626,
                                                                  ),
                                                              foregroundColor:
                                                                  Colors.white,
                                                            ),
                                                        icon: const Icon(
                                                          Icons
                                                              .stop_circle_outlined,
                                                        ),
                                                        label: const Text(
                                                          'End Live',
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          height: commentsPanelHeight,
                                          child: GlassCard(
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  const Text(
                                                    'Live Comments',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Expanded(
                                                    child: ListView.builder(
                                                      reverse: true,
                                                      itemCount:
                                                          comments.length,
                                                      itemBuilder: (context, index) {
                                                        final comment =
                                                            comments[index];
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                bottom: 8,
                                                              ),
                                                          child: InkWell(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                            onTap: () =>
                                                                _onCommentTap(
                                                                  comment,
                                                                ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    10,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    const Color(
                                                                      0xFFF8FAFC,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                              ),
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  InkWell(
                                                                    onTap: () async {
                                                                      final profile = await repo.fetchMemberPublicProfile(
                                                                        sessionId:
                                                                            widget.sessionId,
                                                                        userId:
                                                                            comment.userId,
                                                                      );
                                                                      if (!mounted) {
                                                                        return;
                                                                      }
                                                                      showDialog<
                                                                        void
                                                                      >(
                                                                        context:
                                                                            this.context,
                                                                        builder:
                                                                            (
                                                                              context,
                                                                            ) => AlertDialog(
                                                                              title: const Text(
                                                                                'Member Profile',
                                                                              ),
                                                                              content: Text(
                                                                                profile ==
                                                                                        null
                                                                                    ? 'Profile unavailable.'
                                                                                    : '${profile.displayName}\n${profile.role}\n${profile.email}',
                                                                              ),
                                                                            ),
                                                                      );
                                                                    },
                                                                    child: Text(
                                                                      comment
                                                                          .displayName,
                                                                      style: const TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.w800,
                                                                        color: Color(
                                                                          0xFF0D9488,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 2,
                                                                  ),
                                                                  Text(
                                                                    comment
                                                                        .text,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: TextField(
                                                          controller:
                                                              _commentController,
                                                          maxLength: 250,
                                                          decoration:
                                                              const InputDecoration(
                                                                counterText: '',
                                                                hintText:
                                                                    'Comment...',
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      IconButton.filled(
                                                        onPressed: () async {
                                                          await repo.sendComment(
                                                            sessionId: widget
                                                                .sessionId,
                                                            text:
                                                                _commentController
                                                                    .text,
                                                          );
                                                          _commentController
                                                              .clear();
                                                        },
                                                        style:
                                                            IconButton.styleFrom(
                                                              backgroundColor:
                                                                  const Color(
                                                                    0xFF0D9488,
                                                                  ),
                                                            ),
                                                        icon: const Icon(
                                                          Icons.send_rounded,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 8,
                                                    children:
                                                        const [
                                                              '\u2764\ufe0f',
                                                              '\u{1F525}',
                                                              '\u{1F44F}',
                                                              '\u{1F499}',
                                                              '\u{1F389}',
                                                              '\u{1F64C}',
                                                            ]
                                                            .map(
                                                              (
                                                                emoji,
                                                              ) => OutlinedButton(
                                                                onPressed: () async {
                                                                  try {
                                                                    await repo.sendReaction(
                                                                      sessionId:
                                                                          widget
                                                                              .sessionId,
                                                                      emoji:
                                                                          emoji,
                                                                    );
                                                                  } catch (
                                                                    error
                                                                  ) {
                                                                    if (!mounted) {
                                                                      return;
                                                                    }
                                                                    ScaffoldMessenger.of(
                                                                      this.context,
                                                                    ).showSnackBar(
                                                                      SnackBar(
                                                                        content: Text(
                                                                          error.toString().replaceFirst(
                                                                            'Exception: ',
                                                                            '',
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    );
                                                                  }
                                                                },
                                                                child: Text(
                                                                  emoji,
                                                                  style:
                                                                      const TextStyle(
                                                                        fontSize:
                                                                            18,
                                                                      ),
                                                                ),
                                                              ),
                                                            )
                                                            .toList(
                                                              growable: false,
                                                            ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    ..._bursts.map(
                                      (burst) => Positioned(
                                        right: burst.right,
                                        bottom: 24,
                                        child: _BurstWidget(
                                          key: ValueKey('burst_${burst.id}'),
                                          emoji: burst.emoji,
                                          onDone: () {
                                            _bursts.removeWhere(
                                              (entry) => entry.id == burst.id,
                                            );
                                            if (mounted) {
                                              setState(() {});
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.icon});
  final String text;
  final IconData icon;

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
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Burst {
  const _Burst({required this.id, required this.emoji, required this.right});
  final String id;
  final String emoji;
  final double right;
}

class _BurstWidget extends StatefulWidget {
  const _BurstWidget({super.key, required this.emoji, required this.onDone});
  final String emoji;
  final VoidCallback onDone;

  @override
  State<_BurstWidget> createState() => _BurstWidgetState();
}

class _BurstWidgetState extends State<_BurstWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();
  late final Animation<double> _rise = Tween<double>(
    begin: 0,
    end: -220,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(0, _rise.value),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}
