#!/usr/bin/env python3
"""
cosmos_cache.py — local cache builder for cosmos.so /public-work content.

Pipeline (all idempotent / resumable):

  1. discover : iterate queries.txt, call public.work text-search, append unique
                candidate items to queue.tsv. Optionally expand via image-search
                (similar items) for the first N results of each query.
  2. download : drain queue.tsv, fetch image bytes with rate limit, dedupe by
                sha256, validate dimensions / size, write img/<sha>.<ext> and
                append a row to manifest.tsv.

State (state.json) records:
  - last_query_index           : how far through queries.txt the discoverer got
  - queue_cursor               : how many queue.tsv rows the downloader has consumed
  - bytes_downloaded, items_kept, items_skipped, started_at

Constraints:
  - <=2 requests/second to api.public.work and cdn.cosmos.so each (configurable).
  - skip images outside [256x256, 10MB].
  - skip non-image content.

Designed to share network bandwidth politely; minimal CPU work (image dimensions
are read from the bytes header without re-encoding).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import struct
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parent
QUERIES = ROOT / "queries.txt"
QUEUE = ROOT / "queue.tsv"
MANIFEST = ROOT / "manifest.tsv"
SHA_INDEX = ROOT / "sha.index"          # one sha256 per line, for fast dedupe
ID_INDEX = ROOT / "id.index"            # one cosmos id per line, for fast dedupe
STATE = ROOT / "state.json"
IMG_DIR = ROOT / "img"
LOG = ROOT / "run.log"

API_KEY = "0ee9493d520a41a7ad91b9208fd420dd"  # public client key, embedded in cosmos.so JS bundle
TEXT_SEARCH = "https://api.public.work/public-domain/text-search"
IMAGE_SEARCH = "https://api.public.work/public-domain/image-search"

UA = "arcan-textures-cache/1.0 (research; ariel@geosure.ai)"

MIN_DIM = 256
MAX_BYTES = 10 * 1024 * 1024  # 10 MiB
MIN_BYTES = 4 * 1024          # absurdly tiny -> skip

# polite throttling
API_INTERVAL = 0.55           # ~1.8 req/s for the search API
CDN_INTERVAL = 0.55           # ~1.8 req/s for the image CDN
TIMEOUT = 30
RETRIES = 2

MANIFEST_HEADER = "sha256\tsrc_url\tpage_url\tauthor\tw\th\tbytes\tlicense\tts\ttitle\trepository\tcosmos_id\n"


# ----------------------------- utilities -----------------------------


def log(msg: str) -> None:
    line = f"[{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}] {msg}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


def load_state() -> dict:
    if STATE.exists():
        try:
            return json.loads(STATE.read_text())
        except json.JSONDecodeError:
            pass
    return {
        "last_query_index": 0,
        "queue_cursor": 0,
        "bytes_downloaded": 0,
        "items_kept": 0,
        "items_skipped": 0,
        "started_at": time.time(),
    }


def save_state(s: dict) -> None:
    tmp = STATE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(s, indent=2))
    tmp.replace(STATE)


def load_index(p: Path) -> set[str]:
    if not p.exists():
        return set()
    with p.open() as f:
        return {l.strip() for l in f if l.strip()}


def append_index(p: Path, value: str) -> None:
    with p.open("a") as f:
        f.write(value + "\n")


# ----------------------------- networking -----------------------------


_last_call = {"api": 0.0, "cdn": 0.0}


def _throttle(kind: str, interval: float) -> None:
    now = time.monotonic()
    delta = now - _last_call[kind]
    if delta < interval:
        time.sleep(interval - delta)
    _last_call[kind] = time.monotonic()


def http_post_json(url: str, body: dict) -> dict:
    _throttle("api", API_INTERVAL)
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-API-Key": API_KEY,
            "User-Agent": UA,
        },
        method="POST",
    )
    last_err: Exception | None = None
    for attempt in range(RETRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                if resp.status == 429 or resp.status >= 500:
                    raise urllib.error.HTTPError(url, resp.status, "throttled", resp.headers, None)
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code == 429:
                wait = 5 * (attempt + 1) + random.random()
                log(f"429 from API; sleeping {wait:.1f}s")
                time.sleep(wait)
                continue
            if 500 <= e.code < 600:
                time.sleep(2 * (attempt + 1))
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = e
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"POST {url} failed: {last_err}")


def http_get_bytes(url: str, cap: int = MAX_BYTES + 1) -> tuple[int, bytes, str]:
    _throttle("cdn", CDN_INTERVAL)
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "image/*,*/*;q=0.5",
        },
    )
    last_err: Exception | None = None
    for attempt in range(RETRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                ct = (resp.headers.get("Content-Type") or "").split(";")[0].strip().lower()
                buf = bytearray()
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    buf.extend(chunk)
                    if len(buf) > cap:
                        return resp.status, bytes(buf[:cap]), ct  # caller will reject as too big
                return resp.status, bytes(buf), ct
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code == 429:
                wait = 5 * (attempt + 1) + random.random()
                log(f"429 from CDN; sleeping {wait:.1f}s")
                time.sleep(wait)
                continue
            if e.code in (404, 403, 410):
                return e.code, b"", ""
            if 500 <= e.code < 600:
                time.sleep(2 * (attempt + 1))
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = e
            time.sleep(2 * (attempt + 1))
    log(f"GET {url} failed: {last_err}")
    return 0, b"", ""


# ----------------------------- image inspection -----------------------------


def sniff_image(buf: bytes) -> tuple[str, int, int] | None:
    """Return (ext, w, h) for jpg/png/gif/webp/bmp; None if unknown."""
    if len(buf) < 24:
        return None
    if buf.startswith(b"\xff\xd8"):  # JPEG
        i = 2
        while i < len(buf) - 9:
            if buf[i] != 0xFF:
                i += 1
                continue
            marker = buf[i + 1]
            if marker == 0xFF:
                i += 1
                continue
            if marker in (0xD8, 0xD9):
                i += 2
                continue
            seg_len = struct.unpack(">H", buf[i + 2 : i + 4])[0]
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                if i + 9 > len(buf):
                    return None
                h, w = struct.unpack(">HH", buf[i + 5 : i + 9])
                return ("jpg", w, h)
            i += 2 + seg_len
        return None
    if buf.startswith(b"\x89PNG\r\n\x1a\n"):
        w, h = struct.unpack(">II", buf[16:24])
        return ("png", w, h)
    if buf[:6] in (b"GIF87a", b"GIF89a"):
        w, h = struct.unpack("<HH", buf[6:10])
        return ("gif", w, h)
    if buf[:4] == b"RIFF" and buf[8:12] == b"WEBP":
        chunk = buf[12:16]
        if chunk == b"VP8 ":
            w = struct.unpack("<H", buf[26:28])[0] & 0x3FFF
            h = struct.unpack("<H", buf[28:30])[0] & 0x3FFF
            return ("webp", w, h)
        if chunk == b"VP8L":
            b1, b2, b3, b4 = buf[21], buf[22], buf[23], buf[24]
            w = 1 + (((b2 & 0x3F) << 8) | b1)
            h = 1 + (((b4 & 0xF) << 10) | (b3 << 2) | ((b2 & 0xC0) >> 6))
            return ("webp", w, h)
        if chunk == b"VP8X":
            w = 1 + (buf[24] | (buf[25] << 8) | (buf[26] << 16))
            h = 1 + (buf[27] | (buf[28] << 8) | (buf[29] << 16))
            return ("webp", w, h)
        return None
    if buf.startswith(b"BM"):
        w, h = struct.unpack("<ii", buf[18:26])
        return ("bmp", w, abs(h))
    return None


def ext_for_content_type(ct: str) -> str | None:
    return {
        "image/jpeg": "jpg",
        "image/jpg": "jpg",
        "image/png": "png",
        "image/gif": "gif",
        "image/webp": "webp",
        "image/bmp": "bmp",
    }.get(ct)


# ----------------------------- discover -----------------------------


def normalize_payload(it: dict) -> dict | None:
    """Flatten cosmos's quirky list-wrapped fields."""
    pid = it.get("id")
    p = it.get("payload") or {}

    def first(v):
        if isinstance(v, list):
            return v[0] if v else None
        return v

    url = first(p.get("image_url"))
    if not url:
        return None
    width = first(p.get("image_width"))
    height = first(p.get("image_height"))
    return {
        "id": pid,
        "encoded_id": it.get("encoded_id"),
        "url": url,
        "thumb": first(p.get("image_thumbnail")),
        "w": int(width) if width else None,
        "h": int(height) if height else None,
        "title": p.get("title") or "",
        "author": p.get("artist_name") or "",
        "credit": p.get("credit_line") or "",
        "license": p.get("description") or "",  # often "PD Worldwide" etc
        "source_url": p.get("source_url") or "",
        "repository": p.get("repository") or "",
        "date": p.get("date_approximate") or "",
    }


def queue_append(rows: Iterable[dict], seen_ids: set[str]) -> int:
    added = 0
    with QUEUE.open("a") as f:
        for r in rows:
            if r is None:
                continue
            sid = str(r["id"])
            if sid in seen_ids:
                continue
            seen_ids.add(sid)
            append_index(ID_INDEX, sid)
            cols = [
                sid,
                r["url"],
                str(r["w"] or ""),
                str(r["h"] or ""),
                (r["title"] or "").replace("\t", " ").replace("\n", " "),
                (r["author"] or "").replace("\t", " ").replace("\n", " "),
                (r["credit"] or "").replace("\t", " ").replace("\n", " "),
                (r["license"] or "").replace("\t", " ").replace("\n", " "),
                (r["source_url"] or "").replace("\t", " "),
                (r["repository"] or "").replace("\t", " "),
                (r["date"] or "").replace("\t", " "),
            ]
            f.write("\t".join(cols) + "\n")
            added += 1
    return added


def discover_loop(target_items: int, expand_top: int = 0) -> None:
    """Walk queries.txt, collect candidates until we have at least target_items unique items."""
    if not QUERIES.exists():
        log("queries.txt missing — aborting discover")
        return

    queries = [q.strip() for q in QUERIES.read_text().splitlines() if q.strip()]
    state = load_state()
    seen_ids = load_index(ID_INDEX)

    log(f"discover start: have {len(seen_ids)} candidates, target {target_items}, "
        f"resuming at query #{state['last_query_index']}/{len(queries)}")

    i = state["last_query_index"]
    while i < len(queries) and len(seen_ids) < target_items:
        q = queries[i]
        try:
            r = http_post_json(TEXT_SEARCH, {"page": 0, "pageLimit": 200, "query": q})
            results = r.get("results") or []
            normalized = [normalize_payload(it) for it in results]
            added = queue_append(normalized, seen_ids)
            log(f"q[{i+1}/{len(queries)}] '{q[:40]}' -> {len(results)} results, +{added} new (total {len(seen_ids)})")

            # expand via image-search on first few results, optional and pricey
            if expand_top > 0 and added > 0:
                for it in normalized[: expand_top]:
                    if it is None:
                        continue
                    try:
                        r2 = http_post_json(
                            IMAGE_SEARCH,
                            {"page": 0, "pageLimit": 200, "elementId": str(it["id"])},
                        )
                        n2 = [normalize_payload(x) for x in (r2.get("results") or [])]
                        added2 = queue_append(n2, seen_ids)
                        log(f"   expand {it['id']}: +{added2}")
                    except Exception as e:
                        log(f"   expand failed: {e}")
        except Exception as e:
            log(f"q[{i+1}/{len(queries)}] '{q[:40]}' FAILED: {e}")

        i += 1
        state["last_query_index"] = i
        save_state(state)

    log(f"discover finished: {len(seen_ids)} candidates queued at query #{i}")


# ----------------------------- download -----------------------------


def download_loop(target_kept: int) -> None:
    if not QUEUE.exists():
        log("queue.tsv missing — run discover first")
        return

    state = load_state()
    sha_index = load_index(SHA_INDEX)
    items_kept = state.get("items_kept", 0)

    if not MANIFEST.exists():
        MANIFEST.write_text(MANIFEST_HEADER)

    cursor = state.get("queue_cursor", 0)
    log(f"download start: kept {items_kept}, cursor {cursor}, target {target_kept}")

    with QUEUE.open() as fq:
        # skip already-consumed lines
        for _ in range(cursor):
            if not fq.readline():
                break
        for line in fq:
            if items_kept >= target_kept:
                break
            cursor += 1
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 11:
                continue
            (
                cosmos_id,
                url,
                w_s,
                h_s,
                title,
                author,
                credit,
                license_,
                source_url,
                repository,
                date_s,
            ) = cols

            try:
                # Hint-skip if API metadata is below threshold; cheap savings
                if w_s and h_s:
                    try:
                        if int(w_s) < MIN_DIM or int(h_s) < MIN_DIM:
                            state["items_skipped"] = state.get("items_skipped", 0) + 1
                            continue
                    except ValueError:
                        pass

                status, buf, ct = http_get_bytes(url)
                if status != 200 or not buf:
                    state["items_skipped"] = state.get("items_skipped", 0) + 1
                    continue
                if not ct.startswith("image/"):
                    state["items_skipped"] = state.get("items_skipped", 0) + 1
                    continue
                if len(buf) > MAX_BYTES or len(buf) < MIN_BYTES:
                    state["items_skipped"] = state.get("items_skipped", 0) + 1
                    continue

                sniff = sniff_image(buf)
                if sniff is None:
                    state["items_skipped"] = state.get("items_skipped", 0) + 1
                    continue
                ext, w, h = sniff
                if w < MIN_DIM or h < MIN_DIM:
                    state["items_skipped"] = state.get("items_skipped", 0) + 1
                    continue

                sha = hashlib.sha256(buf).hexdigest()
                if sha in sha_index:
                    state["items_skipped"] = state.get("items_skipped", 0) + 1
                    continue
                sha_index.add(sha)

                # bucketed dir to avoid 100k flat
                bucket = IMG_DIR / sha[:2]
                bucket.mkdir(parents=True, exist_ok=True)
                out = bucket / f"{sha}.{ext}"
                tmp = out.with_suffix(out.suffix + ".tmp")
                tmp.write_bytes(buf)
                tmp.replace(out)
                append_index(SHA_INDEX, sha)

                ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                page_url = f"https://www.cosmos.so/public-work?elementId={cosmos_id}"
                license_str = license_ or "Public Domain (per cosmos.so/public-work)"
                row = [
                    sha,
                    url,
                    page_url,
                    author,
                    str(w),
                    str(h),
                    str(len(buf)),
                    license_str,
                    ts,
                    title,
                    repository,
                    cosmos_id,
                ]
                with MANIFEST.open("a") as mf:
                    mf.write("\t".join(c.replace("\t", " ").replace("\n", " ") for c in row) + "\n")

                items_kept += 1
                state["items_kept"] = items_kept
                state["bytes_downloaded"] = state.get("bytes_downloaded", 0) + len(buf)

                if items_kept % 50 == 0:
                    state["queue_cursor"] = cursor
                    save_state(state)
                    log(f"kept {items_kept} (cursor {cursor}, {state['bytes_downloaded']/1e6:.1f} MB)")
            except Exception as e:
                log(f"download error for id={cosmos_id}: {e}")
                state["items_skipped"] = state.get("items_skipped", 0) + 1
            finally:
                state["queue_cursor"] = cursor

    save_state(state)
    log(f"download finished: kept {items_kept}, cursor {cursor}, "
        f"{state['bytes_downloaded']/1e6:.1f} MB total")


# ----------------------------- main -----------------------------


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("phase", choices=["discover", "download", "both"], default="both", nargs="?")
    ap.add_argument("--target", type=int, default=12000, help="goal for kept images (download phase)")
    ap.add_argument("--queue-target", type=int, default=20000, help="goal for queued candidates (discover phase)")
    ap.add_argument("--expand-top", type=int, default=0, help="image-search expansion per query (0=off)")
    args = ap.parse_args()

    IMG_DIR.mkdir(parents=True, exist_ok=True)
    log(f"cosmos_cache start phase={args.phase} target={args.target}")

    if args.phase in ("discover", "both"):
        discover_loop(args.queue_target, args.expand_top)

    if args.phase in ("download", "both"):
        download_loop(args.target)

    return 0


if __name__ == "__main__":
    sys.exit(main())
