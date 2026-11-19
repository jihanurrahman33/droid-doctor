# droid_doctor example

`droid_doctor` is a command-line tool. Run it from the root of a Flutter
project, or point it at one with `-p`.

```sh
dart pub global activate droid_doctor
cd my_flutter_app
```

## 1. Check the Android build

```sh
droid_doctor
```

```console
droid_doctor 1.0.0  ·  data 2026-11-19  ·  ~/code/my_app

  Flutter  3.47.2     flutter --version
  JDK      17.0.20    flutter config --jdk-dir (...)
  Gradle   8.3        android/gradle/wrapper/gradle-wrapper.properties:5
  AGP      8.7.0      android/settings.gradle.kts:22
  KGP      1.9.0      android/settings.gradle.kts:23

error    Android Gradle Plugin 8.7.0 requires Gradle 8.9 or newer (found 8.3).
         at android/gradle/wrapper/gradle-wrapper.properties:5
         fix: Set distributionUrl to https\://services.gradle.org/distributions/gradle-8.9-all.zip
...
4 errors, 2 warnings, 0 infos.
```

The exit code is 1 when problems are found, so the same command works in CI.

## 2. Preview the fix, then apply it

```sh
droid_doctor fix --dry-run   # show the changes only
droid_doctor fix             # show them, ask, then apply
```

```console
Versions:
  Gradle  8.3 → 8.14.7
  AGP     8.7.0 → 8.11.2
  KGP     1.9.0 → 2.2.21
...
Applied 3 changes to 2 files.
Backup: .dart_tool/droid_doctor/backups/20261119-093754-062  (undo with `droid_doctor fix --undo`)
```

## 3. Undo it

```sh
droid_doctor fix --undo
```

## 4. Before upgrading Flutter

```sh
droid_doctor plan --flutter latest
```

Shows what the new Flutter release requires of your Android build, and what
`fix` would change to get there.

See the [README](https://github.com/jihanurrahman33/droid-doctor#readme) for
`explain` (diagnose a failed build log), `plugins` (audit Android plugins) and
all options.
