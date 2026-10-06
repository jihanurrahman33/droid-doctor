import 'dart:io';

import 'package:args/command_runner.dart';

import '../explain/explainer.dart';
import '../report/explain_reporter.dart';
import 'runner.dart';

final class ExplainCommand extends Command<int> {
  ExplainCommand(this.context) {
    argParser
      ..addFlag('json', negatable: false, help: 'Print JSON output.')
      ..addFlag('color', help: 'Force colored output on or off.');
  }

  final CliContext context;

  @override
  String get name => 'explain';

  @override
  String get description =>
      'Explain the errors in a Gradle/Flutter build log.\n\n'
      'Examples:\n'
      '  droid_doctor explain build.log\n'
      '  flutter build apk 2>&1 | droid_doctor explain -';

  @override
  String get invocation => 'droid_doctor explain <log-file | ->';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    if (rest.length > 1) usageException('Pass a single log file.');
    final path = rest.isEmpty ? null : rest.single;

    final String log;
    final String source;
    if (path == null || path == '-') {
      if (path == null && context.stdinIsTerminal) {
        usageException('Pass a log file, or pipe one in with `-`.');
      }
      log = await context.readStdin();
      source = 'stdin';
    } else {
      final file = File(path);
      if (!file.existsSync()) usageException('Log file not found: $path');
      log = file.readAsStringSync();
      source = path;
    }

    final diagnoses = explainLog(log);
    final color = args.wasParsed('color') ? args.flag('color') : context.color;
    context.out.write(args.flag('json')
        ? '${renderDiagnosesJson(diagnoses, source: source)}\n'
        : renderDiagnoses(diagnoses, source: source, color: color));
    return diagnoses.isEmpty ? ExitCode.problems : ExitCode.ok;
  }
}
