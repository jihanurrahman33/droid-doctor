import 'package:droid_doctor/droid_doctor.dart';
import 'package:test/test.dart';

Detected<Version> d(String v, [int line = 1]) =>
    Detected(Version.parse(v), location: SourceLocation('f', line));

ProjectSnapshot project({
  String? flutter = '3.47.2',
  String? java = '17',
  String? gradle = '9.3.1',
  String? agp = '9.1.0',
  String? kgp = '2.4.0',
  bool builtInKotlin = false,
  String? namespace = 'com.example',
  int? minSdk,
  String? javaTarget,
  String? kotlinJvmTarget,
  PluginApplyStyle style = PluginApplyStyle.declarative,
}) =>
    ProjectSnapshot(
      projectPath: '/p',
      dsl: Dsl.kotlin,
      flutter: flutter == null ? null : d(flutter),
      java: java == null ? null : d(java),
      gradle: gradle == null ? null : d(gradle),
      agp: agp == null ? null : d(agp),
      kgp: kgp == null ? null : d(kgp),
      builtInKotlin: builtInKotlin,
      namespace: namespace == null ? null : Detected(namespace),
      minSdk: minSdk == null ? null : Detected(minSdk),
      javaTarget: javaTarget == null ? null : d(javaTarget),
      kotlinJvmTarget: kotlinJvmTarget == null ? null : d(kotlinJvmTarget),
      pluginApplyStyle: style,
      appBuildFile: 'android/app/build.gradle.kts',
    );

final matrix = CompatMatrix.bundled();

List<Finding> check(ProjectSnapshot p) => checkProject(p, matrix);

Iterable<Finding> byRule(List<Finding> f, String id) =>
    f.where((x) => x.ruleId == id);

void main() {
  test('current template has no findings', () {
    expect(check(project()), isEmpty);
  });

  group('compatibility', () {
    test('AGP above Gradle minimum boundary', () {
      final ok =
          check(project(flutter: null, agp: '8.7.0', gradle: '8.9', kgp: null));
      expect(byRule(ok, 'compatibility'), isEmpty);

      final bad =
          check(project(flutter: null, agp: '8.7.0', gradle: '8.8', kgp: null));
      final f = byRule(bad, 'compatibility').single;
      expect(f.severity, Severity.error);
      expect(f.message, contains('requires Gradle 8.9 or newer (found 8.8)'));
      expect(f.fix, contains('gradle-8.9-all.zip'));
    });

    test('JDK too new for Gradle is an error', () {
      final f = check(project(
          flutter: null, java: '21', gradle: '8.3', agp: null, kgp: null));
      expect(
        byRule(f, 'compatibility').map((x) => x.message),
        contains('Java (JDK) 21 requires Gradle 8.4 or newer (found 8.3).'),
      );
    });

    test('Gradle 9 on a pre-17 JDK is an error', () {
      final f = check(project(
          flutter: null, java: '11', gradle: '9.3.1', agp: null, kgp: null));
      final x = byRule(f, 'compatibility').single;
      expect(x.severity, Severity.error);
      expect(x.message, contains('below 9'));
    });

    test('AGP 8 requires JDK 17', () {
      final f = check(project(
          flutter: null, java: '11', gradle: '8.9', agp: '8.7.0', kgp: null));
      expect(byRule(f, 'compatibility').single.message,
          contains('requires Java (JDK) 17'));
    });

    test('KGP older than Gradle supports is only a warning', () {
      final f = check(
          project(flutter: null, gradle: '8.9', agp: '8.7.0', kgp: '1.9.0'));
      final compat = byRule(f, 'compatibility').toList();
      expect(compat, hasLength(2));
      expect(compat.every((x) => x.severity == Severity.warning), isTrue);
      expect(compat.first.fix, startsWith('Upgrade Kotlin Gradle Plugin'));
    });

    test('inclusive max boundary', () {
      // KGP 1.9.20 supports Gradle up to and including 8.1.1.
      final ok = check(
          project(flutter: null, gradle: '8.1.1', agp: null, kgp: '1.9.20'));
      expect(byRule(ok, 'compatibility'), isEmpty);
      final over = check(
          project(flutter: null, gradle: '8.1.2', agp: null, kgp: '1.9.20'));
      expect(byRule(over, 'compatibility'), hasLength(1));
    });
  });

  group('flutter requirements', () {
    test('errors and warnings by threshold', () {
      final f = check(project(gradle: '8.14.3', agp: '8.7.0', kgp: '2.3.20'));
      final reqs = byRule(f, 'flutter-requirements').toList();
      expect(reqs.map((x) => (x.severity, x.message.split(' (').first)), [
        (
          Severity.error,
          'Flutter 3.47 requires Android Gradle Plugin 8.11.1 or newer'
        ),
        (Severity.warning, 'Flutter 3.47 warns on Gradle below 9.1.0'),
      ]);
      expect(reqs.first.fix, contains('9.1.0'), reason: 'suggests template');
    });

    test('minSdk thresholds', () {
      expect(
          byRule(check(project(minSdk: 21)), 'flutter-requirements')
              .single
              .severity,
          Severity.error);
      expect(
          byRule(check(project(minSdk: 23)), 'flutter-requirements')
              .single
              .severity,
          Severity.warning);
      expect(
          byRule(check(project(minSdk: 24)), 'flutter-requirements'), isEmpty);
    });

    test('unknown Flutter release is reported as info', () {
      final f =
          byRule(check(project(flutter: '3.10.0')), 'flutter-requirements');
      expect(f.single.severity, Severity.info);
      expect(f.single.message, contains('3.10'));
    });
  });

  test('versions newer than the data are flagged as info', () {
    final f =
        byRule(check(project(flutter: null, agp: '9.4.0')), 'unknown-version');
    expect(f.single.severity, Severity.info);
  });

  test('missing versions', () {
    final f = byRule(
        check(project(gradle: null, agp: null, kgp: null)), 'missing-version');
    expect(f.map((x) => x.severity),
        [Severity.warning, Severity.warning, Severity.info]);
    final builtIn = byRule(
        check(project(kgp: null, builtInKotlin: true)), 'missing-version');
    expect(builtIn, isEmpty);
  });

  test('missing namespace only matters for AGP 8+', () {
    expect(byRule(check(project(namespace: null)), 'missing-namespace'),
        hasLength(1));
    expect(
        byRule(
            check(project(
                flutter: null,
                java: '11',
                gradle: '7.5',
                agp: '7.4.2',
                kgp: null,
                namespace: null)),
            'missing-namespace'),
        isEmpty);
  });

  test('legacy plugin apply', () {
    final f = byRule(check(project(style: PluginApplyStyle.legacyImperative)),
        'legacy-plugin-apply');
    expect(f.single.severity, Severity.warning);
  });

  group('jvm target', () {
    test('Java/Kotlin mismatch', () {
      final f = byRule(check(project(javaTarget: '17', kotlinJvmTarget: '11')),
          'jvm-target');
      expect(f.single.message, contains('Inconsistent JVM-target'));
    });

    test('JDK older than target', () {
      final f = byRule(
          check(project(
              flutter: null,
              java: '11',
              gradle: '8.9',
              agp: null,
              kgp: null,
              javaTarget: '17',
              kotlinJvmTarget: '17')),
          'jvm-target');
      expect(f.single.message, 'JDK 11 cannot compile for JVM 17.');
    });

    test('matching targets are fine', () {
      expect(
          byRule(check(project(javaTarget: '17', kotlinJvmTarget: '17')),
              'jvm-target'),
          isEmpty);
    });
  });

  test('findings are sorted by severity, stable within a severity', () {
    final f = check(
        project(gradle: '8.14.3', agp: '8.7.0', kgp: '1.9.0', minSdk: 21));
    final severities = f.map((x) => x.severity.index).toList();
    expect(severities, [...severities]..sort());
  });
}
