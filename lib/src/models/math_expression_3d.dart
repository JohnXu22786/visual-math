import 'math_expression.dart';
import 'math_input_catalog.dart';
import 'math_expression_parser.dart';
import 'math_3d_object.dart';

/// The type of a 3D expression.
enum Expression3DType {
  /// Surface z = f(x, y) — explicit function of x and y.
  surface,

  /// Parametric curve (x(t), y(t), z(t)).
  parametricCurve,

  /// Parametric surface (x(u,v), y(u,v), z(u,v)).
  parametricSurface,
}

/// Represents a 3D math expression — a surface, parametric curve, or
/// parametric surface.
///
/// Uses the same native expression parser as the 2D [MathExpression] class.
class Expression3D {
  final String rawExpression;
  final String normalizedExpression;
  final Expression3DType type;
  final Set<String> parameters;

  // Surface: z = f(x, y)
  final double Function(double x, double y)? _surfaceEvaluator;

  // Parametric curve: (x(t), y(t), z(t))
  final double Function(double t)? _curveX;
  final double Function(double t)? _curveY;
  final double Function(double t)? _curveZ;
  final double tMin;
  final double tMax;

  // Parametric surface: (x(u,v), y(u,v), z(u,v))
  final double Function(double u, double v)? _surfX;
  final double Function(double u, double v)? _surfY;
  final double Function(double u, double v)? _surfZ;
  final double uMin;
  final double uMax;
  final double vMin;
  final double vMax;

  final String? _parseError;

  bool get isValid => rawExpression.isNotEmpty && _parseError == null;
  String? get parseError => _parseError;

  const Expression3D._({
    required this.rawExpression,
    required this.normalizedExpression,
    required this.type,
    required this.parameters,
    double Function(double, double)? surfaceEvaluator,
    double Function(double t)? curveX,
    double Function(double t)? curveY,
    double Function(double t)? curveZ,
    double Function(double u, double v)? surfX,
    double Function(double u, double v)? surfY,
    double Function(double u, double v)? surfZ,
    this.tMin = 0,
    this.tMax = 1,
    this.uMin = 0,
    this.uMax = 1,
    this.vMin = 0,
    this.vMax = 1,
    String? parseError,
  }) : _surfaceEvaluator = surfaceEvaluator,
       _curveX = curveX,
       _curveY = curveY,
       _curveZ = curveZ,
       _surfX = surfX,
       _surfY = surfY,
       _surfZ = surfZ,
       _parseError = parseError;

  // ==================================================================
  // Surface z = f(x, y)
  // ==================================================================

  /// Create a surface expression from z = f(x, y) input.
  factory Expression3D.surface(
    String input, {
    Map<String, double> parameterValues = const {},
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return Expression3D._(
        rawExpression: '',
        normalizedExpression: '',
        type: Expression3DType.surface,
        parameters: {},
        parseError: '表达式为空',
      );
    }

    // Strip z = or f(x,y) = prefix
    final body = _stripSurfacePrefix(trimmed);
    if (body.isEmpty) {
      return Expression3D._(
        rawExpression: trimmed,
        normalizedExpression: '',
        type: Expression3DType.surface,
        parameters: {},
        parseError: '表达式为空',
      );
    }

    // Normalize
    var normalized = '';

    // Create evaluator
    String? error;
    double Function(double, double)? evalFn;

    try {
      normalized = _normalizeExpression(body);
      evalFn = _createSurfaceEvaluator(normalized, parameterValues);
    } catch (e) {
      error = e.toString();
    }

    final params = _extractParameters(normalized);

    return Expression3D._(
      rawExpression: trimmed,
      normalizedExpression: normalized,
      type: Expression3DType.surface,
      parameters: params,
      surfaceEvaluator: evalFn,
      parseError: error,
    );
  }

  /// Evaluate the surface at (x, y).
  double evaluateSurface(double x, double y) {
    if (_surfaceEvaluator == null) throw _parseError ?? '无效的曲面表达式';
    return _surfaceEvaluator(x, y);
  }

  /// Sample the surface on a grid and return a [SurfaceMesh].
  SurfaceMesh sampleSurfaceGrid({
    double xMin = -5,
    double xMax = 5,
    double yMin = -5,
    double yMax = 5,
    int gridX = 40,
    int gridY = 40,
  }) {
    if (!isValid || _surfaceEvaluator == null) {
      return const SurfaceMesh(vertices: [], indices: []);
    }

    return SurfaceMesh.fromFunction(
      xMin: xMin,
      xMax: xMax,
      yMin: yMin,
      yMax: yMax,
      gridX: gridX,
      gridY: gridY,
      f: _surfaceEvaluator,
    );
  }

  // ==================================================================
  // Parametric curve
  // ==================================================================

  /// Create a parametric curve expression.
  ///
  /// Format: (x(t), y(t), z(t))
  factory Expression3D.parametricCurve(
    String input, {
    double tMin = 0,
    double tMax = 1,
    Map<String, double> parameterValues = const {},
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return Expression3D._(
        rawExpression: '',
        normalizedExpression: '',
        type: Expression3DType.parametricCurve,
        parameters: {},
        tMin: tMin,
        tMax: tMax,
        parseError: '表达式为空',
      );
    }

    // Parse (x(t), y(t), z(t)) format
    final components = _parseParametricComponents(trimmed);
    if (components == null) {
      return Expression3D._(
        rawExpression: trimmed,
        normalizedExpression: '',
        type: Expression3DType.parametricCurve,
        parameters: {},
        tMin: tMin,
        tMax: tMax,
        parseError: '参数曲线格式错误，应为 (x(t), y(t), z(t))',
      );
    }

    String? error;
    double Function(double)? curveX, curveY, curveZ;
    var params = <String>{};

    try {
      params = _extractParameters(
        components.map(_normalizeExpression).join(' '),
        independentVariables: const {'t'},
      );
      final varNames = ['t'];
      for (final key in parameterValues.keys) {
        if (!varNames.contains(key)) varNames.add(key);
      }

      curveX = _createParametricEvaluator(
        components[0],
        varNames,
        parameterValues,
      );
      curveY = _createParametricEvaluator(
        components[1],
        varNames,
        parameterValues,
      );
      curveZ = _createParametricEvaluator(
        components[2],
        varNames,
        parameterValues,
      );
    } catch (e) {
      error = e.toString();
    }

    return Expression3D._(
      rawExpression: trimmed,
      normalizedExpression: trimmed,
      type: Expression3DType.parametricCurve,
      parameters: params,
      curveX: curveX,
      curveY: curveY,
      curveZ: curveZ,
      tMin: tMin,
      tMax: tMax,
      parseError: error,
    );
  }

  /// Evaluate the curve at parameter t.
  Point3D evaluateCurve(double t) {
    if (_curveX == null || _curveY == null || _curveZ == null) {
      throw _parseError ?? '无效的参数曲线';
    }
    return Point3D(_curveX(t), _curveY(t), _curveZ(t));
  }

  /// Sample the curve at [numSamples] points, omitting non-finite results.
  ///
  /// Use [sampleCurveSegments] when separate branches must remain disconnected.
  List<Point3D> sampleCurve({int numSamples = 100}) =>
      sampleCurveSegments(numSamples: numSamples)
          .expand((segment) => segment)
          .toList();

  /// Sample the curve into finite, contiguous paths separated at invalid values.
  List<List<Point3D>> sampleCurveSegments({int numSamples = 100}) {
    if (!isValid || _curveX == null || numSamples < 2) return [];

    final segments = <List<Point3D>>[];
    var current = <Point3D>[];
    final step = (tMax - tMin) / (numSamples - 1);

    void endSegment() {
      if (current.isNotEmpty) segments.add(current);
      current = <Point3D>[];
    }

    for (int i = 0; i < numSamples; i++) {
      final t = tMin + i * step;
      try {
        final point = evaluateCurve(t);
        if (point.x.isFinite && point.y.isFinite && point.z.isFinite) {
          current.add(point);
        } else {
          endSegment();
        }
      } catch (_) {
        endSegment();
      }
    }
    endSegment();
    return segments;
  }

  // ==================================================================
  // Parametric surface
  // ==================================================================

  /// Create a parametric surface expression.
  ///
  /// Format: (x(u,v), y(u,v), z(u,v))
  factory Expression3D.parametricSurface(
    String input, {
    double uMin = 0,
    double uMax = 1,
    double vMin = 0,
    double vMax = 1,
    Map<String, double> parameterValues = const {},
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return Expression3D._(
        rawExpression: '',
        normalizedExpression: '',
        type: Expression3DType.parametricSurface,
        parameters: {},
        uMin: uMin,
        uMax: uMax,
        vMin: vMin,
        vMax: vMax,
        parseError: '表达式为空',
      );
    }

    // Parse (x(u,v), y(u,v), z(u,v)) format
    final components = _parseParametricComponents(trimmed);
    if (components == null) {
      return Expression3D._(
        rawExpression: trimmed,
        normalizedExpression: '',
        type: Expression3DType.parametricSurface,
        parameters: {},
        uMin: uMin,
        uMax: uMax,
        vMin: vMin,
        vMax: vMax,
        parseError: '参数曲面格式错误，应为 (x(u,v), y(u,v), z(u,v))',
      );
    }

    String? error;
    double Function(double, double)? surfX, surfY, surfZ;
    var params = <String>{};

    try {
      params = _extractParameters(
        components.map(_normalizeExpression).join(' '),
        independentVariables: const {'u', 'v'},
      );
      final varNames = ['u', 'v'];
      for (final key in parameterValues.keys) {
        if (!varNames.contains(key)) varNames.add(key);
      }

      surfX = _createSurfaceParametricEvaluator(
        components[0],
        varNames,
        parameterValues,
      );
      surfY = _createSurfaceParametricEvaluator(
        components[1],
        varNames,
        parameterValues,
      );
      surfZ = _createSurfaceParametricEvaluator(
        components[2],
        varNames,
        parameterValues,
      );
    } catch (e) {
      error = e.toString();
    }

    return Expression3D._(
      rawExpression: trimmed,
      normalizedExpression: trimmed,
      type: Expression3DType.parametricSurface,
      parameters: params,
      surfX: surfX,
      surfY: surfY,
      surfZ: surfZ,
      uMin: uMin,
      uMax: uMax,
      vMin: vMin,
      vMax: vMax,
      parseError: error,
    );
  }

  /// Evaluate the parametric surface at (u, v).
  Point3D evaluateParametricSurface(double u, double v) {
    if (_surfX == null || _surfY == null || _surfZ == null) {
      throw _parseError ?? '无效的参数曲面';
    }
    return Point3D(_surfX(u, v), _surfY(u, v), _surfZ(u, v));
  }

  // ==================================================================
  // Parameter support
  // ==================================================================

  /// Create an updated expression with new parameter values.
  Expression3D withParameters(Map<String, double> parameterValues) {
    if (!isValid) return this;

    switch (type) {
      case Expression3DType.surface:
        return Expression3D.surface(
          rawExpression,
          parameterValues: parameterValues,
        );
      case Expression3DType.parametricCurve:
        return Expression3D.parametricCurve(
          rawExpression,
          tMin: tMin,
          tMax: tMax,
          parameterValues: parameterValues,
        );
      case Expression3DType.parametricSurface:
        return Expression3D.parametricSurface(
          rawExpression,
          uMin: uMin,
          uMax: uMax,
          vMin: vMin,
          vMax: vMax,
          parameterValues: parameterValues,
        );
    }
  }

  // ==================================================================
  // Internal helpers
  // ==================================================================

  /// Strip z = or f(x,y) = prefix from a surface expression.
  static String _stripSurfacePrefix(String expr) {
    // f(x,y) = ...
    final fxyMatch = RegExp(r'^f\s*\(\s*x\s*,\s*y\s*\)\s*=\s*')
        .firstMatch(expr);
    if (fxyMatch != null) {
      return expr.substring(fxyMatch.end);
    }
    // z = ...
    final zMatch = RegExp(r'^z\s*=\s*').firstMatch(expr);
    if (zMatch != null) {
      return expr.substring(zMatch.end);
    }
    return expr;
  }

  /// Parse a parametric expression like (x(t), y(t), z(t)) or
  /// (x(u,v), y(u,v), z(u,v)) into three component strings.
  ///
  /// Returns null if the format is invalid.
  static List<String>? _parseParametricComponents(String expr) {
    var trimmed = expr.trim();
    if (trimmed.startsWith(r'\left(') && trimmed.endsWith(r'\right)')) {
      trimmed = trimmed.substring(5, trimmed.length - 7) + ')';
    }
    // Must be wrapped in parentheses
    if (!trimmed.startsWith('(') || !trimmed.endsWith(')')) return null;

    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) return null;

    // Split by commas, respecting parentheses
    final components = <String>[];
    var depth = 0;
    var start = 0;

    for (int i = 0; i < inner.length; i++) {
      if ('({['.contains(inner[i])) depth++;
      if (')}]'.contains(inner[i])) depth--;
      if (inner[i] == ',' && depth == 0 && (i == 0 || inner[i - 1] != r'\')) {
        components.add(inner.substring(start, i).trim());
        start = i + 1;
      }
    }
    components.add(inner.substring(start).trim());

    if (components.length != 3) return null;
    return components;
  }

  /// Normalize an expression for numeric parsing.
  static String _normalizeExpression(String expr) {
    // Reuse normalization logic similar to MathExpression
    var result = expr.trim();
    if (result.isEmpty) return '';

    // Replace LaTeX commands
    result = MathExpression.convertLatexForParser(result);
    result = result.replaceAll('{', '(').replaceAll('}', ')');
    result = result.replaceAll(RegExp(r'(?<=\w)\s+(?=\w)'), '*');
    result = result.replaceAll(RegExp(r'\s+'), '');
    if (result.isEmpty) return '';

    result = _addImplicitMultiplication(result);
    return result;
  }

  /// Create a two-variable evaluator for surface f(x, y).
  static double Function(double, double) _createSurfaceEvaluator(
    String normalized,
    Map<String, double> parameterValues,
  ) {
    final variableNames = _detectVariables(normalized, [
      'x',
      'y',
      ...parameterValues.keys,
    ]);
    final mergedParams = Map<String, double>.from(parameterValues);
    for (final name in variableNames) {
      if (name != 'x' && name != 'y' && !mergedParams.containsKey(name)) {
        mergedParams[name] = 1.0;
      }
    }

    final evaluate = MathExpressionParser.parse(
      normalized,
      variables: variableNames,
    );
    return (double x, double y) {
      final args = Map<String, num>.from(mergedParams);
      args['x'] = x;
      args['y'] = y;
      return evaluate(args);
    };
  }

  /// Create a single-variable evaluator for parametric curve components.
  static double Function(double) _createParametricEvaluator(
    String expr,
    List<String> variableNames,
    Map<String, double> parameterValues,
  ) {
    final normalized = _normalizeExpression(expr);

    // Detect symbolic parameters as well as the curve's sampling variable.
    final allVars = _detectVariables(normalized, variableNames);

    final mergedParams = Map<String, double>.from(parameterValues);
    for (final name in allVars) {
      if (name != 't' && !mergedParams.containsKey(name)) {
        mergedParams[name] = 1.0;
      }
    }

    final evaluate = MathExpressionParser.parse(normalized, variables: allVars);
    return (double t) {
      final args = Map<String, num>.from(mergedParams);
      args['t'] = t;
      return evaluate(args);
    };
  }

  /// Create a two-variable evaluator for parametric surface components.
  static double Function(double, double) _createSurfaceParametricEvaluator(
    String expr,
    List<String> variableNames,
    Map<String, double> parameterValues,
  ) {
    final normalized = _normalizeExpression(expr);

    // Auto-detect additional variables in the expression
    final allVars = _detectVariables(normalized, variableNames);
    final mergedParams = Map<String, double>.from(parameterValues);
    for (final name in allVars) {
      if (name != 'u' && name != 'v' && !mergedParams.containsKey(name)) {
        mergedParams[name] = 1.0;
      }
    }

    final evaluate = MathExpressionParser.parse(normalized, variables: allVars);
    return (double u, double v) {
      final args = Map<String, num>.from(mergedParams);
      args['u'] = u;
      args['v'] = v;
      return evaluate(args);
    };
  }

  /// Detect all variable names in an expression.
  static List<String> _detectVariables(String expr, List<String> knownVars) {
    const builtinConstants = {
      'e',
      'pi',
      'ln2',
      'ln10',
      'log2e',
      'log10e',
      'sqrt1_2',
      'sqrt2',
    };
    const knownFunctions = {
      'sin',
      'cos',
      'tan',
      'sqrt',
      'abs',
      'ln',
      'log',
      'exp',
      'asin',
      'acos',
      'atan',
      'sinh',
      'cosh',
      'tanh',
      'sec',
      'csc',
      'cot',
      'pow',
      'nrt',
      'fact',
      'floor',
      'ceil',
      'round',
      'coth',
      'sech',
      'csch',
    };

    final result = <String>[...knownVars];
    final matches = RegExp(r'\b([a-zA-Z]\w*)\b').allMatches(expr);
    for (final m in matches) {
      final name = m[1]!;
      if (!result.contains(name) &&
          !knownFunctions.contains(name.toLowerCase()) &&
          !builtinConstants.contains(name)) {
        result.add(name);
      }
    }
    return result;
  }

  /// Extract parameter names from expression body.
  static Set<String> _extractParameters(
    String expr, {
    Set<String> independentVariables = const {'x', 'y'},
  }) {
    if (expr.isEmpty) return {};
    const knownFunctions = {
      'sin',
      'cos',
      'tan',
      'sqrt',
      'abs',
      'ln',
      'log',
      'exp',
      'asin',
      'acos',
      'atan',
      'sinh',
      'cosh',
      'tanh',
      'sec',
      'csc',
      'cot',
      'pow',
      'nrt',
      'fact',
      'floor',
      'ceil',
      'round',
      'coth',
      'sech',
      'csch',
    };
    const builtinConstants = {
      'e',
      'pi',
      'ln2',
      'ln10',
      'log2e',
      'log10e',
      'sqrt1_2',
      'sqrt2',
    };

    final params = <String>{};
    final matches = RegExp(r'\b([a-zA-Z]\w*)\b').allMatches(expr);
    for (final m in matches) {
      final name = m[1]!;
      final normalizedName = name.toLowerCase();
      if (independentVariables.contains(normalizedName) ||
          builtinConstants.contains(normalizedName)) {
        continue;
      }
      if (knownFunctions.contains(normalizedName)) continue;
      params.add(name);
    }
    return params;
  }

  static String _addImplicitMultiplication(String expr) {
    var result = expr;
    result = result.replaceAllMapped(
      RegExp(r'(?<![a-zA-Z])([xyzuvt]{2,})(?![a-zA-Z])'),
      (match) => match[1]!.split('').join('*'),
    );
    final tokens = RegExp(
      r'(?<![a-zA-Z0-9_])(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|(?:\d+(?:\.\d*)?|\.\d+)|.',
    ).allMatches(result).map((match) => match[0]!).toList();
    final withProducts = StringBuffer();
    for (var i = 0; i < tokens.length; i++) {
      if (i > 0 &&
          double.tryParse(tokens[i - 1]) != null &&
          RegExp(r'^[a-zA-Z(]$').hasMatch(tokens[i])) {
        withProducts.write('*');
      }
      withProducts.write(tokens[i]);
    }
    result = withProducts.toString();
    result = result.replaceAllMapped(
      RegExp(r'(\))\s*([a-zA-Z(])'),
      (m) => '${m[1]!}*${m[2]!}',
    );
    result = result.replaceAllMapped(
      RegExp(r'(?<![a-zA-Z])([a-zA-Z])(?![a-zA-Z])\('),
      (match) => '${match[1]}*(',
    );
    result = result.replaceAllMapped(RegExp(r'\b([a-zA-Z]\w*)\('), (match) {
      final name = match[1]!;
      if (mathGreekNames.contains(name) ||
          mathConstantInputs.any((input) => input.name == name) ||
          name.contains('_')) {
        return '$name*(';
      }
      return match[0]!;
    });
    return result;
  }
}
