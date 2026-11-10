import 'dart:math' as math;

import 'math_expression.dart';

/// The quantity calculated from one or two explicit functions.
enum DefiniteIntegralKind {
  /// The signed value of the integral of f(x).
  signedIntegral,

  /// The geometric area between f(x) and the x-axis.
  areaUnderCurve,

  /// The geometric area between two functions.
  areaBetweenCurves,
}

/// The outcome of an adaptive numerical definite integral.
enum DefiniteIntegralStatus {
  /// The estimated absolute error is within the requested tolerance.
  converged,

  /// The refinement limit was reached before the requested tolerance.
  didNotConverge,

  /// A sampled function value was invalid, threw, or was non-finite.
  invalidFunction,

  /// Bounds are non-finite or the lower bound is not less than the upper.
  invalidBounds,

  /// The tolerance or refinement depth is invalid.
  invalidOptions,

  /// The supplied expression is invalid or is not an explicit function.
  invalidExpression,
}

/// Result of a numerical definite integral.
class DefiniteIntegralResult {
  /// The integral estimate, or null when evaluation could not produce one.
  final double? value;

  /// Estimated absolute error from the adaptive Simpson refinement.
  final double estimatedAbsoluteError;

  /// Number of underlying function evaluations used by quadrature estimates.
  final int evaluationCount;

  /// Whether the estimate met its tolerance or why it did not.
  final DefiniteIntegralStatus status;

  const DefiniteIntegralResult({
    required this.value,
    required this.estimatedAbsoluteError,
    required this.evaluationCount,
    required this.status,
  });

  /// Whether the requested tolerance was reached.
  bool get converged => status == DefiniteIntegralStatus.converged;
}

/// Numerically integrates an explicit function over finite ordered bounds.
///
/// Adaptive Simpson refinement estimates the value and its absolute error.
/// Four differently sized initial partitions are compared before convergence
/// is reported, which reduces false convergence from sampled-out oscillations.
/// Trigonometric phases are also checked on uniform and off-grid samples. For
/// geometric areas, the integrand is the absolute function value or absolute
/// difference of the two functions. This is a numerical method, not a proof
/// that an arbitrary expression has no unsampled discontinuities. Possible
/// denominator zeros are checked over the selected interval; possible
/// discontinuities and unresolved oscillations are reported as inconclusive
/// because finite sampling cannot rule them all out.
///
/// [parameterValues] and [secondParameterValues] provide values used while
/// checking parameterized denominators. The supplied expressions should also
/// be parameterized for numerical evaluation.
DefiniteIntegralResult calculateDefiniteIntegral({
  required MathExpression function,
  required double lowerBound,
  required double upperBound,
  DefiniteIntegralKind kind = DefiniteIntegralKind.signedIntegral,
  MathExpression? secondFunction,
  Map<String, double> parameterValues = const {},
  Map<String, double> secondParameterValues = const {},
  double absoluteTolerance = 1e-8,
  int maxDepth = 20,
}) {
  if (!lowerBound.isFinite ||
      !upperBound.isFinite ||
      upperBound <= lowerBound ||
      !(upperBound - lowerBound).isFinite) {
    return const DefiniteIntegralResult(
      value: null,
      estimatedAbsoluteError: double.infinity,
      evaluationCount: 0,
      status: DefiniteIntegralStatus.invalidBounds,
    );
  }
  if (!absoluteTolerance.isFinite || absoluteTolerance <= 0 || maxDepth < 1) {
    return const DefiniteIntegralResult(
      value: null,
      estimatedAbsoluteError: double.infinity,
      evaluationCount: 0,
      status: DefiniteIntegralStatus.invalidOptions,
    );
  }
  if (!function.isValid ||
      function.type != MathExpressionType.explicit ||
      (kind == DefiniteIntegralKind.areaBetweenCurves &&
          (secondFunction == null ||
              !secondFunction.isValid ||
              secondFunction.type != MathExpressionType.explicit))) {
    return const DefiniteIntegralResult(
      value: null,
      estimatedAbsoluteError: double.infinity,
      evaluationCount: 0,
      status: DefiniteIntegralStatus.invalidExpression,
    );
  }

  var evaluations = 0;
  double differenceFromSecond(double first, double x) {
    evaluations++;
    return (first - secondFunction!.evaluator(x)).abs();
  }

  double evaluate(double x) {
    evaluations++;
    final first = function.evaluator(x);
    if (!first.isFinite) throw const _InvalidSample();
    final value = switch (kind) {
      DefiniteIntegralKind.signedIntegral => first,
      DefiniteIntegralKind.areaUnderCurve => first.abs(),
      DefiniteIntegralKind.areaBetweenCurves => differenceFromSecond(first, x),
    };
    if (!value.isFinite) throw const _InvalidSample();
    return value;
  }

  final unresolvedOscillation =
      _hasUnresolvedTrigOscillation(
        function.normalizedExpression,
        lowerBound,
        upperBound,
        parameterValues,
      ) ||
      (kind == DefiniteIntegralKind.areaBetweenCurves &&
          _hasUnresolvedTrigOscillation(
            secondFunction!.normalizedExpression,
            lowerBound,
            upperBound,
            secondParameterValues,
          ));
  if (unresolvedOscillation) {
    return const DefiniteIntegralResult(
      value: null,
      estimatedAbsoluteError: double.infinity,
      evaluationCount: 0,
      status: DefiniteIntegralStatus.didNotConverge,
    );
  }

  try {
    final estimates = [
      _integratePartition(
        evaluate: evaluate,
        lowerBound: lowerBound,
        upperBound: upperBound,
        panels: 8,
        tolerance: absoluteTolerance,
        maxDepth: maxDepth,
      ),
      _integratePartition(
        evaluate: evaluate,
        lowerBound: lowerBound,
        upperBound: upperBound,
        panels: 11,
        tolerance: absoluteTolerance,
        maxDepth: maxDepth,
      ),
      _integratePartition(
        evaluate: evaluate,
        lowerBound: lowerBound,
        upperBound: upperBound,
        panels: 13,
        tolerance: absoluteTolerance,
        maxDepth: maxDepth,
      ),
      _integratePartition(
        evaluate: evaluate,
        lowerBound: lowerBound,
        upperBound: upperBound,
        panels: 17,
        tolerance: absoluteTolerance,
        maxDepth: maxDepth,
      ),
    ];
    final refined = estimates.last;
    var estimatedError = estimates.first.error;
    var estimateSpread = 0.0;
    for (var i = 0; i < estimates.length; i++) {
      if (estimates[i].error > estimatedError) {
        estimatedError = estimates[i].error;
      }
      for (var j = i + 1; j < estimates.length; j++) {
        final difference = (estimates[i].value - estimates[j].value).abs();
        if (difference > estimateSpread) estimateSpread = difference;
      }
    }
    if (estimateSpread > estimatedError) estimatedError = estimateSpread;
    final domainUncertain =
        _mayHaveUnsampledSingularity(
          function,
          lowerBound,
          upperBound,
          parameterValues,
        ) ||
        (kind == DefiniteIntegralKind.areaBetweenCurves &&
            _mayHaveUnsampledSingularity(
              secondFunction!,
              lowerBound,
              upperBound,
              secondParameterValues,
            ));
    final converged =
        estimates.every((estimate) => estimate.converged) &&
        estimatedError <= absoluteTolerance &&
        !domainUncertain;
    return DefiniteIntegralResult(
      value: refined.value,
      estimatedAbsoluteError: domainUncertain
          ? double.infinity
          : estimatedError,
      evaluationCount: evaluations,
      status: converged
          ? DefiniteIntegralStatus.converged
          : DefiniteIntegralStatus.didNotConverge,
    );
  } on _InvalidSample {
    return DefiniteIntegralResult(
      value: null,
      estimatedAbsoluteError: double.infinity,
      evaluationCount: evaluations,
      status: DefiniteIntegralStatus.invalidFunction,
    );
  } catch (_) {
    return DefiniteIntegralResult(
      value: null,
      estimatedAbsoluteError: double.infinity,
      evaluationCount: evaluations,
      status: DefiniteIntegralStatus.invalidFunction,
    );
  }
}

bool _mayHaveUnsampledSingularity(
  MathExpression expression,
  double lowerBound,
  double upperBound,
  Map<String, double> parameterValues,
) {
  final source = expression.normalizedExpression;
  return _hasPotentialDenominatorZero(
        source,
        lowerBound,
        upperBound,
        parameterValues,
      ) ||
      _negativePowerMayContainZero(
        source,
        lowerBound,
        upperBound,
        parameterValues,
      ) ||
      _hasSampledModuloDiscontinuity(
        source,
        lowerBound,
        upperBound,
        parameterValues,
      ) ||
      _hasSampledRoundingJump(source, lowerBound, upperBound, parameterValues);
}

bool _hasSampledModuloDiscontinuity(
  String source,
  double lowerBound,
  double upperBound,
  Map<String, double> parameterValues,
) {
  for (
    var modulo = source.indexOf('%');
    modulo >= 0;
    modulo = source.indexOf('%', modulo + 1)
  ) {
    final depthAtModulo = _parenthesisDepth(source, modulo);
    var start = modulo - 1;
    var depth = depthAtModulo;
    while (start >= 0) {
      final character = source[start];
      if (character == ')') depth++;
      if (character == '(') {
        if (depth == depthAtModulo) break;
        depth--;
      }
      if (depth == depthAtModulo &&
          (character == '+' || character == '-' || character == ',')) {
        break;
      }
      start--;
    }
    start++;

    var end = modulo + 1;
    depth = depthAtModulo;
    while (end < source.length) {
      final character = source[end];
      if (character == '(') depth++;
      if (character == ')') {
        if (depth == depthAtModulo) break;
        depth--;
      }
      if (depth == depthAtModulo &&
          (character == '+' ||
              character == '-' ||
              character == '*' ||
              character == '/' ||
              character == '%' ||
              character == ',')) {
        break;
      }
      end++;
    }

    final left = MathExpression.fromInput(source.substring(start, modulo));
    final right = MathExpression.fromInput(source.substring(modulo + 1, end));
    if (!left.isValid ||
        left.type != MathExpressionType.explicit ||
        !right.isValid ||
        right.type != MathExpressionType.explicit ||
        left.parameters.any(
          (name) => name != 'x' && !parameterValues.containsKey(name),
        ) ||
        right.parameters.any(
          (name) => name != 'x' && !parameterValues.containsKey(name),
        )) {
      return true;
    }

    final leftEvaluator = left.withParameters(parameterValues).evaluator;
    final rightEvaluator = right.withParameters(parameterValues).evaluator;
    final step = (upperBound - lowerBound) / 1024;
    int? previousQuotient;
    try {
      for (var i = 0; i <= 1024; i++) {
        final x = lowerBound + step * i;
        final divisor = rightEvaluator(x);
        final ratio = leftEvaluator(x) / divisor;
        if (!ratio.isFinite || divisor == 0) return true;
        final quotient = ratio.truncate();
        if (previousQuotient != null && quotient != previousQuotient) {
          return true;
        }
        previousQuotient = quotient;
      }
    } catch (_) {
      return true;
    }
  }
  return false;
}

int _parenthesisDepth(String source, int end) {
  var depth = 0;
  for (var i = 0; i < end; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') depth--;
  }
  return depth;
}

bool _hasUnresolvedTrigOscillation(
  String source,
  double lowerBound,
  double upperBound,
  Map<String, double> parameterValues,
) {
  final calls = RegExp(r'\b(sin|cos|tan|cot|sec|csc)\s*\(');
  for (final match in calls.allMatches(source)) {
    final open = source.indexOf('(', match.start);
    var depth = 1;
    var close = -1;
    for (var i = open + 1; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')' && --depth == 0) {
        close = i;
        break;
      }
    }
    if (close < 0) return true;
    final argument = MathExpression.fromInput(
      source.substring(open + 1, close).trim(),
    );
    if (!argument.isValid || argument.type != MathExpressionType.explicit) {
      return true;
    }
    if (argument.parameters.any(
      (name) => name != 'x' && !parameterValues.containsKey(name),
    ))
      return true;
    final evaluator = argument.withParameters(parameterValues).evaluator;
    // Keep the phase scan dense enough that ordinary, rapidly varying
    // functions can be resolved without treating the scan's own coarse step
    // as evidence of aliasing.
    const samples = 8192;
    final width = upperBound - lowerBound;
    final xSamples = [
      for (var i = 0; i <= samples; i++) lowerBound + width * (i / samples),
    ];
    // The irrationally spaced points prevent a high frequency from aligning
    // with every point on the uniform phase grid.
    const goldenFraction = 0.6180339887498949;
    for (var i = 1; i <= 257; i++) {
      final fraction = (i * goldenFraction) % 1;
      xSamples.add(lowerBound + width * fraction);
    }
    xSamples.sort();
    var previous = double.nan;
    try {
      for (final x in xSamples) {
        final value = evaluator(x);
        if (!value.isFinite) return true;
        if (previous.isFinite) {
          final phaseStep = (value - previous).abs();
          if (phaseStep > math.pi / 4) return true;
        }
        previous = value;
      }
    } catch (_) {
      return true;
    }
  }
  return false;
}

bool _hasSampledRoundingJump(
  String source,
  double lowerBound,
  double upperBound,
  Map<String, double> parameterValues,
) {
  final calls = RegExp(r'\b(floor|ceil|round)\s*\(');
  for (final match in calls.allMatches(source)) {
    final open = source.indexOf('(', match.start);
    var depth = 1;
    var close = -1;
    for (var i = open + 1; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')' && --depth == 0) {
        close = i;
        break;
      }
    }
    if (close < 0) return true;
    final argument = MathExpression.fromInput(
      source.substring(open + 1, close).trim(),
    );
    if (!argument.isValid || argument.type != MathExpressionType.explicit) {
      return true;
    }
    if (argument.parameters.any(
      (name) => name != 'x' && !parameterValues.containsKey(name),
    ))
      return true;
    final evaluator = argument.withParameters(parameterValues).evaluator;
    double? previousRounded;
    const samples = 1024;
    final step = (upperBound - lowerBound) / samples;
    try {
      for (var i = 0; i <= samples; i++) {
        final value = evaluator(lowerBound + step * i);
        if (!value.isFinite) return true;
        final rounded = switch (match.group(1)) {
          'floor' => value.floorToDouble(),
          'ceil' => value.ceilToDouble(),
          _ => value.roundToDouble(),
        };
        if (previousRounded != null && previousRounded != rounded) {
          return true;
        }
        previousRounded = rounded;
      }
    } catch (_) {
      return true;
    }
  }
  return false;
}

bool _hasPotentialDenominatorZero(
  String source,
  double lowerBound,
  double upperBound,
  Map<String, double> parameterValues,
) {
  for (
    var slash = source.indexOf('/');
    slash >= 0;
    slash = source.indexOf('/', slash + 1)
  ) {
    final start = slash + 1;
    var depth = 0;
    var end = start;
    for (; end < source.length; end++) {
      final character = source[end];
      if (character == '(') depth++;
      if (character == ')') depth--;
      if (depth == 0 &&
          end > start &&
          (character == '+' ||
              character == '-' ||
              character == '*' ||
              character == '/' ||
              character == '%')) {
        break;
      }
    }
    if (_expressionMayContainZero(
      source.substring(start, end).trim(),
      lowerBound,
      upperBound,
      parameterValues,
    ))
      return true;
  }
  return false;
}

bool _negativePowerMayContainZero(
  String source,
  double lowerBound,
  double upperBound,
  Map<String, double> parameterValues,
) {
  for (final match in RegExp(r'\^\s*\(?\s*-').allMatches(source)) {
    var end = match.start;
    while (end > 0 && source[end - 1].trim().isEmpty) {
      end--;
    }
    if (end == 0) return true;
    var start = end - 1;
    if (source[start] == ')') {
      var depth = 1;
      start--;
      for (; start >= 0; start--) {
        if (source[start] == ')') depth++;
        if (source[start] == '(' && --depth == 0) break;
      }
      if (start < 0) return true;
    } else {
      while (start > 0 &&
          RegExp(r'[a-zA-Z0-9_.]').hasMatch(source[start - 1])) {
        start--;
      }
    }
    if (_expressionMayContainZero(
      source.substring(start, end).trim(),
      lowerBound,
      upperBound,
      parameterValues,
    ))
      return true;
  }

  for (final match in RegExp(r'\bpow\s*\(').allMatches(source)) {
    final open = source.indexOf('(', match.start);
    var depth = 1;
    var comma = -1;
    var close = -1;
    for (var i = open + 1; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') {
        depth--;
        if (depth == 0) {
          close = i;
          break;
        }
      }
      if (source[i] == ',' && depth == 1) comma = i;
    }
    if (comma < 0 || close < 0) continue;
    if (!source.substring(comma + 1, close).trim().startsWith('-')) continue;
    if (_expressionMayContainZero(
      source.substring(open + 1, comma).trim(),
      lowerBound,
      upperBound,
      parameterValues,
    ))
      return true;
  }
  return false;
}

bool _expressionMayContainZero(
  String source,
  double lowerBound,
  double upperBound,
  Map<String, double> parameterValues,
) {
  if (source.isEmpty) return true;
  final expression = MathExpression.fromInput(source);
  if (!expression.isValid || expression.type != MathExpressionType.explicit) {
    return true;
  }
  if (expression.parameters.any(
    (name) => name != 'x' && !parameterValues.containsKey(name),
  ))
    return true;
  final evaluator = expression.withParameters(parameterValues).evaluator;
  const samples = 1024;
  final step = (upperBound - lowerBound) / samples;
  var previous = double.nan;
  var maximumMagnitude = 0.0;
  final values = <double>[];
  try {
    for (var i = 0; i <= samples; i++) {
      final value = evaluator(lowerBound + step * i);
      if (!value.isFinite || value == 0) return true;
      final magnitude = value.abs();
      if (magnitude > maximumMagnitude) maximumMagnitude = magnitude;
      if (previous.isFinite && (previous < 0) != (value < 0)) return true;
      previous = value;
      values.add(value);
    }
  } catch (_) {
    return true;
  }

  if (maximumMagnitude == 0) return true;
  for (var i = 1; i < samples; i++) {
    final before = values[i - 1].abs();
    final current = values[i].abs();
    final after = values[i + 1].abs();
    if (current >= before || current >= after) continue;
    final minimum = _minimumAbsoluteOnInterval(
      evaluator,
      lowerBound + step * (i - 1),
      lowerBound + step * (i + 1),
    );
    if (minimum <= maximumMagnitude * 1e-12) return true;
  }
  return false;
}

double _minimumAbsoluteOnInterval(
  double Function(double) evaluate,
  double lowerBound,
  double upperBound,
) {
  const ratio = 0.6180339887498949;
  var left = lowerBound;
  var right = upperBound;
  var first = right - (right - left) * ratio;
  var second = left + (right - left) * ratio;
  var firstValue = evaluate(first).abs();
  var secondValue = evaluate(second).abs();
  for (var i = 0; i < 48; i++) {
    if (firstValue <= secondValue) {
      right = second;
      second = first;
      secondValue = firstValue;
      first = right - (right - left) * ratio;
      firstValue = evaluate(first).abs();
    } else {
      left = first;
      first = second;
      firstValue = secondValue;
      second = left + (right - left) * ratio;
      secondValue = evaluate(second).abs();
    }
  }
  return firstValue < secondValue ? firstValue : secondValue;
}

_Refinement _integratePartition({
  required double Function(double) evaluate,
  required double lowerBound,
  required double upperBound,
  required int panels,
  required double tolerance,
  required int maxDepth,
}) {
  final width = upperBound - lowerBound;
  var value = 0.0;
  var error = 0.0;
  var converged = true;
  for (var i = 0; i < panels; i++) {
    final a = lowerBound + width * (i / panels);
    final b = lowerBound + width * ((i + 1) / panels);
    final m = a + (b - a) / 2;
    final fa = evaluate(a);
    final fm = evaluate(m);
    final fb = evaluate(b);
    final whole = _simpson(a, b, fa, fm, fb);
    final result = _refine(
      evaluate: evaluate,
      a: a,
      b: b,
      fa: fa,
      fm: fm,
      fb: fb,
      whole: whole,
      tolerance: tolerance / panels,
      depth: maxDepth,
    );
    value += result.value;
    error += result.error;
    converged = converged && result.converged;
  }
  return _Refinement(value, error, converged);
}

class _Refinement {
  final double value;
  final double error;
  final bool converged;

  const _Refinement(this.value, this.error, this.converged);
}

_Refinement _refine({
  required double Function(double) evaluate,
  required double a,
  required double b,
  required double fa,
  required double fm,
  required double fb,
  required double whole,
  required double tolerance,
  required int depth,
}) {
  final m = a + (b - a) / 2;
  final leftMidpoint = a + (m - a) / 2;
  final rightMidpoint = m + (b - m) / 2;
  final flm = evaluate(leftMidpoint);
  final frm = evaluate(rightMidpoint);
  final left = _simpson(a, m, fa, flm, fm);
  final right = _simpson(m, b, fm, frm, fb);
  final delta = left + right - whole;
  final error = delta.abs() / 15;
  final value = left + right + delta / 15;
  if (!value.isFinite || !error.isFinite) throw const _InvalidSample();
  if (error <= tolerance) return _Refinement(value, error, true);
  if (depth <= 1) return _Refinement(value, error, false);

  final leftResult = _refine(
    evaluate: evaluate,
    a: a,
    b: m,
    fa: fa,
    fm: flm,
    fb: fm,
    whole: left,
    tolerance: tolerance / 2,
    depth: depth - 1,
  );
  final rightResult = _refine(
    evaluate: evaluate,
    a: m,
    b: b,
    fa: fm,
    fm: frm,
    fb: fb,
    whole: right,
    tolerance: tolerance / 2,
    depth: depth - 1,
  );
  return _Refinement(
    leftResult.value + rightResult.value,
    leftResult.error + rightResult.error,
    leftResult.converged && rightResult.converged,
  );
}

double _simpson(double a, double b, double fa, double fm, double fb) =>
    (b - a) / 6 * (fa + 4 * fm + fb);

class _InvalidSample implements Exception {
  const _InvalidSample();
}
