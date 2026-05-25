import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/robot_graph.dart';

class NodeMap extends StatelessWidget {
  const NodeMap({
    super.key,
    required this.transformationController,
    required this.selectedEdge,
    required this.direction,
    required this.destination,
    required this.path,
    required this.currentNode,
    required this.robotPosition,
    required this.robotAngle,
    required this.robotVisible,
    required this.robotBlinkRed,
    required this.onEdgeSelected,
    required this.onNodeSelected,
  });

  final TransformationController transformationController;
  final GraphEdge? selectedEdge;
  final List<int>? direction;
  final int? destination;
  final List<int> path;
  final int? currentNode;
  final Offset? robotPosition;
  final double robotAngle;
  final bool robotVisible;
  final bool robotBlinkRed;
  final ValueChanged<GraphEdge> onEdgeSelected;
  final ValueChanged<int> onNodeSelected;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: transformationController,
      constrained: false,
      minScale: 0.58,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(360),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTap,
        child: CustomPaint(
          size: graphSize,
          painter: NodeMapPainter(
            selectedEdge: selectedEdge,
            direction: direction,
            destination: destination,
            path: path,
            currentNode: currentNode,
            robotPosition: robotPosition,
            robotAngle: robotAngle,
            robotVisible: robotVisible,
            robotBlinkRed: robotBlinkRed,
          ),
        ),
      ),
    );
  }

  void _handleTap(TapUpDetails details) {
    final point = details.localPosition;

    final node = _hitNode(point);
    if (node != null) {
      onNodeSelected(node);
      return;
    }

    final edge = _hitEdge(point);
    if (edge != null) {
      onEdgeSelected(edge);
    }
  }

  int? _hitNode(Offset point) {
    int? bestNode;
    var bestDistance = double.infinity;

    for (final entry in graphNodes.entries) {
      final distance = (entry.value - point).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestNode = entry.key;
      }
    }

    return bestDistance <= 24 ? bestNode : null;
  }

  GraphEdge? _hitEdge(Offset point) {
    GraphEdge? bestEdge;
    var bestDistance = double.infinity;

    for (final edge in allGraphEdges) {
      final distance = _distanceToPath(edgePath(edge.a, edge.b), point);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestEdge = edge;
      }
    }

    return bestDistance <= 28 ? bestEdge : null;
  }

  double _distanceToPath(Path path, Offset point) {
    var best = double.infinity;
    for (final metric in path.computeMetrics()) {
      final samples = math.max(10, (metric.length / 8).ceil());
      for (var i = 0; i <= samples; i++) {
        final offset = metric.length * i / samples;
        final tangent = metric.getTangentForOffset(offset);
        if (tangent == null) {
          continue;
        }

        final distance = (tangent.position - point).distance;
        if (distance < best) {
          best = distance;
        }
      }
    }
    return best;
  }
}

class NodeMapPainter extends CustomPainter {
  const NodeMapPainter({
    required this.selectedEdge,
    required this.direction,
    required this.destination,
    required this.path,
    required this.currentNode,
    required this.robotPosition,
    required this.robotAngle,
    required this.robotVisible,
    required this.robotBlinkRed,
  });

  final GraphEdge? selectedEdge;
  final List<int>? direction;
  final int? destination;
  final List<int> path;
  final int? currentNode;
  final Offset? robotPosition;
  final double robotAngle;
  final bool robotVisible;
  final bool robotBlinkRed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _drawTracks(canvas);
    _drawHighlights(canvas);
    _drawCompass(canvas);
    _drawNodes(canvas);
    _drawRobot(canvas);
  }

  void _drawTracks(Canvas canvas) {
    final trackPaint = Paint()
      ..color = const Color(0xFF050505)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;

    for (final edge in allGraphEdges) {
      final paint = trackPaint
        ..strokeCap = curvedEdges.containsKey(edge.key)
            ? StrokeCap.round
            : StrokeCap.butt;
      canvas.drawPath(edgePath(edge.a, edge.b), paint);
    }
  }

  void _drawHighlights(Canvas canvas) {
    final layerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final selected = direction != null && direction!.length == 2
        ? GraphEdge(direction![0], direction![1])
        : selectedEdge;
    if (selected != null) {
      canvas.drawPath(
        edgePath(selected.a, selected.b),
        layerPaint
          ..color = const Color(0xFF2D7DFF)
          ..strokeWidth = 7,
      );
    }

    for (var i = 0; i < path.length - 1; i++) {
      canvas.drawPath(
        edgePath(path[i], path[i + 1]),
        layerPaint
          ..color = const Color(0xFFFF9F1C)
          ..strokeWidth = 7,
      );
    }
  }

  void _drawNodes(Canvas canvas) {
    for (final entry in graphNodes.entries) {
      final id = entry.key;
      final point = entry.value;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: point, width: 14, height: 14),
        const Radius.circular(2),
      );

      var strokeColor = const Color(0xFF111827);
      var strokeWidth = 1.4;
      if (destination == id) {
        strokeColor = const Color(0xFFFF3131);
        strokeWidth = 4;
      }
      if (direction != null && direction!.length == 2 && direction![1] == id) {
        strokeColor = const Color(0xFF10C772);
        strokeWidth = 4;
      }
      if (currentNode == id) {
        strokeColor = const Color(0xFFB967FF);
        strokeWidth = 4;
      }

      canvas.drawRRect(rect, Paint()..color = Colors.white);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );

      final labelOffset = labelOffsets[id] ?? const Offset(12, -12);
      _drawOutlinedText(
        canvas,
        id.toString(),
        point + labelOffset,
        fontSize: 15,
        color: const Color(0xFFDC2626),
      );
    }
  }

  void _drawCompass(Canvas canvas) {
    const center = Offset(500, 730);
    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    canvas.drawCircle(center, 36, paint);
    _drawCompassArrow(canvas, center + const Offset(0, -54), 0);
    _drawCompassArrow(canvas, center + const Offset(54, 0), math.pi / 2);
    _drawCompassArrow(canvas, center + const Offset(0, 54), math.pi);
    _drawCompassArrow(canvas, center + const Offset(-54, 0), -math.pi / 2);

    canvas.drawCircle(center, 11, Paint()..color = const Color(0xFF111827));
    _drawPlainText(canvas, 'N', center + const Offset(0, -66));
    _drawPlainText(canvas, 'E', center + const Offset(66, 6));
    _drawPlainText(canvas, 'S', center + const Offset(0, 84));
    _drawPlainText(canvas, 'W', center + const Offset(-66, 6));
  }

  void _drawCompassArrow(Canvas canvas, Offset tip, double angle) {
    final path = Path()
      ..moveTo(0, -18)
      ..lineTo(10, 18)
      ..lineTo(0, 10)
      ..lineTo(-10, 18)
      ..close();

    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(angle);
    canvas.drawPath(path, Paint()..color = const Color(0xFF111827));
    canvas.restore();
  }

  void _drawRobot(Canvas canvas) {
    final point = robotPosition;
    if (!robotVisible || point == null) {
      return;
    }

    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(robotAngle);
    canvas.drawCircle(
      Offset.zero,
      16,
      Paint()
        ..color = robotBlinkRed
            ? const Color(0xFFFF3131)
            : const Color(0xFF2D7DFF),
    );
    canvas.drawCircle(
      Offset.zero,
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white,
    );
    final head = Path()
      ..moveTo(0, -25)
      ..lineTo(8, -9)
      ..lineTo(0, -14)
      ..lineTo(-8, -9)
      ..close();
    canvas.drawPath(head, Paint()..color = Colors.white);
    canvas.restore();
  }

  void _drawOutlinedText(
    Canvas canvas,
    String text,
    Offset center, {
    required double fontSize,
    required Color color,
  }) {
    _paintText(
      canvas,
      text,
      center,
      TextStyle(
        fontFamily: 'Quicksand',
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.white,
      ),
    );
    _paintText(
      canvas,
      text,
      center,
      TextStyle(
        fontFamily: 'Quicksand',
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        color: color,
      ),
    );
  }

  void _drawPlainText(Canvas canvas, String text, Offset center) {
    _paintText(
      canvas,
      text,
      center,
      const TextStyle(
        fontFamily: 'Quicksand',
        color: Color(0xFF111827),
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  void _paintText(Canvas canvas, String text, Offset center, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant NodeMapPainter oldDelegate) {
    return oldDelegate.selectedEdge != selectedEdge ||
        oldDelegate.direction != direction ||
        oldDelegate.destination != destination ||
        oldDelegate.path != path ||
        oldDelegate.currentNode != currentNode ||
        oldDelegate.robotPosition != robotPosition ||
        oldDelegate.robotAngle != robotAngle ||
        oldDelegate.robotVisible != robotVisible ||
        oldDelegate.robotBlinkRed != robotBlinkRed;
  }
}
