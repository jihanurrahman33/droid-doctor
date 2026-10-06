import '../fix/edits.dart';
import '../fix/planner.dart';

/// Renders a fix plan: version changes, a line diff, and manual steps.
String renderPlan(FixPlan plan, {bool color = false}) {
  String paint(String text, String code) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;

  final out = StringBuffer()
    ..writeln(paint('droid_doctor fix', '1') +
        paint('  ·  strategy: ${plan.strategy.name}', '2'))
    ..writeln();

  if (plan.versionChanges.isNotEmpty) {
    out.writeln('Versions:');
    for (final MapEntry(key: c, value: change) in plan.versionChanges.entries) {
      out.writeln('  ${c.shortName.padRight(7)} ${change.from} → '
          '${paint('${change.to}', '32')}');
    }
    out.writeln();
  }

  if (plan.edits.isNotEmpty) {
    out.writeln('Changes:');
    final ordered = [...plan.edits]..sort((a, b) {
        final byPath = a.path.compareTo(b.path);
        return byPath != 0 ? byPath : a.anchorLine.compareTo(b.anchorLine);
      });
    for (final edit in ordered) {
      switch (edit) {
        case ReplaceLine(:final line, :final before, :final after):
          out
            ..writeln(paint('  ${edit.path}:$line', '36') +
                paint('  ${edit.reason}', '2'))
            ..writeln(paint('  - ${before.trim()}', '31'))
            ..writeln(paint('  + ${after.trim()}', '32'));
        case InsertLines(:final afterLine, :final lines):
          final where = afterLine == null ? 'end' : 'after line $afterLine';
          out.writeln(paint('  ${edit.path} ($where)', '36') +
              paint('  ${edit.reason}', '2'));
          for (final l in lines) {
            out.writeln(paint('  + ${l.trim()}', '32'));
          }
      }
    }
    out.writeln();
  }

  if (plan.manualSteps.isNotEmpty) {
    out.writeln(paint('Manual steps:', '33'));
    for (final step in plan.manualSteps) {
      out.writeln('  • $step');
    }
    out.writeln();
  }

  if (plan.notes.isNotEmpty) {
    out.writeln('Notes:');
    for (final note in plan.notes) {
      out.writeln('  • $note');
    }
    out.writeln();
  }
  return out.toString();
}
