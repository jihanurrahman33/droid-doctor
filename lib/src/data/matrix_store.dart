import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'compat_matrix.dart';

/// Where `data update` downloads from: the matrix on the main branch, which
/// the weekly data workflow keeps current.
final remoteMatrixUri = Uri.parse('https://raw.githubusercontent.com/'
    'jihanurrahman33/droid-doctor/main/data/matrix.json');

/// Data older than this gets a note suggesting `data update`.
const staleAfter = Duration(days: 30);

/// The per-user cache directory: `$DROID_DOCTOR_CACHE`, else
/// `%LOCALAPPDATA%\droid_doctor` on Windows, else
/// `$XDG_CACHE_HOME/droid_doctor` or `~/.cache/droid_doctor`.
String defaultCacheDir(Map<String, String> env, String operatingSystem) {
  if (env['DROID_DOCTOR_CACHE'] case final dir? when dir.isNotEmpty) return dir;
  if (operatingSystem == 'windows') {
    return p.windows
        .join(env['LOCALAPPDATA'] ?? env['APPDATA'] ?? '.', 'droid_doctor');
  }
  final xdg = env['XDG_CACHE_HOME'];
  return p.posix.join(
    xdg != null && xdg.isNotEmpty
        ? xdg
        : p.posix.join(env['HOME'] ?? '.', '.cache'),
    'droid_doctor',
  );
}

/// The matrix in use and where it came from.
typedef LoadedMatrix = ({CompatMatrix matrix, String source, String? note});

enum UpdateStatus { updated, upToDate }

/// Bundled data plus an optional newer download in the cache directory.
final class MatrixStore {
  MatrixStore(this.cacheDir);

  final String cacheDir;

  File get cacheFile => File(p.join(cacheDir, 'matrix.json'));

  /// The newest usable matrix: the cached download if it parses and is newer
  /// than the bundled data, otherwise the bundled data.
  LoadedMatrix load() {
    final bundled = CompatMatrix.bundled();
    final file = cacheFile;
    if (!file.existsSync()) {
      return (matrix: bundled, source: 'bundled', note: null);
    }
    try {
      final cached = CompatMatrix.parse(file.readAsStringSync());
      if (cached.updated.compareTo(bundled.updated) > 0) {
        return (matrix: cached, source: file.path, note: null);
      }
      return (matrix: bundled, source: 'bundled', note: null);
    } on FormatException catch (e) {
      return (
        matrix: bundled,
        source: 'bundled',
        note: 'Ignoring downloaded data in ${file.path}: ${e.message}',
      );
    }
  }

  /// Downloads the latest matrix with [fetch], validates it, and caches it if
  /// it is newer than what [load] returns. Throws [FormatException] for data
  /// this version can't read (nothing is written then).
  Future<(UpdateStatus, CompatMatrix)> update(
    Future<String> Function(Uri) fetch,
  ) async {
    final text = await fetch(remoteMatrixUri);
    final downloaded = CompatMatrix.parse(text);
    final current = load().matrix;
    if (downloaded.updated.compareTo(current.updated) <= 0) {
      return (UpdateStatus.upToDate, current);
    }
    Directory(cacheDir).createSync(recursive: true);
    final temp = File('${cacheFile.path}.tmp')
      ..writeAsStringSync(text, flush: true);
    temp.renameSync(cacheFile.path);
    return (UpdateStatus.updated, downloaded);
  }
}

/// A note when [matrix] is older than [staleAfter], else null.
String? stalenessNote(CompatMatrix matrix, DateTime now) {
  final updated = DateTime.tryParse(matrix.updated);
  if (updated == null) return null;
  final age = now.difference(updated).inDays;
  if (age <= staleAfter.inDays) return null;
  return 'Compatibility data is from ${matrix.updated} ($age days old); '
      'run `droid_doctor data update`.';
}

/// GETs [uri] as text, failing on non-200 responses.
Future<String> httpGetText(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final response = await (await client.getUrl(uri)).close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
