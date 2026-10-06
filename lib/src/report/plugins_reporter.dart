import 'dart:convert';

import '../model/finding.dart';
import '../plugins/plugin_auditor.dart';

String renderPluginsJson(List<PluginReport> reports) =>
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'plugins': [for (final r in reports) r.toJson()],
      'summary': {
        'checked': reports.length,
        'errors': reports.where((r) => r.worst == Severity.error).length,
        'warnings': reports.where((r) => r.worst == Severity.warning).length,
      },
    });

String renderPlugins(
  List<PluginReport> reports, {
  required String context,
  bool color = false,
}) {
  String paint(String text, String code) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;

  final out = StringBuffer()
    ..writeln(paint('droid_doctor plugins', '1') + paint('  ·  $context', '2'))
    ..writeln();

  final problems = reports.where((r) => r.findings.isNotEmpty).toList();
  for (final r in problems) {
    final version = r.plugin.version ?? '(path/git)';
    final newer = (r.info?.isDiscontinued ?? false)
        ? paint('  (discontinued)', '31')
        : r.hasNewerVersion
            ? paint('  → ${r.latestVersion} available', '32')
            : r.latestVersion != null
                ? paint('  (latest)', '2')
                : '';
    out.writeln('${paint(r.plugin.name, '1')} $version$newer');
    for (final f in r.findings) {
      final (label, code) = switch (f.severity) {
        Severity.error => ('error  ', '31'),
        Severity.warning => ('warning', '33'),
        Severity.info => ('info   ', '36'),
      };
      out.writeln('  ${paint(label, code)}  ${f.message}');
      if (f.location != null) {
        out.writeln(paint('           at ${f.location}', '2'));
      }
      if (f.fix != null) out.writeln('           fix: ${f.fix}');
    }
    out.writeln();
  }

  final errors = reports.where((r) => r.worst == Severity.error).length;
  final warnings = reports.where((r) => r.worst == Severity.warning).length;
  final ok = reports.length - problems.length;
  final summary = '${reports.length} Android plugin'
      '${reports.length == 1 ? '' : 's'} checked: $errors with errors, '
      '$warnings with warnings, $ok OK.';
  out.writeln(errors > 0
      ? paint(summary, '31')
      : warnings > 0
          ? paint(summary, '33')
          : paint(summary, '32'));
  return out.toString();
}
