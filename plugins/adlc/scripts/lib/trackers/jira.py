#!/usr/bin/env python3
"""Jira tracker adapter for ADLC — REST API v2, Python 3 standard library only.

Works with Jira Cloud and Jira Server / Data Center. It talks to the REST API directly, so it
does not depend on any MCP connector or on one company's setup.

Environment:
  JIRA_BASE_URL     e.g. https://your-company.atlassian.net   (required)
  JIRA_EMAIL        + JIRA_API_TOKEN   -> basic auth (Jira Cloud)
  JIRA_PAT                             -> bearer token (Jira Server / Data Center)
  ADLC_STATUS_*     the tracker's status name per canonical state (set by adlc-tracker.sh)

The machine block lives in ONE dedicated comment whose whole body is a {noformat} panel
holding the block (feature: ... seal: "sha256:..."). {noformat} keeps the text verbatim, so
the seal survives the round trip. Nothing else is written into that comment.

Called by adlc-tracker.sh:  jira.py <action> <KEY> [file]
Exit codes: 0 ok, 1 tracker refused / not found, 2 usage or config, 3 no block, 4 two blocks.
"""

import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

STATES = ["draft", "in-refinement", "ready-for-agent", "in-progress", "in-review", "done"]
NOFORMAT_RE = re.compile(r"\{noformat\}\r?\n?(.*?)\r?\n?\{noformat\}", re.S)
SEAL_RE = re.compile(r'^seal: "sha256:[0-9a-f]{64}"\s*$', re.M)


def die(code, msg):
    print(f"jira tracker: {msg}", file=sys.stderr)
    sys.exit(code)


def base_url():
    url = os.environ.get("JIRA_BASE_URL", "").rstrip("/")
    if not url:
        die(2, "JIRA_BASE_URL is not set")
    return url


def auth_header():
    pat = os.environ.get("JIRA_PAT")
    if pat:
        return "Bearer " + pat
    email, token = os.environ.get("JIRA_EMAIL"), os.environ.get("JIRA_API_TOKEN")
    if email and token:
        return "Basic " + base64.b64encode(f"{email}:{token}".encode()).decode()
    die(2, "set JIRA_EMAIL + JIRA_API_TOKEN (Cloud) or JIRA_PAT (Server/Data Center)")


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base_url() + path, data=data, method=method)
    req.add_header("Authorization", auth_header())
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        die(1, f"{method} {path} -> HTTP {e.code}: {detail}")
    except urllib.error.URLError as e:
        die(1, f"{method} {path} -> {e.reason}")


def issue_path(key):
    return "/rest/api/2/issue/" + urllib.parse.quote(key)


def status_name(state):
    return os.environ.get("ADLC_STATUS_" + state.upper().replace("-", "_"), state)


def all_comments(key):
    out, start = [], 0
    while True:
        page = api("GET", f"{issue_path(key)}/comment?startAt={start}&maxResults=100")
        comments = page.get("comments", [])
        out.extend(comments)
        start += len(comments)
        if not comments or start >= page.get("total", 0):
            return out


def block_comments(key):
    """Comments that carry a sealed machine block: (comment, block-body)."""
    found = []
    for c in all_comments(key):
        body = c.get("body") or ""
        if not isinstance(body, str):
            continue
        m = NOFORMAT_RE.search(body)
        if m and SEAL_RE.search(m.group(1)):
            found.append((c, m.group(1).replace("\r\n", "\n").rstrip("\n")))
    return found


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def fence_body(path):
    """The body of the ```adlc fence in a block file."""
    lines, inside, body = read_text(path).splitlines(), False, []
    for line in lines:
        if not inside and re.match(r"^```adlc[ \t]*$", line):
            inside = True
            continue
        if inside and re.match(r"^```[ \t]*$", line):
            return "\n".join(body)
        if inside:
            body.append(line)
    die(2, f"{path} has no complete ```adlc block")


def cmd_fetch(key):
    f = api("GET", f"{issue_path(key)}?fields=summary,status,assignee,description")["fields"]
    assignee = (f.get("assignee") or {}).get("displayName", "unassigned")
    print(f"# {key}: {f.get('summary', '')}\n")
    print(f"- Status: {(f.get('status') or {}).get('name', '?')}")
    print(f"- Assignee: {assignee}\n")
    print(f.get("description") or "")


def cmd_status(key):
    name = api("GET", f"{issue_path(key)}?fields=status")["fields"]["status"]["name"]
    for s in STATES:
        if status_name(s).lower() == name.lower():
            print(s)
            return
    print("other:" + name)


def cmd_transition(key, state):
    target = status_name(state).lower()
    ts = api("GET", f"{issue_path(key)}/transitions")["transitions"]
    for t in ts:
        if t.get("to", {}).get("name", "").lower() == target or t.get("name", "").lower() == target:
            api("POST", f"{issue_path(key)}/transitions", {"transition": {"id": t["id"]}})
            print(f"jira tracker: {key} -> {status_name(state)}")
            return
    names = ", ".join(sorted({t.get("to", {}).get("name", t.get("name", "?")) for t in ts}))
    die(1, f"no transition from the current status to '{status_name(state)}' (available: {names}). "
           f"Fix the statuses: map in .claude/adlc-config.md or the Jira workflow.")


def cmd_claim(key):
    me = api("GET", "/rest/api/2/myself")
    body = {"accountId": me["accountId"]} if me.get("accountId") else {"name": me.get("name")}
    api("PUT", f"{issue_path(key)}/assignee", body)
    print(f"jira tracker: {key} assigned to {me.get('displayName', 'you')}")


def cmd_read_block(key, out):
    found = block_comments(key)
    if not found:
        die(3, f"{key} has no machine-block comment")
    if len(found) > 1:
        ids = ", ".join(c["id"] for c, _ in found)
        die(4, f"{key} has {len(found)} machine-block comments ({ids}); exactly one is allowed")
    with open(out, "w", encoding="utf-8") as f:
        f.write("```adlc\n" + found[0][1] + "\n```\n")


def cmd_write_block(key, path):
    body = "{noformat}\n" + fence_body(path) + "\n{noformat}"
    found = block_comments(key)
    if len(found) > 1:
        die(4, f"{key} already has {len(found)} machine-block comments; delete the extras by hand first")
    if found:
        cid = found[0][0]["id"]
        api("PUT", f"{issue_path(key)}/comment/{cid}", {"body": body})
        print(f"jira tracker: machine block updated in comment {cid}")
    else:
        c = api("POST", f"{issue_path(key)}/comment", {"body": body})
        print(f"jira tracker: machine block written to new comment {c.get('id')}")


def cmd_append(key, path):
    desc = api("GET", f"{issue_path(key)}?fields=description")["fields"].get("description") or ""
    text = read_text(path).strip("\n")
    api("PUT", issue_path(key), {"fields": {"description": (desc.rstrip("\n") + "\n\n" + text).lstrip("\n")}})
    print(f"jira tracker: appended to the description of {key}")


def cmd_comment(key, path):
    c = api("POST", f"{issue_path(key)}/comment", {"body": read_text(path)})
    print(f"jira tracker: comment {c.get('id')} added to {key}")


def main(argv):
    if len(argv) < 2:
        die(2, "usage: jira.py <action> <KEY> [file]")
    action, key, rest = argv[0], argv[1], argv[2:]
    one = {"fetch": cmd_fetch, "status": cmd_status, "claim": cmd_claim}
    two = {"transition": cmd_transition, "read-block": cmd_read_block,
           "write-block": cmd_write_block, "append": cmd_append, "comment": cmd_comment}
    if action in one and not rest:
        one[action](key)
    elif action in two and len(rest) == 1:
        two[action](key, rest[0])
    else:
        die(2, f"bad call: {action} {key} {' '.join(rest)}")


if __name__ == "__main__":
    main(sys.argv[1:])
