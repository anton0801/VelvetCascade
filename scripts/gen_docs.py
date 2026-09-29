#!/usr/bin/env python3
"""Генерирует отчётные документы из фактических данных проекта:
docs/IMPLEMENTATION_CHECKLIST.md, docs/SCREEN_MATRIX.md, docs/MEDIA_AUDIT.md,
docs/LEVEL_BALANCE_REPORT.md, docs/LEVEL_TRACES.md.
Статусы вычисляются из манифестов, отчёта LevelForge, скриншотов и исходников — не вручную."""
import json, os, re, glob, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def P(*a): return os.path.join(ROOT, *a)
def load(p, default=None):
    try:
        with open(P(p)) as f: return json.load(f)
    except Exception: return default

TODAY = datetime.date.today().isoformat()
art = load('VelvetCascade/Resources/Manifests/art_manifest.json', [])
audio_m = load('VelvetCascade/Resources/Manifests/audio_manifest.json', {'entries': []})
audio = audio_m.get('entries', [])
forge = load('Production/LevelForge/forge_report.json', [])
swift_src = ''
for f in glob.glob(P('VelvetCascade', '**', '*.swift'), recursive=True):
    swift_src += open(f).read()
shots = sorted(glob.glob(P('docs', 'screenshots', '*', '*.png')))
shot_devices = sorted({os.path.basename(os.path.dirname(s)) for s in shots} - {'components', 'moments'})

# ---------------------------------------------------------------- screens
SCREENS = [
    ('01', 'Welcome', 'onboarding/welcome', 'WelcomeView', ['welcome']),
    ('02', 'Match Tutorial', 'onboarding/match', 'MatchTutorialView', ['match']),
    ('03', 'Rotation Tutorial', 'onboarding/rotate', 'RotationTutorialView', ['rotate']),
    ('04', 'Home', 'home', 'HomeView', ['home_new', 'home_resume', 'home_complete']),
    ('05', 'Worlds', 'worlds', 'WorldsView', ['worlds_new', 'worlds_mid', 'worlds_all']),
    ('06', 'World Map', 'worlds/:worldID', 'WorldMapView', ['map_mid', 'map_locked']),
    ('07', 'Level Brief', 'levels/:levelID/brief', 'LevelBriefView', ['brief_new', 'brief_replay', 'brief_invalid']),
    ('08', 'Gameplay', 'game/:runID', 'GameplayView', ['game_6x6', 'game_8x8', 'game_ring', 'game_split', 'game_q1', 'game_q2', 'game_q3', 'game_moves1', 'game_hc', 'game_hint', 'game_tutorial']),
    ('09', 'Turn Preview', 'game/:runID/turn-preview', 'GameplayView.previewSheet', ['preview_key', 'preview_split']),
    ('08*', 'Gameplay moments', 'game/:runID', 'GameplayView (mid-animation)', ['moment_rotation', 'moment_key_extraction', 'moment_cascade']),
    ('10', 'Intermission', 'game/:runID/pause', 'IntermissionPanel', ['pause', 'restart_confirm']),
    ('11', 'Curtain Call', 'results/win/:runID', 'CurtainCallView', ['win_3', 'win_2', 'win_1_repeat', 'win_20', 'win_180', 'win_cap']),
    ('12', 'One More Act', 'results/fail/:runID', 'OneMoreActView', ['fail']),
    ('13', 'New Theatre', 'worlds/unlocked/:worldID', 'NewTheatreView', ['new_theatre', 'final_bow']),
    ('14', 'Daily Encore', 'daily', 'DailyEncoreView', ['daily_ready', 'daily_collected', 'daily_restored', 'daily_error']),
    ('15', 'Encore Reward', 'daily/reward/:receiptID', 'EncoreRewardView', ['reward_mixed', 'reward_pair', 'reward_triple', 'reward_cap']),
    ('16', 'Stage Handbook', 'help', 'StageHandbookView', ['handbook_' + t for t in ['matches', 'stageTurn', 'curtainSweep', 'keysExits', 'velvetPlates', 'crates', 'ice', 'chains', 'shutters', 'specials', 'dailyEncore']]),
    ('17', 'Settings', 'settings', 'SettingsView', ['settings']),
    ('18', 'Credits', 'settings/credits', 'CreditsView', ['credits']),
    ('19', 'Import Review', 'settings/import/review', 'ImportReviewView', ['import_valid', 'import_run']),
    ('20', 'Recovery', 'shared/error', 'RecoveryView', ['recovery_save', 'recovery_import', 'recovery_level', 'recovery_restore']),
    ('21', 'Encore Rules', 'daily/rules', 'EncoreRulesView', ['rules']),
    ('22', 'Reset Confirmation', 'settings/reset', 'ResetConfirmationView', ['reset']),
]

def shot_path(dev, fx):
    p = P('docs', 'screenshots', dev, fx + '.png')
    if fx.startswith('moment_'):
        p = P('docs', 'screenshots', 'moments', fx + '.png')
    return os.path.relpath(p, P('docs')) if os.path.exists(p) else None

lines = ['# Screen Matrix — Velvet Cascade', '',
         f'Generated {TODAY} by `scripts/gen_docs.py` from actual screenshots of the working Debug build '
         '(DEBUG fixtures on in-memory repositories; `scripts/capture_all.sh`). Devices/labels: ' + ', '.join(shot_devices) + '.', '',
         'Status «captured» means a real screenshot of the running app exists for that variant; visual review notes are in docs/HANDOFF.md. '
         'No mockups are used as screenshots.', '']
for dev in shot_devices:
    lines += [f'## {dev}', '', '| # | Screen | Route | View | Variant | Screenshot | Status |', '|---|---|---|---|---|---|---|']
    for num, name, route, view, fxs in SCREENS:
        for fx in fxs:
            sp = shot_path(dev, fx)
            lines.append(f'| {num} | {name} | `{route}` | `{view}` | {fx} | ' + (f'[png]({sp})' if sp else '—') + f' | {"captured" if sp else "missing"} |')
    lines.append('')
gal = sorted(glob.glob(P('docs', 'screenshots', '*', 'gallery_*.png')))
lines += ['## Component gallery (UI01–UI20, DEBUG)', '', 'States normal / pressed / disabled / focused / committing where applicable:', '']
for g in gal:
    lines.append(f'- [{os.path.relpath(g, P("docs"))}]({os.path.relpath(g, P("docs"))})')
lines.append('')
open(P('docs', 'SCREEN_MATRIX.md'), 'w').write('\n'.join(lines) + '\n')

# ---------------------------------------------------------------- media audit
lines = ['# Media Audit — Velvet Cascade', '', f'Generated {TODAY} by `scripts/gen_docs.py`.', '',
         '## Art (40)', '', '| ID | File | Size | Alpha | Source | Exported | Integrated (referenced in code) | QA | Note |', '|---|---|---|---|---|---|---|---|---|']
art_ok = 0
for e in art:
    stem = os.path.splitext(e['file'])[0]
    exported = os.path.exists(P('VelvetCascade', 'Resources', 'Art', e['file']))
    integrated = ('"' + stem + '"') in swift_src or stem in swift_src
    # Фоны миров подключаются шаблоном String(format: "vc_world_%02d", world).
    if stem.startswith('vc_world_') and 'vc_world_%02d' in swift_src:
        integrated = True
    if e['id'] == 'VC36':
        integrated = os.path.exists(P('VelvetCascade', 'Assets.xcassets', 'AppIcon.appiconset', e['file']))
    qa = e.get('qaStatus', '?')
    ok = exported and integrated and qa == 'pass'
    art_ok += ok
    lines.append(f"| {e['id']} | `{e['file']}` | {e['pixelWidth']}×{e['pixelHeight']} | {'yes' if e['hasAlpha'] else 'no'} | procedural CoreGraphics (ArtForge) | {'yes' if exported else 'NO'} | {'yes' if integrated else 'NO'} | {qa} | {'' if ok else 'check'} |")
lines += ['', f'Art: {art_ok}/40 exported + integrated + QA pass. Production method: procedural vector/CoreGraphics (no image model available); see docs/ART_PRODUCTION.md for quality limitations.', '',
          '## Audio (44)', '', '| ID | Runtime file | Bus | Provider | Model | QA | Integrated | Missing / note |', '|---|---|---|---|---|---|---|---|']
audio_real = 0
for e in audio:
    stem = os.path.splitext(e['runtimeFile'])[0]
    integrated = ('"' + stem + '"') in swift_src
    real = e['provider'].startswith('ElevenLabs')
    audio_real += real
    note = '' if real else 'procedural substitute — ElevenLabs file missing'
    lines.append(f"| {e['id']} | `{e['runtimeFile']}` | {e['bus']} | {e['provider']} | {e.get('model') or '—'} | {e.get('qaStatus', '?')} | {'yes' if integrated else 'NO'} | {note} |")
lines += ['', f'Audio: {audio_real}/44 produced by ElevenLabs; {44 - audio_real} procedural substitutes. Release readiness per spec requires 44 approved ElevenLabs files and human listening QA.', '']
open(P('docs', 'MEDIA_AUDIT.md'), 'w').write('\n'.join(lines) + '\n')

# ---------------------------------------------------------------- levels
recs = {r['id']: r for r in forge}
lines = ['# Level Balance Report — Velvet Cascade', '', f'Generated {TODAY} from `Production/LevelForge/forge_report.json` (LevelForge build).', '',
         'Method: each brief → deterministic layout (shape mask, obstacles, keys/exits, plates, switches) → beam-search solver on the same Domain engine '
         '(finds a winning `solutionTrace`, replayed with per-action state hashes) → automated bot that does NOT peek at future refills (2 shared refill samples per candidate move) '
         'plays 24 times → win rate compared with a target band per world. If outside the band: targets ×1.2 / key distance / plates toward edges / moves (−10%, floor 80% of brief) '
         'for too easy; key distance −1 / moves (+12%, ≤150%) / targets ×0.9 for too hard. Every change is logged below. '
         '**Bot win rate is an automated proxy, not a human playtest. No manual playtest of the 180 levels was performed.**', '',
         '| ID | Title | Shape | Moves brief→final | Targets × | Solver moves (turns) | Required turns | Bot win % | Status | Adjustments |', '|---|---|---|---|---|---|---|---|---|---|']
for i in range(1, 181):
    r = recs.get(i)
    if not r:
        lines.append(f'| {i} | — | — | — | — | — | — | — | missing | |')
        continue
    adj = '; '.join(r['adjustments']) if r['adjustments'] else '—'
    lines.append(f"| {i} | {r['title']} | {r['shape']} | {r['briefMoves']}→{r['finalMoves']} | {r['targetScale']:.2f} | {r['solutionLength']} ({r['solutionTurns']}) | {r['requiredTurns']} ({r['turnBrief']}) | {r['botWinRate']*100:.0f} | {r['status']} | {adj} |")
ok = sum(1 for r in forge if r['status'].startswith('ok'))
inband = sum(1 for r in forge if r['status'] == 'ok')
lines += ['', f'Summary: {len(forge)} records; {ok} solved and replay-verified; {inband} inside their bot target band; {ok - inband} solved but outside the band (listed with status).', '']
open(P('docs', 'LEVEL_BALANCE_REPORT.md'), 'w').write('\n'.join(lines) + '\n')

lines = ['# Level Traces — rationale per level', '', f'Generated {TODAY}. Each level JSON (`VelvetCascade/Resources/Levels/level_XXX.json`) stores the full `solutionTrace` '
         '(Swap(from,to)/Rotate + expected state hash after every settled action). The trace is verified by `LevelForge verify` and by the app test '
         '`BundledLevelTests.testAll180LevelsValidateAndReplay`.', '',
         'Required turns («!» levels): geometric proof — an exit is active only when local gravity equals its outward direction; from q=0 gravity is Down, and each clockwise Turn advances Down→Right→Up→Left, so an exit facing Right/Up/Left needs ≥1/2/3 Turns. With Rotate forbidden no key bound to such an exit can ever be extracted, therefore the objective is unreachable without that many Turns. The stored trace demonstrates reachability of the required recharge.', '']
for i in range(1, 181):
    path = P('VelvetCascade', 'Resources', 'Levels', f'level_{i:03d}.json')
    if not os.path.exists(path):
        lines.append(f'- **{i}** — missing'); continue
    d = json.load(open(path))
    tr = d['solutionTrace']
    turns = sum(1 for t in tr if t['action'] == 'rotate')
    ports = ', '.join(f"key {p.get('keyID')}→{p['direction']}" for p in d['exitPorts']) or 'no exits'
    obj = ', '.join(o['type'] + (f" {o['color']}×{o['target']}" if o['type'] == 'collect' else '') for o in d['objectives'])
    steps = ' → '.join(('T' if t['action'] == 'rotate' else f"S({t['from']['x']},{t['from']['y']}>{t['to']['x']},{t['to']['y']})") for t in tr)
    lines.append(f"- **{i} {d['title']}** ({d['shape']}, seed {d['seed']}): objectives {obj}; exits {ports}; required turns {d['requiredTurns']} (brief {d['turnBrief']}); "
                 f"trace {len(tr)} actions, {turns} Turn(s): {steps}")
open(P('docs', 'LEVEL_TRACES.md'), 'w').write('\n'.join(lines) + '\n')

# ---------------------------------------------------------------- checklist
COMPONENTS = [('UI01', 'GoldButton', 'GoldButtonStyle'), ('UI02', 'VelvetButton', 'VelvetButtonStyle'), ('UI03', 'IconButton', 'struct IconButton'),
              ('UI04', 'TheatrePanel', 'struct TheatrePanel'), ('UI05', 'BoardFrame', 'struct BoardFrameView'), ('UI06', 'BoardCell', 'struct CellLayerView'),
              ('UI07', 'StageChargeGauge', 'struct StageChargeGauge'), ('UI08', 'GravityCompass', 'struct GravityCompass'), ('UI09', 'MovesBadge', 'struct MovesBadge'),
              ('UI10', 'ObjectiveBadge', 'struct ObjectiveBadge'), ('UI11', 'LevelNode', 'struct LevelNode'), ('UI12', 'ResultStars', 'struct ResultStars'),
              ('UI13', 'LineSparkOverlay', 'struct LineSparkOverlay'), ('UI14', 'DamageMarkers', 'struct DamageStuds'), ('UI15', 'PortAndSwitchMarks', 'struct PortView'),
              ('UI16', 'ModalScrim', 'struct ModalScrim'), ('UI17', 'ReelWindow', 'struct ReelWindow'), ('UI18', 'SparkEmitter', 'struct SparkEmitter'),
              ('UI19', 'SettingsRow', 'struct SettingsRow'), ('UI20', 'MessageState', 'struct MessageState')]
lines = ['# Implementation Checklist — Velvet Cascade', '', f'Generated {TODAY} by `scripts/gen_docs.py` from project data. Status legend: ✅ done & verified by the stated check; ⚠️ done with a stated limitation; ❌ not done.', '',
         '## 22 routes', '', '| # | Screen | Route | Implementation | Screenshot (iphone16pro) | Status |', '|---|---|---|---|---|---|']
for num, name, route, view, fxs in SCREENS:
    impl = view.split('.')[0] in swift_src
    have = sum(1 for fx in fxs if shot_path('iphone16pro', fx))
    lines.append(f'| {num} | {name} | `{route}` | `{view}` | {have}/{len(fxs)} variants | {"✅" if impl and have == len(fxs) else "⚠️"} |')
lines += ['', '## 180 levels', '']
for w in range(1, 10):
    ids = range((w - 1) * 20 + 1, w * 20 + 1)
    solved = sum(1 for i in ids if recs.get(i, {}).get('status', 'failed').startswith('ok'))
    band = sum(1 for i in ids if recs.get(i, {}).get('status') == 'ok')
    lines.append(f'- World {w}: {solved}/20 levels with JSON + verified solution trace; {band}/20 inside bot target band. Manual playtest: not performed.')
e2e = {}
for e2e_path in sorted(glob.glob(P('Production', 'LevelForge', 'e2e_part*.txt'))):
    mode = 'Reduce Motion' if 'reducemotion' in e2e_path else 'full animation'
    dev = os.path.basename(e2e_path).split('_')[2]
    for line in open(e2e_path):
        m = re.match(r'L(\d+): (.*)', line.strip())
        if m: e2e[int(m.group(1))] = f"{m.group(2)} ({dev}, {mode})"
lines += ['', '| ID | Title | JSON + trace | Verified replay | Bot band | In-app end-to-end (trace played through UI pipeline) |', '|---|---|---|---|---|---|']
for i in range(1, 181):
    r = recs.get(i, {})
    st = r.get('status', 'missing')
    ok = st.startswith('ok')
    band = '✅' if st == 'ok' else ('⚠️ ' + st.split('; ', 1)[1] if ok and '; ' in st else '❌')
    e = e2e.get(i, 'not run')
    lines.append(f"| {i} | {r.get('title', '—')} | {'✅' if ok else '❌'} | {'✅' if ok else '❌'} | {band} | {'✅ ' + e if e.startswith('won') else '⚠️ ' + e} |")
lines += ['', 'Manual (human) playtest: not performed for any level. Per-level detail: docs/LEVEL_BALANCE_REPORT.md and docs/LEVEL_TRACES.md.', '',
          '## 40 art IDs', '', f'{art_ok}/40 exported, integrated and QA-pass (procedural; see docs/MEDIA_AUDIT.md).', '',
          '| ID | File | Status |', '|---|---|---|']
for e in art:
    lines.append(f"| {e['id']} | `{e['file']}` | {'✅' if e.get('qaStatus') == 'pass' else '⚠️ ' + str(e.get('qaStatus'))} procedural |")
lines += ['',
          '## 20 code components', '', '| ID | Component | Implementation found | Status |', '|---|---|---|---|']
for cid, name, sym in COMPONENTS:
    found = sym in swift_src
    lines.append(f'| {cid} | {name} | `{sym}` | {"✅" if found else "❌"} |')
lines += ['', '## 44 audio IDs', '', f'{audio_real}/44 produced by ElevenLabs; {44 - audio_real} are labelled procedural substitutes (see docs/MEDIA_AUDIT.md, docs/AUDIO_PRODUCTION.md). Listening QA / approval: 0/44.', '',
          '| ID | File | Provider | Status |', '|---|---|---|---|']
for e in audio:
    real = e['provider'].startswith('ElevenLabs')
    lines.append(f"| {e['id']} | `{e['runtimeFile']}` | {e['provider']} | {'⚠️ technical QA pass, listening QA pending' if real else '❌ substitute (ElevenLabs Music API: 402 paid plan required)'} |")
lines.append('')
open(P('docs', 'IMPLEMENTATION_CHECKLIST.md'), 'w').write('\n'.join(lines) + '\n')
print('docs generated:', art_ok, 'art ok;', audio_real, 'audio ElevenLabs;', len(forge), 'level records')
