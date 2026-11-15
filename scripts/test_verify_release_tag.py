import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("verify-release-tag.sh")


class VerifyReleaseTagTest(unittest.TestCase):
    def run_verifier(self, scenario, checked_out_commit="publish-commit"):
        with tempfile.TemporaryDirectory() as directory:
            bin_directory = Path(directory) / "bin"
            bin_directory.mkdir()
            fake_gh = bin_directory / "gh"
            fake_gh.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"$1\" == api && \"$2\" == repos/owner/repo/git/ref/tags/v1.2.3 ]]; then\n"
                "  if [[ \"$VERIFY_SCENARIO\" == lightweight ]]; then exit 0; fi\n"
                "  printf '%s\\n' tag-object-sha\n"
                "elif [[ \"$1\" == api && \"$2\" == repos/owner/repo/git/tags/tag-object-sha ]]; then\n"
                "  printf '%s\\tcommit\\tpublish-commit\\n' \"$VERIFY_SCENARIO\"\n"
                "else\n"
                "  exit 2\n"
                "fi\n"
            )
            fake_gh.chmod(0o755)
            fake_git = bin_directory / "git"
            fake_git.write_text(
                "#!/usr/bin/env bash\n"
                "[[ \"$1\" == rev-parse && \"$2\" == HEAD ]] || exit 2\n"
                "printf '%s\\n' \"$CHECKED_OUT_COMMIT\"\n"
            )
            fake_git.chmod(0o755)
            github_output = Path(directory) / "github-output"
            environment = os.environ | {
                "GITHUB_REPOSITORY": "owner/repo",
                "GITHUB_OUTPUT": str(github_output),
                "VERIFY_SCENARIO": scenario,
                "CHECKED_OUT_COMMIT": checked_out_commit,
                "PATH": f"{bin_directory}:{os.environ['PATH']}",
            }
            result = subprocess.run(
                [str(SCRIPT), "v1.2.3"],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
            return result, github_output.read_text() if github_output.exists() else ""

    def test_accepts_github_verified_signed_tag(self):
        result, output = self.run_verifier("true")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "commit=publish-commit\n")

    def test_rejects_unsigned_tag(self):
        result, _ = self.run_verifier("false")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not have a verified signature", result.stdout)

    def test_rejects_lightweight_tag(self):
        result, _ = self.run_verifier("lightweight")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be an annotated, signed tag", result.stdout)

    def test_rejects_checked_out_source_that_differs_from_signed_tag(self):
        result, _ = self.run_verifier("true", checked_out_commit="different-commit")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match the verified release tag", result.stdout)


if __name__ == "__main__":
    unittest.main()
