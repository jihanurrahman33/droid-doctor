/// Extracts what each Flutter release requires of Android builds from the
/// Flutter repository at that release's tag.
library;

/// Reads `path` at git `tag` of the Flutter repository; null if missing.
typedef FlutterFileReader = Future<String?> Function(String tag, String path);

const _gradleUtils = 'packages/flutter_tools/lib/src/android/gradle_utils.dart';

/// The version checker moved twice; newest location first.
const _checkerPaths = [
  'packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt',
  'packages/flutter_tools/gradle/src/main/kotlin_scripts/dependency_version_checker.gradle.kts',
  'packages/flutter_tools/gradle/src/main/kotlin/dependency_version_checker.gradle.kts',
];

/// Where `flutter.compileSdkVersion` / `flutter.minSdkVersion` are defined.
const _extensionPaths = [
  'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt',
  'packages/flutter_tools/gradle/src/main/groovy/FlutterExtension.groovy',
  'packages/flutter_tools/gradle/src/main/groovy/flutter.groovy',
];

/// Stable release tags (`3.47.6`, not `3.48.0-0.5.pre`), latest patch per
/// minor, from 3.[minMinor] on. Minors with a single `.0` tag that aren't the
/// newest (3.1.0, 3.12.0) were never stable releases and are skipped.
List<String> latestStablePerMinor(Iterable<String> tags, {int minMinor = 10}) {
  final byMinor = <int, List<int>>{};
  for (final tag in tags) {
    final m = RegExp(r'^3\.(\d+)\.(\d+)$').firstMatch(tag);
    if (m == null) continue;
    (byMinor[int.parse(m[1]!)] ??= []).add(int.parse(m[2]!));
  }
  if (byMinor.isEmpty) return const [];
  final newest = byMinor.keys.reduce((a, b) => a > b ? a : b);
  return [
    for (final minor in byMinor.keys.toList()..sort())
      if (minor >= minMinor && (byMinor[minor]!.length > 1 || minor == newest))
        '3.$minor.${byMinor[minor]!.reduce((a, b) => a > b ? a : b)}',
  ];
}

/// The matrix `flutter` entry for [tag], or null if the templates can't be
/// found (very old releases).
Future<Map<String, Object?>?> extractFlutterRequirements(
  String tag,
  FlutterFileReader read,
) async {
  final utils = await read(tag, _gradleUtils);
  if (utils == null) return null;
  String? constant(String name) =>
      RegExp("const (?:String )?$name = '([^']+)'").firstMatch(utils)?[1];
  final template = <String, Object?>{
    if (constant('templateDefaultGradleVersion') case final v?) 'gradle': v,
    if (constant('templateAndroidGradlePluginVersion') case final v?) 'agp': v,
    if (constant('templateKotlinGradlePluginVersion') case final v?) 'kgp': v,
  };
  if (template.isEmpty) return null;

  final extension = await _firstExisting(tag, _extensionPaths, read);
  if (extension != null) {
    int? sdk(String name) => int.tryParse(RegExp(
          '(?:val|int)\\s+$name\\s*(?::\\s*Int)?\\s*=\\s*(\\d+)',
        ).firstMatch(extension)?[1] ??
        '');
    if (sdk('compileSdkVersion') case final v?) template['compileSdk'] = v;
    if (sdk('minSdkVersion') case final v?) template['minSdk'] = v;
  }

  final error = <String, Object?>{}, warn = <String, Object?>{};
  final checker = await _firstExisting(tag, _checkerPaths, read);
  if (checker != null) {
    for (final m in RegExp(
      r'val (warn|error)(Gradle|AGP|KGP)Version\s*:\s*\w+\s*=\s*\w+\((\d+),\s*(\d+),\s*(\d+)\)',
    ).allMatches(checker)) {
      final version = '${m[3]}.${m[4]}.${m[5]}';
      if (version == '0.0.0') continue; // "No minimum".
      (m[1] == 'warn' ? warn : error)[m[2]!.toLowerCase()] = version;
    }
    for (final m in RegExp(
      r'val (warn|error)JavaVersion\s*:\s*\w+\s*=\s*JavaVersion\.VERSION_(\d+)(?:_(\d+))?',
    ).allMatches(checker)) {
      // VERSION_1_8 -> 8; VERSION_1_1 is Flutter's "no minimum".
      final major = m[2] == '1' ? int.parse(m[3] ?? '0') : int.parse(m[2]!);
      if (major <= 1) continue;
      (m[1] == 'warn' ? warn : error)['java'] = '$major';
    }
    for (final m
        in RegExp(r'val (warn|error)MinSdkVersion\s*:\s*Int\s*=\s*(\d+)')
            .allMatches(checker)) {
      final sdk = int.parse(m[2]!);
      if (sdk <= 1) continue; // Flutter's "no minimum".
      (m[1] == 'warn' ? warn : error)['minSdk'] = sdk;
    }
  }

  final minor = RegExp(r'^(\d+\.\d+)').firstMatch(tag)![1]!;
  return {
    'version': minor,
    'tag': tag,
    'error': _ordered(error),
    'warn': _ordered(warn),
    'template': _ordered(template),
  };
}

/// The compatibility-table code in gradle_utils.dart (the `validate*`
/// functions and compat lists), for detecting upstream changes that need a
/// human to update the matrix rules.
Future<List<String>?> compatibilityCode(
    String tag, FlutterFileReader read) async {
  final utils = await read(tag, _gradleUtils);
  if (utils == null) return null;
  final start = utils.indexOf('bool validateGradleAndKGP');
  if (start == -1) return null;
  return [
    for (final line in utils.substring(start).split('\n'))
      if (line.trim().isNotEmpty && !line.trim().startsWith('//')) line.trim(),
  ];
}

Future<String?> _firstExisting(
    String tag, List<String> paths, FlutterFileReader read) async {
  for (final path in paths) {
    final content = await read(tag, path);
    if (content != null) return content;
  }
  return null;
}

const _keyOrder = ['java', 'gradle', 'agp', 'kgp', 'compileSdk', 'minSdk'];

Map<String, Object?> _ordered(Map<String, Object?> m) => {
      for (final k in _keyOrder)
        if (m.containsKey(k)) k: m[k],
    };
