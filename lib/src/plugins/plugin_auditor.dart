import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/compat_matrix.dart';
import '../detect/gradle_patterns.dart';
import '../detect/source_text.dart';
import '../model/finding.dart';
import '../model/project_snapshot.dart';
import '../model/version.dart';
import 'pub_client.dart';

/// A Flutter plugin with Android code, as resolved by `pub get`.
final class AndroidPlugin {
  const AndroidPlugin({
    required this.name,
    required this.rootPath,
    required this.buildFile,
    this.version,
  });

  final String name;
  final String rootPath;

  /// Absolute path of `android/build.gradle(.kts)`.
  final String buildFile;

  /// From the pub cache directory name (`camera-0.10.5`); null for path or
  /// git dependencies.
  final String? version;
}

/// The result of auditing one plugin.
final class PluginReport {
  const PluginReport._(this.plugin, this.findings, this.info);

  /// Builds a report, turning generic "upgrade" fixes into specific advice
  /// once pub.dev [info] is known: upgrade to a version, replace a
  /// discontinued plugin, or fork one with no newer release.
  factory PluginReport(
    AndroidPlugin plugin,
    List<Finding> findings, {
    PackageInfo? info,
  }) {
    final report = PluginReport._(plugin, findings, info);
    final advice = report._advice();
    if (advice == null) return report;
    final generic = PluginAuditor.upgradeFix(plugin);
    return PluginReport._(
      plugin,
      [
        for (final f in findings)
          f.fix == generic
              ? Finding(
                  ruleId: f.ruleId,
                  severity: f.severity,
                  message: f.message,
                  fix: advice,
                  location: f.location,
                  reference: f.reference,
                )
              : f,
      ],
      info,
    );
  }

  final AndroidPlugin plugin;
  final List<Finding> findings;

  /// From pub.dev, when looked up.
  final PackageInfo? info;

  String? get latestVersion => info?.latestVersion;

  String? _advice() {
    final info = this.info;
    if (info == null) return null;
    final name = plugin.name;
    if (info.isDiscontinued) {
      return '$name is discontinued; replace it with '
          '${info.replacedBy ?? 'a maintained plugin'}.';
    }
    if (hasNewerVersion) {
      return 'Upgrade $name to ${info.latestVersion} '
          '(`flutter pub upgrade $name`, raising its constraint in '
          'pubspec.yaml if needed).';
    }
    return 'No newer $name release on pub.dev: report it upstream, or use a '
        'patched fork via dependency_overrides.';
  }

  bool get hasNewerVersion =>
      latestVersion != null &&
      plugin.version != null &&
      latestVersion != plugin.version &&
      (Version.tryParse(latestVersion) == null ||
          Version.tryParse(plugin.version) == null ||
          Version.parse(latestVersion!) > Version.parse(plugin.version!));

  Severity? get worst => findings.isEmpty
      ? null
      : findings
          .map((f) => f.severity)
          .reduce((a, b) => a.index < b.index ? a : b);

  Map<String, Object?> toJson() => {
        'name': plugin.name,
        'version': plugin.version,
        'path': plugin.rootPath,
        if (latestVersion != null) 'latestVersion': latestVersion,
        if (info?.isDiscontinued ?? false) 'discontinued': true,
        if (info?.replacedBy != null) 'replacedBy': info!.replacedBy,
        'findings': [for (final f in findings) f.toJson()],
      };
}

/// Thrown when the project has no resolved dependencies.
final class PackagesNotResolvedException implements Exception {
  const PackagesNotResolvedException(this.projectPath);

  final String projectPath;

  @override
  String toString() => 'No .dart_tool/package_config.json in $projectPath. '
      'Run `flutter pub get` first.';
}

/// Finds the project's Android plugins via `.dart_tool/package_config.json`.
List<AndroidPlugin> findAndroidPlugins(String projectPath) {
  final config = File(p.join(projectPath, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) throw PackagesNotResolvedException(projectPath);
  final json = jsonDecode(config.readAsStringSync());
  if (json is! Map<String, Object?> || json['packages'] is! List<Object?>) {
    throw FormatException('Unexpected format in ${config.path}');
  }
  final base = Uri.directory(config.parent.path);
  final projectRoot = p.normalize(p.absolute(projectPath));
  final plugins = <AndroidPlugin>[];
  for (final entry in (json['packages'] as List<Object?>)
      .whereType<Map<String, Object?>>()) {
    final name = entry['name'], rootUri = entry['rootUri'];
    if (name is! String || rootUri is! String) continue;
    final root = p.normalize(base.resolve(rootUri).toFilePath());
    if (p.equals(root, projectRoot)) continue;
    final buildFile = [
      p.join(root, 'android', 'build.gradle.kts'),
      p.join(root, 'android', 'build.gradle'),
    ].where((f) => File(f).existsSync()).firstOrNull;
    if (buildFile == null) continue;
    final dirVersion = RegExp('^${RegExp.escape(name)}-(\\d[\\w.+-]*)\$')
        .firstMatch(p.basename(root))
        ?.group(1);
    plugins.add(AndroidPlugin(
      name: name,
      rootPath: root,
      buildFile: buildFile,
      version: dirVersion,
    ));
  }
  plugins.sort((a, b) => a.name.compareTo(b.name));
  return plugins;
}

/// Checks a plugin's Android build against the app's settings.
final class PluginAuditor {
  const PluginAuditor(this.project, this.matrix);

  final ProjectSnapshot project;
  final CompatMatrix matrix;

  static final _agp8 = Version.parse('8.0');

  /// The app's effective minSdk/compileSdk: literal values, or what Flutter's
  /// `flutter.minSdkVersion` / `flutter.compileSdkVersion` resolve to.
  int? get appMinSdk => project.minSdk?.value ?? _template('minSdk');
  int? get appCompileSdk =>
      project.compileSdk?.value ?? _template('compileSdk');

  int? _template(String key) {
    final flutter = project.flutter?.value;
    final requirements =
        flutter == null ? null : matrix.requirementsFor(flutter);
    return int.tryParse(requirements?.template[key] ?? '');
  }

  List<Finding> audit(AndroidPlugin plugin) {
    final display = '${plugin.name}/android/${p.basename(plugin.buildFile)}';
    final source =
        SourceText(display, File(plugin.buildFile).readAsStringSync());
    final findings = <Finding>[];
    void add(String id, Severity severity, String message, String fix,
            [SourceLocation? location]) =>
        findings.add(Finding(
          ruleId: 'plugin-$id',
          severity: severity,
          message: message,
          fix: fix,
          location: location ?? SourceLocation(display, 1),
        ));

    final agp = project.agp?.value;
    if (agp != null &&
        agp >= _agp8 &&
        source.find(GradlePatterns.namespace) == null) {
      add(
          'namespace',
          Severity.error,
          'No namespace; AGP $agp fails with "Namespace not specified".',
          upgradeFix(plugin));
    }

    final minSdk = source.find(GradlePatterns.minSdk);
    final appMin = appMinSdk;
    if (minSdk != null && appMin != null && int.parse(minSdk.value) > appMin) {
      add(
          'min-sdk',
          Severity.error,
          'Requires minSdk ${minSdk.value}, but the app uses $appMin; the '
              'manifest merger fails.',
          'Raise minSdk in ${project.appBuildFile ?? 'android/app/build.gradle'} '
              'to ${minSdk.value}.',
          minSdk.location);
    }

    final compileSdk = source.find(GradlePatterns.compileSdk);
    final appCompile = appCompileSdk;
    if (compileSdk != null &&
        appCompile != null &&
        int.parse(compileSdk.value) > appCompile) {
      add(
          'compile-sdk',
          Severity.warning,
          'Compiles against Android SDK ${compileSdk.value}, higher than the '
              "app's $appCompile.",
          'Raise compileSdk in ${project.appBuildFile ?? 'android/app/build.gradle'} '
              'to ${compileSdk.value}.',
          compileSdk.location);
    }

    if (source.contains(GradlePatterns.appliesKotlin)) {
      _jvmTargets(plugin, source, add);
      if (project.builtInKotlin) {
        add(
            'built-in-kotlin',
            Severity.warning,
            "Applies the Kotlin Android plugin, which AGP 9's built-in Kotlin "
                'replaces.',
            'If the build fails, set android.builtInKotlin=false in '
                'android/gradle.properties (as flutter create does).');
      }
    }

    if (source.contains(GradlePatterns.jcenter)) {
      add(
          'jcenter',
          Severity.warning,
          'Uses the jcenter() repository, which is read-only and unreliable.',
          upgradeFix(plugin));
    }
    return findings;
  }

  void _jvmTargets(
    AndroidPlugin plugin,
    SourceText source,
    void Function(String, Severity, String, String, [SourceLocation?]) add,
  ) {
    final java = source.find(GradlePatterns.javaTarget);
    final kotlin = source.find(GradlePatterns.kotlinJvmTarget);
    final javaVersion = parseJavaVersion(java?.value);
    if (java == null || javaVersion == null) return;
    if (kotlin != null) {
      final kotlinVersion = parseJavaVersion(kotlin.value);
      if (kotlinVersion != null && kotlinVersion.major != javaVersion.major) {
        add(
            'jvm-target',
            Severity.warning,
            'Java targets JVM ${javaVersion.major} but Kotlin targets JVM '
                '${kotlinVersion.major}; can fail with "Inconsistent JVM-target '
                'compatibility".',
            upgradeFix(plugin),
            kotlin.location);
      }
      return;
    }
    // Without an explicit jvmTarget, Kotlin targets the JDK running Gradle.
    final jdk = project.java?.value.major;
    if (jdk != null && jdk != javaVersion.major) {
      add(
          'jvm-target',
          Severity.warning,
          'Java targets JVM ${javaVersion.major} and Kotlin defaults to the JDK '
              '($jdk); can fail with "Inconsistent JVM-target compatibility".',
          upgradeFix(plugin),
          java.location);
    }
  }

  /// The generic fix, refined by [PluginReport] once pub.dev is consulted.
  static String upgradeFix(AndroidPlugin plugin) =>
      'Upgrade ${plugin.name} (`flutter pub upgrade ${plugin.name}`, raising '
      'its constraint in pubspec.yaml if needed).';
}
