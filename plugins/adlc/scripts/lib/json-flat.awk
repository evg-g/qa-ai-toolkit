# json-flat.awk — flatten a JSON document into "path<TAB>value" lines, POSIX awk only.
#
#   {"bindings": {"pw": {"surface": ["ui"], "runner": "playwright"}}}
# becomes
#   bindings/pw/surface/0<TAB>ui
#   bindings/pw/runner<TAB>playwright
#
# Strings are unescaped for \" \\ \/ \n \t; other escapes are kept as written. It exists so
# the gates can read surface-bindings.json without jq. On a parse error it prints
# "json-flat: <reason> at offset <n>" to stderr and exits 1.

function fail(msg) { printf "json-flat: %s at offset %d\n", msg, pos > "/dev/stderr"; failed = 1; exit 1 }
function ws() { while (pos <= len && index(" \t\r\n", substr(s, pos, 1)) > 0) pos++ }
function peek() { ws(); return substr(s, pos, 1) }

function parse_string(    out, c, n) {
  if (substr(s, pos, 1) != "\"") fail("expected a string")
  pos++
  out = ""
  while (pos <= len) {
    c = substr(s, pos, 1)
    if (c == "\"") { pos++; return out }
    if (c == "\\") {
      n = substr(s, pos + 1, 1)
      if (n == "n") out = out "\n"
      else if (n == "t") out = out "\t"
      else if (n == "\"" || n == "\\" || n == "/") out = out n
      else out = out "\\" n
      pos += 2
      continue
    }
    out = out c
    pos++
  }
  fail("unterminated string")
}

function parse_value(path,    c, key, i, start) {
  c = peek()
  if (c == "{") {
    pos++
    if (peek() == "}") { pos++; return }
    while (1) {
      if (peek() != "\"") fail("expected an object key")
      key = parse_string()
      if (peek() != ":") fail("expected ':'")
      pos++
      parse_value(path == "" ? key : path "/" key)
      c = peek()
      if (c == ",") { pos++; continue }
      if (c == "}") { pos++; return }
      fail("expected ',' or '}'")
    }
  }
  if (c == "[") {
    pos++
    if (peek() == "]") { pos++; return }
    i = 0
    while (1) {
      parse_value(path "/" i)
      i++
      c = peek()
      if (c == ",") { pos++; continue }
      if (c == "]") { pos++; return }
      fail("expected ',' or ']'")
    }
  }
  if (c == "\"") { printf "%s\t%s\n", path, parse_string(); return }
  start = pos
  while (pos <= len && index(",}] \t\r\n", substr(s, pos, 1)) == 0) pos++
  if (pos == start) fail("expected a value")
  printf "%s\t%s\n", path, substr(s, start, pos - start)
}

{ s = s $0 "\n" }

END {
  if (failed) exit 1
  len = length(s)
  pos = 1
  parse_value("")
  ws()
  if (pos <= len) fail("trailing content")
}
