import 'package:path/path.dart' as p;

import '../fix/applier.dart';
import '../fix/edits.dart';
import '../fix/planner.dart';
import '../fix/solver.dart';
import '../model/finding.dart';
import '../report/plan_reporter.dart';
import '../rules/rule.dart';
import 'runner.dart';

final class FixCommand extends ProjectCommand {
  FixCommand(super.context) {
    argParser
      ..addOption('strategy',
          allowed: Strategy.values.map((s) => s.name),
          defaultsTo: Strategy.minimal.name,
          allowedHelp: {
            Strategy.minimal.name: 'Smallest upgrades that fix the errors.',
            Strategy.latest.name: 'Newest versions with known compatibility.',
          },
          help: 'How far to upgrade.')
      ..addFlag('dry-run',
          negatable: false, help: 'Show the changes without writing them.')
      ..addFlag('yes',
          abbr: 'y', negatable: false, help: 'Apply without asking.')
      ..addFlag('undo',
          negatable: false, help: 'Restore the files changed by the last fix.')
      ..addFlag('force',
          negatable: false,
          help: 'With --undo, restore even files edited since the fix.');
  }

  @override
  String get name => 'fix';

  @override
  String get description =>
      'Upgrade Gradle, AGP and Kotlin versions and fix related settings.';

  @override
  Future<int> run() async {
    if (args.flag('undo')) return _undo();
    final out = context.out;
    final matrix = loadMatrix();
    final project = await scanProject();
    if (project == null) return ExitCode.usage;

    final plan = FixPlanner(matrix).plan(
      project,
      strategy: Strategy.values.byName(args.option('strategy')!),
    );
    out.write(renderPlan(plan, color: color));

    int remainingErrors() {
      final current = rescan(flutter: project.flutter, java: project.java);
      if (current == null) return 1;
      final findings = checkProject(current, matrix);
      final errors = findings.where((f) => f.severity == Severity.error).length;
      final warnings =
          findings.where((f) => f.severity == Severity.warning).length;
      out.writeln('Check: $errors error${errors == 1 ? '' : 's'}, '
          '$warnings warning${warnings == 1 ? '' : 's'} '
          '(run `droid_doctor check` for details).');
      return errors;
    }

    if (plan.edits.isEmpty) {
      out.writeln(plan.manualSteps.isEmpty
          ? 'Nothing to fix automatically.'
          : 'Nothing droid_doctor can change automatically; see the manual '
              'steps above.');
      return remainingErrors() > 0 ? ExitCode.problems : ExitCode.ok;
    }

    final summary = '${plan.edits.length} change'
        '${plan.edits.length == 1 ? '' : 's'} to ${plan.files.length} file'
        '${plan.files.length == 1 ? '' : 's'}';
    if (args.flag('dry-run')) {
      out.writeln('Dry run: would apply $summary. No files were changed.');
      return remainingErrors() > 0 ? ExitCode.problems : ExitCode.ok;
    }
    if (!args.flag('yes')) {
      if (!context.interactive) {
        out.writeln('Not applied: re-run with --yes to apply $summary.');
        return remainingErrors() > 0 ? ExitCode.problems : ExitCode.ok;
      }
      if (await context.probe.hasUncommittedChanges(project.projectPath)) {
        out.writeln('Note: android/ has uncommitted changes. A backup is '
            'made either way.');
      }
      out.write('Apply $summary? [y/N] ');
      final answer = context.readLine()?.trim().toLowerCase();
      if (answer != 'y' && answer != 'yes') {
        out.writeln('Aborted. No files were changed.');
        return ExitCode.problems;
      }
    }

    final String backup;
    try {
      backup = FixApplier(project.projectPath).apply(plan.edits);
    } on StaleEditException catch (e) {
      context.err.writeln(e);
      return ExitCode.problems;
    }
    out
      ..writeln('Applied $summary.')
      ..writeln('Backup: ${p.normalize(backup)}  '
          '(undo with `droid_doctor fix --undo`)');
    return remainingErrors() > 0 ? ExitCode.problems : ExitCode.ok;
  }

  int _undo() {
    final root = rescan()?.projectPath;
    if (root == null) return ExitCode.usage;
    final result = FixApplier(root).undo(force: args.flag('force'));
    final out = context.out;
    if (result.restored.isEmpty && result.conflicts.isEmpty) {
      out.writeln('No droid_doctor backup found; nothing to undo.');
      return ExitCode.ok;
    }
    if (result.restored.isEmpty) {
      out
        ..writeln('Not restored: these files changed after the fix:')
        ..writeAll(result.conflicts.map((f) => '  $f\n'))
        ..writeln('Re-run with --undo --force to overwrite them.');
      return ExitCode.problems;
    }
    out
      ..writeln('Restored ${result.restored.length} file'
          '${result.restored.length == 1 ? '' : 's'}:')
      ..writeAll(result.restored.map((f) => '  $f\n'));
    return ExitCode.ok;
  }
}
