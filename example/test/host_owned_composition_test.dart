import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';
import 'package:visual_math_example/main.dart';

void main() {
  testWidgets('opens the host-owned formula and parameter composition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: HostOwnedCompositionPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Host-owned controls'), findsOneWidget);
    expect(find.byType(MathFormulaField), findsOneWidget);
    expect(find.byType(MathParameterControls), findsOneWidget);
    expect(find.byType(MathCanvas), findsOneWidget);
    expect(find.byType(MathKeyboard), findsOneWidget);
    expect(find.text('a = 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
