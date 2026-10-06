/// Deterministic, diff-friendly formatting for data/matrix.json: one rule,
/// one Flutter release and one release list per line.
library;

import 'dart:convert';

String formatMatrix(Map<String, Object?> matrix) {
  final out = StringBuffer('{\n');
  final entries = matrix.entries.toList();
  for (var i = 0; i < entries.length; i++) {
    final MapEntry(:key, :value) = entries[i];
    out.write('  ${jsonEncode(key)}: ');
    if (value is List<Object?> && const {'rules', 'flutter'}.contains(key)) {
      out.write('[\n');
      for (var j = 0; j < value.length; j++) {
        out.write(
            '    ${_inline(value[j])}${j < value.length - 1 ? ',' : ''}\n');
      }
      out.write('  ]');
    } else if (value is Map<String, Object?>) {
      out.write('{\n');
      final inner = value.entries.toList();
      for (var j = 0; j < inner.length; j++) {
        out.write('    ${jsonEncode(inner[j].key)}: ${_inline(inner[j].value)}'
            '${j < inner.length - 1 ? ',' : ''}\n');
      }
      out.write('  }');
    } else {
      out.write(_inline(value));
    }
    out.write(i < entries.length - 1 ? ',\n' : '\n');
  }
  out.write('}\n');
  return out.toString();
}

/// Compact JSON with a space after `:` and `,` for readability.
String _inline(Object? value) => switch (value) {
      Map<String, Object?> m => '{${[
          for (final e in m.entries) '${jsonEncode(e.key)}: ${_inline(e.value)}'
        ].join(', ')}}',
      List<Object?> l => '[${l.map(_inline).join(', ')}]',
      _ => jsonEncode(value),
    };
