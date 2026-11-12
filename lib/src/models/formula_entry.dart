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
  /// Stable identity for this row in saved documents.
  final String id;

  /// Raw user input (e.g. "x^2", "sin(x)").
  final String rawExpression;

  /// Parsed expression (null if invalid or empty).
  final MathExpression? parsed;

  /// Rendering color.
  final Color color;

  /// Whether this color was auto-assigned (vs. user-set).
  final bool autoColor;

  /// Whether this formula row is currently included when plotting.
  final bool visible;

  /// Optional lower/upper x-domain expressions, stored exactly as entered.
  final String? domainStartExpression;
  final String? domainEndExpression;
  final bool includeDomainStart;
  final bool includeDomainEnd;

  /// Current parameter values (only relevant if [parsed] has parameters).
  final Map<String, double> parameterValues;

  const FormulaEntry({
    this.id = '',
    required this.rawExpression,
    this.parsed,
    this.color = Colors.blue,
    this.autoColor = true,
    this.visible = true,
    this.domainStartExpression,
    this.domainEndExpression,
    this.includeDomainStart = true,
    this.includeDomainEnd = true,
    this.parameterValues = const {},
  });

  /// Create a copy with optionally overridden fields.
  ///
  /// Replacing [rawExpression] without supplying a new [parsed] expression
  /// clears the old parse so the two values cannot silently get out of sync.
  /// Set [clearParsed] to clear the parse without changing the raw expression.
  FormulaEntry copyWith({
    String? id,
    String? rawExpression,
    MathExpression? parsed,
    bool clearParsed = false,
    Color? color,
    bool? autoColor,
    bool? visible,
    String? domainStartExpression,
    String? domainEndExpression,
    bool? includeDomainStart,
    bool? includeDomainEnd,
    Map<String, double>? parameterValues,
  }) {
    return FormulaEntry(
      id: id ?? this.id,
      rawExpression: rawExpression ?? this.rawExpression,
      parsed: clearParsed
          ? null
          : parsed ??
                (rawExpression != null && rawExpression != this.rawExpression
                    ? null
                    : this.parsed),
      color: color ?? this.color,
      autoColor: autoColor ?? this.autoColor,
      visible: visible ?? this.visible,
      domainStartExpression:
          domainStartExpression ?? this.domainStartExpression,
      domainEndExpression: domainEndExpression ?? this.domainEndExpression,
      includeDomainStart: includeDomainStart ?? this.includeDomainStart,
      includeDomainEnd: includeDomainEnd ?? this.includeDomainEnd,
      parameterValues: parameterValues ?? this.parameterValues,
    );
  }

  bool get isValid =>
      rawExpression.isNotEmpty && parsed != null && parsed!.isValid;
}

/// Assign the next auto-color from the palette, skipping [usedColors].
/// Cycles after [lastAutoColor] if all colors are used.
Color nextFormulaColor(Set<Color> usedColors, {Color? lastAutoColor}) {
  for (final c in formulaPalette) {
    if (!usedColors.contains(c)) return c;
  }
  final lastIndex = lastAutoColor == null
      ? -1
      : formulaPalette.indexOf(lastAutoColor);
  return formulaPalette[(lastIndex + 1) % formulaPalette.length];
}
