import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';
import 'package:visual_math_sdk_consumer/main.dart';

void main() {
  testWidgets('host embeds and updates both public canvases', (tester) async {
    await tester.pumpWidget(const ConsumerApp());
    await tester.pumpAndSettle();
    expect(find.byType(MathCanvas), findsOneWidget);
    await tester.tap(find.text('Plot x²'));
    await tester.pump();
    final graph = tester.state<MathCanvasState>(find.byType(MathCanvas));
    expect(graph.curvePoints, isNotEmpty);
    expect(
      graph.curvePoints.every(
        (point) => (point['y']! - point['x']! * point['x']!).abs() < 1e-8,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(find.byType(MathCanvas3D), findsOneWidget);
    final scene = tester.state<MathCanvas3DState>(find.byType(MathCanvas3D));
    expect(scene.objects.length, 2);
    expect(tester.takeException(), isNull);
  });
}
