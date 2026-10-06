# droid_doctor

Finds and explains **Gradle, Android Gradle Plugin (AGP), Kotlin and JDK
version problems** in the Android build of Flutter projects, before
`flutter build apk` fails with a cryptic error.

```console
$ droid_doctor
droid_doctor 0.1.0  ·  data 2026-10-06  ·  ~/code/my_app

  Flutter  3.47.2     flutter --version
  JDK      17         flutter config --jdk-dir (...)
  Gradle   8.3        android/gradle/wrapper/gradle-wrapper.properties:5
  AGP      8.7.0      android/settings.gradle.kts:22
  KGP      1.9.0      android/settings.gradle.kts:23

error    Android Gradle Plugin 8.7.0 requires Gradle 8.9 or newer (found 8.3).
         at android/gradle/wrapper/gradle-wrapper.properties:5
         fix: Set distributionUrl to https\://services.gradle.org/distributions/gradle-8.9-all.zip
error    Flutter 3.47 requires Android Gradle Plugin 8.11.1 or newer (found 8.7.0).
         at android/settings.gradle.kts:22
         fix: Set the Android Gradle Plugin version to 9.1.0
...
```

## Install

```sh
dart pub global activate droid_doctor
```

## Usage

```sh
droid_doctor                      # check the project in the current directory
droid_doctor -p path/to/app       # check another project
droid_doctor --json               # machine-readable output
droid_doctor --ci                 # also fail (exit 1) on warnings
```

| Option | |
|---|---|
| `-p, --project` | Flutter project root or its `android/` directory (default `.`) |
| `--json` | JSON output |
| `--ci` | Exit 1 on warnings too; no colors |
| `--[no-]color` | Force colors on or off |
| `--flutter-version` | Skip running `flutter`; use this version |
| `--java-version` | Skip JDK detection; use this version |
| `--matrix` | Use a custom compatibility matrix JSON |

### Fixing

```sh
droid_doctor fix                  # show the changes, ask, then apply
droid_doctor fix --dry-run        # only show them
droid_doctor fix --yes            # apply without asking (CI/scripts)
droid_doctor fix --strategy latest  # upgrade to what `flutter create` uses
droid_doctor fix --undo           # restore the files the last fix changed
```

```console
Versions:
  Gradle  8.3 → 8.14
  AGP     8.7.0 → 8.11.1
  KGP     1.9.0 → 2.2.20

Changes:
  android/settings.gradle.kts:22  Upgrade Android Gradle Plugin 8.7.0 → 8.11.1
  - id("com.android.application") version "8.7.0" apply false
  + id("com.android.application") version "8.11.1" apply false
  ...
Apply 6 changes to 3 files? [y/N]
```

- **`minimal`** (default) makes the smallest upgrades that fix every error.
  **`latest`** moves to the newest known versions. Neither ever downgrades.
- Besides versions, `fix` adds a missing AGP 8 `namespace`, aligns the Kotlin
  `jvmTarget` with Java's, raises a too-low `minSdk`, and when crossing to
  AGP 9 keeps the pre-AGP 9 defaults in `gradle.properties` (as
  `flutter create` does).
- Every edit is a single, verified line change. If a declaration doesn't look
  exactly as expected, `fix` lists it as a **manual step** instead of
  guessing; the JDK is never changed for you.
- Changed files are backed up under `.dart_tool/droid_doctor/backups/` (already
  git-ignored in Flutter projects). `fix --undo` refuses to overwrite files you
  edited after the fix unless you add `--force`.
- Exit code: 0 when no errors remain afterwards, 1 otherwise.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | No errors (and no warnings with `--ci`) |
| 1 | Problems found |
| 2 | Usage error or no Android project found |
| 3 | Internal error — please report it |

## What it checks

- **JDK ↔ Gradle**: e.g. JDK 21 needs Gradle 8.4+.
- **AGP ↔ Gradle**: the minimum Gradle for each AGP release.
- **AGP ↔ JDK**: AGP 8+ needs JDK 17.
- **Kotlin Gradle Plugin ↔ Gradle / AGP**: Kotlin's supported ranges.
- **Flutter's own minimums**: the versions your Flutter release errors or
  warns on.
- **AGP 8 `namespace`**, **Java vs Kotlin JVM target** mismatches, a **JDK
  older than the JVM target**, and the deprecated
  **`apply from: flutter.gradle`** setup.

It reads Kotlin DSL and Groovy build files, Gradle version catalogs
(`libs.versions.toml`) and legacy `buildscript { classpath ... }` setups,
ignoring commented-out code. `check` never modifies your project.

The JDK is resolved the way Flutter resolves it: `flutter config --jdk-dir`,
then Android Studio's bundled JBR, then `JAVA_HOME`, then `java` on `PATH`.

## Compatibility data

The data lives in [`data/matrix.json`](data/matrix.json), with a source link on
every rule. It's bundled into the executable so checks work offline. After
editing it, run:

```sh
dart run tool/embed_matrix.dart
```

## Roadmap

- `explain`: turn a Gradle error log into a diagnosis and fix.
- `plugins`: find the dependencies that block an upgrade.
- Data that updates itself weekly from upstream sources.

## License

MIT
