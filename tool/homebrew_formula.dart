// Prints the Homebrew formula for a release, from the release's SHA256SUMS:
//
//   dart run tool/homebrew_formula.dart <version> <SHA256SUMS file>
import 'dart:io';

const _repo = 'jihanurrahman33/droid-doctor';

/// Homebrew platform blocks → release archive target names.
const _targets = {
  ('on_macos', 'on_arm'): 'macos-arm64',
  ('on_macos', 'on_intel'): 'macos-x64',
  ('on_linux', 'on_arm'): 'linux-arm64',
  ('on_linux', 'on_intel'): 'linux-x64',
};

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: homebrew_formula.dart <version> <SHA256SUMS>');
    exit(64);
  }
  stdout.write(homebrewFormula(args[0], File(args[1]).readAsStringSync()));
}

/// Builds the formula for [version] from `sha256sum` output ([checksums]).
/// Throws if any platform's archive is missing.
String homebrewFormula(String version, String checksums) {
  final sums = {
    for (final line in checksums.split('\n'))
      if (RegExp(r'^([0-9a-f]{64})\s+\*?(\S+)$').firstMatch(line.trim())
          case final m?)
        m[2]!: m[1]!,
  };
  String block(String os, String cpu) {
    final archive = 'droid_doctor-$version-${_targets[(os, cpu)]}.tar.gz';
    final sha = sums[archive] ??
        (throw StateError('No checksum for $archive in SHA256SUMS'));
    return '''
    $cpu do
      url "https://github.com/$_repo/releases/download/v$version/$archive"
      sha256 "$sha"
    end''';
  }

  return '''
class DroidDoctor < Formula
  desc "Find, explain and fix Gradle/AGP/Kotlin/JDK problems in Flutter Android builds"
  homepage "https://github.com/$_repo"
  version "$version"
  license "MIT"

  on_macos do
${block('on_macos', 'on_arm')}
${block('on_macos', 'on_intel')}
  end

  on_linux do
${block('on_linux', 'on_arm')}
${block('on_linux', 'on_intel')}
  end

  def install
    bin.install "droid_doctor"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/droid_doctor --version")
  end
end
''';
}
