import 'patterns.dart';

/// A recognized error in a build log.
final class Diagnosis {
  const Diagnosis({
    required this.id,
    required this.title,
    required this.cause,
    required this.fix,
    required this.line,
    required this.excerpt,
    this.reference,
    this.fixable = false,
  });

  final String id;
  final String title;
  final String cause;
  final String fix;

  /// 1-based line in the log where the error appears.
  final int line;
  final String excerpt;
  final String? reference;
  final bool fixable;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'cause': cause,
        'fix': fix,
        'line': line,
        'excerpt': excerpt,
        if (reference != null) 'reference': reference,
        'fixable': fixable,
      };
}

final _ansi = RegExp(r'\x1B\[[0-9;?]*[A-Za-z]');

/// Finds every known error in [log], in log order, without duplicates.
List<Diagnosis> explainLog(String log, {List<ErrorPattern>? patterns}) {
  final text = log.replaceAll(_ansi, '').replaceAll('\r\n', '\n');
  final lineStarts = [0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }
  int lineOf(int offset) {
    var lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  final seen = <String>{};
  final found = <Diagnosis>[];
  for (final pattern in patterns ?? errorPatterns) {
    for (final m in pattern.regex.allMatches(text)) {
      final title = pattern.title(m, text);
      // The same error is often repeated (per variant/task); report it once.
      if (!seen.add('${pattern.id}|$title')) continue;
      final line = lineOf(m.start);
      final lineEnd = text.indexOf('\n', lineStarts[line - 1]);
      var excerpt = text
          .substring(
              lineStarts[line - 1], lineEnd == -1 ? text.length : lineEnd)
          .trim();
      if (excerpt.length > 200) excerpt = '${excerpt.substring(0, 197)}...';
      found.add(Diagnosis(
        id: pattern.id,
        title: title,
        cause: pattern.cause(m, text),
        fix: pattern.fix(m, text),
        line: line,
        excerpt: excerpt,
        reference: pattern.reference,
        fixable: pattern.isFixable(m, text),
      ));
    }
  }
  found.sort((a, b) => a.line.compareTo(b.line));
  return found;
}
