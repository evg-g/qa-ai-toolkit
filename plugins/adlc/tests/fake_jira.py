#!/usr/bin/env python3
"""A tiny in-memory Jira (REST v2 subset) for testing the Jira tracker adapter.

  python3 fake_jira.py <port-file>    listens on a free port and writes it to <port-file>

Seeds issue DEMO-7 in status "To Do" with a workflow To Do -> Refining -> Ready for Agent ->
In Progress -> In Review -> Done. Requires basic auth (any email, token "secret").
"""

import base64
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

ISSUES = {
    "DEMO-7": {
        "summary": "Export a CSV of fridge readings",
        "status": "To Do",
        "assignee": None,
        "description": "As a clinic admin I want a CSV.\n\n# The CSV has one row per reading.",
        "comments": [],
    }
}
FLOW = ["To Do", "Refining", "Ready for Agent", "In Progress", "In Review", "Done"]
ME = {"accountId": "acc-1", "displayName": "Test User"}
NEXT_ID = [100]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, obj=None):
        raw = json.dumps(obj).encode() if obj is not None else b""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n)) if n else {}

    def authed(self):
        h = self.headers.get("Authorization", "")
        if not h.startswith("Basic "):
            return False
        return base64.b64decode(h[6:]).decode().endswith(":secret")

    def route(self, method):
        if not self.authed():
            return self.send(401, {"errorMessages": ["unauthorized"]})
        path = self.path.split("?")[0]
        if path == "/rest/api/2/myself":
            return self.send(200, ME)
        m = re.match(r"^/rest/api/2/issue/([A-Z]+-\d+)(/.*)?$", path)
        if not m or m.group(1) not in ISSUES:
            return self.send(404, {"errorMessages": ["Issue does not exist"]})
        issue, sub = ISSUES[m.group(1)], m.group(2) or ""
        if sub == "" and method == "GET":
            return self.send(200, {"key": m.group(1), "fields": {
                "summary": issue["summary"], "status": {"name": issue["status"]},
                "assignee": issue["assignee"], "description": issue["description"]}})
        if sub == "" and method == "PUT":
            issue["description"] = self.body()["fields"]["description"]
            return self.send(204)
        if sub == "/assignee" and method == "PUT":
            issue["assignee"] = {"displayName": ME["displayName"]} if self.body().get("accountId") == "acc-1" else None
            return self.send(204)
        if sub == "/transitions" and method == "GET":
            i = FLOW.index(issue["status"])
            nxt = FLOW[i + 1:i + 2] + FLOW[:1]
            return self.send(200, {"transitions": [{"id": str(FLOW.index(n)), "name": "Move to " + n, "to": {"name": n}} for n in nxt]})
        if sub == "/transitions" and method == "POST":
            issue["status"] = FLOW[int(self.body()["transition"]["id"])]
            return self.send(204)
        if sub == "/comment" and method == "GET":
            return self.send(200, {"startAt": 0, "total": len(issue["comments"]), "comments": issue["comments"]})
        if sub == "/comment" and method == "POST":
            NEXT_ID[0] += 1
            # Jira Cloud stores wiki markup as ADF and renders it back with CRLF sometimes;
            # simulate that so the adapter's normalisation is exercised.
            c = {"id": str(NEXT_ID[0]), "body": self.body()["body"].replace("\n", "\r\n")}
            issue["comments"].append(c)
            return self.send(201, c)
        m2 = re.match(r"^/comment/(\d+)$", sub)
        if m2 and method == "PUT":
            for c in issue["comments"]:
                if c["id"] == m2.group(1):
                    c["body"] = self.body()["body"]
                    return self.send(200, c)
            return self.send(404, {})
        return self.send(405, {})

    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")

    def do_PUT(self):
        self.route("PUT")


if __name__ == "__main__":
    srv = HTTPServer(("127.0.0.1", 0), Handler)
    with open(sys.argv[1], "w") as f:
        f.write(str(srv.server_address[1]))
    srv.serve_forever()
