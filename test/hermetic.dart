import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:path/path.dart' as p;

/// A cache directory that never exists, so tests always use bundled data.
final hermeticCacheDir =
    p.join(Directory.systemTemp.path, 'droid_doctor_no_cache_${pid}_x');

/// A date that is never more than 30 days after the bundled data's date, so
/// staleness notes never appear in tests.
DateTime hermeticNow() => DateTime.utc(2026, 10, 6);

/// The compatibility data as of 2026-10-06, frozen for tests that assert the
/// exact versions the solver picks. The bundled data changes with every
/// refresh, so such tests must not read it.
CompatMatrix snapshotMatrix() =>
    CompatMatrix.parse(File(p.join('test', 'fixtures', 'matrix_snapshot.json'))
        .readAsStringSync());
