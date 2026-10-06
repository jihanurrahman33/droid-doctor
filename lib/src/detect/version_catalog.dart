import '../model/finding.dart';

/// The parts of a Gradle version catalog (`gradle/libs.versions.toml`) needed
/// to resolve plugin versions. Only the TOML subset Gradle catalogs use in
/// practice is supported: `key = "value"` and single-line inline tables.
final class VersionCatalog {
  VersionCatalog._(this._versions, this._plugins);

  factory VersionCatalog.parse(String relativePath, String content) {
    final versions = <String, ({String value, SourceLocation location})>{};
    final plugins = <String, ({String value, SourceLocation location})>{};
    final pluginRefs = <String, String>{}; // plugin id -> versions key
    String? section;
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final header = RegExp(r'^\[([\w.-]+)\]').firstMatch(line);
      if (header != null) {
        section = header.group(1);
        continue;
      }
      final location = SourceLocation(relativePath, i + 1);
      if (section == 'versions') {
        final m = RegExp(r'^([\w.-]+)\s*=\s*"([^"]+)"').firstMatch(line);
        if (m != null) {
          versions[m.group(1)!] = (value: m.group(2)!, location: location);
        }
      } else if (section == 'plugins') {
        // name = "plugin.id:1.2.3"
        final short =
            RegExp(r'^[\w.-]+\s*=\s*"([^":]+):([^"]+)"').firstMatch(line);
        if (short != null) {
          plugins[short.group(1)!] =
              (value: short.group(2)!, location: location);
          continue;
        }
        // name = { id = "plugin.id", version = "1.2.3" | version.ref = "key" }
        final id = RegExp(r'\bid\s*=\s*"([^"]+)"').firstMatch(line)?.group(1);
        if (id == null) continue;
        final literal = RegExp(r'\bversion\s*=\s*"([^"]+)"').firstMatch(line);
        final ref =
            RegExp(r'\bversion\.ref\s*=\s*"([^"]+)"').firstMatch(line) ??
                RegExp(r'\bversion\s*=\s*\{\s*ref\s*=\s*"([^"]+)"')
                    .firstMatch(line);
        if (literal != null) {
          plugins[id] = (value: literal.group(1)!, location: location);
        } else if (ref != null) {
          pluginRefs[id] = ref.group(1)!;
        }
      }
    }
    for (final MapEntry(key: id, value: key) in pluginRefs.entries) {
      final version = versions[key];
      if (version != null) plugins[id] = version;
    }
    return VersionCatalog._(versions, plugins);
  }

  final Map<String, ({String value, SourceLocation location})> _versions;
  final Map<String, ({String value, SourceLocation location})> _plugins;

  /// The version declared for plugin [id], located where it should be edited.
  ({String value, SourceLocation location})? pluginVersion(String id) =>
      _plugins[id];

  /// A `[versions]` entry.
  ({String value, SourceLocation location})? version(String key) =>
      _versions[key];
}
