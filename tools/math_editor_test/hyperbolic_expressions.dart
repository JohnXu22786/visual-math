import '../../lib/src/models/math_expression_parser.dart';

void main() {
  for (final name in ['tanh', 'coth']) {
    print(MathExpressionParser.toJavaScript('$name(x)', variables: ['x']));
  }
}
