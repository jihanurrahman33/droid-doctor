import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';

Future<void> main(List<String> arguments) async {
  try {
    exitCode = await runDroidDoctor(arguments);
  } on Object catch (error, stackTrace) {
    stderr
      ..writeln('droid_doctor crashed: $error')
      ..writeln(stackTrace)
      ..writeln('Please report this at the project issue tracker.');
    exitCode = ExitCode.internal;
  }
}
