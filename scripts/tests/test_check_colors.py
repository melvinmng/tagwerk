"""Tests of scripts/check-colors.py on small Swift snippets.

Run: /usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
"""
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
spec = importlib.util.spec_from_file_location("check_colors", ROOT / "scripts" / "check-colors.py")
check_colors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_colors)


def kinds(source):
    """The kinds of the findings in a Swift snippet."""
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "View.swift"
        path.write_text(source, encoding="utf-8")
        return [kind for _, kind, _ in check_colors.findings(path)]


def section_findings(source):
    """The reasons of the section header/footer findings (decision D1) in a Swift snippet."""
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "View.swift"
        path.write_text(source, encoding="utf-8")
        return [kind for _, kind, _ in check_colors.section_tone_findings(path)]


class CheckColorsTests(unittest.TestCase):
    def test_systemGrey_asForeground_isReported(self):
        self.assertEqual(kinds('Text("a").foregroundStyle(.secondary)'), ["system grey as foreground"])
        self.assertEqual(kinds('Text("a").foregroundStyle(isOn ? Color.accentColor : Color.secondary)'), ["system grey as foreground"])
        self.assertEqual(kinds('Text("a").foregroundColor(.secondary)'), ["system grey as foreground"])

    def test_systemGrey_asSymbolInATextLine_isReported(self):
        self.assertEqual(kinds('Image(systemName: "x").foregroundStyle(.secondary)'), ["system grey as foreground"])

    def test_fillsAndStrokes_areNotReported(self):
        self.assertEqual(kinds('Circle().fill(Color.secondary.opacity(0.2))'), [])
        self.assertEqual(kinds('Capsule().background(.secondary.opacity(0.1))'), [])
        self.assertEqual(kinds('.tint(.secondary)'), [])

    def test_namedTones_areNotReported(self):
        self.assertEqual(kinds('Text("a").foregroundStyle(.secondaryText)'), [])
        self.assertEqual(kinds('Text("a").foregroundStyle(isOverdue ? Color.redText : Color.secondaryText)'), [])

    def test_systemColour_onText_isReported(self):
        self.assertEqual(kinds('Text("a").foregroundStyle(.red)'), ["system colour on text"])
        self.assertEqual(kinds('Label("a", systemImage: "x").foregroundStyle(.orange)'), ["system colour on text"])

    def test_systemColour_onAModifierLineOfAText_isReported(self):
        self.assertEqual(kinds('Text("a")\n    .font(.caption)\n    .foregroundStyle(.purple)'), ["system colour on text"])
        self.assertEqual(kinds('Label("a",\n      systemImage: "x")\n    .foregroundStyle(.green)'), ["system colour on text"])

    def test_systemColour_onSymbolsAndShapes_isNotReported(self):
        self.assertEqual(kinds('Image(systemName: "flag.fill").foregroundStyle(.red)'), [])
        self.assertEqual(kinds('Image(systemName: "flag.fill")\n    .font(.caption)\n    .foregroundStyle(.orange)'), [])

    def test_exemptComment_silencesALine(self):
        self.assertEqual(kinds('Text("a").foregroundStyle(.secondary) // system-colour: sits on Liquid Glass'), [])

    def test_sectionHeaderAndFooter_inTheSystemGrey_areReported(self):
        source = 'Section {\n    Text("a")\n} header: {\n    Text("Titel")\n} footer: {\n    Text("Hinweis \\(count)")\n        .font(.footnote)\n}'
        self.assertEqual(len(section_findings(source)), 2)

    def test_sectionHeaderAndFooter_inTheNamedTone_areNotReported(self):
        source = 'Section {\n    Text("a")\n} header: {\n    Text("Titel")\n        .foregroundStyle(.secondaryText)\n} footer: {\n    if x { Text("Hinweis").foregroundStyle(.secondaryText) }\n}'
        self.assertEqual(section_findings(source), [])

    def test_sectionHeaderAndFooter_withAnOwnColour_areNotReported(self):
        self.assertEqual(section_findings('Section { Text("a") } footer: { Text("x").foregroundStyle(.redText) }'), [])

    def test_sectionTitleInitialiser_isReported(self):
        self.assertEqual(len(section_findings('Section("Titel") {\n    Text("a")\n}')), 1)
        self.assertEqual(len(section_findings('Section(section.title) {\n    Text("a")\n}')), 1)

    def test_rowsInASection_areNotReported(self):
        self.assertEqual(section_findings('Section {\n    Text("a")\n    Text("b")\n} header: {\n    Label("c", systemImage: "x")\n}'), [])

    def test_theRepository_hasNoSectionToneFindings(self):
        scoped = {path for pattern in check_colors.SECTION_TONE_SCOPE for path in check_colors.APP.glob(pattern)}
        self.assertTrue(scoped)
        problems = [(path, number) for path in sorted(scoped) for number, _, _ in check_colors.section_tone_findings(path)]
        self.assertEqual(problems, [])

    def test_theRepository_hasNoFindings(self):
        problems = [(path, number) for path in check_colors.swift_files() for number, _, _ in check_colors.findings(path)]
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
