#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python - <<'PY'
import sys
from pathlib import Path

arg = Path(sys.argv[1]) if len(sys.argv)>1 else None
if arg is None:
    root = Path('.')
else:
    if arg.exists():
        root = arg
    else:
        # if user passed a short dir name like 'tui', try src/<name>
        alt = Path('src')/arg
        if alt.exists():
            root = alt
        else:
            # fall back to provided arg (it may be a glob)
            root = arg

# Use os.walk to robustly find .rs files in subfolders (handles symlinks and unusual paths)
files = {'rs': [], 'asm': [], 'c': [], 'html': [], 'css': [], 'sh': []}
for ext in ('rs','asm','c','html','css','sh'):
    for p in root.rglob(f"*.{ext}"):
        # skip any files under a "target" directory
        if 'target' in p.parts:
            continue
        files[ext].append(p)
    files[ext] = sorted(files[ext])

def analyze(s: str, ext: str='rs'):
    lines = s.splitlines()
    total_lines = len(lines)
    # per-line flags (we only use totals later)
    comment_only = [False]*total_lines
    inline_comment = [False]*total_lines
    doc_comment = [False]*total_lines
    block_comment = [False]*total_lines

    # ASM analysis is much simpler: just look for prefixes
    if ext == 'asm':
        prefixes = ['//', '#', ';']
        for idx, line in enumerate(lines):
            stripped = line.lstrip()
            if not stripped:
                continue
            for pref in prefixes:
                if stripped.startswith(pref):
                    comment_only[idx] = True
                    break
            else:
                # check for inline comments
                for pref in prefixes:
                    pos = line.find(pref)
                    if pos != -1 and line[:pos].strip():
                        inline_comment[idx] = True
                        break
        total_comment_lines = sum(1 for i in range(total_lines) if comment_only[i] or inline_comment[i])
        return {
            'total_lines': total_lines,
            'comment_only': sum(comment_only),
            'inline_comment': sum(inline_comment),
            'doc_comment': 0,
            'block_comment': 0,
            'total_comment_lines': total_comment_lines,
        }

    # HTML needs <!-- --> comment handling
    if ext == 'html':
        inside = False
        for idx, line in enumerate(lines):
            i = 0
            while i < len(line):
                if not inside and line.startswith('<!--', i):
                    inside = True
                    comment_only[idx] = True
                    i += 4
                    continue
                if inside:
                    comment_only[idx] = True
                    if line.startswith('-->', i):
                        inside = False
                        i += 3
                        continue
                i += 1
        total_comment_lines = sum(1 for i in range(total_lines) if comment_only[i])
        return {
            'total_lines': total_lines,
            'comment_only': sum(comment_only),
            'inline_comment': sum(inline_comment),
            'doc_comment': 0,
            'block_comment': 0,
            'total_comment_lines': total_comment_lines,
        }

    # shell files use simple '#' comments
    if ext == 'sh':
        for idx, line in enumerate(lines):
            stripped = line.lstrip()
            if not stripped:
                continue
            if stripped.startswith('#'):
                comment_only[idx] = True
            else:
                pos = line.find('#')
                if pos != -1 and line[:pos].strip():
                    inline_comment[idx] = True
        total_comment_lines = sum(1 for i in range(total_lines) if comment_only[i] or inline_comment[i])
        return {
            'total_lines': total_lines,
            'comment_only': sum(comment_only),
            'inline_comment': sum(inline_comment),
            'doc_comment': 0,
            'block_comment': 0,
            'total_comment_lines': total_comment_lines,
        }

    # existing Rust-style logic
    n = len(s)
    i = 0
    line_idx = 0
    line_start = 0
    in_string = False
    delim = ''
    raw = False
    raw_hashes = 0
    escape = False
    block_depth = 0

    while i < n:
        c = s[i]
        nxt = s[i+1] if i+1 < n else ''

        if c == '\n':
            line_idx += 1
            line_start = i+1
            i += 1
            continue

        if block_depth > 0:
            block_comment[line_idx] = True
            if c == '/' and nxt == '*':
                block_depth += 1
                i += 2
                continue
            if c == '*' and nxt == '/':
                block_depth -= 1
                i += 2
                continue
            i += 1
            continue

        if in_string:
            if raw:
                closing = '"' + ('#'*raw_hashes)
                if s.startswith(closing, i):
                    in_string = False
                    raw = False
                    i += len(closing)
                    continue
                i += 1
                continue
            if escape:
                escape = False
                i += 1
                continue
            if c == '\\':
                escape = True
                i += 1
                continue
            if c == delim:
                in_string = False
            i += 1
            continue

        # not in string or block
        if c == '/' and nxt == '/':
            # check if comment starts at beginning (after whitespace)
            prefix = s[line_start:i]
            if prefix.strip() == '':
                comment_only[line_idx] = True
            else:
                inline_comment[line_idx] = True
            # doc comment check
            after = s[i:i+3]
            if after in ('///','//!'):
                doc_comment[line_idx] = True
            # skip to end of line
            while i < n and s[i] != '\n': i += 1
            continue

        if c == '/' and nxt == '*':
            block_depth = 1
            block_comment[line_idx] = True
            i += 2
            continue

        if c == 'r' and (nxt == '"' or nxt == '#'):
            j = i+1
            hashes = 0
            while j < n and s[j] == '#':
                hashes += 1; j += 1
            if j < n and s[j] == '"':
                in_string = True; raw = True; raw_hashes = hashes
                i = j+1
                continue

        if c == '"':
            in_string = True
            delim = c
            i += 1
            continue
        if c == "'":
            # Only treat as a char literal for short patterns like 'a' or '\n'
            if i + 2 < n and s[i + 2] == "'":
                # simple char literal like 'a'
                i += 3
                continue
            if i + 3 < n and s[i + 1] == "\\" and s[i + 3] == "'":
                # escaped char literal like '\\n'
                i += 4
                continue
            # Otherwise this is likely a lifetime (e.g. 'a) — don't enter string mode
            i += 1
            continue

        i += 1

    total_comment_lines = sum(1 for i in range(total_lines) if comment_only[i] or inline_comment[i] or block_comment[i] or doc_comment[i])
    return {
        'total_lines': total_lines,
        'comment_only': sum(comment_only),
        'inline_comment': sum(inline_comment),
        'doc_comment': sum(doc_comment),
        'block_comment': sum(block_comment),
        'total_comment_lines': total_comment_lines,
    }

# define column widths
file_w = 50
lines_w = 6
comments_w = 8

def print_table(ext, files_list):
    print(f"Analyzing .{ext} files under {root}\n")
    print(f"+{'-'*file_w}+{'-'*lines_w}+{'-'*comments_w}+")
    print(f"|{'File':^{file_w}}|{'Lines':^{lines_w}}|{'Comments':^{comments_w}}|")
    print(f"+{'='*file_w}+{'='*lines_w}+{'='*comments_w}+")
    totals = {'total_lines':0, 'total_comment_lines':0, 'doc_comment':0}
    for f in files_list:
        s = f.read_text()
        a = analyze(s, ext)
        totals['total_lines'] += a['total_lines']
        totals['total_comment_lines'] += a['total_comment_lines']
        totals['doc_comment'] += a.get('doc_comment', 0)
        print(f"|{str(f):<{file_w}}|{a['total_lines']:>{lines_w}}|{a['total_comment_lines']:>{comments_w}}|")
    print(f"+{'-'*file_w}+{'-'*lines_w}+{'-'*comments_w}+")
    print(f"|{'TOTAL':<{file_w}}|{totals['total_lines']:>{lines_w}}|{totals['total_comment_lines']:>{comments_w}}|")
    print(f"+{'-'*file_w}+{'-'*lines_w}+{'-'*comments_w}+")
    print()
    return totals

summary = []
for ext in ('rs','c','asm','html','css','sh'):
    if files.get(ext):
        tot = print_table(ext, files[ext])
        summary.append((ext, tot['total_lines'], tot.get('doc_comment', 0)))

# print summary table if we found anything
if summary:
    lang_w = 6
    lines_w = 6
    docs_w = 6
    print("Summary of languages found:\n")
    print(f"+{'-'*lang_w}+{'-'*lines_w}+{'-'*docs_w}+")
    print(f"|{'lang':^{lang_w}}|{'lines':^{lines_w}}|{'docs':^{docs_w}}|")
    print(f"+{'='*lang_w}+{'='*lines_w}+{'='*docs_w}+")
    for lang, lines, docs in summary:
        print(f"|{lang:^{lang_w}}|{lines:>{lines_w}}|{docs:>{docs_w}}|")
    print(f"+{'-'*lang_w}+{'-'*lines_w}+{'-'*docs_w}+")
PY
