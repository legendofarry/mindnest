import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

bool get _supportsWindowManager =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool isWindowsDesktopShell(BuildContext context) {
  if (!_supportsWindowManager) {
    return false;
  }
  final mediaQuery = MediaQuery.maybeOf(context);
  final width = mediaQuery?.size.width ?? double.infinity;
  return width >= 900;
}

class WindowsDesktopWindowControls extends StatefulWidget {
  const WindowsDesktopWindowControls({super.key});

  @override
  State<WindowsDesktopWindowControls> createState() =>
      _WindowsDesktopWindowControlsState();
}

class _WindowsDesktopWindowControlsState
    extends State<WindowsDesktopWindowControls>
    with WindowListener {
  bool _isMaximized = true;

  @override
  void initState() {
    super.initState();
    if (!_supportsWindowManager) {
      return;
    }
    windowManager.addListener(this);
    _syncWindowState();
  }

  @override
  void dispose() {
    if (_supportsWindowManager) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _isMaximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _isMaximized = false);
    }
  }

  Future<void> _syncWindowState() async {
    if (!_supportsWindowManager) {
      return;
    }
    final isMaximized = await windowManager.isMaximized();
    if (!mounted) {
      return;
    }
    setState(() => _isMaximized = isMaximized);
  }

  @override
  Widget build(BuildContext context) {
    if (!isWindowsDesktopShell(context)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _WindowControlButton(
            tooltip: 'Minimize',
            icon: Icons.minimize_rounded,
            iconColor: Color(0xFF16324F),
            hoverColor: Color(0xFFE8F1FA),
            onPressed: _minimizeWindow,
          ),
          SizedBox(width: 4),
          _WindowControlButton(
            tooltip: _isMaximized ? 'Restore window' : 'Maximize window',
            icon: _isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconColor: Color(0xFF16324F),
            hoverColor: Color(0xFFE8F1FA),
            onPressed: _toggleMaximizeWindow,
          ),
          const SizedBox(width: 4),
          const _WindowControlButton(
            tooltip: 'Exit app',
            icon: Icons.close_rounded,
            iconColor: Color(0xFFB42318),
            hoverColor: Color(0xFFFDECEC),
            onPressed: _closeWindow,
          ),
        ],
      ),
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.iconColor,
    required this.hoverColor,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color iconColor;
  final Color hoverColor;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          hoverColor: hoverColor,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, color: iconColor, size: 19),
          ),
        ),
      ),
    );
  }
}

Future<void> _minimizeWindow() async {
  if (!_supportsWindowManager) {
    return;
  }
  await windowManager.minimize();
}

Future<void> _toggleMaximizeWindow() async {
  if (!_supportsWindowManager) {
    return;
  }
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
    return;
  }
  await windowManager.maximize();
}

Future<void> _closeWindow() async {
  if (!_supportsWindowManager) {
    return;
  }
  await windowManager.close();
}
