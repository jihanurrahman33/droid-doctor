import '../model/finding.dart';

/// A Gradle build file whose comments are blanked out, so patterns never match
/// commented-out code. Offsets in [masked] equal offsets in the original.
final class SourceText {
  /// Comments are masked only in Gradle scripts; `.properties` files have no
  /// `//` comments (and contain `https\://`).
  SourceText(this.relativePath, String content)
      : masked = relativePath.endsWith('.properties')
            ? content
            : maskComments(content);

  final String relativePath;
  final String masked;

  /// The first match of any of [patterns] (tried in order), with group 1 as
  /// the value.
  ({String value, SourceLocation location})? find(Iterable<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(masked);
      if (match != null) {
        return (value: match.group(1)!, location: locationOf(match.start));
      }
    }
    return null;
  }

  bool contains(RegExp pattern) => pattern.hasMatch(masked);

  SourceLocation locationOf(int offset) {
    var line = 1;
    for (var i = 0; i < offset && i < masked.length; i++) {
      if (masked.codeUnitAt(i) == 0x0A) line++;
    }
    return SourceLocation(relativePath, line);
  }

  /// Simple `name = "1.2.3"` assignments (Groovy `ext.name = '1.2.3'`,
  /// `ext { name = '1.2.3' }`, Kotlin `val name = "1.2.3"`), for resolving
  /// `$name` references.
  Map<String, ({String value, SourceLocation location})> versionVariables() {
    final pattern = RegExp(
      r'''(?:\bext\.|\bval\s+|\bvar\s+|\bdef\s+|^\s*)(\w+)\s*(?::\s*String\s*)?=\s*["'](\d[\w.-]*)["']''',
      multiLine: true,
    );
    return {
      for (final m in pattern.allMatches(masked))
        m.group(1)!: (value: m.group(2)!, location: locationOf(m.start)),
    };
  }

  /// Resolves [raw] if it is a `$name` / `${name}` reference to a variable in
  /// this file (null if undefined); returns [raw] itself otherwise.
  ({String value, SourceLocation location})? resolve(
    ({String value, SourceLocation location}) raw,
  ) {
    final ref = RegExp(r'^\$\{?(\w+)\}?$').firstMatch(raw.value);
    if (ref == null) return raw;
    return versionVariables()[ref.group(1)!];
  }
}

/// Replaces `//` and `/* */` comments with spaces (keeping newlines), leaving
/// string literals intact so URLs like `https://` survive.
String maskComments(String source) {
  final out = StringBuffer();
  var i = 0;
  String? quote; // The active string delimiter: ', ", or """.
  while (i < source.length) {
    final c = source[i];
    if (quote != null) {
      if (c == r'\' && i + 1 < source.length) {
        out.write(source.substring(i, i + 2));
        i += 2;
        continue;
      }
      if (source.startsWith(quote, i)) {
        out.write(quote);
        i += quote.length;
        quote = null;
        continue;
      }
      out.write(c);
      i++;
      continue;
    }
    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final stop = end == -1 ? source.length : end + 2;
      for (; i < stop; i++) {
        out.write(source[i] == '\n' ? '\n' : ' ');
      }
      continue;
    }
    if (source.startsWith('"""', i)) {
      quote = '"""';
    } else if (c == '"' || c == "'") {
      quote = c;
    }
    out.write(quote ?? c);
    i += quote?.length ?? 1;
  }
  return out.toString();
}
