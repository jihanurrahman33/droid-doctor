import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/matrix_store.dart';
import 'runner.dart';

final class DataCommand extends Command<int> {
  DataCommand(CliContext context) {
    addSubcommand(_DataShowCommand(context));
    addSubcommand(_DataUpdateCommand(context));
  }

  @override
  String get name => 'data';

  @override
  String get description => 'Show or update the compatibility data.';
}

final class _DataShowCommand extends Command<int> {
  _DataShowCommand(this.context);

  final CliContext context;

  @override
  String get name => 'show';

  @override
  String get description => 'Show which compatibility data is in use.';

  @override
  Future<int> run() async {
    final loaded = MatrixStore(context.cacheDir).load();
    final m = loaded.matrix;
    final releases = [for (final f in m.flutter) f.flutter]..sort();
    final out = context.out
      ..writeln('Source:   ${loaded.source}')
      ..writeln('Updated:  ${m.updated}')
      ..writeln(
          'Flutter:  ${releases.isEmpty ? 'none' : '${releases.first}–${releases.last} (${releases.length} releases)'}')
      ..writeln('Rules:    ${m.rules.length}');
    for (final note
        in [loaded.note, stalenessNote(m, context.now())].nonNulls) {
      out.writeln('Note:     $note');
    }
    return ExitCode.ok;
  }
}

final class _DataUpdateCommand extends Command<int> {
  _DataUpdateCommand(this.context);

  final CliContext context;

  @override
  String get name => 'update';

  @override
  String get description =>
      'Download the latest compatibility data (no droid_doctor upgrade '
      'needed).';

  @override
  Future<int> run() async {
    final store = MatrixStore(context.cacheDir);
    try {
      final (status, matrix) = await store.update(context.httpGet);
      context.out.writeln(switch (status) {
        UpdateStatus.updated =>
          'Updated compatibility data to ${matrix.updated} '
              '(${store.cacheFile.path}).',
        UpdateStatus.upToDate =>
          'Compatibility data is up to date (${matrix.updated}).',
      });
      return ExitCode.ok;
    } on FormatException catch (e) {
      context.err.writeln('The latest data needs a newer droid_doctor '
          '(${e.message}). Run: dart pub global activate droid_doctor');
      return ExitCode.problems;
    } on IOException catch (e) {
      context.err.writeln('Could not download compatibility data: $e');
      return ExitCode.problems;
    }
  }
}
