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
    'coth': (value) =>
        (math.exp(value) + math.exp(-value)) /
        (math.exp(value) - math.exp(-value)),
    'csc': (value) => 1 / math.sin(value),
    'csch': (value) => 2 / (math.exp(value) - math.exp(-value)),
    'exp': math.exp,
    'fact': _factorial,
    'floor': (value) => value.floorToDouble(),
    'ln': math.log,
    'log': math.log,
    'round': (value) => value.roundToDouble(),
    'sec': (value) => 1 / math.cos(value),
    'sech': (value) => 2 / (math.exp(value) + math.exp(-value)),
    'sin': math.sin,
    'sinh': (value) => (math.exp(value) - math.exp(-value)) / 2,
    'sqrt': math.sqrt,
    'tan': math.tan,
    'tanh': (value) =>
        (math.exp(value) - math.exp(-value)) /
        (math.exp(value) + math.exp(-value)),
  };

  static final Map<String, double Function(double, double)> _binaryFunctions = {
    'log': (base, value) => math.log(value) / math.log(base),
    'nrt': (root, value) => value < 0 && root.isFinite && root % 2 == 1
        ? -math.pow(-value, 1 / root).toDouble()
        : math.pow(value, 1 / root).toDouble(),
    'pow': (base, exponent) => math.pow(base, exponent).toDouble(),
  };

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
