import 'dart:convert';
import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'hermetic.dart';

final pinned = ['--flutter-version', '3.47.2', '--java-version', '17'];

String fixture(String name) => p.join('test', 'fixtures', name);

Future<({int code, String out, String err})> run(List<String> args) async {
  final out = StringBuffer(), err = StringBuffer();
  final code = await runDroidDoctor(
    cacheDir: hermeticCacheDir,
    now: hermeticNow,
    args,
    out: out,
    err: err,
    // Any process call would make the test depend on the machine.
    probe: EnvironmentProbe(
      run: (exe, args) => throw StateError('unexpected process: $exe $args'),
    ),
  );
  return (code: code, out: out.toString(), err: err.toString());
}

void main() {
  test('check is the default command', () async {
    final r = await run(['-p', fixture('modern_kts'), ...pinned]);
    expect(r.code, ExitCode.ok);
    expect(r.out, contains('No problems found.'));
    expect(r.out, isNot(contains('\x1B[')), reason: 'no color in tests');
  });

  test('exits 1 when errors are found', () async {
    final r = await run(['check', '-p', fixture('broken_kts'), ...pinned]);
    expect(r.code, ExitCode.problems);
    expect(r.out, contains('7 errors, 2 warnings, 0 infos.'));
  });

  test('--ci fails on warnings too', () async {
    final args = ['-p', fixture('catalog_kts'), ...pinned];
    expect((await run(args)).code, ExitCode.ok);
    expect((await run([...args, '--ci'])).code, ExitCode.problems);
  });

  test('--json output', () async {
    final r = await run(['-p', fixture('broken_kts'), '--json', ...pinned]);
    final json = jsonDecode(r.out) as Map<String, Object?>;
    expect(json['summary'], {'error': 7, 'warning': 2, 'info': 0});
    final project = json['project'] as Map<String, Object?>;
    expect((project['agp'] as Map)['value'], '8.7.0');
    final first = (json['findings'] as List).first as Map;
    expect(first['severity'], 'error');
    expect(first['location'], isA<Map<String, Object?>>());
  });

  test('--color forces ANSI colors', () async {
    final r = await run(['-p', fixture('modern_kts'), '--color', ...pinned]);
    expect(r.out, contains('\x1B['));
  });

  test('missing project is a usage error', () async {
    final empty = Directory.systemTemp.createTempSync('droid_doctor_');
    addTearDown(() => empty.deleteSync(recursive: true));
    final r = await run(['-p', empty.path, ...pinned]);
    expect(r.code, ExitCode.usage);
    expect(r.err, contains('No Android project found'));
  });

  test('invalid overrides and options are usage errors', () async {
    final r = await run([
      '-p',
      fixture('modern_kts'),
      '--flutter-version',
      'x',
      '--java-version',
      '17'
    ]);
    expect(r.code, ExitCode.usage);
    expect(r.err, contains('Invalid --flutter-version'));
    expect((await run(['--bogus'])).code, ExitCode.usage);
  });

  test('custom --matrix', () async {
    final dir = Directory.systemTemp.createTempSync('droid_doctor_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bad = File(p.join(dir.path, 'm.json'))..writeAsStringSync('{}');
    final r = await run(
        ['-p', fixture('modern_kts'), '--matrix', bad.path, ...pinned]);
    expect(r.code, ExitCode.usage);
    expect(r.err, contains('Invalid matrix'));
  });

  test('--version and --help', () async {
    expect(
        (await run(['--version'])).out.trim(), 'droid_doctor $packageVersion');
    final help = await run(['--help']);
    expect(help.code, ExitCode.ok);
    expect(help.out, contains('check'));
  });

  test('--annotations emits GitHub workflow commands', () async {
    for (final project in [
      fixture('broken_kts'),
      p.join(fixture('broken_kts'), 'android'),
    ]) {
      final r = await run(['-p', project, '--annotations', ...pinned]);
      final lines = r.out.split('\n').where((l) => l.startsWith('::')).toList();
      expect(lines, hasLength(9));
      expect(
        lines.first,
        '::error title=droid_doctor%3A compatibility,'
        'file=test/fixtures/broken_kts/android/gradle/wrapper/'
        'gradle-wrapper.properties,line=5::Android Gradle Plugin 8.7.0 '
        'requires Gradle 8.9 or newer (found 8.3).%0AFix: Set distributionUrl '
        r'to https\://services.gradle.org/distributions/gradle-8.9-all.zip',
        reason: 'same path whether -p is the root or android/',
      );
    }
  });
}
