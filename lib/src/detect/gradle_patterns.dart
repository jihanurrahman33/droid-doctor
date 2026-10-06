/// Patterns for module build files (`build.gradle` / `build.gradle.kts`),
/// shared by the app scanner and the plugin auditor. Group 1 is the value.
abstract final class GradlePatterns {
  // No whitespace in the value, so `hasProperty('namespace')) {` never
  // matches as a namespace declaration.
  static final namespace = [
    RegExp(r'''\bnamespace\s*=?\s*["']([^"'\s]+)["']'''),
  ];

  static final applicationId = [
    RegExp(r'''\bapplicationId\s*=?\s*["']([^"'\s]+)["']'''),
  ];

  static final compileSdk = [
    RegExp(r'\bcompileSdk(?:Version)?\s*[=(]?\s*(\d+)\b'),
  ];

  static final minSdk = [
    RegExp(r'\bminSdk(?:Version)?\s*[=(]?\s*(\d+)\b'),
  ];

  static final javaTarget = [
    RegExp(r'\btargetCompatibility\s*=?\s*JavaVersion\.VERSION_(\d+(?:_\d+)?)'),
    RegExp(r'''\btargetCompatibility\s*=?\s*["']?(\d+(?:\.\d+)?)\b'''),
  ];

  static final kotlinJvmTarget = [
    RegExp(
        r'\bjvmTarget\s*(?:=|\.set\()\s*[\w.]*JvmTarget\.JVM_(\d+(?:_\d+)?)'),
    RegExp(
        r'\bjvmTarget\s*(?:=|\.set\()\s*JavaVersion\.VERSION_(\d+(?:_\d+)?)'),
    RegExp(r'''\bjvmTarget\s*(?:=|\.set\()\s*["'](\d+(?:\.\d+)?)["']'''),
    RegExp(r'\bjvmToolchain\s*\(?\s*(\d+)'),
  ];

  /// Applies the Kotlin Android plugin in any of its spellings.
  static final appliesKotlin = RegExp(
    r'''(?:apply\s+plugin\s*:\s*["']kotlin-android["']|\bid\s*\(?\s*["'](?:kotlin-android|org\.jetbrains\.kotlin\.android)["']|\bkotlin\s*\(\s*["']android["']\s*\))''',
  );

  static final jcenter = RegExp(r'\bjcenter\s*\(\s*\)');
}
