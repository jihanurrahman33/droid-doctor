## 0.1.0

- Initial release: `droid_doctor check`.
- Detects Flutter, JDK, Gradle, Android Gradle Plugin and Kotlin Gradle Plugin
  versions from Kotlin DSL, Groovy, version catalogs and legacy `buildscript`
  setups.
- Checks JDK↔Gradle, AGP↔Gradle, AGP↔JDK, KGP↔Gradle and KGP↔AGP
  compatibility, Flutter 3.47's minimums, AGP 8 `namespace`, JVM target
  mismatches and the deprecated `apply from: flutter.gradle` style.
- Human and `--json` output; `--ci` fails on warnings.
