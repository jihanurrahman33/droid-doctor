## 0.3.0

- New `droid_doctor explain <log | ->`: recognizes 23 common Gradle, AGP,
  Kotlin, JDK, SDK and Flutter build errors and explains the cause and fix,
  using the versions in the log. Tested against real `flutter build` logs.
  Pipe a build straight in: `flutter build apk 2>&1 | droid_doctor explain -`.
- New `droid_doctor plugins`: audits every Android plugin the app depends on
  for missing AGP 8 namespaces, higher minSdk/compileSdk than the app,
  Java/Kotlin JVM target mismatches, `jcenter()`, and Kotlin plugins under
  AGP built-in Kotlin. Looks up pub.dev for newer versions and discontinued
  packages' replacements (`--offline` to skip).

## 0.2.0

- New `droid_doctor fix` command: picks compatible Gradle, AGP and Kotlin
  versions and applies them as verified single-line edits.
  - `--strategy minimal` (default) makes the smallest upgrades that fix the
    errors; `--strategy latest` moves to what `flutter create` generates.
    Never downgrades.
  - Also adds a missing AGP 8 `namespace`, aligns the Kotlin `jvmTarget` with
    Java, raises a too-low `minSdk`, and keeps pre-AGP 9 defaults in
    `gradle.properties` when crossing to AGP 9, as `flutter create` does.
  - Shows a diff and asks before writing (`--yes` to skip, `--dry-run` to
    only show it). Anything it can't change safely becomes a manual step.
  - Backs up every changed file under `.dart_tool/droid_doctor/backups/`;
    `fix --undo` restores the last fix and refuses to overwrite files edited
    since (`--force` to override).
- The compatibility matrix now lists known releases per component.

## 0.1.0

- Initial release: `droid_doctor check`.
- Detects Flutter, JDK, Gradle, Android Gradle Plugin and Kotlin Gradle Plugin
  versions from Kotlin DSL, Groovy, version catalogs and legacy `buildscript`
  setups.
- Checks JDK↔Gradle, AGP↔Gradle, AGP↔JDK, KGP↔Gradle and KGP↔AGP
  compatibility, Flutter 3.47's minimums, AGP 8 `namespace`, JVM target
  mismatches and the deprecated `apply from: flutter.gradle` style.
- Human and `--json` output; `--ci` fails on warnings.
