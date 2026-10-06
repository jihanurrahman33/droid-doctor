import 'dart:convert';

import '../explain/explainer.dart';

String renderDiagnosesJson(List<Diagnosis> diagnoses,
        {required String source}) =>
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'source': source,
      'diagnoses': [for (final d in diagnoses) d.toJson()],
    });

String renderDiagnoses(
  List<Diagnosis> diagnoses, {
  required String source,
  bool color = false,
}) {
  String paint(String text, String code) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;

  final out = StringBuffer()
    ..writeln(paint('droid_doctor explain', '1') + paint('  ·  $source', '2'))
    ..writeln();

  if (diagnoses.isEmpty) {
    out
      ..writeln('No known error found in the log.')
      ..writeln('If the build failed, please share the log at '
          'https://github.com/jihanurrahman33/droid-doctor/issues so the '
          'pattern can be added.');
    return out.toString();
  }

  for (var i = 0; i < diagnoses.length; i++) {
    final d = diagnoses[i];
    out
      ..writeln(paint('${i + 1}. ${d.title}', '31;1') +
          paint('  (line ${d.line})', '2'))
      ..writeln(paint('   > ${d.excerpt}', '2'))
      ..writeln('   cause: ${d.cause}')
      ..writeln('   fix:   ${d.fix}');
    if (d.fixable) {
      out.writeln(paint('   auto:  droid_doctor fix', '32'));
    }
    if (d.reference != null) {
      out.writeln(paint('   see:   ${d.reference}', '2'));
    }
    out.writeln();
  }
  if (diagnoses.length > 1) {
    out.writeln('Fix them in order: the first error often causes the rest.');
  }
  return out.toString();
}
