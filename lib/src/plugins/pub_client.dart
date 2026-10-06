import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What pub.dev knows about a package.
final class PackageInfo {
  const PackageInfo({
    required this.latestVersion,
    this.isDiscontinued = false,
    this.replacedBy,
  });

  final String latestVersion;
  final bool isDiscontinued;

  /// The package the author recommends instead, if discontinued.
  final String? replacedBy;
}

/// Looks up a package; null if unknown or unreachable.
typedef PackageLookup = Future<PackageInfo?> Function(String package);

/// Queries the pub.dev API. Any failure (offline, timeout, unknown package,
/// unexpected response) returns null: the lookup only enriches the report.
Future<PackageInfo?> pubDevPackageInfo(
  String package, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client
        .getUrl(Uri.https('pub.dev', '/api/packages/$package'))
        .timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) return null;
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    return parsePackageInfo(jsonDecode(body));
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Parses a pub.dev `/api/packages/<name>` response.
PackageInfo? parsePackageInfo(Object? json) => switch (json) {
      {'latest': {'version': final String version}} => PackageInfo(
          latestVersion: version,
          isDiscontinued: (json as Map)['isDiscontinued'] == true,
          replacedBy: json['replacedBy'] as String?,
        ),
      _ => null,
    };
