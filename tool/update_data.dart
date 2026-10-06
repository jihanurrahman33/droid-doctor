// Refreshes data/matrix.json from upstream sources and writes a review
// report. Run from the package root:
//
//   dart run tool/update_data.dart [--flutter-repo <path>] [--report <file>]
//
// Automatic: Flutter's per-release requirements (from flutter_tools at each
// stable tag) and the Gradle/AGP/KGP release lists. Never automatic: the
// pairwise compatibility rules — when upstream changes them, the report says
// so and a human updates the rules.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:droid_doctor/droid_doctor.dart';

import 'embed_matrix.dart' show embedMatrix;
import 'src/flutter_requirements.dart';
import 'src/matrix_format.dart';
import 'src/releases.dart';

const _matrixPath = 'data/matrix.json';
const _flutterRepo = 'https://github.com/flutter/flutter';

Future<void> main(List<String> arguments) async {
  final args = (ArgParser()
        ..addOption('flutter-repo',
            help: 'Local Flutter git checkout (faster than downloading).')
        ..addOption('report', help: 'Write a Markdown review report here.'))
      .parse(arguments);
  final repo = args.option('flutter-repo');
  final read = repo == null ? _readFromGitHub : _readFromCheckout(repo);
  final report = <String>[];

  final json =
      jsonDecode(File(_matrixPath).readAsStringSync()) as Map<String, Object?>;
  final before = formatMatrix({...json}..remove('updated'));

  // 1. Flutter requirements per stable minor release.
  final tags = latestStablePerMinor(await _tags(repo));
  final flutter = <Map<String, Object?>>[];
  for (final tag in tags) {
    final entry = await extractFlutterRequirements(tag, read);
    if (entry == null) {
      stderr.writeln('Skipped Flutter $tag (no template data).');
    } else {
      flutter.add(entry);
    }
  }
  if (flutter.isEmpty) throw StateError('No Flutter data extracted.');
  json['flutter'] = flutter.reversed.toList(); // Newest first.

  // 2. Release lists.
  final releases = {
    'gradle': condenseReleases(
        parseGradleVersions(
            await _get('https://services.gradle.org/versions/all')),
        floor: '7.0'),
    'agp': condenseReleases(
        parseMavenMetadata(await _get('https://dl.google.com/dl/android/maven2/'
            'com/android/tools/build/gradle/maven-metadata.xml')),
        floor: '7.0'),
    'kgp': condenseReleases(
        parseMavenMetadata(await _get('https://repo1.maven.org/maven2/'
            'org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml')),
        floor: '1.7.0',
        kotlinStyle: true),
  };
  json['releases'] = releases;

  // 3. What needs a human.
  final matrix = CompatMatrix.parse(formatMatrix(json));
  for (final MapEntry(key: component, value: from)
      in matrix.unknownFrom.entries) {
    final newer = [
      for (final v in matrix.releases[component] ?? const <Version>[])
        if (v >= from) '$v',
    ];
    if (newer.isNotEmpty) {
      report.add('- **${component.displayName}** releases with no '
          'compatibility rules yet (`unknownFrom: $from`): ${newer.join(', ')}. '
          'Add rules from the upstream docs, then raise `unknownFrom`.');
    }
  }
  final reviewedAt = json['rulesReviewedAgainstFlutter'] as String?;
  final latest = tags.last;
  if (reviewedAt != null && reviewedAt != latest) {
    final old = await compatibilityCode(reviewedAt, read);
    final now = await compatibilityCode(latest, read);
    if (old != null && now != null) {
      final added = now.where((l) => !old.contains(l)).toList();
      final removed = old.where((l) => !now.contains(l)).toList();
      if (added.isEmpty && removed.isEmpty) {
        json['rulesReviewedAgainstFlutter'] = latest;
      } else {
        report.add('- Flutter changed its compatibility tables between '
            '$reviewedAt and $latest (gradle_utils.dart). Update the matrix '
            'rules, then set `rulesReviewedAgainstFlutter` to `$latest`.\n\n'
            '```diff\n'
            '${[
          ...removed.take(40).map((l) => '- $l'),
          ...added.take(40).map((l) => '+ $l'),
        ].join('\n')}\n```');
      }
    }
  }

  // 4. Write only on real changes, so the weekly run doesn't churn dates.
  final changed = formatMatrix({...json}..remove('updated')) != before;
  if (changed) {
    final now = DateTime.now().toUtc();
    json['updated'] = '${now.year}-${_two(now.month)}-${_two(now.day)}';
    final ordered = {
      for (final key in [
        'schemaVersion',
        'updated',
        'rulesReviewedAgainstFlutter',
        'sources',
        'unknownFrom',
        'releases',
        'rules',
        'flutter',
      ])
        if (json.containsKey(key)) key: json[key],
      ...json,
    };
    final text = formatMatrix(ordered);
    CompatMatrix.parse(text); // Never write a matrix the tool can't read.
    File(_matrixPath).writeAsStringSync(text);
    File('lib/src/data/bundled_matrix.g.dart')
        .writeAsStringSync(embedMatrix(text));
  }

  final summary = [
    changed
        ? 'Updated $_matrixPath: Flutter ${flutter.first['version']}–'
            '${flutter.last['version']} (${flutter.length} releases); '
            'latest Gradle ${releases['gradle']!.last}, AGP '
            '${releases['agp']!.last}, KGP ${releases['kgp']!.last}.'
        : 'No data changes.',
    if (report.isNotEmpty) ...['', '### Needs review', '', ...report],
  ].join('\n');
  stdout.writeln(summary);
  if (args.option('report') case final path?) {
    File(path).writeAsStringSync('$summary\n');
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

Future<List<String>> _tags(String? repo) async {
  final result = repo == null
      ? await Process.run(
          'git', ['ls-remote', '--tags', '--refs', _flutterRepo])
      : await Process.run('git', ['-C', repo, 'tag', '-l', '3.*']);
  if (result.exitCode != 0) throw StateError('git failed: ${result.stderr}');
  return [
    for (final line in '${result.stdout}'.split('\n'))
      if (line.trim().isNotEmpty) line.trim().split('refs/tags/').last,
  ];
}

FlutterFileReader _readFromCheckout(String repo) => (tag, path) async {
      final result =
          await Process.run('git', ['-C', repo, 'show', '$tag:$path']);
      return result.exitCode == 0 ? '${result.stdout}' : null;
    };

Future<String?> _readFromGitHub(String tag, String path) async {
  try {
    return await _get(
        'https://raw.githubusercontent.com/flutter/flutter/$tag/$path');
  } on HttpException {
    return null;
  }
}

final _client = HttpClient();

Future<String> _get(String url) async {
  for (var attempt = 1;; attempt++) {
    try {
      final response = await (await _client.getUrl(Uri.parse(url))).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 404) {
        throw HttpException('404', uri: Uri.parse(url));
      }
      if (response.statusCode != 200) {
        throw StateError('GET $url: HTTP ${response.statusCode}');
      }
      return body;
    } on SocketException {
      if (attempt == 3) rethrow;
      await Future<void>.delayed(Duration(seconds: attempt * 2));
    }
  }
}
