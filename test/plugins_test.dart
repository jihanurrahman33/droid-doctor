import 'dart:convert';
import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fix_test.dart' show copyFixture;

const oldPlugin = '''
group 'com.example.old_plugin'
version '1.0'

buildscript {
    repositories {
        google()
        jcenter()
    }
}

apply plugin: 'com.android.library'
apply plugin: 'kotlin-android'

android {
    compileSdkVersion 37

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    defaultConfig {
        minSdkVersion 26
    }
}
''';

const goodPlugin = '''
apply plugin: 'com.android.library'
apply plugin: 'kotlin-android'

android {
    if (project.android.hasProperty("namespace")) {
        namespace 'com.example.good_plugin'
    }
    compileSdk 34

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = '17'
    }
    defaultConfig {
        minSdk 21
    }
}
''';

const mismatchedPlugin = '''
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.mismatched"
    compileOptions {
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}
''';

/// A copy of [fixture] with a resolved package_config pointing into a fake
/// pub cache.
String projectWithPlugins(String fixture, {bool builtInKotlin = false}) {
  final root = copyFixture(fixture);
  final cache = p.join(root, 'pub_cache', 'hosted', 'pub.dev');
  void package(String dir, {String? buildFile, String? content}) {
    Directory(p.join(cache, dir, 'lib')).createSync(recursive: true);
    if (buildFile != null) {
      File(p.join(cache, dir, 'android', buildFile))
        ..createSync(recursive: true)
        ..writeAsStringSync(content!);
    }
  }

  package('old_plugin-1.0.0', buildFile: 'build.gradle', content: oldPlugin);
  package('good_plugin-2.0.0', buildFile: 'build.gradle', content: goodPlugin);
  package('mismatched-0.3.1+2',
      buildFile: 'build.gradle.kts', content: mismatchedPlugin);
  package('pure_dart-1.0.0');
  final local = Directory(p.join(root, 'local_plugin', 'android'))
    ..createSync(recursive: true);
  File(p.join(local.path, 'build.gradle.kts'))
      .writeAsStringSync('android {\n    namespace = "com.example.local"\n}\n');

  String entry(String name, String rootUri) =>
      jsonEncode({'name': name, 'rootUri': rootUri, 'packageUri': 'lib/'});
  File(p.join(root, '.dart_tool', 'package_config.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    ${entry('old_plugin', Uri.directory(p.join(cache, 'old_plugin-1.0.0')).toString())},
    ${entry('good_plugin', '../pub_cache/hosted/pub.dev/good_plugin-2.0.0/')},
    ${entry('mismatched', '../pub_cache/hosted/pub.dev/mismatched-0.3.1+2/')},
    ${entry('pure_dart', '../pub_cache/hosted/pub.dev/pure_dart-1.0.0/')},
    ${entry('local_plugin', '../local_plugin/')},
    ${entry('app', '../')}
  ]
}
''');
  if (builtInKotlin) {
    File(p.join(root, 'android', 'gradle.properties'))
        .writeAsStringSync('android.builtInKotlin=true\n');
  }
  return root;
}

ProjectSnapshot scan(String root) => const AndroidScanner().scan(
      root,
      flutter: Detected(Version.parse('3.47.2')),
      java: Detected(Version.parse('17')),
    );

Map<String, List<String>> audit(String root) {
  final project = scan(root);
  final auditor = PluginAuditor(project, CompatMatrix.bundled());
  return {
    for (final plugin in findAndroidPlugins(root))
      plugin.name: [for (final f in auditor.audit(plugin)) f.ruleId],
  };
}

void main() {
  test('finds Android plugins with versions from the pub cache layout', () {
    final plugins = findAndroidPlugins(projectWithPlugins('modern_kts'));
    expect(
      [for (final p in plugins) '${p.name}@${p.version}'],
      [
        'good_plugin@2.0.0',
        'local_plugin@null',
        'mismatched@0.3.1+2',
        'old_plugin@1.0.0',
      ],
      reason: 'pure Dart packages and the app itself are skipped',
    );
  });

  test('audits plugins against the app', () {
    expect(audit(projectWithPlugins('modern_kts')), {
      'good_plugin': <String>[],
      'local_plugin': <String>[],
      'mismatched': ['plugin-jvm-target'],
      'old_plugin': [
        'plugin-namespace',
        'plugin-min-sdk',
        'plugin-compile-sdk',
        'plugin-jvm-target',
        'plugin-jcenter',
      ],
    });
  });

  test('effective app SDKs come from flutter.* defaults when delegated', () {
    final auditor = PluginAuditor(
        scan(projectWithPlugins('modern_kts')), CompatMatrix.bundled());
    expect(auditor.appMinSdk, 24);
    expect(auditor.appCompileSdk, 36);
  });

  test('namespace is only required from AGP 8', () {
    final findings = audit(projectWithPlugins('legacy_groovy'));
    expect(findings['old_plugin'], isNot(contains('plugin-namespace')));
    expect(findings['old_plugin'], contains('plugin-min-sdk'),
        reason: 'legacy app has minSdkVersion 21');
  });

  test('flags Kotlin plugins under AGP built-in Kotlin', () {
    final findings =
        audit(projectWithPlugins('modern_kts', builtInKotlin: true));
    expect(findings['good_plugin'], ['plugin-built-in-kotlin']);
  });

  test('missing package_config asks for pub get', () {
    expect(() => findAndroidPlugins(copyFixture('modern_kts')),
        throwsA(isA<PackagesNotResolvedException>()));
  });

  group('CLI', () {
    Future<({int code, String out, String err, List<String> lookups})> run(
        List<String> args) async {
      final out = StringBuffer(), err = StringBuffer(), lookups = <String>[];
      final code = await runDroidDoctor(
        args,
        out: out,
        err: err,
        probe: EnvironmentProbe(
            run: (exe, a) => throw StateError('unexpected process $exe')),
        packageInfo: (name) async {
          lookups.add(name);
          return name == 'old_plugin'
              ? const PackageInfo(latestVersion: '3.0.0')
              : const PackageInfo(latestVersion: '0.3.1+2');
        },
      );
      return (
        code: code,
        out: out.toString(),
        err: err.toString(),
        lookups: lookups
      );
    }

    const pinned = ['--flutter-version', '3.47.2', '--java-version', '17'];

    test('reports problem plugins with upgrade hints', () async {
      final r = await run(
          ['plugins', '-p', projectWithPlugins('modern_kts'), ...pinned]);
      expect(r.code, ExitCode.problems);
      expect(r.lookups..sort(), ['mismatched', 'old_plugin'],
          reason: 'only plugins with findings are looked up');
      expect(r.out, contains('old_plugin 1.0.0  → 3.0.0 available'));
      expect(r.out, contains('mismatched 0.3.1+2  (latest)'));
      expect(r.out, contains('fix: Upgrade old_plugin to 3.0.0'));
      expect(r.out, contains('fix: No newer mismatched release on pub.dev'));
      expect(r.out, isNot(contains('good_plugin')));
      expect(
          r.out,
          contains(
              '4 Android plugins checked: 1 with errors, 1 with warnings, 2 OK.'));
    });

    test('--offline and --json', () async {
      final r = await run([
        'plugins',
        '-p',
        projectWithPlugins('modern_kts'),
        '--offline',
        '--json',
        ...pinned
      ]);
      expect(r.lookups, isEmpty);
      final json = jsonDecode(r.out) as Map<String, Object?>;
      expect(json['summary'], {'checked': 4, 'errors': 1, 'warnings': 1});
    });

    test('unresolved packages is a usage error', () async {
      final r =
          await run(['plugins', '-p', copyFixture('modern_kts'), ...pinned]);
      expect(r.code, ExitCode.usage);
      expect(r.err, contains('flutter pub get'));
    });
  });

  group('pub.dev advice', () {
    final plugin = AndroidPlugin(
        name: 'uni_links', rootPath: '/x', buildFile: '/x', version: '0.5.1');
    final upgrade = Finding(
      ruleId: 'plugin-namespace',
      severity: Severity.error,
      message: 'm',
      fix: PluginAuditor.upgradeFix(plugin),
    );
    const other = Finding(
        ruleId: 'plugin-min-sdk',
        severity: Severity.error,
        message: 'm',
        fix: 'raise');

    test('discontinued plugins get their replacement', () {
      final r = PluginReport(plugin, [upgrade, other],
          info: const PackageInfo(
              latestVersion: '0.5.1',
              isDiscontinued: true,
              replacedBy: 'app_links'));
      expect(r.findings.map((f) => f.fix),
          ['uni_links is discontinued; replace it with app_links.', 'raise']);
      expect(r.toJson(), containsPair('replacedBy', 'app_links'));
    });

    test('without lookup the generic fix stays', () {
      expect(PluginReport(plugin, [upgrade]).findings.single.fix,
          PluginAuditor.upgradeFix(plugin));
    });

    test('parses the pub.dev response', () {
      // Shape of https://pub.dev/api/packages/uni_links (trimmed).
      final info = parsePackageInfo(jsonDecode(
          '{"name":"uni_links","isDiscontinued":true,"replacedBy":"app_links",'
          '"latest":{"version":"0.5.1"}}'))!;
      expect(info.latestVersion, '0.5.1');
      expect(info.isDiscontinued, isTrue);
      expect(info.replacedBy, 'app_links');
      expect(parsePackageInfo({'error': 'not found'}), isNull);
    });
  });
}
