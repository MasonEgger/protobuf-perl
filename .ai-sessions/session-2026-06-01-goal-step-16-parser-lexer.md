# Session 2026-06-01 — Step 16: Parser Lexer (Proto3::Parser::Lexer)

Begins Phase 3 (the parser). First component: the hand-written tokenizer for
`.proto` source.

## What changed

- **`lib/Proto3/Parser/Lexer.pm`** (new) — hand-written tokenizer producing an
  ordered token stream of `{ type, value, line, col }` hashes. Written as a
  plain package with methods (not `feature 'class'`) — simpler for a stateful
  cursor and sidesteps the class-feature bareword traps.
  - **Token types:** `ident`, `fullident` (dotted, single token), `keyword`
    (table-driven `%KEYWORD` — proto3 grammar words + scalar type names),
    `int` (decimal / hex `0x..` / octal `0NN`, decoded to numeric value),
    `float` (incl. exponent and leading-dot `.5`), `bool` (`true`/`false` →
    `1`/`0`), `string` (single- AND double-quoted, with escape decoding),
    `punct` (single chars from table-driven `%PUNCT`).
  - **String escapes:** `\n \t \r \a \b \f \v \\ \" \' \?` via `%SIMPLE_ESCAPE`;
    hex `\xNN` (1–2 hex digits → byte); octal `\NNN` (1–3 octal digits → byte).
    Unknown escapes kept literally (lenient).
  - **Comments discarded:** `//` line comments and `/* */` block comments
    (including multi-line) produce no tokens.
  - **Positions:** every token carries 1-based `line` and `col` of its first
    character; `_advance` tracks newline → line bump + col reset.
  - **Errors:** unterminated string literal and unterminated block comment raise
    `Proto3::Exception::Parser` with `line`/`column` pointing at the start of the
    offending construct.
  - Full POD documenting every token kind and the public API.
- **`lib/Proto3/Exception.pm`** — `Proto3::Exception::Parser` gained `line` and
  `column` `:param` fields plus explicit `line`/`column` reader methods, so all
  parser errors (lexer and later grammar) can carry source positions. Subclasses
  inherit them.
- **`t/parser/lexer.t`** (new) — covers 16.1–16.7: identifiers/fullIdent,
  int (dec/hex/oct), float, bool; string escapes (`\n \t \" \\ \xNN` octal);
  keyword-vs-identifier (`message` keyword vs `messages` ident); punctuation;
  comment discarding (line, block, multi-line); line+col on a multi-line sample;
  unterminated string and unterminated block comment → typed `Parser` error with
  position.
- **`todo.md`** — checked off 16.1–16.11.

## Why

Step 16 (spec §4.4) opens Phase 3. The grammar (Step 17+) consumes this token
stream, so the lexer must classify tokens correctly, decode literal values,
discard comments, and preserve source positions for error reporting.

## How / decisions

- Plain package, not `feature 'class'`: the lexer is a mutable cursor and the
  per-character `_advance`/`_peek` helpers read more naturally as ordinary subs;
  also avoids the documented 5.38.2 bareword-inside-class-method trap.
- `fullident` is a single token (dotted run) rather than ident-dot-ident — the
  grammar wants dotted names (type refs, package names) as one unit, and `.5`
  vs `foo.bar` is disambiguated by whether the char after the dot is a digit.
- Table-driven keyword and punctuation recognition (16.9) is the natural shape,
  baked in from the start rather than refactored later.
- One test-quoting fix during GREEN: the "escaped backslash" case needs proto
  source `"a\\b"` (two backslashes), which is `q{"a\\\\b"}` in a Perl `q{}`
  literal — the original `q{"a\\b"}` was actually a `\b` (backspace) escape.

## Verification

- Final gate (single sequential command):
  `perl -Ilib -c lib/Proto3/Parser/Lexer.pm && prove -lr t` → Result: PASS,
  GATE_EXIT=0.

## Next steps

- Step 17: Grammar core (`Proto3::Parser::Grammar`) — syntax/package/message,
  one field per scalar type, json_name camelCase default, label handling,
  consuming this token stream via a cursor abstraction.
