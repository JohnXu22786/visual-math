import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';
import 'package:visual_math_sdk_consumer/main.dart';

void main() {
  testWidgets(
    'host updates a graph and reports invalid input without losing it',
    (tester) async {
      await tester.pumpWidget(const ConsumerApp());
      await tester.pumpAndSettle();
      expect(find.text('2D ready'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'x^2');
      await tester.tap(find.text('Plot'));
      await tester.pump();
      final graph = tester.state<MathCanvasState>(find.byType(MathCanvas));
      final points = graph.curvePoints;
      expect(points, isNotEmpty);
      expect(
        points.every((p) => (p['y']! - p['x']! * p['x']!).abs() < 1e-8),
        isTrue,
      );
      expect(find.text('Plot samples: ${points.length}'), findsOneWidget);
      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2D'));
      await tester.pumpAndSettle();
      expect(graph.curvePoints, equals(points));
      await tester.enterText(find.byType(TextField), 'sin(');
      await tester.tap(find.text('Plot'));
      await tester.pump();
      expect(find.byKey(const Key('plot-error')), findsOneWidget);
      expect(graph.curvePoints, equals(points));
      await tester.enterText(find.byType(TextField), 'x');
      await tester.tap(find.text('Plot'));
      await tester.pump();
      expect(find.byKey(const Key('plot-error')), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Plot'));
      await tester.pump();
      expect(find.text('Plot samples: 0'), findsOneWidget);
    },
  );

  testWidgets('host initializes and replaces a scene and disposes safely', (
    tester,
  ) async {
    await tester.pumpWidget(const ConsumerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(find.text('3D ready'), findsOneWidget);
    final scene = tester.state<MathCanvas3DState>(find.byType(MathCanvas3D));
    expect(scene.objects.length, 2);
    expect(find.text('Scene changes: 1'), findsOneWidget);
    await tester.tap(find.text('Replace scene'));
    await tester.pump();
    expect(scene.objects.length, 1);
    expect(find.text('Scene changes: 2'), findsOneWidget);
    await tester.tap(find.text('2D'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(scene.objects.length, 1);
    expect(find.text('Scene changes: 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
