// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class MindNestLogo extends StatefulWidget {
  const MindNestLogo({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  });

  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  State<MindNestLogo> createState() => _MindNestLogoState();
}

class _MindNestLogoState extends State<MindNestLogo> {
  static int _nextViewId = 0;

  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'mindnest-logo-${_nextViewId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
      final alignment = widget.alignment.resolve(TextDirection.ltr);
      final image = html.ImageElement()
        ..src = 'assets/assets/MindNest-Logo.svg'
        ..alt = 'MindNest logo'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        ..style.objectFit = _cssObjectFit(widget.fit)
        ..style.objectPosition =
            '${_toPercent(alignment.x)} ${_toPercent(alignment.y)}';
      return image;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }

  String _cssObjectFit(BoxFit fit) {
    return switch (fit) {
      BoxFit.fill => 'fill',
      BoxFit.contain => 'contain',
      BoxFit.cover => 'cover',
      BoxFit.fitWidth => 'contain',
      BoxFit.fitHeight => 'contain',
      BoxFit.none => 'none',
      BoxFit.scaleDown => 'scale-down',
    };
  }

  String _toPercent(double value) {
    final percent = ((value + 1) / 2) * 100;
    return '${percent.clamp(0, 100).toStringAsFixed(0)}%';
  }
}
