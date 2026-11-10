import 'dart:math' as math;

import 'math_expression.dart';

/// Result of numerically estimating a derivative at one point.
enum LocalDerivativeStatus {
  /// A finite centered difference gave a stable estimate.
  estimated,

  /// The function is not finite close to the requested point.
  undefined,

  /// One-sided slopes grow without a stable finite limit.
  possibleVerticalTangent,

  /// Nearby samples do not support a reliable derivative estimate.
  unstable,
}

/// Numerical derivative and nearby function value for an explicit function.
class LocalDerivativeResult {
  /// The requested x-coordinate.
  final double x;

  /// The function value at [x], when defined.
  final double? y;

  /// The estimated first derivative, when finite and stable.
  final double? derivative;

  /// The estimated second derivative, when finite and stable.
  final double? secondDerivative;

  /// Numerical status of the estimate.
  final LocalDerivativeStatus status;

  /// Step size used for the finite difference.
  final double step;

  const LocalDerivativeResult({
    required this.x,
    required this.y,
    required this.derivative,
    required this.secondDerivative,
    required this.status,
    required this.step,
  });

  /// Whether a tangent and normal can be drawn from this estimate.
  bool get hasFiniteTangent =>
      status == LocalDerivativeStatus.estimated &&
      y != null &&
      derivative != null;
}

/// A detected local feature, classified from sampled slope behavior.
class LocalCriticalPoint {
  /// Approximate x-coordinate of the feature.
  final double x;

  /// Approximate function value.
  final double y;

  /// Classification supported by the samples.
  final LocalCriticalPointKind kind;

  const LocalCriticalPoint({
    required this.x,
    required this.y,
    required this.kind,
  });
}

/// Sample-based classification for a local critical point.
enum LocalCriticalPointKind {
  /// Samples rise on both sides of the point.
  localMinimum,

  /// Samples fall on both sides of the point.
  localMaximum,

  /// Slope appears to retain its sign while curvature changes sign.
  possibleStationaryInflection,
}

/// Numerical tools for explicit 2D functions.
///
/// These results are estimates from finite samples. They describe local
/// behavior at the chosen resolution and do not prove global properties.
class MathLocalAnalysis {
  const MathLocalAnalysis._();

  /// Estimates first and second derivatives near [x].
  static LocalDerivativeResult derivativeAt(
    MathExpression expression,
    double x, {
    double? domainMin,
    double? domainMax,
  }) {
    var step = math.max(1e-5, x.abs() * 1e-5).toDouble();
    if (!expression.isValid ||
        expression.type != MathExpressionType.explicit ||
        !x.isFinite) {
      return LocalDerivativeResult(
        x: x,
        y: null,
        derivative: null,
        secondDerivative: null,
        status: LocalDerivativeStatus.undefined,
        step: step,
      );
    }
    if (domainMin != null) {
      step = math.min(step, (x - domainMin) / 2).toDouble();
    }
    if (domainMax != null) {
      step = math.min(step, (domainMax - x) / 2).toDouble();
    }
    if (!step.isFinite || step <= 0) {
      return LocalDerivativeResult(
        x: x,
        y: null,
        derivative: null,
        secondDerivative: null,
        status: LocalDerivativeStatus.undefined,
        step: 0,
      );
    }
    final f = expression.evaluator;
    double? at(double value) {
      try {
        final result = f(value);
        return result.isFinite ? result : null;
      } catch (_) {
        return null;
      }
    }

    final y = at(x);
    final left = at(x - step);
    final right = at(x + step);
    if (y == null) {
      return LocalDerivativeResult(
        x: x,
        y: null,
        derivative: null,
        secondDerivative: null,
        status: LocalDerivativeStatus.undefined,
        step: step,
      );
    }
    if (left == null || right == null) {
      final oneSided = left == null ? right : left;
      final halfSide = left == null ? at(x + step / 2) : at(x - step / 2);
      final coarseSlope = oneSided == null
          ? double.nan
          : (oneSided - y) / (left == null ? step : -step);
      final fineSlope = halfSide == null
          ? double.nan
          : (halfSide - y) / (left == null ? step / 2 : -step / 2);
      final vertical =
          coarseSlope.isFinite &&
          fineSlope.isFinite &&
          coarseSlope.abs() > 10 &&
          fineSlope.abs() > coarseSlope.abs() * 1.2;
      return LocalDerivativeResult(
        x: x,
        y: y,
        derivative: null,
        secondDerivative: null,
        status: vertical
            ? LocalDerivativeStatus.possibleVerticalTangent
            : LocalDerivativeStatus.undefined,
        step: step,
      );
    }
    final leftSlope = (y - left) / step;
    final rightSlope = (right - y) / step;
    if (!leftSlope.isFinite || !rightSlope.isFinite) {
      return LocalDerivativeResult(
        x: x,
        y: y,
        derivative: null,
        secondDerivative: null,
        status: LocalDerivativeStatus.unstable,
        step: step,
      );
    }
    final halfLeft = at(x - step / 2);
    final halfRight = at(x + step / 2);
    final finerLeftSlope = halfLeft == null
        ? double.nan
        : (y - halfLeft) / (step / 2);
    final finerRightSlope = halfRight == null
        ? double.nan
        : (halfRight - y) / (step / 2);
    final coarseSideMismatch = (leftSlope - rightSlope).abs();
    final finerSideMismatch = (finerLeftSlope - finerRightSlope).abs();
    if (finerSideMismatch.isFinite &&
        finerSideMismatch > coarseSideMismatch * 1.5) {
      return LocalDerivativeResult(
        x: x,
        y: y,
        derivative: null,
        secondDerivative: null,
        status: LocalDerivativeStatus.unstable,
        step: step,
      );
    }
    if (leftSlope * rightSlope > 0 &&
        finerLeftSlope.isFinite &&
        finerRightSlope.isFinite &&
        finerLeftSlope.abs() > math.max(10, leftSlope.abs() * 1.2) &&
        finerRightSlope.abs() > math.max(10, rightSlope.abs() * 1.2)) {
      return LocalDerivativeResult(
        x: x,
        y: y,
        derivative: null,
        secondDerivative: null,
        status: LocalDerivativeStatus.possibleVerticalTangent,
        step: step,
      );
    }
    if (leftSlope * rightSlope < 0 &&
        finerLeftSlope.isFinite &&
        finerRightSlope.isFinite &&
        finerLeftSlope.abs() >= leftSlope.abs() * 0.8 &&
        finerRightSlope.abs() >= rightSlope.abs() * 0.8) {
      return LocalDerivativeResult(
        x: x,
        y: y,
        derivative: null,
        secondDerivative: null,
        status: LocalDerivativeStatus.unstable,
        step: step,
      );
    }
    final derivative = (right - left) / (2 * step);
    final secondDerivative = (right - 2 * y + left) / (step * step);
    if (!derivative.isFinite || !secondDerivative.isFinite) {
      return LocalDerivativeResult(
        x: x,
        y: y,
        derivative: null,
        secondDerivative: null,
        status: LocalDerivativeStatus.unstable,
        step: step,
      );
    }
    return LocalDerivativeResult(
      x: x,
      y: y,
      derivative: derivative,
      secondDerivative: secondDerivative,
      status: LocalDerivativeStatus.estimated,
      step: step,
    );
  }

  /// Finds sampled local extrema and possible stationary inflections in an interval.
  ///
  /// A possible stationary inflection is included only when a near-zero
  /// derivative estimate is accompanied by opposite-sign second differences
  /// on either side. The label remains tentative because samples cannot prove
  /// the behavior between points.
  static List<LocalCriticalPoint> criticalPoints(
    MathExpression expression, {
    required double xMin,
    required double xMax,
    int samples = 400,
  }) {
    if (!expression.isValid ||
        expression.type != MathExpressionType.explicit ||
        !xMin.isFinite ||
        !xMax.isFinite ||
        xMin >= xMax ||
        samples < 8) {
      return const [];
    }
    final step = (xMax - xMin) / samples;
    if (!step.isFinite || step <= 0) return const [];
    double? value(double x) {
      try {
        final y = expression.evaluator(x);
        return y.isFinite ? y : null;
      } catch (_) {
        return null;
      }
    }

    final xs = List<double>.generate(samples + 1, (i) => xMin + i * step);
    final ys = xs.map(value).toList(growable: false);
    final points = <LocalCriticalPoint>[];
    for (var i = 1; i < samples; i++) {
      final before = ys[i - 1];
      final at = ys[i];
      final after = ys[i + 1];
      if (before == null || at == null || after == null) continue;
      final isMinimum =
          at <= before && at <= after && (at < before || at < after);
      final isMaximum =
          at >= before && at >= after && (at > before || at > after);
      if (!isMinimum && !isMaximum) continue;
      final leftMidpoint = value((xs[i - 1] + xs[i]) / 2);
      final rightMidpoint = value((xs[i] + xs[i + 1]) / 2);
      final localVariation = math.max(
        1e-12,
        math.max(
          (at - before).abs(),
          math.max((after - at).abs(), (after - before).abs()),
        ),
      );
      if (leftMidpoint == null || rightMidpoint == null) continue;
      final leftInterpolation = (before + at) / 2;
      final rightInterpolation = (at + after) / 2;
      if ((leftMidpoint - leftInterpolation).abs() > localVariation * 0.3 ||
          (rightMidpoint - rightInterpolation).abs() > localVariation * 0.3) {
        continue;
      }
      final leftSlope = (at - before) / step;
      final rightSlope = (after - at) / step;
      final finerLeftSlope = (at - leftMidpoint) / (step / 2);
      final finerRightSlope = (rightMidpoint - at) / (step / 2);
      final coarseMismatch = (leftSlope - rightSlope).abs();
      final finerMismatch = (finerLeftSlope - finerRightSlope).abs();
      if (finerMismatch > coarseMismatch * 1.5) continue;
      points.add(
        LocalCriticalPoint(
          x: xs[i],
          y: at,
          kind: isMinimum
              ? LocalCriticalPointKind.localMinimum
              : LocalCriticalPointKind.localMaximum,
        ),
      );
    }

    // Inflection candidates require a near-stationary sampled point and a
    // curvature sign change. This deliberately favors false negatives over
    // claiming a stationary inflection from a noisy/discontinuous sample.
    for (var i = 2; i < samples - 2; i++) {
      final x = xMin + i * step;
      final before = value(x - step);
      final at = value(x);
      final after = value(x + step);
      final before2 = value(x - 2 * step);
      final after2 = value(x + 2 * step);
      if (before == null ||
          at == null ||
          after == null ||
          before2 == null ||
          after2 == null) {
        continue;
      }
      final first = (after - before) / (2 * step);
      final finerBefore = value(x - step / 2);
      final finerAfter = value(x + step / 2);
      if (finerBefore == null || finerAfter == null) continue;
      final finerFirst = (finerAfter - finerBefore) / step;
      final leftCurvature = (at - 2 * before + before2) / (step * step);
      final rightCurvature = (after2 - 2 * after + at) / (step * step);
      final localVariation = math.max(
        1e-12,
        math.max(
          (at - before).abs(),
          math.max((after - at).abs(), (after - before).abs()),
        ),
      );
      final derivativeTolerance = localVariation / step * 1e-3;
      if (finerFirst.abs() <=
              math.max(derivativeTolerance, first.abs() * 0.4) &&
          leftCurvature.isFinite &&
          rightCurvature.isFinite &&
          leftCurvature * rightCurvature < 0 &&
          !points.any((point) => (point.x - x).abs() <= step * 1.5)) {
        points.add(
          LocalCriticalPoint(
            x: x,
            y: at,
            kind: LocalCriticalPointKind.possibleStationaryInflection,
          ),
        );
      }
    }
    points.sort((a, b) => a.x.compareTo(b.x));
    final deduplicated = <LocalCriticalPoint>[];
    for (final point in points) {
      if (deduplicated.isEmpty ||
          (point.x - deduplicated.last.x).abs() > step * 1.5) {
        deduplicated.add(point);
      }
    }
    return List.unmodifiable(deduplicated);
  }
}
