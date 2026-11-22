import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math_example/update_checker.dart';

void main() {
  group('compareVersions', () {
    test('distinguishes newer, equal, and older releases', () {
      expect(compareVersions('0.4.0', '0.3.9'), greaterThan(0));
      expect(compareVersions('0.3.0', '0.3.0'), 0);
      expect(compareVersions('0.2.9', '0.3.0'), lessThan(0));
      expect(compareVersions('1.0.0-alpha.2', '1.0.0-alpha.10'), lessThan(0));
      expect(compareVersions('1.0.0-beta', '1.0.0'), lessThan(0));
    });
  });

  group('GithubReleaseInfo.parse', () {
    test('normalizes the tag and keeps release notes and URL', () {
      final release = GithubReleaseInfo.parse({
        'tag_name': 'v0.4.0',
        'html_url':
            'https://github.com/JohnXu22786/visual-math/releases/tag/v0.4.0',
        'body': 'A release note',
      });

      expect(release.version, '0.4.0');
      expect(release.url.toString(), contains('/releases/tag/v0.4.0'));
      expect(release.notes, 'A release note');
    });

    test('rejects malformed version and non-GitHub release URL', () {
      expect(
        () => GithubReleaseInfo.parse({
          'tag_name': 'main',
          'html_url': 'https://github.com/JohnXu22786/visual-math/releases',
          'body': '',
        }),
        throwsFormatException,
      );
      expect(
        () => GithubReleaseInfo.parse({
          'tag_name': 'v0.4.0',
          'html_url': 'https://example.com/release',
          'body': '',
        }),
        throwsFormatException,
      );
    });
  });
}
