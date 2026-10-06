import 'package:droid_doctor/src/detect/source_text.dart';
import 'package:droid_doctor/src/detect/version_catalog.dart';
import 'package:test/test.dart';

void main() {
  group('maskComments', () {
    test('blanks line and block comments, preserving offsets', () {
      const source = 'a // x\nb /* y\nz */ c';
      final masked = maskComments(source);
      expect(masked.length, source.length);
      expect(masked, 'a     \nb     \n     c');
    });

    test('keeps comment markers inside strings', () {
      const source = 'url "https://example.com" // gone\n'
          "x 'a//b' \"\"\"multi // line\"\"\"";
      expect(
        maskComments(source),
        'url "https://example.com"        \n'
        "x 'a//b' \"\"\"multi // line\"\"\"",
      );
    });

    test('handles escaped quotes and unterminated block comments', () {
      expect(maskComments(r'"a\"//b" /* open'), r'"a\"//b"        ');
    });
  });

  group('SourceText', () {
    test('ignores commented-out declarations and reports lines', () {
      final text = SourceText('build.gradle', '''
// id("com.android.application") version "1.0.0"
id("com.android.application") version "8.7.0"
''');
      final found = text.find([RegExp(r'version "([^"]+)"')]);
      expect(found!.value, '8.7.0');
      expect(found.location.toString(), 'build.gradle:2');
    });

    test('resolves \$variable references', () {
      final text = SourceText('build.gradle', '''
ext.kotlin_version = '1.7.10'
val agpVersion = "8.7.0"
classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:\$kotlin_version"
''');
      final kgp = text.resolve((
        value: r'$kotlin_version',
        location: text.locationOf(0),
      ));
      expect(kgp!.value, '1.7.10');
      expect(kgp.location.line, 1);
      expect(
        text.resolve(
            (value: r'${agpVersion}', location: text.locationOf(0)))!.value,
        '8.7.0',
      );
      expect(
        text.resolve((value: r'$missing', location: text.locationOf(0))),
        isNull,
      );
    });

    test('does not mask .properties files', () {
      final text = SourceText('gradle-wrapper.properties',
          r'distributionUrl=https\://services.gradle.org/distributions/gradle-8.9-all.zip');
      expect(text.masked, contains('gradle-8.9-all.zip'));
    });
  });

  group('VersionCatalog', () {
    test('resolves version.ref, literal, inline-table ref and short forms', () {
      final catalog = VersionCatalog.parse('libs.versions.toml', '''
[versions]
agp = "8.11.1"
kotlin = "2.2.20"

[plugins]
# comment
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android = { id = "org.jetbrains.kotlin.android", version = { ref = "kotlin" } }
other = { id = "com.example.other", version = "1.2.3" }
short = "com.example.short:4.5.6"
''');
      final agp = catalog.pluginVersion('com.android.application')!;
      expect(agp.value, '8.11.1');
      expect(agp.location.line, 2, reason: 'points at the [versions] entry');
      expect(catalog.pluginVersion('org.jetbrains.kotlin.android')!.value,
          '2.2.20');
      expect(catalog.pluginVersion('com.example.other')!.value, '1.2.3');
      expect(catalog.pluginVersion('com.example.short')!.value, '4.5.6');
      expect(catalog.pluginVersion('missing'), isNull);
    });
  });
}
