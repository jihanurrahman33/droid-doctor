import 'package:droid_doctor/droid_doctor.dart';
import 'package:test/test.dart';

Version v(String s) => Version.parse(s);

void main() {
  group('Version', () {
    test('missing trailing segments count as zero', () {
      expect(v('8.10'), v('8.10.0'));
      expect(v('8.10').hashCode, v('8.10.0').hashCode);
      expect(v('9'), v('9.0.0'));
    });

    test('compares numerically, not lexically', () {
      expect(v('8.10') > v('8.9'), isTrue);
      expect(v('8.14.100') > v('8.14.3'), isTrue);
      expect(v('10.0') > v('9.3.1'), isTrue);
    });

    test('pre-releases sort before their release, in qualifier order', () {
      final ordered = [
        '9.0.0-alpha03',
        '9.0.0-alpha10',
        '9.0.0-beta01',
        '9.0.0-rc-1',
        '9.0.0-rc-2',
        '9.0.0',
      ].map(v).toList();
      for (var i = 0; i < ordered.length - 1; i++) {
        expect(ordered[i] < ordered[i + 1], isTrue,
            reason: '${ordered[i]} < ${ordered[i + 1]}');
      }
      expect(v('2.1.0-RC2') < v('2.1.0'), isTrue);
      expect(v('2.1.0-RC2').isPreRelease, isTrue);
      expect(v('8.0-milestone-1') < v('8.0-rc-1'), isTrue);
    });

    test('keeps the original text', () {
      expect(v(' 8.10 ').toString(), '8.10');
    });

    test('rejects invalid input', () {
      for (final bad in ['', 'abc', '8.', '.8', r'$agp', '8.x', '1..2']) {
        expect(() => v(bad), throwsFormatException, reason: bad);
        expect(Version.tryParse(bad), isNull, reason: bad);
      }
      expect(Version.tryParse(null), isNull);
    });
  });

  group('parseJavaVersion', () {
    test('normalizes legacy and modern forms', () {
      expect(parseJavaVersion('1.8'), v('8'));
      expect(parseJavaVersion('1_8'), v('8'));
      expect(parseJavaVersion('1.8.0_392'), v('8'));
      expect(parseJavaVersion('11'), v('11'));
      expect(parseJavaVersion('17.0.20'), v('17.0.20'));
      expect(parseJavaVersion('21.0.4+7'), v('21.0.4'));
      expect(parseJavaVersion('25-ea'), v('25'));
      expect(parseJavaVersion('nope'), isNull);
      expect(parseJavaVersion(null), isNull);
    });
  });

  group('VersionRange', () {
    test('min is inclusive and max exclusive by default', () {
      final r = VersionRange(min: v('8.5'), max: v('9.6'));
      expect(r.allows(v('8.5')), isTrue);
      expect(r.allows(v('9.5.99')), isTrue);
      expect(r.isBelow(v('8.4.9')), isTrue);
      expect(r.isAbove(v('9.6')), isTrue);
      expect(r.toString(), '>=8.5 <9.6');
    });

    test('max can be inclusive', () {
      final r = VersionRange(max: v('8.1.1'), maxInclusive: true);
      expect(r.allows(v('8.1.1')), isTrue);
      expect(r.isAbove(v('8.1.2')), isTrue);
      expect(r.toString(), '<=8.1.1');
    });

    test('unbounded', () {
      expect(const VersionRange().allows(v('1')), isTrue);
      expect(const VersionRange().toString(), 'any');
    });
  });
}
