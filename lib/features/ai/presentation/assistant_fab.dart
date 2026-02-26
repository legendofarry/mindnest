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
    return Hero(
      tag: heroTag,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF0EA5A0), Color(0xFF0B7C9E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x66E6FFFA)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x3D0B7C9E),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.smart_toy_outlined, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'MindNest AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
                SizedBox(width: 8),
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: Color(0xFFE6FFFA),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
