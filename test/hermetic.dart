import 'dart:io';

import 'package:path/path.dart' as p;

/// A cache directory that never exists, so tests always use bundled data.
final hermeticCacheDir =
    p.join(Directory.systemTemp.path, 'droid_doctor_no_cache_${pid}_x');

/// The bundled data's date, so staleness notes never appear in tests.
DateTime hermeticNow() => DateTime.utc(2026, 10, 6);
