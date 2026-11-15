import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  test('copyWith retains or clears hiddenPlot3D explicitly', () {
    const plot = Object3D.point(Point3D(1, 2, 3));
    const entry = FormulaEntry(rawExpression: 'x', hiddenPlot3D: plot);

    expect(entry.copyWith().hiddenPlot3D, same(plot));
    expect(entry.copyWith(clearHiddenPlot3D: true).hiddenPlot3D, isNull);
  });

  test('copyWith retains or clears domainStartExpression explicitly', () {
    const entry = FormulaEntry(rawExpression: 'x', domainStartExpression: 'a');

    expect(entry.copyWith().domainStartExpression, 'a');
    expect(
      entry.copyWith(clearDomainStartExpression: true).domainStartExpression,
      isNull,
    );
  });

  test('copyWith retains or clears domainEndExpression explicitly', () {
    const entry = FormulaEntry(rawExpression: 'x', domainEndExpression: 'b');

    expect(entry.copyWith().domainEndExpression, 'b');
    expect(
      entry.copyWith(clearDomainEndExpression: true).domainEndExpression,
      isNull,
    );
  });
}
