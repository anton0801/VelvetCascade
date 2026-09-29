#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Velvet Cascade - ElevenLabs audio production pipeline.

Python 3 standard library only, plus the ffmpeg / ffprobe command line tools.

Modes
-----
  dry-run        [--ids ...]   list IDs, runtime files, requested durations, request hashes and
                               local state. Never touches the network, never needs the API key.
  account                      read the account subscription tier (free call) so the plan can be
                               recorded for the licence note. Needs the key.
  generate       --ids S01-S05 generate missing IDs (1 variant per ID). Needs ELEVENLABS_API_KEY
                               from the environment or the project .env file.
  build-runtime  [--ids ...]   edit selected ElevenLabs masters into runtime files and rewrite
                               their manifest entries.
  qa             [...]         run scripts/audio_qa.py (all 44 runtime files + key leak scan).
  approve / reject             record the human listening-QA verdict for the selected variant.
  resolve-uncertain            clear an "uncertain" marker after checking provider history.

Secret handling: the key is read at runtime only (env var or .env), only ever placed into the
request header, never printed, never written to disk, never put into argv. All console output
passes through redact(). TLS uses ssl.create_default_context() with full certificate and host
name verification; if this Python has no CA store, a system CA bundle file is loaded into the
same verifying context (verification is never disabled).
"""
from __future__ import annotations

import argparse
import array
import datetime as dt
import email.utils
import hashlib
import http.client
import json
import math
import os
import shutil
import socket
import ssl
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parent.parent
REQUESTS_PATH = ROOT / "scripts" / "audio_requests.json"
RAW_ROOT = ROOT / "Production" / "AudioRaw"
RUNTIME_DIR = ROOT / "VelvetCascade" / "Resources" / "Audio"
MANIFEST_PATH = ROOT / "VelvetCascade" / "Resources" / "Manifests" / "audio_manifest.json"
ENV_PATH = ROOT / ".env"
KEY_VAR = "ELEVENLABS_API_KEY"

API_HOST = "api.elevenlabs.io"
SR = 48000
MAX_VARIANTS = 3            # 1 initial + max 2 extra (only for QA-rejected IDs, explicit flag)
MAX_429_ATTEMPTS = 3
MAX_RETRY_AFTER_S = 300
CONNECT_TIMEOUT_S = 20
READ_TIMEOUT_S = {"sound-generation": 180, "music": 900}

SUBSTITUTE_PROVIDER = "procedural-substitute (NOT ElevenLabs)"
ELEVEN_PROVIDER = "ElevenLabs"

# Runtime level policy (attenuate only - effects are never pushed up to full scale).
SFX_PEAK_CEILING_DB = {"low": -9.0, "medium": -6.0, "high": -4.5, "highest": -3.0}
MUSIC_PEAK_CEILING_DB = -6.5
MUSIC_RMS_CEILING_DB = -19.0
AMBIENCE_PEAK_CEILING_DB = -12.0
AMBIENCE_RMS_CEILING_DB = -36.0

# Provider response headers worth keeping (never request headers - they carry the key).
KEEP_HEADERS = {
    "content-type", "content-length", "date", "request-id", "x-request-id", "history-item-id",
    "song-id", "character-cost", "x-character-count", "current-concurrent-requests",
    "maximum-concurrent-requests", "retry-after", "x-region", "x-trace-id",
}

FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
FFPROBE = shutil.which("ffprobe") or "/opt/homebrew/bin/ffprobe"

_print_lock = threading.Lock()
_SECRET: str | None = None


# ----------------------------------------------------------------------------- utilities

def redact(text: object) -> str:
    s = str(text)
    if _SECRET and _SECRET in s:
        s = s.replace(_SECRET, "***")
    return s


def out(msg: str = "") -> None:
    with _print_lock:
        print(redact(msg), flush=True)


def dev_err(msg: str) -> None:
    """Provider/API errors go to the developer console (stderr) only."""
    with _print_lock:
        print(redact(msg), file=sys.stderr, flush=True)


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def atomic_write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def atomic_write_json(path: Path, obj: object) -> None:
    text = json.dumps(obj, indent=2, ensure_ascii=False) + "\n"
    if _SECRET and _SECRET in text:          # defence in depth - must never happen
        raise RuntimeError("refusing to write a file that contains the API key")
    atomic_write_bytes(path, text.encode("utf-8"))


def db(x: float) -> float:
    return 20.0 * math.log10(x) if x > 0 else -999.0


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def load_requests() -> dict:
    with open(REQUESTS_PATH, encoding="utf-8") as f:
        doc = json.load(f)
    entries = doc["entries"]
    if len(entries) != 44 or len({e["id"] for e in entries}) != 44:
        raise SystemExit("audio_requests.json must contain exactly 44 unique IDs")
    return doc


def parse_ids(spec: str | None, entries: list[dict]) -> list[dict]:
    order = [e["id"] for e in entries]
    by_id = {e["id"]: e for e in entries}
    if not spec:
        return list(entries)
    spec = spec.strip()
    if spec.lower() in ("all", "*"):
        return list(entries)
    groups = {"sfx": "sfx", "ambience": "ambience", "music": "music"}
    chosen: list[str] = []
    for part in [p.strip() for p in spec.split(",") if p.strip()]:
        if part.lower() in groups:
            chosen += [e["id"] for e in entries if e["kind"] == groups[part.lower()]]
            continue
        if "-" in part:
            a, b = [s.strip().upper() for s in part.split("-", 1)]
            if a[0] != b[0] or a not in by_id or b not in by_id:
                raise SystemExit(f"bad ID range: {part}")
            ia, ib = order.index(a), order.index(b)
            if ib < ia:
                raise SystemExit(f"bad ID range: {part}")
            chosen += order[ia:ib + 1]
        else:
            p = part.upper()
            if p not in by_id:
                raise SystemExit(f"unknown ID: {part}")
            chosen.append(p)
    seen: set[str] = set()
    return [by_id[i] for i in order if i in chosen and not (i in seen or seen.add(i))]


# ----------------------------------------------------------------------------- secret

def load_api_key() -> str | None:
    """Env var first, then the gitignored project .env. The value is never printed."""
    val = os.environ.get(KEY_VAR, "").strip()
    if val:
        return val
    if ENV_PATH.is_file():
        for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("export "):
                line = line[7:].lstrip()
            if line.startswith(KEY_VAR + "="):
                v = line.split("=", 1)[1].strip().strip('"').strip("'").strip()
                if v:
                    return v
    return None


def tls_context() -> ssl.SSLContext:
    ctx = ssl.create_default_context()            # CERT_REQUIRED + check_hostname
    if ctx.cert_store_stats().get("x509_ca", 0) == 0 and not os.environ.get("SSL_CERT_FILE"):
        loaded = False
        try:
            import certifi  # type: ignore
            ctx.load_verify_locations(cafile=certifi.where())
            loaded = True
        except Exception:
            pass
        if not loaded:
            for cand in ("/etc/ssl/cert.pem", "/opt/homebrew/etc/ca-certificates/cert.pem",
                         "/usr/local/etc/ca-certificates/cert.pem", "/etc/ssl/certs/ca-certificates.crt"):
                if os.path.isfile(cand):
                    ctx.load_verify_locations(cafile=cand)
                    break
    assert ctx.verify_mode == ssl.CERT_REQUIRED and ctx.check_hostname
    return ctx


# ----------------------------------------------------------------------------- request model

def output_format_for(entry: dict, opts) -> str:
    if entry["endpoint"] == "music":
        return getattr(opts, "music_output_format", None) or entry["output_format"]
    return getattr(opts, "output_format", None) or entry["output_format"]


def build_request(entry: dict, opts=None) -> dict:
    """Normalized request (no secrets). Its canonical JSON is hashed."""
    fmt = output_format_for(entry, opts)
    prompt = " ".join(entry["prompt"].split())
    if entry["endpoint"] == "sound-generation":
        path = "/v1/sound-generation"
        body = {
            "text": prompt,
            "model_id": entry["model"],
            "duration_seconds": round(float(entry["requestDurationSeconds"]), 3),
            "loop": bool(entry["loop"]),
            "prompt_influence": round(float(entry["promptInfluence"]), 3),
        }
    elif entry["endpoint"] == "music":
        path = "/v1/music"
        model = getattr(opts, "music_model", None) or entry["model"]
        body = {
            "prompt": prompt,                         # never together with composition_plan
            "model_id": model,
            "music_length_ms": int(entry["musicLengthMs"]),
            "force_instrumental": True,               # no seed together with prompt
        }
    else:
        raise ValueError(entry["endpoint"])
    return {"method": "POST", "host": API_HOST, "path": path,
            "query": {"output_format": fmt}, "body": body}


def request_hash(req: dict) -> str:
    canon = json.dumps(req, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(canon.encode("utf-8")).hexdigest()


# ----------------------------------------------------------------------------- ffmpeg helpers

def run(cmd: list[str], data: bytes | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, input=data, capture_output=True)


def raw_input_args(ext: str, output_format: str) -> list[str]:
    if ext == "pcm":
        rate = int(output_format.split("_")[1])
        return ["-f", "s16le", "-ar", str(rate), "-ac", "1"]
    if ext in ("ulaw", "alaw"):
        return ["-f", "mulaw" if ext == "ulaw" else "alaw", "-ar", "8000", "-ac", "1"]
    return []


def ffprobe(path: Path, input_args: list[str] | None = None) -> dict | None:
    cmd = [FFPROBE, "-v", "error", *(input_args or []), "-show_entries",
           "stream=codec_name,codec_long_name,sample_rate,channels,bits_per_sample,bit_rate,duration,duration_ts"
           ":format=format_name,duration,bit_rate", "-of", "json", str(path)]
    p = run(cmd)
    if p.returncode != 0:
        return None
    try:
        info = json.loads(p.stdout)
    except json.JSONDecodeError:
        return None
    streams = [s for s in info.get("streams", []) if s.get("codec_name")]
    if not streams:
        return None
    return {"stream": streams[0], "format": info.get("format", {})}


def decode_f32(path: Path, channels: int | None = None, rate: int = SR,
               input_args: list[str] | None = None, afilter: str | None = None) -> tuple[array.array, int]:
    if channels is None:
        pi = ffprobe(path, input_args)
        if not pi:
            raise RuntimeError(f"ffprobe cannot read {rel(path)}")
        channels = int(pi["stream"]["channels"])
    cmd = [FFMPEG, "-v", "error", "-nostdin", *(input_args or []), "-i", str(path)]
    if afilter:
        cmd += ["-af", afilter]
    cmd += ["-f", "f32le", "-acodec", "pcm_f32le", "-ac", str(channels), "-ar", str(rate), "pipe:1"]
    p = run(cmd)
    if p.returncode != 0:
        raise RuntimeError(f"ffmpeg decode failed for {rel(path)}: {p.stderr.decode(errors='replace')[:300]}")
    a = array.array("f")
    a.frombytes(p.stdout[: len(p.stdout) - len(p.stdout) % 4])
    if sys.byteorder != "little":
        a.byteswap()
    return a, channels


def write_wav(samples: array.array, channels: int, path: Path, bits: int = 16) -> None:
    """Float32 interleaved -> PCM WAV (16-bit with TPDF dither, or 24-bit) via temp + atomic rename."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    codec = "pcm_s16le" if bits == 16 else "pcm_s24le"
    af = "aresample=osf=s16:dither_method=triangular" if bits == 16 else "anull"
    data = samples.tobytes() if sys.byteorder == "little" else _swapped(samples)
    cmd = [FFMPEG, "-v", "error", "-nostdin", "-y", "-f", "f32le", "-ar", str(SR), "-ac", str(channels),
           "-i", "pipe:0", "-af", af, "-c:a", codec, "-map_metadata", "-1",
           "-fflags", "+bitexact", "-flags:a", "+bitexact", "-f", "wav", str(tmp)]
    p = run(cmd, data)
    if p.returncode != 0:
        raise RuntimeError(f"ffmpeg WAV write failed: {p.stderr.decode(errors='replace')[:300]}")
    if not ffprobe(tmp):
        raise RuntimeError(f"written WAV does not decode: {rel(tmp)}")
    os.replace(tmp, path)


def _swapped(a: array.array) -> bytes:
    b = array.array(a.typecode, a)
    b.byteswap()
    return b.tobytes()


def channel(a: array.array, c: int, n_ch: int) -> array.array:
    return a[c::n_ch] if n_ch > 1 else a


def interleave(chans: list[array.array]) -> array.array:
    if len(chans) == 1:
        return array.array("f", chans[0])
    n = len(chans[0])
    res = array.array("f", bytes(4 * n * len(chans)))
    for c, ch in enumerate(chans):
        res[c::len(chans)] = ch
    return res


def sumsq(a) -> float:
    try:
        return math.sumprod(a, a)            # Python >= 3.12 (C speed)
    except AttributeError:
        return sum(x * x for x in a)


def stats(a: array.array, n_ch: int) -> dict:
    frames = len(a) // n_ch
    peak = max((abs(max(a)), abs(min(a)))) if len(a) else 0.0
    per = []
    for c in range(n_ch):
        ch = channel(a, c, n_ch)
        n = max(1, len(ch))
        per.append({"dc": sum(ch) / n, "rms": math.sqrt(sumsq(ch) / n)})
    rms = math.sqrt(sum(p["rms"] ** 2 for p in per) / max(1, n_ch))
    dc = max((abs(p["dc"]) for p in per), default=0.0)
    clipped = sum(1 for x in a if abs(x) >= 0.99997)
    return {"frames": frames, "duration": frames / SR, "peak": peak, "peakDBFS": round(db(peak), 2),
            "rms": rms, "rmsDBFS": round(db(rms), 2), "dcOffset": dc, "clippedSamples": clipped}


def seam_metrics(a: array.array, n_ch: int) -> dict:
    """Click detector at the loop seam (last sample -> first sample).

    Second difference at the two seam points, compared with the 99th percentile of the second
    difference in +-256 samples around the seam (so a legit attack on the downbeat is not a click).
    """
    worst = 0.0
    detail = []
    for c in range(n_ch):
        ch = channel(a, c, n_ch)
        n = len(ch)
        if n < 1024:
            continue
        w = 256
        ring = list(ch[n - w:]) + list(ch[:w])      # seam between index w-1 and w
        d2 = [abs(ring[i + 1] - 2 * ring[i] + ring[i - 1]) for i in range(1, len(ring) - 1)]
        seam_vals = [d2[w - 2], d2[w - 1]]          # centred on ring[w-1] and ring[w]
        local = sorted(d2[: w - 4] + d2[w + 2:])
        p99 = local[int(0.99 * (len(local) - 1))] if local else 0.0
        jump = abs(ch[0] - ch[n - 1])
        floor = 4.0 / 32768.0
        ratio = max(seam_vals) / max(p99, floor)
        worst = max(worst, ratio)
        detail.append({"channel": c, "seamJump": round(jump, 6), "seamD2": round(max(seam_vals), 6),
                       "localP99D2": round(p99, 6), "ratio": round(ratio, 3)})
    return {"seamClickRatio": round(worst, 3), "pass": worst <= 3.0, "channels": detail}


# ----------------------------------------------------------------------------- local state

def id_dir(eid: str) -> Path:
    return RAW_ROOT / eid


def variants(eid: str) -> list[tuple[int, Path, dict]]:
    res = []
    d = id_dir(eid)
    if not d.is_dir():
        return res
    for p in sorted(d.glob("v*")):
        if p.is_dir() and p.name[1:].isdigit() and (p / "meta.json").is_file():
            with open(p / "meta.json", encoding="utf-8") as f:
                res.append((int(p.name[1:]), p, json.load(f)))
    res.sort(key=lambda t: t[0])
    return res


def variant_is_valid(vdir: Path, meta: dict) -> bool:
    if meta.get("technicalQA") != "pass":
        return False
    raw = vdir / meta.get("rawFile", "")
    return raw.is_file() and sha256_file(raw) == meta.get("rawSha256")


def selected_variant(eid: str) -> tuple[int, Path, dict] | None:
    sel_path = id_dir(eid) / "selection.json"
    vs = variants(eid)
    if sel_path.is_file():
        with open(sel_path, encoding="utf-8") as f:
            sel = json.load(f).get("selectedVariant")
        for n, p, m in vs:
            if n == sel and variant_is_valid(p, m) and m.get("listeningQA") != "rejected":
                return n, p, m
    for n, p, m in reversed(vs):
        if variant_is_valid(p, m) and m.get("listeningQA") != "rejected":
            return n, p, m
    return None


def uncertain_marker(eid: str) -> Path:
    return id_dir(eid) / "UNCERTAIN.json"


def append_attempt_log(eid: str, record: dict) -> None:
    d = id_dir(eid)
    d.mkdir(parents=True, exist_ok=True)
    line = json.dumps(record, ensure_ascii=False, sort_keys=True)
    if _SECRET and _SECRET in line:
        raise RuntimeError("refusing to log the API key")
    with open(d / "attempts.jsonl", "a", encoding="utf-8") as f:
        f.write(line + "\n")


def account_snapshot() -> dict | None:
    p = RAW_ROOT / "account_snapshot.json"
    if p.is_file():
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    return None


def state_label(eid: str) -> str:
    if uncertain_marker(eid).is_file():
        return "UNCERTAIN (check provider history, then resolve-uncertain)"
    vs = variants(eid)
    if not vs:
        return "not generated"
    sel = selected_variant(eid)
    if sel:
        n, _, m = sel
        return f"v{n} {m.get('technicalQA')} / listening {m.get('listeningQA')}"
    return "; ".join(f"v{n}:{m.get('technicalQA')}/{m.get('listeningQA')}" for n, _, m in vs)


# ----------------------------------------------------------------------------- HTTP

class HttpResult:
    def __init__(self, kind: str, status: int = 0, headers: dict | None = None,
                 body: bytes = b"", error: str = ""):
        self.kind = kind            # ok | http | not-sent | uncertain
        self.status = status
        self.headers = headers or {}
        self.body = body
        self.error = error


def http_call(method: str, path: str, query: dict | None, body: dict | None, key: str,
              read_timeout: float) -> HttpResult:
    ctx = tls_context()
    conn = http.client.HTTPSConnection(API_HOST, 443, timeout=CONNECT_TIMEOUT_S, context=ctx)
    url = path + ("?" + urlencode(query) if query else "")
    try:
        conn.connect()
    except ssl.SSLCertVerificationError as e:
        return HttpResult("not-sent", error=f"TLS certificate verification failed ({e}); install CA "
                          "certificates for this Python (verification is never disabled)")
    except (OSError, socket.timeout) as e:
        return HttpResult("not-sent", error=f"connection failed before sending: {type(e).__name__}: {e}")
    try:
        conn.sock.settimeout(read_timeout)
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"xi-api-key": key, "Accept": "*/*", "User-Agent": "VelvetCascade-audio-pipeline/1"}
        if payload is not None:
            headers["Content-Type"] = "application/json"
        conn.request(method, url, body=payload, headers=headers)
        resp = conn.getresponse()
        data = resp.read()
        hdrs = {k.lower(): v for k, v in resp.getheaders()}
        return HttpResult("ok" if resp.status == 200 else "http", resp.status, hdrs, data)
    except (socket.timeout, TimeoutError) as e:
        return HttpResult("uncertain", error=f"timeout after the request was sent: {type(e).__name__}")
    except (OSError, http.client.HTTPException) as e:
        return HttpResult("uncertain", error=f"network error after sending: {type(e).__name__}: {e}")
    finally:
        conn.close()


def kept_headers(h: dict) -> dict:
    res = {}
    for k, v in h.items():
        kl = k.lower()
        if kl in ("set-cookie", "authorization", "xi-api-key"):
            continue
        if kl in KEEP_HEADERS or kl.startswith("x-ratelimit") or "cost" in kl or "credit" in kl \
                or "character" in kl or kl.endswith("request-id") or "history" in kl or kl.startswith("song"):
            res[kl] = redact(v)
    return res


def provider_request_id(h: dict) -> str | None:
    for k in ("request-id", "x-request-id", "history-item-id", "song-id", "x-trace-id"):
        if h.get(k):
            return h[k]
    return None


def parse_error(body: bytes) -> str:
    try:
        j = json.loads(body.decode("utf-8", errors="replace"))
    except Exception:
        return body[:300].decode("utf-8", errors="replace")
    det = j.get("detail", j) if isinstance(j, dict) else j
    if isinstance(det, dict):
        parts = [str(det.get(k)) for k in ("status", "code", "type", "message") if det.get(k)]
        return " | ".join(parts) if parts else json.dumps(det)[:400]
    if isinstance(det, list):
        return "; ".join(f"{'.'.join(map(str, d.get('loc', [])))}: {d.get('msg')}" if isinstance(d, dict) else str(d)
                         for d in det)[:600]
    return str(det)[:400]


def retry_after_seconds(h: dict, attempt: int) -> float:
    ra = h.get("retry-after")
    if ra:
        try:
            return min(MAX_RETRY_AFTER_S, max(1.0, float(ra)))
        except ValueError:
            try:
                when = email.utils.parsedate_to_datetime(ra)
                return min(MAX_RETRY_AFTER_S, max(1.0, (when - dt.datetime.now(when.tzinfo)).total_seconds()))
            except Exception:
                pass
    return min(MAX_RETRY_AFTER_S, 5.0 * (2 ** (attempt - 1)))


# ----------------------------------------------------------------------------- generation

def sniff_ext(fmt: str, content_type: str, head: bytes) -> str:
    if head[:3] == b"ID3" or (len(head) > 1 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0):
        return "mp3"
    if head[:4] == b"OggS":
        return "ogg"
    if head[:4] == b"RIFF":
        return "wav"
    if head[:4] == b"fLaC":
        return "flac"
    if fmt.startswith("pcm_"):
        return "pcm"
    if fmt.startswith(("ulaw", "alaw")):
        return fmt.split("_")[0]
    return "bin"


def verify_audio(path: Path, ext: str, fmt: str, entry: dict) -> tuple[bool, list[str], dict]:
    reasons: list[str] = []
    info: dict = {}
    iargs = raw_input_args(ext, fmt)
    pi = ffprobe(path, iargs)
    if not pi:
        return False, ["not decodable by ffprobe"], info
    st = pi["stream"]
    info["codec"] = {k: st.get(k) for k in ("codec_name", "codec_long_name", "sample_rate", "channels",
                                              "bits_per_sample", "bit_rate")}
    info["container"] = pi["format"].get("format_name")
    try:
        a, ch = decode_f32(path, None if not iargs else 1, SR, iargs)
    except RuntimeError as e:
        return False, [str(e)], info
    s = stats(a, ch)
    info.update({"decodedDuration": round(s["duration"], 4), "decodedChannels": ch,
                 "peakDBFS": s["peakDBFS"], "rmsDBFS": s["rmsDBFS"]})
    exp = float(entry["requestDurationSeconds"])
    d = s["duration"]
    if entry["endpoint"] == "music":
        if not (0.5 * exp <= d <= 1.5 * exp):
            reasons.append(f"duration {d:.2f}s far from requested {exp:.2f}s")
        elif abs(d - exp) > 0.05 * exp:
            info["durationWarning"] = f"{d:.2f}s vs requested {exp:.2f}s"
    elif abs(d - exp) > max(0.3, (0.3 if entry.get("loop") else 0.2) * exp):
        # Для петель провайдер возвращает длину, удобную для бесшовного повтора (напр. 1.86 s при запросе 1.5 s).
        reasons.append(f"duration {d:.3f}s does not match requested {exp:.3f}s")
    if s["peakDBFS"] < -45 or s["rmsDBFS"] < -65:
        reasons.append(f"near-silent output (peak {s['peakDBFS']} dBFS, rms {s['rmsDBFS']} dBFS)")
    return not reasons, reasons, info


def make_master(raw: Path, ext: str, fmt: str, dest: Path) -> dict:
    """Decode for real (never rename MP3 to WAV) -> PCM WAV 48 kHz / 24-bit."""
    tmp = dest.with_name(dest.name + ".tmp")
    cmd = [FFMPEG, "-v", "error", "-nostdin", "-y", *raw_input_args(ext, fmt), "-i", str(raw),
           "-af", f"aresample={SR}:filter_size=64:phase_shift=10:cutoff=0.97",
           "-ar", str(SR), "-c:a", "pcm_s24le", "-map_metadata", "-1", "-fflags", "+bitexact",
           "-flags:a", "+bitexact", "-f", "wav", str(tmp)]
    p = run(cmd)
    if p.returncode != 0 or not ffprobe(tmp):
        raise RuntimeError(f"master decode failed: {p.stderr.decode(errors='replace')[:300]}")
    os.replace(tmp, dest)
    pi = ffprobe(dest)["stream"]
    return {"file": dest.name, "sampleRate": int(pi["sample_rate"]), "channels": int(pi["channels"]),
            "bitDepth": int(pi.get("bits_per_sample") or 24), "codec": pi["codec_name"],
            "sha256": sha256_file(dest)}


class RunState:
    def __init__(self):
        self.lock = threading.Lock()
        self.blocked: dict[str, str] = {}        # endpoint -> reason
        self.abort: str | None = None


def generate_one(entry: dict, key: str, opts, rs: RunState) -> dict:
    eid = entry["id"]
    req = build_request(entry, opts)
    rhash = request_hash(req)
    fmt = req["query"]["output_format"]
    res = {"id": eid, "result": "", "detail": ""}

    with rs.lock:
        if rs.abort:
            res.update(result="skipped", detail=rs.abort)
            return res
        if entry["endpoint"] in rs.blocked:
            res.update(result="skipped", detail=f"endpoint blocked earlier in this run: {rs.blocked[entry['endpoint']]}")
            return res

    if uncertain_marker(eid).is_file():
        res.update(result="blocked-uncertain",
                   detail="a previous attempt ended uncertain (timeout/5xx); check provider history, then "
                          "`generate_audio.py resolve-uncertain --ids " + eid + "`")
        return res

    vs = variants(eid)
    active = [(n, p, m) for n, p, m in vs if variant_is_valid(p, m) and m.get("listeningQA") != "rejected"]
    if active:
        n, p, m = active[-1]
        master = id_dir(eid) / "master.wav"
        if m.get("requestHash") == rhash:
            if not master.is_file():
                shutil.copyfile(p / "master.wav", master)
            res.update(result="reused", detail=f"existing valid output v{n} ({m.get('rawFile')})")
        else:
            res.update(result="skipped", detail=f"v{n} exists with different request hash (params changed); "
                                                "reject it first if a new variant is really wanted")
        return res
    if vs and not opts.extra_variant:
        res.update(result="skipped", detail="all existing variants are rejected/failed; pass --extra-variant "
                                            "to create one more (max 2 extra)")
        return res
    if len(vs) >= MAX_VARIANTS:
        res.update(result="stopped", detail=f"variant limit reached ({MAX_VARIANTS} = 1 + 2 extra)")
        return res
    vnum = (vs[-1][0] + 1) if vs else 1

    started = now_iso()
    t0 = time.time()
    attempt = 0
    while True:
        attempt += 1
        out(f"[{eid}] POST {req['path']} (v{vnum}, attempt {attempt}, format {fmt}, "
            f"{'music_length_ms=' + str(req['body'].get('music_length_ms')) if entry['endpoint'] == 'music' else 'duration=' + str(req['body'].get('duration_seconds')) + 's loop=' + str(req['body'].get('loop'))})")
        r = http_call("POST", req["path"], req["query"], req["body"], key, READ_TIMEOUT_S[entry["endpoint"]])
        kh = kept_headers(r.headers)
        log = {"time": now_iso(), "variant": vnum, "attempt": attempt, "requestHash": rhash,
               "kind": r.kind, "httpStatus": r.status, "providerHeaders": kh, "error": redact(r.error)}
        if r.kind == "not-sent":
            append_attempt_log(eid, log)
            dev_err(f"[{eid}] request not sent: {r.error}")
            res.update(result="error-not-sent", detail=r.error)
            return res
        if r.kind == "uncertain":
            log["note"] = "request may have been accepted and billed; no automatic retry"
            append_attempt_log(eid, log)
            atomic_write_json(uncertain_marker(eid), {"id": eid, "time": now_iso(), "requestHash": rhash,
                                                      "variant": vnum, "reason": redact(r.error)})
            dev_err(f"[{eid}] UNCERTAIN: {r.error}. Marked; not retried.")
            res.update(result="uncertain", detail=r.error)
            return res
        if r.status == 429:
            log["error"] = parse_error(r.body)
            append_attempt_log(eid, log)
            if attempt >= MAX_429_ATTEMPTS:
                dev_err(f"[{eid}] HTTP 429 after {attempt} attempts: {log['error']}")
                res.update(result="stopped", detail=f"HTTP 429 after {attempt} attempts: {log['error']}")
                return res
            wait = retry_after_seconds(r.headers, attempt)
            dev_err(f"[{eid}] HTTP 429 ({log['error']}); waiting {wait:.0f}s (Retry-After honoured)")
            time.sleep(wait)
            continue
        if r.kind == "http":
            reason = parse_error(r.body)
            log["error"] = reason
            append_attempt_log(eid, log)
            if r.status >= 500:
                atomic_write_json(uncertain_marker(eid), {"id": eid, "time": now_iso(), "requestHash": rhash,
                                                          "variant": vnum, "reason": f"HTTP {r.status}: {reason}"})
                dev_err(f"[{eid}] HTTP {r.status} (server error): {reason}. Marked UNCERTAIN; not retried.")
                res.update(result="uncertain", detail=f"HTTP {r.status}: {reason}")
                return res
            dev_err(f"[{eid}] HTTP {r.status}: {reason}. Stopping this ID.")
            if r.status == 401:
                with rs.lock:
                    rs.blocked[entry["endpoint"]] = f"HTTP 401 {reason}"
            if r.status in (402, 403):
                with rs.lock:
                    rs.blocked[entry["endpoint"]] = f"HTTP {r.status} {reason}"
            res.update(result=f"stopped-http-{r.status}", detail=reason)
            return res
        break    # 200

    elapsed = round(time.time() - t0, 2)
    ctype = r.headers.get("content-type", "")
    body = r.body
    head = body[:16]
    if "json" in ctype.lower() or body.lstrip()[:1] in (b"{", b"["):
        log = {"time": now_iso(), "variant": vnum, "kind": "json-instead-of-audio", "httpStatus": r.status,
               "contentType": ctype, "error": parse_error(body), "providerHeaders": kept_headers(r.headers)}
        append_attempt_log(eid, log)
        dev_err(f"[{eid}] HTTP 200 but JSON body ({ctype}): {log['error']} - not saved as audio")
        res.update(result="stopped", detail="JSON body instead of audio")
        return res
    if not (ctype.lower().startswith("audio/") or ctype.lower() in ("application/octet-stream", "binary/octet-stream")):
        dev_err(f"[{eid}] unexpected content-type {ctype!r}; verifying payload by decoding")

    vdir = id_dir(eid) / f"v{vnum}"
    vdir.mkdir(parents=True, exist_ok=True)
    ext = sniff_ext(fmt, ctype, head)
    tmp = vdir / f"raw.{ext}.tmp"
    with open(tmp, "wb") as f:
        f.write(body)
        f.flush()
        os.fsync(f.fileno())
    ok, reasons, info = verify_audio(tmp, ext, fmt, entry)
    raw_sha = hashlib.sha256(body).hexdigest()
    snap = account_snapshot() or {}
    meta = {
        "id": eid, "variant": vnum, "provider": ELEVEN_PROVIDER, "endpoint": req["path"],
        "model": req["body"]["model_id"], "outputFormatRequested": fmt,
        "requestHash": rhash, "normalizedRequest": req,
        "requestedAt": started, "completedAt": now_iso(), "elapsedSeconds": elapsed,
        "httpStatus": r.status, "contentType": ctype, "providerHeaders": kept_headers(r.headers),
        "providerRequestId": provider_request_id(r.headers),
        "rawSha256": raw_sha, "rawBytes": len(body),
        "accountTierAtGeneration": snap.get("tier"),
        "costNote": "Actual cost not invented: only provider response headers above are recorded.",
        "listeningQA": "pending",
        **info,
    }
    if ok:
        raw_final = vdir / f"raw.{ext}"
        os.replace(tmp, raw_final)                  # atomic rename after verification
        meta["rawFile"] = raw_final.name
        try:
            meta["master"] = make_master(raw_final, ext, fmt, vdir / "master.wav")
            meta["technicalQA"] = "pass"
            meta["technicalQAReasons"] = []
        except RuntimeError as e:
            meta["technicalQA"] = "fail"
            meta["technicalQAReasons"] = [str(e)]
    else:
        failed = vdir / f"raw_failed.{ext}"
        os.replace(tmp, failed)
        meta["rawFile"] = failed.name
        meta["technicalQA"] = "fail"
        meta["technicalQAReasons"] = reasons
    atomic_write_json(vdir / "meta.json", meta)
    append_attempt_log(eid, {"time": now_iso(), "variant": vnum, "kind": "ok", "httpStatus": 200,
                             "requestHash": rhash, "providerHeaders": meta["providerHeaders"],
                             "technicalQA": meta["technicalQA"], "reasons": meta["technicalQAReasons"]})
    if meta["technicalQA"] == "pass":
        tmpm = id_dir(eid) / "master.wav.tmp"
        shutil.copyfile(vdir / "master.wav", tmpm)
        os.replace(tmpm, id_dir(eid) / "master.wav")
        atomic_write_json(id_dir(eid) / "selection.json", {"id": eid, "selectedVariant": vnum, "time": now_iso()})
        c = info.get("codec", {})
        res.update(result="generated", detail=f"v{vnum} {c.get('codec_name')} {c.get('sample_rate')}Hz "
                                              f"{c.get('channels')}ch {info.get('decodedDuration')}s "
                                              f"peak {info.get('peakDBFS')} dBFS, request-id "
                                              f"{meta['providerRequestId']}, {elapsed}s")
    else:
        dev_err(f"[{eid}] output failed technical checks: {meta['technicalQAReasons']}")
        res.update(result="failed-checks", detail="; ".join(meta["technicalQAReasons"]))
    return res


def cmd_generate(opts) -> int:
    global _SECRET
    doc = load_requests()
    selected = parse_ids(opts.ids, doc["entries"])
    key = load_api_key()
    if not key:
        print(f"Missing {KEY_VAR}", file=sys.stderr)
        print(f"Set {KEY_VAR} in the environment or in the gitignored .env file "
              "(see .env.example). No audio was created.", file=sys.stderr)
        return 2
    _SECRET = key
    conc = max(1, min(2, int(opts.concurrency)))
    out(f"Generating {len(selected)} ID(s) with concurrency {conc}: {', '.join(e['id'] for e in selected)}")
    rs = RunState()
    with ThreadPoolExecutor(max_workers=conc) as ex:
        results = list(ex.map(lambda e: generate_one(e, key, opts, rs), selected))
    out("")
    out(f"{'ID':<4} {'result':<20} detail")
    for r in results:
        out(f"{r['id']:<4} {r['result']:<20} {r['detail']}")
    bad = [r for r in results if r["result"] not in ("generated", "reused")]
    return 1 if bad else 0


def cmd_account(opts) -> int:
    global _SECRET
    key = load_api_key()
    if not key:
        print(f"Missing {KEY_VAR}", file=sys.stderr)
        return 2
    _SECRET = key
    r = http_call("GET", "/v1/user/subscription", None, None, key, 60)
    if r.kind != "ok":
        dev_err(f"subscription query failed: {r.status} {r.error or parse_error(r.body)}")
        return 1
    j = json.loads(r.body)
    keep = ("tier", "status", "character_count", "character_limit", "next_character_count_reset_unix",
            "billing_period", "character_refresh_period", "can_use_instant_voice_cloning")
    snap = {k: j.get(k) for k in keep if k in j}
    snap["queriedAt"] = now_iso()
    atomic_write_json(RAW_ROOT / "account_snapshot.json", snap)
    for k, v in snap.items():
        out(f"  {k}: {v}")
    return 0


# ----------------------------------------------------------------------------- dry run

def cmd_dry_run(opts) -> int:
    doc = load_requests()
    selected = parse_ids(opts.ids, doc["entries"])
    out("DRY RUN - no network requests are sent, the API key is not read.")
    out(f"{'ID':<4} {'endpoint':<16} {'model':<24} {'format':<14} {'req':>7} {'target':>7} {'loop':<5} "
        f"{'runtime file':<28} {'hash':<14} state")
    tot_sfx = 0.0
    tot_music = 0
    for e in selected:
        req = build_request(e, opts)
        h = request_hash(req)[7:19]
        if e["endpoint"] == "music":
            reqd = f"{req['body']['music_length_ms']}ms"
            tot_music += req["body"]["music_length_ms"]
        else:
            reqd = f"{req['body']['duration_seconds']:.2f}s"
            tot_sfx += req["body"]["duration_seconds"]
        out(f"{e['id']:<4} {req['path'][4:]:<16} {req['body']['model_id']:<24} {req['query']['output_format']:<14} "
            f"{reqd:>7} {e['targetDuration']:>6.2f}s {str(e['loop']).lower():<5} {e['runtimeFile']:<28} {h:<14} "
            f"{state_label(e['id'])}")
    out("")
    out(f"{len(selected)} request(s): sound-generation total {tot_sfx:.1f}s requested, "
        f"music total {tot_music / 1000:.0f}s requested. Nothing was sent.")
    return 0


# ----------------------------------------------------------------------------- editing

def raised_cos(i: int, n: int) -> float:
    return 0.5 - 0.5 * math.cos(math.pi * (i + 0.5) / n)


def onepole_hp(x: list[float], fc: float = 20.0) -> list[float]:
    a = math.exp(-2 * math.pi * fc / SR)
    y = [0.0] * len(x)
    px = py = 0.0
    for i, v in enumerate(x):
        py = a * (py + v - px)
        px = v
        y[i] = py
    return y


def to_mono(a: array.array, n_ch: int) -> list[float]:
    if n_ch == 1:
        return list(a)
    chans = [channel(a, c, n_ch) for c in range(n_ch)]
    mono = [sum(v) / n_ch for v in zip(*chans)]
    m_rms = math.sqrt(sumsq(mono) / max(1, len(mono)))
    c_rms = max(math.sqrt(sumsq(ch) / max(1, len(ch))) for ch in chans)
    if c_rms > 0 and m_rms < 0.5 * c_rms:           # phase cancellation - use the louder channel
        best = max(chans, key=lambda ch: sumsq(ch))
        return list(best)
    return mono


def edit_one_shot(mono: list[float], target_s: float) -> tuple[list[float], dict]:
    x = onepole_hp(mono, 20.0)
    peak = max(abs(v) for v in x) or 1e-9
    thr = peak * 10 ** (-30 / 20)
    onset = next(i for i, v in enumerate(x) if abs(v) >= thr)
    pre = int(0.002 * SR)
    start = max(0, onset - pre)
    n = int(round(target_s * SR))
    seg = x[start:start + n]
    seg += [0.0] * (n - len(seg))
    speak = max(abs(v) for v in seg) or 1e-9
    w = int(0.02 * SR)
    tail_rms = math.sqrt(sum(v * v for v in seg[-w:]) / w)
    tail_rel = db(tail_rms / speak)
    shaped = False
    if tail_rel > -40.0:
        d = min(int(0.4 * n), int(0.15 * SR))
        k = math.log(10 ** (-40 / 20))              # reach about -40 dB at the cut
        for i in range(d):
            u = (i + 1) / d
            seg[n - d + i] *= math.exp(k * u * u)
        shaped = True
    fi = max(1, min(int(0.002 * SR), n // 10))
    for i in range(fi):
        seg[i] *= raised_cos(i, fi)
    fo = max(int(0.002 * SR), min(int(0.008 * SR), n // 10))
    for i in range(fo):
        seg[n - 1 - i] *= raised_cos(i, fo)
    return seg, {"method": "onset-trim + decay-preserving taper" if shaped else "onset-trim",
                 "sourceOnsetSample": onset, "sourceStartSample": start, "targetFrames": n,
                 "tailLevelBeforeShapingDbRel": round(tail_rel, 1), "decayShaped": shaped,
                 "fadeInMs": round(fi / SR * 1000, 2), "fadeOutMs": round(fo / SR * 1000, 2),
                 "dcFilter": "one-pole high-pass 20 Hz"}


def ncc(a: list[float], b: list[float]) -> float:
    ea, eb = sumsq(a), sumsq(b)
    if ea <= 0 or eb <= 0:
        return 0.0
    try:
        num = math.sumprod(a, b)
    except AttributeError:
        num = sum(p * q for p, q in zip(a, b))
    return num / math.sqrt(ea * eb)


def crossfade_loop(chans: list[list[float]], start: int, length: int, xf: int, equal_power: bool) -> list[list[float]]:
    """Loop = x[start:start+length]; the continuation after the loop end (tail, reverb) is crossfaded
    into the head so that sample length-1 -> 0 is the natural x[start+length-1] -> x[start+length]."""
    res = []
    for ch in chans:
        seg = ch[start:start + length]
        for i in range(xf):
            u = (i + 0.5) / xf
            if equal_power:
                gi, go = math.sin(0.5 * math.pi * u), math.cos(0.5 * math.pi * u)
            else:
                gi, go = u, 1.0 - u
            seg[i] = ch[start + i] * gi + ch[start + length + i] * go
        res.append(seg)
    return res


def strip_padding(chans: list[list[float]]) -> tuple[list[list[float]], int, int]:
    n = len(chans[0])
    lim = int(0.05 * SR)
    a = 0
    while a < min(lim, n) and all(abs(ch[a]) < 1e-5 for ch in chans):
        a += 1
    b = n
    while n - b < lim and b > a and all(abs(ch[b - 1]) < 1e-5 for ch in chans):
        b -= 1
    return [ch[a:b] for ch in chans], a, n - b


def edit_generic_loop(chans: list[list[float]], target_s: float, xf_ms: float, align_ms: float,
                      equal_power: bool) -> tuple[list[list[float]], dict]:
    """Loops requested with loop=true. Keep the provider loop if its seam is already clean; otherwise
    repair it with the shortest crossfade (continuation after the loop end blended into the head) that
    passes the seam check, trying a short seam-repair fade before the longer musical one."""
    chans, lead, trail = strip_padding(chans)
    n = len(chans[0])
    tgt = int(round(target_s * SR))
    natural = seam_metrics(interleave([array.array("f", c) for c in chans]), len(chans))
    info = {"strippedLeadingSamples": lead, "strippedTrailingSamples": trail,
            "providerLoopSeam": natural["seamClickRatio"]}
    if natural["pass"] and abs(n - tgt) <= 0.05 * tgt:
        info.update(method="provider loop kept (seam already clean)", loopFrames=n, crossfadeMs=0)
        return chans, info
    mono = [sum(v) / len(chans) for v in zip(*chans)]
    tried = []
    for fade_ms in sorted({min(30.0, xf_ms), xf_ms}):
        xf = max(1, int(fade_ms / 1000 * SR))
        L0 = min(tgt, n - xf - 1)
        if L0 < SR * 0.25:
            continue
        W = min(int(0.05 * SR), xf)
        best = (ncc(mono[0:W], mono[L0:L0 + W]), 0)
        al = int(align_ms / 1000 * SR)
        for d in range(-al, al + 1, 12):
            L = L0 + d
            if L + xf + W >= n or L < 1:
                continue
            c = ncc(mono[0:W], mono[L:L + W])
            if c > best[0]:
                best = (c, d)
        L = L0 + best[1]
        loop = crossfade_loop(chans, 0, L, xf, equal_power)
        sm = seam_metrics(interleave([array.array("f", c) for c in loop]), len(loop))
        tried.append({"crossfadeMs": round(xf / SR * 1000, 1), "seam": sm["seamClickRatio"]})
        if sm["pass"]:
            info.update(method="crossfade loop (continuation after loop end blended into the head)",
                        loopFrames=L, crossfadeMs=round(xf / SR * 1000, 1),
                        crossfadeCurve="equal-power" if equal_power else "equal-gain",
                        alignmentNcc=round(best[0], 3), alignmentOffsetSamples=best[1], crossfadesTried=tried)
            return loop, info
    raise RuntimeError(f"no crossfade produced a clean seam: {tried}")


# --- music analysis (pure Python FFT for chroma) -----------------------------------------

def _fft(re_: list[float], im_: list[float]) -> None:
    n = len(re_)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            re_[i], re_[j] = re_[j], re_[i]
            im_[i], im_[j] = im_[j], im_[i]
    size = 2
    while size <= n:
        half = size // 2
        ang = -2 * math.pi / size
        twr = [math.cos(ang * k) for k in range(half)]
        twi = [math.sin(ang * k) for k in range(half)]
        for s in range(0, n, size):
            for k in range(half):
                a = s + k
                b = a + half
                tr = re_[b] * twr[k] - im_[b] * twi[k]
                ti = re_[b] * twi[k] + im_[b] * twr[k]
                re_[b] = re_[a] - tr
                im_[b] = im_[a] - ti
                re_[a] += tr
                im_[a] += ti
        size <<= 1


def chroma_of(x: list[float], sr: int, nfft: int = 4096) -> list[float]:
    win = [0.5 - 0.5 * math.cos(2 * math.pi * i / nfft) for i in range(nfft)]
    re_ = [v * w for v, w in zip(x[:nfft], win)] + [0.0] * max(0, nfft - len(x))
    im_ = [0.0] * nfft
    _fft(re_, im_)
    ch = [0.0] * 12
    for k in range(1, nfft // 2):
        f = k * sr / nfft
        if f < 70 or f > 2200:
            continue
        mag = math.hypot(re_[k], im_[k])
        pc = int(round(12 * math.log2(f / 440.0))) % 12
        ch[pc] += mag
    return ch


def cos_sim(a: list[float], b: list[float]) -> float:
    na = math.sqrt(sum(v * v for v in a))
    nb = math.sqrt(sum(v * v for v in b))
    return sum(p * q for p, q in zip(a, b)) / (na * nb) if na > 0 and nb > 0 else 0.0


def analyse_music(master: Path, beats_per_bar: int, nominal_bpm: float) -> dict:
    ar = 12000
    hop = 120                                   # 10 ms
    full, _ = decode_f32(master, 1, ar)
    low, _ = decode_f32(master, 1, ar, afilter="lowpass=f=180,lowpass=f=180")
    full = list(full)
    low = list(low)
    diff = [b - a for a, b in zip(full, full[1:])] + [0.0]
    F = len(full) // hop
    ef = [sumsq(diff[i * hop:(i + 1) * hop]) for i in range(F)]
    el = [sumsq(low[i * hop:(i + 1) * hop]) for i in range(F)]

    def onset(e: list[float]) -> list[float]:
        lg = [math.log(v + 1e-9) for v in e]
        o = [0.0] + [max(0.0, lg[i] - lg[i - 1]) for i in range(1, len(lg))]
        return [max(o[max(0, i - 1):i + 2]) for i in range(len(o))]      # 3-frame max for jitter
    of, ol = onset(ef), onset(el)

    def comb(o: list[float], bpm: float) -> tuple[float, float]:
        P = 6000.0 / bpm
        best = (0.0, 0.0)
        steps = int(P)
        for ph in range(steps):
            s = 0.0
            t = float(ph)
            while t < len(o):
                s += o[int(t)]
                t += P
            s /= (len(o) / P)
            if s > best[0]:
                best = (s, float(ph))
        return best

    cands = []
    b = 80.0
    while b <= 112.0:
        sc, ph = comb(of, b)
        prior = 0.85 + 0.15 * math.exp(-0.5 * ((b - nominal_bpm) / 6.0) ** 2)
        cands.append((sc * prior, b, ph))
        b += 0.25
    cands.sort(reverse=True)
    _, b0, _ = cands[0]
    fine = []
    b = b0 - 0.3
    while b <= b0 + 0.3:
        sc, ph = comb(of, b)
        fine.append((sc, b, ph))
        b += 0.02
    fine.sort(reverse=True)
    _, bpm, phase = fine[0]
    P = 6000.0 / bpm
    beats = []
    t = phase
    while t < F:
        beats.append(t)
        t += P
    bar_scores = []
    for j in range(beats_per_bar):
        s = sum(ol[int(beats[k])] + 0.5 * of[int(beats[k])] for k in range(j, len(beats), beats_per_bar))
        bar_scores.append(s / max(1, len(range(j, len(beats), beats_per_bar))))
    jd = max(range(beats_per_bar), key=lambda j: bar_scores[j])
    downbeats_f = beats[jd::beats_per_bar]
    # bar features
    bar_len_s = beats_per_bar * 60.0 / bpm
    bars = []
    for m, dbf in enumerate(downbeats_f):
        a = int(dbf * hop)
        e = int(a + bar_len_s * ar)
        if e > len(full):
            break
        seg = full[a:e]
        rms = math.sqrt(sumsq(seg) / len(seg))
        chroma = [0.0] * 12
        nfr = 3
        for q in range(nfr):
            off = a + int(q * (e - a - 4096) / max(1, nfr - 1))
            c = chroma_of(full[off:off + 4096], ar)
            chroma = [u + v for u, v in zip(chroma, c)]
        bars.append({"index": m, "startSample48k": int(round(dbf * hop * SR / ar)), "rmsDb": db(rms), "chroma": chroma})
    return {"bpm": round(bpm, 3), "beatPhaseFrames": phase, "downbeatBeatIndex": jd,
            "barScores": [round(v, 4) for v in bar_scores], "bars": bars, "barLenSamples": bar_len_s * SR,
            "tempoCandidates": [(round(c[1], 2), round(c[0], 4)) for c in cands[:5]]}


def edit_music_loop(chans: list[list[float]], master: Path, entry: dict) -> tuple[list[list[float]], dict]:
    bpb = int(entry["beatsPerBar"])
    an = analyse_music(master, bpb, float(entry.get("tempoBpm", 96)))
    bars = an["bars"]
    n = len(chans[0])
    if len(bars) < 10:
        raise RuntimeError("too few bars detected for a loop")
    med = sorted(b["rmsDb"] for b in bars)[len(bars) // 2]
    valid = [b["rmsDb"] >= med - 8.0 for b in bars]
    xf_max = int(0.30 * SR)
    L_bar = an["barLenSamples"]
    best = None
    starts = [m for m in range(len(bars) - 1) if valid[m] and valid[m + 1]][:6]
    for m in starts:
        for nb in (32, 28, 24, 20, 16, 12, 8):
            e = m + nb
            if e >= len(bars) or not valid[e]:
                continue
            s_samp = bars[m]["startSample48k"]
            L = int(round(nb * L_bar))
            if s_samp + L + xf_max + int(0.08 * SR) > n:
                continue
            sim = cos_sim(bars[e]["chroma"], bars[m]["chroma"])
            if m >= 1:
                sim = 0.65 * sim + 0.35 * cos_sim(bars[e - 1]["chroma"], bars[m - 1]["chroma"])
            esim = max(0.0, 1.0 - abs(bars[e]["rmsDb"] - bars[m]["rmsDb"]) / 12.0)
            score = sim + 0.3 * esim + 0.04 * nb / 4
            if best is None or score > best[0]:
                best = (score, m, nb, s_samp, L, sim, esim)
    if best is None:
        raise RuntimeError("no loop candidate found at detected downbeats")
    score, m, nb, s_samp, L, sim, esim = best
    mono = [sum(v) / len(chans) for v in zip(*chans)]
    W = int(0.05 * SR)
    al = int(0.012 * SR)
    best1 = (-2.0, 0)
    best2 = (-2.0, 0, 0)
    for d in range(-al, al + 1, 24):
        s = s_samp + d
        if s < 0 or s + L + al + W + xf_max > n:
            continue
        seg0 = mono[s:s + W]
        c0 = ncc(seg0, mono[s + L:s + L + W])
        if c0 > best1[0]:
            best1 = (c0, d)
        for dl in range(-al, al + 1, 24):
            c = ncc(seg0, mono[s + L + dl:s + L + dl + W])
            if c > best2[0]:
                best2 = (c, d, dl)
    if best2[0] >= 0.3 and best2[0] > best1[0] + 0.05:
        c, d, dl = best2                    # the continuation clearly re-aligns with the loop start
        s0 = s_samp + d
        seg0 = mono[s0:s0 + W]
        for fdl in range(dl - 24, dl + 25, 2):          # sample-level refinement of the loop length
            if s0 + L + fdl + W + xf_max <= n:
                cf = ncc(seg0, mono[s0 + L + fdl:s0 + L + fdl + W])
                if cf > c:
                    c, dl = cf, fdl
    else:
        (c, d), dl = best1, 0               # keep the bar length from the detected tempo
    s = s_samp + d
    L = L + dl
    if c >= 0.6:
        xf, ep = int(0.04 * SR), False
    elif c >= 0.2:
        xf, ep = int(0.09 * SR), True
    else:
        xf, ep = int(0.18 * SR), True
    loop = crossfade_loop(chans, s, L, xf, ep)
    info = {"method": "downbeat-aligned bar loop, continuation (tail/reverb) crossfaded into the head",
            "detectedBpm": an["bpm"], "tempoCandidates": an["tempoCandidates"], "beatsPerBar": bpb,
            "downbeatBeatIndex": an["downbeatBeatIndex"], "barsDetected": len(bars),
            "loopStartBar": m, "loopBars": nb, "sourceStartSample": s, "loopFrames": L,
            "loopLengthAdjustSamples": dl,
            "effectiveBpm": round(nb * bpb * 60.0 * SR / L, 4),
            "chromaSimilarity": round(sim, 3), "energySimilarity": round(esim, 3),
            "seamAlignNcc": round(c, 3), "seamAlignOffsetSamples": d,
            "crossfadeMs": round(xf / SR * 1000, 1), "crossfadeCurve": "equal-power" if ep else "equal-gain",
            "note": "Automatic edit; loop must still be listened to (3+ repeats) before approval."}
    return loop, info


SFX_QUIET_OUTLIER_DB = 15.0   # one-shot тише потолка более чем на 15 dB — выброс провайдера
SFX_OUTLIER_LIFT_TO_DB = 8.0  # поднимается до (потолок − 8 dB), не до максимума


def apply_gain_and_dc(chans: list[list[float]], peak_ceiling_db: float, rms_ceiling_db: float | None,
                      lift_outliers: bool = False) -> tuple[list[list[float]], dict]:
    res = []
    for ch in chans:
        m = sum(ch) / max(1, len(ch))
        res.append([v - m for v in ch] if abs(m) > 1e-7 else ch)
    peak = max(max(abs(v) for v in ch) for ch in res) or 1e-9
    rms = math.sqrt(sum(sumsq(ch) for ch in res) / sum(len(ch) for ch in res))
    g_db = min(0.0, peak_ceiling_db - 0.1 - db(peak))
    lifted = False
    if lift_outliers and db(peak) < peak_ceiling_db - SFX_QUIET_OUTLIER_DB:
        g_db = (peak_ceiling_db - SFX_OUTLIER_LIFT_TO_DB) - db(peak)
        lifted = True
    if rms_ceiling_db is not None:
        g_db = min(g_db, rms_ceiling_db - db(rms))
    g = 10 ** (g_db / 20)
    if g_db != 0:
        res = [[v * g for v in ch] for ch in res]
    info = {"gainDb": round(g_db, 2), "peakCeilingDb": peak_ceiling_db, "rmsCeilingDb": rms_ceiling_db}
    if lifted:
        info["quietOutlierLift"] = f"provider output was more than {SFX_QUIET_OUTLIER_DB:.0f} dB below the ceiling; lifted to ceiling-{SFX_OUTLIER_LIFT_TO_DB:.0f} dB"
    return res, info


def lift_quiet_ambience(chans: list[list[float]], rms_ceiling_db: float, peak_ceiling_db: float) -> tuple[list[list[float]], dict]:
    """Ambience, пришедший намного тише целевого RMS (−36 dB), поднимается до RMS −40 dB (в пределах пикового потолка)."""
    rms = math.sqrt(sum(sumsq(ch) for ch in chans) / sum(len(ch) for ch in chans)) or 1e-9
    peak = max(max(abs(v) for v in ch) for ch in chans) or 1e-9
    if db(rms) >= rms_ceiling_db - 12:
        return chans, {}
    g_db = min((rms_ceiling_db - 4) - db(rms), peak_ceiling_db - 0.1 - db(peak))
    g = 10 ** (g_db / 20)
    return [[v * g for v in ch] for ch in chans], {"quietAmbienceLiftDb": round(g_db, 2)}


# ----------------------------------------------------------------------------- manifest

MIX_DEFAULTS = {
    "busVolumes": {"music": 0.45, "sfx": 0.70, "ambience": 0.20},
    "masterHeadroomDb": 6,
    "maxSfxVoices": 10,
    "priorityOrder": ["highest", "high", "medium", "low"],
    "musicDuck": {"db": -6, "attackMs": 80, "releaseMs": 450, "on": ["turn", "result", "reward"]},
    "menuGameplayCrossfadeMs": 600,
    "musicAssignment": {"M01": "menu, world maps, Settings", "M02": "levels of worlds 1-8", "M03": "levels of world 9"},
    "ambienceAssignment": {"A01": "menu", "A02": "level scene", "rule": "never both ambience loops at once"},
}


def load_manifest() -> dict:
    if MANIFEST_PATH.is_file():
        with open(MANIFEST_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {"entries": []}


def save_manifest(man: dict, requests_doc: dict) -> None:
    order = [e["id"] for e in requests_doc["entries"]]
    by_id = {e["id"]: e for e in man.get("entries", [])}
    entries = [by_id[i] for i in order if i in by_id]
    n_el = sum(1 for e in entries if e.get("provider") == ELEVEN_PROVIDER)
    n_sub = sum(1 for e in entries if e.get("provider") == SUBSTITUTE_PROVIDER)
    n_app = sum(1 for e in entries if e.get("provider") == ELEVEN_PROVIDER and e.get("qaStatus") == "approved")
    missing = [i for i in order if i not in by_id]
    doc = {
        "schemaVersion": 1,
        "game": "Velvet Cascade",
        "updatedAt": now_iso(),
        "resourceSubdirectory": "Audio",
        "loopPointConvention": "loopStart/loopEnd are sample frames; loopEnd is exclusive and equals frameCount (whole file loops).",
        "releaseGate": "Release requires all 44 IDs with provider 'ElevenLabs' and qaStatus 'approved' (human listening QA).",
        "releaseReady": n_app == 44 and not missing,
        "counts": {"total": len(entries), "elevenLabs": n_el, "substitute": n_sub, "approved": n_app,
                   "missing": missing},
        "mixDefaults": MIX_DEFAULTS,
        "entries": entries,
    }
    atomic_write_json(MANIFEST_PATH, doc)


def runtime_file_facts(path: Path) -> dict:
    pi = ffprobe(path)
    if not pi:
        raise RuntimeError(f"runtime file does not decode: {rel(path)}")
    st = pi["stream"]
    ch = int(st["channels"])
    a, _ = decode_f32(path, ch, int(st["sample_rate"]))
    s = stats(a, ch)
    facts = {
        "sampleRate": int(st["sample_rate"]), "channels": ch,
        "bitDepth": int(st.get("bits_per_sample") or 0) or None,
        "format": f"{pi['format'].get('format_name')}/{st['codec_name']}",
        "frameCount": s["frames"], "editedDuration": round(s["frames"] / int(st["sample_rate"]), 4),
        "peakDBFS": s["peakDBFS"], "rmsDBFS": s["rmsDBFS"], "dcOffset": round(s["dcOffset"], 7),
        "runtimeSha256": sha256_file(path),
    }
    return facts, a


def base_entry(req: dict) -> dict:
    e = {k: req[k] for k in ("id", "kind", "bus", "runtimeFile", "priority", "eventMapping", "targetDuration", "isLoop")}
    for k in ("notes", "pitchVariantsSemitones", "gainVariationDbMax", "tempoBpm", "beatsPerBar"):
        if k in req:
            e[k] = req[k]
    return e


LICENSE_NOTE_EL = ("Generated with ElevenLabs on the user's account; plan tier recorded in accountTier when the key "
                   "allows user_read (on 2026-09-29 it did not: HTTP 401, and the Music API answered 402 paid_plan_required, "
                   "which indicates a free plan). Before commercial "
                   "publication verify the commercial-use rights of exactly that plan (spec: do not assume any "
                   "free-tier output is commercially licensed).")


# ----------------------------------------------------------------------------- build-runtime

def build_one(entry: dict) -> dict:
    eid = entry["id"]
    sel = selected_variant(eid)
    if not sel:
        return {"id": eid, "result": "no-elevenlabs-master", "detail": state_label(eid)}
    vnum, vdir, meta = sel
    master = vdir / "master.wav"
    if not master.is_file():
        raise RuntimeError(f"{eid}: selected master missing")
    a, C = decode_f32(master)
    chans = [list(channel(a, c, C)) for c in range(C)]
    kind = entry["kind"]
    if kind == "sfx" and not entry["isLoop"]:
        mono = to_mono(a, C)
        seg, info = edit_one_shot(mono, float(entry["targetDuration"]))
        outc, g = apply_gain_and_dc([seg], SFX_PEAK_CEILING_DB[entry["priority"]], None, lift_outliers=True)
    elif kind == "sfx":
        mono = to_mono(a, C)
        loop, info = edit_generic_loop([mono], float(entry["targetDuration"]), 25.0, 30.0, False)
        outc, g = apply_gain_and_dc(loop, SFX_PEAK_CEILING_DB[entry["priority"]], None)
    elif kind == "ambience":
        xf = 1200.0 if eid == "A01" else 800.0
        loop, info = edit_generic_loop(chans, float(entry["targetDuration"]), xf, 0.0, True)
        outc, g = apply_gain_and_dc(loop, AMBIENCE_PEAK_CEILING_DB, AMBIENCE_RMS_CEILING_DB)
        outc, lift = lift_quiet_ambience(outc, AMBIENCE_RMS_CEILING_DB, AMBIENCE_PEAK_CEILING_DB)
        g.update(lift)
    else:
        loop, info = edit_music_loop(chans, master, entry)
        outc, g = apply_gain_and_dc(loop, MUSIC_PEAK_CEILING_DB, MUSIC_RMS_CEILING_DB)
    info["level"] = g
    samples = interleave([array.array("f", c) for c in outc])
    dest = RUNTIME_DIR / entry["runtimeFile"]
    write_wav(samples, len(outc), dest, 16)
    facts, decoded = runtime_file_facts(dest)
    seam = seam_metrics(decoded, facts["channels"]) if entry["isLoop"] else None
    info["seamAfterEdit"] = seam
    atomic_write_json(id_dir(eid) / "runtime_edit.json", {"id": eid, "variant": vnum, "time": now_iso(),
                                                          "runtimeFile": rel(dest), **info})
    snap = account_snapshot() or {}
    e = base_entry(entry)
    codec = meta.get("codec", {})
    e.update({
        "provider": ELEVEN_PROVIDER,
        "model": meta.get("model"),
        "requestID": meta.get("providerRequestId"),
        "providerHeaders": meta.get("providerHeaders", {}),
        "requestHash": meta.get("requestHash"),
        "variant": vnum,
        "sourceHash": "sha256:" + meta.get("rawSha256", ""),
        "sourceFile": rel(vdir / meta["rawFile"]),
        "sourceCodec": f"{codec.get('codec_name')} {codec.get('sample_rate')} Hz {codec.get('channels')}ch "
                       f"{int(codec.get('bit_rate') or 0) // 1000} kb/s ({meta.get('outputFormatRequested')})",
        "masterFile": rel(id_dir(eid) / "master.wav"),
        "productionDate": (meta.get("completedAt") or now_iso())[:10],
        **facts,
        "loopStart": 0 if entry["isLoop"] else None,
        "loopEnd": facts["frameCount"] if entry["isLoop"] else None,
        "qaStatus": "approved" if meta.get("listeningQA") == "approved" else "auto-qa-pass-pending-listening",
        "listeningQA": meta.get("listeningQA", "pending"),
        "accountTier": meta.get("accountTierAtGeneration") or snap.get("tier"),
        "licensePlanNote": LICENSE_NOTE_EL,
        "edit": {k: v for k, v in info.items() if k not in ("tempoCandidates",)},
    })
    if kind == "music":
        e["loopBars"] = info.get("loopBars")
        e["detectedBpm"] = info.get("detectedBpm")
        e["nominalTempoBpm"] = entry.get("tempoBpm")
        e["tempoBpm"] = info.get("effectiveBpm")        # loop length == loopBars bars at this tempo
    if seam and not seam["pass"]:
        e["qaStatus"] = "auto-qa-fail-seam"
    return {"id": eid, "result": "built", "entry": e,
            "detail": f"v{vnum} -> {entry['runtimeFile']} {facts['editedDuration']}s {facts['channels']}ch "
                      f"peak {facts['peakDBFS']} dBFS" + (f", seam ratio {seam['seamClickRatio']}" if seam else "")}


def cmd_build_runtime(opts) -> int:
    doc = load_requests()
    selected = parse_ids(opts.ids, doc["entries"])
    man = load_manifest()
    by_id = {e["id"]: e for e in man.get("entries", [])}
    rc = 0
    for entry in selected:
        try:
            r = build_one(entry)
        except Exception as ex:          # report and continue with the next ID
            dev_err(f"[{entry['id']}] build-runtime failed: {ex}")
            rc = 1
            continue
        if r["result"] == "built":
            by_id[entry["id"]] = r["entry"]
        out(f"{r['id']:<4} {r['result']:<22} {r['detail']}")
    man["entries"] = list(by_id.values())
    save_manifest(man, doc)
    out(f"Manifest updated: {rel(MANIFEST_PATH)}")
    return rc


# ----------------------------------------------------------------------------- QA verdicts

def cmd_verdict(opts, verdict: str) -> int:
    doc = load_requests()
    selected = parse_ids(opts.ids, doc["entries"])
    man = load_manifest()
    by_id = {e["id"]: e for e in man.get("entries", [])}
    for entry in selected:
        eid = entry["id"]
        vs = variants(eid)
        sel = selected_variant(eid)
        if not sel:
            out(f"{eid}: no selectable ElevenLabs variant")
            continue
        n, p, m = sel
        m["listeningQA"] = verdict
        m["listeningQANote"] = opts.note or ""
        m["listeningQATime"] = now_iso()
        atomic_write_json(p / "meta.json", m)
        append_attempt_log(eid, {"time": now_iso(), "variant": n, "kind": f"listening-{verdict}", "note": opts.note or ""})
        if eid in by_id and by_id[eid].get("provider") == ELEVEN_PROVIDER and by_id[eid].get("variant") == n:
            by_id[eid]["listeningQA"] = verdict
            by_id[eid]["qaStatus"] = "approved" if verdict == "approved" else "rejected-listening"
        out(f"{eid}: v{n} listeningQA = {verdict}" + (f" (variants so far: {len(vs)}/{MAX_VARIANTS})" if verdict == "rejected" else ""))
    man["entries"] = list(by_id.values())
    if man["entries"]:
        save_manifest(man, doc)
    return 0


def cmd_resolve_uncertain(opts) -> int:
    doc = load_requests()
    for entry in parse_ids(opts.ids, doc["entries"]):
        mk = uncertain_marker(entry["id"])
        if mk.is_file():
            with open(mk, encoding="utf-8") as f:
                data = json.load(f)
            append_attempt_log(entry["id"], {"time": now_iso(), "kind": "uncertain-resolved", "marker": data,
                                             "note": opts.note or ""})
            mk.unlink()
            out(f"{entry['id']}: uncertain marker resolved")
    return 0


def cmd_qa(argv: list[str]) -> int:
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import audio_qa  # noqa: E402
    return audio_qa.main(argv)


# ----------------------------------------------------------------------------- CLI

def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "qa":
        return cmd_qa(argv[1:])
    ap = argparse.ArgumentParser(description="Velvet Cascade ElevenLabs audio pipeline")
    sub = ap.add_subparsers(dest="mode", required=True)
    for name in ("dry-run", "generate", "build-runtime", "approve", "reject", "resolve-uncertain", "account"):
        p = sub.add_parser(name)
        if name != "account":
            p.add_argument("--ids", required=name in ("generate", "approve", "reject", "resolve-uncertain"),
                           help="e.g. S01-S05, S01,S03, A01-A02, M01, sfx, ambience, music, all")
        if name in ("dry-run", "generate"):
            p.add_argument("--output-format", help="override output_format for sound-generation")
            p.add_argument("--music-output-format", help="override output_format for music")
            p.add_argument("--music-model", help="override music model_id (music_v1 default)")
        if name == "generate":
            p.add_argument("--concurrency", type=int, default=1, help="1 or 2")
            p.add_argument("--extra-variant", action="store_true",
                           help="allow one extra variant for IDs whose variants were all rejected (max 2 extra)")
        if name in ("approve", "reject", "resolve-uncertain"):
            p.add_argument("--note", default="")
    opts = ap.parse_args(argv)
    if opts.mode == "dry-run":
        return cmd_dry_run(opts)
    if opts.mode == "generate":
        return cmd_generate(opts)
    if opts.mode == "account":
        return cmd_account(opts)
    if opts.mode == "build-runtime":
        return cmd_build_runtime(opts)
    if opts.mode == "approve":
        return cmd_verdict(opts, "approved")
    if opts.mode == "reject":
        return cmd_verdict(opts, "rejected")
    if opts.mode == "resolve-uncertain":
        return cmd_resolve_uncertain(opts)
    return 2


if __name__ == "__main__":
    sys.exit(main())
