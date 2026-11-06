import 'package:flutter/material.dart';

import 'math_expression.dart';

/// A palette of distinct colors for auto-assigning to formulas.
const List<Color> formulaPalette = [
  Color(0xFF2196F3), // Blue
  Color(0xFFF44336), // Red
  Color(0xFF4CAF50), // Green
  Color(0xFFFF9800), // Orange
  Color(0xFF9C27B0), // Purple
  Color(0xFF009688), // Teal
  Color(0xFFE91E63), // Pink
  Color(0xFF3F51B5), // Indigo
  Color(0xFF00BCD4), // Cyan
  Color(0xFFFF5722), // Deep Orange
];

/// A single formula entry with its parsed expression, color, and parameters.
class FormulaEntry {
  /// Raw user input (e.g. "x^2", "sin(x)").
  final String rawExpression;

  /// Parsed expression (null if invalid or empty).
  final MathExpression? parsed;

  /// Rendering color.
  final Color color;

  /// Whether this color was auto-assigned (vs. user-set).
  final bool autoColor;

  /// Current parameter values (only relevant if [parsed] has parameters).
  final Map<String, double> parameterValues;

  /// Optional numeric x interval resolved from the formula's endpoint inputs.
  final double? domainMin;
  final double? domainMax;
  final bool includeDomainMin;
  final bool includeDomainMax;
  final String domainMinExpression;
  final String domainMaxExpression;
  final String? identity;

  const FormulaEntry({
    required this.rawExpression,
    this.parsed,
    this.color = Colors.blue,
    this.autoColor = true,
    this.parameterValues = const {},
    this.domainMin,
    this.domainMax,
    this.includeDomainMin = true,
    this.includeDomainMax = true,
    this.domainMinExpression = '',
    this.domainMaxExpression = '',
    this.identity,
  });

  /// Create a copy with optionally overridden fields.
  ///
  /// Replacing [rawExpression] without supplying a new [parsed] expression
  /// clears the old parse so the two values cannot silently get out of sync.
  /// Set [clearParsed] to clear the parse without changing the raw expression.
  FormulaEntry copyWith({
    String? rawExpression,
    MathExpression? parsed,
    bool clearParsed = false,
    Color? color,
    bool? autoColor,
    Map<String, double>? parameterValues,
    double? domainMin,
    double? domainMax,
    bool clearDomainMin = false,
    bool clearDomainMax = false,
    bool? includeDomainMin,
    bool? includeDomainMax,
    String? domainMinExpression,
    String? domainMaxExpression,
    String? identity,
  }) {
    return FormulaEntry(
      rawExpression: rawExpression ?? this.rawExpression,
      parsed: clearParsed
          ? null
          : parsed ??
              (rawExpression != null && rawExpression != this.rawExpression
                  ? null
                  : this.parsed),
      color: color ?? this.color,
      autoColor: autoColor ?? this.autoColor,
      parameterValues: parameterValues ?? this.parameterValues,
      domainMin: clearDomainMin ? null : domainMin ?? this.domainMin,
      domainMax: clearDomainMax ? null : domainMax ?? this.domainMax,
      includeDomainMin: includeDomainMin ?? this.includeDomainMin,
      includeDomainMax: includeDomainMax ?? this.includeDomainMax,
      domainMinExpression: domainMinExpression ?? this.domainMinExpression,
      domainMaxExpression: domainMaxExpression ?? this.domainMaxExpression,
      identity: identity ?? this.identity,
    );
  }

  bool get isValid =>
      rawExpression.isNotEmpty && parsed != null && parsed!.isValid;
}

/// Assign the next auto-color from the palette, skipping [usedColors].
/// Cycles through the palette if all colors are used.
Color nextFormulaColor(Set<Color> usedColors) {
  for (final c in formulaPalette) {
    if (!usedColors.contains(c)) return c;
  }
  // All colors used — cycle from start
  return formulaPalette[usedColors.length % formulaPalette.length];
}
