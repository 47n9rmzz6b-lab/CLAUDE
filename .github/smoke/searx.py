#!/usr/bin/env python3
"""Faux serveur SearXNG (port 8765) : résultats fixes et pages de test, requêtes enregistrées."""
import http.server
import json
import time
import urllib.parse

LOG = "/tmp/searx.log"
PAGES = {
    "meteo-lyon": ("Météo à Lyon – prévisions du jour",
                   "<p>Aujourd'hui à Lyon : 23 °C, ciel dégagé, vent faible du sud.</p>"
                   "<p>Code de vérification de la page : TOURNESOL-42.</p>"),
    "lyon": ("Lyon – encyclopédie", "<p>Lyon est une ville française située au confluent du Rhône et de la Saône.</p>"),
    "hibiscus": ("Projet Hibiscus – page officielle", "<p>Le projet Hibiscus a été lancé en 2024 à Grenoble.</p>"),
}
RESULTS = [
    {"title": PAGES["meteo-lyon"][0], "url": "http://localhost:8765/page/meteo-lyon",
     "content": "Aujourd'hui à Lyon : 23 °C, ciel dégagé, vent faible. Code de vérification : TOURNESOL-42."},
    {"title": PAGES["lyon"][0], "url": "http://localhost:8765/page/lyon",
     "content": "Lyon est une ville française située au confluent du Rhône et de la Saône."},
    {"title": PAGES["hibiscus"][0], "url": "http://localhost:8765/page/hibiscus",
     "content": "Le projet Hibiscus a été lancé en 2024 à Grenoble."},
]


def log(entry):
    entry["time"] = round(time.time(), 2)
    with open(LOG, "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/search":
            query = urllib.parse.parse_qs(url.query).get("q", [""])[0]
            log({"search": query})
            body = json.dumps({"query": query, "results": RESULTS}, ensure_ascii=False).encode()
            kind = "application/json"
        elif url.path.startswith("/page/"):
            slug = url.path.rsplit("/", 1)[-1]
            log({"fetch": slug})
            title, html = PAGES.get(slug, PAGES["lyon"])
            body = (f"<html><head><title>{title}</title><style>p{{}}</style></head><body><nav>menu</nav>"
                    f"<h1>{title}</h1>{html}<footer>pied de page</footer></body></html>").encode()
            kind = "text/html; charset=utf-8"
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
