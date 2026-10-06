/// A version number as used by Gradle, the Android Gradle Plugin, Kotlin and
/// the JDK, e.g. `8.10.2`, `2.1.0-RC2` or `9.0.0-alpha03`.
///
/// These are not semver: the number of numeric segments varies and missing
/// trailing segments count as zero (`8.10` == `8.10.0`). A pre-release
/// qualifier sorts before the release it qualifies (`2.1.0-RC2` < `2.1.0`).
final class Version implements Comparable<Version> {
  Version._(this._text, this._segments, this._qualifier);

  /// Parses [input], throwing a [FormatException] if it is not a version.
  factory Version.parse(String input) {
    final text = input.trim();
    final match = _pattern.firstMatch(text);
    if (match == null) throw FormatException('Invalid version', input);
    final segments = match.group(1)!.split('.').map(int.parse).toList();
    return Version._(text, segments, match.group(2)?.toLowerCase());
  }

  /// Like [Version.parse], but returns `null` for null or invalid input.
  static Version? tryParse(String? input) {
    if (input == null) return null;
    try {
      return Version.parse(input);
    } on FormatException {
      return null;
    }
  }

  static final _pattern = RegExp(
    r'^(\d{1,9}(?:\.\d{1,9})*)(?:-([0-9A-Za-z][0-9A-Za-z.-]*))?$',
  );

  final String _text;
  final List<int> _segments;
  final String? _qualifier;

  /// The first numeric segment.
  int get major => _segments.first;

  /// The second numeric segment, or 0 if absent.
  int get minor => _segment(1);

  /// Whether this version has a pre-release qualifier such as `-rc1`.
  bool get isPreRelease => _qualifier != null;

  int _segment(int index) => index < _segments.length ? _segments[index] : 0;

  @override
  int compareTo(Version other) {
    final length = _segments.length > other._segments.length
        ? _segments.length
        : other._segments.length;
    for (var i = 0; i < length; i++) {
      final diff = _segment(i).compareTo(other._segment(i));
      if (diff != 0) return diff;
    }
    return _compareQualifiers(_qualifier, other._qualifier);
  }

  static int _compareQualifiers(String? a, String? b) {
    if (a == b) return 0;
    if (a == null) return 1; // A release sorts after any pre-release.
    if (b == null) return -1;
    final rank = _qualifierRank(a).compareTo(_qualifierRank(b));
    if (rank != 0) return rank;
    final numberA = _firstNumber(a), numberB = _firstNumber(b);
    if (numberA != null && numberB != null && numberA != numberB) {
      return numberA.compareTo(numberB);
    }
    return a.compareTo(b);
  }

  static int _qualifierRank(String q) {
    if (q.contains('snapshot') || q.startsWith('dev')) return 0;
    if (q.startsWith('alpha')) return 1;
    if (q.startsWith('milestone') || RegExp(r'^m\d').hasMatch(q)) return 2;
    if (q.startsWith('beta')) return 3;
    if (q.startsWith('rc')) return 4;
    return 5;
  }

  static int? _firstNumber(String s) {
    final match = RegExp(r'\d+').firstMatch(s);
    return match == null ? null : int.parse(match.group(0)!);
  }

  bool operator <(Version other) => compareTo(other) < 0;
  bool operator <=(Version other) => compareTo(other) <= 0;
  bool operator >(Version other) => compareTo(other) > 0;
  bool operator >=(Version other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode {
    var end = _segments.length;
    while (end > 1 && _segments[end - 1] == 0) {
      end--;
    }
    return Object.hash(Object.hashAll(_segments.take(end)), _qualifier);
  }

  @override
  String toString() => _text;
}

/// Parses a Java version in any of the forms found in the wild — `1.8`,
/// `1_8` (from `JavaVersion.VERSION_1_8`), `1.8.0_392`, `17`, `21.0.4+7`,
/// `25-ea` — and normalizes legacy `1.x` versions to `x`.
Version? parseJavaVersion(String? input) {
  if (input == null) return null;
  final text = input.trim().replaceAll('_', '.');
  final legacy = RegExp(r'^1\.(\d+)').firstMatch(text);
  if (legacy != null) return Version.parse(legacy.group(1)!);
  final modern = RegExp(r'^(\d+(?:\.\d+)*)').firstMatch(text);
  return modern == null ? null : Version.parse(modern.group(1)!);
}

/// A range of versions with an inclusive [min] and an exclusive [max] (or an
/// inclusive one when [maxInclusive] is set). A null bound is unbounded.
final class VersionRange {
  const VersionRange({this.min, this.max, this.maxInclusive = false});

  factory VersionRange.fromJson(Map<String, Object?> json) => VersionRange(
        min: _optionalVersion(json, 'min'),
        max: _optionalVersion(json, 'max'),
        maxInclusive: json['maxInclusive'] as bool? ?? false,
      );

  final Version? min;
  final Version? max;
  final bool maxInclusive;

  bool allows(Version v) => !isBelow(v) && !isAbove(v);

  bool isBelow(Version v) => min != null && v < min!;

  bool isAbove(Version v) =>
      max != null && (maxInclusive ? v > max! : v >= max!);

  @override
  String toString() {
    final parts = [
      if (min != null) '>=$min',
      if (max != null) '${maxInclusive ? '<=' : '<'}$max',
    ];
    return parts.isEmpty ? 'any' : parts.join(' ');
  }
}

Version? _optionalVersion(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('"$key" must be a string');
  return Version.parse(value);
}
