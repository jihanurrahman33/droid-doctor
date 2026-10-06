import 'dart:convert';
import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'hermetic.dart';

String realLog(String name) =>
    File(p.join('test', 'fixtures', 'logs', '$name.log')).readAsStringSync();

Diagnosis single(String log) {
  final found = explainLog(log);
  expect(found, hasLength(1), reason: found.map((d) => d.id).join(', '));
  return found.single;
}

void main() {
  // Logs captured from real `flutter build apk` runs (Flutter 3.47.2).
  group('real logs', () {
    test('AGP needs newer Gradle', () {
      final d = single(realLog('min_gradle'));
      expect(d.id, 'agp-min-gradle');
      expect(d.title, 'Gradle 8.3 is too old for this Android Gradle Plugin');
      expect(d.fix, contains('gradle-8.9-all.zip'));
      expect(d.fixable, isTrue);
    });

    test('JVM target mismatch names the module from the task path', () {
      final d = single(realLog('jvm_target'));
      expect(d.id, 'jvm-target-mismatch');
      expect(d.title, 'Java targets JVM 17 but Kotlin targets JVM 11');
      expect(d.cause, startsWith('Module :app '));
      expect(d.excerpt, startsWith('Inconsistent JVM-target compatibility'));
    });

    test('missing namespace in a plugin is not auto-fixable', () {
      final d = single(realLog('plugin_namespace'));
      expect(d.title, 'Module :uni_links has no namespace');
      expect(d.fix, startsWith('Upgrade or replace the plugin uni_links;'));
      expect(d.fixable, isFalse, reason: 'fix only edits the app');
    });

    test('missing namespace in the app', () {
      final d = single(realLog('namespace'));
      expect(d.id, 'missing-namespace');
      expect(d.title, 'Module :app has no namespace');
      expect(d.fix, contains('droid_doctor fix'));
    });
  });

  // Error text as printed by Gradle, AGP, Kotlin and Flutter.
  final samples = {
    'class-file-version': (
      'BUG! exception in phase \'semantic analysis\' in source unit '
          "'_BuildScript_' Unsupported class file major version 65",
      'Gradle cannot run on Java 21',
    ),
    'gradle-java-incompatible': (
      'Your build is currently configured to use incompatible Java 21.0.1 '
          'and Gradle 8.3. Cannot sync the project.',
      'Java 21.0.1 and Gradle 8.3 are incompatible',
    ),
    'flutter-gradle-java-incompatible': (
      "Your project's Gradle version is incompatible with the Java version "
          'that Flutter is using for Gradle.',
      "Gradle and Flutter's JDK are incompatible",
    ),
    'gradle-cache-jdk': (
      "Could not open cp_settings generic class cache for settings file '/a/settings.gradle'",
      'Gradle is too old for the JDK',
    ),
    'agp-requires-java': (
      'Android Gradle plugin requires Java 17 to run. You are currently using Java 11.',
      'The Android Gradle Plugin needs Java 17',
    ),
    'manifest-package': (
      'Incorrect package="com.example.app" found in source AndroidManifest.xml: '
          '/a/AndroidManifest.xml.',
      'AndroidManifest.xml still sets package="com.example.app"',
    ),
    'kotlin-metadata': (
      'e: /a/MainActivity.kt: Module was compiled with an incompatible version '
          'of Kotlin. The binary version of its metadata is 1.9.0, expected '
          'version is 1.7.1.',
      'Kotlin Gradle Plugin is too old (needs 1.9.0)',
    ),
    'agp-min-kgp': (
      'The Android Gradle plugin supports only Kotlin Gradle plugin version '
          '1.5.20 and higher.',
      'Kotlin Gradle Plugin must be 1.5.20 or newer',
    ),
    'kotlin-duplicate-class': (
      'Duplicate class kotlin.collections.jdk8.CollectionsJDK8Kt found in '
          'modules kotlin-stdlib-1.8.0 and kotlin-stdlib-jdk8-1.6.21',
      'Duplicate Kotlin standard library classes',
    ),
    'min-sdk-library': (
      'uses-sdk:minSdkVersion 21 cannot be smaller than version 23 declared '
          'in library [:camera_android]',
      'minSdk 21 is lower than :camera_android needs (23)',
    ),
    'compile-sdk-dependency': (
      "Dependency 'androidx.core:core:1.13.0' requires libraries and "
          'applications that\n      depend on it to compile against version '
          '34 or later of the\n      Android APIs.',
      'compileSdk must be 34 or higher',
    ),
    'compile-sdk-plugins': (
      'Your project is configured to compile against Android SDK 33, but the '
          'following plugin(s) require to be compiled against a higher '
          'Android SDK version:',
      'Plugins need a compileSdk higher than 33',
    ),
    'v1-embedding': (
      'Build failed due to use of deleted Android v1 embedding.',
      'The app uses the removed Android v1 embedding',
    ),
    'sdk-location': (
      'SDK location not found. Define a valid SDK location with an '
          'ANDROID_HOME environment variable',
      'Android SDK not found',
    ),
    'sdk-licenses': (
      'Failed to install the following Android SDK packages as some licences '
          'have not been accepted. You have not accepted the license '
          'agreements of the following SDK components:',
      'Android SDK licenses not accepted',
    ),
    'ndk': (
      'No version of NDK matched the requested version 27.0.12077973',
      'NDK 27.0.12077973 is not installed',
    ),
    'out-of-memory': (
      'Execution failed for task \':app:mergeDexDebug\'.\n> java.lang.OutOfMemoryError: Java heap space',
      'Gradle ran out of memory',
    ),
    'plugin-not-found': (
      "Plugin [id: 'com.android.application', version: '8.99.0', "
          "apply: false] was not found in any of the following sources:",
      'Gradle plugin com.android.application not found',
    ),
    'jcenter': (
      'Could not GET https://jcenter.bintray.com/com/x/1.0/x-1.0.pom',
      'The build still uses JCenter',
    ),
    'dependency-not-found': (
      'Could not find com.example:missing-lib:1.2.3.',
      'Dependency com.example:missing-lib:1.2.3 not found',
    ),
  };

  group('patterns', () {
    for (final MapEntry(key: id, value: (text, title)) in samples.entries) {
      test(id, () {
        final d = single(text);
        expect(d.id, id);
        expect(d.title, title);
        expect(d.cause, isNotEmpty);
        expect(d.fix, isNotEmpty);
      });
    }

    test('every pattern has a sample', () {
      final tested = {
        ...samples.keys,
        'agp-min-gradle',
        'jvm-target-mismatch',
        'missing-namespace'
      };
      expect(errorPatterns.map((p) => p.id).toSet(), tested);
    });
  });

  test('plugin namespace errors point at the plugin', () {
    final d = single('''
FAILURE: Build failed with an exception.
* What went wrong:
A problem occurred configuring project ':flutter_old_plugin'.
> Could not create an instance of type com.android.build.api.variant.impl.LibraryVariantBuilderImpl.
   > Namespace not specified. Specify a namespace in the module's build file.
''');
    expect(d.title, 'Module :flutter_old_plugin has no namespace');
    expect(d.fix, contains('droid_doctor plugins'));
    expect(d.fixable, isFalse);
  });

  test('strips ANSI codes, dedupes repeats, sorts by line', () {
    final found = explainLog('noise\n'
        '\x1B[31mCould not find com.a:b:1.0.\x1B[0m\n'
        'Minimum supported Gradle version is 8.9. Current version is 8.3.\n'
        'Could not find com.a:b:1.0.\n');
    expect(found.map((d) => (d.id, d.line)), [
      ('dependency-not-found', 2),
      ('agp-min-gradle', 3),
    ]);
    expect(found.first.excerpt, 'Could not find com.a:b:1.0.');
  });

  test('unknown logs produce nothing', () {
    expect(explainLog('BUILD SUCCESSFUL in 3s'), isEmpty);
  });

  group('CLI', () {
    Future<({int code, String out, String err})> run(
      List<String> args, {
      String? stdinText,
    }) async {
      final out = StringBuffer(), err = StringBuffer();
      final code = await runDroidDoctor(
        cacheDir: hermeticCacheDir,
        now: hermeticNow,
        args,
        out: out,
        err: err,
        stdinIsTerminal: stdinText == null,
        readStdin: () async => stdinText ?? '',
      );
      return (code: code, out: out.toString(), err: err.toString());
    }

    test('explains a log file', () async {
      final r = await run(
          ['explain', p.join('test', 'fixtures', 'logs', 'min_gradle.log')]);
      expect(r.code, ExitCode.ok);
      expect(r.out, contains('1. Gradle 8.3 is too old'));
      expect(r.out, contains('auto:  droid_doctor fix'));
    });

    test('reads stdin with -', () async {
      final r = await run(['explain', '-', '--json'],
          stdinText: realLog('namespace'));
      final json = jsonDecode(r.out) as Map<String, Object?>;
      expect((json['diagnoses'] as List).single,
          containsPair('id', 'missing-namespace'));
      expect(json['source'], 'stdin');
    });

    test('nothing recognized exits 1', () async {
      final r = await run(['explain', '-'], stdinText: 'all good');
      expect(r.code, ExitCode.problems);
      expect(r.out, contains('No known error'));
    });

    test('usage errors', () async {
      expect((await run(['explain'])).code, ExitCode.usage,
          reason: 'no file and nothing piped');
      expect((await run(['explain', 'missing.log'])).err,
          contains('Log file not found'));
    });
  });
}
