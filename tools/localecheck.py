"""Strict private Lua locale completeness, formatting and literal-command gate."""
import json
from pathlib import Path
import re
import sys
from lupa import lua51

REQUIRED = {"deDE", "esES", "frFR", "ruRU", "zhCN"}
FORMAT = re.compile(r"%%|%[-+#0 ]*[0-9]*(?:\.[0-9]+)?[cdiouxXeEfgGqs]")
COMMAND = re.compile(r"/br\s+([a-z][a-z0-9]*)\b")
# Actual machine options, never a greedy span of adjacent translated prose.
OPTIONS = {
    "coordinate": {"panel", "on", "off", "request", "need", "review", "publish", "status", "inbox", "accept", "decline"},
    "config": {"navigate", "narrate"}, "storage": {"delete", "profile", "ignore"},
    "theme": {"priority", "panel", "list", "up", "down", "reset"},
    "plates": {"on", "off", "names", "bars", "restore"},
    "readiness": {"personal", "show", "hide", "next", "prev", "aura", "off"},
    "smartprio": {"on", "off", "list", "here", "clear", "instance"},
    "debuff": {"on", "off", "list", "add", "remove", "player", "focus"},
    "prep": {"show", "personal", "hide", "next", "prev"},
    "positions": {"on", "off", "reset"}, "bless": {"complement", "on", "off"},
    "forecast": {"timer", "off"}, "subgroup": {"ALL", "NONE", "BUFF"}, "ready": {"next"},
}


def english_table(path):
    source = Path(path).read_text(encoding="utf-8-sig")
    match = re.search(r"^local L = (\{.*?^\})", source, re.S | re.M)
    if not match:
        raise ValueError("could not find English L table")
    return dict(lua51.LuaRuntime().execute("return " + match.group(1)).items())


def locale_table(path, code):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    env, ns = lua.table(), lua.table()
    lua.eval("function(s,e,n) setfenv(assert(loadstring(s)),e)('BuffRadar',n) end")(
        Path(path).read_text(encoding="utf-8-sig"), env, ns)
    if list(env.items()) or set(dict(ns.items())) != {"Locales"}:
        raise ValueError("locale wrote unexpected globals or namespace fields")
    packs = dict(ns.Locales.items()) if lua51.lua_type(ns.Locales) == "table" else {}
    if set(packs) != {code} or lua51.lua_type(packs[code]) != "table":
        raise ValueError("expected one namespace-private locale pack")
    pack = dict(packs[code].items())
    if any(not isinstance(k, str) or not isinstance(v, str) or not v.strip() for k, v in pack.items()):
        raise ValueError("expected nonempty string translations")
    return pack


def formats(text):
    result, pos = [], 0
    while pos < len(text):
        if text[pos] != "%":
            pos += 1
            continue
        match = FORMAT.match(text, pos)
        result.append(match.group()[-1] if match else "bare-percent")
        pos = match.end() if match else pos + 1
    return result


def markup(text):
    tokens, colors = [], 0
    for match in re.finditer(r"\|c[0-9a-fA-F]{8}|\|r|\|H[^|]*\|h[^|]*\|h|\|T[^|]*\|t|\|A[^|]*\|a", text):
        token = match.group()
        if token.startswith("|c"):
            colors += 1
            tokens.append(token.lower())
        elif token == "|r":
            if not colors:
                word = re.match(r"[A-Za-z]+", text[match.start() + 1:])
                if word and word.group() in {"request", "review", "reset", "restore"}:
                    continue  # literal machine-option separators, not color resets
                raise ValueError("unbalanced color close")
            colors -= 1
            tokens.append(token)
        elif token.startswith("|H"):
            tokens.append(token.split("|h", 1)[0] + "|h|h")
        else:
            tokens.append(token)
    if colors:
        raise ValueError("unbalanced color open")
    stripped = re.sub(r"\|H[^|]*\|h[^|]*\|h|\|T[^|]*\|t|\|A[^|]*\|a", "", text)
    if re.search(r"\|[HTA]", stripped):
        raise ValueError("unbalanced hyperlink/texture markup")
    return tokens


def command_signature(text, source=None):
    original, translated = list(COMMAND.finditer(source or text)), list(COMMAND.finditer(text))
    result = []
    if [m.group(1) for m in original] != [m.group(1) for m in translated]:
        return [m.group(1) for m in translated], []
    for index, (src, dst) in enumerate(zip(original, translated)):
        allowed, expected = OPTIONS.get(src.group(1), set()), []
        end = original[index + 1].start() if index + 1 < len(original) else len(source or text)
        for token in re.findall(r"<[^>]*>|\[[^\]]*\]|[A-Za-z][A-Za-z0-9]*|[.;]", (source or text)[src.end():end]):
            if token.startswith(("<", "[")):
                expected.extend(word for word in re.findall(r"[A-Za-z][A-Za-z0-9]*", token) if word in allowed)
            elif token in allowed:
                expected.append(token)
            elif token not in {"or", "and"}:
                break
        end = translated[index + 1].start() if index + 1 < len(translated) else len(text)
        words = re.findall(r"[A-Za-z][A-Za-z0-9]*", text[dst.end():end])
        result.append([word for word in words if word in set(expected)])
    return [m.group(1) for m in translated], result


def problems(english, pack, code, identical):
    errors = [f"missing: {key!r}" for key in sorted(set(english) - set(pack))]
    errors += [f"unknown: {key!r}" for key in sorted(set(pack) - set(english))]
    for key in sorted(set(english) & set(pack)):
        value = pack[key]
        if not isinstance(value, str) or not value.strip():
            errors.append(f"empty/non-string: {key!r}")
            continue
        try:
            if formats(value) != formats(english[key]):
                raise ValueError("placeholder order/type/literal percent differs")
            if markup(value) != markup(english[key]):
                raise ValueError("markup differs")
            if command_signature(value, english[key]) != command_signature(english[key]):
                raise ValueError("literal command or option differs")
            if value == english[key] and key not in identical.get(code, {}):
                raise ValueError("identical English requires reviewed justification")
        except ValueError as error:
            errors.append(f"{key!r}: {error}")
    return errors


def main(addon, directory):
    english = english_table(addon)
    identical = json.loads(Path(__file__).with_name("locale-identical.json").read_text(encoding="utf-8"))
    bad = False
    for code in sorted(REQUIRED):
        try:
            pack = locale_table(Path(directory) / (code + ".lua"), code)
            errors = problems(english, pack, code, identical)
        except (OSError, ValueError, lua51.LuaError) as error:
            pack, errors = {}, [str(error)]
        print(f"{code}.lua: {'FAIL' if errors else 'OK'} - {len(pack)} of {len(english)} strings")
        for error in errors:
            print("  " + error)
        bad |= bool(errors)
    return int(bad)


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
