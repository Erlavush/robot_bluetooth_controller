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
      minScale: 0.22,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(520),
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

    return bestDistance <= graphNodeBlockSize / 2 + 18 ? bestNode : null;
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

    return bestDistance <= graphTrackWidth / 2 + 18 ? bestEdge : null;
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
    _drawNodes(canvas);
    _drawRobot(canvas);
  }

  void _drawTracks(Canvas canvas) {
    final trackPaint = Paint()
      ..color = const Color(0xFF050505)
      ..style = PaintingStyle.stroke
      ..strokeWidth = graphTrackWidth
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(edgePath(startGuideNode, showcaseStartNode), trackPaint);
    canvas.drawPath(edgePath(showcaseFinishNode, finishGuideNode), trackPaint);

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
          ..strokeWidth = 12,
      );
    }

    for (var i = 0; i < path.length - 1; i++) {
      canvas.drawPath(
        edgePath(path[i], path[i + 1]),
        layerPaint
          ..color = const Color(0xFFFF9F1C)
          ..strokeWidth = 12,
      );
    }
  }

  void _drawNodes(Canvas canvas) {
    for (final entry in graphNodes.entries) {
      final id = entry.key;
      final point = entry.value;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: point,
          width: graphNodeBlockSize,
          height: graphNodeBlockSize,
        ),
        const Radius.circular(1),
      );

      var strokeColor = const Color(0xFF050505);
      var strokeWidth = 2.0;
      if (destination == id) {
        strokeColor = const Color(0xFFFF3131);
        strokeWidth = 8;
      }
      if (direction != null && direction!.length == 2 && direction![1] == id) {
        strokeColor = const Color(0xFF10C772);
        strokeWidth = 8;
      }
      if (currentNode == id) {
        strokeColor = const Color(0xFFB967FF);
        strokeWidth = 8;
      }

      canvas.drawRRect(rect, Paint()..color = const Color(0xFF050505));
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
        color: const Color(0xFF111827),
      );
    }
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
