import 'dart:io';

import 'package:droid_doctor/droid_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'hermetic.dart';

import 'fix_test.dart' show copyFixture, read;

final pinned = ['--flutter-version', '3.47.2', '--java-version', '17'];

Future<({int code, String out, String err})> run(
  List<String> args, {
  bool interactive = false,
  String? answer,
  bool gitDirty = false,
}) async {
  final out = StringBuffer(), err = StringBuffer();
  final code = await runDroidDoctor(
    cacheDir: hermeticCacheDir,
    now: hermeticNow,
    args,
    out: out,
    err: err,
    interactive: interactive,
    readLine: () => answer,
    probe: EnvironmentProbe(run: (exe, arguments) async {
      if (exe == 'git') {
        return ProcessResult(0, 0, gitDirty ? ' M android/x\n' : '', '');
      }
      throw StateError('unexpected process: $exe $arguments');
    }),
  );
  return (code: code, out: out.toString(), err: err.toString());
}

String settings(String root) => read(root, 'android/settings.gradle.kts');

void main() {
  test('--dry-run shows the plan and writes nothing', () async {
    final root = copyFixture('broken_kts');
    final before = settings(root);
    final r = await run(['fix', '-p', root, '--dry-run', ...pinned]);
    expect(r.code, ExitCode.problems, reason: 'errors remain');
    expect(r.out, contains('AGP     8.7.0 → 8.11.2'));
    expect(r.out, contains('Dry run: would apply 6 changes to 3 files.'));
    expect(settings(root), before);
  });

  test('without a terminal, --yes is required', () async {
    final root = copyFixture('broken_kts');
    final before = settings(root);
    final r = await run(['fix', '-p', root, ...pinned]);
    expect(r.out, contains('re-run with --yes'));
    expect(settings(root), before);
  });

  test('interactive "y" applies, then the project checks clean', () async {
    final root = copyFixture('broken_kts');
    final r = await run(['fix', '-p', root, ...pinned],
        interactive: true, answer: 'y', gitDirty: true);
    expect(r.out, contains('uncommitted changes'));
    expect(r.out, contains('Applied 6 changes to 3 files.'));
    expect(r.out, contains('Check: 0 errors'));
    expect(r.code, ExitCode.ok);
    expect(settings(root), contains('"8.11.2"'));
    expect((await run(['check', '-p', root, ...pinned])).code, ExitCode.ok);
  });

  test('interactive "n" aborts', () async {
    final root = copyFixture('broken_kts');
    final before = settings(root);
    final r = await run(['fix', '-p', root, ...pinned],
        interactive: true, answer: 'n');
    expect(r.out, contains('Aborted'));
    expect(settings(root), before);
  });

  test('--yes then --undo round-trips', () async {
    final root = copyFixture('broken_kts');
    final before = settings(root);
    expect(
        (await run(['fix', '-p', root, '--yes', ...pinned])).code, ExitCode.ok);
    final undo = await run(['fix', '-p', root, '--undo']);
    expect(undo.code, ExitCode.ok);
    expect(undo.out, contains('Restored 3 files'));
    expect(settings(root), before);
    expect((await run(['fix', '-p', root, '--undo'])).out,
        contains('nothing to undo'));
  });

  test('--undo reports conflicts', () async {
    final root = copyFixture('broken_kts');
    await run(['fix', '-p', root, '--yes', ...pinned]);
    final file = File(p.join(root, 'android', 'settings.gradle.kts'));
    file.writeAsStringSync('${file.readAsStringSync()}// edited\n');
    final r = await run(['fix', '-p', root, '--undo']);
    expect(r.code, ExitCode.problems);
    expect(r.out, contains('--undo --force'));
  });

  test('healthy project: nothing to fix', () async {
    final root = copyFixture('modern_kts');
    final r = await run(['fix', '-p', root, '--yes', ...pinned]);
    expect(r.code, ExitCode.ok);
    expect(r.out, contains('Nothing to fix automatically.'));
  });

  test('invalid --strategy is a usage error', () async {
    final r = await run(['fix', '--strategy', 'yolo', ...pinned]);
    expect(r.code, ExitCode.usage);
  });
}
