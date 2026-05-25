import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ArrowDirection { up, down, left, right }

class ArrowControlButton extends StatefulWidget {
  const ArrowControlButton({
    super.key,
    required this.direction,
    required this.active,
    required this.disabled,
    required this.onPressedChanged,
  });

  final ArrowDirection direction;
  final bool active;
  final bool disabled;
  final ValueChanged<bool> onPressedChanged;

  @override
  State<ArrowControlButton> createState() => _ArrowControlButtonState();
}

class _ArrowControlButtonState extends State<ArrowControlButton> {
  final Set<int> _activePointers = {};

  bool get _pressed => _activePointers.isNotEmpty;

  void _setPointer(int pointer, bool active) {
    if (widget.disabled) {
      return;
    }

    final wasPressed = _pressed;
    if (active) {
      _activePointers.add(pointer);
    } else {
      _activePointers.remove(pointer);
    }

    if (wasPressed != _pressed) {
      widget.onPressedChanged(_pressed);
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant ArrowControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disabled && _activePointers.isNotEmpty) {
      _activePointers.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !widget.disabled,
      child: Listener(
        onPointerDown: (event) => _setPointer(event.pointer, true),
        onPointerUp: (event) => _setPointer(event.pointer, false),
        onPointerCancel: (event) => _setPointer(event.pointer, false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 80),
          scale: _pressed ? 0.94 : 1,
          child: Opacity(
            opacity: widget.disabled ? 0.25 : 1,
            child: ColoredBox(
              color: Colors.black,
              child: CustomPaint(
                painter: _ArrowPainter(
                  direction: widget.direction,
                  active: widget.active,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.direction, required this.active});

  final ArrowDirection direction;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = active ? const Color(0xFFFFE066) : Colors.white
      ..style = PaintingStyle.fill;

    final shadow = Paint()
      ..color = const Color(0xFFFFE066).withValues(alpha: active ? 0.45 : 0)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    final path = _arrowPath(size);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(_rotation);
    canvas.translate(-size.width / 2, -size.height / 2);
    if (active) {
      canvas.drawPath(path, shadow);
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  Path _arrowPath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.50, 0)
      ..lineTo(w * 0.97, h * 0.55)
      ..lineTo(w * 0.70, h * 0.55)
      ..lineTo(w * 0.70, h)
      ..lineTo(w * 0.30, h)
      ..lineTo(w * 0.30, h * 0.55)
      ..lineTo(w * 0.03, h * 0.55)
      ..close();
  }

  double get _rotation {
    switch (direction) {
      case ArrowDirection.up:
        return 0;
      case ArrowDirection.down:
        return math.pi;
      case ArrowDirection.left:
        return -math.pi / 2;
      case ArrowDirection.right:
        return math.pi / 2;
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) {
    return oldDelegate.direction != direction || oldDelegate.active != active;
  }
}
