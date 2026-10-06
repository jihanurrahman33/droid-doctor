import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';

Future<void> main(List<String> arguments) async {
  try {
    exitCode = await runDroidDoctor(arguments);
  } on Object catch (error, stackTrace) {
    stderr
      ..writeln('droid_doctor crashed: $error')
      ..writeln(stackTrace)
      ..writeln(
          'Please report it at https://github.com/jihanurrahman33/droid-doctor/issues');
    exitCode = ExitCode.internal;
  }
}
