import '../data/compat_matrix.dart';
import '../model/component.dart';
import '../model/finding.dart';
import '../model/project_snapshot.dart';
import '../model/version.dart';
import 'rule.dart';

/// Reports build-file versions that could not be found.
final class MissingVersionRule implements Rule {
  const MissingVersionRule();

  @override
  String get id => 'missing-version';

  @override
  Iterable<Finding> check(ProjectSnapshot project, CompatMatrix matrix) sync* {
    if (project.gradle == null) {
      yield Finding(
        ruleId: id,
        severity: Severity.warning,
        message: 'Could not find the Gradle version.',
        fix: 'Check distributionUrl in '
            'android/gradle/wrapper/gradle-wrapper.properties.',
      );
    }
    if (project.agp == null) {
      yield Finding(
        ruleId: id,
        severity: Severity.warning,
        message: 'Could not find the Android Gradle Plugin version.',
        fix: 'Declare it in android/settings.gradle(.kts): '
            'id("com.android.application") version "<version>" apply false',
      );
    }
    if (project.kgp == null && !project.builtInKotlin) {
      yield Finding(
        ruleId: id,
        severity: Severity.info,
        message: 'No Kotlin Gradle Plugin version declared; '
            'Kotlin compatibility was not checked.',
      );
    }
  }
}

/// Flags versions newer than the bundled data knows about.
final class UnknownVersionRule implements Rule {
  const UnknownVersionRule();

  @override
  String get id => 'unknown-version';

  @override
  Iterable<Finding> check(ProjectSnapshot project, CompatMatrix matrix) sync* {
    for (final component in Component.values) {
      final found = project.version(component);
      final unknownFrom = matrix.unknownFrom[component];
      if (found == null || unknownFrom == null || found.value < unknownFrom) {
        continue;
      }
      yield Finding(
        ruleId: id,
        severity: Severity.info,
        message: '${component.displayName} ${found.value} is newer than '
            "droid_doctor's compatibility data (updated ${matrix.updated}); "
            'its compatibility was not verified.',
        fix: 'Update droid_doctor: dart pub global activate droid_doctor',
        location: found.location,
      );
    }
  }
}

/// Checks every pairwise rule in the matrix (JDK↔Gradle, AGP↔Gradle,
/// AGP↔JDK, KGP↔Gradle, KGP↔AGP).
final class CompatibilityRule implements Rule {
  const CompatibilityRule();

  @override
  String get id => 'compatibility';

  @override
  Iterable<Finding> check(ProjectSnapshot project, CompatMatrix matrix) sync* {
    for (final rule in matrix.rules) {
      final when = project.version(rule.when);
      final required = project.version(rule.require);
      if (when == null || required == null) continue;
      if (!rule.whenRange.allows(when.value)) continue;

      final range = rule.requireRange;
      final whenName = '${rule.when.displayName} ${when.value}';
      final requiredName = '${rule.require.displayName} ${required.value}';
      if (range.isBelow(required.value)) {
        yield Finding(
          ruleId: id,
          severity: Severity.error,
          message: '$whenName requires ${rule.require.displayName} '
              '${range.min} or newer (found ${required.value}).',
          fix: upgradeHint(rule.require, range.min!),
          location: required.location,
          reference: rule.reference,
        );
      } else if (range.isAbove(required.value)) {
        yield Finding(
          ruleId: id,
          severity: rule.aboveMaxSeverity,
          message: '$requiredName is newer than $whenName supports '
              '(${rule.require.displayName} ${_describeMax(range)}).',
          fix: 'Upgrade ${rule.when.displayName} to a version that supports '
              '$requiredName.',
          location: when.location,
          reference: rule.reference,
        );
      }
    }
  }

  static String _describeMax(VersionRange range) =>
      range.maxInclusive ? 'up to ${range.max}' : 'below ${range.max}';
}

/// Checks the minimums the project's Flutter version enforces.
final class FlutterRequirementsRule implements Rule {
  const FlutterRequirementsRule();

  @override
  String get id => 'flutter-requirements';

  @override
  Iterable<Finding> check(ProjectSnapshot project, CompatMatrix matrix) sync* {
    final flutter = project.flutter?.value;
    if (flutter == null) return;
    final requirements = matrix.requirementsFor(flutter);
    if (requirements == null) {
      yield Finding(
        ruleId: id,
        severity: Severity.info,
        message: 'No requirement data for Flutter ${flutter.major}.'
            '${flutter.minor}; only toolchain compatibility was checked.',
      );
      return;
    }
    final release = 'Flutter ${flutter.major}.${flutter.minor}';

    for (final component in Component.values) {
      final found = project.version(component);
      if (found == null) continue;
      final errorBelow = requirements.errorBelow[component];
      final warnBelow = requirements.warnBelow[component];
      final suggested = Version.tryParse(requirements.template[component.name]);
      if (errorBelow != null && found.value < errorBelow) {
        yield _finding(Severity.error, release, component, errorBelow, found,
            suggested ?? errorBelow, requirements.reference);
      } else if (warnBelow != null && found.value < warnBelow) {
        yield _finding(Severity.warning, release, component, warnBelow, found,
            suggested ?? warnBelow, requirements.reference);
      }
    }

    final minSdk = project.minSdk;
    if (minSdk != null) {
      final errorBelow = requirements.errorMinSdkBelow;
      final warnBelow = requirements.warnMinSdkBelow;
      final severity = errorBelow != null && minSdk.value < errorBelow
          ? Severity.error
          : warnBelow != null && minSdk.value < warnBelow
              ? Severity.warning
              : null;
      if (severity != null) {
        final needed = severity == Severity.error ? errorBelow : warnBelow;
        yield Finding(
          ruleId: id,
          severity: severity,
          message:
              '$release ${severity == Severity.error ? 'requires' : 'recommends'} '
              'minSdk $needed or higher (found ${minSdk.value}).',
          fix: 'Set minSdk = flutter.minSdkVersion (or $needed+) in '
              '${project.appBuildFile ?? 'android/app/build.gradle'}.',
          location: minSdk.location,
          reference: requirements.reference,
        );
      }
    }
  }

  Finding _finding(
    Severity severity,
    String release,
    Component component,
    Version minimum,
    Detected<Version> found,
    Version suggested,
    String? reference,
  ) =>
      Finding(
        ruleId: id,
        severity: severity,
        message: severity == Severity.error
            ? '$release requires ${component.displayName} $minimum or newer '
                '(found ${found.value}).'
            : '$release warns on ${component.displayName} below $minimum '
                '(found ${found.value}); support will be removed soon.',
        fix: upgradeHint(component, suggested),
        location: found.location,
        reference: reference,
      );
}
