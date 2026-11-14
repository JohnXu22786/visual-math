import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  test('ellipse rejects a zero minor radius and remains recoverable', () {
    final construction = ConstructionState(tool: ConstructionTool.ellipse);
    construction.addPoint(Point3D.origin);
    construction.addPoint(const Point3D(1, 0, 0));

    expect(
      construction.addPoint(const Point3D(2, 0, 0)),
      ConstructionAction.awaitInput,
    );
    expect(construction.points, [Point3D.origin, const Point3D(1, 0, 0)]);
    expect(construction.currentInstruction, contains('短轴长度必须大于 0'));
    expect(construction.result, isNull);

    expect(
      construction.addPoint(const Point3D(0, 0.5, 0)),
      ConstructionAction.complete,
    );
    expect(construction.result!.conic!.quadraticY, 4);
    expect(
      construction.result!.vertices.every(
        (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
      ),
      isTrue,
    );
  });

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

  test('angle measurement handles direction subtraction overflow', () {
    final state = ConstructionState(tool: ConstructionTool.angle);

    state.addPoint(const Point3D(1e308, 0, 0));
    state.addPoint(const Point3D(-1e308, 0, 0));
    state.addPoint(const Point3D(-1e308, 1, 0));

    expect(state.result?.label, '角度 90.00°');
  });

  test('plane construction handles direction subtraction overflow', () {
    final state = ConstructionState(tool: ConstructionTool.plane);

    expect(
      state.addPoint(const Point3D(-1e308, 0, 0)),
      ConstructionAction.advanceStep,
    );
    expect(
      state.addPoint(const Point3D(1e308, 0, 0)),
      ConstructionAction.advanceStep,
    );
    expect(
      state.addPoint(const Point3D(-1e308, 1, 0)),
      ConstructionAction.complete,
    );

    expect(state.result?.type, Object3DType.plane);
    expect(state.result?.planeC, closeTo(1, 1e-10));
    expect(state.result?.planeD, closeTo(0, 1e-10));
  });

  test('general plane construction handles direction subtraction overflow', () {
    final state = ConstructionState(tool: ConstructionTool.generalPlane);

    state.addPoint(const Point3D(-1e308, 0, 0));
    state.addPoint(const Point3D(1e308, 0, 0));

    expect(state.result?.type, Object3DType.plane);
    expect(state.result?.planeA, closeTo(1, 1e-10));
    expect(state.result?.planeD, closeTo(-1e308, 1e293));
  });

  test('perpendicular plane handles direction subtraction overflow', () {
    final state = ConstructionState(tool: ConstructionTool.perpendicularPlane);

    state.addPoint(Point3D.origin);
    state.addPoint(const Point3D(1, 0, 0));
    state.addPoint(const Point3D(0, 1, 0));
    state.addPoint(const Point3D(-1e308, 0, 0));
    state.addPoint(const Point3D(1e308, 0, 0));

    expect(state.result?.type, Object3DType.plane);
    expect(state.result?.planeB.abs(), closeTo(1, 1e-10));
  });

  test(
    'rotation axis handles subtraction overflow between finite endpoints',
    () {
      final state = ConstructionState(tool: ConstructionTool.rotation);

      state.addPoint(const Point3D(-1e308, 1, 0));
      state.addPoint(const Point3D(-1e308, 0, 0));
      state.addPoint(const Point3D(1e308, 0, 0));
      state.addPoint(const Point3D(-1e308, 0, 1));

      final result = state.result;
      expect(result?.type, Object3DType.point);
      expect(result?.point.x.isFinite, isTrue);
      expect(result?.point.y, closeTo(0, 1e-10));
      expect(result?.point.z, closeTo(1, 1e-10));
    },
  );

  test('dilation direction handles subtraction overflow', () {
    final state = ConstructionState(tool: ConstructionTool.dilation);

    state.addPoint(const Point3D(1e308, 0, 0));
    state.addPoint(const Point3D(-1e308, 0, 0));
    state.addPoint(const Point3D(-1e308, 1e308, 0));

    final result = state.result;
    expect(result?.point.x.isFinite, isTrue);
    expect(result?.point.x, closeTo(0, 1e-10));
    expect(result?.point.y, closeTo(0, 1e-10));
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
