"""Independent mutation fixtures for visible prose and catalog identity."""
import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location("calls",Path(__file__).with_name("localization_callsites.py"))
calls=importlib.util.module_from_spec(spec);spec.loader.exec_module(calls)
class CallsiteTests(unittest.TestCase):
    def test_visible_direct_callback_and_nested_format_are_found(self):
        for source in ('Print("Untranslated user message")', 'Tip(button, L["Title"], function() return "Untranslated tooltip" end)', 'label:SetText(string.format("Missing %d buffs", n))', 'X.ShowExport(text,false,"Untranslated copy title")', 'X.PrintDiff(text,"Untranslated label")'):
            self.assertTrue(calls.candidates(source),source)
    def test_localized_literal_and_conditional_labels_are_allowed(self):
        for source in ('Print(L["Translated message"])','label:SetText(L[blocked and "Blocked" or "Ready"])','Tip(b,L["Title"],L["Help"])'):
            self.assertFalse(calls.candidates(source),source)
    def test_comments_do_not_create_or_hide_callsite(self):
        self.assertFalse(calls.candidates('-- Print("comment")'))
        self.assertTrue(calls.candidates('-- harmless\nPrint("Real prose")'))
if __name__=="__main__":unittest.main()
