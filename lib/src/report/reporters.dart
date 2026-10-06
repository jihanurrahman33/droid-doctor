import 'dart:convert';

import '../data/compat_matrix.dart';
import '../model/component.dart';
import '../model/finding.dart';
import '../model/project_snapshot.dart';

/// The outcome of a `check` run.
final class CheckResult {
  const CheckResult({
    required this.project,
    required this.findings,
    required this.matrix,
    this.notes = const [],
  });

  final ProjectSnapshot project;
  final List<Finding> findings;
  final CompatMatrix matrix;

  /// Environment probing problems.
  final List<String> notes;

  int count(Severity severity) =>
      findings.where((f) => f.severity == severity).length;
}

/// Machine-readable output for CI and editor integrations.
String renderJson(CheckResult result, {required String toolVersion}) =>
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'tool': {'name': 'droid_doctor', 'version': toolVersion},
      'dataUpdated': result.matrix.updated,
      'project': result.project.toJson(),
      'notes': result.notes,
      'findings': [for (final f in result.findings) f.toJson()],
      'summary': {
        for (final s in Severity.values) s.name: result.count(s),
      },
    });

/// Human-readable output.
String renderText(
  CheckResult result, {
  required String toolVersion,
  bool color = false,
}) {
  String paint(String text, String code) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;
  String bold(String text) => paint(text, '1');
  String dim(String text) => paint(text, '2');

  final out = StringBuffer()
    ..writeln(bold('droid_doctor $toolVersion') +
        dim('  ·  data ${result.matrix.updated}  ·  ${result.project.projectPath}'))
    ..writeln();

  final project = result.project;
  final rows = <(String, Detected<Object>?)>[
    ('Flutter', project.flutter),
    for (final c in Component.values) (c.shortName, project.version(c)),
  ];
  for (final (label, detected) in rows) {
    final value = detected?.value.toString() ?? paint('not found', '33');
    out.writeln('  ${label.padRight(8)} ${value.padRight(10)} '
        '${dim(detected?.source ?? '')}');
  }
  out.writeln();

  for (final note in result.notes) {
    out.writeln('${paint('note', '36')}     $note');
  }
  if (result.notes.isNotEmpty) out.writeln();

  for (final f in result.findings) {
    final (label, code) = switch (f.severity) {
      Severity.error => ('error  ', '31'),
      Severity.warning => ('warning', '33'),
      Severity.info => ('info   ', '36'),
    };
    out.writeln('${paint(label, code)}  ${f.message}');
    if (f.location != null) out.writeln('         ${dim('at ${f.location}')}');
    if (f.fix != null) out.writeln('         fix: ${f.fix}');
    if (f.reference != null) {
      out.writeln('         ${dim('see ${f.reference}')}');
    }
  }

  final errors = result.count(Severity.error);
  final warnings = result.count(Severity.warning);
  final infos = result.count(Severity.info);
  if (result.findings.isNotEmpty) out.writeln();
  final summary =
      '${_plural(errors, 'error')}, ${_plural(warnings, 'warning')}, '
      '${_plural(infos, 'info', 'infos')}.';
  out.writeln(errors > 0
      ? paint(summary, '31')
      : warnings > 0
          ? paint(summary, '33')
          : paint('No problems found. $summary', '32'));
  return out.toString();
}

String _plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : many ?? '${one}s'}';
