import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_math/visual_math.dart';

Future<void> _selectCategory(WidgetTester tester, String category) async {
  await tester.ensureVisible(find.byTooltip('全部符号分类'));
  await tester.tap(find.byTooltip('全部符号分类'));
  await tester.pumpAndSettle();
  final panel = find.byType(AlertDialog);
  final item = find.descendant(of: panel, matching: find.text(category));
  final list = find
      .descendant(of: panel, matching: find.byType(Scrollable))
      .last;
  await tester.scrollUntilVisible(item, 80, scrollable: list);
  await tester.pumpAndSettle();
  await tester.tap(item.last);
  await tester.pumpAndSettle();
}

Future<void> _pumpKeyboard(
  WidgetTester tester,
  List<String> commands, {
  double width = 320,
  double height = 400,
  bool enabled = true,
  bool persistenceEnabled = true,
  String preferenceNamespace = '',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            height: height,
            child: MathKeyboard(
              activeLabel: '公式 1',
              enabled: enabled,
              persistenceEnabled: persistenceEnabled,
              preferenceNamespace: preferenceNamespace,
              onDismiss: () {},
              onPlot: () {},
              onCommand: (kind, value) async => commands.add('$kind:$value'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('common first page swaps the operator and function columns', (
    tester,
  ) async {
    final commands = <String>[];
    await _pumpKeyboard(tester, commands);

    final arithmetic = [
      find.byTooltip('加法'),
      find.byTooltip('减法'),
      find.byTooltip('乘法'),
      find.byTooltip('除法'),
    ];
    final operatorRects = arithmetic.map(tester.getRect).toList();
    expect(operatorRects.map((rect) => rect.left).toSet(), hasLength(1));
    for (var index = 1; index < operatorRects.length; index++) {
      expect(
        operatorRects[index].top,
        greaterThan(operatorRects[index - 1].top),
      );
    }

    final fraction = tester.getRect(find.byTooltip('分数：选区放入分子'));
    final power = tester.getRect(find.byTooltip('幂：进入指数'));
    final root = tester.getRect(find.byTooltip(r'\sqrt{x}'));
    final parentheses = tester.getRect(find.byTooltip(r'\left(x\right)'));
    final functionRects = [fraction, power, root, parentheses];
    expect(functionRects.map((rect) => rect.left).toSet(), hasLength(1));
    expect(functionRects.first.left, lessThan(operatorRects.first.left));
    for (var index = 0; index < functionRects.length; index++) {
      expect(functionRects[index].top, operatorRects[index].top);
    }

    final equals = tester.getRect(find.byTooltip('等于'));
    expect(equals.top, operatorRects.last.top);
    expect(
      equals.left,
      closeTo((operatorRects.first.left + functionRects.first.left) / 2, 1),
    );
    expect(
      tester.getRect(find.byTooltip('7')).left,
      greaterThan(operatorRects.first.left),
    );
    expect(find.text('1/2'), findsOneWidget);

    await _selectCategory(tester, '微积分');
    expect(find.text('1/2'), findsOneWidget);
    expect(find.byTooltip(r'\nabla'), findsNothing);
    await tester.drag(find.byTooltip(r'\sum'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    expect(find.byTooltip(r'\nabla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category order is merged, draggable, selected, and persisted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'math_keyboard_category_order_v1': ['函数', 'missing-category', '常用', '函数'],
    });
    final commands = <String>[];
    await _pumpKeyboard(tester, commands);
    await tester.pumpAndSettle();

    List<String> chipOrder() => tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((chip) => (chip.label as Text).data!)
        .toList();

    expect(chipOrder().take(3), ['函数', '常用', '字母']);
    await tester.tap(find.byTooltip('全部符号分类'));
    await tester.pumpAndSettle();
    final dialogRect = tester.getRect(find.byType(AlertDialog));
    final screenCenter = tester.getCenter(find.byType(Scaffold));
    expect(dialogRect.center.dx, closeTo(screenCenter.dx, 1));
    expect(dialogRect.center.dy, closeTo(screenCenter.dy, 1));
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('category-row-常用')))
          .selected,
      isTrue,
    );

    await tester.drag(
      find.byKey(const ValueKey('category-order-handle-函数')),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    final savedOrder = preferences.getStringList(
      'math_keyboard_category_order_v1',
    )!;
    expect(savedOrder, hasLength(14));
    expect(savedOrder.toSet(), hasLength(14));
    expect(savedOrder, isNot(contains('missing-category')));
    expect(savedOrder.first, isNot('函数'));

    await tester.tap(find.text('常用').last);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await _pumpKeyboard(tester, commands);
    await tester.pumpAndSettle();
    expect(chipOrder(), savedOrder);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category order uses the workspace namespace and can be disabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'visual_math.first.math_keyboard_category_order_v1': ['函数'],
      'visual_math.second.math_keyboard_category_order_v1': ['字母'],
    });
    final commands = <String>[];
    await _pumpKeyboard(tester, commands, preferenceNamespace: 'second');
    await tester.pumpAndSettle();
    final chipOrder = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((chip) => (chip.label as Text).data!)
        .toList();
    expect(chipOrder.first, '字母');

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await _pumpKeyboard(
      tester,
      commands,
      preferenceNamespace: 'isolated',
      persistenceEnabled: false,
    );
    await tester.tap(find.byTooltip('全部符号分类'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('category-order-handle-常用')),
      const Offset(0, 100),
    );
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getStringList(
        'visual_math.isolated.math_keyboard_category_order_v1',
      ),
      isNull,
    );
  });

  testWidgets('reordering keeps the selected category visible in the strip', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'math_keyboard_category_order_v1': [
        '字母',
        '指数/对数',
        '函数',
        '常量',
        '括号/区间',
        '关系',
        '希腊字母',
        '希腊变体',
        '微积分',
        '集合/逻辑',
        '矩阵',
        '箭头',
        '样式',
        '常用',
      ],
    });
    final commands = <String>[];
    await _pumpKeyboard(tester, commands);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('全部符号分类'));
    await tester.pumpAndSettle();
    final panel = find.byType(AlertDialog);
    final selectedRow = find.byKey(const ValueKey('category-row-常用'));
    final list = find
        .descendant(of: panel, matching: find.byType(Scrollable))
        .last;
    await tester.scrollUntilVisible(selectedRow, 80, scrollable: list);
    await tester.drag(
      find.byKey(const ValueKey('category-order-handle-常用')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();

    final chip = find
        .ancestor(of: find.text('常用').first, matching: find.byType(ChoiceChip))
        .first;
    final chipRect = tester.getRect(chip);
    final keyboard = tester.getRect(find.byType(MathKeyboard));
    expect(chipRect.left, greaterThanOrEqualTo(keyboard.left));
    expect(chipRect.right, lessThanOrEqualTo(keyboard.right - 44));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'category order dialog keeps its actions reachable on short screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final commands = <String>[];
      await _pumpKeyboard(tester, commands, width: 320, height: 130);
      await tester.tap(find.byTooltip('全部符号分类'));
      await tester.pumpAndSettle();

      final dialog = tester.getRect(find.byType(AlertDialog));
      final done = tester.getRect(find.text('完成'));
      expect(dialog.top, greaterThanOrEqualTo(0));
      expect(dialog.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
      expect(done.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large set operators retain bound and operand template slots', (
    tester,
  ) async {
    final commands = <String>[];
    await _pumpKeyboard(tester, commands);
    await _selectCategory(tester, '集合/逻辑');
    await tester.drag(find.byTooltip(r'\in'), const Offset(-100, 0));
    await tester.pumpAndSettle();

    for (final symbol in [r'\bigcup', r'\bigcap', r'\coprod']) {
      await tester.tap(find.byTooltip(symbol));
    }

    expect(commands, [
      r'insert:\bigcup_{#?}^{#?}#0',
      r'insert:\bigcap_{#?}^{#?}#0',
      r'insert:\coprod_{#?}^{#?}#0',
    ]);
  });

  testWidgets(
    'inverse keys use a-prefix names and insert parser-compatible LaTeX',
    (tester) async {
      final commands = <String>[];
      await _pumpKeyboard(tester, commands);
      await _selectCategory(tester, '函数');

      expect(
        {
          for (final input in mathUnaryInputs.where(
            (input) => ['asin', 'acos', 'atan'].contains(input.name),
          ))
            input.name: input.label,
        },
        {
          'asin': r'\operatorname{asin}',
          'acos': r'\operatorname{acos}',
          'atan': r'\operatorname{atan}',
        },
      );
      for (final label in ['asin（角度用弧度）', 'acos（角度用弧度）', 'atan（角度用弧度）']) {
        expect(find.byTooltip(label), findsOneWidget);
      }

      final inverseSine = find.byTooltip('asin（角度用弧度）');
      expect(inverseSine, findsOneWidget);
      await tester.tap(inverseSine);
      expect(commands, [r'insert:\arcsin\left(#0\right)']);

      await tester.drag(find.byTooltip('sin（角度用弧度）'), const Offset(-100, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byTooltip('sqrt'), const Offset(-100, 0));
      await tester.pumpAndSettle();
      for (final label in [
        'acot（公式排版）',
        'asec（公式排版）',
        'acsc（公式排版）',
        'asinh（公式排版）',
        'acosh（公式排版）',
        'atanh（公式排版）',
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
      }
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Latin QWERTY shows all letters at $width with persistent Shift and pinned navigation',
      (tester) async {
        final commands = <String>[];
        await _pumpKeyboard(tester, commands, width: width);
        await _selectCategory(tester, '字母');
        final keyboard = tester.getRect(find.byType(MathKeyboard));
        final navigation = tester.getRect(find.byTooltip('光标右移'));
        final rowTops = <double>[];
        for (final row in ['qwertyuiop', 'asdfghjkl', 'zxcvbnm']) {
          final rects = [
            for (final letter in row.split(''))
              tester.getRect(find.byTooltip(letter)),
          ];
          rowTops.add(rects.first.top);
          for (var index = 0; index < rects.length; index++) {
            final rect = rects[index];
            expect(rect.top, rects.first.top);
            expect(rect.height, 44);
            expect(rect.left, greaterThanOrEqualTo(keyboard.left));
            expect(rect.right, lessThanOrEqualTo(keyboard.right));
            expect(rect.bottom, lessThanOrEqualTo(navigation.top));
            if (index > 0)
              expect(rect.left, greaterThan(rects[index - 1].right));
            await tester.tap(find.byTooltip(row[index]));
          }
        }
        expect(rowTops[0], lessThan(rowTops[1]));
        expect(rowTops[1], lessThan(rowTops[2]));
        expect(commands, [
          for (final letter in 'qwertyuiopasdfghjklzxcvbnm'.split(''))
            'insert:$letter',
        ]);
        commands.clear();
        final shift = find.byKey(const ValueKey('math-keyboard-shift'));
        final backspace = find.byTooltip('⌫');
        expect(tester.getRect(shift).top, rowTops.last);
        expect(tester.getRect(backspace).top, rowTops.last);
        final semantics = tester.ensureSemantics();
        expect(
          tester.getSemantics(shift),
          matchesSemantics(
            label: 'Shift',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
          ),
        );
        await tester.tap(shift);
        await tester.pump();
        expect(
          tester.getSemantics(shift),
          matchesSemantics(
            label: 'Shift',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasToggledState: true,
            isToggled: true,
            hasTapAction: true,
          ),
        );
        expect(find.byTooltip('Shift：大写已开启，切换小写'), findsOneWidget);
        await tester.tap(find.byTooltip('Q'));
        await tester.tap(find.byTooltip('M'));
        await tester.tap(backspace);
        await tester.tap(find.byTooltip('3'));
        await tester.tap(find.text('上一项'));
        await tester.tap(find.text('下一项'));
        await _selectCategory(tester, '函数');
        await tester.tap(find.byTooltip('7'));
        await _selectCategory(tester, '字母');
        await tester.tap(find.byTooltip('Q'));
        await _selectCategory(tester, '希腊字母');
        await tester.tap(find.byTooltip('Alpha'));
        await _selectCategory(tester, '字母');
        await tester.tap(shift);
        await tester.pump();
        await tester.tap(find.byTooltip('q'));
        expect(commands, [
          'insert:Q',
          'insert:M',
          'command:deleteBackward',
          'insert:3',
          'previous:',
          'next:',
          'insert:7',
          'insert:Q',
          r'insert:\Alpha',
          'insert:q',
        ]);
        expect(tester.getRect(find.byTooltip('光标右移')), navigation);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'Greek page swipes preserve Shift slots and reset on category changes',
    (tester) async {
      final commands = <String>[];
      await _pumpKeyboard(tester, commands);
      await _selectCategory(tester, '希腊字母');
      expect(find.text('希腊大写'), findsNothing);
      expect(find.text('1/2'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('1/2'), matching: find.byType(TextButton)),
        findsNothing,
      );
      await tester.drag(find.byTooltip('alpha'), const Offset(-100, 0));
      await tester.pumpAndSettle();
      final firstSlot = tester.getRect(find.byTooltip('nu'));
      const secondPage = [
        'nu',
        'xi',
        'omicron',
        'pi',
        'rho',
        'sigma',
        'tau',
        'upsilon',
        'phi',
        'chi',
        'psi',
        'omega',
      ];
      for (final name in secondPage) {
        await tester.tap(find.byTooltip(name));
      }
      final shift = find.byKey(const ValueKey('math-keyboard-shift'));
      await tester.tap(shift);
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      expect(tester.getRect(find.byTooltip('Nu')), firstSlot);
      for (final name in secondPage) {
        await tester.tap(
          find.byTooltip('${name[0].toUpperCase()}${name.substring(1)}'),
        );
      }
      await tester.tap(shift);
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      expect(tester.getRect(find.byTooltip('nu')), firstSlot);
      await tester.tap(find.byTooltip('nu'));
      expect(commands, [
        for (final name in secondPage) 'insert:\\$name',
        for (final name in secondPage)
          'insert:\\${name[0].toUpperCase()}${name.substring(1)}',
        r'insert:\nu',
      ]);
      await tester.tap(shift);
      await tester.pump();
      await _selectCategory(tester, '希腊变体');
      await tester.tap(find.byTooltip('varkappa'));
      await _selectCategory(tester, '希腊字母');
      expect(find.text('1/2'), findsOneWidget);
      await tester.tap(find.byTooltip('Alpha'));
      expect(commands.sublist(commands.length - 2), [
        r'insert:\varkappa',
        r'insert:\Alpha',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short Latin keyboard scrolls letters while navigation stays pinned',
    (tester) async {
      final commands = <String>[];
      await _pumpKeyboard(tester, commands, height: 90);
      await _selectCategory(tester, '字母');
      final right = find.byTooltip('光标右移');
      final before = tester.getRect(right);
      final scrollable = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        find.byTooltip('q'),
        40,
        scrollable: scrollable,
      );
      await tester.tap(find.byTooltip('q'));
      await tester.scrollUntilVisible(
        find.byTooltip('⌫'),
        40,
        scrollable: scrollable,
      );
      await tester.tap(find.byTooltip('⌫'));
      await tester.tap(right);
      expect(commands, [
        'insert:q',
        'command:deleteBackward',
        'navigate:right',
      ]);
      expect(tester.getRect(right), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category directory reaches logs and hidden Greek keys without losing numeric positions',
    (tester) async {
      final commands = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 320,
                height: 220,
                child: MathKeyboard(
                  activeLabel: '公式 1',
                  onDismiss: () {},
                  onPlot: () {},
                  onCommand: (kind, value) async =>
                      commands.add('$kind:$value'),
                ),
              ),
            ),
          ),
        ),
      );
      final seven = find.byTooltip('7');
      final before = tester.getRect(seven);
      await _selectCategory(tester, '指数/对数');
      await tester.tap(find.byTooltip('自然对数 ln'));
      await tester.tap(seven);
      expect(tester.getRect(seven), before);
      expect(commands, [r'insert:\ln\left(#0\right)', 'insert:7']);
      await _selectCategory(tester, '希腊字母');
      final selectedTab = tester.getRect(
        find.ancestor(of: find.text('希腊字母'), matching: find.byType(ChoiceChip)),
      );
      final keyboard = tester.getRect(find.byType(MathKeyboard));
      expect(selectedTab.left, greaterThanOrEqualTo(keyboard.left));
      expect(selectedTab.right, lessThanOrEqualTo(keyboard.right - 44));
      expect(tester.getRect(seven), before);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('math-keyboard-shift')),
        40,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('math-keyboard-shift')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byTooltip('Alpha'),
        -40,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.tap(find.byTooltip('Alpha'));
      expect(commands.last, r'insert:\Alpha');
      await tester.drag(find.byTooltip('Alpha'), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(tester.getRect(seven), before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'very short keyboard scrolls controls and keys without hiding arrows',
    (tester) async {
      final commands = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 320,
                height: 90,
                child: MathKeyboard(
                  activeLabel: '公式 1',
                  onDismiss: () {},
                  onPlot: () {},
                  onCommand: (kind, value) async =>
                      commands.add('$kind:$value'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final right = find.byTooltip('光标右移');
      final before = tester.getRect(right);
      await tester.scrollUntilVisible(
        find.byTooltip('7'),
        60,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.tap(find.byTooltip('7'));
      await tester.tap(right);
      expect(tester.getRect(right), before);
      expect(commands, ['insert:7', 'navigate:right']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'navigation stays visible while keys scroll in a short viewport',
    (tester) async {
      final commands = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 320,
                height: 180,
                child: MathKeyboard(
                  activeLabel: '公式 1',
                  onDismiss: () {},
                  onPlot: () {},
                  onCommand: (kind, value) async {
                    commands.add('$kind:$value');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final right = find.byTooltip('光标右移');
      final before = tester.getRect(right);
      await tester.drag(find.byTooltip('7'), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(tester.getRect(right), before);
      await tester.tap(right);
      await tester.tap(find.byTooltip('光标上移 / 切换上层'));
      await tester.tap(find.byTooltip('退出当前结构'));
      expect(commands, ['navigate:right', 'navigate:up', 'navigate:out']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('alphabet category keeps previous and next navigation usable', (
    tester,
  ) async {
    final commands = <String>[];
    await _pumpKeyboard(tester, commands);
    await _selectCategory(tester, '字母');

    await tester.tap(find.text('上一项'));
    await tester.tap(find.text('下一项'));

    expect(commands, ['previous:', 'next:']);
  });

  testWidgets('loading editor disables insertion and structural navigation', (
    tester,
  ) async {
    final commands = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathKeyboard(
            enabled: false,
            activeLabel: '公式 1',
            onDismiss: () {},
            onPlot: () {},
            onCommand: (kind, value) async {
              commands.add('$kind:$value');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('7'));
    await tester.tap(find.text('上一项'));
    await tester.tap(find.text('下一项'));
    await tester.tap(find.byTooltip('撤销'));
    expect(commands, isEmpty);
    await _selectCategory(tester, '字母');
    await tester.tap(find.byTooltip('q'));
    await tester.tap(find.byKey(const ValueKey('math-keyboard-shift')));
    await tester.tap(find.byTooltip('光标右移'));
    expect(find.byTooltip('q'), findsOneWidget);
    expect(find.byTooltip('Q'), findsNothing);
    expect(commands, isEmpty);
  });
  testWidgets('changing categories keeps numeric keys and navigation usable', (
    tester,
  ) async {
    final commands = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathKeyboard(
            activeLabel: '公式 1',
            onDismiss: () {},
            onPlot: () {},
            onCommand: (kind, value) async {
              commands.add('$kind:$value');
            },
          ),
        ),
      ),
    );
    final seven = find.descendant(
      of: find.byTooltip('7'),
      matching: find.byType(FilledButton),
    );
    final before = tester.getRect(seven);
    await tester.tap(seven);
    await _selectCategory(tester, '函数');
    expect(tester.getRect(seven), before);
    await tester.tap(find.text('下一项'));
    await tester.tap(find.byTooltip('⌫'));
    expect(commands, ['insert:7', 'next:', 'command:deleteBackward']);
    expect(tester.takeException(), isNull);
  });
}
