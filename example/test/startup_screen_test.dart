import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math_example/main.dart';

void main() {
  testWidgets('shows startup screen before opening the existing example menu', (
    tester,
  ) async {
    await tester.pumpWidget(const VisualMathExampleApp());

    expect(find.text('Visual Math'), findsOneWidget);
    expect(find.text('Visual Math examples'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Visual Math examples'), findsOneWidget);
    expect(find.text('Standalone 2D canvas'), findsOneWidget);
  });
}
