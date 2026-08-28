import 'package:flutter/material.dart';
import 'main.dart' show AppColors;

/// Shows a floating success/error card that fades in, sits for a moment,
/// then fades out on its own. This is an Overlay entry, NOT a dialog route,
/// so it can never collide with real screen navigation (unlike showDialog,
/// which competes with pushReplacement/pop calls for the same nav stack).
void showAppNotification(
  BuildContext context, {
  required String message,
  bool isError = false,
}) {
  final overlayState = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _NotificationOverlay(
      message: message,
      isError: isError,
      onFinished: () {
        entry.remove();
      },
    ),
  );

  overlayState.insert(entry);
}

class _NotificationOverlay extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onFinished;

  const _NotificationOverlay({
    required this.message,
    required this.isError,
    required this.onFinished,
  });

  @override
  State<_NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<_NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;
      await _controller.reverse();
      widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Material(
          color: Colors.black.withValues(alpha: 0.001),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Center(
                child: Transform.scale(
                  scale: _scale.value.clamp(0.0, 1.2),
                  child: Opacity(
                    opacity: _opacity.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              );
            },
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 40),
              padding: EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.isError ? Colors.redAccent : AppColors.accent,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (widget.isError ? Colors.redAccent : AppColors.primary)
                            .withValues(alpha: 0.18),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isError
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    color: widget.isError ? Colors.redAccent : AppColors.accent,
                    size: 48,
                  ),
                  SizedBox(height: 14),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
