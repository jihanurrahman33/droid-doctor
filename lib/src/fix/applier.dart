import 'dart:io';

import 'package:path/path.dart' as p;

import 'edits.dart';

/// Where backups live: inside `.dart_tool/`, which Flutter projects already
/// ignore in git.
const backupRoot = '.dart_tool/droid_doctor/backups';

/// Applies edits with a backup, and restores the latest backup on undo.
final class FixApplier {
  FixApplier(this.projectPath, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final String projectPath;
  final DateTime Function() _clock;

  /// Applies [edits] and returns the backup directory (relative to the
  /// project). All edits are verified before any file is written; a
  /// [StaleEditException] leaves the project untouched.
  String apply(List<Edit> edits) {
    final byFile = <String, List<Edit>>{};
    for (final e in edits) {
      (byFile[e.path] ??= []).add(e);
    }

    final updates = <String, ({String before, String after})>{};
    for (final MapEntry(key: path, value: fileEdits) in byFile.entries) {
      final file = File(p.join(projectPath, path));
      if (!file.existsSync()) throw StaleEditException(path, 0);
      final before = file.readAsStringSync();
      updates[path] = (
        before: before,
        after: TextLines.parse(before).apply(fileEdits, path: path),
      );
    }

    final backup = p.join(backupRoot, _timestamp());
    for (final MapEntry(key: path, value: content) in updates.entries) {
      _write(p.join(projectPath, backup, 'before', path), content.before);
      _write(p.join(projectPath, backup, 'after', path), content.after);
    }
    for (final MapEntry(key: path, value: content) in updates.entries) {
      _writeAtomically(File(p.join(projectPath, path)), content.after);
    }
    return backup;
  }

  /// Restores the most recent backup and deletes it, so repeated undos step
  /// back through earlier fixes. Files edited since the fix are reported as
  /// conflicts and nothing is restored unless [force] is set.
  UndoResult undo({bool force = false}) {
    final root = Directory(p.join(projectPath, backupRoot));
    final backups = root.existsSync()
        ? (root.listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
        : <Directory>[];
    if (backups.isEmpty) return const UndoResult(restored: [], conflicts: []);
    final latest = backups.last;
    final afterDir = p.join(latest.path, 'after');

    final files = [
      for (final f in Directory(afterDir).listSync(recursive: true))
        if (f is File) p.relative(f.path, from: afterDir),
    ]..sort();
    final conflicts = [
      for (final path in files)
        if (_read(p.join(projectPath, path)) !=
            File(p.join(afterDir, path)).readAsStringSync())
          path,
    ];
    if (conflicts.isNotEmpty && !force) {
      return UndoResult(restored: const [], conflicts: conflicts);
    }
    for (final path in files) {
      _writeAtomically(
        File(p.join(projectPath, path)),
        File(p.join(latest.path, 'before', path)).readAsStringSync(),
      );
    }
    latest.deleteSync(recursive: true);
    return UndoResult(restored: files, conflicts: conflicts);
  }

  String _timestamp() {
    final now = _clock().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final base = '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}-'
        '${now.millisecond.toString().padLeft(3, '0')}';
    var name = base;
    for (var i = 1;
        Directory(p.join(projectPath, backupRoot, name)).existsSync();
        i++) {
      name = '$base-$i';
    }
    return name;
  }

  static String? _read(String path) {
    final file = File(path);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  static void _write(String path, String content) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// Writes via a temporary file and rename, so a crash never leaves a
  /// half-written build file.
  static void _writeAtomically(File file, String content) {
    final temp = File('${file.path}.droid_doctor.tmp');
    temp.writeAsStringSync(content, flush: true);
    temp.renameSync(file.path);
  }
}

final class UndoResult {
  const UndoResult({required this.restored, required this.conflicts});

  final List<String> restored;

  /// Files changed since the fix was applied.
  final List<String> conflicts;
}
