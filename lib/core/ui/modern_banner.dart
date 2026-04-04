import 'package:flutter/material.dart';

enum ModernBannerTone { info, success, warning, error }

/// Displays the modern MaterialBanner used across MindNest auth flows.
void showModernBanner(
  BuildContext context, {
  required String message,
  IconData icon = Icons.info_outline_rounded,
  Color color = const Color(0xFF0E9B90),
  Duration autoDismissAfter = const Duration(seconds: 6),
}) {
  final messenger = ScaffoldMessenger.of(context);
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
