import 'dart:math' as math;

import '../models/math_3d_object.dart';

/// Returns the circle or tangent point where [sphere] meets [plane].
Object3D? spherePlaneIntersectionCurve(Object3D sphere, Object3D plane) {
  final equation = _planeEquation(plane);
  if (equation == null) return null;

  final center = sphere.sphereCenter;
  final radius = sphere.sphereRadius.abs();
  if (!_finitePoint(center) || !radius.isFinite) return null;

  final centerScale = math.max(
    math.max(center.x.abs(), center.y.abs()),
    center.z.abs(),
  );
  final normalLength = math.sqrt(equation.normalSquared);
  final scaledCenter = centerScale == 0
      ? Vector3D.zero
      : Vector3D(
          center.x / centerScale,
          center.y / centerScale,
          center.z / centerScale,
        );
  final scaledCenterDot = equation.normal.dot(scaledCenter);
  final scaledSignedDistance = centerScale == 0
      ? -_quotientByProduct(equation.d, [
          equation.coefficientScale,
          normalLength,
        ])
      : centerScale *
            (scaledCenterDot / normalLength -
                _quotientByProduct(equation.d, [
                  centerScale,
                  equation.coefficientScale,
                  normalLength,
                ]));
  final directCenterDot =
      equation.normal.x * center.x +
      equation.normal.y * center.y +
      equation.normal.z * center.z;
  final projectedCenter = directCenterDot.isFinite
      ? directCenterDot / normalLength
      : centerScale * (scaledCenterDot / normalLength);
  final planeOffset = _quotientByProduct(equation.d, [
    equation.coefficientScale,
    normalLength,
  ]);
  final signedDistance = projectedCenter.isFinite && planeOffset.isFinite
      ? projectedCenter - planeOffset
      : scaledSignedDistance;
  if (!signedDistance.isFinite) return null;

  final distance = signedDistance.abs();
  final geometryScale = math.max(radius, distance);
  final projectedCenterMagnitude =
      (equation.normal.x * scaledCenter.x).abs() +
      (equation.normal.y * scaledCenter.y).abs() +
      (equation.normal.z * scaledCenter.z).abs();
  final projectedCenterRatio = projectedCenterMagnitude / normalLength;
  final planeOffsetRatio = centerScale == 0
      ? 0.0
      : _quotientByProduct(equation.d.abs(), [
          centerScale,
          equation.coefficientScale,
          normalLength,
        ]);
  final isUnitAxisNormal =
      normalLength == 1 &&
      ((equation.normal.x.abs() == 1 &&
              equation.normal.y == 0 &&
              equation.normal.z == 0) ||
          (equation.normal.y.abs() == 1 &&
              equation.normal.x == 0 &&
              equation.normal.z == 0) ||
          (equation.normal.z.abs() == 1 &&
              equation.normal.x == 0 &&
              equation.normal.y == 0));
  final smallerProjection = math.min(projectedCenter.abs(), planeOffset.abs());
  final largerProjection = math.max(projectedCenter.abs(), planeOffset.abs());
  final exactAxisAlignedComparison =
      isUnitAxisNormal &&
      equation.coefficientScale == 1 &&
      _sumIsExact(projectedCenter, -planeOffset) &&
      (smallerProjection == 0 || smallerProjection >= largerProjection / 2);
  final exactDistanceEvaluation =
      _productIsExact(equation.normal.x, center.x) &&
      _productIsExact(equation.normal.y, center.y) &&
      _productIsExact(equation.normal.z, center.z) &&
      _sumIsExact(equation.normal.x * center.x, equation.normal.y * center.y) &&
      _sumIsExact(
        equation.normal.x * center.x + equation.normal.y * center.y,
        equation.normal.z * center.z,
      ) &&
      _productIsExact(normalLength, normalLength) &&
      normalLength * normalLength == equation.normalSquared &&
      projectedCenter * normalLength == directCenterDot &&
      _sumIsExact(projectedCenter, -planeOffset) &&
      (equation.d == 0 ||
          planeOffset * equation.coefficientScale * normalLength == equation.d);
  final coordinateTolerance = exactAxisAlignedComparison
      ? 0.0
      : centerScale *
            (math.max(projectedCenterRatio, planeOffsetRatio) *
                4.440892098500626e-16);
  if (geometryScale != 0 && coordinateTolerance >= geometryScale) {
    return null;
  }
  if (distance == radius &&
      coordinateTolerance > 0 &&
      !exactDistanceEvaluation) {
    return null;
  }
  if (distance != radius && (distance - radius).abs() <= coordinateTolerance) {
    return null;
  }
  final tolerance = math.max(geometryScale * 1e-12, coordinateTolerance);
  final comparisonScale = math.max(radius, distance);
  if (comparisonScale != 0 &&
      distance / comparisonScale >
          radius / comparisonScale + tolerance / comparisonScale) {
    return null;
  }

  final circleCenter =
      center + equation.normal * (-signedDistance / normalLength);
  final distanceRatio = radius == 0 ? 0.0 : (distance / radius).clamp(0.0, 1.0);
  final circleRadius = radius * math.sqrt(1 - distanceRatio * distanceRatio);
  return _circleOnPlane(circleCenter, equation.normal, circleRadius);
}

/// Returns the circle or tangent point where [first] and [second] meet.
Object3D? sphereSphereIntersectionCurve(Object3D first, Object3D second) {
  final firstCenter = first.sphereCenter;
  final secondCenter = second.sphereCenter;
  if (!_finitePoint(firstCenter) || !_finitePoint(secondCenter)) return null;

  final delta = secondCenter - firstCenter;
  final firstRadius = first.sphereRadius.abs();
  final secondRadius = second.sphereRadius.abs();
  if (!firstRadius.isFinite || !secondRadius.isFinite) {
    return null;
  }

  final coordinateScale = [
    firstCenter.x.abs(),
    firstCenter.y.abs(),
    firstCenter.z.abs(),
    secondCenter.x.abs(),
    secondCenter.y.abs(),
    secondCenter.z.abs(),
  ].fold<double>(0, (scale, value) => math.max(scale, value).toDouble());
  final deltaIsFinite = _finiteVector(delta);
  final distance = deltaIsFinite ? _scaledMagnitude(delta) : double.infinity;
  if (distance == 0 && firstRadius == 0 && secondRadius == 0) {
    return Object3D.point(firstCenter, color: 0xFF1565C0);
  }
  final scale = math.max(
    deltaIsFinite && distance.isFinite ? distance : coordinateScale,
    math.max(firstRadius, secondRadius),
  );
  if (scale == 0) return Object3D.point(firstCenter, color: 0xFF1565C0);
  final scaledDelta = deltaIsFinite && distance.isFinite
      ? Vector3D(delta.x / scale, delta.y / scale, delta.z / scale)
      : Vector3D(
          secondCenter.x / scale - firstCenter.x / scale,
          secondCenter.y / scale - firstCenter.y / scale,
          secondCenter.z / scale - firstCenter.z / scale,
        );
  final scaledDistance = _scaledMagnitude(scaledDelta);
  if (!scaledDistance.isFinite ||
      (scaledDistance == 0 && (!deltaIsFinite || !distance.isFinite))) {
    return null;
  }
  final distanceRatio = deltaIsFinite && distance.isFinite
      ? distance / scale
      : scaledDistance;
  final scaledFirstRadius = firstRadius / scale;
  final scaledSecondRadius = secondRadius / scale;
  final scaledGeometry = math.max(
    distanceRatio,
    math.max(scaledFirstRadius, scaledSecondRadius),
  );
  final coordinateTolerance = deltaIsFinite && distance.isFinite
      ? 0.0
      : coordinateScale / scale * 4.440892098500626e-16;
  if (scaledGeometry != 0 && coordinateTolerance >= scaledGeometry) {
    return null;
  }
  final scaledTolerance = math.max(scaledGeometry * 1e-12, coordinateTolerance);
  if (distanceRatio >
          scaledFirstRadius + scaledSecondRadius + scaledTolerance ||
      distanceRatio <
          (scaledFirstRadius - scaledSecondRadius).abs() - scaledTolerance) {
    return null;
  }
  if (distanceRatio == 0 && scaledFirstRadius != scaledSecondRadius) {
    return null;
  }

  final axis = deltaIsFinite && distance.isFinite
      ? Vector3D(delta.x / distance, delta.y / distance, delta.z / distance)
      : Vector3D(
          scaledDelta.x / scaledDistance,
          scaledDelta.y / scaledDistance,
          scaledDelta.z / scaledDistance,
        );
  if (!_finiteVector(axis)) return null;
  final alongRatio = scaledFirstRadius == scaledSecondRadius
      ? distanceRatio / 2
      : (scaledFirstRadius * scaledFirstRadius -
                scaledSecondRadius * scaledSecondRadius +
                distanceRatio * distanceRatio) /
            (2 * distanceRatio);
  final along =
      scaledFirstRadius == scaledSecondRadius &&
          deltaIsFinite &&
          distance.isFinite
      ? distance / 2
      : scale * alongRatio;
  if (!along.isFinite) return null;
  final center = firstCenter + axis * along;
  final radiusRatioSquared =
      scaledFirstRadius * scaledFirstRadius - alongRatio * alongRatio;
  final scaledRadiusTolerance =
      scaledTolerance * (scaledFirstRadius + alongRatio.abs()) +
      scaledTolerance * scaledTolerance;
  if (radiusRatioSquared < -scaledRadiusTolerance) return null;
  final radius =
      scale * math.sqrt(math.max(0.0, radiusRatioSquared).toDouble());
  return _circleOnPlane(center, axis, radius);
}

({Vector3D normal, double d, double coefficientScale, double normalSquared})?
_planeEquation(Object3D plane) {
  final a = plane.planeA;
  final b = plane.planeB;
  final c = plane.planeC;
  final d = plane.planeD;
  if (!a.isFinite || !b.isFinite || !c.isFinite || !d.isFinite) return null;
  final scale = math.max(a.abs(), math.max(b.abs(), c.abs()));
  if (scale == 0 || !scale.isFinite) return null;
  final normal = Vector3D(a / scale, b / scale, c / scale);
  final normalSquared = normal.dot(normal);
  if (!normalSquared.isFinite || normalSquared == 0) {
    return null;
  }
  return (
    normal: normal,
    d: d,
    coefficientScale: scale,
    normalSquared: normalSquared,
  );
}

double _quotientByProduct(double numerator, List<double> factors) {
  if (numerator == 0) return numerator;
  double? tryOrder(double value, List<double> remaining) {
    if (remaining.isEmpty) return value;
    for (var i = 0; i < remaining.length; i++) {
      final next = value / remaining[i];
      if (!next.isFinite || (next == 0 && remaining.length > 1)) continue;
      final rest = [...remaining]..removeAt(i);
      final result = tryOrder(next, rest);
      if (result != null) return result;
    }
    return null;
  }

  final orderedResult = tryOrder(numerator, factors);
  if (orderedResult != null) return orderedResult;
  final logMagnitude =
      math.log(numerator.abs()) -
      factors.fold<double>(0, (sum, factor) => sum + math.log(factor));
  final result = math.exp(logMagnitude);
  return numerator.isNegative ? -result : result;
}

Object3D? _circleOnPlane(Point3D center, Vector3D normal, double radius) {
  if (!_finitePoint(center) || !_finiteVector(normal) || !radius.isFinite) {
    return null;
  }
  if (radius < 0) return null;
  if (radius == 0) return Object3D.point(center, color: 0xFF1565C0);

  final normalizedNormal = normal.normalized();
  if (!_finiteVector(normalizedNormal) || normalizedNormal.magnitude == 0) {
    return null;
  }
  var u = normalizedNormal.cross(Vector3D.unitX).normalized();
  if (u.magnitude < 1e-9) {
    u = normalizedNormal.cross(Vector3D.unitY).normalized();
  }
  final v = normalizedNormal.cross(u).normalized();
  final points = List.generate(65, (i) {
    final angle = 2 * math.pi * i / 64;
    return center +
        u * (radius * math.cos(angle)) +
        v * (radius * math.sin(angle));
  });
  if (points.any((point) => !_finitePoint(point))) return null;

  final radiusSquared = radius * radius;
  final conic = radiusSquared.isFinite && radiusSquared > 0
      ? Conic3D(
          origin: center,
          axisU: u,
          axisV: v,
          quadraticX: 1,
          quadraticXY: 0,
          quadraticY: 1,
          linearX: 0,
          linearY: 0,
          constant: -radiusSquared,
        )
      : null;
  return Object3D.curve(points: points, color: 0xFF1565C0, conic: conic);
}

double _scaledMagnitude(Vector3D vector) {
  final scale = math.max(
    vector.x.abs(),
    math.max(vector.y.abs(), vector.z.abs()),
  );
  if (scale == 0) return 0;
  final x = vector.x / scale;
  final y = vector.y / scale;
  final z = vector.z / scale;
  return scale * math.sqrt(x * x + y * y + z * z);
}

bool _productIsExact(double first, double second) {
  const splitter = 134217729.0;
  final product = first * second;
  if (!product.isFinite) return false;
  final firstSplit = splitter * first;
  final secondSplit = splitter * second;
  if (!firstSplit.isFinite || !secondSplit.isFinite) return false;
  final firstHigh = firstSplit - (firstSplit - first);
  final firstLow = first - firstHigh;
  final secondHigh = secondSplit - (secondSplit - second);
  final secondLow = second - secondHigh;
  final error =
      ((firstHigh * secondHigh - product) + firstHigh * secondLow) +
      firstLow * secondHigh +
      firstLow * secondLow;
  return error == 0;
}

bool _sumIsExact(double first, double second) {
  final sum = first + second;
  if (!sum.isFinite) return false;
  final secondVirtual = sum - first;
  final error = (first - (sum - secondVirtual)) + (second - secondVirtual);
  return error == 0;
}

bool _finitePoint(Point3D point) =>
    point.x.isFinite && point.y.isFinite && point.z.isFinite;

bool _finiteVector(Vector3D vector) =>
    vector.x.isFinite && vector.y.isFinite && vector.z.isFinite;
