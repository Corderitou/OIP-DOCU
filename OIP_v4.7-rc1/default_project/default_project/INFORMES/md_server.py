"""Servidor web local para navegar una carpeta y leer archivos .md renderizados.

Uso:
    python md_server.py                 # sirve la carpeta actual (puerto 8000, abre navegador)
    python md_server.py --port 8080     # otro puerto
    python md_server.py --dir RUTA      # sirve otra carpeta
    python md_server.py --no-open       # no abrir el navegador
"""

import argparse
import html
import mimetypes
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import markdown

    MD_EXTENSIONS = ["tables", "fenced_code", "sane_lists"]
    HAS_MARKDOWN = True
except ImportError:
    HAS_MARKDOWN = False

ROOT = os.path.abspath(os.getcwd())

CSS = """
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body {
  margin: 0; padding: 2rem 1rem;
  font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
  background: #f6f7f9; color: #1c2430; line-height: 1.65;
}
main { max-width: 900px; margin: 0 auto; background: #fff;
  border: 1px solid #dfe3e8; border-radius: 10px; padding: 2rem 2.5rem;
  box-shadow: 0 2px 10px rgba(20,30,50,.06); }
nav.crumbs { font-size: .92rem; margin-bottom: 1rem; color:#5a6675; }
nav.crumbs a { color: #2563eb; text-decoration: none; }
nav.crumbs a:hover { text-decoration: underline; }
h1,h2,h3,h4 { line-height: 1.25; color: #10203a; }
h1 { border-bottom: 2px solid #e3e8ef; padding-bottom: .35rem; }
h2 { border-bottom: 1px solid #eceff4; padding-bottom: .25rem; margin-top: 2rem; }
code, pre { font-family: Consolas, "Cascadia Code", monospace; }
code { background: #eef1f5; border-radius: 4px; padding: .12em .35em; font-size:.92em; }
pre { background: #f2f4f8; border: 1px solid #e2e6ec; border-radius: 8px;
  padding: .9rem 1rem; overflow-x: auto; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; width: 100%; margin: 1rem 0; font-size: .95rem; }
th, td { border: 1px solid #d7dde5; padding: .45rem .65rem; text-align: left; vertical-align: top; }
th { background: #eef2f7; }
blockquote { border-left: 4px solid #c3ccd9; margin: 1rem 0; padding: .2rem 1rem; color:#45516b; }
a { color: #2563eb; }
ul.listing { list-style: none; padding: 0; margin: 0; }
ul.listing li { padding: .42rem .2rem; border-bottom: 1px solid #edf0f4; display:flex; gap:.6rem; align-items:baseline;}
ul.listing li:last-child { border-bottom: none; }
ul.listing a { text-decoration: none; font-weight: 500; }
ul.listing a:hover { text-decoration: underline; }
ul.listing .size { margin-left: auto; color: #8794a6; font-size: .85rem; white-space: nowrap; }
.icon { width: 1.15em; display:inline-block; text-align:center; }
.mdfile > a { color:#0f4cc0; }
.rawlink { float: right; font-size: .88rem; }
footer.note { max-width: 900px; margin: 1rem auto 0; font-size:.82rem; color:#93a0b1; text-align:center;}
@media (prefers-color-scheme: dark) {
  body { background:#12161c; color:#dbe2ea; }
  main { background:#181e26; border-color:#262e39; box-shadow:none; }
  h1,h2,h3,h4 { color:#eef3f9; } h1{border-color:#28313d;} h2{border-color:#222a34;}
  code { background:#232b36; } pre { background:#161c24; border-color:#273041; }
  th,td { border-color:#303a48; } th{background:#202833;}
  blockquote{border-color:#3a4556;color:#aab6c6;}
  ul.listing li{border-color:#212933;} ul.listing .size{color:#6d7a8c;}
}
"""


def safe_join(base: str, rel: str) -> str:
    rel = rel.strip("/")
    if rel in ("", "."):
        return base
    path = os.path.abspath(os.path.join(base, *rel.split("/")))
    if os.path.commonpath([base, path]) != base:
        raise PermissionError(rel)
    return path


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} GB"


def crumbs(rel_dir: str) -> str:
    parts = [p for p in rel_dir.split("/") if p]
    links = ['<a href="/">raíz</a>']
    acc = ""
    for p in parts:
        acc += "/" + p
        links.append(f'<a href="{urllib.parse.quote(acc)}/">{html.escape(p)}</a>')
    return " / ".join(links)


class Handler(BaseHTTPRequestHandler):
    server_version = "MDServer/1.0"

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        route = urllib.parse.unquote(parsed.path)
        raw_mode = urllib.parse.parse_qs(parsed.query).get("raw", ["0"])[0] == "1"
        try:
            target = safe_join(ROOT, route)
        except PermissionError:
            self.send_error(403, "Ruta fuera de la carpeta servida")
            return

        if os.path.isdir(target):
            if not route.endswith("/"):
                self.send_response(301)
                self.send_header("Location", parsed.path + "/")
                self.end_headers()
                return
            self.send_listing(target, route.strip("/"))
        elif os.path.isfile(target):
            ext = os.path.splitext(target)[1].lower()
            if ext == ".md" and not raw_mode:
                self.send_markdown(target)
            else:
                self.send_file(target)
        else:
            self.send_error(404, "No encontrado")
            return

    # ---------- respuestas ----------

    def _send_html(self, body: str) -> None:
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_file(self, path: str) -> None:
        ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
        try:
            with open(path, "rb") as fh:
                data = fh.read()
        except OSError:
            self.send_error(404, "No se pudo leer el archivo")
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_markdown(self, path: str) -> None:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        if HAS_MARKDOWN:
            rendered = markdown.markdown(text, extensions=MD_EXTENSIONS)
        else:
            rendered = f"<pre>{html.escape(text)}</pre>"
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        title = os.path.basename(path)
        raw_url = "/" + urllib.parse.quote(rel) + "?raw=1"
        body = f"""<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title><style>{CSS}</style></head>
<body><main>
<nav class="crumbs">{crumbs(os.path.dirname(rel))}
<span class="rawlink"><a href="{raw_url}">ver crudo</a></span></nav>
<article>{rendered}</article>
</main>
<footer class="note">servido por md_server desde <b>{html.escape(ROOT)}</b></footer>
</body></html>"""
        self._send_html(body)

    def send_listing(self, path: str, rel_dir: str) -> None:
        try:
            entries = sorted(
                os.scandir(path), key=lambda e: (not e.is_dir(), e.name.lower())
            )
        except OSError:
            self.send_error(500, "No se pudo listar la carpeta")
            return
        items = []
        if rel_dir:
            parent = os.path.dirname(rel_dir)
            items.append(
                f'<li class="dirfile"><span class="icon">&#8617;</span>'
                f'<a href="/{urllib.parse.quote(parent)}/">..</a></li>'
            )
        for entry in entries:
            url = "/" + urllib.parse.quote((rel_dir + "/" + entry.name).strip("/"))
            esc = html.escape(entry.name)
            try:
                if entry.is_dir():
                    items.append(
                        f'<li class="dirfile"><span class="icon">&#128193;</span>'
                        f'<a href="{url}/">{esc}</a><span class="size">carpeta</span></li>'
                    )
                else:
                    size = human_size(entry.stat().st_size)
                    icon = "&#128196;"
                    cls = ""
                    if entry.name.lower().endswith(".md"):
                        icon = "&#128209;"
                        cls = ' class="mdfile"'
                    items.append(
                        f'<li{cls}><span class="icon">{icon}</span>'
                        f'<a href="{url}">{esc}</a><span class="size">{size}</span></li>'
                    )
            except OSError:
                continue
        body = f"""<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Índice: /{html.escape(rel_dir)}</title><style>{CSS}</style></head>
<body><main>
<nav class="crumbs">{crumbs(rel_dir)}</nav>
<h1>&#128209; Archivos Markdown y carpetas</h1>
<ul class="listing">{''.join(items)}</ul>
</main>
<footer class="note">servido por md_server desde <b>{html.escape(ROOT)}</b>
&middot; {"markdown activo" if HAS_MARKDOWN else "FALTA paquete markdown: pip install markdown"}</footer>
</body></html>"""
        self._send_html(body)

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))


def main() -> int:
    global ROOT
    parser = argparse.ArgumentParser(description="Navegador web de archivos Markdown")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--dir", default=".", help="carpeta a servir (por defecto, la actual)")
    parser.add_argument("--no-open", action="store_true", help="no abrir el navegador")
    args = parser.parse_args()

    ROOT = os.path.abspath(args.dir)
    if not os.path.isdir(ROOT):
        print(f"Carpeta inexistente: {ROOT}", file=sys.stderr)
        return 1

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"Siriendo {ROOT}")
    print(f"Abre {url} en tu navegador (Ctrl+C para detener)")
    if not args.no_open:
        import threading
        import webbrowser

        threading.Timer(0.6, webbrowser.open, args=(url,)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDetenido.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
