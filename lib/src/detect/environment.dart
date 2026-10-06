import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/finding.dart';
import '../model/version.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

Future<ProcessResult> _runProcess(String executable, List<String> arguments) =>
    Process.run(executable, arguments, runInShell: Platform.isWindows);

/// Finds the Flutter SDK version and the JDK Flutter will build with.
final class EnvironmentProbe {
  EnvironmentProbe({
    ProcessRunner? run,
    Map<String, String>? environment,
    bool Function(String path)? fileExists,
    String? operatingSystem,
  })  : _run = run ?? _runProcess,
        _environment = environment ?? Platform.environment,
        _fileExists = fileExists ?? ((path) => File(path).existsSync()),
        _os = operatingSystem ?? Platform.operatingSystem;

  final ProcessRunner _run;
  final Map<String, String> _environment;
  final bool Function(String path) _fileExists;
  final String _os;

  /// Problems encountered while probing, for the report.
  final List<String> notes = [];

  Map<String, Object?>? _flutterConfig;

  Future<Detected<Version>?> flutterVersion() async {
    final json = await _runJson('flutter', ['--version', '--machine']);
    final version = Version.tryParse(json?['frameworkVersion'] as String?);
    if (version == null) {
      notes.add('Could not determine the Flutter version '
          '(is `flutter` on PATH?). Pass --flutter-version to set it.');
      return null;
    }
    return Detected(version, origin: 'flutter --version');
  }

  /// Resolves the JDK the same way Flutter does: `flutter config --jdk-dir`,
  /// then Android Studio's bundled JBR, then `JAVA_HOME`, then `java` on PATH.
  Future<Detected<Version>?> java() async {
    final config = _flutterConfig ??=
        await _runJson('flutter', ['config', '--machine']) ?? const {};
    final candidates = <(String, String)>[
      if (config['jdk-dir'] case final String dir)
        (_javaExecutable(dir), 'flutter config --jdk-dir ($dir)'),
      for (final jbr
          in _androidStudioJbrs(config['android-studio-dir'] as String?))
        (_javaExecutable(jbr), 'Android Studio JBR ($jbr)'),
      if (_environment['JAVA_HOME'] case final String home when home.isNotEmpty)
        (_javaExecutable(home), 'JAVA_HOME ($home)'),
    ];
    for (final (executable, origin) in candidates) {
      if (!_fileExists(executable)) continue;
      final version = await _javaVersion(executable);
      if (version != null) return Detected(version, origin: origin);
    }
    final fromPath = await _javaVersion('java');
    if (fromPath != null) return Detected(fromPath, origin: 'java on PATH');
    notes.add('Could not find a JDK. Pass --java-version to set it.');
    return null;
  }

  /// Whether git reports uncommitted changes under [projectPath]/android.
  /// False when git is unavailable or this isn't a repository.
  Future<bool> hasUncommittedChanges(String projectPath) async {
    try {
      final result = await _run(
          'git', ['-C', projectPath, 'status', '--porcelain', '--', 'android']);
      return result.exitCode == 0 && '${result.stdout}'.trim().isNotEmpty;
    } on ProcessException {
      return false;
    }
  }

  String _javaExecutable(String home) =>
      p.join(home, 'bin', _os == 'windows' ? 'java.exe' : 'java');

  Iterable<String> _androidStudioJbrs(String? configured) sync* {
    final dirs = [
      if (configured != null) configured,
      ...switch (_os) {
        'macos' => ['/Applications/Android Studio.app/Contents'],
        'windows' => [r'C:\Program Files\Android\Android Studio'],
        _ => [
            '/opt/android-studio',
            if (_environment['HOME'] case final String home)
              p.join(home, 'android-studio'),
          ],
      },
    ];
    for (final dir in dirs) {
      // macOS bundles nest the JDK home one level deeper.
      yield p.join(dir, 'jbr', 'Contents', 'Home');
      yield p.join(dir, 'jbr');
    }
  }

  Future<Version?> _javaVersion(String executable) async {
    try {
      final result = await _run(executable, ['-version']);
      if (result.exitCode != 0) return null;
      // `java -version` prints to stderr; some distributions use stdout.
      final output = '${result.stderr}\n${result.stdout}';
      final raw = RegExp(r'version "([^"]+)"').firstMatch(output)?.group(1);
      return parseJavaVersion(raw);
    } on ProcessException {
      return null;
    }
  }

  Future<Map<String, Object?>?> _runJson(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await _run(executable, arguments);
      if (result.exitCode != 0) return null;
      final out = '${result.stdout}';
      // Flutter may print banners (e.g. upgrade notices) around the JSON.
      final start = out.indexOf('{'), end = out.lastIndexOf('}');
      if (start == -1 || end < start) return null;
      final decoded = jsonDecode(out.substring(start, end + 1));
      return decoded is Map<String, Object?> ? decoded : null;
    } on ProcessException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
