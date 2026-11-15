import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  test('line, segment, and ray reject overflowing endpoint directions', () {
    for (final tool in [
      ConstructionTool.line,
      ConstructionTool.segment,
      ConstructionTool.ray,
    ]) {
      final state = ConstructionState(tool: tool);
      const start = Point3D(-1e308, 0, 0);

      expect(state.addPoint(start), ConstructionAction.advanceStep);
      expect(
        state.addPoint(const Point3D(1e308, 0, 0)),
        ConstructionAction.awaitInput,
      );
      expect(state.points, [start]);
      expect(state.result, isNull);

      expect(
        state.addPoint(const Point3D(-5e307, 0, 0)),
        ConstructionAction.complete,
      );
      expect(state.result?.type, Object3DType.line);
      expect(
        (state.result!.pointB.x - state.result!.pointA.x).isFinite,
        isTrue,
      );
    }
  });

  test(
    'cube rejects endpoints whose difference overflows before committing',
    () {
      final state = ConstructionState(tool: ConstructionTool.cube);
      const start = Point3D(-1e308, 0, 0);

      expect(state.addPoint(start), ConstructionAction.advanceStep);
      expect(
        state.addPoint(const Point3D(1e308, 0, 0)),
        ConstructionAction.awaitInput,
      );
      expect(state.points, [start]);
      expect(state.result, isNull);

      expect(
        state.addPoint(const Point3D(-5e307, 0, 0)),
        ConstructionAction.complete,
      );
      expect(
        state.result!.vertices.every(
          (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
        ),
        isTrue,
      );
    },
  );

  test('cube validates geometry with the supplied plane normal', () {
    final state = ConstructionState(tool: ConstructionTool.cube);
    const start = Point3D(1.55e308, -1.75e308, 0);

    expect(state.addPoint(start), ConstructionAction.advanceStep);
    expect(
      state.addPoint(
        const Point3D(1.7e308, -1.6e308, 0),
        workingPlaneNormal: const Vector3D(0, 0, -1),
      ),
      ConstructionAction.awaitInput,
    );
    expect(state.points, [start]);
    expect(state.result, isNull);
  });

  test('circumcircle sector handles finite points with overflowing deltas', () {
    final state = ConstructionState(tool: ConstructionTool.circumcircleSector);

    state.addPoint(const Point3D(-1e308, 0, 0));
    state.addPoint(const Point3D(1e308, 0, 0));
    expect(
      state.addPoint(const Point3D(0, 1e308, 0)),
      ConstructionAction.complete,
    );

    expect(state.result?.type, Object3DType.polyhedron);
    expect(
      state.result!.vertices.every(
        (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
      ),
      isTrue,
    );
  });

  test('large finite square can close a polygon with finite mesh vertices', () {
    final state = ConstructionState(tool: ConstructionTool.polygon);

    state.addPoint(Point3D.origin);
    state.addPoint(const Point3D(1e200, 0, 0));
    state.addPoint(const Point3D(1e200, 1e200, 0));
    state.addPoint(const Point3D(0, 1e200, 0));
    final action = state.addPoint(Point3D.origin);

    expect(action, ConstructionAction.complete);
    expect(state.result?.type, Object3DType.polyhedron);
    expect(
      state.result?.vertices.every(
        (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
      ),
      isTrue,
    );
  });

  test(
    'opposite-sign extreme square can close without non-finite vertices',
    () {
      final state = ConstructionState(tool: ConstructionTool.polygon);

      state.addPoint(const Point3D(-1e308, -1e308, 0));
      state.addPoint(const Point3D(1e308, -1e308, 0));
      state.addPoint(const Point3D(1e308, 1e308, 0));
      state.addPoint(const Point3D(-1e308, 1e308, 0));
      final action = state.addPoint(const Point3D(-1e308, -1e308, 0));

      expect(action, ConstructionAction.complete);
      expect(state.result?.type, Object3DType.polyhedron);
      expect(
        state.result?.vertices.every(
          (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
        ),
        isTrue,
      );
    },
  );

  test(
    'large finite square can complete filled area with finite coordinates',
    () {
      final state = ConstructionState(tool: ConstructionTool.area);

      state.addPoint(Point3D.origin);
      state.addPoint(const Point3D(1e200, 0, 0));
      state.addPoint(const Point3D(1e200, 1e200, 0));
      state.addPoint(const Point3D(0, 1e200, 0));
      final action = state.addPoint(Point3D.origin);

      expect(action, ConstructionAction.complete);
      expect(state.result?.type, Object3DType.point);
      expect(state.result?.point.x.isFinite, isTrue);
      expect(state.result?.point.y.isFinite, isTrue);
      expect(state.result?.point.z.isFinite, isTrue);
      expect(state.result?.label, isNot(contains('Infinity')));
      expect(state.result?.label, isNot(contains('NaN')));
      expect(state.result?.label, contains('e'));
    },
  );

  test('large collinear polygon remains rejected', () {
    final state = ConstructionState(tool: ConstructionTool.polygon);

    state.addPoint(Point3D.origin);
    state.addPoint(const Point3D(1e200, 0, 0));
    state.addPoint(const Point3D(2e200, 0, 0));
    state.addPoint(const Point3D(3e200, 0, 0));
    final action = state.addPoint(Point3D.origin);

    expect(action, ConstructionAction.awaitInput);
    expect(state.result, isNull);
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

  test('surface of revolution handles finite extreme axis endpoints', () {
    final state = ConstructionState(tool: ConstructionTool.surfaceOfRevolution);

    state.addPoint(const Point3D(-1e308, 0, 0));
    state.addPoint(const Point3D(1e308, 0, 0));
    state.addPoint(const Point3D(0, 1, 0));
    expect(state.addPoint(const Point3D(0, 2, 0)), ConstructionAction.complete);

    final result = state.result;
    expect(result?.type, Object3DType.surface);
    expect(
      result?.vertices.every(
        (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
      ),
      isTrue,
    );
  });

  test('surface of revolution rejects non-finite generated geometry', () {
    final state = ConstructionState(tool: ConstructionTool.surfaceOfRevolution);

    state.addPoint(Point3D.origin);
    state.addPoint(const Point3D(1, 0, 0));
    state.addPoint(const Point3D(1e308, 1e308, 0));
    expect(
      state.addPoint(const Point3D(1e308, -1e308, 0)),
      ConstructionAction.complete,
    );

    final result = state.result;
    expect(result?.type, Object3DType.curve);
    expect(
      result?.vertices.every(
        (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
      ),
      isTrue,
    );
  });

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

  test('fixed-length segment handles direction subtraction overflow', () {
    final state = ConstructionState(tool: ConstructionTool.fixedLengthSegment);

    state.addPoint(const Point3D(1e308, 0, 0));
    state.addPoint(const Point3D(-1e308, 0, 0));
    state.addPoint(const Point3D(1, 0, 0));

    final result = state.result;
    expect(result?.type, Object3DType.line);
    expect(result?.pointA.x.isFinite, isTrue);
    expect(result?.pointB.x.isFinite, isTrue);
    expect(result?.pointB.x, closeTo(0, 1e-10));
  });

  test('translation rejects overflow and can recover with valid input', () {
    final state = ConstructionState(tool: ConstructionTool.translation);
    const original = Point3D(1e308, 0, 0);
    const vectorStart = Point3D.origin;
    const overflowingVectorEnd = Point3D(1e308, 0, 0);

    state.addPoint(original);
    state.addPoint(vectorStart);
    expect(state.addPoint(overflowingVectorEnd), ConstructionAction.awaitInput);

    expect(state.isComplete, isFalse);
    expect(state.result, isNull);
    expect(state.points, [original, vectorStart]);
    expect(state.previewObject?.type, Object3DType.line);
    expect(state.previewObject?.pointA, original);
    expect(state.previewObject?.pointB, vectorStart);

    expect(
      state.addPoint(const Point3D(1e307, 0, 0)),
      ConstructionAction.complete,
    );
    expect(state.isComplete, isTrue);
    expect(state.result?.point.x.isFinite, isTrue);
    expect(state.result?.point.x, greaterThan(1e308));
  });

  test(
    'fixed-length segment rejects overflow and can recover with valid input',
    () {
      final state = ConstructionState(
        tool: ConstructionTool.fixedLengthSegment,
      );
      const start = Point3D(1e308, 0, 0);
      const directionPoint = Point3D(1.000000000000001e308, 0, 0);

      state.addPoint(start);
      state.addPoint(directionPoint);
      expect(state.addPoint(Point3D.origin), ConstructionAction.awaitInput);

      expect(state.isComplete, isFalse);
      expect(state.result, isNull);
      expect(state.points, [start, directionPoint]);
      expect(state.previewObject?.type, Object3DType.line);
      expect(state.previewObject?.pointA, start);
      expect(state.previewObject?.pointB, directionPoint);

      expect(
        state.addPoint(const Point3D(0.5e308, 0, 0)),
        ConstructionAction.complete,
      );
      expect(state.isComplete, isTrue);
      expect(state.result?.pointA.x.isFinite, isTrue);
      expect(state.result?.pointB.x.isFinite, isTrue);
      expect(state.result?.pointB.x, greaterThan(start.x));
    },
  );

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

  test('ellipse rejects unrepresentable conic coefficients', () {
    final oversized = ConstructionState(tool: ConstructionTool.ellipse);
    oversized.addPoint(Point3D.origin);
    oversized.addPoint(const Point3D(1e200, 0, 0));

    expect(
      oversized.addPoint(const Point3D(0, 1, 0)),
      ConstructionAction.awaitInput,
    );
    expect(oversized.result, isNull);
    expect(oversized.points, hasLength(2));

    final largeButRepresentable = ConstructionState(
      tool: ConstructionTool.ellipse,
    );
    largeButRepresentable.addPoint(Point3D.origin);
    largeButRepresentable.addPoint(const Point3D(1e155, 0, 0));
    expect(
      largeButRepresentable.addPoint(const Point3D(0, 1e155, 0)),
      ConstructionAction.complete,
    );
    expect(largeButRepresentable.result!.conic!.quadraticX, greaterThan(0));
    expect(largeButRepresentable.result!.conic!.quadraticY, greaterThan(0));
  });

  test('hyperbola rejects axes whose implicit coefficients underflow', () {
    final oversized = ConstructionState(tool: ConstructionTool.hyperbola);

    expect(oversized.addPoint(Point3D.origin), ConstructionAction.advanceStep);
    expect(
      oversized.addPoint(const Point3D(1e200, 0, 0)),
      ConstructionAction.advanceStep,
    );
    expect(
      oversized.addPoint(const Point3D(0, 1e200, 0)),
      ConstructionAction.awaitInput,
    );

    expect(oversized.result, isNull);
    expect(oversized.points, hasLength(2));

    final largeButRepresentable = ConstructionState(
      tool: ConstructionTool.hyperbola,
    );
    largeButRepresentable.addPoint(Point3D.origin);
    largeButRepresentable.addPoint(const Point3D(1e155, 0, 0));
    expect(
      largeButRepresentable.addPoint(const Point3D(0, 1e155, 0)),
      ConstructionAction.complete,
    );
    expect(largeButRepresentable.result!.conic!.quadraticX, greaterThan(0));
    expect(largeButRepresentable.result!.conic!.quadraticY, lessThan(0));

    final representable = ConstructionState(tool: ConstructionTool.hyperbola);
    representable.addPoint(Point3D.origin);
    representable.addPoint(const Point3D(2, 0, 0));
    expect(
      representable.addPoint(const Point3D(0, 3, 0)),
      ConstructionAction.complete,
    );

    final conic = representable.result!.conic!;
    expect(conic.quadraticX, closeTo(0.25, 1e-12));
    expect(conic.quadraticY, closeTo(-1 / 9, 1e-12));
  });

  test('preview uses the current point without mutating construction', () {
    final state = ConstructionState(tool: ConstructionTool.line);
    state.addPoint(const Point3D(1, 2, 3));

    final preview = state.previewForPoint(const Point3D(4, 5, 6));

    expect(preview?.type, Object3DType.line);
    expect(state.points, hasLength(1));
  });
}
