import 'dart:convert';

import 'package:http/http.dart' as http;

/// Example hosts may pass the package version at build time; the fallback
/// stays aligned with the version in the repository's root pubspec.yaml.
const visualMathVersion = String.fromEnvironment(
  'VISUAL_MATH_VERSION',
  defaultValue: '0.3.0',
);

const _latestReleaseUri =
    'https://api.github.com/repos/JohnXu22786/visual-math/releases/latest';

class GithubReleaseInfo {
  const GithubReleaseInfo({
    required this.version,
    required this.url,
    required this.notes,
  });

  final String version;
  final Uri url;
  final String notes;

  factory GithubReleaseInfo.parse(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Release response must be an object.');
    }
    final tag = json['tag_name'];
    final rawUrl = json['html_url'];
    if (tag is! String || rawUrl is! String) {
      throw const FormatException('Release is missing its tag or URL.');
    }
    final version = tag.replaceFirst(RegExp(r'^v'), '');
    _parseVersion(version);
    final url = Uri.tryParse(rawUrl);
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith('/JohnXu22786/visual-math/releases/tag/')) {
      throw const FormatException('Release URL is not a Visual Math release.');
    }
    return GithubReleaseInfo(
      version: version,
      url: url,
      notes: json['body'] is String ? json['body'] as String : '',
    );
  }
}

Future<GithubReleaseInfo> fetchLatestRelease({http.Client? client}) async {
  final requestClient = client ?? http.Client();
  try {
    final response = await requestClient
        .get(
          Uri.parse(_latestReleaseUri),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('GitHub returned HTTP ${response.statusCode}.');
    }
    try {
      return GithubReleaseInfo.parse(jsonDecode(response.body));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('GitHub returned invalid release data.');
    }
  } finally {
    if (client == null) requestClient.close();
  }
}

int compareVersions(String left, String right) {
  final a = _parseVersion(left);
  final b = _parseVersion(right);
  for (var i = 0; i < 3; i++) {
    final comparison = a.core[i].compareTo(b.core[i]);
    if (comparison != 0) return comparison;
  }
  if (a.prerelease == null && b.prerelease == null) return 0;
  if (a.prerelease == null) return 1;
  if (b.prerelease == null) return -1;
  final aParts = a.prerelease!.split('.');
  final bParts = b.prerelease!.split('.');
  for (var i = 0; i < aParts.length && i < bParts.length; i++) {
    final an = int.tryParse(aParts[i]);
    final bn = int.tryParse(bParts[i]);
    final comparison = an != null && bn != null
        ? an.compareTo(bn)
        : an != null
        ? -1
        : bn != null
        ? 1
        : aParts[i].compareTo(bParts[i]);
    if (comparison != 0) return comparison;
  }
  return aParts.length.compareTo(bParts.length);
}

({List<int> core, String? prerelease}) _parseVersion(String value) {
  final match = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  ).firstMatch(value);
  if (match == null) throw FormatException('Invalid version: $value');
  return (
    core: [int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!)],
    prerelease: match[4],
  );
}
