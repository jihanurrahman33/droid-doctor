import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

ProjectSnapshot scan(String fixture) =>
    const AndroidScanner().scan(p.join('test', 'fixtures', fixture));

void main() {
  test('modern Kotlin DSL template (flutter create 3.47)', () {
    final s = scan('modern_kts');
    expect(s.dsl, Dsl.kotlin);
    expect(s.gradle!.value, Version.parse('9.3.1'));
    expect(s.gradle!.location.toString(),
        p.join('android', 'gradle', 'wrapper', 'gradle-wrapper.properties:5'));
    expect(s.agp!.value, Version.parse('9.1.0'));
    expect(s.agp!.location.toString(),
        p.join('android', 'settings.gradle.kts:22'));
    expect(s.kgp!.value, Version.parse('2.4.0'));
    expect(s.pluginApplyStyle, PluginApplyStyle.declarative);
    expect(s.builtInKotlin, isFalse);
    expect(s.namespace!.value, 'com.example.sample');
    expect(s.compileSdk, isNull, reason: 'delegated to flutter.*');
    expect(s.minSdk, isNull, reason: 'delegated to flutter.*');
    expect(s.javaTarget!.value, Version.parse('17'));
    expect(s.kotlinJvmTarget!.value, Version.parse('17'));
    expect(s.appBuildFile, p.join('android', 'app', 'build.gradle.kts'));
  });

  test('legacy Groovy project with buildscript classpath and ext vars', () {
    final s = scan('legacy_groovy');
    expect(s.dsl, Dsl.groovy);
    expect(s.gradle!.value, Version.parse('7.5'));
    expect(s.agp!.value, Version.parse('7.3.0'));
    expect(s.kgp!.value, Version.parse('1.7.10'),
        reason: 'commented-out 1.5.31 must be ignored');
    expect(s.kgp!.location!.line, 3);
    expect(s.pluginApplyStyle, PluginApplyStyle.legacyImperative);
    expect(s.namespace, isNull);
    expect(s.compileSdk!.value, 33);
    expect(s.minSdk!.value, 21);
    expect(s.javaTarget!.value, Version.parse('8'));
    expect(s.kotlinJvmTarget!.value, Version.parse('8'));
  });

  test('version catalog', () {
    final s = scan('catalog_kts');
    expect(s.agp!.value, Version.parse('8.11.1'));
    expect(s.agp!.location.toString(),
        p.join('android', 'gradle', 'libs.versions.toml:3'));
    expect(s.kgp!.value, Version.parse('2.2.20'));
    expect(s.gradle!.value, Version.parse('8.14.3'));
  });

  test('accepts the android/ directory itself', () {
    final s = const AndroidScanner()
        .scan(p.join('test', 'fixtures', 'modern_kts', 'android'));
    expect(s.agp!.value, Version.parse('9.1.0'));
    expect(p.basename(s.projectPath), 'modern_kts');
  });

  test('passes environment values through', () {
    final s = const AndroidScanner().scan(
      p.join('test', 'fixtures', 'modern_kts'),
      flutter: Detected(Version.parse('3.47.2'), origin: 'test'),
      java: Detected(Version.parse('17'), origin: 'test'),
    );
    expect(s.flutter!.value, Version.parse('3.47.2'));
    expect(s.java!.value, Version.parse('17'));
  });

  test('throws for a directory without an Android project', () {
    final empty = Directory.systemTemp.createTempSync('droid_doctor_');
    addTearDown(() => empty.deleteSync(recursive: true));
    expect(() => const AndroidScanner().scan(empty.path),
        throwsA(isA<ProjectNotFoundException>()));
  });

  test('detects AGP 9 built-in Kotlin and Groovy plugin syntax', () {
    final dir = Directory.systemTemp.createTempSync('droid_doctor_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final android = Directory(p.join(dir.path, 'android'))..createSync();
    File(p.join(android.path, 'settings.gradle')).writeAsStringSync('''
plugins {
    id "dev.flutter.flutter-plugin-loader" version "1.0.0"
    id "com.android.application" version "9.1.0" apply false
}
''');
    File(p.join(android.path, 'gradle.properties'))
        .writeAsStringSync('android.builtInKotlin=true\n');
    final s = const AndroidScanner().scan(dir.path);
    expect(s.agp!.value, Version.parse('9.1.0'));
    expect(s.kgp, isNull);
    expect(s.builtInKotlin, isTrue);
    expect(s.gradle, isNull);
  });
}
