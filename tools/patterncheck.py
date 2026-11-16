"""Fail when a Lua pattern call could treat user text as a pattern.

string.find / match / gmatch / gsub interpret their pattern argument, so a
pattern built from player names, chat, imports or edit boxes can raise
("malformed pattern") or match the wrong thing. Every pattern argument in the
addon must be a string literal, or the call must be a plain find
(`:find(x, init, true)`). Usage: python tools/patterncheck.py FILE...
"""

import re
import sys

CALL = re.compile(r"(?::|\bstring\.)(find|match|gmatch|gsub)\(")


def first_arg(text, start):
    """Return (argument, rest-of-call) for the call opened at text[start-1]."""
    depth, i, quote = 0, start, None
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return text[start:i], ""
            depth -= 1
        elif c == "," and depth == 0:
            end = text.find(")", i)
            return text[start:i], text[i:end + 1 if end >= 0 else len(text)]
        i += 1
    return text[start:], ""


def check(path):
    problems = []
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            code = line.split("--", 1)[0] if not line.lstrip().startswith("--[[") else ""
            for call in CALL.finditer(code):
                method = call.group(1)
                arg, rest = first_arg(code, call.end())
                if call.group(0).startswith("string."):
                    # string.find(s, pattern, ...): the pattern is the second argument.
                    arg, rest = first_arg(code, call.end() + len(arg) + 1)
                arg = arg.strip()
                if arg.startswith(("\"", "'", "[[")):
                    continue
                if method == "find" and re.search(r",\s*[^,]+,\s*true\s*\)?\s*$", rest.strip()):
                    continue
                problems.append(f"{path}:{number}: {method} pattern is not a literal: {line.strip()[:100]}")
    return problems


def main(paths):
    problems = [p for path in paths for p in check(path)]
    for problem in problems:
        print(problem)
    print(f"patterncheck: {len(paths)} file(s), {len(problems)} non-literal pattern(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
