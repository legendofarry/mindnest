import 'package:flutter/material.dart';

class NoScrollbarScrollBehavior extends MaterialScrollBehavior {
  const NoScrollbarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
