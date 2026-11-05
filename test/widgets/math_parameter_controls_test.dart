import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

Finder field(String label) => find.widgetWithText(TextFormField, label);

Widget controls(
  Map<String, MathParameter> parameters,
  void Function(String, MathParameter) onChanged,
) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: Scaffold(
    body: ListView(
      children: [
        MathParameterControls(parameters: parameters, onChanged: onChanged),
      ],
    ),
  ),
);

Widget liveControls(MathParameter initial, List<double> changes) {
  var parameter = initial;
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => ListView(
          children: [
            MathParameterControls(
              parameters: {'A': parameter},
              onChanged: (_, updated) {
                changes.add(updated.value);
                setState(() => parameter = updated);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> focusSlider(WidgetTester tester) async {
  final focus = find.descendant(
    of: find.byType(Slider),
    matching: find.byType(FocusableActionDetector),
  );
  tester.widget<FocusableActionDetector>(focus).focusNode!.requestFocus();
  await tester.pumpAndSettle();
}

SemanticsNode sliderSemantics() =>
    find.semantics.byFlag(SemanticsFlag.isSlider).evaluate().single;

Future<void> withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final semantics = tester.ensureSemantics();
  try {
    await body();
  } finally {
    semantics.dispose();
  }
}

void main() {
  testWidgets(
    'parameter accessibility announces exact typed values between ticks',
    (tester) async => withSemantics(tester, () async {
      await tester.pumpWidget(
        controls({
          'A': MathParameter(value: 0.42, min: -1, max: 1, step: 0.3),
        }, (_, __) {}),
      );
      expect(sliderSemantics().getSemanticsData().value, 'A = 0.42');
    }),
  );

  testWidgets('parameter keyboard steps advance through the short endpoint', (
    tester,
  ) async {
    final changes = <double>[];
    await tester.pumpWidget(
      liveControls(MathParameter(value: 0, min: 0, max: 1, step: 0.3), changes),
    );
    await focusSlider(tester);
    for (final expected in [0.3, 0.6, 0.9, 1.0]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(changes.last, closeTo(expected, 1e-12));
    }
    final count = changes.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(changes, hasLength(count));
    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      closeTo(1.0, 1e-12),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(changes.last, closeTo(0.9, 1e-12));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(changes.last, closeTo(0.6, 1e-12));
  });

  testWidgets(
    'parameter ordinary labels stay readable after a default slider gesture',
    (tester) async => withSemantics(tester, () async {
      final changes = <double>[];
      await tester.pumpWidget(liveControls(MathParameter(value: 0), changes));
      final bounds = tester.getRect(find.byType(Slider));
      await tester.tapAt(
        Offset(bounds.left + 24 + (bounds.width - 48) * 0.51, bounds.center.dy),
      );
      await tester.pumpAndSettle();
      expect(changes.last, closeTo(0.1, 1e-12));
      expect(sliderSemantics().getSemanticsData().value, 'A = 0.1');
      expect(find.text('A = 0.1'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).label, '0.1');
      expect(sliderSemantics().getSemanticsData().increasedValue, 'A = 0.2');
      await tester.tap(find.byTooltip('设置参数 A'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field('数值')).controller!.text, '0.1');
    }),
  );

  testWidgets(
    'parameter ordinary labels stay readable after a fractional semantic step',
    (tester) async => withSemantics(tester, () async {
      final changes = <double>[];
      await tester.pumpWidget(
        liveControls(
          MathParameter(value: -0.2, min: -0.7, max: 1.2, step: 0.25),
          changes,
        ),
      );
      final node = sliderSemantics();
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(changes.last, closeTo(0.05, 1e-12));
      expect(sliderSemantics().getSemanticsData().value, 'A = 0.05');
      expect(find.text('A = 0.05'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).label, '0.05');
      expect(sliderSemantics().getSemanticsData().increasedValue, 'A = 0.3');
    }),
  );

  testWidgets(
    'parameter screen reader steps announce and use the grid',
    (tester) async => withSemantics(tester, () async {
      final changes = <double>[];
      await tester.pumpWidget(
        liveControls(
          MathParameter(value: -0.7, min: -0.7, max: 1.2, step: 0.25),
          changes,
        ),
      );
      for (final expected in [-0.45, -0.2, 0.05, 0.3, 0.55, 0.8, 1.05, 1.2]) {
        final node = sliderSemantics();
        final announcedNext = node.getSemanticsData().increasedValue;
        expect(announcedNext, startsWith('A = '));
        expect(
          double.parse(announcedNext.replaceFirst('A = ', '')),
          closeTo(expected, 1e-12),
        );
        node.owner!.performAction(node.id, SemanticsAction.increase);
        await tester.pumpAndSettle();
        expect(changes.last, closeTo(expected, 1e-12));
        expect(sliderSemantics().getSemanticsData().value, announcedNext);
      }
      final last = sliderSemantics();
      expect(
        last.getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );
      expect(last.getSemanticsData().decreasedValue, 'A = 1.05');
      last.owner!.performAction(last.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(changes.last, closeTo(1.05, 1e-12));
    }),
  );

  testWidgets(
    'parameter keyboard preserves typed values until adjustment',
    (tester) async => withSemantics(tester, () async {
      final changes = <double>[];
      await tester.pumpWidget(
        liveControls(
          MathParameter(value: 0.42, min: 0, max: 1, step: 0.3),
          changes,
        ),
      );
      await focusSlider(tester);
      expect(changes, isEmpty);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.42);
      expect(sliderSemantics().getSemanticsData().value, 'A = 0.42');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(changes.last, closeTo(0.6, 1e-12));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(changes.last, closeTo(0.3, 1e-12));
    }),
  );

  testWidgets('parameter large grid keyboard visits every representable tick', (
    tester,
  ) async {
    const min = 10000000000000000.0;
    final changes = <double>[];
    await tester.pumpWidget(
      liveControls(
        MathParameter(value: min, min: min, max: min + 10, step: 3),
        changes,
      ),
    );
    await focusSlider(tester);
    for (final offset in [4, 6, 8, 10]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(changes.last - min, offset);
    }
    final count = changes.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(changes, hasLength(count));
    for (final offset in [8, 6, 4, 0]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(changes.last - min, offset);
    }
  });

  testWidgets(
    'parameter large grid screen reader visits every representable tick',
    (tester) async => withSemantics(tester, () async {
      const min = 10000000000000000.0;
      final changes = <double>[];
      await tester.pumpWidget(
        liveControls(
          MathParameter(value: min, min: min, max: min + 10, step: 3),
          changes,
        ),
      );
      for (final offset in [4, 6, 8, 10]) {
        final node = sliderSemantics();
        node.owner!.performAction(node.id, SemanticsAction.increase);
        await tester.pumpAndSettle();
        expect(changes.last - min, offset);
      }
      expect(
        sliderSemantics().getSemanticsData().hasAction(
          SemanticsAction.increase,
        ),
        isFalse,
      );
      for (final offset in [8, 6, 4, 0]) {
        final node = sliderSemantics();
        node.owner!.performAction(node.id, SemanticsAction.decrease);
        await tester.pumpAndSettle();
        expect(changes.last - min, offset);
      }
      expect(
        sliderSemantics().getSemanticsData().hasAction(
          SemanticsAction.decrease,
        ),
        isFalse,
      );
    }),
  );

  testWidgets(
    'parameter large grid announcements distinguish actual tick values',
    (tester) async => withSemantics(tester, () async {
      const min = 10000000000000000.0;
      final changes = <double>[];
      await tester.pumpWidget(
        liveControls(
          MathParameter(value: min, min: min, max: min + 10, step: 3),
          changes,
        ),
      );
      for (final offset in [4, 6, 8, 10]) {
        final node = sliderSemantics();
        expect(
          node.getSemanticsData().increasedValue,
          'A = ${(min + offset).toStringAsFixed(0)}',
        );
        node.owner!.performAction(node.id, SemanticsAction.increase);
        await tester.pumpAndSettle();
        expect(
          sliderSemantics().getSemanticsData().value,
          'A = ${(min + offset).toStringAsFixed(0)}',
        );
      }
    }),
  );

  testWidgets('parameter duplicate ticks do not stall keyboard decrease', (
    tester,
  ) async {
    const min = 10000000000000000.0;
    final changes = <double>[];
    await tester.pumpWidget(
      liveControls(
        MathParameter(value: min + 4, min: min, max: min + 10, step: 1.1),
        changes,
      ),
    );
    await focusSlider(tester);
    for (final offset in [2, 0]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).value - min, offset);
    }
    expect(changes.map((value) => value - min), [2, 0]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(changes, hasLength(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(changes.last - min, 2);
  });

  testWidgets(
    'parameter duplicate ticks retain semantic decrease action',
    (tester) async => withSemantics(tester, () async {
      const min = 10000000000000000.0;
      final changes = <double>[];
      await tester.pumpWidget(
        liveControls(
          MathParameter(value: min + 4, min: min, max: min + 10, step: 1.1),
          changes,
        ),
      );
      for (final offset in [2, 0]) {
        final node = sliderSemantics();
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.decrease),
          isTrue,
        );
        expect(
          node.getSemanticsData().decreasedValue,
          'A = ${(min + offset).toStringAsFixed(0)}',
        );
        node.owner!.performAction(node.id, SemanticsAction.decrease);
        await tester.pumpAndSettle();
        expect(changes.last - min, offset);
      }
      expect(
        sliderSemantics().getSemanticsData().hasAction(
          SemanticsAction.decrease,
        ),
        isFalse,
      );
    }),
  );

  testWidgets(
    'parameter fractional and typed announcements preserve actual values',
    (tester) async => withSemantics(tester, () async {
      for (final parameter in [
        MathParameter(
          value: 1e13 + 0.0625,
          min: 1e13,
          max: 1e13 + 1,
          step: 0.0625,
        ),
        MathParameter(
          value: -1e13 - 0.0625,
          min: -1e13 - 1,
          max: -1e13,
          step: 0.0625,
        ),
        MathParameter(value: 1.2345678901234567),
        MathParameter(value: -1.2345678901234567),
      ]) {
        await tester.pumpWidget(controls({'A': parameter}, (_, __) {}));
        final announced = sliderSemantics().getSemanticsData().value;
        expect(
          double.parse(announced.replaceFirst('A = ', '')),
          parameter.value,
        );
        expect(find.text('A = ${parameter.value}'), findsOneWidget);
        expect(
          tester.widget<Slider>(find.byType(Slider)).label,
          parameter.value.toString(),
        );
        await tester.tap(find.byTooltip('设置参数 A'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(field('数值')).controller!.text,
          parameter.value.toString(),
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }
    }),
  );

  testWidgets('parameter slider gestures quantize on the original step grid', (
    tester,
  ) async {
    final changes = <MathParameter>[];
    await tester.pumpWidget(
      controls({'A': MathParameter(value: 0, min: 0, max: 1, step: 0.3)}, (
        name,
        parameter,
      ) {
        expect(name, 'A');
        changes.add(parameter);
      }),
    );
    final slider = find.byType(Slider);
    final bounds = tester.getRect(slider);
    await tester.tapAt(Offset(bounds.right - 24, bounds.center.dy));
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(changes.last.value, 1);
    expect(changes.last.step, 0.3);
  });

  testWidgets('parameter invalid dialog retains edits without callbacks', (
    tester,
  ) async {
    final changes = <MathParameter>[];
    await tester.pumpWidget(
      controls({
        'A': MathParameter(),
      }, (_, parameter) => changes.add(parameter)),
    );
    await tester.tap(find.byTooltip('设置参数 A'));
    await tester.pumpAndSettle();
    await tester.enterText(field('数值'), '1.234');
    await tester.enterText(field('最小值'), '2');
    await tester.enterText(field('最大值'), '1');
    await tester.enterText(field('步长'), '0');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(changes, isEmpty);
    expect(find.text('最大值必须大于最小值'), findsOneWidget);
    expect(find.text('步长必须大于 0'), findsOneWidget);
    expect(tester.widget<TextFormField>(field('数值')).controller!.text, '1.234');
    expect(tester.widget<TextFormField>(field('最小值')).controller!.text, '2');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
  });

  testWidgets('parameter dialog applies bounds step and exact typed value', (
    tester,
  ) async {
    final changes = <MathParameter>[];
    await tester.pumpWidget(
      controls({
        'A': MathParameter(),
      }, (_, parameter) => changes.add(parameter)),
    );
    await tester.tap(find.byTooltip('设置参数 A'));
    await tester.pumpAndSettle();
    await tester.enterText(field('数值'), '0.42');
    await tester.enterText(field('最小值'), '-1');
    await tester.enterText(field('最大值'), '1');
    await tester.enterText(field('步长'), '0.3');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(changes, hasLength(1));
    expect(changes.single.value, 0.42);
    expect(changes.single.min, -1);
    expect(changes.single.max, 1);
    expect(changes.single.step, 0.3);
  });

  testWidgets(
    'parameter dialog rejects nonfinite entry and clamps valid bounds',
    (tester) async {
      final changes = <MathParameter>[];
      await tester.pumpWidget(
        controls({
          'A': MathParameter(value: 4),
        }, (_, parameter) => changes.add(parameter)),
      );
      await tester.tap(find.byTooltip('设置参数 A'));
      await tester.pumpAndSettle();
      await tester.enterText(field('数值'), 'NaN');
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.text('请输入有限数值'), findsOneWidget);
      expect(changes, isEmpty);
      await tester.enterText(field('数值'), '4');
      await tester.enterText(field('最大值'), '2');
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(changes.single.value, 2);
    },
  );

  testWidgets(
    'parameter narrow dialog scrolls above keyboard without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final changes = <MathParameter>[];
      await tester.pumpWidget(
        controls({
          'A': MathParameter(),
        }, (_, parameter) => changes.add(parameter)),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('设置参数 A'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scroll = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SingleChildScrollView),
      );
      await tester.drag(scroll.first, const Offset(0, -220));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('步长'));
      await tester.enterText(field('步长'), '0.25');
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(changes.single.step, 0.25);
    },
  );
}
