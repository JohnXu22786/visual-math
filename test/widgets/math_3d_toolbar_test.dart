import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  testWidgets('initially selected tool is visible in a narrow toolbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Math3DToolbar(
            activeTool: ConstructionTool.regularPolygon,
            onToolSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tool = find.text('正多边形');
    final rect = tester.getRect(tool);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(390));
  });

  testWidgets('command feedback follows the current label resolver', (
    tester,
  ) async {
    var language = 'English';
    final selected = <ConstructionTool>[];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Math3DToolbar(
                activeTool: ConstructionTool.move,
                onToolSelected: selected.add,
                labelResolver: (source) => '$language:$source',
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('English:编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('English:切换场景中对象标签的显示'));
    await tester.pump();
    expect(selected.last, ConstructionTool.showHideLabels);
    expect(find.text('English:命令：English:切换场景中对象标签的显示'), findsOneWidget);

    update(() => language = 'French');
    await tester.pump();
    expect(find.text('French:命令：French:切换场景中对象标签的显示'), findsOneWidget);

    await tester.tap(find.byTooltip('French:切换到标准等轴测视图'));
    await tester.pump();
    expect(selected.last, ConstructionTool.viewDirection);
    expect(find.text('French:命令：French:切换到标准等轴测视图'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('French:命令：French:切换到标准等轴测视图'), findsNothing);
  });

  testWidgets(
    'group selection creates a regular polygon and changing sides resets partial input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var tool = ConstructionTool.point;
      var sides = 6;
      var instruction = '';
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                return Column(
                  children: [
                    Math3DToolbar(
                      activeTool: tool,
                      instruction: instruction,
                      polygonSides: sides,
                      onPolygonSidesChanged: (value) =>
                          update(() => sides = value),
                      onToolSelected: (value) => update(() => tool = value),
                    ),
                    Expanded(
                      child: MathCanvas3D(
                        key: key,
                        currentTool: tool,
                        onToolInstruction: (value) =>
                            update(() => instruction = value),
                        polygonSides: sides,
                        onObjectCreated: (object) => key.currentState!
                            .setObjects([...key.currentState!.objects, object]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final lineAndPolygonCategory = find.text('直线与多边形');
      await tester.ensureVisible(lineAndPolygonCategory);
      await tester.tap(lineAndPolygonCategory);
      await tester.pumpAndSettle();
      final regularPolygonTool = find.text('正多边形');
      await tester.ensureVisible(regularPolygonTool);
      await tester.tap(regularPolygonTool);
      await tester.pumpAndSettle();
      final canvasRect = tester.getRect(find.byType(MathCanvas3D));
      final start = canvasRect.center;
      await tester.tapAt(start);
      await tester.pump();
      expect(key.currentState!.constructionState!.points, hasLength(1));
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.pumpAndSettle();
      expect(key.currentState!.constructionState!.points, isEmpty);
      await tester.tapAt(start);
      await tester.pump();
      await tester.tapAt(start + const Offset(65, 0));
      await tester.pump();
      expect(key.currentState!.objects.single.vertices, hasLength(5));
      await tester.tap(find.byTooltip('结束工具，返回移动'));
      await tester.pumpAndSettle();
      expect(key.currentState!.activeTool, ConstructionTool.move);
      expect(tester.takeException(), isNull);
    },
  );
}
