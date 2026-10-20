import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "check_arm64_appcast", Path(__file__).resolve().parents[1] / "check-arm64-appcast.py"
)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class Arm64AppcastTests(unittest.TestCase):
    def check(self, items):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(
                '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                f"<channel>{items}</channel></rss>"
            )
            checker.check_appcast(path)

    def test_arm64_requirement(self):
        self.check(
            "<item><sparkle:hardwareRequirements> ARM64 </sparkle:hardwareRequirements>"
            '<enclosure url="release.dmg"/></item>'
        )

    def test_missing_requirement(self):
        with self.assertRaises(ValueError):
            self.check('<item><enclosure url="release.dmg"/></item>')

    def test_empty_feed(self):
        with self.assertRaises(ValueError):
            self.check("")

    def test_not_a_substring_match(self):
        with self.assertRaises(ValueError):
            self.check(
                "<item><sparkle:hardwareRequirements>not-arm64</sparkle:hardwareRequirements>"
                '<enclosure url="release.dmg"/></item>'
            )


if __name__ == "__main__":
    unittest.main()
