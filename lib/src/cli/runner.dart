import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../data/compat_matrix.dart';
import '../detect/android_scanner.dart';
import '../detect/environment.dart';
import '../model/finding.dart';
import '../model/project_snapshot.dart';
import '../model/version.dart';
import '../report/reporters.dart';
import '../rules/rule.dart';
import 'version.dart';

/// Process exit codes.
abstract final class ExitCode {
  static const ok = 0;
  static const problems = 1;
  static const usage = 2;
  static const internal = 3;
}

/// Runs droid_doctor with [arguments] and returns the exit code. `check` is
/// the default command.
Future<int> runDroidDoctor(
  List<String> arguments, {
  EnvironmentProbe? probe,
  StringSink? out,
  StringSink? err,
  bool? color,
}) {
  final stdoutSink = out ?? stdout;
  final runner = DroidDoctorRunner(
    probe: probe ?? EnvironmentProbe(),
    out: stdoutSink,
    err: err ?? stderr,
    color: color ?? (out == null && stdout.supportsAnsiEscapes),
  );
  final isTopLevel = arguments.isNotEmpty &&
      (runner.commands.containsKey(arguments.first) ||
          const {'-h', '--help', '--version'}.contains(arguments.first));
  return runner.run(isTopLevel ? arguments : ['check', ...arguments]);
}

final class DroidDoctorRunner extends CommandRunner<int> {
  DroidDoctorRunner({
    required EnvironmentProbe probe,
    required StringSink out,
    required StringSink err,
    required bool color,
  })  : _out = out,
        _err = err,
        super(
          'droid_doctor',
          'Finds and explains Gradle, AGP, Kotlin and JDK version problems in '
              "a Flutter project's Android build.",
        ) {
    argParser.addFlag('version',
        negatable: false, help: 'Print the droid_doctor version.');
    addCommand(CheckCommand(probe: probe, out: out, err: err, color: color));
  }

  final StringSink _out;
  final StringSink _err;

  @override
  void printUsage() => _out.writeln(usage);

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final results = parse(args);
      if (results.flag('version')) {
        _out.writeln('droid_doctor $packageVersion');
        return ExitCode.ok;
      }
      return await runCommand(results) ?? ExitCode.ok;
    } on UsageException catch (e) {
      _err.writeln(e);
      return ExitCode.usage;
    }
  }
}

final class CheckCommand extends Command<int> {
  CheckCommand({
    required EnvironmentProbe probe,
    required StringSink out,
    required StringSink err,
    required bool color,
  })  : _probe = probe,
        _out = out,
        _err = err,
        _color = color {
    argParser
      ..addOption('project',
          abbr: 'p',
          help: 'Flutter project root or its android/ directory.',
          defaultsTo: '.')
      ..addFlag('json', negatable: false, help: 'Print JSON output.')
      ..addFlag('ci',
          negatable: false,
          help: 'Exit with code 1 on warnings too, and disable colors.')
      ..addFlag('color', help: 'Force colored output on or off.')
      ..addOption('flutter-version',
          help: 'Use this Flutter version instead of running `flutter`.',
          valueHelp: '3.47.2')
      ..addOption('java-version',
          help: 'Use this JDK version instead of detecting it.',
          valueHelp: '17')
      ..addOption('matrix',
          help:
              'Use this compatibility matrix JSON instead of the bundled one.',
          valueHelp: 'path');
  }

  final EnvironmentProbe _probe;
  final StringSink _out;
  final StringSink _err;
  final bool _color;

  @override
  String get name => 'check';

  @override
  String get description =>
      'Check Android build versions for problems (the default command).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final matrix = _loadMatrix(args.option('matrix'));
    final flutter = _override(args, 'flutter-version', Version.tryParse) ??
        await _probe.flutterVersion();
    final java = _override(args, 'java-version', parseJavaVersion) ??
        await _probe.java();

    final ProjectSnapshot project;
    try {
      project = const AndroidScanner().scan(
        args.option('project')!,
        flutter: flutter,
        java: java,
      );
    } on ProjectNotFoundException catch (e) {
      _err.writeln(e);
      return ExitCode.usage;
    }
    final result = CheckResult(
      project: project,
      findings: checkProject(project, matrix),
      matrix: matrix,
      notes: _probe.notes,
    );

    final ci = args.flag('ci');
    _out.write(args.flag('json')
        ? '${renderJson(result, toolVersion: packageVersion)}\n'
        : renderText(
            result,
            toolVersion: packageVersion,
            color:
                !ci && (args.wasParsed('color') ? args.flag('color') : _color),
          ));

    final failing = result.count(Severity.error) +
        (ci ? result.count(Severity.warning) : 0);
    return failing > 0 ? ExitCode.problems : ExitCode.ok;
  }

  Detected<Version>? _override(
    ArgResults args,
    String option,
    Version? Function(String) parse,
  ) {
    final raw = args.option(option);
    if (raw == null) return null;
    final version = parse(raw);
    if (version == null) usageException('Invalid --$option: "$raw"');
    return Detected(version, origin: '--$option');
  }

  CompatMatrix _loadMatrix(String? path) {
    if (path == null) return CompatMatrix.bundled();
    final file = File(path);
    if (!file.existsSync()) usageException('Matrix file not found: $path');
    try {
      return CompatMatrix.parse(file.readAsStringSync());
    } on FormatException catch (e) {
      usageException('Invalid matrix $path: ${e.message}');
    }
  }
}
