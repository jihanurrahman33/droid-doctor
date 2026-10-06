import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/finding.dart';
import '../model/project_snapshot.dart';
import '../model/version.dart';
import 'source_text.dart';
import 'version_catalog.dart';

/// Thrown when a directory does not contain a Flutter Android project.
final class ProjectNotFoundException implements Exception {
  const ProjectNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _agpIds = ['com.android.application', 'com.android.library'];
const _kgpId = 'org.jetbrains.kotlin.android';

/// Reads a Flutter project's `android/` build files into a [ProjectSnapshot].
/// Never writes or executes anything.
final class AndroidScanner {
  const AndroidScanner();

  /// Scans [projectPath], which may be the Flutter project root or its
  /// `android/` directory. [flutter] and [java] come from the environment.
  ProjectSnapshot scan(
    String projectPath, {
    Detected<Version>? flutter,
    Detected<Version>? java,
  }) {
    final root = p.normalize(p.absolute(projectPath));
    final android = _androidDir(root);
    final projectRoot = android == root ? p.dirname(root) : root;

    SourceText? read(String relative) {
      final file = File(p.join(android, relative));
      if (!file.existsSync()) return null;
      final display = p.relative(file.path, from: projectRoot);
      return SourceText(display, file.readAsStringSync());
    }

    SourceText? readFirst(List<String> candidates) {
      for (final c in candidates) {
        final text = read(c);
        if (text != null) return text;
      }
      return null;
    }

    final settings = readFirst(['settings.gradle.kts', 'settings.gradle']);
    final rootBuild = readFirst(['build.gradle.kts', 'build.gradle']);
    final appBuild = readFirst(['app/build.gradle.kts', 'app/build.gradle']);
    final wrapper = read('gradle/wrapper/gradle-wrapper.properties');
    final properties = read('gradle.properties');
    final catalogFile = File(p.join(android, 'gradle', 'libs.versions.toml'));
    final catalog = catalogFile.existsSync()
        ? VersionCatalog.parse(
            p.relative(catalogFile.path, from: projectRoot),
            catalogFile.readAsStringSync(),
          )
        : null;

    final buildFiles = [settings, rootBuild].nonNulls.toList();
    final agp = _pluginVersion(buildFiles, catalog, _agpIds,
        classpath: 'com.android.tools.build:gradle');
    final kgp = _pluginVersion(buildFiles, catalog, [_kgpId],
        classpath: 'org.jetbrains.kotlin:kotlin-gradle-plugin');

    final gradle = wrapper?.find([
      RegExp(
          r'^\s*distributionUrl\s*=\s*\S*?gradle-(\d[\w.-]*?)-(?:all|bin)\.zip',
          multiLine: true),
    ]);

    return ProjectSnapshot(
      projectPath: projectRoot,
      dsl: (settings ?? appBuild)?.relativePath.endsWith('.kts') ?? false
          ? Dsl.kotlin
          : Dsl.groovy,
      flutter: flutter,
      java: java,
      gradle: _version(gradle, Version.tryParse),
      agp: _version(agp, Version.tryParse),
      kgp: _version(kgp, Version.tryParse),
      pluginApplyStyle: _pluginApplyStyle(settings, appBuild),
      builtInKotlin: properties?.contains(RegExp(
            r'^\s*android\.builtInKotlin\s*=\s*true\s*$',
            multiLine: true,
          )) ??
          false,
      namespace: _detected(appBuild?.find([
        RegExp(r'''\bnamespace\s*=?\s*["']([^"']+)["']'''),
      ])),
      applicationId: _detected(appBuild?.find([
        RegExp(r'''\bapplicationId\s*=?\s*["']([^"']+)["']'''),
      ])),
      compileSdk: _version(
        appBuild?.find([RegExp(r'\bcompileSdk(?:Version)?\s*[=(]?\s*(\d+)\b')]),
        int.tryParse,
      ),
      minSdk: _version(
        appBuild?.find([RegExp(r'\bminSdk(?:Version)?\s*[=(]?\s*(\d+)\b')]),
        int.tryParse,
      ),
      javaTarget: _version(
        appBuild?.find([
          RegExp(
              r'\btargetCompatibility\s*=?\s*JavaVersion\.VERSION_(\d+(?:_\d+)?)'),
          RegExp(r'''\btargetCompatibility\s*=?\s*["']?(\d+(?:\.\d+)?)\b'''),
        ]),
        parseJavaVersion,
      ),
      kotlinJvmTarget: _version(
        appBuild?.find([
          RegExp(
              r'\bjvmTarget\s*(?:=|\.set\()\s*[\w.]*JvmTarget\.JVM_(\d+(?:_\d+)?)'),
          RegExp(
              r'\bjvmTarget\s*(?:=|\.set\()\s*JavaVersion\.VERSION_(\d+(?:_\d+)?)'),
          RegExp(r'''\bjvmTarget\s*(?:=|\.set\()\s*["'](\d+(?:\.\d+)?)["']'''),
          RegExp(r'\bjvmToolchain\s*\(?\s*(\d+)'),
        ]),
        parseJavaVersion,
      ),
      appBuildFile: appBuild?.relativePath,
    );
  }

  String _androidDir(String root) {
    bool hasSettings(String dir) =>
        File(p.join(dir, 'settings.gradle')).existsSync() ||
        File(p.join(dir, 'settings.gradle.kts')).existsSync();

    final nested = p.join(root, 'android');
    if (hasSettings(nested)) return nested;
    if (hasSettings(root)) return root;
    throw ProjectNotFoundException(
      'No Android project found in $root '
      '(expected android/settings.gradle or android/settings.gradle.kts).',
    );
  }

  /// Finds a plugin version declared via the `plugins {}` block, the version
  /// catalog, or a legacy `buildscript { classpath ... }` dependency.
  ({String value, SourceLocation location})? _pluginVersion(
    List<SourceText> files,
    VersionCatalog? catalog,
    List<String> ids, {
    required String classpath,
  }) {
    for (final id in ids) {
      final quoted = RegExp.escape(id);
      for (final file in files) {
        final match = file.find([
          RegExp(
              '''\\bid\\s*\\(?\\s*["']$quoted["']\\s*\\)?\\s*version\\s*\\(?\\s*["']([^"']+)["']'''),
        ]);
        if (match != null) return file.resolve(match);
      }
      final fromCatalog = catalog?.pluginVersion(id);
      if (fromCatalog != null) return fromCatalog;
    }
    final dependency = RegExp.escape(classpath);
    for (final file in files) {
      final match = file.find([RegExp('''["']$dependency:([^"']+)["']''')]);
      if (match != null) return file.resolve(match);
    }
    return null;
  }

  PluginApplyStyle _pluginApplyStyle(SourceText? settings, SourceText? app) {
    if (app?.contains(
            RegExp(r'''apply\s*\(?\s*from\s*[:=]\s*[^\n]*flutter\.gradle''')) ??
        false) {
      return PluginApplyStyle.legacyImperative;
    }
    if ((settings?.contains(RegExp(r'dev\.flutter\.flutter-plugin-loader')) ??
            false) ||
        (app?.contains(RegExp(r'dev\.flutter\.flutter-gradle-plugin')) ??
            false)) {
      return PluginApplyStyle.declarative;
    }
    return PluginApplyStyle.unknown;
  }

  static Detected<T>? _version<T>(
    ({String value, SourceLocation location})? found,
    T? Function(String) parse,
  ) {
    if (found == null) return null;
    final value = parse(found.value);
    return value == null ? null : Detected(value, location: found.location);
  }

  static Detected<String>? _detected(
    ({String value, SourceLocation location})? found,
  ) =>
      found == null ? null : Detected(found.value, location: found.location);
}
