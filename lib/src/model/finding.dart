enum Severity { error, warning, info }

/// A file and 1-based line, with [path] relative to the project root.
final class SourceLocation {
  const SourceLocation(this.path, this.line);

  final String path;
  final int line;

  Map<String, Object?> toJson() => {'path': path, 'line': line};

  @override
  String toString() => '$path:$line';
}

/// A value found in the project or environment, and where it came from:
/// either a [location] in a build file or a free-form [origin] description.
final class Detected<T> {
  const Detected(this.value, {this.location, this.origin});

  final T value;
  final SourceLocation? location;
  final String? origin;

  String? get source => location?.toString() ?? origin;
}

/// A problem (or note) reported by a rule.
final class Finding {
  const Finding({
    required this.ruleId,
    required this.severity,
    required this.message,
    this.fix,
    this.location,
    this.reference,
  });

  final String ruleId;
  final Severity severity;
  final String message;
  final String? fix;
  final SourceLocation? location;
  final String? reference;

  Map<String, Object?> toJson() => {
        'rule': ruleId,
        'severity': severity.name,
        'message': message,
        if (fix != null) 'fix': fix,
        if (location != null) 'location': location!.toJson(),
        if (reference != null) 'reference': reference,
      };
}
