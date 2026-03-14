import 'package:flutter/material.dart';

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
          color: color.withOpacity(0.14),
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
