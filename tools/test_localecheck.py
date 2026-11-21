"""Negative locale fixtures, independent of translation wording choices."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("localecheck", HERE / "localecheck.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class LocaleGateTests(unittest.TestCase):
    def test_each_new_locale_requires_every_key(self):
        english = gate.english_table(HERE.parent / "BuffRadar/BuffRadar.lua")
        allow = json.loads((HERE / "locale-identical.json").read_text(encoding="utf-8"))
        for code in ("frFR", "esES", "ruRU", "zhCN"):
            with self.subTest(locale=code):
                pack = gate.locale_table(HERE.parent / f"BuffRadar/Locales/{code}.lua", code)
                pack.pop(next(iter(english)))
                self.assertTrue(any("missing:" in item for item in gate.problems(english, pack, code, allow)))

    def test_placeholder_order_and_literal_percent(self):
        for source, changed in (("%d %s", "%s %d"), ("%d%%", "%d%s"), ("%s", "%k")):
            self.assertTrue(gate.problems({source: source}, {source: changed}, "test", {}))

    def test_markup_balance_and_payload(self):
        for source, changed in (("|cffffffffReady|r", "|cffffffffPrêt"),
                                ("|cffffffffReady|r", "Prêt|r"),
                                ("|Hitem:1|hText|h", "|Hitem:2|hTexte|h"),
                                ("Ready", "|Hitem:1|hTexte")):
            self.assertTrue(gate.problems({source: source}, {source: changed}, "test", {}))
        self.assertTrue(gate.problems({"Ready": "Ready"}, {"Ready": "|rX"}, "test", {}))
        source = "|cffffffffReady|rnow"
        self.assertFalse(gate.problems({source: source}, {source: "|cffffffffPrêt|rmaintenant"}, "test", {}))

    def test_literal_commands_and_options(self):
        for source, changed in (("Use /br coordinate inbox.", "Utilisez /br coordinate review."),
                                ("Use /br firstcast.", "Utilisez /br premier."),
                                ("Use /br plates on|off|names|bars|restore.", "Utilisez /br plates on|off|noms|bars|restore.")):
            self.assertTrue(gate.problems({source: source}, {source: changed}, "test", {}))

    def test_command_trailing_prose_is_not_an_option(self):
        source = "Caster plan from %s. Use /br coordinate inbox to review it."
        translated = "Plan de %s. Utilisez /br coordinate inbox pour le consulter."
        self.assertFalse(gate.problems({source: source}, {source: translated}, "test", {}))

    def test_identical_english_requires_review(self):
        self.assertTrue(gate.problems({"Ready": "Ready"}, {"Ready": "Ready"}, "test", {}))
        self.assertFalse(gate.problems({"DPS": "DPS"}, {"DPS": "DPS"}, "test", {"test": {"DPS": "Gaming acronym"}}))

    def test_globals_and_empty_values_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frFR.lua"
            for source in ("local _,n=...; n.Locales={frFR={Ready='Prêt'}}; Unexpected=true",
                           "local _,n=...; n.Locales={frFR={Ready=''}}"):
                path.write_text(source, encoding="utf-8")
                with self.assertRaises(ValueError):
                    gate.locale_table(path, "frFR")


if __name__ == "__main__":
    unittest.main()
