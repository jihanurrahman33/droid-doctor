import '../data/compat_matrix.dart';
import '../model/component.dart';
import '../model/finding.dart';
import '../model/project_snapshot.dart';
import '../model/version.dart';
import 'compatibility_rules.dart';
import 'project_rules.dart';

/// A single check. Rules are pure: they only read the snapshot and matrix.
abstract interface class Rule {
  String get id;

  Iterable<Finding> check(ProjectSnapshot project, CompatMatrix matrix);
}

const defaultRules = <Rule>[
  MissingVersionRule(),
  UnknownVersionRule(),
  CompatibilityRule(),
  FlutterRequirementsRule(),
  LegacyPluginApplyRule(),
  MissingNamespaceRule(),
  JvmTargetRule(),
];

/// Runs [rules] and returns their findings, most severe first.
List<Finding> checkProject(
  ProjectSnapshot project,
  CompatMatrix matrix, {
  List<Rule> rules = defaultRules,
}) {
  final findings = [for (final r in rules) ...r.check(project, matrix)];
  _stableSort(findings, (a, b) => a.severity.index - b.severity.index);
  return findings;
}

/// Stable sort, so findings of equal severity keep rule order.
void _stableSort<T>(List<T> list, int Function(T, T) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}

/// How to move [component] to [target], phrased for the report.
String upgradeHint(Component component, Version target) => switch (component) {
      Component.gradle => 'Set distributionUrl to '
          'https\\://services.gradle.org/distributions/gradle-$target-all.zip',
      Component.agp => 'Set the Android Gradle Plugin version to $target',
      Component.kgp => 'Set the Kotlin Gradle Plugin '
          '(org.jetbrains.kotlin.android) version to $target',
      Component.java => 'Install JDK $target or newer, then run '
          '`flutter config --jdk-dir=<path-to-jdk>`',
    };
