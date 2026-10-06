import 'dart:convert';
import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:test/test.dart';

import '../tool/src/flutter_requirements.dart';
import '../tool/src/matrix_format.dart';
import '../tool/src/releases.dart';

void main() {
  group('latestStablePerMinor', () {
    test('keeps the latest stable patch per minor, skipping non-releases', () {
      expect(
        latestStablePerMinor([
          '3.0.5',
          '3.1.0',
          '3.10.5',
          '3.10.6',
          '3.12.0',
          '3.13.0',
          '3.13.9',
          '3.47.0',
          '3.47.6',
          '3.48.0-0.5.pre',
          'v1.0.0',
          '3.49.0',
        ]),
        ['3.10.6', '3.13.9', '3.47.6', '3.49.0'],
        reason: '3.1.0 and 3.12.0 were never stable; 3.49.0 is the newest',
      );
    });
  });

  group('extractFlutterRequirements', () {
    // File contents in the shapes Flutter has used (3.22 and 3.35+).
    final files = {
      '3.22.3:packages/flutter_tools/lib/src/android/gradle_utils.dart': '''
const String templateDefaultGradleVersion = '7.6.3';
const String templateAndroidGradlePluginVersion = '7.3.0';
const String templateKotlinGradlePluginVersion = '1.7.10';
''',
      '3.22.3:packages/flutter_tools/gradle/src/main/groovy/flutter.groovy': '''
    public final int compileSdkVersion = 34
    public  final int minSdkVersion = 21
''',
      '3.22.3:packages/flutter_tools/gradle/src/main/kotlin/dependency_version_checker.gradle.kts':
          '''
        val warnGradleVersion: Version = Version(7, 0, 2)
        val errorGradleVersion: Version = Version(0, 0, 0)
        val warnJavaVersion: JavaVersion = JavaVersion.VERSION_11
        val errorJavaVersion: JavaVersion = JavaVersion.VERSION_1_1
        val warnAGPVersion: Version = Version(7, 0, 0)
        val errorAGPVersion: Version = Version(0, 0, 0)
''',
      '3.47.6:packages/flutter_tools/lib/src/android/gradle_utils.dart': '''
const templateDefaultGradleVersion = '9.3.1';
const templateAndroidGradlePluginVersion = '9.1.0';
const templateKotlinGradlePluginVersion = '2.4.0';
''',
      '3.47.6:packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt':
          '''
    val compileSdkVersion: Int = 36
    val minSdkVersion: Int = 24
''',
      '3.47.6:packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt':
          '''
    @VisibleForTesting internal val warnGradleVersion: Version = Version(9, 1, 0)
    @VisibleForTesting internal val errorGradleVersion: Version = Version(8, 14, 0)
    @VisibleForTesting internal val warnJavaVersion: JavaVersion = JavaVersion.VERSION_17
    @VisibleForTesting internal val errorJavaVersion: JavaVersion = JavaVersion.VERSION_17
    @VisibleForTesting internal val warnAGPVersion: AndroidPluginVersion = AndroidPluginVersion(9, 0, 1)
    @VisibleForTesting internal val errorAGPVersion: AndroidPluginVersion = AndroidPluginVersion(8, 11, 1)
    @VisibleForTesting internal val warnKGPVersion: Version = Version(2, 3, 20)
    @VisibleForTesting internal val errorKGPVersion: Version = Version(2, 2, 20)
    internal val warnMinSdkVersion: Int = 24
    internal val errorMinSdkVersion: Int = 23
''',
    };
    Future<String?> read(String tag, String path) async => files['$tag:$path'];

    test('current layout', () async {
      expect(await extractFlutterRequirements('3.47.6', read), {
        'version': '3.47',
        'tag': '3.47.6',
        'error': {
          'java': '17',
          'gradle': '8.14.0',
          'agp': '8.11.1',
          'kgp': '2.2.20',
          'minSdk': 23
        },
        'warn': {
          'java': '17',
          'gradle': '9.1.0',
          'agp': '9.0.1',
          'kgp': '2.3.20',
          'minSdk': 24
        },
        'template': {
          'gradle': '9.3.1',
          'agp': '9.1.0',
          'kgp': '2.4.0',
          'compileSdk': 36,
          'minSdk': 24
        },
      });
    });

    test('older layout, with "no minimum" sentinels skipped', () async {
      final entry = (await extractFlutterRequirements('3.22.3', read))!;
      expect(entry['error'], isEmpty);
      expect(entry['warn'], {'java': '11', 'gradle': '7.0.2', 'agp': '7.0.0'});
      expect(entry['template'], {
        'gradle': '7.6.3',
        'agp': '7.3.0',
        'kgp': '1.7.10',
        'compileSdk': 34,
        'minSdk': 21
      });
    });

    test('missing templates means no entry', () async {
      expect(await extractFlutterRequirements('3.0.5', read), isNull);
    });

    test('the extracted 3.47 entry matches the bundled data', () async {
      final bundled =
          CompatMatrix.bundled().requirementsFor(Version.parse('3.47'))!;
      final entry = (await extractFlutterRequirements('3.47.6', read))!;
      final error = entry['error'] as Map<String, Object?>;
      expect(bundled.errorBelow[Component.agp],
          Version.parse(error['agp'] as String));
      expect(bundled.errorMinSdkBelow, error['minSdk']);
    });
  });

  group('release lists', () {
    test('Gradle: only final, unbroken releases', () {
      final json = jsonEncode([
        {'version': '9.8.1-20261006035232+0000', 'snapshot': true},
        {
          'version': '9.8.0',
          'snapshot': false,
          'rcFor': '',
          'milestoneFor': ''
        },
        {'version': '9.8.0-rc-1', 'rcFor': '9.8.0', 'milestoneFor': ''},
        {'version': '9.7.0', 'broken': true, 'rcFor': '', 'milestoneFor': ''},
        {'version': '8.14', 'rcFor': '', 'milestoneFor': ''},
      ]);
      expect(parseGradleVersions(json), ['9.8.0', '8.14']);
    });

    test('Maven metadata: stable versions only', () {
      expect(
        parseMavenMetadata('<versions><version>9.5.0-alpha08</version>'
            '<version>9.4.1</version><version>2.4.20-RC</version></versions>'),
        ['9.4.1'],
      );
    });

    test('condenses to the newest patch per line', () {
      expect(
        condenseReleases(['6.9', '8.14', '8.14.5', '8.14.3', '9.0.0', '8.9'],
            floor: '7.0'),
        ['8.9', '8.14.5', '9.0.0'],
      );
    });

    test('Kotlin lines split x.y.0 from x.y.20 tooling releases', () {
      expect(
        condenseReleases(['2.2.0', '2.2.10', '2.2.20', '2.2.21', '2.3.0'],
            floor: '1.7.0', kotlinStyle: true),
        ['2.2.0', '2.2.10', '2.2.21', '2.3.0'],
      );
    });
  });

  test('formatMatrix round-trips the bundled data', () {
    final source = File('data/matrix.json').readAsStringSync();
    final json = jsonDecode(source) as Map<String, Object?>;
    expect(formatMatrix(json), source,
        reason: 'data/matrix.json must stay in the pipeline\'s format');
  });

  group('MatrixStore', () {
    late Directory dir;
    setUp(
        () => dir = Directory.systemTemp.createTempSync('droid_doctor_store_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String withDate(String date) => File('data/matrix.json')
        .readAsStringSync()
        .replaceFirst(RegExp(r'"updated": "[^"]+"'), '"updated": "$date"');

    test('uses the bundled data without a download', () {
      expect(MatrixStore(dir.path).load().source, 'bundled');
    });

    test('update caches newer data and load prefers it', () async {
      final store = MatrixStore(dir.path);
      final (status, matrix) = await store.update((uri) async {
        expect(uri, remoteMatrixUri);
        return withDate('2099-01-01');
      });
      expect(status, UpdateStatus.updated);
      expect(matrix.updated, '2099-01-01');
      expect(store.load().matrix.updated, '2099-01-01');

      final (again, _) =
          await store.update((_) async => withDate('2099-01-01'));
      expect(again, UpdateStatus.upToDate);
    });

    test('older downloads are not cached', () async {
      final store = MatrixStore(dir.path);
      final (status, _) =
          await store.update((_) async => withDate('2000-01-01'));
      expect(status, UpdateStatus.upToDate);
      expect(store.cacheFile.existsSync(), isFalse);
    });

    test('unreadable data is never written, and a bad cache is ignored',
        () async {
      final store = MatrixStore(dir.path);
      await expectLater(
        store.update((_) async => '{"schemaVersion": 2}'),
        throwsA(isA<FormatException>()),
      );
      expect(store.cacheFile.existsSync(), isFalse);

      store.cacheFile.writeAsStringSync('not json');
      final loaded = store.load();
      expect(loaded.source, 'bundled');
      expect(loaded.note, contains('Ignoring downloaded data'));
    });
  });

  test('staleness note after 30 days', () {
    final matrix = CompatMatrix.bundled();
    final updated = DateTime.parse(matrix.updated);
    expect(
        stalenessNote(matrix, updated.add(const Duration(days: 30))), isNull);
    expect(stalenessNote(matrix, updated.add(const Duration(days: 45))),
        contains('45 days old'));
  });

  test('defaultCacheDir', () {
    expect(defaultCacheDir({'DROID_DOCTOR_CACHE': '/c'}, 'linux'), '/c');
    expect(
        defaultCacheDir({'XDG_CACHE_HOME': '/x'}, 'linux'), '/x/droid_doctor');
    expect(defaultCacheDir({'HOME': '/h'}, 'macos'), '/h/.cache/droid_doctor');
    expect(
        defaultCacheDir(
            {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'}, 'windows'),
        r'C:\Users\u\AppData\Local\droid_doctor');
  });
}
