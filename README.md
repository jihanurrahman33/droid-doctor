# droid_doctor

Finds, explains and fixes **Gradle, Android Gradle Plugin (AGP), Kotlin and JDK
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
droid_doctor fix --strategy latest  # newest versions with known compatibility
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
  **`latest`** moves to the newest versions the compatibility data covers.
  Neither ever downgrades.
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

### Explaining a failed build

```sh
flutter build apk 2>&1 | droid_doctor explain -
droid_doctor explain build.log
```

```console
1. Module :uni_links has no namespace  (line 26)
   > > Namespace not specified. Specify a namespace in the module's build file: ...
   cause: Android Gradle Plugin 8+ requires every module to declare `namespace` in its build file.
   fix:   Upgrade or replace the plugin uni_links; `droid_doctor plugins` shows newer or replacement packages.
```

Recognizes 23 common errors: Gradle/AGP/Kotlin/JDK version mismatches,
JVM target mismatches, missing namespaces, minSdk/compileSdk conflicts,
duplicate Kotlin classes, SDK/NDK/license problems, out-of-memory, missing
plugins and dependencies. Errors `fix` can resolve are marked `auto`. Exits 1
when nothing is recognized. `--json` is available.

### Auditing plugins

```sh
droid_doctor plugins
```

```console
uni_links 0.5.1  (discontinued)
  error    No namespace; AGP 8.11.1 fails with "Namespace not specified".
           fix: uni_links is discontinued; replace it with app_links.
```

Reads the resolved dependencies (run `flutter pub get` first) and checks each
plugin's Android build against your app: missing AGP 8 namespace, higher
minSdk or compileSdk, Java/Kotlin JVM target mismatch, `jcenter()`, and Kotlin
plugins under AGP built-in Kotlin. For problem plugins it asks pub.dev whether
a newer version or a replacement exists (`--offline` to skip). `--json` and
`--ci` work as in `check`.

### Planning a Flutter upgrade

```sh
droid_doctor plan --flutter 3.47      # or --flutter latest
```

```console
Flutter 3.47 requires:
  component minimum   warns below  yours            status
  Gradle    8.14.0    9.1.0        7.5              ✗ fails
  AGP       8.11.1    9.0.1        7.3.0            ✗ fails
  ...
Apply it now, before upgrading Flutter:
  droid_doctor fix --flutter-version 3.47
```

Shows the minimums Flutter enforces (and the versions it warns about), how
your project compares, and what `fix` would change. Exits 1 when the upgrade
would break the build.

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
every rule. It's bundled into the executable so checks work offline.

```sh
droid_doctor data show     # which data is in use, and how old it is
droid_doctor data update   # download newer data without upgrading droid_doctor
```

A weekly workflow refreshes it and opens a pull request:

- **Automatic:** each stable Flutter release's Android requirements, read from
  Flutter's own version checks at that release's tag (3.10 onwards), and the
  Gradle, AGP and Kotlin release lists.
- **Reviewed by a human:** the pairwise compatibility rules. The pull request
  lists new releases the rules don't cover yet and any change to Flutter's
  compatibility tables.

To refresh locally (a Flutter checkout makes it faster):

```sh
dart run tool/update_data.dart [--flutter-repo ~/dev/flutter]
dart run tool/embed_matrix.dart   # after editing data/matrix.json by hand
```

## Roadmap

- Native binaries, a Homebrew tap and a GitHub Action.
- iOS checks (CocoaPods/SPM, deployment target).

## License

MIT
