import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:test/test.dart';

/// A fake process runner keyed by "executable arg1 arg2".
ProcessRunner fakeRun(Map<String, (int, String, String)> responses,
        {List<String>? calls}) =>
    (executable, arguments) async {
      final key = [executable, ...arguments].join(' ');
      calls?.add(key);
      final response = responses[key];
      if (response == null) throw ProcessException(executable, arguments);
      return ProcessResult(0, response.$1, response.$2, response.$3);
    };

const javaHome = '/jdk/home';
const studioJbr = '/Applications/Android Studio.app/Contents/jbr/Contents/Home';

void main() {
  group('flutterVersion', () {
    test('parses JSON surrounded by banners', () async {
      final probe = EnvironmentProbe(
        run: fakeRun({
          'flutter --version --machine': (
            0,
            'A new version is available!\n{"frameworkVersion": "3.47.2"}\n',
            ''
          ),
        }),
      );
      final v = await probe.flutterVersion();
      expect(v!.value, Version.parse('3.47.2'));
      expect(probe.notes, isEmpty);
    });

    test('adds a note when flutter is missing', () async {
      final probe = EnvironmentProbe(run: fakeRun({}));
      expect(await probe.flutterVersion(), isNull);
      expect(probe.notes.single, contains('--flutter-version'));
    });
  });

  group('java', () {
    test('prefers flutter config --jdk-dir', () async {
      final probe = EnvironmentProbe(
        operatingSystem: 'macos',
        environment: {'JAVA_HOME': '/other'},
        fileExists: (_) => true,
        run: fakeRun({
          'flutter config --machine': (0, '{"jdk-dir": "$javaHome"}', ''),
          '$javaHome/bin/java -version': (
            0,
            '',
            'openjdk version "17.0.20" 2026-07-21'
          ),
        }),
      );
      final java = await probe.java();
      expect(java!.value, Version.parse('17.0.20'));
      expect(java.origin, contains('jdk-dir'));
    });

    test('falls back to the Android Studio JBR, then JAVA_HOME', () async {
      final calls = <String>[];
      final probe = EnvironmentProbe(
        operatingSystem: 'macos',
        environment: {'JAVA_HOME': javaHome},
        fileExists: (path) => path == '$javaHome/bin/java',
        run: fakeRun({
          'flutter config --machine': (0, '{}', ''),
          '$javaHome/bin/java -version': (0, '', 'java version "1.8.0_392"'),
        }, calls: calls),
      );
      final java = await probe.java();
      expect(java!.value, Version.parse('8'));
      expect(java.origin, 'JAVA_HOME ($javaHome)');
    });

    test('uses the Android Studio JBR when present', () async {
      final probe = EnvironmentProbe(
        operatingSystem: 'macos',
        environment: {},
        fileExists: (path) => path == '$studioJbr/bin/java',
        run: fakeRun({
          'flutter config --machine': (0, '{}', ''),
          '$studioJbr/bin/java -version': (0, '', 'openjdk version "21.0.4"'),
        }),
      );
      expect((await probe.java())!.origin, startsWith('Android Studio JBR'));
    });

    test('falls back to java on PATH, then gives up with a note', () async {
      final onPath = EnvironmentProbe(
        environment: {},
        fileExists: (_) => false,
        run: fakeRun({'java -version': (0, '', 'openjdk version "11.0.2"')}),
      );
      expect((await onPath.java())!.value, Version.parse('11.0.2'));

      final none = EnvironmentProbe(
          environment: {}, fileExists: (_) => false, run: fakeRun({}));
      expect(await none.java(), isNull);
      expect(none.notes.single, contains('--java-version'));
    });
  });
}
