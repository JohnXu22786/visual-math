import 'dart:math' as math;

/// Compiles the numeric expression syntax used by the graph evaluators.
///
/// Expressions are parsed once and returned as a function of the supplied
/// variable values, so sampling a graph does not repeatedly parse its formula.
class MathExpressionParser {
  MathExpressionParser._(this._tokens, this._variables);

  final List<_Token> _tokens;
  final Set<String> _variables;
  var _position = 0;

  /// Parse [source] and return a compiled evaluator over [variables].
  static double Function(Map<String, num>) parse(
    String source, {
    required Iterable<String> variables,
  }) {
    final parser = MathExpressionParser._(_tokenize(source), variables.toSet());
    final expression = parser._parseExpression();
    if (!parser._isAtEnd) {
      throw FormatException(
        'Unexpected token ${parser._current.text}',
        source,
        parser._current.offset,
      );
    }
    return (values) => expression(values).toDouble();
  }

  /// Return a continuous factor whose sign change proves a touching zero.
  ///
  /// This deliberately recognizes a bounded set of structures: neutral zero
  /// additions, products of continuous expressions, positive integer powers,
  /// and absolute values. It does not infer zeros from a small residual alone.
  static List<String> touchingRootFactors(
    String source, {
    required Iterable<String> variables,
  }) {
    try {
      final parser = _RootEvidenceParser(_tokenize(source), variables.toSet());
      final node = parser.parse();
      return node.rootFactors.map((factor) => factor.code).toList();
    } on FormatException {
      return const [];
    }
  }

  /// Whether [source] is structurally zero after substituting fixed variables.
  static bool isIdenticallyZeroAfterSubstitution(
    String source, {
    required Iterable<String> variables,
    required Map<String, double> substitutions,
    required Map<String, (double, double)> intervals,
  }) {
    try {
      final node = _RootEvidenceParser(
        _tokenize(source),
        variables.toSet(),
        substitutions: substitutions,
        intervals: intervals,
      ).parse();
      return node.zero;
    } on FormatException {
      return false;
    }
  }

  /// Compile the same expression grammar to a JavaScript expression.
  static String toJavaScript(
    String source, {
    required Iterable<String> variables,
  }) {
    final names = variables.toSet();
    // Validate identifiers and function arities using the numeric parser.
    parse(source, variables: names);
    final parser = MathExpressionParser._(_tokenize(source), names);
    return parser._jsSum().code;
  }

  _JsExpression _jsSum() {
    var left = _jsProduct();
    while (_current.text == '+' || _current.text == '-') {
      final op = _current.text;
      _position++;
      final right = _jsProduct();
      left = _JsExpression(
        '${left.wrap(1)}$op${right.wrap(op == '-' && right.code.startsWith('-') ? 4 : 2)}',
        1,
      );
    }
    return left;
  }

  _JsExpression _jsProduct() {
    var left = _jsUnary();
    while (_current.text == '*' ||
        _current.text == '/' ||
        _current.text == '%') {
      final op = _current.text;
      _position++;
      final right = _jsUnary();
      if (op == '%') {
        // Dart's modulo is nonnegative even when the dividend is negative.
        left = _JsExpression(
          '((a,b)=>{const r=a%b;return r<0?r+Math.abs(b):r;})(${left.code},${right.code})',
          4,
        );
      } else {
        left = _JsExpression('${left.wrap(2)}$op${right.wrap(3)}', 2);
      }
    }
    return left;
  }

  _JsExpression _jsUnary() {
    if (_match('+')) return _jsUnary();
    if (_match('-')) return _JsExpression('-${_jsUnary().wrap(4)}', 3);
    return _jsPower();
  }

  _JsExpression _jsPower() {
    final base = _jsPrimary();
    if (!_match('^')) return base;
    final exponent = _jsUnary();
    return _JsExpression('Math.pow(${base.code},${exponent.code})', 4);
  }

  _JsExpression _jsPrimary() {
    final token = _current;
    if (token.kind == _TokenKind.number) {
      _position++;
      final number = token.text;
      return _JsExpression(
        RegExp(r'^0[0-9]').hasMatch(number) ? 'Number("$number")' : number,
        4,
      );
    }
    if (_match('(')) {
      final expression = _jsSum();
      _consume(')');
      return expression;
    }
    _position++;
    final name = token.text;
    if (!_match('(')) {
      if (_variables.contains(name)) {
        return _JsExpression(name == 'x' ? name : '__vmParams["$name"]', 4);
      }
      const constants = {
        'e': 'E',
        'E': 'E',
        'pi': 'PI',
        'PI': 'PI',
        'ln2': 'LN2',
        'LN2': 'LN2',
        'ln10': 'LN10',
        'LN10': 'LN10',
        'log2e': 'LOG2E',
        'LOG2E': 'LOG2E',
        'log10e': 'LOG10E',
        'LOG10E': 'LOG10E',
        'sqrt1_2': 'SQRT1_2',
        'SQRT1_2': 'SQRT1_2',
        'sqrt2': 'SQRT2',
        'SQRT2': 'SQRT2',
      };
      return _JsExpression('Math.${constants[name]}', 4);
    }
    final args = <String>[];
    if (!_match(')')) {
      do {
        args.add(_jsSum().code);
      } while (_match(','));
      _consume(')');
    }
    final a = args.first;
    final code = switch (name) {
      'ln' => 'Math.log($a)',
      'log' when args.length == 2 => '(Math.log(${args[1]})/Math.log($a))',
      'cot' => '(1/Math.tan($a))',
      'csc' => '(1/Math.sin($a))',
      'sec' => '(1/Math.cos($a))',
      'sinh' => 'Math.sinh($a)',
      'cosh' => '((v)=>(Math.exp(v)+Math.exp(-v))/2)($a)',
      'tanh' => 'Math.tanh($a)',
      'coth' => '(1/Math.tanh($a))',
      'csch' => '(1/Math.sinh($a))',
      'sech' => '((v)=>2/(Math.exp(v)+Math.exp(-v)))($a)',
      'round' => '((v)=>Math.sign(v)*Math.round(Math.abs(v)))($a)',
      'fact' =>
        '((v)=>{if(!Number.isFinite(v)||v<0||Math.trunc(v)!=v)return NaN;let r=1;for(let i=2;i<=v;i++){r*=i;if(!Number.isFinite(r))return r;}return r;})($a)',
      'nrt' =>
        '((r,v)=>v<0&&Number.isFinite(r)&&Math.abs(r%2)==1?-Math.pow(-v,1/r):Math.pow(v,1/r))($a,${args[1]})',
      _ => 'Math.$name(${args.join(',')})',
    };
    return _JsExpression(code, 4);
  }

  bool get _isAtEnd => _current.kind == _TokenKind.end;
  _Token get _current => _tokens[_position];

  bool _match(String text) {
    if (_current.text != text) return false;
    _position++;
    return true;
  }

  _Token _consume(String text) {
    if (_match(text)) return _tokens[_position - 1];
    throw FormatException(
      'Expected $text, found ${_current.text}',
      null,
      _current.offset,
    );
  }

  _NumericExpression _parseExpression() => _parseSum();

  _NumericExpression _parseSum() {
    var expression = _parseProduct();
    while (_current.text == '+' || _current.text == '-') {
      final operation = _current.text;
      _position++;
      final left = expression;
      final right = _parseProduct();
      expression = operation == '+'
          ? (values) => left(values) + right(values)
          : (values) => left(values) - right(values);
    }
    return expression;
  }

  _NumericExpression _parseProduct() {
    var expression = _parseUnary();
    while (_current.text == '*' ||
        _current.text == '/' ||
        _current.text == '%') {
      final operation = _current.text;
      _position++;
      final left = expression;
      final right = _parseUnary();
      expression = switch (operation) {
        '*' => (values) => left(values) * right(values),
        '/' => (values) => left(values) / right(values),
        _ => (values) => left(values) % right(values),
      };
    }
    return expression;
  }

  _NumericExpression _parseUnary() {
    if (_match('+')) return _parseUnary();
    if (_match('-')) {
      final operand = _parseUnary();
      return (values) => -operand(values);
    }
    return _parsePower();
  }

  _NumericExpression _parsePower() {
    final base = _parsePrimary();
    if (!_match('^')) return base;
    final exponent = _parseUnary();
    return (values) => math.pow(base(values), exponent(values));
  }

  _NumericExpression _parsePrimary() {
    final token = _current;
    if (token.kind == _TokenKind.number) {
      _position++;
      final number = double.parse(token.text);
      return (_) => number;
    }
    if (_match('(')) {
      final expression = _parseExpression();
      _consume(')');
      return expression;
    }
    if (token.kind == _TokenKind.identifier) {
      _position++;
      final name = token.text;
      if (_match('(')) return _parseFunction(name, token);
      return _parseIdentifier(name, token);
    }
    throw FormatException(
      'Expected a number or identifier',
      null,
      token.offset,
    );
  }

  _NumericExpression _parseFunction(String name, _Token token) {
    final arguments = <_NumericExpression>[];
    if (!_match(')')) {
      do {
        arguments.add(_parseExpression());
      } while (_match(','));
      _consume(')');
    }

    final unary = _unaryFunctions[name];
    if (unary != null && arguments.length == 1) {
      final argument = arguments.single;
      return (values) => unary(argument(values).toDouble());
    }
    final binary = _binaryFunctions[name];
    if (binary != null && arguments.length == 2) {
      final first = arguments[0];
      final second = arguments[1];
      return (values) =>
          binary(first(values).toDouble(), second(values).toDouble());
    }
    final supportedArities = <int>{if (unary != null) 1, if (binary != null) 2};
    if (supportedArities.isEmpty) {
      throw FormatException('Unknown function $name', null, token.offset);
    }
    throw FormatException(
      '$name expects ${supportedArities.join(' or ')} argument(s)',
      null,
      token.offset,
    );
  }

  _NumericExpression _parseIdentifier(String name, _Token token) {
    if (_variables.contains(name)) {
      return (values) {
        final value = values[name];
        if (value == null) {
          throw ArgumentError.value(name, 'variables', 'No value was supplied');
        }
        return value;
      };
    }
    final constant = _constants[name];
    if (constant != null) return (_) => constant;
    throw FormatException('Unknown identifier $name', null, token.offset);
  }

  static List<_Token> _tokenize(String source) {
    final tokens = <_Token>[];
    var position = 0;
    while (position < source.length) {
      final character = source[position];
      if (character.trim().isEmpty) {
        position++;
        continue;
      }
      if (_isDigit(character) ||
          (character == '.' &&
              position + 1 < source.length &&
              _isDigit(source[position + 1]))) {
        final start = position++;
        while (position < source.length && _isDigit(source[position])) {
          position++;
        }
        if (position < source.length && source[position] == '.') {
          position++;
          while (position < source.length && _isDigit(source[position])) {
            position++;
          }
        }
        if (position < source.length &&
            (source[position] == 'e' || source[position] == 'E')) {
          final exponentStart = position++;
          if (position < source.length &&
              (source[position] == '+' || source[position] == '-')) {
            position++;
          }
          final digitsStart = position;
          while (position < source.length && _isDigit(source[position])) {
            position++;
          }
          if (digitsStart == position) position = exponentStart;
        }
        tokens.add(
          _Token(_TokenKind.number, source.substring(start, position), start),
        );
        continue;
      }
      if (_isIdentifierStart(character)) {
        final start = position++;
        while (position < source.length &&
            _isIdentifierPart(source[position])) {
          position++;
        }
        tokens.add(
          _Token(
            _TokenKind.identifier,
            source.substring(start, position),
            start,
          ),
        );
        continue;
      }
      if ('+-*/%^(),'.contains(character)) {
        tokens.add(_Token(_TokenKind.symbol, character, position));
        position++;
        continue;
      }
      throw FormatException(
        'Unexpected character $character',
        source,
        position,
      );
    }
    tokens.add(_Token(_TokenKind.end, '', source.length));
    return tokens;
  }

  static bool _isDigit(String character) =>
      character.codeUnitAt(0) >= 48 && character.codeUnitAt(0) <= 57;

  static bool _isIdentifierStart(String character) =>
      (character.toLowerCase() != character.toUpperCase()) || character == '_';

  static bool _isIdentifierPart(String character) =>
      _isIdentifierStart(character) || _isDigit(character);

  static final Map<String, double> _constants = {
    'e': math.e,
    'E': math.e,
    'pi': math.pi,
    'PI': math.pi,
    'ln2': math.ln2,
    'LN2': math.ln2,
    'ln10': math.ln10,
    'LN10': math.ln10,
    'log2e': math.log2e,
    'LOG2E': math.log2e,
    'log10e': math.log10e,
    'LOG10E': math.log10e,
    'sqrt1_2': math.sqrt1_2,
    'SQRT1_2': math.sqrt1_2,
    'sqrt2': math.sqrt2,
    'SQRT2': math.sqrt2,
  };

  static final Map<String, double Function(double)> _unaryFunctions = {
    'abs': (value) => value.abs(),
    'acos': math.acos,
    'asin': math.asin,
    'atan': math.atan,
    'ceil': (value) => value.ceilToDouble(),
    'cos': math.cos,
    'cosh': (value) => (math.exp(value) + math.exp(-value)) / 2,
    'cot': (value) => 1 / math.tan(value),
    'coth': (value) => 1 / _tanh(value),
    'csc': (value) => 1 / math.sin(value),
    'csch': (value) => 1 / _sinh(value),
    'exp': math.exp,
    'fact': _factorial,
    'floor': (value) => value.floorToDouble(),
    'ln': math.log,
    'log': math.log,
    'round': (value) => value.roundToDouble(),
    'sec': (value) => 1 / math.cos(value),
    'sech': (value) => 2 / (math.exp(value) + math.exp(-value)),
    'sin': math.sin,
    'sinh': _sinh,
    'sqrt': math.sqrt,
    'tan': math.tan,
    'tanh': _tanh,
  };

  static final Map<String, double Function(double, double)> _binaryFunctions = {
    'log': (base, value) => math.log(value) / math.log(base),
    'nrt': (root, value) => value < 0 && root.isFinite && root % 2 == 1
        ? -math.pow(-value, 1 / root).toDouble()
        : math.pow(value, 1 / root).toDouble(),
    'pow': (base, exponent) => math.pow(base, exponent).toDouble(),
  };

  static double _sinh(double value) {
    if (value == 0) return value;
    // A Taylor approximation avoids subtracting nearly equal exponentials.
    if (value.abs() < 1e-2) {
      final square = value * value;
      return value * (1 + square / 6 + square * square / 120);
    }
    return (math.exp(value) - math.exp(-value)) / 2;
  }

  static double _tanh(double value) {
    if (value == 0) return value;
    // Avoid cancellation of the exponentials near zero.
    if (value.abs() < 1e-4) return value - value * value * value / 3;
    // Beyond this point tanh rounds to the sign of its argument.
    if (value.abs() > 20) return value.sign;
    final positive = math.exp(value);
    final negative = math.exp(-value);
    return (positive - negative) / (positive + negative);
  }

  static double _factorial(double value) {
    if (!value.isFinite || value < 0 || value.truncateToDouble() != value) {
      throw ArgumentError.value(
        value,
        'value',
        'Factorial expects a non negative integer.',
      );
    }
    var result = 1.0;
    for (var factor = 2; factor <= value; factor++) {
      result *= factor;
      if (!result.isFinite) return result;
    }
    return result;
  }
}

typedef _NumericExpression = num Function(Map<String, num> values);

enum _TokenKind { number, identifier, symbol, end }

class _Token {
  const _Token(this.kind, this.text, this.offset);

  final _TokenKind kind;
  final String text;
  final int offset;
}

class _JsExpression {
  const _JsExpression(this.code, this.precedence);
  final String code;
  final int precedence;
  String wrap(int required) => precedence < required ? '($code)' : code;
}

// A conservative structural analysis, separate from numerical evaluation.
// Unknown operations are parsed but never treated as continuous evidence.
class _RootEvidenceNode {
  _RootEvidenceNode(
    this.kind,
    this.code, {
    this.left,
    this.right,
    this.continuous = false,
    this.zero = false,
    this.nonzero = false,
    this.integer,
    this.lowerBound,
    this.upperBound,
  });
  final String kind;
  final String code;
  final _RootEvidenceNode? left, right;
  final bool continuous, zero, nonzero;
  final int? integer;
  final double? lowerBound, upperBound;

  List<_RootEvidenceNode> get rootFactors {
    switch (kind) {
      case '+':
        if (right!.zero) return left!.rootFactors;
        if (left!.zero) return right!.rootFactors;
      case '-':
        if (right == null || right!.zero) return left!.rootFactors;
      case 'abs':
        if (left!.continuous) return [left!];
      case '^':
        final exponent = right!.integer;
        if (left!.continuous &&
            exponent != null &&
            exponent > 0 &&
            exponent.isEven)
          return [left!];
      case '*':
        if (left!.continuous && right!.continuous) {
          if (left!.code == right!.code) return [left!];
          return [...left!.rootFactors, ...right!.rootFactors];
        }
    }
    return const [];
  }
}

class _RootEvidenceParser {
  _RootEvidenceParser(
    this.tokens,
    this.variables, {
    this.substitutions = const {},
    this.intervals = const {},
  });
  final List<_Token> tokens;
  final Set<String> variables;
  final Map<String, double> substitutions;
  final Map<String, (double, double)> intervals;
  int position = 0;
  _Token get current => tokens[position];
  bool take(String text) {
    if (current.text != text) return false;
    position++;
    return true;
  }

  void require(String text) {
    if (!take(text)) throw const FormatException('Unexpected token');
  }

  _RootEvidenceNode parse() {
    final node = sum();
    if (current.kind != _TokenKind.end)
      throw const FormatException('Unexpected token');
    return node;
  }

  _RootEvidenceNode sum() {
    var node = product();
    while (current.text == '+' || current.text == '-') {
      final op = current.text;
      position++;
      final rhs = product();
      if (op == '+' && node.zero) {
        node = rhs;
        continue;
      }
      if ((op == '+' || op == '-') && rhs.zero) continue;
      if (op == '-' &&
          node.code == rhs.code &&
          node.continuous &&
          rhs.continuous) {
        node = _RootEvidenceNode(
          'number',
          '0',
          continuous: true,
          zero: true,
          lowerBound: 0,
          upperBound: 0,
        );
        continue;
      }
      final interval = _intervalFor(op, node, rhs);
      node = _RootEvidenceNode(
        op,
        '(${node.code}$op${rhs.code})',
        left: node,
        right: rhs,
        continuous: node.continuous && rhs.continuous,
        zero:
            node.zero && rhs.zero ||
            op == '-' &&
                node.code == rhs.code &&
                node.continuous &&
                rhs.continuous,
        nonzero:
            interval != null && (interval.$1 > 0 || interval.$2 < 0) ||
            node.zero && rhs.nonzero ||
            rhs.zero && node.nonzero,
        lowerBound: interval?.$1,
        upperBound: interval?.$2,
      );
    }
    return node;
  }

  _RootEvidenceNode product() {
    var node = unary();
    while (current.text == '*' || current.text == '/' || current.text == '%') {
      final op = current.text;
      position++;
      final rhs = unary();
      final interval = _intervalFor(op, node, rhs);
      node = _RootEvidenceNode(
        op,
        '(${node.code}$op${rhs.code})',
        left: node,
        right: rhs,
        continuous:
            op == '*' && node.continuous && rhs.continuous ||
            op == '/' && node.continuous && rhs.continuous && rhs.nonzero,
        zero:
            op == '*' &&
                (node.zero && rhs.continuous || rhs.zero && node.continuous) ||
            op == '/' && node.zero && rhs.nonzero,
        nonzero: interval != null && (interval.$1 > 0 || interval.$2 < 0),
        lowerBound: interval?.$1,
        upperBound: interval?.$2,
      );
    }
    return node;
  }

  _RootEvidenceNode unary() {
    if (take('+')) return unary();
    if (take('-')) {
      final node = unary();
      return _RootEvidenceNode(
        '-',
        '(-${node.code})',
        left: node,
        continuous: node.continuous,
        zero: node.zero,
        nonzero: node.nonzero,
        lowerBound: node.upperBound == null ? null : -node.upperBound!,
        upperBound: node.lowerBound == null ? null : -node.lowerBound!,
      );
    }
    return power();
  }

  _RootEvidenceNode power() {
    final node = primary();
    if (!take('^')) return node;
    final exponent = unary();
    final n = exponent.integer;
    final interval = _intervalFor('^', node, exponent);
    return _RootEvidenceNode(
      '^',
      '(${node.code}^${exponent.code})',
      left: node,
      right: exponent,
      continuous: node.continuous && n != null && n >= 0,
      zero: node.zero && n != null && n > 0,
      nonzero:
          node.continuous &&
          interval != null &&
          (interval.$1 > 0 || interval.$2 < 0),
      lowerBound: interval?.$1,
      upperBound: interval?.$2,
    );
  }

  _RootEvidenceNode primary() {
    final token = current;
    if (token.kind == _TokenKind.number) {
      position++;
      final value = double.tryParse(token.text);
      final zero = RegExp(r'^(?:0+(?:\.0*)?|\.0+)(?:[eE][+-]?\d+)?$')
          .hasMatch(token.text);
      final integer = RegExp(r'^\d+$').hasMatch(token.text)
          ? int.tryParse(token.text)
          : null;
      return _RootEvidenceNode(
        'number',
        token.text,
        continuous: value != null && value.isFinite,
        zero: zero,
        nonzero: value != null && value != 0,
        integer: integer,
        lowerBound: value,
        upperBound: value,
      );
    }
    if (take('(')) {
      final node = sum();
      require(')');
      return node;
    }
    if (token.kind == _TokenKind.identifier) {
      position++;
      if (take('(')) {
        final args = <_RootEvidenceNode>[];
        if (!take(')')) {
          do {
            args.add(sum());
          } while (take(','));
          require(')');
        }
        final hasSingleArgument = args.length == 1;
        final argument = hasSingleArgument ? args.single : null;
        final supported = const {
          'sin',
          'cos',
          'tan',
          'abs',
          'sqrt',
          'exp',
          'ln',
          'log',
          'sinh',
          'cosh',
          'tanh',
          'atan',
          'asin',
          'acos',
          'sec',
          'csc',
          'cot',
          'sech',
          'csch',
          'coth',
        }.contains(token.text);
        final absBounds =
            token.text == 'abs' &&
                argument?.lowerBound != null &&
                argument?.upperBound != null
            ? _absoluteInterval(argument!.lowerBound!, argument.upperBound!)
            : null;
        final expBounds =
            token.text == 'exp' &&
                argument?.lowerBound != null &&
                argument?.upperBound != null
            ? (math.exp(argument!.lowerBound!), math.exp(argument.upperBound!))
            : null;
        final trigBounds =
            hasSingleArgument && const {'sin', 'cos'}.contains(token.text)
            ? _trigInterval(token.text, argument!)
            : null;
        final tanBounds = hasSingleArgument && token.text == 'tan'
            ? _tanInterval(argument!)
            : null;
        final continuousFunctionBounds = hasSingleArgument
            ? _continuousUnaryInterval(token.text, argument!)
            : null;
        final singularFunctionBounds = hasSingleArgument
            ? _singularUnaryInterval(
                token.text,
                argument!,
                trigBounds: _trigInterval('sin', argument),
                cosineBounds: _trigInterval('cos', argument),
                sinhBounds: _continuousUnaryInterval('sinh', argument),
                coshBounds: _continuousUnaryInterval('cosh', argument),
                sechBounds: _continuousUnaryInterval('sech', argument),
              )
            : null;
        final continuousFunctionIsDefined =
            !const {'asin', 'acos'}.contains(token.text) ||
            argument != null &&
                argument.lowerBound != null &&
                argument.upperBound != null &&
                argument.lowerBound! >= -1 &&
                argument.upperBound! <= 1;
        final sqrtIsDefined =
            token.text != 'sqrt' ||
            argument != null &&
                argument.lowerBound != null &&
                argument.lowerBound! >= 0;
        final isUnaryLog =
            token.text == 'ln' || token.text == 'log' && hasSingleArgument;
        final logIsDefined =
            !isUnaryLog ||
            argument != null &&
                argument.lowerBound != null &&
                argument.lowerBound! > 0;
        final logBounds =
            isUnaryLog &&
                argument?.lowerBound != null &&
                argument?.upperBound != null &&
                argument!.lowerBound! > 0
            ? (math.log(argument.lowerBound!), math.log(argument.upperBound!))
            : null;
        final sqrtBounds =
            token.text == 'sqrt' &&
                argument?.lowerBound != null &&
                argument?.upperBound != null &&
                argument!.lowerBound! >= 0
            ? (math.sqrt(argument.lowerBound!), math.sqrt(argument.upperBound!))
            : null;
        final binaryNrtBounds =
            token.text == 'nrt' &&
                args.length == 2 &&
                args[0].integer != null &&
                args[0].integer! > 0 &&
                args.every((arg) => arg.continuous) &&
                args[1].lowerBound != null &&
                args[1].upperBound != null &&
                (args[0].integer!.isOdd || args[1].lowerBound! >= 0)
            ? _binaryNrtInterval(args[0].integer!, args[1])
            : null;
        final binaryPowBounds =
            token.text == 'pow' &&
                args.length == 2 &&
                args.every((arg) => arg.continuous) &&
                args[0].lowerBound != null &&
                args[0].upperBound != null &&
                args[1].lowerBound != null &&
                args[1].upperBound != null &&
                args[0].lowerBound! > 0
            ? _binaryPowInterval(args[0], args[1])
            : null;
        final binaryLogBounds =
            token.text == 'log' &&
                args.length == 2 &&
                args[0].lowerBound != null &&
                args[0].upperBound != null &&
                args[1].lowerBound != null &&
                args[1].upperBound != null &&
                args[0].lowerBound! > 0 &&
                (args[0].upperBound! < 1 || args[0].lowerBound! > 1) &&
                args[1].lowerBound! > 0
            ? _binaryLogInterval(args[0], args[1])
            : null;
        final binaryLogIsDefined =
            token.text != 'log' ||
            hasSingleArgument ||
            args.length == 2 &&
                args.every((arg) => arg.continuous) &&
                binaryLogBounds != null;
        final isContinuous =
            hasSingleArgument &&
                supported &&
                argument!.continuous &&
                (token.text != 'tan' || tanBounds != null) &&
                (!const {
                      'sec',
                      'csc',
                      'cot',
                      'csch',
                      'coth',
                    }.contains(token.text) ||
                    singularFunctionBounds != null) &&
                continuousFunctionIsDefined &&
                sqrtIsDefined &&
                logIsDefined &&
                binaryLogIsDefined &&
                (token.text != 'exp' ||
                    expBounds != null &&
                        expBounds.$1.isFinite &&
                        expBounds.$2.isFinite) ||
            token.text == 'log' &&
                args.length == 2 &&
                args.every((arg) => arg.continuous) &&
                binaryLogIsDefined ||
            token.text == 'pow' &&
                args.length == 2 &&
                args.every((arg) => arg.continuous) &&
                binaryPowBounds != null ||
            token.text == 'nrt' &&
                args.length == 2 &&
                args.every((arg) => arg.continuous) &&
                binaryNrtBounds != null;
        final functionLowerBound =
            expBounds?.$1 ??
            absBounds?.$1 ??
            sqrtBounds?.$1 ??
            logBounds?.$1 ??
            trigBounds?.$1 ??
            tanBounds?.$1 ??
            continuousFunctionBounds?.$1 ??
            singularFunctionBounds?.$1 ??
            binaryLogBounds?.$1 ??
            binaryPowBounds?.$1 ??
            binaryNrtBounds?.$1;
        final functionUpperBound =
            expBounds?.$2 ??
            absBounds?.$2 ??
            sqrtBounds?.$2 ??
            logBounds?.$2 ??
            trigBounds?.$2 ??
            tanBounds?.$2 ??
            continuousFunctionBounds?.$2 ??
            singularFunctionBounds?.$2 ??
            binaryLogBounds?.$2 ??
            binaryPowBounds?.$2 ??
            binaryNrtBounds?.$2;
        final functionIsZero =
            hasSingleArgument &&
                argument!.zero &&
                const {
                  'abs',
                  'sin',
                  'sqrt',
                  'tan',
                  'sinh',
                  'tanh',
                  'atan',
                  'asin',
                }.contains(token.text) ||
            logBounds != null && logBounds.$1 == 0 && logBounds.$2 == 0 ||
            binaryLogBounds != null &&
                binaryLogBounds.$1 == 0 &&
                binaryLogBounds.$2 == 0 ||
            binaryNrtBounds != null &&
                binaryNrtBounds.$1 == 0 &&
                binaryNrtBounds.$2 == 0;
        final functionIsNonzero =
            hasSingleArgument &&
                (argument!.zero && token.text == 'cos' ||
                    token.text == 'sqrt' &&
                        argument.lowerBound != null &&
                        argument.lowerBound! > 0) ||
            expBounds != null && expBounds.$1 > 0 ||
            logBounds != null && (logBounds.$1 > 0 || logBounds.$2 < 0) ||
            trigBounds != null && (trigBounds.$1 > 0 || trigBounds.$2 < 0) ||
            tanBounds != null && (tanBounds.$1 > 0 || tanBounds.$2 < 0) ||
            continuousFunctionBounds != null &&
                (continuousFunctionBounds.$1 > 0 ||
                    continuousFunctionBounds.$2 < 0) ||
            singularFunctionBounds != null &&
                (singularFunctionBounds.$1 > 0 ||
                    singularFunctionBounds.$2 < 0) ||
            binaryLogBounds != null &&
                (binaryLogBounds.$1 > 0 || binaryLogBounds.$2 < 0) ||
            binaryPowBounds != null &&
                (binaryPowBounds.$1 > 0 || binaryPowBounds.$2 < 0) ||
            binaryNrtBounds != null &&
                (binaryNrtBounds.$1 > 0 || binaryNrtBounds.$2 < 0);
        return _RootEvidenceNode(
          token.text,
          '${token.text}(${args.map((arg) => arg.code).join(',')})',
          left: argument,
          continuous: isContinuous,
          zero: functionIsZero,
          nonzero: functionIsNonzero,
          lowerBound: functionLowerBound,
          upperBound: functionUpperBound,
        );
      }
      final substitution = substitutions[token.text];
      if (substitution != null) {
        final integer =
            substitution.isFinite &&
                substitution.truncateToDouble() == substitution
            ? substitution.toInt()
            : null;
        return _RootEvidenceNode(
          'number',
          substitution.toString(),
          continuous: substitution.isFinite,
          zero: substitution == 0,
          nonzero: substitution != 0 && substitution.isFinite,
          integer: integer,
          lowerBound: substitution,
          upperBound: substitution,
        );
      }
      final constant = MathExpressionParser._constants[token.text];
      if (constant != null) {
        return _RootEvidenceNode(
          'number',
          token.text,
          continuous: constant.isFinite,
          zero: constant == 0,
          nonzero: constant != 0 && constant.isFinite,
          lowerBound: constant,
          upperBound: constant,
        );
      }
      final interval = intervals[token.text];
      return _RootEvidenceNode(
        'identifier',
        token.text,
        continuous: variables.contains(token.text),
        nonzero: interval != null && (interval.$1 > 0 || interval.$2 < 0),
        lowerBound: interval?.$1,
        upperBound: interval?.$2,
      );
    }
    throw const FormatException('Expected expression');
  }

  (double, double)? _singularUnaryInterval(
    String name,
    _RootEvidenceNode argument, {
    required (double, double)? trigBounds,
    required (double, double)? cosineBounds,
    required (double, double)? sinhBounds,
    required (double, double)? coshBounds,
    required (double, double)? sechBounds,
  }) {
    switch (name) {
      case 'sec':
        return cosineBounds == null
            ? null
            : _divideIntervals((1, 1), cosineBounds);
      case 'csc':
        return trigBounds == null ? null : _divideIntervals((1, 1), trigBounds);
      case 'cot':
        if (cosineBounds == null || trigBounds == null) return null;
        return _divideIntervals(cosineBounds, trigBounds);
      case 'sech':
        return sechBounds;
      case 'csch':
        final bounds = sinhBounds;
        return bounds == null ? null : _divideIntervals((1, 1), bounds);
      case 'coth':
        if (coshBounds == null || sinhBounds == null) return null;
        return _divideIntervals(coshBounds, sinhBounds);
      default:
        return null;
    }
  }

  (double, double)? _divideIntervals(
    (double, double) numerator,
    (double, double) denominator,
  ) {
    if (denominator.$1 <= 0 && denominator.$2 >= 0) return null;
    final values = [
      numerator.$1 / denominator.$1,
      numerator.$1 / denominator.$2,
      numerator.$2 / denominator.$1,
      numerator.$2 / denominator.$2,
    ];
    final lower = values.reduce(math.min);
    final upper = values.reduce(math.max);
    if (!lower.isFinite || !upper.isFinite) return null;
    return (lower, upper);
  }

  (double, double)? _continuousUnaryInterval(
    String name,
    _RootEvidenceNode argument,
  ) {
    final lower = argument.lowerBound;
    final upper = argument.upperBound;
    if (lower == null || upper == null || !lower.isFinite || !upper.isFinite) {
      return null;
    }
    late final double minimum;
    late final double maximum;
    switch (name) {
      case 'sinh':
        minimum = MathExpressionParser._sinh(lower);
        maximum = MathExpressionParser._sinh(upper);
      case 'cosh':
        final left = (math.exp(lower) + math.exp(-lower)) / 2;
        final right = (math.exp(upper) + math.exp(-upper)) / 2;
        minimum = lower <= 0 && upper >= 0 ? 1 : math.min(left, right);
        maximum = math.max(left, right);
      case 'sech':
        double sech(double value) => 2 / (math.exp(value) + math.exp(-value));
        final left = sech(lower);
        final right = sech(upper);
        minimum = math.min(left, right);
        maximum = lower <= 0 && upper >= 0 ? 1 : math.max(left, right);
      case 'tanh':
        minimum = MathExpressionParser._tanh(lower);
        maximum = MathExpressionParser._tanh(upper);
      case 'atan':
        minimum = math.atan(lower);
        maximum = math.atan(upper);
      case 'asin':
        if (lower < -1 || upper > 1) return null;
        minimum = math.asin(lower);
        maximum = math.asin(upper);
      case 'acos':
        if (lower < -1 || upper > 1) return null;
        minimum = math.acos(upper);
        maximum = math.acos(lower);
      default:
        return null;
    }
    if (!minimum.isFinite || !maximum.isFinite) return null;
    return (minimum, maximum);
  }

  (double, double) _absoluteInterval(double lower, double upper) {
    final maximum = math.max(lower.abs(), upper.abs());
    final minimum = lower <= 0 && upper >= 0
        ? 0.0
        : math.min(lower.abs(), upper.abs());
    return (minimum, maximum);
  }

  (double, double)? _tanInterval(_RootEvidenceNode argument) {
    final lower = argument.lowerBound;
    final upper = argument.upperBound;
    if (lower == null ||
        upper == null ||
        !lower.isFinite ||
        !upper.isFinite ||
        lower > upper) {
      return null;
    }
    final firstPole = ((lower - math.pi / 2) / math.pi).ceil();
    final lastPole = ((upper - math.pi / 2) / math.pi).floor();
    if (firstPole <= lastPole) return null;
    final low = math.tan(lower);
    final high = math.tan(upper);
    if (!low.isFinite || !high.isFinite) return null;
    return (low, high);
  }

  (double, double)? _binaryNrtInterval(int degree, _RootEvidenceNode value) {
    final lower = value.lowerBound;
    final upper = value.upperBound;
    if (lower == null || upper == null || !lower.isFinite || !upper.isFinite) {
      return null;
    }
    double root(double input) => input < 0
        ? -math.pow(-input, 1 / degree).toDouble()
        : math.pow(input, 1 / degree).toDouble();
    final first = root(lower);
    final last = root(upper);
    final minimum = math.min(first, last);
    final maximum = math.max(first, last);
    if (!minimum.isFinite || !maximum.isFinite) return null;
    return (minimum, maximum);
  }

  (double, double)? _binaryPowInterval(
    _RootEvidenceNode base,
    _RootEvidenceNode exponent,
  ) {
    final baseLower = base.lowerBound;
    final baseUpper = base.upperBound;
    final exponentLower = exponent.lowerBound;
    final exponentUpper = exponent.upperBound;
    if (baseLower == null ||
        baseUpper == null ||
        exponentLower == null ||
        exponentUpper == null ||
        baseLower <= 0 ||
        !baseUpper.isFinite ||
        !exponentLower.isFinite ||
        !exponentUpper.isFinite) {
      return null;
    }
    final logLower = math.log(baseLower);
    final logUpper = math.log(baseUpper);
    final products = [
      logLower * exponentLower,
      logLower * exponentUpper,
      logUpper * exponentLower,
      logUpper * exponentUpper,
    ];
    final lower = math.exp(products.reduce(math.min));
    final upper = math.exp(products.reduce(math.max));
    if (!lower.isFinite || !upper.isFinite) return null;
    return (lower, upper);
  }

  (double, double)? _binaryLogInterval(
    _RootEvidenceNode base,
    _RootEvidenceNode value,
  ) {
    final baseLower = base.lowerBound;
    final baseUpper = base.upperBound;
    final valueLower = value.lowerBound;
    final valueUpper = value.upperBound;
    if (baseLower == null ||
        baseUpper == null ||
        valueLower == null ||
        valueUpper == null ||
        baseLower <= 0 ||
        baseLower <= 1 && baseUpper >= 1 ||
        valueLower <= 0) {
      return null;
    }
    final logBase = [math.log(baseLower), math.log(baseUpper)];
    final logValue = [math.log(valueLower), math.log(valueUpper)];
    final denominatorLower = logBase.reduce(math.min);
    final denominatorUpper = logBase.reduce(math.max);
    final numeratorLower = logValue.reduce(math.min);
    final numeratorUpper = logValue.reduce(math.max);
    if (denominatorLower <= 0 && denominatorUpper >= 0) return null;
    final quotients = [
      numeratorLower / denominatorLower,
      numeratorLower / denominatorUpper,
      numeratorUpper / denominatorLower,
      numeratorUpper / denominatorUpper,
    ];
    final lower = quotients.reduce(math.min);
    final upper = quotients.reduce(math.max);
    if (!lower.isFinite || !upper.isFinite) return null;
    return (lower, upper);
  }

  (double, double)? _trigInterval(String name, _RootEvidenceNode argument) {
    final lower = argument.lowerBound;
    final upper = argument.upperBound;
    if (lower == null ||
        upper == null ||
        !lower.isFinite ||
        !upper.isFinite ||
        lower > upper ||
        lower.abs() > 1e12 ||
        upper.abs() > 1e12) {
      return null;
    }
    final values = name == 'sin'
        ? [math.sin(lower), math.sin(upper)]
        : [math.cos(lower), math.cos(upper)];
    var minimum = values.reduce(math.min);
    var maximum = values.reduce(math.max);
    final period = 2 * math.pi;
    bool contains(double phase) =>
        ((lower - phase) / period).ceil() <= ((upper - phase) / period).floor();
    if (name == 'sin') {
      if (contains(math.pi / 2)) maximum = 1;
      if (contains(-math.pi / 2)) minimum = -1;
    } else {
      if (contains(0)) maximum = 1;
      if (contains(math.pi)) minimum = -1;
    }
    return (minimum, maximum);
  }

  (double, double)? _intervalFor(
    String operation,
    _RootEvidenceNode left,
    _RootEvidenceNode right,
  ) {
    final a = left.lowerBound;
    final b = left.upperBound;
    final c = right.lowerBound;
    final d = right.upperBound;
    if (a == null || b == null || c == null || d == null) return null;
    late final double lower;
    late final double upper;
    switch (operation) {
      case '+':
        lower = a + c;
        upper = b + d;
      case '-':
        lower = a - d;
        upper = b - c;
      case '*':
        final products = [a * c, a * d, b * c, b * d];
        lower = products.reduce((x, y) => x < y ? x : y);
        upper = products.reduce((x, y) => x > y ? x : y);
      case '/':
        if (c <= 0 && d >= 0) return null;
        final quotients = [a / c, a / d, b / c, b / d];
        lower = quotients.reduce((x, y) => x < y ? x : y);
        upper = quotients.reduce((x, y) => x > y ? x : y);
      case '^':
        final exponent = right.integer;
        if (exponent == null || exponent < 0) return null;
        final first = math.pow(a, exponent).toDouble();
        final last = math.pow(b, exponent).toDouble();
        if (exponent == 0) {
          lower = 1;
          upper = 1;
        } else if (exponent.isEven && a <= 0 && b >= 0) {
          lower = 0;
          upper = first.abs() > last.abs() ? first.abs() : last.abs();
        } else {
          lower = first < last ? first : last;
          upper = first > last ? first : last;
        }
      default:
        return null;
    }
    if (!lower.isFinite || !upper.isFinite) return null;
    return (lower, upper);
  }
}
