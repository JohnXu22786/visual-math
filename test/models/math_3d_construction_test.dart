import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  test('angle measurement remains accurate for large finite vectors', () {
    final state = ConstructionState(tool: ConstructionTool.angle);

    expect(
      state.addPoint(const Point3D(1e155, 0, 0)),
      ConstructionAction.advanceStep,
    );
    expect(state.addPoint(Point3D.origin), ConstructionAction.advanceStep);
    state.addPoint(const Point3D(1e155, 1e155, 0));

    expect(state.result?.label, '角度 45.00°');
  });

  test('collinear plane points remain incomplete', () {
    final state = ConstructionState(tool: ConstructionTool.plane);

    expect(
      state.addPoint(const Point3D(0, 0, 0)),
      ConstructionAction.advanceStep,
    );
    expect(
      state.addPoint(const Point3D(1, 0, 0)),
      ConstructionAction.advanceStep,
    );
    expect(
      state.addPoint(const Point3D(2, 0, 0)),
      ConstructionAction.awaitInput,
    );

    expect(state.result, isNull);
    expect(state.points, hasLength(2));
  });

  test('zero radius sphere remains incomplete', () {
    final state = ConstructionState(tool: ConstructionTool.sphere);

    expect(state.addPoint(Point3D.origin), ConstructionAction.advanceStep);
    expect(state.addPoint(Point3D.origin), ConstructionAction.awaitInput);

    expect(state.result, isNull);
    expect(state.points, hasLength(1));
  });

  test('preview uses the current point without mutating construction', () {
    final state = ConstructionState(tool: ConstructionTool.line);
    state.addPoint(const Point3D(1, 2, 3));

    final preview = state.previewForPoint(const Point3D(4, 5, 6));

    expect(preview?.type, Object3DType.line);
    expect(state.points, hasLength(1));
  });
}
