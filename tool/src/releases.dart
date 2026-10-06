/// Parses upstream release listings into the matrix `releases` lists.
library;

import 'dart:convert';

import 'package:droid_doctor/droid_doctor.dart';

/// Final Gradle releases from https://services.gradle.org/versions/all.
List<String> parseGradleVersions(String json) => [
      for (final v
          in (jsonDecode(json) as List<Object?>).cast<Map<String, Object?>>())
        if (v['snapshot'] != true &&
            v['nightly'] != true &&
            v['releaseNightly'] != true &&
            v['broken'] != true &&
            (v['rcFor'] as String? ?? '').isEmpty &&
            (v['milestoneFor'] as String? ?? '').isEmpty &&
            RegExp(r'^\d+\.\d+(\.\d+)?$').hasMatch(v['version'] as String))
          v['version'] as String,
    ];

/// Stable `x.y.z` versions from a Maven `maven-metadata.xml`.
List<String> parseMavenMetadata(String xml) => [
      for (final m
          in RegExp(r'<version>(\d+\.\d+\.\d+)</version>').allMatches(xml))
        m[1]!,
    ];

/// Keeps the newest patch of each release line at or above [floor], so the
/// solver has one candidate per line. A line is `major.minor` — or, with
/// [kotlinStyle], `major.minor.(patch ~/ 10)`, because Kotlin ships language
/// releases as x.y.0 and tooling releases as x.y.20 with different
/// compatibility.
List<String> condenseReleases(
  Iterable<String> versions, {
  required String floor,
  bool kotlinStyle = false,
}) {
  final min = Version.parse(floor);
  final newest = <String, Version>{};
  for (final raw in versions) {
    final v = Version.tryParse(raw);
    if (v == null || v.isPreRelease || v < min) continue;
    final parts = raw.split('.').map(int.parse).toList();
    final patch = parts.length > 2 ? parts[2] : 0;
    final line = kotlinStyle
        ? '${parts[0]}.${parts[1]}.${patch ~/ 10}'
        : '${parts[0]}.${parts[1]}';
    if (newest[line] == null || v > newest[line]!) newest[line] = v;
  }
  return (newest.values.toList()..sort()).map((v) => '$v').toList();
}
