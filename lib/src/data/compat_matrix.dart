import 'dart:convert';

import '../model/component.dart';
import '../model/finding.dart';
import '../model/version.dart';
import 'bundled_matrix.g.dart';

/// The schema version this build of droid_doctor understands.
const supportedSchemaVersion = 1;

/// "If [when] is in [whenRange], [require] must be in [requireRange]."
final class CompatRule {
  const CompatRule({
    required this.when,
    required this.whenRange,
    required this.require,
    required this.requireRange,
    required this.aboveMaxSeverity,
    this.reference,
  });

  final Component when;
  final VersionRange whenRange;
  final Component require;
  final VersionRange requireRange;

  /// How bad it is for [require] to be newer than [requireRange] allows.
  /// Being older is always an error.
  final Severity aboveMaxSeverity;
  final String? reference;
}

/// What one Flutter minor release (e.g. `3.47`) requires of the Android build.
final class FlutterRequirements {
  const FlutterRequirements({
    required this.flutter,
    required this.errorBelow,
    required this.warnBelow,
    this.errorMinSdkBelow,
    this.warnMinSdkBelow,
    this.template = const {},
    this.reference,
  });

  final Version flutter;
  final Map<Component, Version> errorBelow;
  final Map<Component, Version> warnBelow;
  final int? errorMinSdkBelow;
  final int? warnMinSdkBelow;

  /// Versions `flutter create` generates, used as upgrade suggestions.
  final Map<String, String> template;
  final String? reference;

  bool matches(Version v) =>
      v.major == flutter.major && v.minor == flutter.minor;
}

/// The compatibility data droid_doctor checks projects against.
final class CompatMatrix {
  const CompatMatrix({
    required this.updated,
    required this.unknownFrom,
    this.releases = const {},
    required this.rules,
    required this.flutter,
  });

  /// The matrix bundled with this release.
  factory CompatMatrix.bundled() =>
      _bundled ??= CompatMatrix.parse(bundledMatrixJson);
  static CompatMatrix? _bundled;

  /// Parses and validates matrix JSON, throwing a [FormatException] that names
  /// the offending entry if anything is malformed.
  factory CompatMatrix.parse(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Matrix is not valid JSON: ${e.message}');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('Matrix must be a JSON object');
    }
    final schema = json['schemaVersion'];
    if (schema != supportedSchemaVersion) {
      throw FormatException(
        'Unsupported matrix schemaVersion $schema '
        '(expected $supportedSchemaVersion); upgrade droid_doctor',
      );
    }
    final sources = _map(json, 'sources').cast<String, String>();

    String? reference(Map<String, Object?> entry) {
      final key = entry['source'] as String?;
      if (key == null) return null;
      return sources[key] ?? (throw FormatException('Unknown source "$key"'));
    }

    final rules = <CompatRule>[];
    final rawRules = _list(json, 'rules');
    for (var i = 0; i < rawRules.length; i++) {
      try {
        final r = rawRules[i] as Map<String, Object?>;
        rules.add(CompatRule(
          when: Component.parse(r['when'] as String),
          whenRange: VersionRange.fromJson(_map(r, 'in')),
          require: Component.parse(r['require'] as String),
          requireRange: VersionRange.fromJson(_map(r, 'range')),
          aboveMaxSeverity: Severity.values.byName(
            r['aboveMax'] as String? ?? Severity.error.name,
          ),
          reference: reference(r),
        ));
      } on Object catch (e) {
        throw FormatException('Invalid rules[$i]: $e');
      }
    }

    final flutter = <FlutterRequirements>[];
    final rawFlutter = _list(json, 'flutter');
    for (var i = 0; i < rawFlutter.length; i++) {
      try {
        final f = rawFlutter[i] as Map<String, Object?>;
        final error = _map(f, 'error');
        final warn = _map(f, 'warn');
        flutter.add(FlutterRequirements(
          flutter: Version.parse(f['version'] as String),
          errorBelow: _componentVersions(error),
          warnBelow: _componentVersions(warn),
          errorMinSdkBelow: error['minSdk'] as int?,
          warnMinSdkBelow: warn['minSdk'] as int?,
          template: {
            for (final e
                in (f['template'] as Map<String, Object?>? ?? {}).entries)
              e.key: '${e.value}',
          },
          reference: sources['flutter']
              ?.replaceAll('{tag}', f['tag'] as String? ?? 'main'),
        ));
      } on Object catch (e) {
        throw FormatException('Invalid flutter[$i]: $e');
      }
    }

    return CompatMatrix(
      updated: json['updated'] as String? ?? 'unknown',
      unknownFrom: _componentVersions(_map(json, 'unknownFrom')),
      releases: _releases(json['releases']),
      rules: rules,
      flutter: flutter,
    );
  }

  /// The date the data was last refreshed (YYYY-MM-DD).
  final String updated;

  /// Per component, the first version this data knows nothing about.
  final Map<Component, Version> unknownFrom;

  /// Known release versions per component, ascending: the upgrade targets
  /// `fix` may choose from.
  final Map<Component, List<Version>> releases;

  static Map<Component, List<Version>> _releases(Object? json) {
    if (json == null) return const {};
    if (json is! Map<String, Object?>) {
      throw const FormatException('"releases" must be an object');
    }
    return {
      for (final MapEntry(:key, :value) in json.entries)
        Component.parse(key): [
          for (final v in value as List<Object?>) Version.parse(v as String)
        ]..sort(),
    };
  }

  final List<CompatRule> rules;
  final List<FlutterRequirements> flutter;

  /// The requirements for [version]'s minor release, if known.
  FlutterRequirements? requirementsFor(Version version) {
    for (final f in flutter) {
      if (f.matches(version)) return f;
    }
    return null;
  }

  static Map<Component, Version> _componentVersions(Map<String, Object?> m) => {
        for (final c in Component.values)
          if (m[c.name] case final String v) c: Version.parse(v),
      };

  static Map<String, Object?> _map(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! Map<String, Object?>) {
      throw FormatException('"$key" must be an object');
    }
    return value;
  }

  static List<Object?> _list(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! List<Object?>) throw FormatException('"$key" must be a list');
    return value;
  }
}
