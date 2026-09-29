#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Velvet Cascade - procedural SUBSTITUTE audio (NOT ElevenLabs).

Synthesizes all 44 runtime files (exact runtime filenames from scripts/audio_requests.json) so
debug builds are not silent while the real ElevenLabs production is pending. Every manifest
entry written by this script is labelled provider "procedural-substitute (NOT ElevenLabs)" and
qaStatus "substitute-approved-for-debug". Release readiness still requires the 44 ElevenLabs files.

Techniques: additive / FM synthesis with natural exponential decays (celesta, bells, marimba,
pizzicato, clarinet-like and horn-like tones), damped modal models (wood, brass clicks),
filtered and spectrally moving noise (velvet swishes, air), synthetic room impulse responses.
Loops (S37, A01, A02, M01-M03) are built in the circular domain: every note/tail that runs past
the loop end is wrapped onto the head and reverb is a circular convolution, so the seam is
sample-exact. Music loops are exact bar multiples at 96 BPM (48 kHz: one beat = 30000 frames).

Requires numpy (pip3 install numpy). Deterministic: fixed seeds per ID.
Runtime IDs that already carry a real ElevenLabs file (manifest provider "ElevenLabs" and a
matching runtime hash) are never overwritten.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import itertools
import json
import sys
import wave
from pathlib import Path

import numpy as np

sys.dont_write_bytecode = True          # keep scripts/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_audio as ga  # noqa: E402  (shared manifest/analysis helpers, stdlib only)

SR = 48000
TAU = 2 * np.pi
LN1000 = 6.907755278982137          # ln(1000): amplitude reaches -60 dB at t60
GENERATOR = "synth_substitute_audio.py v1 (numpy additive/FM/modal synthesis + filtered noise)"

SFX_PEAK_DB = {"low": -11.0, "medium": -8.0, "high": -6.0, "highest": -4.5}
MUSIC_PEAK_DB = -7.0
AMBIENCE_PEAK_DB = -24.0


# ============================================================================ basics

def ns(d: float) -> int:
    return int(round(d * SR))


def tv(n: int) -> np.ndarray:
    return np.arange(n) / SR


def mtof(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


NOTE_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def N(name: str) -> int:
    """'C#5' / 'Bb4' / 'D6' -> MIDI."""
    pc = NOTE_PC[name[0]]
    i = 1
    while i < len(name) and name[i] in "#b":
        pc += 1 if name[i] == "#" else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + pc


def decay(t: np.ndarray, t60: float) -> np.ndarray:
    return np.exp(-LN1000 * t / max(t60, 1e-4))


def ramp(n: int, att_s: float) -> np.ndarray:
    a = max(1, ns(att_s))
    r = np.ones(n)
    k = min(a, n)
    r[:k] = 0.5 - 0.5 * np.cos(np.pi * (np.arange(k) + 0.5) / a)
    return r


def place(buf: np.ndarray, sig: np.ndarray, t0: float, gain: float = 1.0) -> None:
    i = ns(t0)
    if i < 0:
        sig = sig[-i:]
        i = 0
    if i >= len(buf) or len(sig) == 0:
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += gain * sig[: j - i]


def freqs(n: int) -> np.ndarray:
    return np.fft.rfftfreq(n, 1 / SR)


def lp_g(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp_g(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def fft_filter(x: np.ndarray, gain_fn, pad: bool = True) -> np.ndarray:
    n = len(x)
    m = 2 * n if pad else n
    X = np.fft.rfft(x, m)
    y = np.fft.irfft(X * gain_fn(freqs(m)), m)
    return y[:n]


def lowpass(x, fc, order=2, pad=True):
    return fft_filter(x, lambda f: lp_g(f, fc, order), pad)


def highpass(x, fc, order=2, pad=True):
    return fft_filter(x, lambda f: hp_g(f, fc, order), pad)


def bandpass(x, lo, hi, order=2, pad=True):
    return fft_filter(x, lambda f: hp_g(f, lo, order) * lp_g(f, hi, order), pad)


def band_noise(n, lo, hi, rng, order=2):
    return bandpass(rng.standard_normal(n), lo, hi, order)


def moving_band(n: int, center_fn, width_oct: float, rng, tilt: float = 0.0) -> np.ndarray:
    """Noise through a spectrally moving band (sqrt-Hann STFT overlap-add, 50 %)."""
    F, H = 1024, 512
    win = np.sqrt(0.5 - 0.5 * np.cos(TAU * np.arange(F) / F))
    x = rng.standard_normal(n + 2 * F)
    y = np.zeros(n + 2 * F)
    f = freqs(F)
    lf = np.log2(np.maximum(f, 1.0))
    for i in range(0, n + F, H):
        c = max(40.0, float(center_fn((i + F / 2) / SR)))
        g = np.exp(-0.5 * ((lf - np.log2(c)) / (width_oct / 2.355)) ** 2)
        if tilt:
            g *= (np.maximum(f, 20.0) / c) ** (-tilt)
        seg = np.fft.irfft(np.fft.rfft(x[i:i + F] * win) * g, F) * win
        y[i:i + F] += seg
    y = y[F // 2: F // 2 + n]
    return y / (np.sqrt(np.mean(y ** 2)) + 1e-12)


def rms(x):
    return float(np.sqrt(np.mean(np.square(x)) + 1e-30))


# ============================================================================ instruments

def partial_sum(n, f, ratios, amps, t60s, rng=None, att=0.001, inharm=0.0):
    t = tv(n)
    y = np.zeros(n)
    for k, (r, a, d) in enumerate(zip(ratios, amps, t60s)):
        fr = f * r * np.sqrt(1 + inharm * (k + 1) ** 2)
        if fr >= 0.45 * SR or a == 0:
            continue
        ph = rng.uniform(0, TAU) if rng is not None else 0.0
        y += a * np.sin(TAU * fr * t + ph) * decay(t, d)
    return y * ramp(n, att)


def celesta(f, vel=1.0, dur=None, bright=1.0, rng=None):
    t60 = 2.1 * (523.0 / f) ** 0.35
    n = ns(dur if dur else min(3.5, t60 * 1.1))
    y = partial_sum(n, f, [1, 2, 4.0, 7.1], [1.0, 0.1, 0.28 * bright * vel, 0.05 * bright * vel],
                    [t60, t60 * 0.45, 0.12, 0.045], rng, att=0.0015)
    if rng is not None:
        tick = band_noise(ns(0.004), 2500, 9000, rng) * ramp(ns(0.004), 0.0005) * decay(tv(ns(0.004)), 0.003)
        y[:len(tick)] += 0.03 * vel * tick / (np.max(np.abs(tick)) + 1e-9)
    return vel * y


def glock(f, vel=1.0, scale=1.0, rng=None):
    n = ns(min(2.5, 1.3 * scale))
    return vel * partial_sum(n, f, [1, 2.76, 5.40, 8.93], [1, 0.3, 0.12, 0.05],
                             [1.1 * scale, 0.4 * scale, 0.14 * scale, 0.06 * scale], rng, att=0.0008)


def crystal(f, vel=1.0, scale=1.0, rng=None):
    n = ns(0.6 * scale + 0.05)
    return vel * partial_sum(n, f, [1, 2.32, 4.25, 6.63], [1, 0.42, 0.18, 0.07],
                             [0.38 * scale, 0.18 * scale, 0.08 * scale, 0.045 * scale], rng, att=0.0006)


def bell(f, vel=1.0, scale=1.0, bright=1.0, rng=None):
    n = ns(min(4.0, 2.6 * scale))
    return vel * partial_sum(n, f, [0.5, 1.0, 1.0016, 2.0, 3.0, 4.2, 5.4],
                             [0.18, 1.0, 0.5, 0.38, 0.16 * bright, 0.07 * bright, 0.035 * bright],
                             [x * scale for x in (3.0, 2.4, 2.4, 1.3, 0.8, 0.4, 0.25)], rng, att=0.001)


def fm_shimmer(f, dur, ratio=1.41, index=2.2, tau=0.12, t60=0.5, vel=1.0):
    n = ns(dur)
    t = tv(n)
    I = index * np.exp(-t / tau)
    y = np.sin(TAU * f * t + I * np.sin(TAU * f * ratio * t)) * decay(t, t60)
    return vel * y * ramp(n, 0.002)


def marimba(f, vel=1.0, soft=0.6, dry=1.0, rng=None):
    t60 = (0.25 + 0.6 * (262.0 / f) ** 0.7) * dry
    n = ns(min(2.5, t60 * 1.05 + 0.02))
    y = partial_sum(n, f, [1, 3.93, 9.24], [1.0, 0.2 * vel * (1 - 0.5 * soft), 0.05 * vel * (1 - 0.6 * soft)],
                    [t60, 0.11, 0.035], rng, att=0.0012)
    if rng is not None:
        m = ns(0.004)
        th = lowpass(rng.standard_normal(m), 1500) * decay(tv(m), 0.003)
        y[:m] += 0.05 * vel * th / (np.max(np.abs(th)) + 1e-9)
    return vel * y


def pizz(f, vel=1.0, rng=None):
    t60 = 0.32 + 0.85 * (98.0 / f) ** 0.6
    n = ns(min(2.2, t60 * 1.05))
    t = tv(n)
    y = np.zeros(n)
    glide = 0.004 * 0.03 * (1 - np.exp(-t / 0.03))
    for k in range(1, 15):
        fk = k * f * np.sqrt(1 + 0.00025 * k * k)
        if fk > 0.42 * SR:
            break
        a = abs(np.sin(k * np.pi * 0.18)) / k ** 1.15
        if k > 3:
            a *= vel ** 0.5
        y += a * np.sin(TAU * fk * (t + glide)) * decay(t, t60 / (1 + 0.4 * (k - 1)))
    y *= ramp(n, 0.0012)
    if rng is not None:
        m = ns(0.005)
        th = lowpass(rng.standard_normal(m), 1800) * decay(tv(m), 0.004)
        y[:m] += 0.06 * th / (np.max(np.abs(th)) + 1e-9)
    y = lowpass(y, 3200 if f < 300 else 4200)
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def reed(f, dur, vel=1.0, dark=0.6, even=0.05, rng=None, att=0.07, rel=0.16, vib=0.0025):
    """Clarinet-like (odd harmonics dominant); with even>0.2 it leans towards a soft bassoon."""
    n = ns(dur + rel)
    t = tv(n)
    vib_env = np.clip((t - 0.25) / 0.3, 0, 1)
    inst = f * (1 + vib * vib_env * np.sin(TAU * 4.8 * t))
    ph = TAU * np.cumsum(inst) / SR
    amps = {1: 1.0, 2: even, 3: 0.42, 4: even * 0.7, 5: 0.2, 6: even * 0.5, 7: 0.1, 8: even * 0.3, 9: 0.05, 11: 0.025}
    y = np.zeros(n)
    for k, a in amps.items():
        if k * f > 0.4 * SR:
            continue
        y += a * np.exp(-(k - 1) * dark * 0.22) * np.sin(k * ph)
    env = ramp(n, att)
    env *= 1 + 0.08 * np.sin(np.pi * np.clip(t / max(dur, 1e-3), 0, 1))
    r0 = ns(dur)
    if r0 < n:
        env[r0:] *= np.cos(0.5 * np.pi * np.linspace(0, 1, n - r0))
    y *= env
    if rng is not None:
        br = band_noise(n, 900, 3200, rng) * env
        y += 0.012 * br / (np.max(np.abs(br)) + 1e-9)
    y = lowpass(y, 2400 + 1400 * (1 - dark))
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def horn(f, dur, vel=1.0, rng=None, att=0.12, rel=0.3):
    n = ns(dur + rel)
    t = tv(n)
    bloom = np.clip(t / 0.15, 0, 1) * (1 - 0.3 * np.clip((t - 0.15) / 0.4, 0, 1))
    B = 1.1 + 1.8 * vel * bloom
    inst = f * (1 + 0.001 * np.sin(TAU * 5.0 * t))
    ph = TAU * np.cumsum(inst) / SR
    y = np.zeros(n)
    for k in range(1, 17):
        if k * f > 0.4 * SR:
            break
        y += np.exp(-(k - 1) / B) * np.sin(k * ph)
    env = ramp(n, att)
    r0 = ns(dur)
    if r0 < n:
        env[r0:] *= np.cos(0.5 * np.pi * np.linspace(0, 1, n - r0))
    y = lowpass(y * env, 2600)
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def harp(f, vel=1.0, rng=None):
    t60 = 1.2 + 1.8 * (196.0 / f) ** 0.5
    n = ns(min(4.0, t60))
    t = tv(n)
    y = np.zeros(n)
    for k in range(1, 13):
        fk = k * f
        if fk > 0.42 * SR:
            break
        a = abs(np.sin(k * np.pi * 0.12)) / k ** 1.4
        y += a * np.sin(TAU * fk * t) * decay(t, t60 / (1 + 0.55 * (k - 1)))
    y *= ramp(n, 0.001)
    return vel * lowpass(y, 5000) / (np.max(np.abs(y)) + 1e-9)


def modal(f0, ratios, amps, t60s, vel=1.0, rng=None, click=0.25, click_band=(1500, 6000), dur=None):
    d = dur if dur else max(t60s) * 1.05 + 0.005
    n = ns(d)
    y = partial_sum(n, f0, ratios, amps, t60s, rng, att=0.0004)
    y /= np.max(np.abs(y)) + 1e-9
    if rng is not None and click > 0:
        m = ns(0.0015)
        c = band_noise(m, click_band[0], click_band[1], rng) * decay(tv(m), 0.001)
        y[:m] += click * c / (np.max(np.abs(c)) + 1e-9)
    return vel * y


def wood(f0, t60=0.04, vel=1.0, rng=None, click=0.25):
    return modal(f0, [1, 1.58, 2.37, 3.1], [1, 0.55, 0.3, 0.15], [t60, t60 * 0.7, t60 * 0.5, t60 * 0.35],
                 vel, rng, click, (1200, 5000))


def brass_tick(f0=3200, t60=0.03, vel=1.0, rng=None, click=0.3):
    return modal(f0, [1, 1.47, 2.09, 2.83, 3.61], [1, 0.7, 0.5, 0.3, 0.2],
                 [t60 * r for r in (1, 0.8, 0.6, 0.45, 0.3)], vel, rng, click, (3000, 12000))


def latch(f0=420, t60=0.06, vel=1.0, rng=None):
    y = modal(f0, [1, 2.29, 3.71, 5.2, 7.35], [1, 0.6, 0.45, 0.3, 0.15],
              [t60 * r for r in (1, 0.7, 0.5, 0.35, 0.25)], 1.0, rng, 0.35, (1500, 7000))
    th = thump(f0 * 0.35, f0 * 0.25, 0.08)
    m = min(len(y), len(th))
    y[:m] += 0.4 * th[:m]
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def thump(f_start, f_end, dur, t60=None):
    n = ns(dur)
    t = tv(n)
    fr = f_end + (f_start - f_end) * np.exp(-t / (dur * 0.25))
    ph = TAU * np.cumsum(fr) / SR
    return np.sin(ph) * decay(t, t60 or dur * 0.8) * ramp(n, 0.002)


def sparkle(n_ev, t0, t1, f_lo, f_hi, rng, vel=1.0, fall=1.5, scale=0.5):
    dur = t1 + 0.5
    buf = np.zeros(ns(dur))
    ts = np.sort(rng.uniform(t0, t1, n_ev))
    for tt in ts:
        f = float(np.exp(rng.uniform(np.log(f_lo), np.log(f_hi))))
        a = vel * rng.uniform(0.5, 1.0) * np.exp(-fall * (tt - t0) / max(t1 - t0, 1e-3))
        place(buf, crystal(f, a, scale, rng), tt)
    return buf


# ============================================================================ space

def make_ir(rt, rng, stereo=False, predelay=0.012, bright=0.5, length=None):
    n = ns(length if length else min(rt * 1.4, 4.0))
    t = tv(n)
    out = []
    for _ in range(2 if stereo else 1):
        w = rng.standard_normal(n)
        W = np.fft.rfft(w)
        f = freqs(n)
        low = np.fft.irfft(W * lp_g(f, 700), n)
        mid = np.fft.irfft(W * hp_g(f, 700) * lp_g(f, 4000), n)
        high = np.fft.irfft(W * hp_g(f, 4000), n)
        ir = low * decay(t, rt * 1.15) + mid * decay(t, rt) + high * decay(t, rt * (0.3 + 0.4 * bright))
        pd = ns(predelay)
        ir[:pd] = 0
        ir[pd:] *= ramp(n - pd, 0.006)
        e = np.sqrt(np.sum(ir ** 2))
        for _k in range(7):
            p = pd + ns(rng.uniform(0.002, 0.045))
            if p < n:
                ir[p] += rng.uniform(-1, 1) * 0.06 * e
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
        out.append(ir)
    return out


def room(x, rt=0.35, wet=0.1, rng=None, bright=0.5):
    ir = make_ir(rt, rng, False, 0.006, bright)[0]
    n = len(x) + len(ir) - 1
    m = 1 << (n - 1).bit_length()
    w = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:n]
    y = np.zeros(n)
    y[:len(x)] += x
    return y + wet * w


def circ_conv(x, ir, L):
    return np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(ir[:L], L), L)


def fold(buf, L):
    """Wrap everything past the loop end onto the head (circular)."""
    outb = buf[..., :L].copy()
    rest = buf[..., L:]
    k = 0
    while rest.shape[-1] > 0:
        m = min(L, rest.shape[-1])
        outb[..., :m] += rest[..., :m]
        rest = rest[..., m:]
        k += 1
    return outb


def periodic_noise(L, gain_fn, rng):
    f = freqs(L)
    X = (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))) * gain_fn(f)
    X[0] = 0
    y = np.fft.irfft(X, L)
    return y / (rms(y) + 1e-12)


def circ_filter(x, gain_fn):
    L = x.shape[-1]
    return np.fft.irfft(np.fft.rfft(x, L, axis=-1) * gain_fn(freqs(L)), L, axis=-1)


# ============================================================================ finishing

def finish_oneshot(x, target, peak_db):
    n = ns(target)
    pre = ns(0.001)
    y = np.zeros(n)
    m = min(n - pre, len(x))
    y[pre:pre + m] = x[:m]
    y = highpass(y, 20, 2)
    y -= np.mean(y)
    pk = np.max(np.abs(y)) + 1e-12
    w = ns(0.02)
    tail_rel = 20 * np.log10(rms(y[-w:]) / pk + 1e-12)
    if tail_rel > -45:
        d = min(int(0.4 * n), ns(0.15))
        u = np.arange(1, d + 1) / d
        y[-d:] *= np.exp(np.log(10 ** (-45 / 20)) * u * u)
    fi = max(1, min(ns(0.002), n // 10))
    y[:fi] *= 0.5 - 0.5 * np.cos(np.pi * (np.arange(fi) + 0.5) / fi)
    fo = max(ns(0.002), min(ns(0.008), n // 10))
    y[-fo:] *= (0.5 - 0.5 * np.cos(np.pi * (np.arange(fo) + 0.5) / fo))[::-1]
    return y * (10 ** (peak_db / 20) / (np.max(np.abs(y)) + 1e-12))


def finish_loop(x, peak_db, hp=20.0):
    """x: (C, L) periodic. Circular DC removal / high-pass keeps the seam exact."""
    x = np.atleast_2d(x)
    x = circ_filter(x, lambda f: hp_g(f, hp, 2))
    x = x - x.mean(axis=-1, keepdims=True)
    return x * (10 ** (peak_db / 20) / (np.max(np.abs(x)) + 1e-12))


def write_pcm16(path: Path, x: np.ndarray, seed: int) -> None:
    x = np.atleast_2d(x)
    rng = np.random.default_rng(seed)
    q = x * 32767.0 + (rng.random(x.shape) - rng.random(x.shape))     # TPDF dither, 1 LSB
    q = np.clip(np.round(q), -32767, 32767).astype("<i2")
    inter = q.T.reshape(-1)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(x.shape[0])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(inter.tobytes())
    tmp.replace(path)


# ============================================================================ SFX designs
# Every function returns (mono signal at natural length, short recipe text).

def s01(r):
    b = np.zeros(ns(0.2))
    place(b, wood(1250, 0.035, 1.0, r), 0)
    place(b, brass_tick(4300, 0.02, 0.28, r, 0.2), 0.002)
    return room(lowpass(b, 7500), 0.25, 0.07, r), "polished wood click (modal 1.25 kHz) + faint brass tick 4.3 kHz"


def s02(r):
    b = np.zeros(ns(0.4))
    place(b, marimba(mtof(N("A5")), 0.9, 0.7, 0.35, r), 0)
    place(b, marimba(mtof(N("E5")), 0.75, 0.7, 0.35, r), 0.075)
    return room(b, 0.25, 0.05, r), "two dry marimba taps A5 -> E5 (descending)"


def s03(r):
    b = np.zeros(ns(0.3))
    place(b, brass_tick(2600, 0.018, 1.0, r, 0.4), 0)
    place(b, wood(1800, 0.012, 0.6, r), 0.001)
    sh = bell(mtof(N("A6")), 0.28, 0.08, 0.5, r)
    fs = 0.12 * fm_shimmer(mtof(N("A6")), 0.2, 1.41, 1.0, 0.05, 0.12)
    m = min(len(sh), len(fs))
    sh[:m] += fs[:m]
    place(b, lowpass(sh, 6000), 0.02)
    return room(b, 0.2, 0.05, r), "toggle snap (brass modal 2.6 kHz) + short muted bell A6"


def s04(r):
    b = np.zeros(ns(0.5))
    place(b, wood(320, 0.07, 1.0, r, 0.15), 0)
    place(b, wood(290, 0.07, 0.9, r, 0.15), 0.11)
    ch = celesta(mtof(N("F#5")), 0.22, 0.35, 0.3, r) + celesta(mtof(N("G5")), 0.2, 0.35, 0.3, r)
    place(b, lowpass(ch, 3000), 0.11)
    return room(b, 0.3, 0.07, r), "two low wooden knocks 320/290 Hz + muted F#5/G5 minor-second chime"


def s05(r):
    n = ns(0.9)
    t = tv(n)
    sw = moving_band(n, lambda s: 350 * (1400 / 350) ** min(1.0, s / 0.6), 1.3, r, 0.3)
    env = np.clip(t / 0.06, 0, 1) ** 1.5 * np.exp(-np.clip(t - 0.35, 0, None) / 0.18)
    y = 0.6 * sw * env
    rum = lowpass(r.standard_normal(n), 150) * env
    y += 0.25 * rum / (np.max(np.abs(rum)) + 1e-9)
    tt = 0.05
    while tt < 0.55:
        place(y, brass_tick(r.uniform(2700, 3400), 0.012, 0.09, r, 0.1), tt)
        tt += r.uniform(0.03, 0.06)
    return room(lowpass(y, 6000), 0.4, 0.1, r), "velvet swish (moving band 350->1400 Hz) + soft rail ticks + low rumble"


def s06(r):
    n = ns(0.8)
    t = tv(n)
    sw = moving_band(n, lambda s: 1300 * (450 / 1300) ** min(1.0, s / 0.5), 1.3, r, 0.3)
    env = np.clip(t / 0.08, 0, 1) ** 1.2 * np.exp(-np.clip(t - 0.3, 0, None) / 0.12)
    y = 0.6 * sw * env
    place(y, wood(380, 0.05, 0.55, r, 0.2), 0.5)
    return room(lowpass(y, 6000), 0.4, 0.09, r), "closing velvet swish (1300->450 Hz) + quiet wooden stop"


def s07(r):
    n = ns(0.35)
    t = tv(n)
    sl = moving_band(n, lambda s: 2500 * (4000 / 2500) ** min(1.0, s / 0.12), 0.9, r)
    env = np.clip(t / 0.02, 0, 1) * np.exp(-np.clip(t - 0.08, 0, None) / 0.03)
    y = 0.25 * sl * env
    place(y, crystal(mtof(N("D7")), 0.9, 0.4, r), 0.115)
    return room(y, 0.25, 0.07, r), "short jewel slide (band noise 2.5->4 kHz) + crystal click D7"


def s08(r):
    n = ns(0.4)
    t = tv(n)
    f1 = moving_band(n, lambda s: 2200 * (3500 / 2200) ** min(1.0, s / 0.07), 0.9, r)
    f2 = moving_band(n, lambda s: 3500 * (2000 / 3500) ** min(1.0, max(0.0, s - 0.09) / 0.07), 0.9, r)
    e1 = np.clip(t / 0.015, 0, 1) * np.exp(-np.clip(t - 0.05, 0, None) / 0.02)
    e2 = np.clip((t - 0.09) / 0.015, 0, 1) * np.exp(-np.clip(t - 0.14, 0, None) / 0.02)
    y = 0.2 * (f1 * e1 + f2 * e2)
    place(y, brass_tick(3600, 0.015, 0.45, r, 0.2), 0.07)
    place(y, brass_tick(3300, 0.015, 0.4, r, 0.2), 0.16)
    m = ns(0.2)
    tt = tv(m)
    fr = 880 * (740 / 880) ** np.clip(tt / 0.12, 0, 1)
    tone = np.sin(TAU * np.cumsum(fr) / SR) * decay(tt, 0.2) * ramp(m, 0.01)
    place(y, 0.35 * tone, 0.1)
    return room(y, 0.25, 0.06, r), "slide forward/back + two soft ticks + gentle 880->740 Hz downward glide"


def s09(r):
    b = np.zeros(ns(0.6))
    for i, nm in enumerate(("D6", "F6", "A6")):
        place(b, crystal(mtof(N(nm)), 0.55, 0.35, r), 0.025 * i)
    place(b, glock(mtof(N("D7")), 0.8, 0.5, r), 0.07)
    place(b, sparkle(6, 0.07, 0.22, 4500, 8000, r, 0.15, 2.0, 0.3), 0)
    return room(b, 0.35, 0.1, r), "three crystal pops D6/F6/A6 + glock chime D7 + tiny sparkle"


def s10(r):
    b = np.zeros(ns(0.7))
    for i, nm in enumerate(("A6", "D7")):
        tt = 0.12 * i
        place(b, crystal(mtof(N(nm)), 0.8, 0.55, r), tt)
        place(b, 0.3 * fm_shimmer(mtof(N(nm)) / 2, 0.4, 1.0, 1.6, 0.06, 0.3), tt)
    return room(b, 0.4, 0.1, r), "ascending A6 -> D7 crystal notes with warm FM brass shimmer an octave below"


def s11(r):
    b = np.zeros(ns(0.8))
    for i, nm in enumerate(("F6", "A6", "D7")):
        place(b, celesta(mtof(N(nm)), 0.75, 0.6, 1.2, r), 0.085 * i)
    place(b, 0.12 * fm_shimmer(mtof(N("D6")), 0.5, 1.41, 1.5, 0.1, 0.35), 0.17)
    return room(b, 0.45, 0.11, r), "three-note celesta F6 A6 D7 + soft metallic FM detail"


def s12(r):
    b = np.zeros(ns(0.9))
    for i, (nm, tt, v) in enumerate((("C6", 0, 0.7), ("E6", 0.07, 0.72), ("G6", 0.14, 0.75), ("F6", 0.24, 0.8))):
        place(b, crystal(mtof(N(nm)), v, 0.8 if i == 3 else 0.5, r), tt)
        place(b, celesta(mtof(N(nm)), 0.35 * v, 0.6, 0.8, r), tt)
    place(b, sparkle(7, 0.25, 0.5, 4000, 7500, r, 0.12, 1.5, 0.35), 0)
    return room(b, 0.5, 0.12, r), "four-note crystal flourish C6 E6 G6 -> F6 (gentle V-I resolution) + light sparkle"


def s13(r):
    b = np.zeros(ns(0.15))
    place(b, wood(900, 0.02, 1.0, r, 0.15), 0)
    place(b, crystal(3100, 0.18, 0.06, r), 0.001)
    return lowpass(b, 6000), "tiny rounded glass-on-wood contact (wood 900 Hz + faint glass), almost no ring"


def s14(r):
    n = ns(0.7)
    t = tv(n)
    b = np.zeros(n)
    sw = moving_band(n, lambda s: 800 * (3500 / 800) ** min(1.0, s / 0.3), 1.0, r)
    b += 0.12 * sw * np.clip(t / 0.15, 0, 1) * np.exp(-np.clip(t - 0.28, 0, None) / 0.03)
    notes = ["D6", "E6", "F6", "G6", "A6", "Bb6", "C7", "D7"]
    for i, nm in enumerate(notes):
        place(b, 0.3 * fm_shimmer(mtof(N(nm)), 0.25, 1.0, 1.2, 0.05, 0.15, 0.4 + 0.07 * i), 0.03 * i)
    place(b, crystal(mtof(N("A6")), 0.7, 0.8, r) + crystal(mtof(N("D7")), 0.5, 0.8, r), 0.3)
    return room(b, 0.45, 0.12, r), "rising brass-FM shimmer D6..D7 + airy swell + clear A6/D7 ping"


def s15(r):
    n = ns(0.6)
    t = tv(n)
    zip_ = moving_band(n, lambda s: 1500 * (7000 / 1500) ** min(1.0, s / 0.18), 0.6, r)
    env = np.clip(t / 0.02, 0, 1) * np.exp(-np.clip(t - 0.15, 0, None) / 0.05)
    y = 0.35 * zip_ * env
    fr = 1200 * (4800 / 1200) ** np.clip(t / 0.18, 0, 1)
    y += 0.06 * np.sin(TAU * np.cumsum(fr) / SR) * env
    y += sparkle(10, 0.12, 0.38, 4000, 8500, r, 0.25, 2.5, 0.3)[:n]
    return room(y, 0.45, 0.12, r, 0.7), "airy zip (narrow band 1.5->7 kHz + faint chirp) + crystal trail"


def s16(r):
    b = np.zeros(ns(0.8))
    pop = band_noise(ns(0.012), 800, 4000, r) * decay(tv(ns(0.012)), 0.008)
    place(b, 0.8 * pop / (np.max(np.abs(pop)) + 1e-9), 0)
    place(b, 0.9 * thump(110, 45, 0.25), 0)
    place(b, 0.3 * fm_shimmer(mtof(N("D6")), 0.5, 1.41, 2.0, 0.08, 0.35), 0.01)
    place(b, 0.22 * fm_shimmer(mtof(N("A6")), 0.5, 1.41, 2.0, 0.08, 0.3), 0.03)
    for k in range(28):
        tt = r.uniform(0.02, 0.4)
        place(b, brass_tick(r.uniform(4000, 8000), 0.008, 0.12 * np.exp(-3 * tt), r, 0.5), tt)
    return room(b, 0.5, 0.12, r), "soft confetti pop (noise + 110->45 Hz bass) + warm metallic FM sparkle + crinkles"


def s17(r):
    n = ns(1.2)
    t = tv(n)
    b = np.zeros(n)
    pent = ["D6", "E6", "F#6", "A6", "B6", "D7", "E7", "F#7", "A7"]
    for i in range(14):
        tt = max(0.0, 0.5 * (i / 13) ** 1.3 + r.uniform(-0.01, 0.01))
        nm = pent[min(len(pent) - 1, int(i * len(pent) / 14))]
        f = mtof(N(nm)) * (1 + r.uniform(-0.002, 0.002))
        place(b, bell(f, 0.35 * (0.6 + 0.4 * np.sin(np.pi * i / 13)), 0.18, 0.6, r), tt)
    pad = moving_band(n, lambda s: 2500 + 3000 * min(1.0, s / 0.5), 1.2, r)
    b += 0.05 * pad * np.clip(t / 0.2, 0, 1) * np.exp(-np.clip(t - 0.45, 0, None) / 0.12)
    return room(b, 0.6, 0.15, r, 0.7), "expanding shimmer of 14 tiny bells (D major pentatonic, rising) + soft air swell"


def s18(r):
    b = np.zeros(ns(0.2))
    place(b, brass_tick(2300, 0.03, 0.9, r, 0.3), 0)
    place(b, 0.3 * celesta(mtof(N("G6")), 1.0, 0.12, 0.5, r), 0.002)
    return room(b, 0.2, 0.05, r), "brass bead click 2.3 kHz + understated pitched tick G6"


def s19(r):
    b = np.zeros(ns(1.0))
    for i, nm in enumerate(("D5", "A5", "D6")):
        place(b, bell(mtof(N(nm)), 0.55, 0.35, 0.7, r), 0.11 * i)
    for k in range(9):
        tt = 0.03 + 0.3 * (1 - (1 - k / 8) ** 1.6)
        place(b, brass_tick(3000 + 150 * k, 0.012, 0.12, r, 0.2), tt)
    for i, nm in enumerate(("A6", "D7", "F7")):
        place(b, crystal(mtof(N(nm)), 0.35, 0.4, r), 0.33 + 0.045 * i)
    return room(b, 0.5, 0.13, r), "three warm bells D5 A5 D6 + accelerating mechanical ticks + rising A6 D7 F7 chime"


def s20(r):
    n = ns(0.6)
    t = tv(n)
    b = np.zeros(n)
    place(b, latch(380, 0.07, 1.0, r), 0)
    place(b, wood(700, 0.03, 0.5, r), 0.01)
    wh = moving_band(n, lambda s: 300 * (1200 / 300) ** min(1.0, s / 0.4), 1.2, r, 0.4)
    env = np.clip((t - 0.03) / 0.25, 0, 1) ** 2 * np.exp(-np.clip(t - 0.3, 0, None) / 0.06)
    b += 0.3 * wh * env
    return room(b, 0.4, 0.1, r), "brass latch release (modal 380 Hz) + wood click + restrained rising whoosh"


def s21(r):
    n = ns(1.0)
    t = tv(n)
    speed = np.sin(np.pi * np.clip(t / 0.82, 0, 1)) ** 0.8
    rum = lowpass(r.standard_normal(n), 180) * speed
    y = 0.5 * rum / (np.max(np.abs(rum)) + 1e-9)
    hum = (np.sin(TAU * 110 * t) + 0.4 * np.sin(TAU * 220 * t)) * speed * (1 + 0.2 * np.sin(TAU * 7 * t))
    y += 0.06 * hum
    sw = moving_band(n, lambda s: 600 + 500 * np.sin(np.pi * min(1.0, s / 0.8)), 1.2, r, 0.4)
    y += 0.3 * sw * speed
    ph = np.cumsum(speed) / SR * 28.0
    idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0]
    for i in idx:
        place(y, brass_tick(r.uniform(2400, 3000), 0.01, 0.07 * speed[i], r, 0.1), i / SR)
    return room(lowpass(y, 5000), 0.45, 0.1, r), "platform rotation: rumble + bearing hum + velvet swish + speed-following bearing ticks"


def s22(r):
    b = np.zeros(ns(0.3))
    place(b, lowpass(latch(260, 0.06, 1.0, r), 3000), 0)
    place(b, 0.7 * thump(140, 90, 0.1, 0.06), 0)
    place(b, wood(900, 0.015, 0.25, r), 0.004)
    return room(b, 0.3, 0.07, r), "rounded brass lock seating (modal 260 Hz, low-passed) + soft low thump"


def s23(r):
    n = ns(0.7)
    t = tv(n)
    br = moving_band(n, lambda s: 900 * (2200 / 900) ** min(1.0, s / 0.35), 1.3, r, 0.3)
    env = np.clip(t / 0.05, 0, 1) * np.exp(-np.clip(t - 0.25, 0, None) / 0.07)
    y = 0.45 * br * env
    y += sparkle(8, 0.1, 0.38, 3000, 6000, r, 0.3, 1.2, 0.25)[:n]
    return room(y, 0.4, 0.1, r), "silky velvet brush (900->2200 Hz) + light crystal scatter"


def s24(r):
    n = ns(0.9)
    t = tv(n)
    b = np.zeros(n)
    sc = band_noise(n, 3000, 6000, r) * np.clip(t / 0.01, 0, 1) * np.exp(-np.clip(t - 0.05, 0, None) / 0.015)
    b += 0.12 * sc / (np.max(np.abs(sc)) + 1e-9)
    place(b, latch(520, 0.05, 0.8, r), 0.09)
    place(b, brass_tick(3000, 0.02, 0.3, r), 0.092)
    place(b, bell(mtof(N("D6")), 0.9, 0.45, 0.8, r), 0.16)
    return room(b, 0.45, 0.1, r), "key scrape + warm lock click (modal 520 Hz) + bright bell D6"


def s25(r):
    n = ns(0.45)
    t = tv(n)
    fl = moving_band(n, lambda s: 1200 * (2600 / 1200) ** min(1.0, s / 0.07), 1.2, r, 0.2)
    y = 0.4 * fl * np.clip(t / 0.01, 0, 1) * np.exp(-np.clip(t - 0.04, 0, None) / 0.025)
    for i, nm in enumerate(("F6", "A6", "C7")):
        place(y, celesta(mtof(N(nm)), 0.22, 0.25, 0.6, r), 0.08 + 0.03 * i)
    return room(y, 0.3, 0.08, r), "cloth flick (1.2->2.6 kHz) + tiny warm celesta sparkle F6 A6 C7"


def s26(r):
    y = modal(210, [1, 1.9, 2.6, 3.4], [1, 0.5, 0.35, 0.2], [0.07, 0.05, 0.035, 0.025], 1.0, r, 0.2, (800, 4000))
    return room(y, 0.2, 0.05, r), "hollow crate knock (box modes from 210 Hz)"


def s27(r):
    b = np.zeros(ns(0.6))
    for k, (tt, f0) in enumerate(((0, 330), (0.018, 410), (0.034, 280))):
        cr = band_noise(ns(0.006), 600, 5000, r) * decay(tv(ns(0.006)), 0.004)
        place(b, (0.8 - 0.2 * k) * cr / (np.max(np.abs(cr)) + 1e-9), tt)
        place(b, wood(f0, 0.04, 0.7 - 0.15 * k, r), tt)
    for k in range(10):
        tt = r.uniform(0.06, 0.3)
        place(b, wood(r.uniform(900, 2200), r.uniform(0.012, 0.02), 0.28 * np.exp(-4 * (tt - 0.06)), r), tt)
    return room(b, 0.3, 0.07, r), "dry wooden crack (3 staggered cracks) + short scatter of small wood pieces"


def s28(r):
    b = np.zeros(ns(0.6))
    tt = 0.0
    for k in range(12):
        m = ns(0.0015)
        c = highpass(r.standard_normal(m), 2500) * decay(tv(m), 0.0008)
        place(b, (0.9 - 0.05 * k) * c / (np.max(np.abs(c)) + 1e-9), tt)
        tt += 0.012 * (0.8 ** k) + 0.002
    gl = modal(2900, [1, 1.48, 2.1, 2.66], [1, 0.7, 0.45, 0.3], [0.25, 0.18, 0.12, 0.09], 0.35, r, 0.0)
    place(b, gl, 0.002)
    return room(b, 0.35, 0.08, r, 0.7), "delicate ice crackle (12 micro-cracks) + glassy modes from 2.9 kHz"


def s29(r):
    b = np.zeros(ns(0.55))
    place(b, brass_tick(2900, 0.05, 0.9, r, 0.35), 0)
    place(b, latch(900, 0.03, 0.5, r), 0.004)
    for k, tt in enumerate((0.08, 0.14, 0.19, 0.24, 0.28)):
        place(b, brass_tick(r.uniform(3500, 5500), 0.03, 0.45 * 0.72 ** k, r, 0.3), tt)
    return room(b, 0.3, 0.08, r), "metallic snap (2.9 kHz) + five bouncing brass clinks"


def s30(r):
    b = np.zeros(ns(0.3))
    place(b, brass_tick(3400, 0.012, 0.35, r, 0.2), 0)
    place(b, latch(600, 0.04, 1.0, r), 0.03)
    place(b, wood(450, 0.03, 0.4, r, 0.1), 0.031)
    return room(b, 0.25, 0.06, r), "two-stage pedal click: pre-tick + secure brass click (600 Hz) with wood thud"


def s31(r):
    n = ns(0.7)
    t = tv(n)
    cl = moving_band(n, lambda s: 600 * (1500 / 600) ** min(1.0, s / 0.4), 1.2, r, 0.3)
    env = np.clip(t / 0.05, 0, 1) * np.exp(-np.clip(t - 0.3, 0, None) / 0.07)
    y = 0.4 * cl * env
    tt = 0.05
    while tt < 0.4:
        place(y, brass_tick(r.uniform(2600, 3200), 0.01, 0.06, r, 0.1), tt)
        tt += r.uniform(0.02, 0.035)
    place(y, wood(500, 0.05, 0.5, r, 0.2), 0.42)
    return room(lowpass(y, 6000), 0.35, 0.08, r), "cloth lift (600->1500 Hz) + faint brass rail ticks + gentle wooden stop"


def s32(r):
    b = np.zeros(ns(0.9))
    place(b, celesta(mtof(N("E6")), 0.55, 0.5, 0.8, r), 0)
    place(b, celesta(mtof(N("A6")), 0.6, 0.5, 0.8, r), 0.08)
    place(b, bell(mtof(N("D6")), 0.85, 0.5, 0.6, r), 0.16)
    return room(b, 0.5, 0.12, r), "celesta question E6 -> A6 resolving to warm bell D6"


def s33(r):
    b = np.zeros(ns(3.2))
    mel = [("A5", 0.00, 0.55), ("Bb5", 0.15, 0.5), ("C6", 0.30, 0.55), ("D6", 0.45, 0.5), ("E6", 0.60, 0.6), ("F6", 0.90, 0.85)]
    for nm, tt, v in mel:
        place(b, celesta(mtof(N(nm)), v, None, 0.9, r), tt)
    for tt, notes, v in ((0.0, ["Bb2", "F4", "D5"], 0.6), (0.45, ["C3", "E4", "G4"], 0.6), (0.9, ["F2", "A3", "C4", "F4"], 0.75)):
        for k, nm in enumerate(notes):
            place(b, 0.45 * pizz(mtof(N(nm)), v, r), tt + 0.012 * k)
    for nm in ("F3", "A3", "C4"):
        place(b, 0.16 * horn(mtof(N(nm)), 1.0, 0.55, r, 0.14, 0.35), 0.9)
    place(b, glock(mtof(N("F6")), 0.25, 0.8, r), 0.9)
    place(b, glock(mtof(N("A6")), 0.2, 0.8, r), 0.96)
    return room(b, 1.2, 0.18, r), "chamber sting IV-V-I in F: celesta A5..F6 line, pizzicato chords, soft horn F-major swell, glock"


def s34(r):
    b = np.zeros(ns(2.0))
    for nm, tt, d, v in (("A4", 0.0, 0.3, 0.6), ("G4", 0.3, 0.27, 0.55), ("F4", 0.57, 0.3, 0.45)):
        place(b, 0.5 * reed(mtof(N(nm)), d, v, 0.7, 0.05, r, 0.05 if tt else 0.02, 0.12), tt)
    place(b, 0.35 * pizz(mtof(N("D3")), 0.45, r), 0.72)
    place(b, marimba(mtof(N("D4")), 0.5, 0.8, 0.9, r), 0.72)
    place(b, marimba(mtof(N("A4")), 0.45, 0.8, 0.9, r), 0.95)
    return room(b, 1.0, 0.16, r), "clarinet-like A4 G4 F4 descent + two gentle marimba notes D4 -> A4 (open, hopeful)"


def s35(r):
    b = np.zeros(ns(3.8))
    gl = ["D4", "E4", "F#4", "G4", "A4", "B4", "C#5", "D5", "E5", "F#5", "A5", "D6"]
    for i, nm in enumerate(gl):
        place(b, 0.35 * harp(mtof(N(nm)), 0.5 + 0.4 * i / len(gl), r), 0.045 * i)
    for nm in ("A3", "C#4", "E4"):
        place(b, 0.13 * horn(mtof(N(nm)), 0.55, 0.45, r, 0.1, 0.2), 0.1)
    for nm in ("D3", "F#3", "A3", "D4"):
        place(b, 0.15 * horn(mtof(N(nm)), 1.6, 0.6, r, 0.12, 0.45), 0.68)
    place(b, 0.5 * thump(mtof(N("D2")) * 1.2, mtof(N("D2")), 0.6, 0.5), 0.68)
    for i, nm in enumerate(("D6", "F#6", "A6")):
        place(b, bell(mtof(N(nm)), 0.4, 0.5, 0.7, r), 0.7 + 0.08 * i)
    place(b, sparkle(8, 0.8, 1.3, 4000, 7500, r, 0.12, 1.0, 0.4), 0)
    return room(b, 1.6, 0.2, r), "harp glissando (D major) + horn A -> D major swell + soft low D + small bells"


def s36(r):
    b = np.zeros(ns(1.2))
    for k in range(8):
        tt = 0.3 * (1 - (1 - k / 8) ** 1.4)
        place(b, brass_tick(r.uniform(3000, 4500), 0.015, 0.25 + 0.03 * k, r, 0.2), tt)
    cr = band_noise(ns(0.12), 300, 600, r) * np.hanning(ns(0.12))
    place(b, 0.15 * cr / (np.max(np.abs(cr)) + 1e-9), 0.02)
    place(b, bell(mtof(N("A5")), 0.8, 0.45, 0.6, r), 0.3)
    return room(b, 0.5, 0.12, r), "tiny accelerating brass gear ticks + small wood creak + warm bell A5"


def s38(r):
    b = np.zeros(ns(0.4))
    place(b, lowpass(latch(700, 0.035, 1.0, r), 5000), 0)
    place(b, wood(350, 0.03, 0.45, r, 0.1), 0.001)
    place(b, glock(mtof(N("A6")), 0.28, 0.25, r), 0.02)
    return room(b, 0.25, 0.06, r), "rounded brass reel lock (modal 700 Hz) + wood thud + tiny glock A6 (pitch-shift friendly)"


def s39(r):
    b = np.zeros(ns(1.6))
    for i, nm in enumerate(("A5", "D6", "F6")):
        place(b, celesta(mtof(N(nm)), 0.6, None, 0.8, r), 0.12 * i)
    for nm in ("F4", "A4", "D5"):
        place(b, 0.1 * horn(mtof(N(nm)), 0.6, 0.4, r, 0.12, 0.3), 0.26)
    place(b, 0.18 * fm_shimmer(mtof(N("D6")), 0.8, 1.41, 1.5, 0.15, 0.6), 0.36)
    place(b, sparkle(6, 0.36, 0.8, 4000, 7000, r, 0.1, 1.2, 0.4), 0)
    return room(b, 0.8, 0.15, r), "three celesta notes A5 D6 F6 + soft horn triad + brass FM sparkle (calm, no fanfare)"


SFX_DESIGNS = {
    "S01": s01, "S02": s02, "S03": s03, "S04": s04, "S05": s05, "S06": s06, "S07": s07, "S08": s08,
    "S09": s09, "S10": s10, "S11": s11, "S12": s12, "S13": s13, "S14": s14, "S15": s15, "S16": s16,
    "S17": s17, "S18": s18, "S19": s19, "S20": s20, "S21": s21, "S22": s22, "S23": s23, "S24": s24,
    "S25": s25, "S26": s26, "S27": s27, "S28": s28, "S29": s29, "S30": s30, "S31": s31, "S32": s32,
    "S33": s33, "S34": s34, "S35": s35, "S36": s36, "S38": s38, "S39": s39,
}


# ============================================================================ loops

def s37_loop(r):
    """1.5 s reel loop: three reels ticking at 8/10/12 Hz (integer counts per loop) + periodic flutter bed."""
    L = ns(1.5)
    buf = np.zeros(L + ns(0.3))
    for rate, f0, amp in ((8, 2400, 0.55), (10, 3100, 0.45), (12, 1900, 0.4)):
        cnt = int(round(rate * 1.5))
        for k in range(cnt):
            tt = k * 1.5 / cnt + 0.004 * np.sin(k)
            a = amp * (0.85 + 0.15 * np.cos(TAU * k / cnt))
            place(buf, brass_tick(f0 * (1 + 0.02 * np.sin(3 * k)), 0.012, 0.5 * a, r, 0.25), tt)
            place(buf, wood(f0 * 0.35, 0.015, 0.35 * a, r, 0.15), tt + 0.001)
    y = fold(buf, L)
    fl = periodic_noise(L, lambda f: hp_g(f, 400, 2) * lp_g(f, 2500, 2), r)
    tt = tv(L)
    am = 0.6 + 0.4 * np.sin(TAU * 8 * tt) * np.sin(TAU * 10 * tt + 1.0)      # 12 and 15 cycles per loop
    y = y + 0.06 * fl * am
    ir = make_ir(0.25, r)[0]
    y = y + 0.08 * circ_conv(y, ir, L)
    y = circ_filter(y, lambda f: lp_g(f, 9000, 2))
    return y, ("three reels ticking at 8/10/12 Hz (brass+wood modal ticks), periodic 400-2500 Hz flutter bed; "
               "all tails wrapped, circular room reverb -> sample-exact loop")


def ambience_loop(r, which):
    if which == "A01":
        L = ns(12.0)
        g = lambda f: (np.maximum(f, 20) / 100.0) ** -0.6 * hp_g(f, 60, 2) * lp_g(f, 1400, 2)
        base = np.stack([periodic_noise(L, g, r), periodic_noise(L, g, r)])
        base = 0.8 * base + 0.2 * base[::-1]
        tt = tv(L)
        breath = 1 + 0.08 * np.sin(TAU * tt / 12.0) + 0.04 * np.sin(TAU * 2 * tt / 12.0 + 1.3)
        y = base * breath
        buf = np.zeros((2, L + ns(3.0)))
        for t0, f0, d, pan in ((2.7, 190, 0.45, -0.4), (7.4, 240, 0.35, 0.3), (10.1, 170, 0.5, 0.1)):
            n = ns(d)
            fr = band_noise(n, 250, 700, r) * (0.5 + 0.5 * np.abs(np.sin(TAU * r.uniform(30, 55) * tv(n)))) * np.hanning(n)
            fr = 0.5 * fr / (np.max(np.abs(fr)) + 1e-9)
            w = wood(f0, 0.12, 0.4, r, 0.0)
            m = min(n, len(w))
            fr[:m] += w[:m]
            cr = lowpass(fr, 900)
            cr = 0.35 * cr / (np.max(np.abs(cr)) + 1e-9)
            gl, gr = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
            place(buf[0], cr * gl, t0)
            place(buf[1], cr * gr, t0)
        ev = fold(buf, L)
        irs = make_ir(1.8, r, True, 0.03, 0.3)
        send = ev.mean(axis=0)
        ev = 0.4 * ev + np.stack([circ_conv(send, irs[0], L), circ_conv(send, irs[1], L)])
        y = y + 0.9 * ev
        desc = ("warm periodic room tone (brown-ish 30-1400 Hz, stereo), slow breathing modulation with integer "
                "cycles, three very soft distant low-passed wooden settles in a circular 1.8 s reverb")
    else:
        L = ns(10.0)
        g = lambda f: hp_g(f, 150, 2) * lp_g(f, 1200, 2) * (np.maximum(f, 20) / 300.0) ** -0.5
        air = np.stack([periodic_noise(L, g, r), periodic_noise(L, g, r)])
        tt = tv(L)
        mod = 1 + 0.15 * np.sin(TAU * 1 * tt / 10.0) + 0.08 * np.sin(TAU * 3 * tt / 10.0 + 0.7)
        flick = periodic_noise(L, lambda f: hp_g(f, 300, 2) * lp_g(f, 900, 2), r)
        fm = np.abs(periodic_noise(L, lambda f: lp_g(f, 9, 2), r))
        y = air * mod + 0.25 * flick * (0.3 + 0.7 * fm / (np.max(fm) + 1e-9))
        buf = np.zeros((2, L + ns(0.5)))
        for k in range(12):
            t0 = (k + r.uniform(0.1, 0.9)) * 10.0 / 12
            n = ns(r.uniform(0.004, 0.009))
            c = band_noise(n, 1000, 3000, r) * ramp(n, 0.0015) * decay(tv(n), n / SR * 0.6)
            c = 0.5 * r.uniform(0.4, 1.0) * c / (np.max(np.abs(c)) + 1e-9)
            pan = r.uniform(-0.6, 0.6)
            place(buf[0], c * np.cos((pan + 1) * np.pi / 4), t0)
            place(buf[1], c * np.sin((pan + 1) * np.pi / 4), t0)
        y = y + fold(buf, L)
        desc = ("periodic warm air band (150-1200 Hz) with slow integer-cycle movement, low flame flutter "
                "(300-900 Hz, <9 Hz modulation) and 12 tiny soft-attack flicker crackles, wrapped")
    return y, desc


# ============================================================================ music

CH = {
    "Dm": (2, [2, 5, 9]), "Dm/C": (0, [2, 5, 9, 0]), "Dm/A": (9, [2, 5, 9]), "D": (2, [2, 6, 9]),
    "Dsus4": (2, [2, 7, 9]), "A7": (9, [9, 1, 4, 7]), "A": (9, [9, 1, 4]), "Asus4": (9, [9, 2, 4]),
    "Gm": (7, [7, 10, 2]), "Gm6": (7, [7, 10, 2, 4]), "Gm7": (7, [7, 10, 2, 5]), "Bb": (10, [10, 2, 5]),
    "Bbmaj7": (10, [10, 2, 5, 9]), "Em7b5": (4, [4, 7, 10, 2]), "F": (5, [5, 9, 0]), "F/A": (9, [5, 9, 0]),
    "C": (0, [0, 4, 7]), "C/E": (4, [0, 4, 7]), "C7": (0, [0, 4, 7, 10]), "Am": (9, [9, 0, 4]),
    "Am7": (9, [9, 0, 4, 7]),
}


def voicing(chord, prev, lo, hi, k):
    """Voice-led k-note voicing: minimal total motion from prev (sorted), must hold the 3rd (and 7th)."""
    _, pcs = CH[chord]
    must = {pcs[1]} | ({pcs[3]} if len(pcs) > 3 else set())
    notes = [m for m in range(lo, hi + 1) if m % 12 in pcs]
    best = None
    for comb in itertools.combinations(notes, k):
        cp = {m % 12 for m in comb}
        if not must <= cp or len(cp) < min(k, len(pcs)):
            continue
        if comb[-1] - comb[0] > 14:
            continue
        cost = sum(abs(a - b) for a, b in zip(comb, prev)) if prev else abs(sum(comb) / k - (lo + hi) / 2)
        if best is None or cost < best[0]:
            best = (cost, list(comb))
    return best[1]


def nearest_tone(chord, target, lo, hi, prefer=None):
    _, pcs = CH[chord]
    cands = [m for m in range(lo, hi + 1) if m % 12 in (prefer or pcs)]
    return min(cands, key=lambda m: (abs(m - target), m))


class Ev:
    __slots__ = ("t", "inst", "midi", "dur", "vel", "pan")

    def __init__(self, t, inst, midi, dur, vel, pan):
        self.t, self.inst, self.midi, self.dur, self.vel, self.pan = t, inst, midi, dur, vel, pan


def render_music(events, L, rng, rt, wet, levels, tail=5.0):
    buf = np.zeros((2, L + ns(tail)))
    cache = {}
    for e in events:
        f = mtof(e.midi)
        key = (e.inst, e.midi, round(e.dur, 3), round(e.vel, 2))
        if key in cache:
            sig = cache[key]
        else:
            if e.inst == "celesta":
                sig = celesta(f, e.vel, max(0.6, e.dur + 0.8), 0.8, rng)
            elif e.inst == "pizz" or e.inst == "pizzbass":
                sig = pizz(f, e.vel, rng)
            elif e.inst == "clar":
                sig = reed(f, e.dur, e.vel, 0.75, 0.04, rng, 0.08, 0.18)
            elif e.inst == "bassoon":
                sig = reed(f, e.dur, e.vel, 0.9, 0.3, rng, 0.12, 0.3, 0.0015)
            elif e.inst == "horn":
                sig = horn(f, e.dur, e.vel, rng, 0.18, 0.4)
            elif e.inst == "mallet":
                sig = marimba(f, e.vel, 0.85, 1.0, rng)
            elif e.inst == "glock":
                sig = glock(f, e.vel, 0.9, rng)
            elif e.inst == "brush":
                n = ns(0.16)
                s = band_noise(n, 1800, 8000, rng) * ramp(n, 0.02) * decay(tv(n), 0.12)
                sig = e.vel * s / (np.max(np.abs(s)) + 1e-9)
            elif e.inst == "tick":
                n = ns(0.03)
                s = band_noise(n, 5000, 11000, rng) * ramp(n, 0.001) * decay(tv(n), 0.02)
                sig = e.vel * s / (np.max(np.abs(s)) + 1e-9)
            else:
                raise ValueError(e.inst)
            if e.inst not in ("brush", "tick"):
                cache[key] = sig
        g = levels[e.inst]
        th = (e.pan + 1) * np.pi / 4
        t_on = e.t % (L / SR)                     # circular time: a slightly early downbeat wraps to the end
        place(buf[0], sig * g * np.cos(th), t_on)
        place(buf[1], sig * g * np.sin(th), t_on)
    dry = fold(buf, L)
    irs = make_ir(rt, rng, True, 0.02, 0.45, min(rt * 1.5, 4.5))
    send = dry.mean(axis=0)
    wetsig = np.stack([circ_conv(send, irs[0], L), circ_conv(send, irs[1], L)])
    return dry + wet * wetsig


def jitter(rng, s=0.004):
    return float(rng.uniform(-s, s))


def compose_m01(rng):
    beat = 60 / 96
    bpb = 3
    prog = ["Dm", "Dm", "Gm", "A7", "Dm", "Bb", "Em7b5", "A7",
            "Dm", "Dm/C", "Bb", "F/A", "Gm", "C7", "F", "C7",
            "F", "C/E", "Dm", "Am", "Bb", "F/A", "Gm7", "A7",
            "Dm", "Dm", "Gm", "Gm", "Dm/A", "A7", "Dm", "A7"]
    mel = {
        1: [("D5", 1), ("F5", 1), ("A5", 1)], 2: [("D6", 2), ("C#6", .5), ("D6", .5)],
        3: [("Bb5", 1.5), ("A5", .5), ("G5", 1)], 4: [("E5", 2), ("C#5", 1)],
        5: [("A4", 1), ("D5", 1), ("F5", 1)], 6: [("D6", 1.5), ("C6", .5), ("Bb5", 1)],
        7: [("Bb5", 1.5), ("A5", .5), ("G5", 1)], 8: [("A5", 2), ("G5", .5), ("E5", .5)],
        9: [("F5", 1), ("A5", 1), ("D6", 1)], 10: [("E6", 1.5), ("D6", .5), ("C6", 1)],
        11: [("D6", 2), ("Bb5", 1)], 12: [("C6", 1.5), ("A5", .5), ("F5", 1)],
        13: [("G5", 1), ("Bb5", 1), ("D6", 1)], 14: [("E6", 1.5), ("D6", .5), ("Bb5", 1)],
        15: [("A5", 2), ("F5", 1)], 16: [("G5", 1), ("Bb5", 1), ("E5", 1)],
        25: [("D5", 1), ("F5", 1), ("A5", 1)], 26: [("D6", 2), ("C#6", .5), ("D6", .5)],
        27: [("Bb5", 1.5), ("A5", .5), ("G5", 1)], 28: [("G5", 2), ("F5", .5), ("E5", .5)],
        29: [("F5", 1.5), ("E5", .5), ("D5", 1)], 30: [("C#5", 1), ("E5", 1), ("G5", 1)],
        31: [("F5", 2), ("D5", 1)], 32: [("E5", 1), ("G5", .5), ("F5", .5), ("E5", 1)],
    }
    clar = {
        17: [("A4", 1.5), ("Bb4", .5), ("C5", 1)], 18: [("G4", 1.5), ("F4", .5), ("E4", 1)],
        19: [("F4", 1), ("A4", 1), ("D5", 1)], 20: [("C5", 2), ("A4", 1)],
        21: [("D5", 1.5), ("C5", .5), ("Bb4", 1)], 22: [("A4", 1.5), ("G4", .5), ("F4", 1)],
        23: [("G4", 1), ("Bb4", 1), ("D5", 1)], 24: [("C#5", 2), ("A4", 1)],
    }
    ev = []
    prev_v = None
    prev_c = N("A4")
    prev_h = None
    for b, chord in enumerate(prog, start=1):
        t0 = (b - 1) * bpb * beat
        root = CH[chord][0]
        bass = 38 + ((root - 38) % 12)
        if bass > 49:
            bass -= 12
        ev.append(Ev(t0 + jitter(rng, 0.003), "pizzbass", bass, beat, 0.75 + (0.05 if b % 2 else 0), -0.15))
        v = voicing(chord, prev_v, 55, 72, 3)
        prev_v = v
        for k, beat_i in enumerate((1, 2)):
            for j, m in enumerate(v):
                ev.append(Ev(t0 + beat_i * beat + 0.006 * j + jitter(rng, 0.004), "pizz", m, beat,
                             (0.5 if beat_i == 1 else 0.42) + rng.uniform(-0.04, 0.04), 0.35))
        line = mel.get(b)
        if line:
            tt = t0
            for nm, d in line:
                ev.append(Ev(tt + jitter(rng, 0.003), "celesta", N(nm), d * beat, 0.62 + rng.uniform(-0.05, 0.05), 0.2))
                tt += d * beat
        cl = clar.get(b)
        if cl:
            tt = t0
            for nm, d in cl:
                ev.append(Ev(tt, "clar", N(nm), d * beat * 0.98, 0.55, -0.3))
                tt += d * beat
            ev.append(Ev(t0 + 2 * beat + 0.01, "celesta", nearest_tone(chord, 88, 84, 93), beat, 0.32, 0.4))
        elif b >= 5:
            _, pcs = CH[chord]
            guides = [pcs[1]] + ([pcs[3]] if len(pcs) > 3 else [])
            m = nearest_tone(chord, prev_c, N("F3"), N("C5"), guides)
            prev_c = m
            ev.append(Ev(t0 + 0.02, "clar", m, 3 * beat * 0.95, 0.3, -0.35))
        if b % 4 == 0:
            hv = voicing(chord, prev_h, 50, 67, 3)
            prev_h = hv
            for m in hv:
                ev.append(Ev(t0 + 0.02, "horn", m, 2.5 * beat, 0.4, 0.0))
    L = 32 * bpb * 30000
    levels = {"celesta": 0.5, "pizzbass": 0.55, "pizz": 0.22, "clar": 0.3, "horn": 0.12, "glock": 0.2}
    x = render_music(ev, L, rng, 1.9, 0.26, levels)
    return x, L, {"bars": 32, "beatsPerBar": 3, "bpm": 96, "chords": prog,
                  "recipe": "D minor waltz 96 BPM 3/4, 32 bars (A A' B A''): celesta melody, pizzicato bass on 1 "
                            "+ voice-led pizzicato chords on 2-3, clarinet-like counter-line and B-section lead, "
                            "sparse horn chords at phrase ends; ends on A7 so bar 32 leads into bar 1"}


def compose_m02(rng):
    beat = 60 / 96
    bpb = 4
    P1 = ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "Asus4", "A7"]
    P2 = ["Dm", "Dm/C", "Bbmaj7", "Bbmaj7", "Gm7", "Gm7", "Asus4", "A7"]
    P3 = ["Bb", "C", "F", "Dm", "Gm", "Gm", "Asus4", "A7"]
    P4 = ["Dm", "Dm", "Bb", "Bb", "Gm6", "Gm", "Asus4", "A7"]
    prog = P1 + P2 + P3 + P4
    patA = [0, 2, 1, 3, 0, 2, 1, 2]
    patB = [0, 1, 2, 3, 2, 1, 0, 2]
    ev = []
    prev_w = N("A3")
    prev_w2 = N("F4")
    for b, chord in enumerate(prog, start=1):
        t0 = (b - 1) * bpb * beat
        root = CH[chord][0]
        bass = 38 + ((root - 38) % 12)
        if bass > 49:
            bass -= 12
        ev.append(Ev(t0 + jitter(rng, 0.003), "pizzbass", bass, beat, 0.7, -0.1))
        fifth = bass + 7
        ev.append(Ev(t0 + 2 * beat + jitter(rng, 0.003), "pizzbass", fifth if b % 2 else bass + 12, beat, 0.55, -0.1))
        _, pcs = CH[chord]
        tones = sorted(m for m in range(N("D4"), N("F5") + 1) if m % 12 in pcs)[:4]
        while len(tones) < 4:
            tones.append(tones[len(tones) % max(1, len(tones))] + 12)
        pat = patA if ((b - 1) // 4) % 2 == 0 else patB
        for i, idx in enumerate(pat):
            if i == 7 and b % 4 == 0:
                continue
            acc = 1.0 if i == 0 else (0.85 if i == 4 else 0.68)
            ev.append(Ev(t0 + i * beat / 2 + jitter(rng, 0.004), "mallet", tones[idx], beat / 2,
                         0.5 * acc + rng.uniform(-0.03, 0.03), 0.25))
        if b % 2 == 0:
            v = voicing(chord, None, 57, 69, 2)
            for j, m in enumerate(v):
                ev.append(Ev(t0 + 1.5 * beat + 0.008 * j, "pizz", m, beat, 0.4, 0.45))
        for q in (1, 3):
            ev.append(Ev(t0 + q * beat + jitter(rng, 0.006), "brush", 60, 0.16, 0.55 + rng.uniform(-0.1, 0.1),
                         rng.uniform(-0.5, 0.5)))
        for q in range(8):
            ev.append(Ev(t0 + q * beat / 2 + jitter(rng, 0.005), "tick", 60, 0.03,
                         (0.35 if q % 2 else 0.22) + rng.uniform(-0.05, 0.05), 0.55))
        if b % 2 == 1:
            nxt = prog[b] if b < len(prog) else prog[0]
            guides = [pcs[1]] + ([pcs[3]] if len(pcs) > 3 else []) + [pcs[0]]
            m = nearest_tone(chord, prev_w, N("D3"), N("A3"), guides)
            prev_w = m
            ev.append(Ev(t0 + 0.03, "bassoon", m, 2 * bpb * beat * 0.97, 0.5, -0.4))
            if 17 <= b <= 24:
                m2 = nearest_tone(nxt if b % 4 == 3 else chord, prev_w2, N("C4"), N("A4"), [pcs[1], pcs[0]])
                prev_w2 = m2
                ev.append(Ev(t0 + 0.05, "clar", m2, 2 * bpb * beat * 0.95, 0.35, 0.35))
    L = 32 * bpb * 30000
    levels = {"pizzbass": 0.45, "pizz": 0.2, "mallet": 0.42, "brush": 0.06, "tick": 0.03, "bassoon": 0.18,
              "clar": 0.15}
    x = render_music(ev, L, rng, 1.6, 0.2, levels)
    return x, L, {"bars": 32, "beatsPerBar": 4, "bpm": 96, "chords": prog,
                  "recipe": "D minor underscore 96 BPM 4/4, 32 bars: soft marimba 8th-note ostinato over chord "
                            "tones, pizzicato bass on 1 and 3, sparse pizzicato offbeat dyads, very light brushes "
                            "and ticks, voice-led low reed (bassoon-like) guide tones; no lead; ends on A7"}


def compose_m03(rng):
    beat = 60 / 96
    bpb = 4
    P1 = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"]
    P2 = ["Gm", "Bb", "F/A", "D", "Gm", "C", "F", "A7"]
    P3 = ["Bbmaj7", "C", "Am7", "Dm", "Bb", "C", "Dsus4", "D"]
    P4 = ["Dm", "Bb", "F", "C", "Gm", "Bb", "Asus4", "A7"]
    prog = P1 + P2 + P3 + P4
    templates = [
        [(0, 2), (2, 1), (3, 1), (4, 3)],
        [(0, 1.5), (1.5, 0.5), (2, 2), (4, 4)],
        [(0, 3), (3, 1), (4, 2), (6, 2)],
        [(1, 1), (2, 1), (3, 1), (4, 4)],
    ]
    contours = [[0, 2, 1, -1], [0, -1, -2, 1], [2, 1, 0, -2], [0, 1, 2, 3]]
    scale = [2, 4, 5, 7, 9, 10, 0, 1]
    ev = []
    prev_v = None
    prev_h = None
    mel_prev = N("A5")
    for b, chord in enumerate(prog, start=1):
        t0 = (b - 1) * bpb * beat
        root = CH[chord][0]
        bass = 38 + ((root - 38) % 12)
        if bass > 49:
            bass -= 12
        ev.append(Ev(t0 + jitter(rng, 0.003), "pizzbass", bass, beat, 0.72, -0.1))
        v = voicing(chord, prev_v, 55, 74, 3)
        prev_v = v
        for q, m in zip((1, 2, 3), v if b % 2 else v[::-1]):
            ev.append(Ev(t0 + q * beat + jitter(rng, 0.004), "pizz", m, beat, 0.45 + rng.uniform(-0.04, 0.04), 0.3))
        if b % 2 == 1:
            unit = (b - 1) // 2
            tpl = templates[unit % len(templates)]
            ctr = contours[(unit * 3 + 1) % len(contours)]
            if unit % 8 == 7:
                tpl = [(0, 3), (4, 3)]
            for (off, d), step in zip(tpl, ctr):
                tt = t0 + off * beat
                ch_now = prog[b - 1] if off < 4 else prog[b] if b < len(prog) else prog[0]
                target = mel_prev + 2 * step
                if d >= 1.5 or off in (0, 4):
                    m = nearest_tone(ch_now, target, N("F5"), N("A6"))
                else:
                    m = nearest_tone(ch_now, target, N("F5"), N("A6"), scale)
                mel_prev = m
                ev.append(Ev(tt + jitter(rng, 0.003), "celesta", m, d * beat, 0.55 + rng.uniform(-0.05, 0.05), 0.15))
            hv = voicing(chord, prev_h, 48, 64, 3)
            prev_h = hv
            bright = chord in ("D", "Dsus4", "C", "F", "Bbmaj7")
            for m in hv:
                ev.append(Ev(t0 + 0.03, "horn", m, 3 * beat, 0.42 if bright else 0.34, -0.05))
        if chord in ("D", "Dsus4") or b in (28, 31):
            ev.append(Ev(t0 + 2 * beat, "glock", nearest_tone(chord, N("F#6"), N("D6"), N("A6")), beat, 0.3, 0.45))
    L = 32 * bpb * 30000
    levels = {"pizzbass": 0.5, "pizz": 0.24, "celesta": 0.48, "horn": 0.12, "glock": 0.22}
    x = render_music(ev, L, rng, 2.7, 0.34, levels)
    return x, L, {"bars": 32, "beatsPerBar": 4, "bpm": 96, "chords": prog,
                  "recipe": "D minor finale underscore 96 BPM 4/4, 32 bars with brighter passages (D major, "
                            "Bbmaj7, C): measured quarter-note pizzicato (bass + voice-led chord tones), "
                            "algorithmic celesta phrases (rhythm templates + contour, chord tones on strong "
                            "beats), soft horn chords every 2 bars, glock accents, larger 2.7 s circular reverb"}


# ============================================================================ main

LICENSE_NOTE_SUB = ("Procedurally synthesized in-house by scripts/synth_substitute_audio.py (no samples, no provider "
                    "output, no third-party material). Debug placeholder only - NOT the ElevenLabs asset; release "
                    "requires the ElevenLabs file for this ID.")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Synthesize the procedural substitute audio set (NOT ElevenLabs)")
    ap.add_argument("--ids", help="subset, e.g. S01-S10, M01, all (default all)")
    ap.add_argument("--no-manifest", action="store_true")
    opts = ap.parse_args(argv)
    doc = ga.load_requests()
    selected = ga.parse_ids(opts.ids, doc["entries"])
    man = ga.load_manifest()
    by_id = {e["id"]: e for e in man.get("entries", [])}
    today = dt.date.today().isoformat()
    print(f"{'ID':<4} {'file':<28} {'dur':>7} {'ch':>2} {'peak':>7} {'rms':>7}  recipe")
    for entry in selected:
        eid = entry["id"]
        dest = ga.RUNTIME_DIR / entry["runtimeFile"]
        cur = by_id.get(eid)
        if cur and cur.get("provider") == ga.ELEVEN_PROVIDER and dest.is_file() \
                and ga.sha256_file(dest) == cur.get("runtimeSha256"):
            print(f"{eid:<4} {entry['runtimeFile']:<28} kept: real ElevenLabs runtime file is not overwritten")
            continue
        seed = int(hashlib.sha256(("vc-substitute-" + eid).encode()).hexdigest()[:8], 16)
        rng = np.random.default_rng(seed)
        extra = {}
        if entry["kind"] == "sfx" and not entry["isLoop"]:
            x, recipe = SFX_DESIGNS[eid](rng)
            y = finish_oneshot(x, float(entry["targetDuration"]), SFX_PEAK_DB[entry["priority"]])
        elif eid == "S37":
            x, recipe = s37_loop(rng)
            y = finish_loop(x, -9.0, 40.0)
        elif entry["kind"] == "ambience":
            x, recipe = ambience_loop(rng, eid)
            y = finish_loop(x, AMBIENCE_PEAK_DB, 25.0)
        else:
            comp = {"M01": compose_m01, "M02": compose_m02, "M03": compose_m03}[eid]
            x, L, info = comp(rng)
            y = finish_loop(x, MUSIC_PEAK_DB, 25.0)
            recipe = info.pop("recipe")
            extra = {"loopBars": info["bars"], "tempoBpm": info["bpm"], "beatsPerBar": info["beatsPerBar"],
                     "chordProgression": info["chords"]}
        write_pcm16(dest, y, seed)
        facts, decoded = ga.runtime_file_facts(dest)
        e = ga.base_entry(entry)
        e.update({
            "provider": ga.SUBSTITUTE_PROVIDER,
            "model": GENERATOR,
            "requestID": None,
            "sourceHash": "sha256:" + facts["runtimeSha256"],
            "sourceCodec": "none - synthesized float64 PCM, TPDF-dithered to pcm_s16le",
            "substituteRecipe": recipe,
            "productionDate": today,
            **facts,
            "loopStart": 0 if entry["isLoop"] else None,
            "loopEnd": facts["frameCount"] if entry["isLoop"] else None,
            "qaStatus": "substitute-approved-for-debug",
            "listeningQA": "not performed by a human",
            "releaseReady": False,
            "licensePlanNote": LICENSE_NOTE_SUB,
            **extra,
        })
        if entry["kind"] == "music" and "notes" in e:
            e["elevenLabsProductionNotes"] = e.pop("notes")
            e["notes"] = ("Substitute composed algorithmically and rendered as an exact 32-bar circular loop "
                          "(no provider generation, no loop editing needed).")
        if entry["isLoop"]:
            e["loopConstruction"] = "circular synthesis (tails wrapped to head, circular reverb) - sample-exact seam"
            e["seam"] = ga.seam_metrics(decoded, facts["channels"])
        by_id[eid] = e
        print(f"{eid:<4} {entry['runtimeFile']:<28} {facts['editedDuration']:>6.3f}s {facts['channels']:>2} "
              f"{facts['peakDBFS']:>7.2f} {facts['rmsDBFS']:>7.2f}  {recipe[:90]}")
    if not opts.no_manifest:
        man["entries"] = list(by_id.values())
        ga.save_manifest(man, doc)
        print(f"Manifest written: {ga.rel(ga.MANIFEST_PATH)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
