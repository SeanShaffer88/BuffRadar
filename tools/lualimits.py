"""Rough Lua 5.1 limit checker for BuffRadar.lua (WoW's Lua is 5.1).

Checks the two compile-time limits most likely to break a big single-file addon:
  * at most 200 active local variables in the main chunk (LUAI_MAXVARS)
  * at most 60 upvalues per function (LUAI_MAXUPVALUES)
Approximate: top-level code is assumed to start at column 0 (the file's style),
and a top-level `do` ... `end` pair at column 0 scopes the locals inside it.
"""
import re
import sys

KEYWORDS = set("and break do else elseif end false for function if in local nil not or repeat return then true until while".split())


def strip(src):
    # remove long comments/strings, comments, then short strings (keep line count)
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", lambda m: "\n" * m.group(0).count("\n"), src, flags=re.S)
    src = re.sub(r"\[(=*)\[.*?\]\1\]", lambda m: '""' + "\n" * m.group(0).count("\n"), src, flags=re.S)
    src = re.sub(r"--[^\n]*", "", src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", src)
    return src


def top_level_locals(lines):
    """Count main-chunk locals in scope, tracking every block keyword.

    Blocks open on function / if / do / repeat and close on end / until (a
    for/while loop opens through its `do`). A `local` statement belongs to the
    main chunk when every open block is a plain `do` block, which is exactly
    when its variables occupy main-chunk registers.
    """
    stack = []  # entries: ("do", active_len) for plain do-blocks, ("x", None) otherwise
    active, peak, peak_line = [], 0, 0
    tok = re.compile(r"(?<![.:\w])(function|if|do|repeat|end|until|while|for|local)(?!\w)")
    for i, line in enumerate(lines, 1):
        # a `local` statement at main-chunk level?
        if all(kind == "do" for kind, _ in stack):
            s = line.strip()
            m = re.match(r"^local\s+function\s+([A-Za-z_]\w*)", s)
            if m:
                names = [m.group(1)]
            else:
                m = re.match(r"^local\s+([A-Za-z_][\w\s,]*?)\s*(=|$)", s)
                names = [n.strip() for n in m.group(1).split(",")] if m else []
            for n in names:
                active.append((n, i))
            if len(active) > peak:
                peak, peak_line = len(active), i
        loop_pending = 0
        for t in tok.findall(line):
            if t in ("while", "for"):
                loop_pending += 1
            elif t == "do":
                if loop_pending:
                    loop_pending -= 1
                    stack.append(("x", None))
                else:
                    stack.append(("do", len(active)))
            elif t in ("function", "if", "repeat"):
                stack.append(("x", None))
            elif t in ("end", "until"):
                if stack:
                    kind, mark = stack.pop()
                    if kind == "do":
                        del active[mark:]
    if stack:
        print(f"  WARNING: {len(stack)} block(s) left open at end of file")
    return peak, peak_line, active


def functions(lines):
    """Column-0 function definitions -> (start, end) using keyword balance."""
    out = []
    i = 0
    n = len(lines)
    opener = re.compile(r"\b(function|do|then|repeat)\b")
    while i < n:
        line = lines[i]
        if re.match(r"^(local\s+)?function\b|^[A-Za-z_][\w.]*\s*=\s*function\b|^[A-Za-z_][\w.:]*\(.*function\b", line):
            depth = 0
            j = i
            while j < n:
                toks = re.findall(r"\b(function|do|then|repeat|end|until|elseif)\b", lines[j])
                for t in toks:
                    if t in ("function", "do", "repeat"):
                        depth += 1
                    elif t == "then":
                        depth += 1
                    elif t == "elseif":
                        depth -= 1  # elseif ... then: the then re-opens
                    elif t in ("end", "until"):
                        depth -= 1
                # `while x do` / `for ... do` count via do; `if ... then` via then
                if depth <= 0 and j > i or (depth <= 0 and toks and j == i and "end" in toks):
                    break
                j += 1
            out.append((i, j))
            i = j + 1
        else:
            i += 1
    return out


def main(path):
    src = strip(open(path, encoding="utf-8").read())
    lines = src.split("\n")
    peak, peak_line, active = top_level_locals(lines)
    print(f"{path}\n  main chunk: peak {peak} active locals (limit 200) at line {peak_line}")
    top = {}
    for name, ln in active:
        top.setdefault(name, ln)
    # also include block-scoped ones for upvalue purposes (approximate)
    for i, line in enumerate(lines, 1):
        m = re.match(r"^local\s+function\s+([A-Za-z_]\w*)", line) or re.match(r"^local\s+([A-Za-z_][\w\s,]*?)\s*(=|$)", line)
        if m:
            for nm in m.group(1).split(","):
                top.setdefault(nm.strip(), i)
    worst = []
    for s, e in functions(lines):
        body = "\n".join(lines[s:e + 1])
        idents = set(re.findall(r"(?<![.:\w])([A-Za-z_]\w*)", body)) - KEYWORDS
        declared = set(re.findall(r"\blocal\s+function\s+([A-Za-z_]\w*)", body))
        for grp in re.findall(r"\blocal\s+([A-Za-z_][\w\s,]*?)\s*(?:=|\n|$)", body):
            declared |= {g.strip() for g in grp.split(",")}
        for grp in re.findall(r"\bfunction\s*[\w.:]*\s*\(([^)]*)\)", body):
            declared |= {g.strip() for g in grp.split(",") if g.strip()}
        for grp in re.findall(r"\bfor\s+([\w\s,]+?)\s+(?:in|=)", body):
            declared |= {g.strip() for g in grp.split(",")}
        own = re.match(r"^(?:local\s+)?function\s+([A-Za-z_]\w*)|^([A-Za-z_]\w*)\s*=", lines[s])
        ups = {x for x in idents if x in top and top[x] < s + 1 and x not in declared}
        worst.append((len(ups), s + 1, lines[s].strip()[:60]))
    worst.sort(reverse=True)
    print("  most upvalues (limit 60):")
    for cnt, ln, head in worst[:6]:
        print(f"    {cnt:3d}  line {ln}: {head}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
