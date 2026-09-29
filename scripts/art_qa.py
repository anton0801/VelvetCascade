#!/usr/bin/env python3
"""Velvet Cascade art QA (VC01–VC40).

Checks every catalog PNG in VelvetCascade/Resources/Art:
  * file exists, exact pixel size from the catalog
  * opaque assets have NO alpha channel (PNG colour type RGB)
  * alpha assets have real transparency: transparent corners, a transparent outer border
    (no clipped edges; curtains are allowed to touch their anchor edge only), no opaque
    black/white corner boxes, and a meaningful transparent-pixel ratio
  * backgrounds: no thin 1-px-column render artifacts in the calm centre
  * VC23: the three empty cream windows are measured from pixels and compared with the target geometry

Also renders Production/ArtSources/contact_sheet.png (all assets on #160C1D plus a readability row with
tokens/specials/key/port/obstacles at 80 px ≈ 40 pt @2x) and, with --write-manifest, writes
VelvetCascade/Resources/Manifests/art_manifest.json from the measured values.

Usage:  python3 scripts/art_qa.py [--write-manifest] [--no-sheet]
Requires Pillow and numpy.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "VelvetCascade", "Resources", "Art")
RENDERS = os.path.join(ROOT, "Production", "ArtSources", "renders")
SHEET = os.path.join(ROOT, "Production", "ArtSources", "contact_sheet.png")
MANIFEST = os.path.join(ROOT, "VelvetCascade", "Resources", "Manifests", "art_manifest.json")
SRC = "Production/ArtSources/ArtForge/Sources/ArtForge/"
PROVENANCE = "Procedural vector/CoreGraphics illustration authored by Claude Code via ArtForge; no image-generation model used"
PRODUCED_AT = "2026-09-29"

BG = "background"
# id, file, w, h, alpha, displayRole, source file, special rule
CATALOG = [
    ("VC01", "vc_onboarding_welcome.png", 1290, 2796, False, "Welcome onboarding fullscreen background (hero Vell inside)", "BackgroundOnboarding.swift", BG),
    ("VC02", "vc_onboarding_match.png", 1290, 2796, False, "Match Tutorial fullscreen background", "BackgroundOnboarding.swift", BG),
    ("VC03", "vc_onboarding_rotate.png", 1290, 2796, False, "Rotation Tutorial fullscreen background (hero Vell inside)", "BackgroundOnboarding.swift", BG),
    ("VC04", "vc_vell_idle.png", 1024, 1536, True, "Home hero, full body, up to 190×260 pt", "Vell.swift", "figure"),
    ("VC05", "vc_vell_celebrate.png", 1024, 1536, True, "Victory / World Complete hero bow, up to 180×220 pt", "Vell.swift", "figure"),
    ("VC06", "vc_vell_encourage.png", 1024, 1536, True, "Retry hero, up to 180×220 pt", "Vell.swift", "figure"),
    ("VC07", "vc_gem_heart.png", 512, 512, True, "Base token Heart (board, objectives 32 pt, reels 48–64 pt)", "Gems.swift", "token"),
    ("VC08", "vc_gem_diamond.png", 512, 512, True, "Base token Diamond", "Gems.swift", "token"),
    ("VC09", "vc_gem_clover.png", 512, 512, True, "Base token Clover", "Gems.swift", "token"),
    ("VC10", "vc_gem_bell.png", 512, 512, True, "Base token Bell", "Gems.swift", "token"),
    ("VC11", "vc_gem_star.png", 512, 512, True, "Base token Star", "Gems.swift", "token"),
    ("VC12", "vc_special_burst.png", 512, 512, True, "Special: Stage Burst (≤82% cell; Help 64 pt)", "Items.swift", "token"),
    ("VC13", "vc_special_prism.png", 512, 512, True, "Special: Prism (≤82% cell)", "Items.swift", "token"),
    ("VC14", "vc_stage_key.png", 512, 512, True, "Stage key token (board, objectives, tutorial, Help)", "Items.swift", "token"),
    ("VC15", "vc_exit_port.png", 512, 512, True, "Key exit port, 36–48 pt", "Items.swift", "token"),
    ("VC16", "vc_crate.png", 512, 512, True, "Obstacle: crate (≤94% cell)", "Items.swift", "tile"),
    ("VC17", "vc_ice_overlay.png", 512, 512, True, "Overlay: ice shell over a token (cell size, centre clear)", "Items.swift", "tile"),
    ("VC18", "vc_chain_overlay.png", 512, 512, True, "Overlay: chains over a token (cell size)", "Items.swift", "tile"),
    ("VC19", "vc_shutter_closed.png", 512, 512, True, "Obstacle: closed shutter (cell size)", "Items.swift", "tile"),
    ("VC20", "vc_switch.png", 512, 512, True, "Board switch pedal (≤80% cell, under a token)", "Items.swift", "tile"),
    ("VC21", "vc_baffle.png", 512, 512, True, "Permanent wall / baffle (cell size)", "Items.swift", "tile"),
    ("VC22", "vc_velvet_plate.png", 512, 512, True, "Velvet plate floor tile under tokens (cell size)", "Items.swift", "tile"),
    ("VC23", "vc_daily_machine.png", 1536, 1536, True, "Daily Encore cabinet (up to 320 pt; Home 56 pt)", "Machine.swift", "machine"),
    ("VC24", "vc_curtain_left.png", 768, 2048, True, "Left curtain layer for turn / transitions (anchor left edge)", "Items.swift", "curtainL"),
    ("VC25", "vc_curtain_right.png", 768, 2048, True, "Right curtain layer for turn / transitions (anchor right edge)", "Items.swift", "curtainR"),
    ("VC26", "vc_spotlight_beam.png", 1024, 1024, True, "Spotlight beam overlay (≤220 pt wide, opacity ≤0.25, additive)", "Items.swift", "fx"),
    ("VC27", "vc_world_01.png", 1290, 2796, False, "World 1 Ruby Rehearsal background (+Home, Daily, preview)", "Backgrounds.swift", BG),
    ("VC28", "vc_world_02.png", 1290, 2796, False, "World 2 Keyhole Wings background", "BackgroundWorlds.swift", BG),
    ("VC29", "vc_world_03.png", 1290, 2796, False, "World 3 Prop Workshop background", "BackgroundWorlds.swift", BG),
    ("VC30", "vc_world_04.png", 1290, 2796, False, "World 4 Frosted Gallery background", "BackgroundWorlds.swift", BG),
    ("VC31", "vc_world_05.png", 1290, 2796, False, "World 5 Chain Loft background", "BackgroundWorlds.swift", BG),
    ("VC32", "vc_world_06.png", 1290, 2796, False, "World 6 Clockwork Curtains background", "BackgroundWorlds.swift", BG),
    ("VC33", "vc_world_07.png", 1290, 2796, False, "World 7 Split Stage background", "BackgroundWorlds.swift", BG),
    ("VC34", "vc_world_08.png", 1290, 2796, False, "World 8 Moonlit Rotation background", "BackgroundWorlds.swift", BG),
    ("VC35", "vc_world_09.png", 1290, 2796, False, "World 9 Grand Cascade background (+Final Bow)", "BackgroundWorlds.swift", BG),
    ("VC36", "vc_app_icon.png", 1024, 1024, False, "App icon source (AppIcon.appiconset universal 1024)", "Items.swift", "icon"),
    ("VC37", "vc_vell_portrait.png", 768, 768, True, "Vell bust portrait (Gameplay/Turn Preview 40 pt, Credits 88 pt)", "Vell.swift", "portrait"),
    ("VC38", "vc_hint_ticket.png", 512, 512, True, "Hint Ticket icon (24–56 pt)", "Items.swift", "token"),
    ("VC39", "vc_result_crest.png", 1024, 512, True, "Result crest behind stars/title (≤200×100 pt)", "Items.swift", "token"),
    ("VC40", "vc_turn_crown.png", 512, 512, True, "Stage Turn emblem (40–56 pt), live gauge sits under the arc", "Items.swift", "token"),
]

# Calm UI-safe region per background (normalized insets from each edge), taken from the ArtForge layout
# constants (drape widths, prop extents, valance/roof depth) and checked visually on the contact sheet.
SAFE_INSETS = {
    "VC01": {"top": 0.65, "left": 0.06, "bottom": 0.02, "right": 0.06},  # lower 35% text/CTA band (hero occupies the middle)
    "VC02": {"top": 0.40, "left": 0.06, "bottom": 0.03, "right": 0.06},  # below the hanging tokens: demo board + text
    "VC03": {"top": 0.65, "left": 0.08, "bottom": 0.02, "right": 0.08},  # lower 35% text band
    "VC27": {"top": 0.12, "left": 0.19, "bottom": 0.02, "right": 0.19},
    "VC28": {"top": 0.11, "left": 0.21, "bottom": 0.02, "right": 0.21},
    "VC29": {"top": 0.10, "left": 0.24, "bottom": 0.02, "right": 0.24},
    "VC30": {"top": 0.10, "left": 0.22, "bottom": 0.02, "right": 0.22},
    "VC31": {"top": 0.12, "left": 0.23, "bottom": 0.02, "right": 0.23},
    "VC32": {"top": 0.11, "left": 0.23, "bottom": 0.02, "right": 0.23},
    "VC33": {"top": 0.10, "left": 0.25, "bottom": 0.02, "right": 0.25},
    "VC34": {"top": 0.20, "left": 0.17, "bottom": 0.02, "right": 0.17},
    "VC35": {"top": 0.20, "left": 0.19, "bottom": 0.02, "right": 0.19},
}

REEL_TARGET = [(0.17, 0.36, 0.36, 0.72), (0.405, 0.595, 0.36, 0.72), (0.64, 0.83, 0.36, 0.72)]

NOTES = {
    "VC01": "Vell (weight on one leg) grips the edge of a crimson curtain with a wrapped gloved fist, baton raised in the other hand, in front of a round brass stage ring and turntable; five tokens float in the upper half; lower 35% calm plum for text/CTA; top band free for the title.",
    "VC02": "Macro plum velvet with huge soft folds; five tokens hang on thin gold cables along the upper edges; empty centre for the live 3×3 demo board.",
    "VC03": "Vell (upper-left, on a brass ledge) points the baton, held in a wrapped fist, at an empty rotating brass frame with motion arcs; open gloved hand on the other side; drapes swept by the turn; warm spotlight from the right; lower 35% calm.",
    "VC04": "Full body, welcoming contrapposto: weight on the screen-left leg (hip raised, shoulders counter-tilted), relaxed right leg with a bent knee; open three-finger-and-thumb gloved palm; baton raised in a fist that wraps it. Same rig/face/hat as all Vell assets.",
    "VC05": "Theatrical bow: torso bent forward 46° from the hips (foreshortened), head lowered in front of the chest with happy closed eyes, hat points flopping forward, one arm sweeping open to the audience with a gesturing glove, baton hand tucked behind the back (baton visible beside the hip), back leg crossed behind. No confetti/stars/text.",
    "VC06": "Thoughtful warm smile (inner brows lifted), head tilt, supportive open palm facing the viewer at shoulder height; baton lowered at the side in a wrapped fist; relaxed contrapposto.",
    "VC07": "Ruby heart, symmetric bevel facets, narrow gold rim, two readable lobes.",
    "VC08": "Sapphire rhombus, four large bevel facets + small table, gold rim.",
    "VC09": "Emerald four-leaf clover, leaves cut to 90° wedges so dark seams separate them; short stem lower-right; gold boss.",
    "VC10": "Amber-gold stage bell, visible clapper in a burgundy-lit mouth, gold lip ring and hanging loop.",
    "VC11": "Amethyst five-point star with ridge facets and gold rim.",
    "VC12": "Plum-metal popper sphere with gold ribs, crimson faceted crystal and a short glowing fuse. No skull/weapon.",
    "VC13": "Pentagonal prism with five gem-coloured bevel facets and an iridescent table in a brass prong setting.",
    "VC14": "Gold key, round bow with plum enamel inset, two bold teeth (readable at 32 pt); drawn at 45° to use the square cell.",
    "VC15": "Small open gold arch with a velvet swag and drawn-back drapes, warm glowing depth, brass threshold. No key, no arrow.",
    "VC16": "Square dark-wood crate, brass corner brackets and a diagonal brace; orthographic, fills ~93% of the cell.",
    "VC17": "Frosted square shell, thin blue cracks, centre alpha fades to ~0 so the token underneath stays readable.",
    "VC18": "Two bronze chains crossing corner to corner with a round gold clasp; ~74% of the cell transparent.",
    "VC19": "Closed crimson louvred stage shutter with brass guide rails, housing and bottom bar; square silhouette.",
    "VC20": "Round brass pedal (unpressed) in a recessed plum velvet niche; no digits.",
    "VC21": "Matte black-plum metal plate with an embossed cross-brace, quiet highlights, eight gold rivets.",
    "VC22": "Flat plum velvet tile with crimson rope piping and one gold diamond stitch; reads as a floor plate under tokens.",
    "VC23": "Symmetric red-plum cabinet, brass/gold frame, marquee bulbs, Vell's hat on a crest; exactly three EMPTY cream windows of equal width; no symbols, text, buttons or lever. reelRects measured from pixels.",
    "VC24": "Heavy crimson velvet panel on brass rings, gold fringe on the leading edge, rope + gold tassel; opaque along the left anchor edge by design.",
    "VC25": "Mirror of VC24 geometry (right anchor edge); shading recomputed so the key light still comes from the upper-left.",
    "VC26": "Soft golden cone with a clearer centre and brighter rims, floor pool and dust motes; no lamp.",
    "VC36": "Big Vell hat crowning a sapphire diamond inside a golden quarter-turn arc pair on plum velvet; full-bleed RGB, square corners.",
    "VC37": "Separate bust drawing (not a downscale): same rig, headScale, face and costume, framed so the skin face oval is 53% of the frame width. In this tight framing the soft hat points flop down over the ears (left longer, right shorter) and the centre point folds over to the right, so all three points with their bells and the collar stay inside the frame; baton rises beside the right shoulder, clear of the face; shoulders fade out below the collar.",
    "VC38": "Cream ticket with two side notches, thin gold inset border, embossed faceted sapphire star, perforation dots; no text.",
    "VC39": "Symmetric brass cartouche with scroll ends, two gold laurel branches and one red ribbon; empty dark-plum velvet field.",
    "VC40": "Mini three-pointed Vell hat resting on a brass quarter-turn arc with end caps; empty space below the arc for the live gauge.",
}
WORLD_NOTES = {
    "VC27": "Ruby Rehearsal: tied-back ruby drapes, scalloped valance with gold fringe, brass stage-ring fragments only at the edges, warm twin spotlights, footlight shells at the bottom corners.",
    "VC28": "Keyhole Wings: lacquered plum side columns with glowing keyhole cut-outs in gold escutcheons, plum drapes, single overhead spot.",
    "VC29": "Prop Workshop: wooden prop racks with crates and brass boxes at both edges, burgundy drapes and valance, warm work light.",
    "VC30": "Frosted Gallery: velvet balcony fronts with brass balusters and ice-crystal clusters at the edges, cold blue edge light vs warm centre.",
    "VC31": "Chain Loft: bronze truss, pulleys, hanging chains with brass counterweights/hooks along the top edges, ruby drapes.",
    "VC32": "Clockwork Curtains: bronze/brass gears cut by the frame edges, louvred crimson stage shutters at the upper corners, crimson drapes.",
    "VC33": "Split Stage: two side pavilions (velvet domes, gold columns, inner tied drapes, lamps) and a warm brass floor, calm centre.",
    "VC34": "Moonlit Rotation: roof trusses and skylight with a small moon (top-right), cold blue light only at the edges, burgundy drapes, faded brass ring fragments.",
    "VC35": "Grand Cascade: golden proscenium arch and fluted pilasters with marquee bulbs, keystone gem, layered crimson/burgundy drapes, coffered dark ceiling.",
}


def load(path):
    im = Image.open(path)
    im.load()
    return im


def content_rect(alpha, thr=8):
    ys, xs = np.where(alpha > thr)
    if len(xs) == 0:
        return None
    h, w = alpha.shape
    return {"x": round(xs.min() / w, 4), "y": round(ys.min() / h, 4),
            "w": round((xs.max() + 1 - xs.min()) / w, 4), "h": round((ys.max() + 1 - ys.min()) / h, 4)}


def measure_reels(rgba):
    a = rgba.astype(np.int32)
    R, G, B, A = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    cream = ((A > 250) & (R > 215) & (G > 198) & (B > 165) & ((R - B) < 70) & ((R - G) < 35)).astype(np.int32)
    k = 7  # erosion radius: removes thin gold highlights, keeps solid windows
    c = np.pad(cream, ((k + 1, k), (k + 1, k))).cumsum(0).cumsum(1)
    box = c[2 * k + 1:, 2 * k + 1:] - c[:-2 * k - 1, 2 * k + 1:] - c[2 * k + 1:, :-2 * k - 1] + c[:-2 * k - 1, :-2 * k - 1]
    core = box == (2 * k + 1) ** 2
    h, w = core.shape
    xs = np.where(core.sum(axis=0) > 50)[0]
    if len(xs) == 0:
        return []
    runs, s, p = [], xs[0], xs[0]
    for x in xs[1:]:
        if x != p + 1:
            runs.append((s, p))
            s = x
        p = x
    runs.append((s, p))
    rects = []
    for x0, x1 in runs:
        ys = np.where(core[:, x0:x1 + 1].any(axis=1))[0]
        rects.append({"x": round((x0 - k) / w, 4), "y": round((ys.min() - k) / h, 4),
                      "w": round((x1 + 1 - x0 + 2 * k) / w, 4), "h": round((ys.max() + 1 - ys.min() + 2 * k) / h, 4)})
    return rects


def measure_face(rgba):
    a = rgba.astype(np.int32)
    R, G, B, A = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    skin = (A > 250) & (R > 190) & ((R - G) >= 22) & ((R - G) <= 48) & ((G - B) >= 12) & ((G - B) <= 38) & (B > 125) & (B < 212)
    # keep the dominant blob around the image centre column
    h, w = skin.shape
    cols = np.where(skin.sum(axis=0) > 25)[0]
    rows = np.where(skin.sum(axis=1) > 25)[0]
    if len(cols) == 0:
        return None
    return {"x": round(cols.min() / w, 4), "y": round(rows.min() / h, 4),
            "w": round((cols.max() + 1 - cols.min()) / w, 4), "h": round((rows.max() + 1 - rows.min()) / h, 4)}


def column_artifacts(rgb):
    """Detect thin bright/dark vertical lines in the calm centre (render artifacts)."""
    h, w, _ = rgb.shape
    band = rgb[int(h * 0.1):int(h * 0.6), int(w * 0.3):int(w * 0.7)].astype(np.float32).sum(axis=2).mean(axis=0)
    d = np.abs(band[1:-1] - (band[:-2] + band[2:]) / 2)
    return float(d.max()) if len(d) else 0.0


def check(entry):
    vid, fname, W, H, alpha, role, src, rule = entry
    path = os.path.join(ART, fname)
    res = {"id": vid, "file": fname, "issues": [], "metrics": {}}
    if not os.path.exists(path):
        res["issues"].append("missing")
        return res, None
    im = load(path)
    res["size"] = im.size
    if im.size != (W, H):
        res["issues"].append(f"size {im.size} != {(W, H)}")
    has_alpha = im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info)
    res["hasAlpha"] = has_alpha
    if not alpha:
        if has_alpha:
            res["issues"].append("opaque asset has an alpha channel")
        rgb = np.asarray(im.convert("RGB"))
        res["metrics"]["transparentPixelRatio"] = 0.0
        if rule == BG:
            art = column_artifacts(rgb)
            res["metrics"]["columnArtifact"] = round(art, 1)
            if art > 40:
                res["issues"].append(f"column artifact {art:.1f}")
        return res, im
    if not has_alpha:
        res["issues"].append("alpha asset has no alpha channel")
        return res, im
    rgba = np.asarray(im.convert("RGBA"))
    A = rgba[..., 3]
    h, w = A.shape
    tr = float((A == 0).mean())
    res["metrics"]["transparentPixelRatio"] = round(tr, 4)
    res["metrics"]["contentRect"] = content_rect(A)
    # corners must be fully transparent (8×8)
    corners = [A[:8, :8], A[:8, -8:], A[-8:, :8], A[-8:, -8:]]
    if any(c.max() > 0 for c in corners):
        res["issues"].append("opaque corner")
    # no black/white opaque boxes in the corners (checkerboard / matte check)
    for c in [rgba[:24, :24], rgba[:24, -24:], rgba[-24:, :24], rgba[-24:, -24:]]:
        op = c[..., 3] > 200
        if op.mean() > 0.5:
            rgbc = c[..., :3][op]
            if (rgbc.max(axis=1) < 16).mean() > 0.9 or (rgbc.min(axis=1) > 240).mean() > 0.9:
                res["issues"].append("black/white corner box")
    # clipped edges: outer 2-px border must be transparent (curtains may touch their anchor edge)
    border = {"top": A[:2, :], "bottom": A[-2:, :], "left": A[:, :2], "right": A[:, -2:]}
    allowed = {"curtainL": {"left"}, "curtainR": {"right"}}.get(rule, set())
    for side, b in border.items():
        if side in allowed:
            continue
        if b.max() > 10:
            res["issues"].append(f"content touches {side} edge")
    if tr < 0.03:
        res["issues"].append(f"transparent ratio too low ({tr:.3f})")
    if rule == "machine":
        reels = measure_reels(rgba)
        res["metrics"]["reelRects"] = reels
        if len(reels) != 3:
            res["issues"].append(f"expected 3 cream windows, measured {len(reels)}")
        else:
            widths = [r["w"] for r in reels]
            if max(widths) - min(widths) > 0.004:
                res["issues"].append("window widths differ")
            for r, (x0, x1, y0, y1) in zip(reels, REEL_TARGET):
                if abs(r["x"] - x0) > 0.01 or abs(r["x"] + r["w"] - x1) > 0.01 or abs(r["y"] - y0) > 0.01 or abs(r["y"] + r["h"] - y1) > 0.01:
                    res["issues"].append("window off target geometry")
    if rule == "portrait":
        res["metrics"]["faceRectMeasured"] = measure_face(rgba)
    if rule == "tile" and vid == "VC17":
        centre = A[h // 2 - 40:h // 2 + 40, w // 2 - 40:w // 2 + 40]
        res["metrics"]["centreAlphaMean"] = round(float(centre.mean()) / 255, 3)
        if centre.mean() > 0.2 * 255:
            res["issues"].append("ice centre not clear")
    return res, im


def anchor_for(entry, metrics):
    vid, _, _, _, alpha, _, _, rule = entry
    cr = metrics.get("contentRect")
    if rule in ("figure",) and cr:
        return {"x": round(cr["x"] + cr["w"] / 2, 4), "y": round(cr["y"] + cr["h"], 4), "meaning": "feet / ground contact (bottom-centre of content)"}
    if rule == "curtainL":
        return {"x": 0.0, "y": 0.0, "meaning": "top-left; pin to the left screen edge"}
    if rule == "curtainR":
        return {"x": 1.0, "y": 0.0, "meaning": "top-right; pin to the right screen edge"}
    if vid == "VC26" and cr:
        return {"x": 0.5, "y": round(cr["y"], 4), "meaning": "beam apex"}
    if vid == "VC40":
        return {"x": 0.5, "y": 0.5, "meaning": "centre; live gauge sits below the arc (y > 0.62)"}
    return {"x": 0.5, "y": 0.5, "meaning": "centre"}


def contact_sheet(results_imgs):
    cell, pad = 260, 16
    cols = 8
    n = len(results_imgs)
    rows = (n + cols - 1) // cols
    readability_ids = ["VC07", "VC08", "VC09", "VC10", "VC11", "VC12", "VC13", "VC14", "VC15", "VC16", "VC17", "VC18", "VC19", "VC20", "VC21", "VC22", "VC38", "VC40", "VC37"]
    W = cols * (cell + pad) + pad
    H = rows * (cell + pad + 22) + pad + 2 * (80 + 40) + 60
    sheet = Image.new("RGB", (W, H), (0x16, 0x0C, 0x1D))
    d = ImageDraw.Draw(sheet)
    lookup = {}
    for i, (res, im) in enumerate(results_imgs):
        if im is None:
            continue
        lookup[res["id"]] = im
        r, c = divmod(i, cols)
        x0, y0 = pad + c * (cell + pad), pad + r * (cell + pad + 22)
        th = im.convert("RGBA").copy()
        th.thumbnail((cell, cell), Image.LANCZOS)
        ox, oy = x0 + (cell - th.width) // 2, y0 + (cell - th.height) // 2
        sheet.paste(th, (ox, oy), th)
        ok = not res["issues"]
        d.text((x0, y0 + cell + 4), f'{res["id"]} {"OK" if ok else "FAIL"}', fill=(0xFF, 0xF3, 0xDC) if ok else (0xF0, 0x7D, 0x8C))
    # readability rows: 80 px (≈40 pt @2x) on a plum board cell and on the cream reel colour
    y = pad + rows * (cell + pad + 22) + 10
    d.text((pad, y), "Readability @ 80 px (40 pt @2x): board cell (Panel) and cream reel", fill=(0xCD, 0xB5, 0xCB))
    y += 22
    for row, bgcol in enumerate([(0x35, 0x1B, 0x36), (0xFF, 0xF3, 0xDC)]):
        x = pad
        for vid in readability_ids:
            im = lookup.get(vid)
            if im is None:
                continue
            d.rounded_rectangle([x - 4, y - 4, x + 84, y + 84], radius=12, fill=bgcol, outline=(0xAF, 0x78, 0x3B))
            if vid in ("VC17", "VC18", "VC20", "VC22"):
                gem = lookup.get("VC08")
                under = gem.convert("RGBA").resize((70, 70), Image.LANCZOS)
                if vid in ("VC20", "VC22"):
                    base = im.convert("RGBA").resize((80, 80), Image.LANCZOS)
                    sheet.paste(base, (x, y), base)
                    sheet.paste(under, (x + 5, y + 5), under)
                else:
                    sheet.paste(under, (x + 5, y + 5), under)
                    top = im.convert("RGBA").resize((80, 80), Image.LANCZOS)
                    sheet.paste(top, (x, y), top)
            else:
                t = im.convert("RGBA").resize((80, 80), Image.LANCZOS)
                sheet.paste(t, (x, y), t)
            x += 96
        y += 110
    sheet.save(SHEET, optimize=True)
    return SHEET


def main():
    write_manifest = "--write-manifest" in sys.argv
    results = []
    for e in CATALOG:
        res, im = check(e)
        results.append((res, im))
    # table
    print(f'{"ID":5} {"file":28} {"size":>11} {"alpha":5} {"transp":>7}  status')
    fails = 0
    for (res, _), e in zip(results, CATALOG):
        size = "x".join(map(str, res.get("size", ("-", "-"))))
        tr = res["metrics"].get("transparentPixelRatio", 0)
        status = "pass" if not res["issues"] else "FAIL: " + "; ".join(res["issues"])
        fails += bool(res["issues"])
        print(f'{res["id"]:5} {res["file"]:28} {size:>11} {str(res.get("hasAlpha", "-")):5} {tr:7.3f}  {status}')
    for res, _ in results:
        if res["id"] == "VC23" and "reelRects" in res["metrics"]:
            print("VC23 measured reelRects:", json.dumps(res["metrics"]["reelRects"]))
        if res["id"] == "VC37":
            print("VC37 measured skin faceRect:", json.dumps(res["metrics"].get("faceRectMeasured")))
    print(f"\n{len(CATALOG) - fails}/{len(CATALOG)} assets pass")
    if "--no-sheet" not in sys.argv:
        print("contact sheet:", contact_sheet(results))
    if write_manifest:
        meta = {}
        mp = os.path.join(RENDERS, "meta.json")
        if os.path.exists(mp):
            meta = json.load(open(mp))
        out = []
        for (res, im), e in zip(results, CATALOG):
            vid, fname, W, H, alpha, role, src, rule = e
            m = res["metrics"]
            item = {
                "id": vid,
                "file": fname,
                "displayRole": role,
                "pixelWidth": W,
                "pixelHeight": H,
                "hasAlpha": bool(res.get("hasAlpha")),
                "transparentPixelRatio": m.get("transparentPixelRatio", 0.0),
                "contentRect": m.get("contentRect") or {"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0},
                "anchor": anchor_for(e, m),
                "safeInsets": SAFE_INSETS.get(vid),
                "provenance": PROVENANCE,
                "sourcePath": SRC + src,
                "nativeRenderPath": "Production/ArtSources/renders/" + fname,
                "renderCommand": f"cd Production/ArtSources/ArtForge && swift run -c release ArtForge {vid}",
                "producedAt": PRODUCED_AT,
                "qaStatus": "pass" if not res["issues"] else "fail: " + "; ".join(res["issues"]),
                "notes": NOTES.get(vid) or WORLD_NOTES.get(vid, ""),
            }
            if rule == BG:
                item["safeInsetsMethod"] = "layout constants from ArtForge sources (drape/prop extents, valance/roof depth), verified visually; decor such as faded ring fragments or light haze may extend slightly inside"
                if vid in ("VC01", "VC03"):
                    item["textSafeRegion"] = {"top": 0.65, "left": 0.08, "bottom": 0.02, "right": 0.08, "meaning": "lower 35% calm plum reserved for text and CTA; hero occupies the middle band"}
            if vid == "VC23":
                item["reelRects"] = m.get("reelRects")
                item["reelRectsTarget"] = [{"x": x0, "y": y0, "w": round(x1 - x0, 4), "h": round(y1 - y0, 4)} for (x0, x1, y0, y1) in REEL_TARGET]
                item["reelRectsMethod"] = "cream-pixel mask eroded 7 px (drops thin gold highlights), column runs → bbox, re-expanded 7 px"
            if vid == "VC37":
                rnd = lambda r: {k: round(v, 4) for k, v in r.items()} if r else None
                item["faceRect"] = rnd(meta.get("VC37", {}).get("faceRect"))
                item["faceRectWithEars"] = rnd(meta.get("VC37", {}).get("faceRectWithEars"))
                item["faceRectMeasuredSkin"] = m.get("faceRectMeasured")
                item["faceRectMethod"] = "faceRect = rig geometry of the skin face oval (hat band to chin); cross-checked against a skin-colour pixel mask"
            out.append(item)
        os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
        with open(MANIFEST, "w") as f:
            json.dump(out, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print("manifest:", MANIFEST)
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
