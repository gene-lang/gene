#!/usr/bin/env python3
"""Small stdlib web helper for GeneClaw tools.

The Gene runtime keeps tool registration and event logging in Gene. This helper
handles the parts that are tedious and brittle in shell: HTTP, JSON, and basic
HTML text extraction.
"""

from __future__ import annotations

import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser


USER_AGENT = "GeneClaw/0.1 (+https://geneclaw.local)"
DEFAULT_TIMEOUT = 15
DEFAULT_LIMIT = 5
MAX_INLINE_TEXT = 20000


def emit(value: dict) -> int:
    sys.stdout.write(json.dumps(value, ensure_ascii=False))
    sys.stdout.write("\n")
    return 0


def fail(message: str, **extra: object) -> int:
    payload = {"status": "failed", "error": message}
    payload.update(extra)
    return emit(payload)


def int_arg(name: str, default: int, minimum: int = 1, maximum: int = 120) -> int:
    try:
        value = int(os.environ.get(name, ""))
    except ValueError:
        value = default
    return max(minimum, min(maximum, value))


def request_url(url: str, timeout: int) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
            content_type = response.headers.get("content-type", "")
            charset = response.headers.get_content_charset() or "utf-8"
            text = raw.decode(charset, errors="replace")
            return {
                "status": "ok",
                "url": url,
                "final_url": response.geturl(),
                "status_code": getattr(response, "status", 200),
                "content_type": content_type,
                "bytes": len(raw),
                "content": text,
            }
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        text = raw.decode("utf-8", errors="replace")
        return {
            "status": "failed",
            "url": url,
            "final_url": exc.geturl(),
            "status_code": exc.code,
            "content_type": exc.headers.get("content-type", ""),
            "bytes": len(raw),
            "content": text,
            "error": f"HTTP {exc.code}",
        }
    except Exception as exc:  # noqa: BLE001 - tool boundary should return errors
        return {"status": "failed", "url": url, "error": str(exc)}


def github_read_url_candidates(url: str) -> list[str]:
    parsed = urllib.parse.urlparse(url)
    if parsed.netloc.lower() != "github.com":
        return []
    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) < 2:
        return []
    owner = parts[0]
    repo = parts[1].removesuffix(".git")
    if not owner or not repo:
        return []
    if len(parts) >= 5 and parts[2] == "blob":
        branch = parts[3]
        path = "/".join(parts[4:])
        return [f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}"]
    if len(parts) == 2:
        candidates: list[str] = []
        for branch in ("HEAD", "main", "master"):
            for name in ("README.md", "README"):
                candidates.append(f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{name}")
        return candidates
    return []


def load_read_payload() -> dict:
    url = os.environ.get("GENECLAW_WEB_URL", "").strip()
    fixture = os.environ.get("GENECLAW_WEB_FETCH_FIXTURE", "").strip()
    if fixture:
        return load_fetch_payload()
    timeout = int_arg("GENECLAW_WEB_TIMEOUT_MS", DEFAULT_TIMEOUT)
    for candidate in github_read_url_candidates(url):
        fetched = request_url(candidate, timeout)
        if fetched.get("status") == "ok" and str(fetched.get("content", "")).strip():
            fetched["url"] = url
            fetched["source_url"] = candidate
            return fetched
    return load_fetch_payload()


class ReadableHTML(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title_parts: list[str] = []
        self.text_parts: list[str] = []
        self.links: list[dict] = []
        self._skip_depth = 0
        self._in_title = False
        self._current_link: str | None = None
        self._current_link_text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        attrs_map = {name.lower(): value or "" for name, value in attrs}
        if tag in {"script", "style", "noscript", "svg"}:
            self._skip_depth += 1
        if tag == "title":
            self._in_title = True
        if tag == "a":
            href = attrs_map.get("href", "").strip()
            if href:
                self._current_link = href
                self._current_link_text = []
        if tag in {"p", "div", "section", "article", "header", "footer", "li", "br", "tr", "h1", "h2", "h3"}:
            self.text_parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in {"script", "style", "noscript", "svg"} and self._skip_depth > 0:
            self._skip_depth -= 1
        if tag == "title":
            self._in_title = False
        if tag == "a" and self._current_link:
            label = clean_text(" ".join(self._current_link_text))
            self.links.append({"url": self._current_link, "text": label})
            self._current_link = None
            self._current_link_text = []
        if tag in {"p", "div", "section", "article", "li", "tr", "h1", "h2", "h3"}:
            self.text_parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip_depth > 0:
            return
        value = data.strip()
        if not value:
            return
        if self._in_title:
            self.title_parts.append(value)
        self.text_parts.append(value)
        self.text_parts.append(" ")
        if self._current_link is not None:
            self._current_link_text.append(value)


class DuckDuckGoHTML(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.results: list[dict] = []
        self._in_title = False
        self._in_snippet = False
        self._current_url = ""
        self._current_title: list[str] = []
        self._current_snippet: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_map = {name.lower(): value or "" for name, value in attrs}
        classes = attrs_map.get("class", "")
        if tag == "a" and "result__a" in classes:
            self._flush()
            self._in_title = True
            self._current_url = normalize_ddg_url(attrs_map.get("href", ""))
            self._current_title = []
            self._current_snippet = []
        elif "result__snippet" in classes:
            self._in_snippet = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._in_title:
            self._in_title = False
        if self._in_snippet and tag in {"a", "div"}:
            self._in_snippet = False

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self._current_title.append(data)
        if self._in_snippet:
            self._current_snippet.append(data)

    def close(self) -> None:
        super().close()
        self._flush()

    def _flush(self) -> None:
        title = clean_text(" ".join(self._current_title))
        if not title or not self._current_url:
            return
        self.results.append(
            {
                "title": title,
                "url": self._current_url,
                "snippet": clean_text(" ".join(self._current_snippet)),
            }
        )
        self._current_url = ""
        self._current_title = []
        self._current_snippet = []


def clean_text(value: str) -> str:
    value = html.unescape(value or "")
    value = re.sub(r"[ \t\r\f\v]+", " ", value)
    value = re.sub(r"\n\s*\n\s*", "\n\n", value)
    return value.strip()


def trim_text(value: str, limit: int = MAX_INLINE_TEXT) -> str:
    if len(value) <= limit:
        return value
    return value[: max(0, limit - 14)] + "...[truncated]"


def normalize_ddg_url(url: str) -> str:
    parsed = urllib.parse.urlparse(html.unescape(url))
    if parsed.path == "/l/":
        query = urllib.parse.parse_qs(parsed.query)
        target = query.get("uddg", [""])[0]
        if target:
            return target
    return urllib.parse.urljoin("https://duckduckgo.com", url)


def read_html(content: str, base_url: str = "") -> dict:
    parser = ReadableHTML()
    parser.feed(content)
    parser.close()
    links: list[dict] = []
    seen: set[str] = set()
    for item in parser.links:
        url = urllib.parse.urljoin(base_url, item.get("url", ""))
        if not url or url in seen:
            continue
        seen.add(url)
        links.append({"url": url, "text": item.get("text", "")})
        if len(links) >= 50:
            break
    text = clean_text("".join(parser.text_parts))
    title = clean_text(" ".join(parser.title_parts))
    return {"title": title, "text": trim_text(text), "links": links}


def command_fetch() -> int:
    return emit(load_fetch_payload())


def load_fetch_payload() -> dict:
    url = os.environ.get("GENECLAW_WEB_URL", "").strip()
    if not url:
        return {"status": "failed", "error": "Missing url"}
    fixture = os.environ.get("GENECLAW_WEB_FETCH_FIXTURE", "").strip()
    if fixture:
        try:
            with open(fixture, "r", encoding="utf-8") as handle:
                content = handle.read()
            return {
                "status": "ok",
                "url": url,
                "final_url": url,
                "status_code": 200,
                "content_type": "text/html; charset=utf-8",
                "bytes": len(content.encode("utf-8")),
                "content": content,
                "fixture": fixture,
            }
        except Exception as exc:  # noqa: BLE001
            return {"status": "failed", "error": f"fixture fetch failed: {exc}", "url": url}
    return request_url(url, int_arg("GENECLAW_WEB_TIMEOUT_MS", DEFAULT_TIMEOUT))


def command_read() -> int:
    fetched = json.loads(os.environ.get("GENECLAW_WEB_FETCHED", "{}"))
    if not fetched:
        fetched = load_read_payload()
    if fetched.get("status") != "ok":
        return emit(fetched)
    readable = read_html(str(fetched.get("content", "")), str(fetched.get("final_url") or fetched.get("url") or ""))
    return emit(
        {
            "status": "ok",
            "url": fetched.get("url", ""),
            "final_url": fetched.get("final_url", fetched.get("url", "")),
            "source_url": fetched.get("source_url", ""),
            "status_code": fetched.get("status_code", 0),
            "content_type": fetched.get("content_type", ""),
            "title": readable["title"],
            "text": readable["text"],
            "links": readable["links"],
        }
    )


def command_search() -> int:
    query = os.environ.get("GENECLAW_WEB_QUERY", "").strip()
    if not query:
        return fail("Missing query")
    limit = int_arg("GENECLAW_WEB_LIMIT", DEFAULT_LIMIT, 1, 20)
    provider = os.environ.get("GENECLAW_SEARCH_PROVIDER", "mojeek").strip().lower()
    fixture = os.environ.get("GENECLAW_WEB_SEARCH_FIXTURE", "").strip()
    if fixture:
        try:
            with open(fixture, "r", encoding="utf-8") as handle:
                loaded = json.load(handle)
            results = loaded.get("results", loaded if isinstance(loaded, list) else [])
            results = results[:limit]
            return emit(
                {
                    "status": "ok",
                    "provider": "fixture",
                    "query": query,
                    "results": results,
                    "output": summarize_results(results),
                    "fixture": fixture,
                }
            )
        except Exception as exc:  # noqa: BLE001
            return fail(f"fixture search failed: {exc}", query=query, provider="fixture")
    if provider not in {"mojeek", "duckduckgo", "ddg"}:
        return fail(f"Unsupported search provider: {provider}", query=query, provider=provider)
    if provider == "mojeek":
        search_url = "https://www.mojeek.com/search?" + urllib.parse.urlencode({"q": query})
        parser = MojeekHTML()
        provider_name = "mojeek"
    else:
        search_url = "https://duckduckgo.com/html/?" + urllib.parse.urlencode({"q": query})
        parser = DuckDuckGoHTML()
        provider_name = "duckduckgo"
    fetched = request_url(search_url, int_arg("GENECLAW_WEB_TIMEOUT_MS", DEFAULT_TIMEOUT))
    if fetched.get("status") != "ok":
        fetched["provider"] = provider_name
        fetched["query"] = query
        return emit(fetched)
    parser.feed(str(fetched.get("content", "")))
    parser.close()
    results = parser.results[:limit]
    return emit(
        {
            "status": "ok",
            "provider": provider_name,
            "query": query,
            "results": results,
            "output": summarize_results(results),
            "source_url": search_url,
        }
    )


def summarize_results(results: list[dict]) -> str:
    lines: list[str] = []
    for index, item in enumerate(results, start=1):
        title = item.get("title", "")
        url = item.get("url", "")
        snippet = item.get("snippet", "")
        line = f"{index}. {title}\n{url}"
        if snippet:
            line += f"\n{snippet}"
        lines.append(line)
    return "\n\n".join(lines)


class MojeekHTML(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.results: list[dict] = []
        self._in_title = False
        self._in_snippet = False
        self._current_url = ""
        self._current_title: list[str] = []
        self._current_snippet: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_map = {name.lower(): value or "" for name, value in attrs}
        classes = attrs_map.get("class", "")
        if tag == "a" and "title" in classes:
            self._flush()
            self._in_title = True
            self._current_url = attrs_map.get("href", "").strip()
            self._current_title = []
            self._current_snippet = []
        elif tag == "p" and "s" in classes:
            self._in_snippet = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._in_title:
            self._in_title = False
        if tag == "p" and self._in_snippet:
            self._in_snippet = False

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self._current_title.append(data)
        if self._in_snippet:
            self._current_snippet.append(data)

    def close(self) -> None:
        super().close()
        self._flush()

    def _flush(self) -> None:
        title = clean_text(" ".join(self._current_title))
        if not title or not self._current_url:
            return
        self.results.append(
            {
                "title": title,
                "url": self._current_url,
                "snippet": clean_text(" ".join(self._current_snippet)),
            }
        )
        self._current_url = ""
        self._current_title = []
        self._current_snippet = []


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        return fail("Missing command")
    command = argv[1]
    if command == "fetch":
        return command_fetch()
    if command == "read":
        return command_read()
    if command == "search":
        return command_search()
    return fail(f"Unknown command: {command}")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
