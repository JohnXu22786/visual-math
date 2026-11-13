import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  group('3D construction geometry', () {
    test('parabola does not connect its divergent path to the vertex', () {
      final construction = ConstructionState(tool: ConstructionTool.conic);
      for (final point in const [
        Point3D(-1, 1, 0),
        Point3D(1, 1, 0),
        Point3D(-2, 4, 0),
        Point3D(0, 0, 0),
        Point3D(2, 4, 0),
      ]) {
        construction.addPoint(point);
      }
      final curve = construction.result!;
      final points = curve.vertices;
      expect(points.any((point) => point.x < -4), isTrue);
      expect(points.any((point) => point.x > 4), isTrue);
      for (var i = 1; i < points.length; i++) {
        if (curve.curveStarts.contains(i)) continue;
        final a = points[i - 1];
        final b = points[i];
        final midpointX = (a.x + b.x) / 2;
        final midpointY = (a.y + b.y) / 2;
        // A chord joining infinity to the vertex cuts far across the parabola.
        expect(
          (midpointY - midpointX * midpointX).abs(),
          lessThan(0.1 * (1 + midpointY.abs())),
        );
      }
    });

    test('intersects a ray with a working plane in front of the camera', () {
      const ray = Ray3D(Point3D(1, 2, 5), Vector3D(0, 0, -1));

      final hit = intersectRayPlane(
        ray,
        point: const Point3D(0, 0, 2),
        normal: Vector3D.unitZ,
      );

      expect(hit, const Point3D(1, 2, 2));
    });

    test('does not create a false hit for a parallel ray', () {
      const ray = Ray3D(Point3D(0, 0, 1), Vector3D.unitX);

      final hit = intersectRayPlane(
        ray,
        point: Point3D.origin,
        normal: Vector3D.unitZ,
      );

      expect(hit, isNull);
    });

    test('reflection handles large valid plane coordinates', () {
      final construction = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      construction.addPoint(const Point3D(0, 0, 1));
      construction.addPoint(Point3D.origin);
      construction.addPoint(const Point3D(1e100, 0, 0));

      expect(
        construction.addPoint(const Point3D(0, 1e100, 0)),
        ConstructionAction.complete,
      );
      expect(construction.result!.point, const Point3D(0, 0, -1));

      final overflowedEdge = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      overflowedEdge.addPoint(const Point3D(0, 0, 1));
      overflowedEdge.addPoint(const Point3D(-1e308, 0, 0));
      overflowedEdge.addPoint(const Point3D(1e308, 0, 0));
      expect(
        overflowedEdge.addPoint(const Point3D(-1e308, 1e308, 0)),
        ConstructionAction.complete,
      );
      expect(overflowedEdge.result!.point, const Point3D(0, 0, -1));

      final largePoint = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      largePoint.addPoint(const Point3D(1e308, 0, 0));
      largePoint.addPoint(Point3D.origin);
      largePoint.addPoint(const Point3D(0, 1, 0));
      expect(
        largePoint.addPoint(const Point3D(0, 0, 1)),
        ConstructionAction.complete,
      );
      expect(largePoint.result!.point, const Point3D(-1e308, 0, 0));

      final largeProjection = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      largeProjection.addPoint(const Point3D(1.7e308, 1.7e308, 1.7e308));
      largeProjection.addPoint(Point3D.origin);
      largeProjection.addPoint(const Point3D(1, -1, 0));
      expect(
        largeProjection.addPoint(const Point3D(1, 1, -2)),
        ConstructionAction.complete,
      );
      final reflectedLarge = largeProjection.result!.point;
      expect(reflectedLarge.x / 1.7e308, closeTo(-1, 1e-12));
      expect(reflectedLarge.y / 1.7e308, closeTo(-1, 1e-12));
      expect(reflectedLarge.z / 1.7e308, closeTo(-1, 1e-12));

      final smallResidualAfterLargeCancellation = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      smallResidualAfterLargeCancellation.addPoint(
        const Point3D(1e308, 1e-20, -1e308),
      );
      smallResidualAfterLargeCancellation.addPoint(Point3D.origin);
      smallResidualAfterLargeCancellation.addPoint(const Point3D(1, -1, 0));
      expect(
        smallResidualAfterLargeCancellation.addPoint(const Point3D(1, 0, -1)),
        ConstructionAction.complete,
      );
      expect(
        smallResidualAfterLargeCancellation.result!.point.y / 1e-20,
        closeTo(1 / 3, 1e-12),
      );

      final overflowFallbackResidual = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      overflowFallbackResidual.addPoint(const Point3D(1e308, 1e-20, -1e308));
      overflowFallbackResidual.addPoint(const Point3D(-1e308, 0, 1e308));
      overflowFallbackResidual.addPoint(const Point3D(0, -1e308, 1e308));
      expect(
        overflowFallbackResidual.addPoint(const Point3D(-1e308, 1e308, 0)),
        ConstructionAction.complete,
      );
      expect(
        overflowFallbackResidual.result!.point.y / 1e-20,
        closeTo(1 / 3, 1e-12),
      );

      final largeTangentPoint = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      const tangentPoint = Point3D(1e308, 1e308, 0);
      largeTangentPoint.addPoint(tangentPoint);
      largeTangentPoint.addPoint(const Point3D(-1e308, -1e308, 0));
      largeTangentPoint.addPoint(const Point3D(-1e308, -9e307, 0));
      expect(
        largeTangentPoint.addPoint(const Point3D(-9e307, -1e308, 0)),
        ConstructionAction.complete,
      );
      expect(largeTangentPoint.result!.point, tangentPoint);

      final smallNormalComponent = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      smallNormalComponent.addPoint(const Point3D(0, 1e278, 1e308));
      smallNormalComponent.addPoint(Point3D.origin);
      smallNormalComponent.addPoint(const Point3D(0, 0, 1));
      expect(
        smallNormalComponent.addPoint(const Point3D(1, -1e-300, 0)),
        ConstructionAction.complete,
      );
      expect(smallNormalComponent.result!.point.x / 1e-22, closeTo(-2, 1e-12));

      final smallAlignedOffset = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      smallAlignedOffset.addPoint(const Point3D(1e308, 1e-100, 0));
      smallAlignedOffset.addPoint(Point3D.origin);
      smallAlignedOffset.addPoint(const Point3D(1e308, 0, 0));
      expect(
        smallAlignedOffset.addPoint(const Point3D(0, 0, 1)),
        ConstructionAction.complete,
      );
      expect(smallAlignedOffset.result!.point.y, -1e-100);

      final pointOnPlane = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      pointOnPlane.addPoint(Point3D.origin);
      pointOnPlane.addPoint(Point3D.origin);
      pointOnPlane.addPoint(const Point3D(1, 0, 0));
      expect(
        pointOnPlane.addPoint(const Point3D(0, 1, 0)),
        ConstructionAction.complete,
      );
      expect(pointOnPlane.result!.point, Point3D.origin);
    });

    test('reflection rejects unrepresentable derived points', () {
      final construction = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      construction.addPoint(Point3D.origin);
      construction.addPoint(const Point3D(1e308, 0, 0));
      construction.addPoint(const Point3D(1e308, 1e100, 0));
      final previewBeforeRejectedPoint = construction.previewObject;

      expect(
        construction.addPoint(const Point3D(1e308, 0, 1e100)),
        ConstructionAction.awaitInput,
      );
      expect(construction.points, hasLength(3));
      expect(construction.result, isNull);
      expect(construction.currentInstruction, contains('无法表示'));
      expect(construction.previewObject, same(previewBeforeRejectedPoint));
      expect(
        construction.addPoint(const Point3D(0, 0, 1e308)),
        ConstructionAction.complete,
      );
      expect(construction.result!.point.x, closeTo(1e308, 1e294));
      expect(construction.result!.point.z, closeTo(1e308, 1e294));
    });

    test('round constructions reject unrepresentable radii and recover', () {
      for (final tool in [
        ConstructionTool.sphere,
        ConstructionTool.sphereByRadius,
        ConstructionTool.circle,
        ConstructionTool.arc,
        ConstructionTool.circularSector,
      ]) {
        final construction = ConstructionState(tool: tool);
        construction.addPoint(Point3D.origin);
        construction.updatePreviewPoint(const Point3D(1e155, 0, 0));
        final preview = construction.previewObject;
        if (preview != null && preview.type == Object3DType.sphere) {
          expect(
            preview.sphereRadius.isFinite,
            isTrue,
            reason: '$tool preview',
          );
        }
        if (preview != null) {
          expect(
            preview.vertices.every(
              (p) => p.x.isFinite && p.y.isFinite && p.z.isFinite,
            ),
            isTrue,
            reason: '$tool preview',
          );
        }
        expect(
          construction.addPoint(const Point3D(1e155, 0, 0)),
          ConstructionAction.awaitInput,
          reason: '$tool',
        );
        expect(construction.points, [Point3D.origin], reason: '$tool');
        expect(construction.result, isNull, reason: '$tool');
        expect(
          construction.addPoint(const Point3D(2, 0, 0)),
          tool == ConstructionTool.arc ||
                  tool == ConstructionTool.circularSector
              ? ConstructionAction.advanceStep
              : ConstructionAction.complete,
          reason: '$tool',
        );
        if (tool == ConstructionTool.arc ||
            tool == ConstructionTool.circularSector) {
          expect(
            construction.addPoint(const Point3D(0, 2, 0)),
            ConstructionAction.complete,
          );
        }
        expect(construction.result, isNotNull, reason: '$tool');
      }
    });

    test('three-point round constructions handle large radii safely', () {
      for (final tool in [
        ConstructionTool.circleThreePoints,
        ConstructionTool.circumcircleArc,
        ConstructionTool.circumcircleSector,
      ]) {
        final construction = ConstructionState(tool: tool);
        construction.addPoint(Point3D.origin);
        construction.addPoint(const Point3D(1e155, 0, 0));
        final action = construction.addPoint(const Point3D(0, 1e155, 0));
        if (tool == ConstructionTool.circumcircleSector) {
          expect(action, ConstructionAction.complete, reason: '$tool');
          expect(
            construction.result!.vertices.every(
              (p) => p.x.isFinite && p.y.isFinite && p.z.isFinite,
            ),
            isTrue,
            reason: '$tool',
          );
        } else {
          expect(action, ConstructionAction.awaitInput, reason: '$tool');
          expect(construction.result, isNull, reason: '$tool');
        }
      }
    });

    test('axis and normal circles reject overflowing radii', () {
      for (final tool in [
        ConstructionTool.circleAxisPoint,
        ConstructionTool.circleCenterNormalRadius,
      ]) {
        final construction = ConstructionState(tool: tool);
        construction.addPoint(Point3D.origin);
        construction.addPoint(const Point3D(0, 0, 1));
        expect(
          construction.addPoint(const Point3D(1e155, 0, 0)),
          ConstructionAction.awaitInput,
          reason: '$tool',
        );
        expect(construction.result, isNull, reason: '$tool');
        expect(
          construction.addPoint(const Point3D(2, 0, 0)),
          ConstructionAction.complete,
          reason: '$tool',
        );
      }
    });

    test('axis circle permits a large axial offset with a small radius', () {
      final construction = ConstructionState(
        tool: ConstructionTool.circleAxisPoint,
      );
      construction.addPoint(Point3D.origin);
      construction.addPoint(const Point3D(1, 0, 0));
      expect(
        construction.addPoint(const Point3D(1e155, 1, 0)),
        ConstructionAction.complete,
      );
      expect(
        construction.result!.vertices.every(
          (p) => p.x.isFinite && p.y.isFinite && p.z.isFinite,
        ),
        isTrue,
      );
    });

    test('normal circle permits a large normal and a small radius', () {
      final construction = ConstructionState(
        tool: ConstructionTool.circleCenterNormalRadius,
      );
      construction.addPoint(Point3D.origin);
      construction.addPoint(const Point3D(0, 0, 1e155));
      expect(
        construction.addPoint(const Point3D(1, 0, 0)),
        ConstructionAction.complete,
      );
      expect(construction.result!.vertices.any((p) => p.y.abs() > 0.9), isTrue);
    });

    test('large arc endpoint direction retains the requested sweep', () {
      for (final tool in [
        ConstructionTool.arc,
        ConstructionTool.circularSector,
      ]) {
        final construction = ConstructionState(tool: tool);
        construction.addPoint(Point3D.origin);
        construction.addPoint(const Point3D(1e150, 0, 0));
        expect(
          construction.addPoint(const Point3D(0, 1e155, 0)),
          ConstructionAction.complete,
          reason: '$tool',
        );
        final last = construction.result!.vertices.last;
        expect(last.x / 1e150, closeTo(0, 1e-12));
        expect(last.y / 1e150, closeTo(1, 1e-12));
      }
    });

    test('normal circle rejects an unrepresentable normal difference', () {
      final construction = ConstructionState(
        tool: ConstructionTool.circleCenterNormalRadius,
      );
      construction.addPoint(const Point3D(0, 0, 1e308));
      construction.addPoint(const Point3D(0, 0, -1e308));
      expect(
        construction.addPoint(const Point3D(1, 0, 1e308)),
        ConstructionAction.awaitInput,
      );
      expect(construction.result, isNull);
    });

    test('sphere keeps a spatial radius point instead of flattening it', () {
      final construction = ConstructionState(tool: ConstructionTool.sphere);
      expect(
        construction.addPoint(const Point3D(1, 2, 3)),
        ConstructionAction.advanceStep,
      );
      expect(
        construction.addPoint(const Point3D(1, 2, 6)),
        ConstructionAction.complete,
      );

      expect(construction.result?.type, Object3DType.sphere);
      expect(construction.result?.sphereCenter, const Point3D(1, 2, 3));
      expect(construction.result?.sphereRadius, 3);
    });

    test('sphere rejects a zero radius without advancing the workflow', () {
      final construction = ConstructionState(tool: ConstructionTool.sphere);
      const center = Point3D(1, 2, 3);
      construction.addPoint(center);

      expect(construction.addPoint(center), ConstructionAction.awaitInput);
      expect(construction.points, [center]);
      expect(construction.result, isNull);
      expect(construction.currentInstruction, contains('半径必须大于 0'));

      expect(
        construction.addPoint(const Point3D(2, 2, 3)),
        ConstructionAction.complete,
      );
      expect(construction.result?.sphereRadius, 1);
    });

    test(
      'sphere preview shows the live volume instead of only a radius line',
      () {
        final construction = ConstructionState(tool: ConstructionTool.sphere);
        construction.addPoint(const Point3D(1, 1, 1));

        construction.updatePreviewPoint(const Point3D(1, 1, 3));

        expect(construction.previewObject?.type, Object3DType.sphere);
        expect(
          construction.previewObject?.sphereCenter,
          const Point3D(1, 1, 1),
        );
        expect(construction.previewObject?.sphereRadius, 2);
      },
    );

    test('plane rejects a collinear third point and remains recoverable', () {
      final construction = ConstructionState(tool: ConstructionTool.plane);
      construction.addPoint(Point3D.origin);
      construction.addPoint(const Point3D(1, 0, 0));

      expect(
        construction.addPoint(const Point3D(2, 0, 0)),
        ConstructionAction.awaitInput,
      );
      expect(construction.points.length, 2);
      expect(construction.currentInstruction, contains('不能共线'));

      expect(
        construction.addPoint(const Point3D(0, 1, 0)),
        ConstructionAction.complete,
      );
      expect(construction.result?.type, Object3DType.plane);
      expect(construction.result?.planeC, closeTo(1, 1e-9));
    });

    test('line rejects duplicate endpoints', () {
      final construction = ConstructionState(tool: ConstructionTool.line);
      const point = Point3D(2, -1, 4);
      construction.addPoint(point);

      expect(construction.addPoint(point), ConstructionAction.awaitInput);
      expect(construction.points, [point]);
      expect(construction.result, isNull);
    });

    test('circle vertices stay in the active working plane', () {
      final construction = ConstructionState(tool: ConstructionTool.circle);
      construction.addPoint(Point3D.origin, workingPlaneNormal: Vector3D.unitZ);
      expect(
        construction.addPoint(
          const Point3D(2, 0, 0),
          workingPlaneNormal: Vector3D.unitZ,
        ),
        ConstructionAction.complete,
      );

      final vertices = construction.result!.vertices;
      expect(vertices, isNotEmpty);
      expect(vertices.every((point) => point.z.abs() < 1e-9), isTrue);
    });

    test('cone and cylinder tools create round meshes from spatial points', () {
      final cone = ConstructionState(tool: ConstructionTool.cone);
      cone.addPoint(Point3D.origin);
      cone.addPoint(const Point3D(2, 0, 0));
      expect(
        cone.addPoint(const Point3D(0, 0, 3)),
        ConstructionAction.complete,
      );
      expect(cone.result?.type, Object3DType.polyhedron);
      expect(cone.result?.vertices.length, 26);
      expect(cone.result?.indices.length, 24 * 6);

      final cylinder = ConstructionState(tool: ConstructionTool.cylinder);
      cylinder.addPoint(Point3D.origin);
      cylinder.addPoint(const Point3D(2, 0, 0));
      expect(
        cylinder.addPoint(const Point3D(0, 0, 3)),
        ConstructionAction.complete,
      );
      expect(cylinder.result?.type, Object3DType.polyhedron);
      expect(cylinder.result?.vertices.length, 50);
      expect(cylinder.result?.indices.length, 24 * 12);
    });

    test('prism and pyramid tools create triangular solids', () {
      final prism = ConstructionState(tool: ConstructionTool.extrudePrism);
      prism.addPoint(Point3D.origin);
      prism.addPoint(const Point3D(2, 0, 0));
      prism.addPoint(const Point3D(0, 2, 0));
      expect(
        prism.addPoint(const Point3D(0, 0, 3)),
        ConstructionAction.complete,
      );
      expect(prism.result?.vertices.length, 6);
      expect(prism.result?.indices.length, 24);

      final pyramid = ConstructionState(tool: ConstructionTool.pyramid);
      pyramid.addPoint(Point3D.origin);
      pyramid.addPoint(const Point3D(2, 0, 0));
      pyramid.addPoint(const Point3D(0, 2, 0));
      expect(
        pyramid.addPoint(const Point3D(0, 0, 3)),
        ConstructionAction.complete,
      );
      expect(pyramid.result?.vertices.length, 4);
      expect(pyramid.result?.indices.length, 12);
    });
  });
}
