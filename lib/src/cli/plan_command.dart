import '../data/compat_matrix.dart';
import '../fix/planner.dart';
import '../model/component.dart';
import '../model/finding.dart';
import '../model/version.dart';
import '../report/plan_reporter.dart';
import '../rules/rule.dart';
import 'runner.dart';

/// Shows what a Flutter upgrade requires of the Android build, before
/// upgrading.
final class PlanCommand extends ProjectCommand {
  PlanCommand(super.context) {
    argParser.addOption('flutter',
        help: 'The Flutter release to plan for, or "latest".',
        valueHelp: '3.47');
  }

  @override
  String get name => 'plan';

  @override
  String get description =>
      'Show what upgrading Flutter would require of the Android build.';

  @override
  Future<int> run() async {
    final matrix = loadMatrix();
    final raw = args.option('flutter');
    if (raw == null) {
      usageException('Pass --flutter <version> or --flutter latest.');
    }
    final requirements = _target(matrix, raw);
    final project = await scanProject();
    if (project == null) return ExitCode.usage;

    final target =
        '${requirements.flutter.major}.${requirements.flutter.minor}';
    final upgraded = project.withVersions(
      flutter: Detected(requirements.flutter, origin: '--flutter'),
    );
    final findings = checkProject(upgraded, matrix)
        .where((f) => f.severity != Severity.info)
        .toList();
    final plan = FixPlanner(matrix).plan(upgraded);

    String paint(String text, String code) =>
        color ? '\x1B[${code}m$text\x1B[0m' : text;
    final out = context.out
      ..writeln(paint('droid_doctor plan', '1') +
          paint(
              '  ·  Flutter ${project.flutter?.value ?? 'unknown'} → '
                  '$target',
              '2'))
      ..writeln()
      ..writeln('Flutter $target requires:')
      ..writeln(paint(
          '  ${'component'.padRight(10)}${'minimum'.padRight(10)}'
              '${'warns below'.padRight(13)}${'yours'.padRight(17)}status',
          '2'));

    void row(String label, Object? error, Object? warn, Object? yours,
        Severity? severity) {
      final status = switch (severity) {
        Severity.error => paint('✗ fails', '31'),
        Severity.warning => paint('! warns', '33'),
        _ => yours == null ? paint('? unknown', '2') : paint('✓ ok', '32'),
      };
      out.writeln('  ${label.padRight(10)}${'${error ?? '-'}'.padRight(10)}'
          '${'${warn ?? '-'}'.padRight(13)}${'${yours ?? '-'}'.padRight(17)}'
          '$status');
    }

    Severity? severityOf(Comparable<Object>? yours, Object? error, Object? warn,
        int Function(Object?) compare) {
      if (yours == null) return null;
      if (error != null && compare(error) < 0) return Severity.error;
      if (warn != null && compare(warn) < 0) return Severity.warning;
      return null;
    }

    for (final c in Component.values) {
      final yours = project.version(c)?.value;
      final error = requirements.errorBelow[c];
      final warn = requirements.warnBelow[c];
      row(
        c.shortName,
        error,
        warn,
        yours,
        severityOf(yours, error, warn, (v) => yours!.compareTo(v as Version)),
      );
    }
    final minSdk = project.minSdk?.value;
    row(
      'minSdk',
      requirements.errorMinSdkBelow,
      requirements.warnMinSdkBelow,
      minSdk ?? 'flutter default',
      minSdk == null
          ? Severity.info
          : severityOf(minSdk, requirements.errorMinSdkBelow,
              requirements.warnMinSdkBelow, (v) => minSdk.compareTo(v as int)),
    );
    out.writeln();

    final errors = findings.where((f) => f.severity == Severity.error).length;
    if (errors == 0) {
      out.writeln(paint(
          'Ready: the Android build already meets Flutter '
              "$target's minimums.",
          '32'));
      final warnings = findings.length;
      if (warnings > 0) {
        out.writeln('$warnings warning${warnings == 1 ? '' : 's'}: support for '
            'some versions ends soon. To clear them now:\n'
            '  droid_doctor fix --strategy latest --flutter-version $target');
      }
      return ExitCode.ok;
    }
    out
      ..writeln('$errors error${errors == 1 ? '' : 's'} after upgrading. '
          'What `fix` would change:')
      ..writeln()
      ..write(renderPlan(plan, color: color).split('\n').skip(2).join('\n'))
      ..writeln('Apply it now, before upgrading Flutter:')
      ..writeln('  droid_doctor fix --flutter-version $target');
    return ExitCode.problems;
  }

  FlutterRequirements _target(CompatMatrix matrix, String raw) {
    if (matrix.flutter.isEmpty) usageException('No Flutter release data.');
    if (raw == 'latest') {
      return matrix.flutter.reduce((a, b) => a.flutter > b.flutter ? a : b);
    }
    final version = Version.tryParse(raw);
    final requirements =
        version == null ? null : matrix.requirementsFor(version);
    if (requirements == null) {
      final known = [for (final f in matrix.flutter) f.flutter]..sort();
      usageException('No data for Flutter $raw. Known releases: '
          '${known.join(', ')}. Newer data: `droid_doctor data update`.');
    }
    return requirements;
  }
}
