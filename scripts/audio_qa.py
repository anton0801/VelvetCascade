#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Velvet Cascade - audio QA (Python 3 stdlib + ffmpeg/ffprobe).

Checks all 44 runtime files against scripts/audio_requests.json and the audio manifest:
  * manifest has exactly the 44 IDs, runtime file names keep the spec stems
  * every file exists, ffprobe decodes it and a full ffmpeg decode succeeds
  * non-zero signal, sample peak <= -3 dBFS (music <= -6 dBFS), no clipped samples, |DC| small
  * sample rate / channels / bit depth / frame count / hash match the manifest
  * one-shots: duration == target, onset without extra silence, tail not cut abruptly
  * loops: loop points valid, click measure at the seam (and at the joins of a 3x repeat render),
    music loops are exact bar multiples
  * provider bookkeeping (substitutes clearly labelled, ElevenLabs entries point at a raw source
    whose sha256 matches sourceHash)
  * secret scan: the API key value (read at runtime from env/.env, never printed), any
    ElevenLabs-style key pattern and the header name "xi-api-key" must not appear in the app
    sources/resources/manifests; the key value must not appear in scripts, docs or AudioRaw metadata.
Exit code 0 = pass, 1 = failures. --release additionally requires every ID to be an approved
ElevenLabs file (the spec's release gate). Listening QA is NOT automated.
"""
from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUESTS_PATH = ROOT / "scripts" / "audio_requests.json"
RUNTIME_DIR = ROOT / "VelvetCascade" / "Resources" / "Audio"
MANIFEST_PATH = ROOT / "VelvetCascade" / "Resources" / "Manifests" / "audio_manifest.json"
RAW_ROOT = ROOT / "Production" / "AudioRaw"
ENV_PATH = ROOT / ".env"
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
FFPROBE = shutil.which("ffprobe") or "/opt/homebrew/bin/ffprobe"

SUB = "procedural-substitute (NOT ElevenLabs)"
EL = "ElevenLabs"
CLIP = 0.99997
DC_MAX = 0.002
SEAM_MAX = 3.0


def db(x: float) -> float:
    return 20 * math.log10(x) if x > 0 else -999.0


def sumsq(a) -> float:
    try:
        return math.sumprod(a, a)
    except AttributeError:
        return sum(v * v for v in a)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def probe(path: Path) -> dict | None:
    p = subprocess.run([FFPROBE, "-v", "error", "-show_entries",
                        "stream=codec_name,sample_rate,channels,bits_per_sample,duration_ts,duration:format=format_name",
                        "-of", "json", str(path)], capture_output=True)
    if p.returncode != 0:
        return None
    try:
        j = json.loads(p.stdout)
        return {"stream": j["streams"][0], "format": j.get("format", {})}
    except (json.JSONDecodeError, KeyError, IndexError):
        return None


def decode(path: Path, ch: int, sr: int) -> array.array | None:
    p = subprocess.run([FFMPEG, "-v", "error", "-nostdin", "-i", str(path), "-f", "f32le", "-acodec", "pcm_f32le",
                        "-ac", str(ch), "-ar", str(sr), "pipe:1"], capture_output=True)
    if p.returncode != 0:
        return None
    a = array.array("f")
    a.frombytes(p.stdout[: len(p.stdout) - len(p.stdout) % 4])
    if sys.byteorder != "little":
        a.byteswap()
    return a


def seam(ch: array.array) -> float:
    n = len(ch)
    w = 256
    if n < 4 * w:
        return 0.0
    ring = list(ch[n - w:]) + list(ch[:w])
    d2 = [abs(ring[i + 1] - 2 * ring[i] + ring[i - 1]) for i in range(1, len(ring) - 1)]
    at = max(d2[w - 2], d2[w - 1])
    local = sorted(d2[: w - 4] + d2[w + 2:])
    p99 = local[int(0.99 * (len(local) - 1))]
    return at / max(p99, 4.0 / 32768.0)


def repeat_join_ratio(path: Path, ch: int, sr: int, frames: int, reps: int = 3) -> tuple[float, bool]:
    """Decode the file `reps` times back to back through the real decoder (ffmpeg -stream_loop) and
    measure the click ratio at every join; also confirms the decoder adds no padding (3 x frames)."""
    p = subprocess.run([FFMPEG, "-v", "error", "-nostdin", "-stream_loop", str(reps - 1), "-i", str(path),
                        "-f", "f32le", "-acodec", "pcm_f32le", "-ac", str(ch), "-ar", str(sr), "pipe:1"],
                       capture_output=True)
    if p.returncode != 0:
        return 999.0, False
    a = array.array("f")
    a.frombytes(p.stdout[: len(p.stdout) - len(p.stdout) % 4])
    total = len(a) // ch
    exact = total == reps * frames
    w = 256
    worst = 0.0
    for c in range(ch):
        for j in range(1, reps):
            k = j * frames
            seg = [a[(k + i) * ch + c] for i in range(-w, w)]
            d2 = [abs(seg[i + 1] - 2 * seg[i] + seg[i - 1]) for i in range(1, len(seg) - 1)]
            at = max(d2[w - 2], d2[w - 1])
            local = sorted(d2[: w - 4] + d2[w + 2:])
            p99 = local[int(0.99 * (len(local) - 1))]
            worst = max(worst, at / max(p99, 4.0 / 32768.0))
    return worst, exact


def load_key() -> str | None:
    v = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if v:
        return v
    if ENV_PATH.is_file():
        for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("export "):
                line = line[7:].lstrip()
            if line.startswith("ELEVENLABS_API_KEY="):
                v = line.split("=", 1)[1].strip().strip('"').strip("'").strip()
                return v or None
    return None


KEY_PATTERN = re.compile(rb"sk_[0-9a-f]{40,}")


def secret_scan() -> tuple[list[str], int, bool]:
    key = load_key()
    key_b = key.encode() if key else None
    strict_roots = [ROOT / "VelvetCascade", ROOT / "VelvetCascade.xcodeproj", ROOT / "manifests",
                    ROOT / "scripts" / "audio_requests.json"]
    loose = [ROOT / "scripts", ROOT / "docs", RAW_ROOT, ROOT / ".env.example", ROOT / "README.md"]
    problems: list[str] = []
    scanned = 0

    def files(p: Path):
        if p.is_file():
            yield p
        elif p.is_dir():
            for q in p.rglob("*"):
                if q.is_file():
                    yield q

    seen: set[Path] = set()
    for group, roots in (("strict", strict_roots), ("loose", loose)):
        for r in roots:
            for f in files(r):
                if f in seen:
                    continue
                seen.add(f)
                if group == "loose" and f.suffix.lower() in (".wav", ".mp3", ".m4a", ".ogg", ".pcm", ".bin", ".png"):
                    continue          # large media in scripts/docs/AudioRaw: key value check only below
                try:
                    data = f.read_bytes()
                except OSError:
                    continue
                scanned += 1
                if key_b and key_b in data:
                    problems.append(f"API key value found in {f.relative_to(ROOT)}")
                if KEY_PATTERN.search(data) and group == "strict":
                    problems.append(f"ElevenLabs-style key pattern found in {f.relative_to(ROOT)}")
                if group == "strict" and b"xi-api-key" in data.lower():
                    problems.append(f"'xi-api-key' found in app/manifest file {f.relative_to(ROOT)}")
                if group == "loose" and KEY_PATTERN.search(data):
                    problems.append(f"ElevenLabs-style key pattern found in {f.relative_to(ROOT)}")
    if RAW_ROOT.is_dir() and key_b:
        for f in RAW_ROOT.rglob("*"):
            if f.is_file() and f not in seen:
                scanned += 1
                if key_b in f.read_bytes():
                    problems.append(f"API key value found in {f.relative_to(ROOT)}")
    return problems, scanned, key is not None


def check_entry(req: dict, e: dict | None, release: bool) -> tuple[list[str], list[str], dict]:
    fails: list[str] = []
    warns: list[str] = []
    row = {"id": req["id"], "file": req["runtimeFile"], "prov": "-", "sr": "-", "ch": "-", "bits": "-",
           "dur": "-", "target": req["targetDuration"], "peak": "-", "rms": "-", "dc": "-", "loop": "-"}
    if e is None:
        return [f"missing from manifest"], warns, row
    row["prov"] = "EL" if e.get("provider") == EL else ("SUB" if e.get("provider") == SUB else "??")
    stem = Path(req["runtimeFile"]).stem
    rf = e.get("runtimeFile", "")
    if Path(rf).stem != stem or Path(rf).suffix.lower() not in (".wav", ".m4a", ".caf"):
        fails.append(f"runtime file name {rf!r} does not keep the spec stem {stem!r}")
    row["file"] = rf
    path = RUNTIME_DIR / rf
    if not path.is_file():
        fails.append(f"file missing: {path.relative_to(ROOT)}")
        return fails, warns, row
    pi = probe(path)
    if not pi:
        fails.append("ffprobe cannot decode")
        return fails, warns, row
    st = pi["stream"]
    sr, ch = int(st["sample_rate"]), int(st["channels"])
    bits = int(st.get("bits_per_sample") or 0)
    row.update(sr=sr, ch=ch, bits=bits or st["codec_name"])
    a = decode(path, ch, sr)
    if a is None or len(a) == 0:
        fails.append("ffmpeg full decode failed / empty")
        return fails, warns, row
    frames = len(a) // ch
    dur = frames / sr
    chans = [a[c::ch] if ch > 1 else a for c in range(ch)]
    peak = max(abs(max(a)), abs(min(a)))
    rms = math.sqrt(sumsq(a) / len(a))
    dcs = [sum(c) / len(c) for c in chans]
    dc = max(abs(v) for v in dcs)
    clipped = sum(1 for v in a if abs(v) >= CLIP)
    row.update(dur=round(dur, 3), peak=round(db(peak), 2), rms=round(db(rms), 2), dc=f"{dc:.1e}")

    # manifest consistency
    for k, v in (("sampleRate", sr), ("channels", ch)):
        if e.get(k) != v:
            fails.append(f"{k} {v} != manifest {e.get(k)}")
    if e.get("bitDepth") and bits and e["bitDepth"] != bits:
        fails.append(f"bitDepth {bits} != manifest {e.get('bitDepth')}")
    if e.get("frameCount") is not None and abs(e["frameCount"] - frames) > (0 if path.suffix == ".wav" else 2):
        fails.append(f"frameCount {frames} != manifest {e.get('frameCount')}")
    if e.get("editedDuration") is not None and abs(e["editedDuration"] - dur) > 0.001:
        fails.append(f"duration {dur:.4f}s != manifest editedDuration {e.get('editedDuration')}")
    if e.get("runtimeSha256") and e["runtimeSha256"] != sha256(path):
        fails.append("runtime sha256 differs from manifest (file changed after manifest was written)")
    if sr != 48000:
        warns.append(f"sample rate {sr} (spec masters/runtime use 48 kHz)")

    # signal
    if peak <= 10 ** (-60 / 20) or rms <= 10 ** (-80 / 20):
        fails.append(f"near-silent (peak {db(peak):.1f} dBFS, rms {db(rms):.1f} dBFS)")
    ceiling = -6.0 if req["kind"] == "music" else -3.0
    if db(peak) > ceiling + 0.01:
        fails.append(f"peak {db(peak):.2f} dBFS above {ceiling} dBFS")
    if clipped:
        fails.append(f"{clipped} clipped samples")
    if dc > DC_MAX:
        fails.append(f"DC offset {dc:.4f} > {DC_MAX}")
    if e.get("peakDBFS") is not None and abs(e["peakDBFS"] - db(peak)) > 0.05:
        warns.append(f"manifest peakDBFS {e['peakDBFS']} vs measured {db(peak):.2f}")
    if req["kind"] == "ambience" and db(rms) > -30:
        warns.append(f"ambience rms {db(rms):.1f} dBFS is not 'very quiet'")

    if not req["isLoop"]:
        tgt = float(req["targetDuration"])
        if abs(dur - tgt) > 0.005:
            fails.append(f"duration {dur:.3f}s != target {tgt:.3f}s")
        thr = peak * 10 ** (-30 / 20)
        mono_abs = [max(abs(c[i]) for c in chans) for i in range(min(frames, int(0.1 * sr)))]
        onset = next((i for i, v in enumerate(mono_abs) if v >= thr), None)
        if onset is None or onset > int(0.025 * sr):
            fails.append(f"attack starts late ({'none' if onset is None else f'{onset / sr * 1000:.1f} ms'})")
        w = int(0.005 * sr)
        tail = math.sqrt(sum(sumsq(c[-w:]) for c in chans) / (w * ch))
        if db(tail) > db(peak) - 30:
            fails.append(f"tail cut abruptly (last 5 ms at {db(tail) - db(peak):.1f} dB rel. peak)")
        if abs(chans[0][0]) > 0.01 or abs(chans[0][-1]) > 0.01:
            warns.append("first/last sample not near zero (fade)")
    else:
        ls, le = e.get("loopStart"), e.get("loopEnd")
        if ls is None or le is None or not (0 <= ls < le <= frames):
            fails.append(f"invalid loop points {ls}..{le} for {frames} frames")
        worst = max(seam(c) for c in chans)
        rep, exact = repeat_join_ratio(path, ch, sr, frames)
        row["loop"] = f"seam {worst:.2f} / 3x {rep:.2f}"
        if worst > SEAM_MAX or rep > SEAM_MAX:
            fails.append(f"loop seam click ratio {max(worst, rep):.2f} > {SEAM_MAX}")
        if not exact:
            fails.append("3x repeat decode is not exactly 3 x frameCount (decoder padding breaks the loop)")
        if req["kind"] == "music":
            bars, bpm, bpb = e.get("loopBars"), e.get("tempoBpm") or e.get("detectedBpm"), e.get("beatsPerBar")
            if bars and bpm and bpb:
                exp = bars * bpb * 60.0 / bpm * sr
                if abs(exp - frames) > 2:
                    fails.append(f"music loop {frames} frames is not {bars} bars at {bpm} BPM ({exp:.1f})")
            else:
                warns.append("music loop without loopBars/tempo in manifest")
        else:
            tgt = float(req["targetDuration"])
            if abs(dur - tgt) > 0.05 * tgt:
                warns.append(f"loop length {dur:.3f}s vs target {tgt:.2f}s")

    # provider bookkeeping
    prov = e.get("provider")
    if prov == SUB:
        if e.get("qaStatus") != "substitute-approved-for-debug":
            fails.append(f"substitute with qaStatus {e.get('qaStatus')!r}")
        if e.get("requestID"):
            fails.append("substitute must not carry a provider requestID")
    elif prov == EL:
        src = e.get("sourceFile")
        if not src or not (ROOT / src).is_file():
            fails.append("ElevenLabs entry without raw source file")
        elif "sha256:" + sha256(ROOT / src) != e.get("sourceHash"):
            fails.append("raw source sha256 != sourceHash")
        if not e.get("requestID"):
            warns.append("ElevenLabs entry without provider request id")
        if e.get("qaStatus") not in ("approved", "auto-qa-pass-pending-listening"):
            fails.append(f"ElevenLabs entry qaStatus {e.get('qaStatus')!r}")
    else:
        fails.append(f"unknown provider {prov!r}")
    if release and not (prov == EL and e.get("qaStatus") == "approved"):
        fails.append("release gate: not an approved ElevenLabs file")
    if req["id"] == "S38" and e.get("pitchVariantsSemitones") != [0, 2, 4]:
        fails.append("S38 must declare pitchVariantsSemitones [0, 2, 4]")
    return fails, warns, row


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Velvet Cascade audio QA")
    ap.add_argument("--release", action="store_true", help="enforce the release gate (44 approved ElevenLabs files)")
    ap.add_argument("--json", help="also write the report as JSON to this path")
    opts = ap.parse_args(argv)
    with open(REQUESTS_PATH, encoding="utf-8") as f:
        reqs = json.load(f)["entries"]
    if not MANIFEST_PATH.is_file():
        print(f"FAIL: manifest missing ({MANIFEST_PATH.relative_to(ROOT)})")
        return 1
    with open(MANIFEST_PATH, encoding="utf-8") as f:
        man = json.load(f)
    entries = man.get("entries", [])
    by_id: dict[str, dict] = {}
    global_fails: list[str] = []
    for e in entries:
        if e.get("id") in by_id:
            global_fails.append(f"duplicate manifest id {e.get('id')}")
        by_id[e.get("id")] = e
    expected = [r["id"] for r in reqs]
    extra = sorted(set(by_id) - set(expected))
    if extra:
        global_fails.append(f"unexpected manifest ids {extra}")
    if len(expected) != 44:
        global_fails.append(f"requests list has {len(expected)} ids, expected 44")

    hdr = (f"{'ID':<4} {'runtime file':<27} {'prov':<4} {'sr':>5} {'ch':>2} {'bits':>4} {'dur s':>7} {'target':>6} "
           f"{'peak':>7} {'rms':>7} {'|dc|':>7}  {'loop seam':<17} result")
    print(hdr)
    print("-" * len(hdr))
    n_fail = 0
    report = []
    for req in reqs:
        fails, warns, row = check_entry(req, by_id.get(req["id"]), opts.release)
        res = "PASS" if not fails else "FAIL"
        if fails:
            n_fail += 1
        tgt = f"{row['target']:.2f}" + ("L" if req["isLoop"] else "")
        print(f"{row['id']:<4} {row['file']:<27} {row['prov']:<4} {row['sr']:>5} {row['ch']:>2} {str(row['bits']):>4} "
              f"{str(row['dur']):>7} {tgt:>6} {str(row['peak']):>7} {str(row['rms']):>7} {str(row['dc']):>7}  "
              f"{row['loop']:<17} {res}")
        for m in fails:
            print(f"       FAIL: {m}")
        for m in warns:
            print(f"       warn: {m}")
        report.append({"id": req["id"], "result": res, "fails": fails, "warnings": warns, **{k: row[k] for k in row}})

    problems, scanned, key_known = secret_scan()
    print("-" * len(hdr))
    print(f"Secret scan: {scanned} files checked ({'API key value from env/.env included' if key_known else 'no API key available locally; pattern + header-name checks only'}). "
          + ("OK - no key / key pattern / 'xi-api-key' in app, resources or manifests." if not problems else ""))
    for p in problems:
        print(f"  FAIL: {p}")
    for g in global_fails:
        print(f"  FAIL: {g}")
    n_el = sum(1 for e in entries if e.get("provider") == EL)
    n_sub = sum(1 for e in entries if e.get("provider") == SUB)
    n_app = sum(1 for e in entries if e.get("provider") == EL and e.get("qaStatus") == "approved")
    print(f"Files: {len(expected) - n_fail}/{len(expected)} pass technical QA. Providers: {n_el} ElevenLabs, "
          f"{n_sub} procedural substitutes. Approved ElevenLabs (release): {n_app}/44.")
    print("Listening QA (3+ loop repeats, small iPhone speaker, headphones, turn+bomb+key mix) is NOT automated "
          "and has not been performed by a human.")
    ok = n_fail == 0 and not problems and not global_fails
    gate = "release gate" if opts.release else "debug/technical gate"
    print(f"RESULT: {'PASS' if ok else 'FAIL'} ({gate})"
          + ("" if opts.release else f"; release gate would {'pass' if n_app == 44 else 'FAIL'} ({44 - n_app} IDs not approved ElevenLabs)"))
    if opts.json:
        with open(opts.json, "w", encoding="utf-8") as f:
            json.dump({"result": "PASS" if ok else "FAIL", "entries": report, "secretProblems": problems,
                       "globalFailures": global_fails}, f, indent=2)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
