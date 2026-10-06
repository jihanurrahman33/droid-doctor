import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:droid_doctor/src/data/bundled_matrix.g.dart';
import 'package:test/test.dart';

import '../tool/embed_matrix.dart' show embedMatrix;

void main() {
  final source = File('data/matrix.json').readAsStringSync();

  test('bundled matrix is in sync with data/matrix.json', () {
    expect(
      File('lib/src/data/bundled_matrix.g.dart').readAsStringSync(),
      embedMatrix(source),
      reason: 'run: dart run tool/embed_matrix.dart',
    );
    expect(bundledMatrixJson, source);
  });

  test('bundled matrix parses', () {
    final m = CompatMatrix.bundled();
    expect(m.rules, isNotEmpty);
    expect(m.flutter, isNotEmpty);
    expect(m.unknownFrom.keys, containsAll(Component.values));
  });

  test('rules for the same component pair never overlap', () {
    final rules = CompatMatrix.bundled().rules;
    for (var i = 0; i < rules.length; i++) {
      for (var j = i + 1; j < rules.length; j++) {
        final a = rules[i], b = rules[j];
        if (a.when != b.when || a.require != b.require) continue;
        expect(_overlaps(a.whenRange, b.whenRange), isFalse,
            reason: 'rules[$i] ${a.when.name} ${a.whenRange} overlaps '
                'rules[$j] ${b.whenRange}');
      }
    }
  });

  test('every rule has a reference and a sane range', () {
    for (final r in CompatMatrix.bundled().rules) {
      expect(r.reference, startsWith('https://'));
      final min = r.requireRange.min, max = r.requireRange.max;
      if (min != null && max != null) expect(min < max, isTrue);
    }
  });

  test('rejects malformed matrices with a precise message', () {
    expect(
      () => CompatMatrix.parse('{"schemaVersion": 2}'),
      throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', contains('schemaVersion 2'))),
    );
    expect(() => CompatMatrix.parse('nope'), throwsFormatException);
    final badRule = source.replaceFirst('"when": "java"', '"when": "jdk"');
    expect(
      () => CompatMatrix.parse(badRule),
      throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', contains('rules[0]'))),
    );
  });

  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!;
    expect(packageVersion, version.group(1));
  });
}

bool _overlaps(VersionRange a, VersionRange b) {
  // Ranges are [min, max); a null bound is unbounded.
  bool before(VersionRange x, VersionRange y) =>
      x.max != null &&
      y.min != null &&
      (x.maxInclusive ? x.max! < y.min! : x.max! <= y.min!);
  return !before(a, b) && !before(b, a);
}
