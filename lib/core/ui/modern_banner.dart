import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ModernBannerTone { info, success, warning, error }

OverlayEntry? _currentOverlayEntry;
Timer? _currentAutoDismissTimer;

void _removeCurrentOverlayEntryImmediate() {
  try {
    _currentAutoDismissTimer?.cancel();
    _currentAutoDismissTimer = null;
    _currentOverlayEntry?.remove();
  } catch (_) {}
  _currentOverlayEntry = null;
}

/// Displays a floating banner at the top of the application using an
/// [OverlayEntry]. Falls back to the old MaterialBanner when an Overlay
/// is not available (rare). The banner auto-dismisses after [autoDismissAfter].
void showModernBanner(
  BuildContext context, {
  required String message,
  IconData icon = Icons.info_outline_rounded,
  Color color = const Color(0xFF0E9B90),
  Duration autoDismissAfter = const Duration(seconds: 6),
}) {
  // Remove any existing overlay banner immediately
  _removeCurrentOverlayEntryImmediate();

  final overlay = Overlay.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (overlay == null) {
    // Fallback to MaterialBanner when no overlay is available.
    messenger.removeCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.white,
        elevation: 8,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: const EdgeInsets.only(right: 12),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Dismiss'),
          ),
        ],
        surfaceTintColor: Colors.transparent,
      ),
    );

    if (autoDismissAfter.inMilliseconds > 0) {
      Future.delayed(autoDismissAfter, messenger.hideCurrentMaterialBanner);
    }
    return;
  }

  // Build overlay entry with animated banner widget
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _ModernBannerWidget(
      message: message,
      icon: icon,
      color: color,
      autoDismissAfter: autoDismissAfter,
      onClosed: () {
        // remove overlay entry after animation completes
        try {
          entry.remove();
        } catch (_) {}
        if (_currentOverlayEntry == entry) {
          _currentOverlayEntry = null;
        }
      },
    ),
  );

  _currentOverlayEntry = entry;
  overlay.insert(entry);
}

void showModernBannerFromSnackBar(BuildContext context, SnackBar snackBar) {
  final message = _extractMessageFromWidget(snackBar.content).trim();
  final tone = _inferToneFromMessage(message);
  final messenger = ScaffoldMessenger.of(context);

  messenger.removeCurrentSnackBar();
  messenger.removeCurrentMaterialBanner();

  showModernBanner(
    context,
    message: message.isEmpty ? 'Done.' : message,
    icon: _iconForTone(tone),
    color: _colorForTone(tone),
    autoDismissAfter: snackBar.duration,
  );
}

String _extractMessageFromWidget(Widget? widget) {
  if (widget == null) {
    return '';
  }

  if (widget is Text) {
    final data = widget.data?.trim();
    if (data != null && data.isNotEmpty) {
      return data;
    }
    final spanText = widget.textSpan?.toPlainText().trim();
    if (spanText != null && spanText.isNotEmpty) {
      return spanText;
    }
  }

  if (widget is RichText) {
    final data = widget.text.toPlainText().trim();
    if (data.isNotEmpty) {
      return data;
    }
  }

  if (widget is Padding) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is Align) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is Center) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is SizedBox) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is Container) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is DecoratedBox) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is DefaultTextStyle) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is Expanded) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is Flexible) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is SafeArea) {
    return _extractMessageFromWidget(widget.child);
  }

  if (widget is Row) {
    return widget.children
        .map(_extractMessageFromWidget)
        .where((text) => text.trim().isNotEmpty)
        .join(' ')
        .trim();
  }

  if (widget is Column) {
    return widget.children
        .map(_extractMessageFromWidget)
        .where((text) => text.trim().isNotEmpty)
        .join(' ')
        .trim();
  }

  if (widget is Wrap) {
    return widget.children
        .map(_extractMessageFromWidget)
        .where((text) => text.trim().isNotEmpty)
        .join(' ')
        .trim();
  }

  return '';
}

ModernBannerTone _inferToneFromMessage(String message) {
  final normalized = message.toLowerCase();

  const errorHints = <String>[
    'error',
    'failed',
    'fail',
    'invalid',
    'incorrect',
    'declined',
    'removed',
    'unable',
    'could not',
    'must',
    'missing',
    'not found',
    'not available',
    'can\'t',
    'cannot',
  ];
  if (errorHints.any(normalized.contains)) {
    return ModernBannerTone.error;
  }

  const warningHints = <String>['pending', 'review', 'warning', 'wait'];
  if (warningHints.any(normalized.contains)) {
    return ModernBannerTone.warning;
  }

  const successHints = <String>[
    'sent',
    'saved',
    'updated',
    'approved',
    'accepted',
    'joined',
    'booked',
    'completed',
    'published',
    'resubmitted',
    'revoked',
    'deleted',
    'regenerated',
    'submitted',
    'marked',
    'connected',
  ];
  if (successHints.any(normalized.contains)) {
    return ModernBannerTone.success;
  }

  return ModernBannerTone.info;
}

Color _colorForTone(ModernBannerTone tone) {
  switch (tone) {
    case ModernBannerTone.success:
      return const Color(0xFF0E9B90);
    case ModernBannerTone.warning:
      return const Color(0xFFC78400);
    case ModernBannerTone.error:
      return const Color(0xFFBE123C);
    case ModernBannerTone.info:
      return const Color(0xFF2563EB);
  }
}

IconData _iconForTone(ModernBannerTone tone) {
  switch (tone) {
    case ModernBannerTone.success:
      return Icons.check_circle_outline_rounded;
    case ModernBannerTone.warning:
      return Icons.warning_amber_rounded;
    case ModernBannerTone.error:
      return Icons.error_outline_rounded;
    case ModernBannerTone.info:
      return Icons.info_outline_rounded;
  }
}

class _ModernBannerWidget extends StatefulWidget {
  const _ModernBannerWidget({
    required this.message,
    required this.icon,
    required this.color,
    required this.autoDismissAfter,
    required this.onClosed,
  });

  final String message;
  final IconData icon;
  final Color color;
  final Duration autoDismissAfter;
  final VoidCallback onClosed;

  @override
  State<_ModernBannerWidget> createState() => _ModernBannerWidgetState();
}

class _ModernBannerWidgetState extends State<_ModernBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  Timer? _localTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    if (widget.autoDismissAfter.inMilliseconds > 0) {
      _localTimer = Timer(widget.autoDismissAfter, _startClose);
      _currentAutoDismissTimer = _localTimer;
    }
  }

  @override
  void dispose() {
    _localTimer?.cancel();
    if (_currentAutoDismissTimer == _localTimer) {
      _currentAutoDismissTimer = null;
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await _controller.reverse();
    } catch (_) {}
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxWidth = math.min(980.0, mq.size.width - 56);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, -0.2),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: _controller, curve: Curves.easeOut),
                ),
            child: FadeTransition(
              opacity: _controller.drive(CurveTween(curve: Curves.easeIn)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x220F172A),
                          blurRadius: 30,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: widget.color.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _startClose,
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF68758A),
                          splashRadius: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
