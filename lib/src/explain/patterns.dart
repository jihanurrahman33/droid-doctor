/// Builds diagnosis text from a match and the whole (ANSI-stripped) log.
typedef DiagnosisText = String Function(RegExpMatch match, String log);

/// A known build error: how to recognize it and what it means.
final class ErrorPattern {
  ErrorPattern(
    this.id,
    String pattern, {
    required this.title,
    required this.cause,
    required this.fix,
    this.reference,
    bool fixable = false,
    bool Function(RegExpMatch match, String log)? fixableWhen,
  })  : regex = RegExp(pattern, multiLine: true, caseSensitive: false),
        isFixable = fixableWhen ?? ((_, __) => fixable);

  final String id;
  final RegExp regex;
  final DiagnosisText title;
  final DiagnosisText cause;
  final DiagnosisText fix;
  final String? reference;

  /// Whether `droid_doctor fix` can resolve this occurrence.
  final bool Function(RegExpMatch match, String log) isFixable;
}

/// Whether the error comes from the app module (or no module is named),
/// as opposed to a plugin — `fix` only edits the app.
bool _inApp(RegExpMatch m, String log) {
  final project = _projectBefore(m, log);
  return project == null || project == ':app';
}

/// `:camera_android` → `camera_android` (Flutter names plugin subprojects
/// after their package).
String _package(String project) => project.substring(1);

/// Java class-file major version → Java release (`65` → `21`).
int _javaForClassVersion(String major) => int.parse(major) - 44;

/// The Gradle project being configured when [match] occurred, e.g. `:camera`.
String? _projectBefore(RegExpMatch match, String log) {
  final before = log.substring(0, match.start);
  // "A problem occurred configuring project ':camera'." or
  // "Execution failed for task ':app:compileDebugKotlin'." (project = task
  // path without the task name).
  final projects = RegExp(
    r"(?:(?:configuring|evaluating) project '(:[^']+)'|"
    r"Execution failed for task '(:[^']+):[^':]+')",
  ).allMatches(before);
  if (projects.isEmpty) return null;
  return projects.last.group(1) ?? projects.last.group(2);
}

String _module(RegExpMatch m, String log) {
  final project = _projectBefore(m, log);
  return project == null ? 'A module' : 'Module $project';
}

const _jdkHint = 'Point Flutter at a suitable JDK with '
    '`flutter config --jdk-dir=<path-to-jdk>` (check it with `flutter doctor -v`).';

/// The pattern library, most specific first. Each pattern quotes the error
/// text it matches in a test.
final errorPatterns = <ErrorPattern>[
  ErrorPattern(
    'agp-min-gradle',
    r'Minimum supported Gradle version is (\S+?)\.? Current version is (\S+?)\.?(?:\s|$)',
    title: (m, _) => 'Gradle ${m[2]} is too old for this Android Gradle Plugin',
    cause: (m, _) => 'The Android Gradle Plugin needs Gradle ${m[1]} or newer, '
        'but the wrapper uses ${m[2]}.',
    fix: (m, _) => 'Set distributionUrl in '
        'android/gradle/wrapper/gradle-wrapper.properties to gradle-${m[1]}-all.zip '
        '(or newer).',
    reference:
        'https://developer.android.com/build/releases/gradle-plugin#updating-gradle',
    fixable: true,
  ),
  ErrorPattern(
    'class-file-version',
    r'Unsupported class file major version (\d+)',
    title: (m, _) => 'Gradle cannot run on Java ${_javaForClassVersion(m[1]!)}',
    cause: (m, _) => 'Gradle (or a Groovy build script) was started with JDK '
        '${_javaForClassVersion(m[1]!)}, which is newer than this Gradle '
        'version supports.',
    fix: (m, _) => 'Upgrade Gradle (run `droid_doctor fix`), or use an older '
        'JDK. $_jdkHint',
    reference:
        'https://docs.gradle.org/current/userguide/compatibility.html#java',
    fixable: true,
  ),
  ErrorPattern(
    'gradle-java-incompatible',
    r'configured to use (?:incompatible )?Java (\S+?) and Gradle (\S+?)[.,]?(?:\s|$)',
    title: (m, _) => 'Java ${m[1]} and Gradle ${m[2]} are incompatible',
    cause: (m, _) => 'Gradle ${m[2]} does not support running on Java ${m[1]}.',
    fix: (m, _) => 'Upgrade Gradle (run `droid_doctor fix`), or use an older '
        'JDK. $_jdkHint',
    reference:
        'https://docs.gradle.org/current/userguide/compatibility.html#java',
    fixable: true,
  ),
  ErrorPattern(
    'flutter-gradle-java-incompatible',
    r"Your project's Gradle version is incompatible with the Java version",
    title: (_, __) => "Gradle and Flutter's JDK are incompatible",
    cause: (_, __) => 'The JDK Flutter uses for Gradle is newer than the '
        "project's Gradle version supports.",
    fix: (_, __) => 'Run `droid_doctor fix` to upgrade Gradle, or use an older '
        'JDK. $_jdkHint',
    reference:
        'https://docs.flutter.dev/release/breaking-changes/android-java-gradle-migration-guide',
    fixable: true,
  ),
  ErrorPattern(
    'gradle-cache-jdk',
    r'Could not open cp_settings generic class cache',
    title: (_, __) => 'Gradle is too old for the JDK',
    cause: (_, __) => "Gradle's Groovy compiler failed on a JDK newer than "
        'this Gradle version supports.',
    fix: (_, __) => 'Run `droid_doctor fix` to upgrade Gradle, or use an older '
        'JDK. $_jdkHint',
    fixable: true,
  ),
  ErrorPattern(
    'agp-requires-java',
    r'Android Gradle plugin requires Java (\d+) to run\. You are currently using Java (\S+?)\.?(?:\s|$)',
    title: (m, _) => 'The Android Gradle Plugin needs Java ${m[1]}',
    cause: (m, _) => 'Gradle runs on Java ${m[2]}, but this AGP version '
        'requires Java ${m[1]}.',
    fix: (m, _) => 'Install JDK ${m[1]} and use it for Gradle. $_jdkHint',
    reference: 'https://developer.android.com/build/jdks',
  ),
  ErrorPattern(
    'jvm-target-mismatch',
    r"Inconsistent JVM[- ]Target compatibility detected for tasks '([^']+)' \(([\d.]+)\) and '([^']+)' \(([\d.]+)\)",
    title: (m, _) => 'Java targets JVM ${m[2]} but Kotlin targets JVM ${m[4]}',
    cause: (m, log) => '${_module(m, log)} compiles Java (${m[1]}) and Kotlin '
        '(${m[3]}) for different JVM versions.',
    fix: (m, log) => _inApp(m, log)
        ? 'Use the same version for targetCompatibility and jvmTarget in '
            'android/app/build.gradle (run `droid_doctor fix`).'
        : 'The plugin ${_package(_projectBefore(m, log)!)} sets mismatched '
            'targets. Upgrade it (see `droid_doctor plugins`), or align the '
            'targets for all subprojects in android/build.gradle.',
    reference: 'https://kotl.in/gradle/jvm/target-validation',
    fixableWhen: _inApp,
  ),
  ErrorPattern(
    'missing-namespace',
    r'Namespace not specified',
    title: (m, log) => '${_module(m, log)} has no namespace',
    cause: (_, __) => 'Android Gradle Plugin 8+ requires every module to '
        'declare `namespace` in its build file.',
    fix: (m, log) => _inApp(m, log)
        ? 'Add namespace to android/app/build.gradle (run `droid_doctor fix`).'
        : 'Upgrade or replace the plugin ${_package(_projectBefore(m, log)!)}; '
            '`droid_doctor plugins` shows newer or replacement packages.',
    reference:
        'https://developer.android.com/build/configure-app-module#set-namespace',
    fixableWhen: _inApp,
  ),
  ErrorPattern(
    'manifest-package',
    r'Incorrect package="([^"]+)" found in source AndroidManifest\.xml',
    title: (m, _) => 'AndroidManifest.xml still sets package="${m[1]}"',
    cause: (_, __) => 'AGP 8+ takes the package from `namespace`; the '
        'manifest attribute is no longer allowed.',
    fix: (_, __) => 'Remove package="..." from the <manifest> tag and make '
        'sure namespace is set in the module build file.',
    reference:
        'https://developer.android.com/build/configure-app-module#set-namespace',
  ),
  ErrorPattern(
    'kotlin-metadata',
    r'compiled with an incompatible version of Kotlin\. The binary version of its metadata is (\S+?), expected version is (\S+?)\.?(?:\s|$)',
    title: (m, _) => 'Kotlin Gradle Plugin is too old (needs ${m[1]})',
    cause: (m, _) => 'A dependency was built with Kotlin ${m[1]}, but the '
        'project compiles with Kotlin ${m[2]}.',
    fix: (m, _) => 'Upgrade the Kotlin Gradle Plugin to ${m[1]} or newer '
        '(run `droid_doctor fix`).',
    fixable: true,
  ),
  ErrorPattern(
    'agp-min-kgp',
    r'The Android Gradle plugin supports only Kotlin Gradle plugin version (\S+?) and higher',
    title: (m, _) => 'Kotlin Gradle Plugin must be ${m[1]} or newer',
    cause: (m, _) => 'This AGP version does not support Kotlin Gradle Plugin '
        'versions below ${m[1]}.',
    fix: (m, _) => 'Upgrade the Kotlin Gradle Plugin (run `droid_doctor fix`).',
    fixable: true,
  ),
  ErrorPattern(
    'kotlin-duplicate-class',
    r'Duplicate class (kotlin\.\S+) found in modules',
    title: (_, __) => 'Duplicate Kotlin standard library classes',
    cause: (_, __) => 'Kotlin 1.8 merged kotlin-stdlib-jdk7/jdk8 into '
        'kotlin-stdlib; an old Kotlin Gradle Plugin pulls in both.',
    fix: (_, __) => 'Upgrade the Kotlin Gradle Plugin to 1.8 or newer '
        '(run `droid_doctor fix`).',
    fixable: true,
  ),
  ErrorPattern(
    'min-sdk-library',
    r'uses-sdk:minSdkVersion (\d+) cannot be smaller than version (\d+) declared in library \[([^\]]+)\]',
    title: (m, _) => 'minSdk ${m[1]} is lower than ${m[3]} needs (${m[2]})',
    cause: (m, _) => 'The library ${m[3]} requires minSdk ${m[2]}.',
    fix: (m, _) =>
        'Set minSdk = ${m[2]} (or higher) in android/app/build.gradle.',
  ),
  ErrorPattern(
    'compile-sdk-dependency',
    r"Dependency '([^']+)' requires (?:libraries and applications that\s+depend on it to )?compile against version (\d+) or later of the\s+Android APIs",
    title: (m, _) => 'compileSdk must be ${m[2]} or higher',
    cause: (m, _) => 'The dependency ${m[1]} was built against Android API '
        '${m[2]}.',
    fix: (m, _) =>
        'Set compileSdk = ${m[2]} (or flutter.compileSdkVersion on a '
        'recent Flutter) in android/app/build.gradle.',
    reference: 'https://developer.android.com/build/releases/gradle-plugin',
  ),
  ErrorPattern(
    'compile-sdk-plugins',
    r'configured to compile against Android SDK (\d+), but the following plugin\(s\) require to be compiled against a higher Android SDK version',
    title: (m, _) => 'Plugins need a compileSdk higher than ${m[1]}',
    cause: (_, __) => 'Some plugins are compiled against a newer Android SDK '
        'than the app.',
    fix: (_, __) => 'Raise compileSdk in android/app/build.gradle to the '
        'highest version Flutter lists (or use flutter.compileSdkVersion).',
  ),
  ErrorPattern(
    'v1-embedding',
    r'Build failed due to use of deleted Android v1 embedding',
    title: (_, __) => 'The app uses the removed Android v1 embedding',
    cause: (_, __) => 'MainActivity or AndroidManifest.xml still uses '
        'FlutterApplication / the v1 embedding, which Flutter removed.',
    fix: (_, __) => 'Migrate MainActivity to io.flutter.embedding.android.'
        'FlutterActivity and remove FlutterApplication from the manifest.',
    reference:
        'https://docs.flutter.dev/release/breaking-changes/plugin-api-migration',
  ),
  ErrorPattern(
    'sdk-location',
    r'SDK location not found',
    title: (_, __) => 'Android SDK not found',
    cause: (_, __) => 'Neither ANDROID_HOME nor sdk.dir in '
        'android/local.properties points to an Android SDK.',
    fix: (_, __) => 'Run `flutter config --android-sdk <path>` or set '
        'ANDROID_HOME, then `flutter doctor`.',
  ),
  ErrorPattern(
    'sdk-licenses',
    r'(?:You have not accepted the license agreements|License for package .+? not accepted)',
    title: (_, __) => 'Android SDK licenses not accepted',
    cause: (_, __) => 'Gradle tried to install an SDK component whose '
        'license has not been accepted.',
    fix: (_, __) => 'Run `flutter doctor --android-licenses`.',
  ),
  ErrorPattern(
    'ndk',
    r'(?:No version of NDK matched the requested version (\S+)|NDK .+?did not have a source\.properties file)',
    title: (m, _) => m[1] == null
        ? 'The NDK installation is broken'
        : 'NDK ${m[1]} is not installed',
    cause: (_, __) => 'The NDK version the build requests is missing or '
        'incomplete.',
    fix: (m, _) => m[1] == null
        ? 'Delete the broken NDK folder under <android-sdk>/ndk and rebuild.'
        : 'Install it with `sdkmanager "ndk;${m[1]}"` (or let the build '
            'install it after accepting licenses).',
  ),
  ErrorPattern(
    'out-of-memory',
    r'(?:java\.lang\.OutOfMemoryError|Java heap space|OutOfMemoryError: Metaspace)',
    title: (_, __) => 'Gradle ran out of memory',
    cause: (_, __) => 'The Gradle daemon heap or metaspace is too small for '
        'this build.',
    fix: (_, __) =>
        'Raise org.gradle.jvmargs in android/gradle.properties, e.g. '
        '-Xmx4G -XX:MaxMetaspaceSize=1G.',
  ),
  ErrorPattern(
    'plugin-not-found',
    r"Plugin \[id: '([^']+)'(?:, version: '([^']+)')?[^\]]*\] was not found",
    title: (m, _) => 'Gradle plugin ${m[1]} not found',
    cause: (m, _) => m[2] == null
        ? 'Gradle could not resolve the plugin ${m[1]}.'
        : 'Gradle could not resolve ${m[1]} version ${m[2]}; the version may '
            'not exist or the repositories are missing.',
    fix: (m, _) => m[1]!.startsWith('dev.flutter.')
        ? 'Check that android/local.properties has flutter.sdk and that '
            'settings.gradle includes the Flutter SDK gradle build.'
        : 'Check the version exists and that pluginManagement { repositories '
            '{ google(); mavenCentral(); gradlePluginPortal() } } is set.',
  ),
  ErrorPattern(
    'jcenter',
    r'(?:jcenter\.bintray\.com|Could not find .+?jcenter)',
    title: (_, __) => 'The build still uses JCenter',
    cause: (_, __) => 'JCenter is read-only and unreliable; artifacts can fail '
        'to download.',
    fix: (_, __) => 'Replace jcenter() with mavenCentral() in the build files, '
        'and upgrade plugins that still use it (see `droid_doctor plugins`).',
  ),
  ErrorPattern(
    'dependency-not-found',
    r'Could not find ([\w.-]+:[\w.-]+:[\w.+-]+)\.',
    title: (m, _) => 'Dependency ${m[1]} not found',
    cause: (_, __) => 'No configured repository has this artifact (wrong '
        'version, missing repository, or a network problem).',
    fix: (_, __) => 'Check the version exists, that google() and '
        'mavenCentral() are in the repositories, and your network/proxy.',
  ),
];
