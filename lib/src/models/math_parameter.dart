import 'dart:math' as math;

/// A shared parameter value and the slider grid used to adjust it.
class MathParameter {
  final double value;
  final double min;
  final double max;
  final double step;
  final int _lastStep;
  final bool _hasShortFinalStep;

  factory MathParameter({
    double value = 1,
    double min = -5,
    double max = 5,
    double step = 0.1,
  }) {
    _requireFinite(value, 'value');
    _requireFinite(min, 'min');
    _requireFinite(max, 'max');
    _requireFinite(step, 'step');
    if (min >= max) {
      throw ArgumentError.value(max, 'max', 'Must be greater than min');
    }
    final width = max - min;
    if (!width.isFinite) {
      throw ArgumentError.value(max, 'max', 'Range must be finite');
    }
    if (step <= 0 || step > width) {
      throw ArgumentError.value(step, 'step', 'Must be positive and <= range');
    }
    final intervals = width / step;
    // Grid indices must be representable, and a step must move both bounds.
    if (!intervals.isFinite ||
        intervals > 4503599627370496 ||
        min + step == min ||
        max - step == max) {
      throw ArgumentError.value(step, 'step', 'Too small for these bounds');
    }
    final nearest = intervals.roundToDouble();
    final tolerance = math.min(1e-9, intervals * 1e-14);
    final lastStep = (intervals - nearest).abs() <= tolerance
        ? nearest.toInt()
        : intervals.floor();
    return MathParameter._(
      value.clamp(min, max).toDouble(),
      min,
      max,
      step,
      lastStep,
      (intervals - nearest).abs() > tolerance,
    );
  }

  const MathParameter._(
    this.value,
    this.min,
    this.max,
    this.step,
    this._lastStep,
    this._hasShortFinalStep,
  );

  /// Typed values are clamped to the bounds without being quantized.
  MathParameter withValue(double value) {
    _requireFinite(value, 'value');
    return MathParameter._(
      value.clamp(min, max).toDouble(),
      min,
      max,
      step,
      _lastStep,
      _hasShortFinalStep,
    );
  }

  /// Snap a slider gesture to steps from [min], never redistributing the grid.
  double snap(double raw) {
    _requireFinite(raw, 'raw');
    return _gridValue(_nearestIndex(raw));
  }

  int get _lastIndex => _lastStep + (_hasShortFinalStep ? 1 : 0);

  int _nearestIndex(double raw) {
    final bounded = raw.clamp(min, max).toDouble();
    final gridIndex =
        ((bounded - min) / step).round().clamp(0, _lastStep).toInt();
    if (_hasShortFinalStep &&
        (max - bounded).abs() <= (_gridValue(gridIndex) - bounded).abs()) {
      return _lastIndex;
    }
    return gridIndex;
  }

  double _gridValue(int index) {
    if (index == _lastIndex && _hasShortFinalStep) return max;
    if (index == _lastStep && !_hasShortFinalStep) return max;
    return (min + index * step).clamp(min, max).toDouble();
  }

  /// Return the next grid value in a direction, preserving exact boundary values.
  double adjacentValue(bool increase) {
    var index = _nearestIndex(value);
    final direction = increase ? 1 : -1;
    final snapped = _gridValue(index);
    final scale = math.max(
      math.max(math.max(snapped.abs(), value.abs()), min.abs()),
      (index * step).abs(),
    );
    final alignmentTolerance =
        math.min(step * 1e-12, scale * 2.220446049250313e-16);
    final aligned = (snapped - value).abs() <= alignmentTolerance;
    final alreadyAhead = increase ? snapped > value : snapped < value;
    if (aligned || !alreadyAhead) {
      index += direction;
    }
    // Several indices can round to the same value at large bounds.
    while (index >= 0 && index <= _lastIndex) {
      final adjacent = _gridValue(index);
      if (increase ? adjacent > value : adjacent < value) return adjacent;
      index += direction;
    }
    return value;
  }

  /// Format computed ticks within their bounded cancellation error.
  /// Exact entries between ticks retain the strict numeric presentation.
  String formatValue([double? number]) {
    final displayed = number ?? value;
    if (number == null && displayed != snap(displayed)) {
      return displayed.toString();
    }
    if (displayed.abs() >= 1e14 || displayed != snap(displayed)) {
      return formatMathParameterNumber(displayed);
    }
    final scale = math.max(math.max(min.abs(), max.abs()), displayed.abs());
    final tolerance = math.min(scale * 2.220446049250313e-16, step * 1e-6);
    for (var precision = 1; precision <= 15; precision++) {
      final encoded = displayed.toStringAsPrecision(precision);
      if ((double.parse(encoded) - displayed).abs() <= tolerance) {
        return _trimMathParameterNumber(encoded);
      }
    }
    return _trimMathParameterNumber(displayed.toString());
  }

  MathParameter reconfigure({
    required double min,
    required double max,
    required double step,
    double? value,
  }) =>
      MathParameter(value: value ?? this.value, min: min, max: max, step: step);

  static void _requireFinite(double number, String name) {
    if (!number.isFinite) {
      throw ArgumentError.value(number, name, 'Must be finite');
    }
  }
}

/// Keep labels readable when arithmetic leaves insignificant decimal digits.
String formatMathParameterNumber(double value) {
  if (value == 0) return '0';
  final cleaned = value.toStringAsPrecision(15);
  final cleanupError = (double.parse(cleaned) - value).abs();
  final representationUnit = value.abs() * 2.220446049250313e-16;
  // Preserve exact large values and meaningful fractional or typed digits.
  final encoded = value.abs() < 1e14 && cleanupError <= representationUnit
      ? cleaned
      : value.toString();
  return _trimMathParameterNumber(encoded);
}

String _trimMathParameterNumber(String encoded) {
  final parts = encoded.split('e');
  var mantissa = parts.first;
  if (mantissa.contains('.')) {
    mantissa = mantissa.replaceFirst(RegExp(r'0+$'), '');
    mantissa = mantissa.replaceFirst(RegExp(r'\.$'), '');
  }
  return parts.length == 1 ? mantissa : '${mantissa}e${parts.last}';
}
