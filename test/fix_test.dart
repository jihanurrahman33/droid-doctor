import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final matrix = CompatMatrix.bundled();
Version v(String s) => Version.parse(s);

/// Copies a fixture into a fresh temp directory, deleted after the test.
String copyFixture(String name) {
  final dest = Directory.systemTemp.createTempSync('droid_doctor_fix_');
  addTearDown(() => dest.deleteSync(recursive: true));
  final source = Directory(p.join('test', 'fixtures', name));
  for (final entity in source.listSync(recursive: true)) {
    if (entity is! File) continue;
    final target =
        File(p.join(dest.path, p.relative(entity.path, from: source.path)));
    target.parent.createSync(recursive: true);
    entity.copySync(target.path);
  }
  return dest.path;
}

ProjectSnapshot scan(String path,
        {String? flutter = '3.47.2', String java = '17'}) =>
    const AndroidScanner().scan(
      path,
      flutter: flutter == null ? null : Detected(v(flutter)),
      java: Detected(v(java)),
    );

String read(String root, String relative) =>
    File(p.join(root, relative)).readAsStringSync();

void main() {
  group('TextLines', () {
    test('preserves CRLF and the trailing newline', () {
      final text = TextLines.parse('a\r\nb\r\n');
      expect(text.lines, ['a', 'b', '']);
      expect(
        text.apply([
          const ReplaceLine('f', 'r', line: 2, before: 'b', after: 'B'),
          const InsertLines('f', 'r', lines: ['c']),
        ], path: 'f'),
        'a\r\nB\r\nc\r\n',
      );
    });

    test('appends to a file without a trailing newline', () {
      expect(
        TextLines.parse('a').apply([
          const InsertLines('f', 'r', lines: ['b'])
        ], path: 'f'),
        'a\nb',
      );
    });

    test('inserts after a line, applying edits bottom-up', () {
      expect(
        TextLines.parse('x {\ny\n}\n').apply([
          const InsertLines('f', 'r', afterLine: 1, lines: ['  n']),
          const ReplaceLine('f', 'r', line: 2, before: 'y', after: 'Y'),
        ], path: 'f'),
        'x {\n  n\nY\n}\n',
      );
    });

    test('rejects a replace whose line changed', () {
      expect(
        () => TextLines.parse('a\n').apply(
            [const ReplaceLine('f', 'r', line: 1, before: 'z', after: 'y')],
            path: 'f'),
        throwsA(isA<StaleEditException>()),
      );
    });
  });

  group('Solver', () {
    test('minimal picks the smallest upgrades that fix every error', () {
      final solution = Solver(matrix).solve(scan(copyFixture('broken_kts')));
      expect(solution.targets, {
        Component.gradle: v('8.14'),
        Component.agp: v('8.11.1'),
        Component.kgp: v('2.2.20'),
      });
      expect(solution.unresolved, isEmpty);
    });

    test('latest picks what flutter create generates', () {
      final solution = Solver(matrix).solve(
        scan(copyFixture('broken_kts')),
        strategy: Strategy.latest,
      );
      expect(solution.targets, {
        Component.gradle: v('9.3.1'),
        Component.agp: v('9.1.0'),
        Component.kgp: v('2.4.0'),
      });
    });

    test('changes nothing for a healthy project', () {
      final solution = Solver(matrix).solve(scan(copyFixture('modern_kts')));
      expect(solution.targets, isEmpty);
      expect(solution.unresolved, isEmpty);
    });

    test('never downgrades', () {
      // JDK 11 can't run Gradle 9; the fix is a newer JDK, not older Gradle.
      final solution =
          Solver(matrix).solve(scan(copyFixture('modern_kts'), java: '11'));
      expect(solution.targets, isEmpty);
      expect(solution.unresolved.map((f) => f.message).join('\n'),
          contains('Java (JDK) 11'));
    });

    test('solves around an old JDK and reports it as unresolved', () {
      final solution =
          Solver(matrix).solve(scan(copyFixture('legacy_groovy'), java: '11'));
      expect(solution.targets[Component.agp], v('8.11.1'));
      expect(solution.unresolved.map((f) => f.message),
          contains(contains('requires Java (JDK) 17')));
    });

    test('without a Flutter version only compatibility drives upgrades', () {
      final solution =
          Solver(matrix).solve(scan(copyFixture('broken_kts'), flutter: null));
      // AGP 8.7.0 only needs Gradle 8.9. KGP 2.0.20 supports AGP <8.6, so the
      // smallest KGP covering AGP 8.7.0 and Gradle 8.9 is 2.1.0.
      expect(solution.targets[Component.gradle], v('8.9'));
      expect(solution.targets.containsKey(Component.agp), isFalse);
      expect(solution.targets[Component.kgp], v('2.1.0'));
    });
  });

  group('FixPlanner', () {
    test('broken Kotlin DSL project', () {
      final root = copyFixture('broken_kts');
      final plan = FixPlanner(matrix).plan(scan(root));
      expect(plan.manualSteps, isEmpty);
      expect(plan.notes, isEmpty);
      final replaced = {
        for (final e in plan.edits.whereType<ReplaceLine>()) e.after.trim(),
      };
      expect(replaced, {
        'id("com.android.application") version "8.11.1" apply false',
        'id("org.jetbrains.kotlin.android") version "2.2.20" apply false',
        r'distributionUrl=https\://services.gradle.org/distributions/gradle-8.14-all.zip',
        'jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17',
        'minSdk = 23',
      });
      final insert = plan.edits.whereType<InsertLines>().single;
      expect(insert.lines, ['    namespace = "com.example.sample"']);
      expect(insert.afterLine, 7);
    });

    test('legacy Groovy project, latest strategy', () {
      final root = copyFixture('legacy_groovy');
      File(p.join(root, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
            '<manifest xmlns:android="x" package="com.example.legacy">\n</manifest>\n');
      final plan =
          FixPlanner(matrix).plan(scan(root), strategy: Strategy.latest);
      final replaced = {
        for (final e in plan.edits.whereType<ReplaceLine>()) e.after.trim(),
      };
      expect(
          replaced,
          containsAll([
            "ext.kotlin_version = '2.4.0'",
            "classpath 'com.android.tools.build:gradle:9.1.0'",
            'minSdkVersion 24',
          ]));
      final inserts = plan.edits.whereType<InsertLines>().toList();
      expect(
          inserts.map((e) => e.lines.last.trim()),
          containsAll([
            'namespace "com.example.legacy"',
            'android.builtInKotlin=false'
          ]));
      expect(plan.manualSteps.join('\n'),
          allOf(contains('apply from'), contains('package=')));
      expect(plan.notes.single, contains('AGP 9'));
    });

    test('a checksummed wrapper becomes a manual step', () {
      final root = copyFixture('broken_kts');
      final wrapper = File(p.join(
          root, 'android', 'gradle', 'wrapper', 'gradle-wrapper.properties'));
      wrapper.writeAsStringSync(
          '${wrapper.readAsStringSync()}distributionSha256Sum=abc\n');
      final plan = FixPlanner(matrix).plan(scan(root));
      expect(plan.edits.map((e) => e.path),
          isNot(contains(contains('gradle-wrapper.properties'))));
      expect(plan.manualSteps.single, contains('distributionSha256Sum'));
    });

    test('an ambiguous line becomes a manual step instead of a guess', () {
      final root = copyFixture('broken_kts');
      final settings = File(p.join(root, 'android', 'settings.gradle.kts'));
      // Two quoted "8.7.0" on the declaration line: which one is AGP's?
      settings.writeAsStringSync(settings.readAsStringSync().replaceFirst(
          'version "8.7.0" apply false',
          'version "8.7.0" apply false; val pinned = "8.7.0"'));
      final plan = FixPlanner(matrix).plan(scan(root));
      expect(plan.manualSteps.single,
          contains('Android Gradle Plugin 8.7.0 → 8.11.1'));
    });

    test('nothing to do for a healthy project', () {
      expect(FixPlanner(matrix).plan(scan(copyFixture('modern_kts'))).isEmpty,
          isTrue);
    });
  });

  group('FixApplier', () {
    test('apply, then undo restores files byte-for-byte', () {
      final root = copyFixture('broken_kts');
      final before = read(root, 'android/settings.gradle.kts');
      final plan = FixPlanner(matrix).plan(scan(root));
      final applier = FixApplier(root);

      final backup = applier.apply(plan.edits);
      expect(backup, startsWith(backupRoot));
      expect(read(root, 'android/settings.gradle.kts'), contains('8.11.1'));
      expect(Directory(root).listSync(recursive: true).map((e) => e.path),
          isNot(contains(endsWith('.droid_doctor.tmp'))));

      final undo = applier.undo();
      expect(undo.restored, hasLength(3));
      expect(read(root, 'android/settings.gradle.kts'), before);
      expect(applier.undo().restored, isEmpty, reason: 'backup consumed');
    });

    test('undo refuses to clobber files edited after the fix', () {
      final root = copyFixture('broken_kts');
      final applier = FixApplier(root)
        ..apply(FixPlanner(matrix).plan(scan(root)).edits);
      final settings = File(p.join(root, 'android', 'settings.gradle.kts'));
      settings.writeAsStringSync('${settings.readAsStringSync()}// mine\n');

      final refused = applier.undo();
      expect(refused.restored, isEmpty);
      expect(refused.conflicts, [p.join('android', 'settings.gradle.kts')]);

      final forced = applier.undo(force: true);
      expect(forced.restored, hasLength(3));
      expect(settings.readAsStringSync(), contains('"8.7.0"'));
    });

    test('a stale plan writes nothing', () {
      final root = copyFixture('broken_kts');
      final plan = FixPlanner(matrix).plan(scan(root));
      final settings = File(p.join(root, 'android', 'settings.gradle.kts'));
      final edited = settings.readAsStringSync().replaceFirst('8.7.0', '8.8.0');
      settings.writeAsStringSync(edited);
      final wrapper =
          read(root, 'android/gradle/wrapper/gradle-wrapper.properties');

      expect(() => FixApplier(root).apply(plan.edits),
          throwsA(isA<StaleEditException>()));
      expect(settings.readAsStringSync(), edited);
      expect(read(root, 'android/gradle/wrapper/gradle-wrapper.properties'),
          wrapper);
      expect(Directory(p.join(root, backupRoot)).existsSync(), isFalse);
    });

    test('backups never collide', () {
      final root = copyFixture('broken_kts');
      final time = DateTime.utc(2026, 1, 1);
      final applier = FixApplier(root, clock: () => time);
      final a = applier.apply([
        const InsertLines('android/gradle.properties', 'r', lines: ['a=1'])
      ]);
      final b = applier.apply([
        const InsertLines('android/gradle.properties', 'r', lines: ['b=2'])
      ]);
      expect(a, isNot(b));
      applier.undo();
      expect(read(root, 'android/gradle.properties'), contains('a=1'));
      expect(read(root, 'android/gradle.properties'), isNot(contains('b=2')));
    });
  });
}
