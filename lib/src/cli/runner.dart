import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../data/compat_matrix.dart';
import '../data/matrix_store.dart';
import '../detect/android_scanner.dart';
import '../detect/environment.dart';
import '../model/finding.dart';
import '../model/project_snapshot.dart';
import '../model/version.dart';
import '../plugins/pub_client.dart';
import '../report/reporters.dart';
import '../rules/rule.dart';
import 'data_command.dart';
import 'explain_command.dart';
import 'fix_command.dart';
import 'plan_command.dart';
import 'plugins_command.dart';
import 'version.dart';

/// Process exit codes.
abstract final class ExitCode {
  static const ok = 0;
  static const problems = 1;
  static const usage = 2;
  static const internal = 3;
}

/// I/O and environment shared by all commands; injectable for tests.
final class CliContext {
  CliContext({
    required this.probe,
    required this.out,
    required this.err,
    required this.color,
    required this.interactive,
    required this.readLine,
    required this.stdinIsTerminal,
    required this.readStdin,
    required this.packageInfo,
    required this.cacheDir,
    required this.now,
    required this.httpGet,
  });

  final EnvironmentProbe probe;
  final StringSink out;
  final StringSink err;
  final bool color;

  /// Whether the user can answer prompts.
  final bool interactive;
  final String? Function() readLine;

  /// Whether stdin is a terminal (nothing piped in).
  final bool stdinIsTerminal;
  final Future<String> Function() readStdin;
  final PackageLookup packageInfo;

  /// Where downloaded compatibility data is cached.
  final String cacheDir;
  final DateTime Function() now;
  final Future<String> Function(Uri) httpGet;
}

/// Runs droid_doctor with [arguments] and returns the exit code. `check` is
/// the default command.
Future<int> runDroidDoctor(
  List<String> arguments, {
  EnvironmentProbe? probe,
  StringSink? out,
  StringSink? err,
  bool? color,
  bool? interactive,
  String? Function()? readLine,
  bool? stdinIsTerminal,
  Future<String> Function()? readStdin,
  PackageLookup? packageInfo,
  String? cacheDir,
  DateTime Function()? now,
  Future<String> Function(Uri)? httpGet,
}) {
  final context = CliContext(
    probe: probe ?? EnvironmentProbe(),
    out: out ?? stdout,
    err: err ?? stderr,
    color: color ?? (out == null && stdout.supportsAnsiEscapes),
    interactive:
        interactive ?? (out == null && stdin.hasTerminal && stdout.hasTerminal),
    readLine: readLine ?? stdin.readLineSync,
    stdinIsTerminal: stdinIsTerminal ?? stdin.hasTerminal,
    readStdin: readStdin ??
        () => stdin.transform(const Utf8Decoder(allowMalformed: true)).join(),
    packageInfo: packageInfo ?? pubDevPackageInfo,
    cacheDir: cacheDir ??
        defaultCacheDir(Platform.environment, Platform.operatingSystem),
    now: now ?? DateTime.now,
    httpGet: httpGet ?? httpGetText,
  );
  final runner = DroidDoctorRunner(context);
  final isTopLevel = arguments.isNotEmpty &&
      (runner.commands.containsKey(arguments.first) ||
          const {'-h', '--help', '--version'}.contains(arguments.first));
  return runner.run(isTopLevel ? arguments : ['check', ...arguments]);
}

final class DroidDoctorRunner extends CommandRunner<int> {
  DroidDoctorRunner(this._context)
      : super(
          'droid_doctor',
          'Finds and fixes Gradle, AGP, Kotlin and JDK version problems in '
              "a Flutter project's Android build.",
        ) {
    argParser.addFlag('version',
        negatable: false, help: 'Print the droid_doctor version.');
    addCommand(CheckCommand(_context));
    addCommand(FixCommand(_context));
    addCommand(ExplainCommand(_context));
    addCommand(PluginsCommand(_context));
    addCommand(PlanCommand(_context));
    addCommand(DataCommand(_context));
  }

  final CliContext _context;

  @override
  void printUsage() => _context.out.writeln(usage);

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final results = parse(args);
      if (results.flag('version')) {
        _context.out.writeln('droid_doctor $packageVersion');
        return ExitCode.ok;
      }
      return await runCommand(results) ?? ExitCode.ok;
    } on UsageException catch (e) {
      _context.err.writeln(e);
      return ExitCode.usage;
    }
  }
}

/// A command that inspects a project: shares the project, environment and
/// matrix options.
abstract class ProjectCommand extends Command<int> {
  ProjectCommand(this.context) {
    argParser
      ..addOption('project',
          abbr: 'p',
          help: 'Flutter project root or its android/ directory.',
          defaultsTo: '.')
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

  final CliContext context;

  ArgResults get args => argResults!;

  bool get color =>
      args.wasParsed('color') ? args.flag('color') : context.color;

  /// Notes about the data in use (ignored downloads, staleness), for reports.
  final dataNotes = <String>[];

  CompatMatrix loadMatrix() {
    final path = args.option('matrix');
    if (path == null) {
      final loaded = MatrixStore(context.cacheDir).load();
      dataNotes.addAll([
        if (loaded.note != null) loaded.note!,
        if (stalenessNote(loaded.matrix, context.now()) case final stale?)
          stale,
      ]);
      return loaded.matrix;
    }
    final file = File(path);
    if (!file.existsSync()) usageException('Matrix file not found: $path');
    try {
      return CompatMatrix.parse(file.readAsStringSync());
    } on FormatException catch (e) {
      usageException('Invalid matrix $path: ${e.message}');
    }
  }

  /// Scans the project with the detected (or overridden) environment.
  /// Returns null after reporting if there is no Android project.
  Future<ProjectSnapshot?> scanProject() async {
    final flutter = _override('flutter-version', Version.tryParse) ??
        await context.probe.flutterVersion();
    final java = _override('java-version', parseJavaVersion) ??
        await context.probe.java();
    return rescan(flutter: flutter, java: java);
  }

  /// Scans again with an already-known environment (e.g. after a fix).
  ProjectSnapshot? rescan({
    Detected<Version>? flutter,
    Detected<Version>? java,
  }) {
    try {
      return const AndroidScanner().scan(
        args.option('project')!,
        flutter: flutter,
        java: java,
      );
    } on ProjectNotFoundException catch (e) {
      context.err.writeln(e);
      return null;
    }
  }

  Detected<Version>? _override(
    String option,
    Version? Function(String) parse,
  ) {
    final raw = args.option(option);
    if (raw == null) return null;
    final version = parse(raw);
    if (version == null) usageException('Invalid --$option: "$raw"');
    return Detected(version, origin: '--$option');
  }
}

final class CheckCommand extends ProjectCommand {
  CheckCommand(super.context) {
    argParser
      ..addFlag('json', negatable: false, help: 'Print JSON output.')
      ..addFlag('ci',
          negatable: false,
          help: 'Exit with code 1 on warnings too, and disable colors.')
      ..addFlag('annotations',
          negatable: false,
          help: 'Also print GitHub Actions annotations, so problems show on '
              'the changed lines of a pull request.');
  }

  @override
  String get name => 'check';

  @override
  String get description =>
      'Check Android build versions for problems (the default command).';

  @override
  Future<int> run() async {
    final matrix = loadMatrix();
    final project = await scanProject();
    if (project == null) return ExitCode.usage;
    final result = CheckResult(
      project: project,
      findings: checkProject(project, matrix),
      matrix: matrix,
      notes: [...context.probe.notes, ...dataNotes],
    );

    final ci = args.flag('ci');
    context.out.write(args.flag('json')
        ? '${renderJson(result, toolVersion: packageVersion)}\n'
        : renderText(result, toolVersion: packageVersion, color: !ci && color));
    if (args.flag('annotations')) {
      context.out.write(renderGitHubAnnotations(result,
          workingDirectory: Directory.current.path));
    }

    final failing = result.count(Severity.error) +
        (ci ? result.count(Severity.warning) : 0);
    return failing > 0 ? ExitCode.problems : ExitCode.ok;
  }
}
