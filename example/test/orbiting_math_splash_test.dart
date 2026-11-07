import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math_example/orbiting_math_splash.dart';

void main() {
  testWidgets('waits for full progress and exits with one nonlinear second', (
    tester,
  ) async {
    var progress = 0.0;
    final transitionComplete = ValueNotifier(false);

    Widget buildSplash() => MaterialApp(
      home: Stack(
        children: [
          const Scaffold(body: Text('existing homepage')),
          OrbitingMathSplash(
            progress: progress,
            onTransitionComplete: () => transitionComplete.value = true,
          ),
        ],
      ),
    );

    await tester.pumpWidget(buildSplash());

    await tester.pump(const Duration(seconds: 20));
    expect(find.text('existing homepage'), findsOneWidget);
    expect(transitionComplete.value, isFalse);
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);

    progress = 1;
    await tester.pumpWidget(buildSplash());
    await tester.pump(const Duration(milliseconds: 500));

    final splash = find.byType(OrbitingMathSplash);
    final opacity = tester
        .widget<Opacity>(
          find.descendant(of: splash, matching: find.byType(Opacity)).first,
        )
        .opacity;
    final scale = tester.widget<Transform>(
      find.descendant(of: splash, matching: find.byType(Transform)).first,
    );
    expect(opacity, greaterThan(.8));
    expect(opacity, lessThan(1));
    expect(1 - opacity, lessThan(.525));
    expect(
      scale.transform.getMaxScaleOnAxis(),
      closeTo(1 + 2.35 * (1 - opacity), .001),
    );
    expect(transitionComplete.value, isFalse);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      tester
          .widget<Opacity>(
            find.descendant(of: splash, matching: find.byType(Opacity)).first,
          )
          .opacity,
      0,
    );
    expect(transitionComplete.value, isTrue);
    transitionComplete.dispose();
  });
}
