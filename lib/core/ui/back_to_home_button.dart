import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';

class BackToHomeButton extends StatelessWidget {
  const BackToHomeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back to Home',
      onPressed: () => context.go(AppRoute.home),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }
}
