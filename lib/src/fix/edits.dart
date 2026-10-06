/// A change to one file, relative to the project root.
sealed class Edit {
  const Edit(this.path, this.reason);

  final String path;
  final String reason;

  /// The 1-based line the edit is anchored to (for ordering and display).
  int get anchorLine;
}

/// Replaces line [line] (1-based), which must currently equal [before].
final class ReplaceLine extends Edit {
  const ReplaceLine(
    super.path,
    super.reason, {
    required this.line,
    required this.before,
    required this.after,
  });

  final int line;
  final String before;
  final String after;

  @override
  int get anchorLine => line;
}

/// Inserts [lines] after line [afterLine] (1-based), or at the end of the file
/// when [afterLine] is null.
final class InsertLines extends Edit {
  const InsertLines(
    super.path,
    super.reason, {
    required this.lines,
    this.afterLine,
  });

  final List<String> lines;
  final int? afterLine;

  @override
  int get anchorLine => afterLine ?? 1 << 30;
}

/// A file's lines without line terminators, remembering the terminator so
/// the file can be written back unchanged apart from the edits.
final class TextLines {
  TextLines._(this.lines, this.eol);

  factory TextLines.parse(String content) {
    final eol = content.contains('\r\n') ? '\r\n' : '\n';
    return TextLines._(
      [
        for (final line in content.split('\n'))
          line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
      ],
      eol,
    );
  }

  /// When the content ends with a newline, the last element is ''.
  final List<String> lines;
  final String eol;

  bool get _endsWithNewline => lines.length > 1 && lines.last.isEmpty;

  /// The 1-based line, or null if out of range.
  String? line(int number) =>
      number >= 1 && number <= lines.length ? lines[number - 1] : null;

  /// Applies [edits] (all for this file) and returns the new content.
  /// Throws [StaleEditException] if a [ReplaceLine] no longer matches.
  String apply(List<Edit> edits, {required String path}) {
    final result = [...lines];
    // Bottom-up, so earlier line numbers stay valid.
    final ordered = [...edits]
      ..sort((a, b) => b.anchorLine.compareTo(a.anchorLine));
    for (final edit in ordered) {
      switch (edit) {
        case ReplaceLine(:final line, :final before, :final after):
          if (line < 1 || line > result.length || result[line - 1] != before) {
            throw StaleEditException(path, line);
          }
          result[line - 1] = after;
        case InsertLines(:final afterLine, lines: final inserted):
          final at = afterLine ??
              (_endsWithNewline ? result.length - 1 : result.length);
          if (at < 0 || at > result.length) throw StaleEditException(path, at);
          result.insertAll(at, inserted);
      }
    }
    return result.join(eol);
  }
}

/// A file changed between planning and applying.
final class StaleEditException implements Exception {
  const StaleEditException(this.path, this.line);

  final String path;
  final int line;

  @override
  String toString() =>
      '$path:$line changed since the fix was planned; run droid_doctor again.';
}
