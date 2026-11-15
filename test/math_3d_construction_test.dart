import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  group('3D construction geometry', () {
    test('rejects conics whose world coefficients lose quadratic terms', () {
      final ordinary = ConstructionState(tool: ConstructionTool.conic);
      for (final point in const [
        Point3D(10, 0, 0),
        Point3D(0, 10, 0),
        Point3D(-10, 0, 0),
        Point3D(0, -10, 0),
      ]) {
        ordinary.addPoint(point);
      }
      expect(
        ordinary.addPoint(
          const Point3D(7.071067811865476, 7.071067811865476, 0),
        ),
        ConstructionAction.complete,
      );
      expect(ordinary.result, isNotNull);
      expect(
        ordinary.result!.conic!.quadraticX.abs() +
            ordinary.result!.conic!.quadraticXY.abs() +
            ordinary.result!.conic!.quadraticY.abs(),
        greaterThan(0),
      );

      for (final (radius, expectedAction) in [
        (1e155, ConstructionAction.complete),
        (1e200, ConstructionAction.awaitInput),
      ]) {
        final huge = ConstructionState(tool: ConstructionTool.conic);
        for (final point in [
          Point3D(radius, 0, 0),
          Point3D(0, radius, 0),
          Point3D(-radius, 0, 0),
          Point3D(0, -radius, 0),
        ]) {
          huge.addPoint(point);
        }
        expect(
          huge.addPoint(
            Point3D(
              7.071067811865476e199 * (radius / 1e200),
              7.071067811865476e199 * (radius / 1e200),
              0,
            ),
          ),
          expectedAction,
        );
        if (expectedAction == ConstructionAction.complete) {
          final conic = huge.result!.conic!;
          expect(
            conic.quadraticX.abs() +
                conic.quadraticXY.abs() +
                conic.quadraticY.abs(),
            greaterThan(0),
          );
        } else {
          expect(huge.result, isNull);
        }
      }

      final partialUnderflow = ConstructionState(tool: ConstructionTool.conic);
      for (final point in const [
        Point3D(1e162, 0, 0),
        Point3D(-1e162, 0, 0),
        Point3D(0, 1e160, 0),
        Point3D(0, -1e160, 0),
      ]) {
        partialUnderflow.addPoint(point);
      }
      expect(
        partialUnderflow.addPoint(
          const Point3D(7.071067811865476e161, 7.071067811865476e159, 0),
        ),
        ConstructionAction.awaitInput,
      );
      expect(partialUnderflow.result, isNull);
    });
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

    test('parabola projects a large directrix without overflowing', () {
      final construction = ConstructionState(tool: ConstructionTool.parabola);
      expect(
        construction.addPoint(const Point3D(1e155, 1, 0)),
        ConstructionAction.advanceStep,
      );
      expect(
        construction.addPoint(Point3D.origin),
        ConstructionAction.advanceStep,
      );
      expect(
        construction.addPoint(const Point3D(1e155, 0, 0)),
        ConstructionAction.complete,
      );

      final parabola = construction.result!;
      expect(parabola.conic, isNotNull);
      expect(parabola.vertices, hasLength(97));
      expect(
        parabola.vertices.every(
          (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
        ),
        isTrue,
      );
      expect(parabola.conic!.origin.x, 1e155);
      expect(parabola.conic!.origin.y, closeTo(0.5, 1e-12));

      final wideParabola = ConstructionState(tool: ConstructionTool.parabola);
      wideParabola.addPoint(const Point3D(0, 2e307, 0));
      wideParabola.addPoint(Point3D.origin);
      expect(
        wideParabola.addPoint(const Point3D(1e308, 0, 0)),
        ConstructionAction.complete,
      );
      expect(
        wideParabola.result!.vertices.every(
          (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
        ),
        isTrue,
      );

      final largeProjectedFoot = ConstructionState(
        tool: ConstructionTool.parabola,
      );
      largeProjectedFoot.addPoint(const Point3D(1.1e308, 1.1e308, 1e308));
      largeProjectedFoot.addPoint(Point3D.origin);
      expect(
        largeProjectedFoot.addPoint(const Point3D(1, 1, 1)),
        ConstructionAction.complete,
      );
      expect(
        largeProjectedFoot.result!.vertices.every(
          (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
        ),
        isTrue,
      );

      final largeOffsetAcrossOrigin = ConstructionState(
        tool: ConstructionTool.parabola,
      );
      largeOffsetAcrossOrigin.addPoint(const Point3D(1.1e308, 1, 0));
      largeOffsetAcrossOrigin.addPoint(const Point3D(-1.1e308, 0, 0));
      expect(
        largeOffsetAcrossOrigin.addPoint(const Point3D(-1e308, 0, 0)),
        ConstructionAction.complete,
      );
      expect(
        largeOffsetAcrossOrigin.result!.vertices.every(
          (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
        ),
        isTrue,
      );

      final overflowingDirectrixDifference = ConstructionState(
        tool: ConstructionTool.parabola,
      );
      overflowingDirectrixDifference.addPoint(const Point3D(0, 0, 1));
      overflowingDirectrixDifference.addPoint(const Point3D(-1.1e308, 0, 0));
      expect(
        overflowingDirectrixDifference.addPoint(const Point3D(1.1e308, 0, 0)),
        ConstructionAction.complete,
      );
      expect(
        overflowingDirectrixDifference.result!.vertices.every(
          (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
        ),
        isTrue,
      );

      final focusOnLargeDirectrix = ConstructionState(
        tool: ConstructionTool.parabola,
      );
      focusOnLargeDirectrix.addPoint(const Point3D(1.1e308, 1.1e308, 1.1e308));
      focusOnLargeDirectrix.addPoint(Point3D.origin);
      expect(
        focusOnLargeDirectrix.addPoint(const Point3D(1, 1, 1)),
        ConstructionAction.awaitInput,
      );
      expect(focusOnLargeDirectrix.result, isNull);
      expect(focusOnLargeDirectrix.points, hasLength(2));
      expect(
        focusOnLargeDirectrix.addPoint(const Point3D(1.1e308, 1.1e308, 1e308)),
        ConstructionAction.complete,
      );
      expect(
        focusOnLargeDirectrix.result!.vertices.every(
          (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
        ),
        isTrue,
      );

      final largeFocusSmallRelativeOffset = ConstructionState(
        tool: ConstructionTool.parabola,
      );
      largeFocusSmallRelativeOffset.addPoint(const Point3D(1e308, 1e108, 0));
      largeFocusSmallRelativeOffset.addPoint(Point3D.origin);
      expect(
        largeFocusSmallRelativeOffset.addPoint(const Point3D(1e308, 0, 0)),
        ConstructionAction.complete,
      );
      expect(largeFocusSmallRelativeOffset.result!.vertices, hasLength(97));
      expect(
        largeFocusSmallRelativeOffset.result!.vertices.every(
          (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
        ),
        isTrue,
      );

      final largeFocusTinyOffset = ConstructionState(
        tool: ConstructionTool.parabola,
      );
      largeFocusTinyOffset.addPoint(const Point3D(1e10, 1e-12, 0));
      largeFocusTinyOffset.addPoint(Point3D.origin);
      expect(
        largeFocusTinyOffset.addPoint(const Point3D(1e10, 0, 0)),
        ConstructionAction.complete,
      );
      expect(largeFocusTinyOffset.result!.vertices, hasLength(97));

      final largeFocusSubnormalRelativeOffset = ConstructionState(
        tool: ConstructionTool.parabola,
      );
      largeFocusSubnormalRelativeOffset.addPoint(
        const Point3D(1e308, 1e-300, 0),
      );
      largeFocusSubnormalRelativeOffset.addPoint(Point3D.origin);
      expect(
        largeFocusSubnormalRelativeOffset.addPoint(const Point3D(1e308, 0, 0)),
        ConstructionAction.complete,
      );
      expect(largeFocusSubnormalRelativeOffset.result!.vertices, hasLength(97));
      expect(largeFocusSubnormalRelativeOffset.result!.conic!.origin.y, 5e-301);
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

    test('ray-plane hit survives overflowing scalar distance', () {
      const ray = Ray3D(Point3D(-1.7e308, 0, 0), Vector3D(1, 1e-308, 0));

      final hit = intersectRayPlane(
        ray,
        point: const Point3D(1.3e308, 0, 0),
        normal: Vector3D.unitX,
      );

      expect(hit, isNotNull);
      expect(hit!.x / 1.3e308, closeTo(1, 1e-15));
      expect(hit.y, closeTo(3, 1e-12));
      expect(hit.z, 0);

      final irrelevantInfiniteCoordinateHit = intersectRayPlane(
        ray,
        point: const Point3D(1.3e308, double.infinity, 0),
        normal: Vector3D.unitX,
      );
      expect(irrelevantInfiniteCoordinateHit, isNotNull);
      expect(irrelevantInfiniteCoordinateHit!.x / 1.3e308, closeTo(1, 1e-15));
      expect(irrelevantInfiniteCoordinateHit.y, closeTo(3, 1e-12));

      const behindRay = Ray3D(Point3D(1.7e308, 0, 0), Vector3D(1, 1e-308, 0));
      const behindPlane = Point3D(-1.3e308, 0, 0);
      expect(
        intersectRayPlane(
          behindRay,
          point: behindPlane,
          normal: Vector3D.unitX,
        ),
        isNull,
      );
      final behindHit = intersectRayPlane(
        behindRay,
        point: behindPlane,
        normal: Vector3D.unitX,
        allowBehind: true,
      );
      expect(behindHit, isNotNull);
      expect(behindHit!.x / -1.3e308, closeTo(1, 1e-15));
      expect(behindHit.y, closeTo(-3, 1e-12));
    });

    test('ray-plane offset ignores overflowing perpendicular separation', () {
      const ray = Ray3D(Point3D(-1e308, 0, 5), Vector3D(0, 0, -1));

      final hit = intersectRayPlane(
        ray,
        point: const Point3D(1e308, 0, 2),
        normal: Vector3D.unitZ,
      );

      expect(hit, const Point3D(-1e308, 0, 2));
      expect(hit!.x.isFinite && hit.y.isFinite && hit.z.isFinite, isTrue);

      const planeBehindRay = Point3D(1e308, 0, 7);
      expect(
        intersectRayPlane(ray, point: planeBehindRay, normal: Vector3D.unitZ),
        isNull,
      );
      expect(
        intersectRayPlane(
          ray,
          point: planeBehindRay,
          normal: Vector3D.unitZ,
          allowBehind: true,
        ),
        const Point3D(-1e308, 0, 7),
      );

      const obliqueRay = Ray3D(Point3D(-1e308, 1e308, 5), Vector3D(0, 0, -1));
      final obliqueHit = intersectRayPlane(
        obliqueRay,
        point: const Point3D(1e308, -1e308, 2),
        normal: Vector3D(1, 1, 1),
      );
      expect(obliqueHit, const Point3D(-1e308, 1e308, 2));

      const diagonalRay = Ray3D(Point3D.origin, Vector3D(1, 1, 1));
      final diagonalHit = intersectRayPlane(
        diagonalRay,
        point: const Point3D(1.7e308, 1.7e308, -1.5e308),
        normal: Vector3D(1, 1, 1),
      );
      expect(diagonalHit, isNotNull);
      expect(
        diagonalHit!.x.isFinite &&
            diagonalHit.y.isFinite &&
            diagonalHit.z.isFinite,
        isTrue,
      );

      const oppositeDiagonalRay = Ray3D(
        Point3D(-1.7e308, 1.7e308, 5),
        Vector3D(1, 1, 1),
      );
      final oppositeDiagonalHit = intersectRayPlane(
        oppositeDiagonalRay,
        point: const Point3D(1.7e308, -1.7e308, 8),
        normal: Vector3D(1, 1, 1),
      );
      expect(oppositeDiagonalHit, isNotNull);
      expect(
        oppositeDiagonalHit!.x.isFinite &&
            oppositeDiagonalHit.y.isFinite &&
            oppositeDiagonalHit.z.isFinite,
        isTrue,
      );

      const tinyResidualRay = Ray3D(
        Point3D(-1.7e308, 1.7e308, 0),
        Vector3D.unitZ,
      );
      expect(
        intersectRayPlane(
          tinyResidualRay,
          point: const Point3D(1.7e308, -1.7e308, 1e-200),
          normal: Vector3D(1, 1, 1),
        ),
        const Point3D(-1.7e308, 1.7e308, 1e-200),
      );

      const weightedCancellationRay = Ray3D(
        Point3D(-1.5e308, 9.2e307, 0),
        Vector3D(0.8, 0.6, 0),
      );
      final weightedCancellationHit = intersectRayPlane(
        weightedCancellationRay,
        point: const Point3D(1.5e308, -9.2e307, 0),
        normal: const Vector3D(0.8, 0.6, 0),
      );
      expect(weightedCancellationHit, isNotNull);
      expect(
        weightedCancellationHit!.x.isFinite &&
            weightedCancellationHit.y.isFinite &&
            weightedCancellationHit.z.isFinite,
        isTrue,
      );
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

      final overflowIntermediateCancellationResidual = ConstructionState(
        tool: ConstructionTool.reflectionInPlane,
      );
      overflowIntermediateCancellationResidual.addPoint(
        const Point3D(1.7e308, -1.7e308, 1e-20),
      );
      overflowIntermediateCancellationResidual.addPoint(
        const Point3D(-1.7e308, 1.7e308, 0),
      );
      overflowIntermediateCancellationResidual.addPoint(Point3D.origin);
      expect(
        overflowIntermediateCancellationResidual.addPoint(
          const Point3D(0, 1.7e308, -1.7e308),
        ),
        ConstructionAction.complete,
      );
      expect(
        overflowIntermediateCancellationResidual.result!.point.z / 1e-20,
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

    test('three-point plane rejects an overflowing finite offset', () {
      const a = Point3D(1.3e308, 1.3e308, 0);
      final construction = ConstructionState(tool: ConstructionTool.plane);
      construction.addPoint(a);
      construction.addPoint(const Point3D(1.3e308, 1.3e308, 1));

      expect(
        construction.addPoint(
          const Point3D(1.300000000000002e308, 1.299999999999998e308, 0),
        ),
        ConstructionAction.awaitInput,
      );
      expect(construction.result, isNull);
      expect(construction.points, hasLength(2));
    });

    test('normal-defined planes reject overflowing offsets and keep ordinary ones valid', () {
      const largePoint = Point3D(1.3e308, 1.3e308, 0);
      final large = ConstructionState(tool: ConstructionTool.generalPlane);
      large.addPoint(largePoint);
      expect(
        large.addPoint(
          const Point3D(1.300000000000002e308, 1.300000000000002e308, 0),
        ),
        ConstructionAction.awaitInput,
      );
      expect(large.result, isNull);
      expect(large.points, [largePoint]);

      final ordinary = ConstructionState(tool: ConstructionTool.generalPlane);
      ordinary.addPoint(const Point3D(1, 2, 3));
      expect(
        ordinary.addPoint(const Point3D(2, 3, 3)),
        ConstructionAction.complete,
      );
      final plane = ordinary.result!;
      expect(
        [
          plane.planeA,
          plane.planeB,
          plane.planeC,
          plane.planeD,
        ].every((coefficient) => coefficient.isFinite),
        isTrue,
      );
      expect(
        plane.planeA * 1 + plane.planeB * 2 + plane.planeC * 3,
        closeTo(plane.planeD, 1e-12),
      );
    });

    test('line rejects duplicate endpoints', () {
      final construction = ConstructionState(tool: ConstructionTool.line);
      const point = Point3D(2, -1, 4);
      construction.addPoint(point);

      expect(construction.addPoint(point), ConstructionAction.awaitInput);
      expect(construction.points, [point]);
      expect(construction.result, isNull);
    });

    test('regular polygon and tetrahedron reject unrepresentable edges', () {
      for (final tool in [
        ConstructionTool.regularPolygon,
        ConstructionTool.tetrahedron,
      ]) {
        final construction = ConstructionState(tool: tool);
        construction.addPoint(Point3D.origin);
        final preview = construction.previewObject;

        expect(
          construction.addPoint(const Point3D(1.4e308, 1.4e308, 0)),
          ConstructionAction.awaitInput,
          reason: '$tool',
        );
        expect(construction.points, [Point3D.origin], reason: '$tool');
        expect(construction.stepIndex, 1, reason: '$tool');
        expect(construction.previewObject, same(preview), reason: '$tool');
        expect(construction.result, isNull, reason: '$tool');

        expect(
          construction.addPoint(const Point3D(2, 0, 0)),
          ConstructionAction.complete,
          reason: '$tool valid control',
        );
        expect(
          construction.result!.vertices.every(
            (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
          ),
          isTrue,
          reason: '$tool valid control',
        );
      }
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

    test('round solids reject radii that produce non-finite meshes', () {
      for (final tool in [ConstructionTool.cone, ConstructionTool.cylinder]) {
        final construction = ConstructionState(tool: tool);
        construction.addPoint(Point3D.origin);
        construction.addPoint(const Point3D(1.3e308, 1.3e308, 0));

        expect(
          construction.addPoint(const Point3D(0, 0, 1)),
          ConstructionAction.awaitInput,
          reason: '$tool must reject a radius whose magnitude overflows',
        );
        expect(construction.points, [
          Point3D.origin,
          const Point3D(1.3e308, 1.3e308, 0),
        ]);
        expect(construction.result, isNull);
      }
    });

    test('cone rejects zero height and an axis-degenerate radius', () {
      final zeroHeight = ConstructionState(tool: ConstructionTool.cone);
      zeroHeight.addPoint(Point3D.origin);
      zeroHeight.addPoint(const Point3D(2, 0, 0));
      expect(
        zeroHeight.addPoint(Point3D.origin),
        ConstructionAction.awaitInput,
      );
      expect(zeroHeight.points, [Point3D.origin, const Point3D(2, 0, 0)]);
      expect(zeroHeight.result, isNull);
      expect(
        zeroHeight.currentInstruction,
        '高度必须大于 0 且半径方向不能与高度方向平行，请重新选择顶部位置',
      );

      final axialRadius = ConstructionState(tool: ConstructionTool.cone);
      axialRadius.addPoint(Point3D.origin);
      axialRadius.addPoint(const Point3D(0, 0, 2));
      expect(
        axialRadius.addPoint(const Point3D(0, 0, 3)),
        ConstructionAction.awaitInput,
      );
      expect(axialRadius.points, [Point3D.origin, const Point3D(0, 0, 2)]);
      expect(axialRadius.result, isNull);
      expect(
        axialRadius.currentInstruction,
        '高度必须大于 0 且半径方向不能与高度方向平行，请重新选择顶部位置',
      );
    });

    test('cylinder rejects zero height and an axis-degenerate radius', () {
      final zeroHeight = ConstructionState(tool: ConstructionTool.cylinder);
      zeroHeight.addPoint(Point3D.origin);
      zeroHeight.addPoint(const Point3D(2, 0, 0));
      expect(
        zeroHeight.addPoint(Point3D.origin),
        ConstructionAction.awaitInput,
      );
      expect(zeroHeight.points, [Point3D.origin, const Point3D(2, 0, 0)]);
      expect(zeroHeight.result, isNull);
      expect(
        zeroHeight.currentInstruction,
        '高度必须大于 0 且半径方向不能与高度方向平行，请重新选择顶部位置',
      );

      final axialRadius = ConstructionState(tool: ConstructionTool.cylinder);
      axialRadius.addPoint(Point3D.origin);
      axialRadius.addPoint(const Point3D(0, 0, 2));
      expect(
        axialRadius.addPoint(const Point3D(0, 0, 3)),
        ConstructionAction.awaitInput,
      );
      expect(axialRadius.points, [Point3D.origin, const Point3D(0, 0, 2)]);
      expect(axialRadius.result, isNull);
      expect(
        axialRadius.currentInstruction,
        '高度必须大于 0 且半径方向不能与高度方向平行，请重新选择顶部位置',
      );
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

    test(
      'extruded prism rejects a finite height point that overflows its mesh',
      () {
        final prism = ConstructionState(tool: ConstructionTool.extrudePrism);
        prism.addPoint(Point3D.origin);
        prism.addPoint(const Point3D(1, -1, 0));
        prism.addPoint(const Point3D(1, 0, -1));

        expect(
          prism.addPoint(const Point3D(1.1e308, 1.1e308, 1.1e308)),
          ConstructionAction.awaitInput,
        );
        expect(prism.points, [
          Point3D.origin,
          const Point3D(1, -1, 0),
          const Point3D(1, 0, -1),
        ]);
        expect(prism.result, isNull);

        expect(
          prism.addPoint(const Point3D(0, 0, 3)),
          ConstructionAction.complete,
        );
        expect(prism.result?.vertices.length, 6);
        expect(
          prism.result!.vertices.every(
            (point) => point.x.isFinite && point.y.isFinite && point.z.isFinite,
          ),
          isTrue,
        );
      },
    );
  });
}
