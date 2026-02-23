import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindnest/app/theme.dart';
import 'package:mindnest/app/theme_mode_controller.dart';
import 'package:mindnest/core/routes/app_router.dart';

class MindNestApp extends ConsumerWidget {
  const MindNestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeControllerProvider);

    return MaterialApp.router(
      title: 'MindNest',
      theme: MindNestTheme.light(),
      darkTheme: MindNestTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
