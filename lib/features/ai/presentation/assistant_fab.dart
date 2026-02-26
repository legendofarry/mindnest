import 'package:flutter/material.dart';

class AssistantFab extends StatelessWidget {
  const AssistantFab({
    super.key,
    required this.onPressed,
    required this.heroTag,
  });

  final VoidCallback onPressed;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: heroTag,
      onPressed: onPressed,
      backgroundColor: const Color(0xFF0E9B90),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.smart_toy_outlined),
      label: const Text(
        'Ask AI',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
