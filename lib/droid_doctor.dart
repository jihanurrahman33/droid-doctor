/// Finds and explains Gradle, Android Gradle Plugin, Kotlin and JDK version
/// problems in the Android build of Flutter projects.
library;

export 'src/cli/runner.dart' show ExitCode, runDroidDoctor;
export 'src/cli/version.dart';
export 'src/data/compat_matrix.dart';
export 'src/detect/android_scanner.dart';
export 'src/detect/environment.dart';
export 'src/model/component.dart';
export 'src/model/finding.dart';
export 'src/model/project_snapshot.dart';
export 'src/model/version.dart';
export 'src/report/reporters.dart';
export 'src/rules/rule.dart' show Rule, checkProject, defaultRules;
