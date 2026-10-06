import '../data/compat_matrix.dart';
import '../model/finding.dart';
import '../model/project_snapshot.dart';
import '../model/version.dart';
import 'rule.dart';

/// Flags the deprecated `apply from: flutter.gradle` style.
final class LegacyPluginApplyRule implements Rule {
  const LegacyPluginApplyRule();

  @override
  String get id => 'legacy-plugin-apply';

  @override
  Iterable<Finding> check(ProjectSnapshot project, CompatMatrix matrix) sync* {
    if (project.pluginApplyStyle != PluginApplyStyle.legacyImperative) return;
    yield Finding(
      ruleId: id,
      severity: Severity.warning,
      message: "Flutter's Gradle plugin is applied with the deprecated "
          '`apply from: flutter.gradle` style.',
      fix: 'Migrate to the declarative plugins {} block.',
      location: project.appBuildFile == null
          ? null
          : SourceLocation(project.appBuildFile!, 1),
      reference: 'https://docs.flutter.dev/release/breaking-changes/'
          'flutter-gradle-plugin-apply',
    );
  }
}

/// AGP 8+ requires `namespace` in the module build file.
final class MissingNamespaceRule implements Rule {
  const MissingNamespaceRule();

  @override
  String get id => 'missing-namespace';

  static final _agp8 = Version.parse('8.0');

  @override
  Iterable<Finding> check(ProjectSnapshot project, CompatMatrix matrix) sync* {
    final agp = project.agp?.value;
    final appBuild = project.appBuildFile;
    if (agp == null || agp < _agp8 || appBuild == null) return;
    if (project.namespace != null) return;
    yield Finding(
      ruleId: id,
      severity: Severity.error,
      message: 'AGP $agp requires a `namespace` in $appBuild.',
      fix: 'Add namespace = "<your.application.id>" inside the android { } '
          'block and remove package="..." from AndroidManifest.xml.',
      location: SourceLocation(appBuild, 1),
      reference: 'https://developer.android.com/build/configure-app-module'
          '#set-namespace',
    );
  }
}

/// The JDK must be able to produce the requested bytecode, and Java and
/// Kotlin must target the same JVM version.
final class JvmTargetRule implements Rule {
  const JvmTargetRule();

  @override
  String get id => 'jvm-target';

  @override
  Iterable<Finding> check(ProjectSnapshot project, CompatMatrix matrix) sync* {
    final java = project.javaTarget;
    final kotlin = project.kotlinJvmTarget;
    if (java != null && kotlin != null && java.value != kotlin.value) {
      yield Finding(
        ruleId: id,
        severity: Severity.error,
        message: 'Java targets JVM ${java.value} but Kotlin targets JVM '
            '${kotlin.value}; the build fails with "Inconsistent JVM-target '
            'compatibility".',
        fix: 'Use the same version for targetCompatibility and jvmTarget '
            "(Flutter's template uses 17).",
        location: kotlin.location,
      );
    }

    final jdk = project.java;
    if (jdk == null) return;
    for (final target in [java, kotlin].nonNulls) {
      if (jdk.value.major >= target.value.major) continue;
      yield Finding(
        ruleId: id,
        severity: Severity.error,
        message: 'JDK ${jdk.value} cannot compile for JVM ${target.value}.',
        fix: 'Lower the JVM target or install JDK ${target.value.major}+ and '
            'run `flutter config --jdk-dir=<path-to-jdk>`.',
        location: target.location,
      );
      return;
    }
  }
}
