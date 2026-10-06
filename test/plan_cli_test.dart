import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'hermetic.dart';

Future<({int code, String out, String err})> run(
  List<String> args, {
  String? cacheDir,
  DateTime Function()? now,
  Future<String> Function(Uri)? httpGet,
}) async {
  final out = StringBuffer(), err = StringBuffer();
  final code = await runDroidDoctor(
    args,
    out: out,
    err: err,
    cacheDir: cacheDir ?? hermeticCacheDir,
    now: now ?? hermeticNow,
    httpGet: httpGet ?? (uri) => throw StateError('unexpected download $uri'),
    probe: EnvironmentProbe(
        run: (exe, a) => throw StateError('unexpected process $exe')),
  );
  return (code: code, out: out.toString(), err: err.toString());
}

String fixture(String name) => p.join('test', 'fixtures', name);

void main() {
  group('plan', () {
    test('an upgrade that breaks the build', () async {
      final r = await run([
        'plan',
        '--flutter',
        '3.47',
        '-p',
        fixture('legacy_groovy'),
        '--flutter-version',
        '3.29.3',
        '--java-version',
        '17',
      ]);
      expect(r.code, ExitCode.problems);
      expect(r.out, contains('Flutter 3.29.3 → 3.47'));
      expect(r.out,
          contains(RegExp(r'AGP\s+8\.11\.1\s+9\.0\.1\s+7\.3\.0\s+✗ fails')));
      expect(r.out, contains('AGP     7.3.0 → 8.11.2'));
      expect(r.out, contains('droid_doctor fix --flutter-version 3.47'));
    });

    test('an upgrade that only warns', () async {
      final r = await run([
        'plan',
        '--flutter',
        'latest',
        '-p',
        fixture('catalog_kts'),
        '--flutter-version',
        '3.38.10',
        '--java-version',
        '17',
      ]);
      expect(r.code, ExitCode.ok);
      expect(r.out, contains('Ready'));
      expect(r.out, contains('3 warnings'));
    });

    test('unknown releases list the known ones', () async {
      final r =
          await run(['plan', '--flutter', '2.0', '-p', fixture('modern_kts')]);
      expect(r.code, ExitCode.usage);
      expect(r.err, contains('Known releases: 3.10'));
    });

    test('--flutter is required', () async {
      expect((await run(['plan', '-p', fixture('modern_kts')])).code,
          ExitCode.usage);
    });
  });

  group('data', () {
    late Directory cache;
    setUp(
        () => cache = Directory.systemTemp.createTempSync('droid_doctor_cli_'));
    tearDown(() => cache.deleteSync(recursive: true));

    final newer = File('data/matrix.json')
        .readAsStringSync()
        .replaceFirst(RegExp(r'"updated": "[^"]+"'), '"updated": "2099-01-01"');

    test('update, then show and check use the download', () async {
      final updated = await run(['data', 'update'],
          cacheDir: cache.path, httpGet: (_) async => newer);
      expect(updated.code, ExitCode.ok);
      expect(updated.out, contains('Updated compatibility data to 2099-01-01'));

      final show = await run(['data', 'show'], cacheDir: cache.path);
      expect(show.out, contains('Updated:  2099-01-01'));
      expect(show.out, contains(cache.path));
    });

    test('network failure', () async {
      final r = await run(['data', 'update'],
          cacheDir: cache.path,
          httpGet: (uri) async => throw const SocketException('offline'));
      expect(r.code, ExitCode.problems);
      expect(r.err, contains('Could not download'));
    });

    test('data from a newer schema asks to upgrade droid_doctor', () async {
      final r = await run(['data', 'update'],
          cacheDir: cache.path, httpGet: (_) async => '{"schemaVersion": 99}');
      expect(r.code, ExitCode.problems);
      expect(r.err, contains('dart pub global activate droid_doctor'));
    });

    test('check notes stale data', () async {
      final r = await run(
        [
          '-p',
          fixture('modern_kts'),
          '--flutter-version',
          '3.47.2',
          '--java-version',
          '17'
        ],
        now: () => DateTime.utc(2027, 1, 1),
      );
      expect(r.code, ExitCode.ok, reason: 'a note, not a failure');
      expect(r.out, contains('days old); run `droid_doctor data update`'));
    });
  });
}
