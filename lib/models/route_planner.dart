import 'dart:math' as math;

import 'robot_graph.dart';

class RoutePlan {
  const RoutePlan({
    required this.path,
    required this.commands,
    this.finishAction,
  });

  final List<int> path;
  final List<String> commands;
  final String? finishAction;

  bool get isValid => path.isNotEmpty && commands.isNotEmpty;
}

class RoutePlanner {
  const RoutePlanner._();

  static const Set<String> validRouteCommands = {
    'S',
    'Q',
    'E',
    'L',
    'R',
    'U',
    'X',
  };

  static RoutePlan calculate({
    required int previousNode,
    required int startNode,
    required int destinationNode,
    bool preferLongest = false,
    bool finishExit = false,
  }) {
    final path = preferLongest
        ? longestSimplePath(startNode, destinationNode)
        : shortestPath(startNode, destinationNode);
    if (path.isEmpty) {
      return const RoutePlan(path: [], commands: []);
    }

    final finishAction = finishExit && path.length >= 2
        ? turnCommand(path[path.length - 2], path.last, finishGuideNode)
        : null;

    return RoutePlan(
      path: path,
      commands: generateCommands(previousNode, path),
      finishAction: finishAction,
    );
  }

  static List<int> shortestPath(int start, int end) {
    if (!graphNodes.containsKey(start) || !graphNodes.containsKey(end)) {
      return [];
    }

    final unvisited = graphNodes.keys.toSet();
    final distances = <int, double>{
      for (final node in unvisited) node: double.infinity,
      start: 0,
    };
    final previous = <int, int>{};

    while (unvisited.isNotEmpty) {
      int? current;
      var best = double.infinity;

      for (final node in unvisited) {
        final distance = distances[node] ?? double.infinity;
        if (distance < best) {
          best = distance;
          current = node;
        }
      }

      if (current == null) {
        break;
      }
      if (current == end) {
        break;
      }

      unvisited.remove(current);
      for (final next in graphAdjacency[current] ?? const <int>[]) {
        if (!unvisited.contains(next)) {
          continue;
        }

        final alternative =
            (distances[current] ?? double.infinity) +
            edgeDistance(current, next);
        if (alternative < (distances[next] ?? double.infinity)) {
          distances[next] = alternative;
          previous[next] = current;
        }
      }
    }

    if (start == end) {
      return [start];
    }
    if (!previous.containsKey(end)) {
      return [];
    }

    final path = <int>[end];
    var current = end;
    while (current != start) {
      current = previous[current]!;
      path.insert(0, current);
    }
    return path;
  }

  static List<int> longestSimplePath(int start, int end) {
    if (!graphNodes.containsKey(start) || !graphNodes.containsKey(end)) {
      return [];
    }

    var bestDistance = double.negativeInfinity;
    var bestPath = <int>[];

    void visit(int current, Set<int> visited, List<int> path, double distance) {
      if (current == end) {
        if (distance > bestDistance) {
          bestDistance = distance;
          bestPath = List<int>.from(path);
        }
        return;
      }

      for (final next in graphAdjacency[current] ?? const <int>[]) {
        if (visited.contains(next)) {
          continue;
        }

        visited.add(next);
        path.add(next);
        visit(next, visited, path, distance + edgeDistance(current, next));
        path.removeLast();
        visited.remove(next);
      }
    }

    visit(start, {start}, [start], 0);
    return bestPath;
  }

  static List<String> generateCommands(int previousNode, List<int> path) {
    if (path.isEmpty) {
      return [];
    }
    if (path.length == 1) {
      return ['X'];
    }

    final commands = <String>[];
    var previous = previousNode;
    for (var i = 0; i < path.length - 1; i++) {
      final current = path[i];
      final next = path[i + 1];
      commands.add(turnCommand(previous, current, next));
      previous = current;
    }
    commands.add('X');
    return commands;
  }

  static String turnCommand(int previous, int current, int next) {
    final a = graphPointFor(previous);
    final b = graphPointFor(current);
    final c = graphPointFor(next);

    final v1 = b - a;
    final v2 = c - b;
    final mag1 = v1.distance;
    final mag2 = v2.distance;
    if (mag1 == 0 || mag2 == 0) {
      return '?';
    }

    final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (mag1 * mag2);
    final cross = v1.dx * v2.dy - v1.dy * v2.dx;
    final clampedDot = dot.clamp(-1.0, 1.0).toDouble();
    final angle = math.acos(clampedDot) * 180 / math.pi;

    if (angle < 25) {
      return 'S';
    }
    if (angle > 155) {
      return 'U';
    }
    if (angle < 65) {
      return cross > 0 ? 'E' : 'Q';
    }
    return cross > 0 ? 'R' : 'L';
  }

  static String commandLabel(String command) {
    return switch (command) {
      'S' => 'S',
      'Q' => 'Q shallow left',
      'E' => 'E shallow right',
      'L' => 'L left',
      'R' => 'R right',
      'U' => 'U turn',
      'X' => 'X stop',
      _ => command,
    };
  }
}
