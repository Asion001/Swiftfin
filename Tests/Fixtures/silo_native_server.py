#!/usr/bin/env python3
"""Synthetic Silo native fixture, audited at 60b903e7d44b68c5a9630cbd10df9bb0513e43e0.
Loopback only; no real credentials or media. Run with --port 8781.
"""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit

PROFILES = [
    dict(id="child", name="Zoë", has_pin=False, is_child=True, is_primary=False),
    dict(id="adult", name="Alex", has_pin=True, is_child=False, is_primary=True),
]
ITEM = dict(content_id="film:日本語?1", type="movie", title="Northern Lights", runtime=90, year=2026)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Do not log credentials, PINs, request bodies or signed URLs.

    def reply(self, value, status=200):
        body = json.dumps(value).encode() if value is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self.route("POST")

    def do_GET(self):
        self.route("GET")

    def route(self, method):
        parsed = urlsplit(self.path)
        if parsed.path.startswith("/redirect/"):
            self.send_response(307)
            self.send_header("Location", "/silo/api/v1/auth/login")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if not parsed.path.startswith("/silo/api/v1/"):
            return self.reply({}, 404)
        path = unquote(parsed.path[len("/silo/api/v1/"):])
        query = parse_qs(parsed.query)
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self.reply({}, 400)
        if path == "auth/providers" and method == "GET":
            return self.reply([dict(id="local", display_name="Password", mode="password", default=True)])
        if path == "auth/login" and method == "POST":
            if body.get("username") != "fixture" or body.get("password") != "fixture":
                return self.reply(dict(error="invalid_credentials"), 401)
            self.server.revoked = False
            return self.reply(dict(access_token="fixture-access-1", refresh_token="fixture-refresh-1", expires_in=900, user=dict(id=7)))
        if path == "auth/refresh" and method == "POST":
            if body.get("refresh_token") != "fixture-refresh-1" or self.server.revoked:
                return self.reply(dict(error="invalid_token"), 401)
            return self.reply(dict(access_token="fixture-access-2", refresh_token="fixture-refresh-2", expires_in=900))
        token = self.headers.get("Authorization")
        if token not in ("Bearer fixture-access-1", "Bearer fixture-access-2") or self.server.revoked:
            return self.reply(dict(error="unauthorized"), 401)
        if path == "auth/logout" and method == "POST":
            self.server.revoked = True
            return self.reply(None, 204)
        if path == "profiles" and method == "GET":
            return self.reply(dict(profiles=PROFILES))
        if path == "profiles/adult/verify-pin" and method == "POST":
            return self.reply(dict(valid=True, profile_token="fixture-proof") if body.get("pin") == "1234" else dict(valid=False))
        if method != "GET":
            return self.reply({}, 405)
        profile = self.headers.get("X-Profile-Id")
        if profile not in ("child", "adult"):
            return self.reply(dict(error="profile_required"), 400)
        if profile == "adult" and self.headers.get("X-Profile-Token") != "fixture-proof":
            return self.reply(dict(error="profile_unverified"), 403)
        # Force one native token renewal during the catalog flow.
        if token == "Bearer fixture-access-1":
            return self.reply(dict(error="unauthorized"), 401)
        if path == "user/libraries":
            return self.reply([dict(id=1, name="Films", type="movie")])
        if path == "catalog":
            if query.get("library_id") != ["1"]:
                return self.reply({}, 400)
            matches = query.get("q", [""])[0].casefold() in ITEM["title"].casefold()
            items = [ITEM] if matches else []
            return self.reply(dict(items=items, total=len(items), total_exact=True, has_more=False, snapshot="2026-09-13T10:00:00Z"))
        if path == "catalog/items/" + ITEM["content_id"]:
            return self.reply(dict(ITEM, overview="A synthetic native catalog fixture."))
        self.reply({}, 404)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8781)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.revoked = False
    print(f"Silo fixture listening on http://127.0.0.1:{args.port}/silo", flush=True)
    server.serve_forever()
