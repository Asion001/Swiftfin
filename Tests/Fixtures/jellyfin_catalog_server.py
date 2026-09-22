#!/usr/bin/env python3
"""Loopback-only Jellyfin catalog fixture. Sign in with fixture / fixture."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
from urllib.parse import parse_qs, urlsplit, unquote

LIBRARY = {"Id": "movies", "Name": "Movies", "Type": "CollectionFolder", "IsFolder": True}
ITEMS = [
    {"Id": "northern-lights", "Name": "Northern Lights", "Type": "Movie", "ProductionYear": 2024,
     "RunTimeTicks": 54000000000, "ImageTags": {"Primary": "fixture-poster-v1"},
     "Overview": "A journey through the winter landscapes of the far north."},
    {"Id": "city-walks", "Name": "City Walks", "Type": "Folder", "IsFolder": True,
     "Overview": "Short films exploring cities on foot."},
]
CHILD = {"Id": "evening", "Name": "An Evening in Warsaw", "Type": "Movie", "ProductionYear": 2025,
         "Overview": "An evening walk along the river.", "RunTimeTicks": 12000000000}


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path.startswith("/redirect/"):
            self.send_response(307)
            self.send_header("Location", "/jellyfin/Users/AuthenticateByName")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path != "/jellyfin/Users/AuthenticateByName":
            return self.reply(404, {})
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        if body != {"Username": "fixture", "Pw": "fixture"}:
            return self.reply(401, {})
        if not self.headers.get("Authorization", "").startswith("MediaBrowser "):
            return self.reply(400, {})
        self.reply(200, {"AccessToken": "fixture-token", "User": {"Id": "fixture-user"}})

    def do_GET(self):
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if self.headers.get("X-Emby-Token") != "fixture-token":
            return self.reply(401, {})
        if url.path == "/jellyfin/Items/northern-lights/Images/Primary":
            data = (Path(__file__).parent / "artwork/northern-lights.png").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if query.get("userId") != ["fixture-user"]:
            return self.reply(401, {})
        if url.path == "/jellyfin/UserViews":
            return self.reply(200, {"Items": [LIBRARY], "TotalRecordCount": 1})
        if url.path == "/jellyfin/Items":
            values = [CHILD] if query.get("parentId") == ["city-walks"] else ITEMS
            search = query.get("searchTerm", [""])[0].casefold()
            if search:
                values = [item for item in values + [CHILD] if search in item["Name"].casefold()]
            start = int(query.get("startIndex", ["0"])[0])
            limit = int(query.get("limit", ["80"])[0])
            return self.reply(200, {"Items": values[start:start + limit], "TotalRecordCount": len(values)})
        for item in [LIBRARY, *ITEMS, CHILD]:
            if unquote(url.path) == "/jellyfin/Items/" + item["Id"]:
                return self.reply(200, item)
        self.reply(404, {})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8769)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"http://127.0.0.1:{server.server_port}/jellyfin", flush=True)
    server.serve_forever()
