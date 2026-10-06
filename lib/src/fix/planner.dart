import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/compat_matrix.dart';
import '../detect/source_text.dart';
import '../model/component.dart';
import '../model/finding.dart';
import '../model/project_snapshot.dart';
import '../model/version.dart';
import 'edits.dart';
import 'solver.dart';

/// Everything `fix` would do.
final class FixPlan {
  const FixPlan({
    required this.strategy,
    required this.versionChanges,
    required this.edits,
    required this.manualSteps,
    required this.notes,
  });

  final Strategy strategy;
  final Map<Component, ({Version from, Version to})> versionChanges;
  final List<Edit> edits;

  /// Changes droid_doctor can't make safely; the user must do these.
  final List<String> manualSteps;

  /// Advice that doesn't block the build.
  final List<String> notes;

  bool get isEmpty => edits.isEmpty && manualSteps.isEmpty;

  Set<String> get files => {for (final e in edits) e.path};
}

/// Turns a [Solution] and the project's other findings into line edits.
///
/// Every edit is a single, verified line change; when a declaration doesn't
/// look exactly as expected, the planner emits a manual step instead of
/// guessing.
final class FixPlanner {
  FixPlanner(this.matrix);

  final CompatMatrix matrix;

  static final _agp8 = Version.parse('8.0');
  static final _agp9 = Version.parse('9.0');

  FixPlan plan(ProjectSnapshot project,
      {Strategy strategy = Strategy.minimal}) {
    return _PlanBuilder(project, matrix, strategy).build();
  }

  static String _javaToken(Version v, {required String separator}) =>
      v.major <= 8 ? '1$separator${v.major}' : '${v.major}';
}

final class _PlanBuilder {
  _PlanBuilder(this.project, this.matrix, this.strategy);

  final ProjectSnapshot project;
  final CompatMatrix matrix;
  final Strategy strategy;

  final edits = <Edit>[];
  final manual = <String>[];
  final notes = <String>[];
  final _files = <String, TextLines?>{};
  final _usedLines = <String>{};

  FixPlan build() {
    final solution = Solver(matrix).solve(project, strategy: strategy);
    final changes = {
      for (final MapEntry(key: c, value: to) in solution.targets.entries)
        c: (from: project.version(c)!.value, to: to),
    };

    for (final MapEntry(key: component, value: change) in changes.entries) {
      _versionEdit(component, project.version(component)!, change.to);
    }
    for (final f in solution.unresolved) {
      manual.add('${f.message}${f.fix == null ? '' : ' ${f.fix}'}');
    }

    final agpFrom = project.agp?.value;
    final agpTo = changes[Component.agp]?.to ?? agpFrom;
    _namespace(agpTo);
    _agp9Flags(agpFrom, agpTo);
    _jvmTarget();
    _minSdk();

    if (project.pluginApplyStyle == PluginApplyStyle.legacyImperative) {
      manual.add("Migrate Flutter's Gradle plugin from `apply from: "
          'flutter.gradle` to the plugins {} block: https://docs.flutter.dev/'
          'release/breaking-changes/flutter-gradle-plugin-apply');
    }

    return FixPlan(
      strategy: strategy,
      versionChanges: changes,
      edits: edits,
      manualSteps: manual,
      notes: notes,
    );
  }

  void _versionEdit(Component component, Detected<Version> found, Version to) {
    final location = found.location;
    final what = '${component.displayName} ${found.value} → $to';
    if (location == null) {
      manual.add('Change $what (could not locate its declaration).');
      return;
    }
    final old = RegExp.escape(found.value.toString());
    final pattern = component == Component.gradle
        ? RegExp('(?<=gradle-)$old(?=-(?:all|bin)\\.zip)')
        : RegExp('(?<=["\':])$old(?=["\'])');

    if (component == Component.gradle) {
      final wrapper = _lines(location.path);
      if (wrapper != null &&
          wrapper.lines
              .any((l) => l.trimLeft().startsWith('distributionSha256Sum'))) {
        manual.add('Change $what in ${location.path} and update '
            'distributionSha256Sum (https://gradle.org/release-checksums/).');
        return;
      }
    }
    _replaceInLine(location, pattern, '$to', 'Upgrade $what', what);
  }

  void _namespace(Version? agp) {
    final appBuild = project.appBuildFile;
    if (agp == null || agp < FixPlanner._agp8) return;
    if (project.namespace != null || appBuild == null) return;
    final id = project.applicationId?.value;
    final source = _lines(appBuild);
    final androidLine = source == null
        ? null
        : _firstLine(appBuild, source, RegExp(r'^\s*android\s*\{\s*$'));
    if (id == null || androidLine == null) {
      manual.add('Add namespace = "<your.application.id>" to the android { } '
          'block in $appBuild (required by AGP 8+).');
      return;
    }
    final indent = RegExp(r'^\s*').stringMatch(source!.line(androidLine)!)!;
    final statement =
        project.dsl == Dsl.kotlin ? 'namespace = "$id"' : 'namespace "$id"';
    edits.add(InsertLines(appBuild, 'Add namespace (required by AGP 8+)',
        afterLine: androidLine, lines: ['$indent    $statement']));
    if (_manifestHasPackage()) {
      manual.add('Remove package="..." from the <manifest> tag in '
          'android/app/src/main/AndroidManifest.xml (AGP 8+ uses namespace).');
    }
  }

  /// `flutter create` sets these when generating AGP 9 projects so existing
  /// Kotlin and DSL setups keep working.
  void _agp9Flags(Version? from, Version? to) {
    if (from == null || to == null) return;
    if (from >= FixPlanner._agp9 || to < FixPlanner._agp9) return;
    const flags = {'android.newDsl': 'false', 'android.builtInKotlin': 'false'};
    final path = p.join('android', 'gradle.properties');
    final properties = _lines(path);
    if (properties == null) {
      manual.add(
          'Add ${flags.entries.map((e) => '${e.key}=${e.value}').join(' and ')} '
          'to android/gradle.properties (AGP 9 defaults changed).');
      return;
    }
    final missing = [
      for (final MapEntry(:key, :value) in flags.entries)
        if (!properties.lines.any((l) =>
            l.trimLeft().startsWith('$key=') ||
            l.trimLeft().startsWith('$key ')))
          '$key=$value',
    ];
    if (missing.isNotEmpty) {
      edits.add(InsertLines(
          path, 'Keep pre-AGP 9 defaults, as flutter create does', lines: [
        '# Added by droid_doctor for the AGP 9 upgrade',
        ...missing
      ]));
    }
    notes.add('AGP 9 is a major upgrade; review the release notes: '
        'https://developer.android.com/build/releases/gradle-plugin');
  }

  void _jvmTarget() {
    final java = project.javaTarget;
    final kotlin = project.kotlinJvmTarget;
    if (java == null || kotlin == null || java.value == kotlin.value) return;
    final location = kotlin.location;
    if (location == null) return;
    final target = java.value;
    final quoted = FixPlanner._javaToken(target, separator: '.');
    final enumToken = FixPlanner._javaToken(target, separator: '_');
    final what = 'Kotlin jvmTarget ${kotlin.value} → ${target.major}';
    final reason = 'Match Kotlin jvmTarget to Java targetCompatibility';
    for (final (pattern, replacement) in [
      (RegExp(r'(?<=JVM_)\d+(?:_\d+)?\b'), enumToken),
      (RegExp(r'(?<=VERSION_)\d+(?:_\d+)?\b'), enumToken),
      (
        RegExp(
            r'''(?<=jvmTarget\s*(?:=|\.set\()\s*["'])\d+(?:\.\d+)?(?=["'])'''),
        quoted
      ),
      (RegExp(r'(?<=jvmToolchain\s*\(?\s*)\d+'), '${target.major}'),
    ]) {
      if (_replaceInLine(location, pattern, replacement, reason, what,
          reportFailure: false)) {
        return;
      }
    }
    manual.add('Change $what at $location.');
  }

  void _minSdk() {
    final minSdk = project.minSdk;
    final flutter = project.flutter?.value;
    final requirements =
        flutter == null ? null : matrix.requirementsFor(flutter);
    if (minSdk == null || requirements == null) return;
    final templateMin = int.tryParse(requirements.template['minSdk'] ?? '');
    final target = switch (strategy) {
      Strategy.minimal => requirements.errorMinSdkBelow,
      Strategy.latest => templateMin ?? requirements.warnMinSdkBelow,
    };
    if (target == null || minSdk.value >= target) return;
    final location = minSdk.location;
    if (location == null) return;
    _replaceInLine(
      location,
      RegExp(r'(?<=\bminSdk(?:Version)?\s*[=(]?\s*)\d+\b'),
      '$target',
      'Raise minSdk to $target (Flutter ${flutter!.major}.${flutter.minor})',
      'minSdk ${minSdk.value} → $target',
    );
  }

  /// Replaces the single match of [pattern] on [location]'s line. Returns
  /// whether an edit was added; otherwise adds a manual step (unless
  /// [reportFailure] is false).
  bool _replaceInLine(
    SourceLocation location,
    RegExp pattern,
    String replacement,
    String reason,
    String what, {
    bool reportFailure = true,
  }) {
    final key = location.toString();
    final line = _lines(location.path)?.line(location.line);
    final matches = line == null
        ? const <RegExpMatch>[]
        : pattern.allMatches(line).toList();
    if (matches.length != 1 || _usedLines.contains(key)) {
      if (reportFailure) manual.add('Change $what at $location.');
      return false;
    }
    final m = matches.single;
    _usedLines.add(key);
    edits.add(ReplaceLine(location.path, reason,
        line: location.line,
        before: line!,
        after: line.replaceRange(m.start, m.end, replacement)));
    return true;
  }

  int? _firstLine(String path, TextLines source, RegExp pattern) {
    final masked = SourceText(path, source.lines.join('\n')).masked.split('\n');
    for (var i = 0; i < masked.length; i++) {
      if (pattern.hasMatch(masked[i])) return i + 1;
    }
    return null;
  }

  bool _manifestHasPackage() {
    final manifest = File(p.join(project.projectPath, 'android', 'app', 'src',
        'main', 'AndroidManifest.xml'));
    return manifest.existsSync() &&
        RegExp(r'<manifest\b[^>]*\bpackage\s*=')
            .hasMatch(manifest.readAsStringSync());
  }

  TextLines? _lines(String relativePath) =>
      _files.putIfAbsent(relativePath, () {
        final file = File(p.join(project.projectPath, relativePath));
        return file.existsSync()
            ? TextLines.parse(file.readAsStringSync())
            : null;
      });
}
