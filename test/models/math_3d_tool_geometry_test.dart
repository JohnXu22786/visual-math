import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  test(
    'line clipping distinguishes extents and respects projection depth rules',
    () {
      const camera = Camera3D(theta: math.pi / 2, phi: 0, distance: 10);
      for (final projection in [
        Projection3D.parallel(scale: 6),
        Projection3D.perspective(),
      ]) {
        const a = Point3D(0, 0, 0);
        const b = Point3D(0, 1, 0);
        final segment = clipLineToView(
          const Object3D.line(a, b),
          camera,
          projection,
        );
        expect(segment, [a, b]);
        final ray = clipLineToView(
          const Object3D.line(a, b, lineKind: Line3DKind.ray),
          camera,
          projection,
        );
        expect(ray.first, a);
        expect(ray.last.y, greaterThan(1));
        final line = clipLineToView(
          const Object3D.line(a, b, lineKind: Line3DKind.line),
          camera,
          projection,
        );
        expect(line.first.y, lessThan(0));
        expect(line.last.y, greaterThan(1));
        final towardsEye = clipLineToView(
          const Object3D.line(a, Point3D(20, 0, 0)),
          camera,
          projection,
        );
        final behind = clipLineToView(
          const Object3D.line(Point3D(11, 0, 0), Point3D(20, 0, 0)),
          camera,
          projection,
        );
        if (projection.type == ProjectionType.perspective) {
          expect(towardsEye.last.x, closeTo(10 - projection.near, 1e-7));
          expect(behind, isEmpty);
        } else {
          expect(towardsEye.last.x, 20);
          expect(behind, [const Point3D(11, 0, 0), const Point3D(20, 0, 0)]);
        }
      }
    },
  );

  test('short nonzero line directions clip like scaled directions', () {
    const camera = Camera3D(theta: math.pi / 2, phi: 0, distance: 10);
    for (final projection in [
      Projection3D.parallel(scale: 6),
      Projection3D.perspective(),
    ]) {
      for (final kind in [Line3DKind.line, Line3DKind.ray]) {
        final short = clipLineToView(
          Object3D.line(
            const Point3D(0, 0, 0),
            const Point3D(0, 1e-13, 0),
            lineKind: kind,
          ),
          camera,
          projection,
        );
        final normal = clipLineToView(
          Object3D.line(
            const Point3D(0, 0, 0),
            const Point3D(0, 1, 0),
            lineKind: kind,
          ),
          camera,
          projection,
        );
        expect(short, hasLength(2));
        expect(normal, hasLength(2));
        for (var i = 0; i < 2; i++) {
          expect(short[i].y, closeTo(normal[i].y, 1e-8));
        }
      }
    }
  });

  test('short direction along the camera axis remains visible', () {
    const camera = Camera3D(theta: 0, phi: 0, distance: 10);
    final projection = Projection3D.perspective();
    final short = clipLineToView(
      const Object3D.line(
        Point3D(0, 0, 0),
        Point3D(0, 1e-16, 0),
        lineKind: Line3DKind.line,
      ),
      camera,
      projection,
    );
    final normal = clipLineToView(
      const Object3D.line(
        Point3D(0, 0, 0),
        Point3D(0, 1, 0),
        lineKind: Line3DKind.line,
      ),
      camera,
      projection,
    );
    expect(short, hasLength(2));
    expect(normal, hasLength(2));
    for (var i = 0; i < 2; i++) {
      expect(short[i].y, closeTo(normal[i].y, 1e-8));
    }
  });

  test('finite extreme segments clip to finite visible endpoints', () {
    const camera = Camera3D(theta: math.pi / 2, phi: 0, distance: 10);
    final projection = Projection3D.perspective();
    final clipped = clipLineToView(
      const Object3D.line(
        Point3D(-double.maxFinite, 0, 0),
        Point3D(double.maxFinite, 0, 0),
      ),
      camera,
      projection,
    );

    expect(clipped, hasLength(2));
    for (final point in clipped) {
      expect(point.x.isFinite && point.y.isFinite && point.z.isFinite, isTrue);
      final screen = worldToScreen(point, camera, projection);
      expect(screen.x.isFinite && screen.y.isFinite, isTrue);
    }
  });

  test('two-point tools keep their geometry and reject zero-length input', () {
    for (final tool in [
      ConstructionTool.segment,
      ConstructionTool.ray,
      ConstructionTool.vector,
      ConstructionTool.midpoint,
    ]) {
      final state = ConstructionState(tool: tool);
      const a = Point3D(1, 2, 3);
      const b = Point3D(4, 6, 8);
      state.addPoint(a);
      expect(state.addPoint(a), ConstructionAction.awaitInput);
      expect(state.addPoint(b), ConstructionAction.complete);
      final object = state.result!;
      switch (tool) {
        case ConstructionTool.midpoint:
          expect(object.point, a.midpoint(b));
        case ConstructionTool.vector:
          expect(object.point, a);
          expect(object.vector, b - a);
        default:
          expect(object.pointA, a);
          expect(object.pointB, b);
          expect(
            object.lineKind,
            tool == ConstructionTool.ray ? Line3DKind.ray : Line3DKind.segment,
          );
      }
    }
  });

  test(
    'three-point circle rejects collinearity and lies in the input plane',
    () {
      final state = ConstructionState(tool: ConstructionTool.circleThreePoints);
      const a = Point3D(1, 2, 0);
      const b = Point3D(1, 0, 2);
      const c = Point3D(1, -2, 0);
      state.addPoint(a);
      state.addPoint(b);
      expect(
        state.addPoint(const Point3D(1, -2, 4)),
        ConstructionAction.awaitInput,
      );
      expect(state.points, [a, b]);
      expect(state.addPoint(c), ConstructionAction.complete);
      for (final p in state.result!.vertices) {
        expect(p.x, closeTo(1, 1e-8));
        expect(p.distanceTo(const Point3D(1, 0, 0)), closeTo(2, 1e-8));
      }
      expect(state.result!.vertices.first.distanceTo(a), lessThan(1e-8));
      expect(state.result!.vertices.last.distanceTo(a), lessThan(1e-8));
    },
  );

  test('circumcircle constructions handle large coordinates', () {
    for (final tool in [
      ConstructionTool.circleThreePoints,
      ConstructionTool.circumcircleArc,
      ConstructionTool.circumcircleSector,
    ]) {
      final state = ConstructionState(tool: tool);
      state.addPoint(Point3D.origin);
      state.addPoint(const Point3D(1e80, 0, 0));
      expect(
        state.addPoint(const Point3D(0, 1e80, 0)),
        ConstructionAction.complete,
      );
      final vertices = state.result!.vertices;
      for (final point in vertices) {
        expect(
          point.x.isFinite && point.y.isFinite && point.z.isFinite,
          isTrue,
          reason: '$tool produced $point',
        );
      }
      if (tool == ConstructionTool.circumcircleSector) {
        expect(vertices.first.x, closeTo(5e79, 1e65));
        expect(vertices.first.y, closeTo(5e79, 1e65));
      }
      final perimeter = tool == ConstructionTool.circumcircleSector
          ? vertices.skip(1)
          : vertices;
      for (final point in perimeter) {
        final x = (point.x - 5e79) / 1e80;
        final y = (point.y - 5e79) / 1e80;
        expect(x * x + y * y, closeTo(0.5, 1e-12), reason: '$tool');
      }
    }
  });

  test('circumcircle constructions handle unequal edge scales', () {
    for (final tool in [
      ConstructionTool.circleThreePoints,
      ConstructionTool.circumcircleArc,
      ConstructionTool.circumcircleSector,
    ]) {
      final state = ConstructionState(tool: tool);
      state.addPoint(Point3D.origin);
      state.addPoint(const Point3D(1e154, 0, 0));
      expect(
        state.addPoint(const Point3D(0, 1e-8, 0)),
        ConstructionAction.complete,
      );
      for (final point in state.result!.vertices) {
        expect(
          point.x.isFinite && point.y.isFinite && point.z.isFinite,
          isTrue,
          reason: '$tool produced $point',
        );
      }
      if (tool == ConstructionTool.circumcircleSector) {
        expect(state.result!.vertices.first.x, closeTo(5e153, 1e139));
        expect(state.result!.vertices.first.y, closeTo(5e-9, 1e-23));
      }
    }

    final state = ConstructionState(tool: ConstructionTool.circumcircleSector);
    state.addPoint(Point3D.origin);
    state.addPoint(const Point3D(1.3e308, 1.3e308, 0));
    expect(
      state.addPoint(const Point3D(0, 0, 1e307)),
      ConstructionAction.complete,
    );
    final center = state.result!.vertices.first;
    expect(center.x / 1e308, closeTo(0.65, 1e-14));
    expect(center.y / 1e308, closeTo(0.65, 1e-14));
    expect(center.z / 1e307, closeTo(0.5, 1e-14));
    final skew = ConstructionState(tool: ConstructionTool.circumcircleSector);
    skew.addPoint(Point3D.origin);
    skew.addPoint(const Point3D(1e308, 0, 0));
    expect(
      skew.addPoint(const Point3D(1e-9, 2e-9, 0)),
      ConstructionAction.complete,
    );
    final skewCenter = skew.result!.vertices.first;
    expect(skewCenter.x / 1e308, closeTo(0.5, 1e-14));
    expect(skewCenter.y / 1e308, closeTo(-0.25, 1e-14));
    final parallel = ConstructionState(
      tool: ConstructionTool.circumcircleSector,
    );
    parallel.addPoint(Point3D.origin);
    parallel.addPoint(const Point3D(1e308, 0, 0));
    expect(
      parallel.addPoint(const Point3D(1e308, 1e300, 0)),
      ConstructionAction.complete,
    );
    final parallelCenter = parallel.result!.vertices.first;
    expect(parallelCenter.x / 1e308, closeTo(0.5, 1e-14));
    expect(parallelCenter.y / 1e300, closeTo(0.5, 1e-14));
  });

  test(
    'regular polygon has equal sides in a tilted plane and validates count',
    () {
      expect(
        () => ConstructionState(
          tool: ConstructionTool.regularPolygon,
          polygonSides: 2,
        ),
        throwsArgumentError,
      );
      for (final count in [3, 6, 12]) {
        final state = ConstructionState(
          tool: ConstructionTool.regularPolygon,
          polygonSides: count,
        );
        state.addPoint(
          const Point3D(2, 0, 0),
          workingPlaneNormal: Vector3D.unitX,
        );
        state.addPoint(
          const Point3D(2, 3, 0),
          workingPlaneNormal: Vector3D.unitX,
        );
        final vertices = state.result!.vertices;
        expect(vertices, hasLength(count));
        for (var i = 0; i < count; i++) {
          expect(vertices[i].x, closeTo(2, 1e-8));
          expect(
            vertices[i].distanceTo(vertices[(i + 1) % count]),
            closeTo(3, 1e-8),
          );
        }
      }
    },
  );

  test(
    'regular tetrahedron has six equal edges including a vertical base edge',
    () {
      for (final b in [const Point3D(2, 0, 0), const Point3D(0, 0, 2)]) {
        final state = ConstructionState(tool: ConstructionTool.tetrahedron);
        state.addPoint(Point3D.origin);
        expect(state.addPoint(Point3D.origin), ConstructionAction.awaitInput);
        state.addPoint(b);
        final vertices = state.result!.vertices;
        expect(vertices, hasLength(4));
        expect(state.result!.indices, hasLength(12));
        for (var i = 0; i < 4; i++) {
          for (var j = i + 1; j < 4; j++) {
            expect(vertices[i].distanceTo(vertices[j]), closeTo(2, 1e-8));
          }
        }
        final volume =
            (vertices[1] - vertices[0])
                .cross(vertices[2] - vertices[0])
                .dot(vertices[3] - vertices[0])
                .abs() /
            6;
        expect(volume, closeTo(8 / (6 * math.sqrt(2)), 1e-8));
      }
    },
  );
}
