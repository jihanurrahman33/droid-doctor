import 'package:test/test.dart';

import '../tool/homebrew_formula.dart';

void main() {
  String sum(String c) => c * 64;
  final checksums = '''
${sum('a')}  droid_doctor-1.0.0-macos-arm64.tar.gz
${sum('b')}  droid_doctor-1.0.0-macos-x64.tar.gz
${sum('c')}  droid_doctor-1.0.0-linux-arm64.tar.gz
${sum('d')} *droid_doctor-1.0.0-linux-x64.tar.gz
${sum('e')}  droid_doctor-1.0.0-windows-x64.zip
''';

  test('builds a formula with per-platform archives', () {
    final formula = homebrewFormula('1.0.0', checksums);
    expect(formula, contains('class DroidDoctor < Formula'));
    expect(formula, contains('version "1.0.0"'));
    expect(
      formula,
      contains('    on_arm do\n'
          '      url "https://github.com/jihanurrahman33/droid-doctor/releases/'
          'download/v1.0.0/droid_doctor-1.0.0-macos-arm64.tar.gz"\n'
          '      sha256 "${sum('a')}"\n'),
    );
    for (final c in ['a', 'b', 'c', 'd']) {
      expect(formula, contains(sum(c)));
    }
    expect(formula, isNot(contains(sum('e'))), reason: 'Windows has no brew');
  });

  test('fails loudly when an archive is missing', () {
    expect(
      () => homebrewFormula('1.0.0', checksums.replaceAll('linux-arm64', 'x')),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('linux-arm64'))),
    );
  });
}
