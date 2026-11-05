import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  test(
    'parameter defaults and exact typed values remain independent of step',
    () {
      final parameter = MathParameter();
      expect(parameter.value, 1);
      expect(parameter.min, -5);
      expect(parameter.max, 5);
      expect(parameter.step, 0.1);
      expect(parameter.withValue(1.23456789).value, 1.23456789);
      expect(parameter.value, 1);
      expect(parameter.withValue(-20).value, -5);
      expect(parameter.withValue(20).value, 5);
    },
  );

  test('parameter slider grid starts at a negative fractional minimum', () {
    final parameter = MathParameter(min: -0.7, max: 1.2, step: 0.25);
    expect(parameter.snap(-0.7), -0.7);
    expect(parameter.snap(-0.36), closeTo(-0.45, 1e-12));
    expect(parameter.snap(0.46), closeTo(0.55, 1e-12));
    expect(parameter.snap(-20), -0.7);
  });

  test(
    'parameter nondividing range retains step and reaches its short endpoint',
    () {
      final parameter = MathParameter(min: -1, max: 1, step: 0.6);
      expect(parameter.snap(-0.4), closeTo(-0.4, 1e-12));
      expect(parameter.snap(0.2), closeTo(0.2, 1e-12));
      expect(parameter.snap(1), 1);
      expect(parameter.snap(100), 1);
      expect(parameter.withValue(1).value, 1);
    },
  );

  test('parameter decimal precision includes aligned endpoints', () {
    final parameter = MathParameter(min: -0.3, max: 0.3, step: 0.1);
    expect(parameter.snap(-0.3), -0.3);
    expect(parameter.snap(0.3), 0.3);
    expect(parameter.snap(0.2), closeTo(0.2, 1e-14));
    final fractional = MathParameter(min: 0, max: 0.3, step: 0.1);
    expect(fractional.snap(0.3), 0.3);
  });

  test(
    'parameter reconfiguration clamps current or explicit value exactly',
    () {
      final parameter = MathParameter(value: 4.123);
      final narrower = parameter.reconfigure(min: -1, max: 2, step: 0.3);
      expect(narrower.value, 2);
      expect(narrower.step, 0.3);
      expect(parameter.value, 4.123);
      expect(
        parameter.reconfigure(min: -1, max: 2, step: 0.3, value: 1.234).value,
        1.234,
      );
      expect(
        parameter.reconfigure(min: -1, max: 2, step: 0.3, value: -9).value,
        -1,
      );
    },
  );

  test('parameter rejects nonfinite values and invalid bounds or step', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(() => MathParameter(value: value), throwsArgumentError);
      expect(() => MathParameter(min: value), throwsArgumentError);
      expect(() => MathParameter(max: value), throwsArgumentError);
      expect(() => MathParameter(step: value), throwsArgumentError);
      expect(() => MathParameter().withValue(value), throwsArgumentError);
      expect(() => MathParameter().snap(value), throwsArgumentError);
    }
    expect(() => MathParameter(min: 2, max: 2), throwsArgumentError);
    expect(() => MathParameter(min: 3, max: 2), throwsArgumentError);
    expect(() => MathParameter(step: 0), throwsArgumentError);
    expect(() => MathParameter(step: -0.1), throwsArgumentError);
    expect(() => MathParameter(step: 11), throwsArgumentError);
    expect(
      () => MathParameter(min: -1e308, max: 1e308, step: 1),
      throwsArgumentError,
    );
  });

  test(
    'parameter rejects floating grids that cannot advance or index safely',
    () {
      expect(
        () => MathParameter(min: 1e16, max: 1e16 + 4, step: 0.1),
        throwsArgumentError,
      );
      expect(
        () => MathParameter(min: 0, max: 1, step: 1e-310),
        throwsArgumentError,
      );
      expect(
        () => MathParameter(min: 0, max: 1, step: 1e-18),
        throwsArgumentError,
      );
    },
  );

  test('parameter supports one-step grids and large usable finite bounds', () {
    final single = MathParameter(min: -2, max: 3, step: 5);
    expect(single.snap(-2), -2);
    expect(single.snap(3), 3);
    final large = MathParameter(min: 1e16, max: 1e16 + 4, step: 2);
    expect(large.snap(1e16 + 4), 1e16 + 4);
  });

  test(
    'parameter large grid adjacency uses integer indices in both directions',
    () {
      const min = 10000000000000000.0;
      var parameter = MathParameter(
        value: min,
        min: min,
        max: min + 10,
        step: 3,
      );
      for (final offset in [4, 6, 8, 10]) {
        final next = parameter.adjacentValue(true);
        expect(next - min, offset);
        parameter = parameter.withValue(next);
      }
      expect(parameter.adjacentValue(true), parameter.value);
      for (final offset in [8, 6, 4, 0]) {
        final next = parameter.adjacentValue(false);
        expect(next - min, offset);
        parameter = parameter.withValue(next);
      }
      expect(parameter.adjacentValue(false), min);
      final between = parameter.withValue(min + 2);
      expect(between.adjacentValue(true) - min, 4);
      expect(between.adjacentValue(false) - min, 0);
      final typedMax = parameter.withValue(min + 10);
      expect(typedMax.adjacentValue(true), min + 10);
      expect(typedMax.adjacentValue(false), min + 8);
    },
  );

  test(
    'parameter adjacency preserves typed values and fractional boundaries',
    () {
      final parameter = MathParameter(
        value: 0.42,
        min: -0.7,
        max: 1.2,
        step: 0.25,
      );
      expect(parameter.value, 0.42);
      expect(parameter.adjacentValue(true), closeTo(0.55, 1e-12));
      expect(parameter.adjacentValue(false), closeTo(0.3, 1e-12));
      expect(parameter.withValue(-0.7).adjacentValue(false), -0.7);
      expect(parameter.withValue(1.05).adjacentValue(true), 1.2);
      expect(parameter.withValue(1.2).adjacentValue(true), 1.2);
      expect(
        parameter.withValue(1.2).adjacentValue(false),
        closeTo(1.05, 1e-12),
      );
      expect(
        parameter.withValue(0.05).adjacentValue(true),
        closeTo(0.3, 1e-12),
      );
      final aligned = MathParameter(value: 0.3, min: -0.3, max: 0.3, step: 0.1);
      expect(aligned.adjacentValue(true), 0.3);
      expect(aligned.adjacentValue(false), closeTo(0.2, 1e-12));
    },
  );

  test(
    'parameter duplicate ticks advance in both directions within bounds',
    () {
      for (final min in [1e16, -1e16]) {
        var parameter = MathParameter(
          value: min + 4,
          min: min,
          max: min + 10,
          step: 1.1,
        );
        expect(parameter.adjacentValue(false) - min, 2);
        parameter = parameter.withValue(min);
        for (final offset in [2, 4, 6, 8, 10]) {
          parameter = parameter.withValue(parameter.adjacentValue(true));
          expect(parameter.value - min, offset);
        }
        expect(parameter.adjacentValue(true), min + 10);
        for (final offset in [8, 6, 4, 2, 0]) {
          parameter = parameter.withValue(parameter.adjacentValue(false));
          expect(parameter.value - min, offset);
        }
        expect(parameter.adjacentValue(false), min);
      }
    },
  );

  test(
    'parameter large grid formatting preserves distinct accepted values',
    () {
      const min = 10000000000000000.0;
      expect(
        [
          for (final offset in [0, 4, 6, 8])
            formatMathParameterNumber(min + offset),
        ],
        [
          '10000000000000000',
          '10000000000000004',
          '10000000000000006',
          '10000000000000008',
        ],
      );
      for (final value in [
        1e15 + 0.5,
        -1e15 - 0.5,
        1e13 + 0.0625,
        -1e13 - 0.0625,
        1.2345678901234567,
        -1.2345678901234567,
      ]) {
        expect(double.parse(formatMathParameterNumber(value)), value);
      }
      expect(formatMathParameterNumber(0.1 + 0.2), '0.3');
    },
  );

  test(
    'parameter presentation cleans grid cancellation and preserves exact entry',
    () {
      final defaults = MathParameter(value: 0);
      final defaultTick = defaults.snap(0.1);
      expect(defaults.withValue(defaultTick).formatValue(), '0.1');
      expect(defaults.formatValue(defaultTick), '0.1');
      final fractional = MathParameter(
        value: -0.2,
        min: -0.7,
        max: 1.2,
        step: 0.25,
      );
      expect(fractional.formatValue(fractional.snap(0.05)), '0.05');
      for (final typed in [
        1.2345678901234567,
        -1.2345678901234567,
        0.10000000000000057,
      ]) {
        expect(defaults.snap(typed), isNot(typed));
        expect(defaults.withValue(typed).formatValue(), typed.toString());
      }
    },
  );

  test('parameter presentation preserves neighboring large grid values', () {
    final integral = MathParameter(
      value: 1e16,
      min: 1e16,
      max: 1e16 + 10,
      step: 1.1,
    );
    expect(integral.formatValue(), '10000000000000000');
    for (final parameter in [
      MathParameter(value: 1e16 + 2, min: 1e16, max: 1e16 + 10, step: 1.1),
      MathParameter(
        value: 1e13 + 0.0625,
        min: 1e13,
        max: 1e13 + 1,
        step: 0.0625,
      ),
      MathParameter(
        value: -1e13 - 0.0625,
        min: -1e13 - 1,
        max: -1e13,
        step: 0.0625,
      ),
    ]) {
      expect(parameter.value, parameter.snap(parameter.value));
      expect(double.parse(parameter.formatValue()), parameter.value);
      final next = parameter.adjacentValue(true);
      expect(double.parse(parameter.formatValue(next)), next);
      expect(parameter.formatValue(next), isNot(parameter.formatValue()));
    }
  });
}
