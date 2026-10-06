import 'component.dart';
import 'finding.dart';
import 'version.dart';

enum Dsl { kotlin, groovy }

/// How the Flutter Gradle plugin is applied.
enum PluginApplyStyle {
  /// `plugins { id("dev.flutter.flutter-gradle-plugin") }` (Flutter 3.16+).
  declarative,

  /// `apply from: ".../flutter.gradle"` — deprecated and removed in newer
  /// Flutter versions.
  legacyImperative,
  unknown,
}

/// Everything droid_doctor knows about a project's Android build.
final class ProjectSnapshot {
  const ProjectSnapshot({
    required this.projectPath,
    required this.dsl,
    this.flutter,
    this.java,
    this.gradle,
    this.agp,
    this.kgp,
    this.pluginApplyStyle = PluginApplyStyle.unknown,
    this.builtInKotlin = false,
    this.namespace,
    this.compileSdk,
    this.minSdk,
    this.javaTarget,
    this.kotlinJvmTarget,
    this.appBuildFile,
  });

  final String projectPath;
  final Dsl dsl;
  final Detected<Version>? flutter;
  final Detected<Version>? java;
  final Detected<Version>? gradle;
  final Detected<Version>? agp;
  final Detected<Version>? kgp;
  final PluginApplyStyle pluginApplyStyle;

  /// AGP 9's built-in Kotlin support (`android.builtInKotlin=true`), which
  /// makes the separate Kotlin Gradle plugin unnecessary.
  final bool builtInKotlin;
  final Detected<String>? namespace;

  /// Literal values only; null when delegated to `flutter.compileSdkVersion`
  /// and friends.
  final Detected<int>? compileSdk;
  final Detected<int>? minSdk;

  /// `compileOptions { targetCompatibility }`.
  final Detected<Version>? javaTarget;

  /// The Kotlin `jvmTarget` or `jvmToolchain`.
  final Detected<Version>? kotlinJvmTarget;

  /// The app module build file, relative to [projectPath].
  final String? appBuildFile;

  Detected<Version>? version(Component component) => switch (component) {
        Component.java => java,
        Component.gradle => gradle,
        Component.agp => agp,
        Component.kgp => kgp,
      };

  Map<String, Object?> toJson() {
    Map<String, Object?>? entry<T>(Detected<T>? d) => d == null
        ? null
        : {
            'value': d.value.toString(),
            if (d.location != null) 'location': d.location!.toJson(),
            if (d.origin != null) 'origin': d.origin,
          };
    return {
      'path': projectPath,
      'dsl': dsl.name,
      'flutter': entry(flutter),
      for (final c in Component.values) c.name: entry(version(c)),
      'pluginApplyStyle': pluginApplyStyle.name,
      'builtInKotlin': builtInKotlin,
      'namespace': entry(namespace),
      'compileSdk': entry(compileSdk),
      'minSdk': entry(minSdk),
      'javaTarget': entry(javaTarget),
      'kotlinJvmTarget': entry(kotlinJvmTarget),
    };
  }
}
