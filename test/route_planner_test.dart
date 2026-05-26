import 'package:flutter_test/flutter_test.dart';
import 'package:robot_bluetooth_controller/models/robot_graph.dart';
import 'package:robot_bluetooth_controller/models/route_planner.dart';

void main() {
  test('calculates measured shortest showcase route', () {
    final plan = RoutePlanner.calculate(
      previousNode: startGuideNode,
      startNode: showcaseStartNode,
      destinationNode: showcaseFinishNode,
      finishExit: true,
    );

    expect(plan.path, [1, 2, 4, 5, 10, 12, 14, 16, 17, 21]);
    expect(plan.commands.join(), 'SRLEESSLRX');
    expect(plan.finishAction, 'L');
  });

  test('calculates longest simple showcase route', () {
    final plan = RoutePlanner.calculate(
      previousNode: startGuideNode,
      startNode: showcaseStartNode,
      destinationNode: showcaseFinishNode,
      preferLongest: true,
      finishExit: true,
    );

    expect(plan.path, [
      1,
      7,
      8,
      9,
      4,
      5,
      3,
      6,
      10,
      12,
      11,
      13,
      14,
      16,
      15,
      19,
      20,
      21,
    ]);
    expect(plan.commands.join(), 'RLSLRQRRQRLLRRLSLX');
    expect(plan.finishAction, 'S');
  });
}
