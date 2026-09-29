#!/usr/bin/env python3
"""Build the Memo flow map page from capture.py's screenshots.

Usage:
  python3 Scripts/flowmap/build_page.py --raw <capture out dir> --site <site dir> --build "2.1.7 (46)"

Writes <site>/index.html and <site>/img/*.jpg. Screens the simulator can't show
(Screen Time's lock screen, iOS prompts, the widget) are drawn as wireframes
from the copy in the code. Edit FLOWS below when a flow changes.
"""
import argparse, html, os, time
from PIL import Image

# A node is ("shot", id, name, note) or ("wire", name, lines, buttons, note).
# A lane is a list alternating node, arrow-label, node...; "" is an unlabeled arrow.
def S(i, name, note=""): return ("shot", i, name, note)
def W(name, lines, buttons=(), note=""): return ("wire", name, lines, buttons, note)

FLOWS = [
    {
        "id": "onboarding", "title": "Onboarding", "eyebrow": "First open",
        "text": "The short route that ships. Accounts the App Store says can't get the free trial skip both trial screens and go from the demo straight to the paywall.",
        "lanes": [
            [S("ob-welcome", "Welcome", "“The app blocker you train to unlock.”"), "Get started",
             S("ob-attribution", "Where did you find Memo?"), "pick or Skip",
             S("ob-bridge", "Bridge"), "",
             S("ob-slot", "Say you open TikTok"), "Spin",
             S("ob-slot-landed", "Lands on Chimp Test"), "Play Chimp Test",
             S("ob-game", "Chimp Test demo", "Ends on the first miss"), "",
             S("ob-game-reward", "Ticket pays out", "“Nice try…” or “You beat the chimps” first"), "See where you'd place",
             S("ob-rank", "You'd place #N", "“Chimps average 7. You remembered N.”")],
            ["→ has a free trial", S("ob-trial-free", "7 days free"), "Continue",
             S("ob-trial-reminder", "Trial reminder"), "Continue",
             S("paywall-yearly", "Paywall · Yearly", "Hard paywall; comes back if closed"), "tap Weekly",
             S("paywall-weekly", "Paywall · Weekly"), "Subscribed",
             W("Notifications prompt", ["iOS asks to send notifications", "(only when a trial reminder is set)"], ["Allow", "Don't Allow"]), "",
             S("home-0", "Home")],
            ["→ no trial for this Apple ID", S("paywall-yearly", "Paywall", "Straight from the rank step")],
        ],
    },
    {
        "id": "home", "title": "Home", "eyebrow": "Tab 1",
        "text": "Memo's charge fills with each game (3 games = 100%). Skip two days and Memo gets rained on. Home can't start a game itself; it hands off to Train or the booth.",
        "lanes": [
            [S("home-0", "0 games today"), "", S("home-1", "1 game · 33%"), "", S("home-2", "2 games · 67%"), "",
             S("home-3", "3 games · 100%"), "", S("home-rain", "Rained on", "2+ days without playing")],
            [S("home-3", "Home"), "tap Memo", S("home-memo-tap", "Memo talks")],
            [S("home-3", "Home"), "tap the charge meter", S("train", "Train tab")],
            [S("home-3", "Home"), "Pick apps to block",
             W("App picker", ["Apple's Screen Time app picker", "(system screen, can't be captured)"], ["Done"]), "",
             S("home-blocking", "Blocking on", "“Spin for your pass”")],
            [S("home-blocking", "Blocking on"), "Spin for your pass / Cheer Memo up", S("booth", "Memo's Booth", "See Unlock flow")],
        ],
    },
    {
        "id": "train", "title": "Train a game", "eyebrow": "Tab 2",
        "text": "The how-to-play screen shows only the first time a game is opened. After a game: your score, a sticker on a new best, and this week's board climbing to your rank.",
        "lanes": [
            [S("train", "Train tab"), "first time only", S("intro-chimpTest", "How to play"), "Play",
             S("play-chimpTest", "Gameplay", "Later launches start here"), "game over",
             S("result-normal", "Result · signed in", "“You're #5.”"), "Done",
             W("Rating prompt", ["“Enjoying Memo?”", "5+ games, 2+ day streak,", "once per 90 days"], ["Not Now"]), "",
             S("train", "Back on Train")],
            ["variants", S("result-pb", "Result · new best", "Sticker + Share"), "",
             S("result-out", "Result · signed out", "Memo's practice rivals"), "",
             S("result-zero", "Result · no score")],
            [S("intro-chimpTest", "How to play"), "tap ?", S("info-sheet", "About this game")],
            ["on a streak milestone", W("Streak celebration", ["7, 14, 30, 60 or 100 days", "Big flame + day count"], ["Share Achievement", "Keep Training"])],
        ],
    },
    {
        "id": "games", "title": "All six games", "eyebrow": "Train detail",
        "text": "Each game's first-open screen and what play looks like.",
        "grid": [
            ("intro-visualMemory", "Visual Memory · intro"), ("play-visualMemory", "Visual Memory · play"),
            ("intro-sequentialMemory", "Number Memory · intro"), ("play-sequentialMemory", "Number Memory · play"),
            ("intro-chimpTest", "Chimp Test · intro"), ("play-chimpTest", "Chimp Test · play"),
            ("intro-mathSpeed", "Math Sprint · intro"), ("play-mathSpeed", "Math Sprint · play"),
            ("intro-colorMatch", "Color Match · intro"), ("play-colorMatch", "Color Match · play"),
            ("intro-reactionTime", "Reaction Time · intro"), ("play-reactionTime", "Reaction Time · play"),
        ],
    },
    {
        "id": "unlock", "title": "Unlock a blocked app", "eyebrow": "The core loop",
        "text": "Opening a blocked app shows Screen Time's shield. “Train to unlock” sends a notification that opens Memo's booth. Games here never show an intro and never reach the Train result.",
        "lanes": [
            [W("Shield", ["“bruh enough TikTok”", "“train to unlock?”", "(copy changes with the day's attempts)"], ["Train to unlock", "Stay focused"]), "Train to unlock",
             W("Notification", ["Memo", "“No feed til you train”", "“Tap to spin your brain game.”"]), "tap",
             S("booth", "Memo's Booth"), "Spin → Play",
             S("booth-game", "Game, unlock mode", "Target bar on top"), "hit the target",
             S("cash-out", "Unlock earned", "Cash out or Keep going"), "Cash out",
             S("unlocked-ticket", "Unlocked", "Minutes start counting down"), "",
             S("unlocked-rank", "Where you'd place", "“Go scroll” asks for a rating from the 3rd unlock")],
            [S("booth-game", "Game"), "missed the target", S("denied", "Denied"), "Try again → miss again",
             S("denied-2", "Denied · 2nd time", "“I really need it” appears"), "I really need it",
             S("escape-hatch", "Breath pause", "15 s, then 2 minutes")],
            ["8.5%, once a day", S("free-pass", "Free pass", "No game; 10 minutes")],
        ],
    },
    {
        "id": "compete", "title": "Compete", "eyebrow": "Tab 3",
        "text": "Weekly Game Center boards per game, plus Streak and Focus. The climb button sends you to the game that moves you up.",
        "lanes": [
            [S("compete", "Focus league"), "pick a board", S("compete-chimp", "Chimp Test board"), "", S("compete-streak", "Streak board"), "", S("compete-sparse", "Quiet week")],
            ["signed out", W("Game Center Required", ["“Sign in via Settings → Game Center”", "(no button)"])],
        ],
    },
    {
        "id": "insights", "title": "Insights", "eyebrow": "Tab 4",
        "text": "This week's phone time from Screen Time. Tap a day for its breakdown.",
        "lanes": [
            [S("insights", "Week"), "tap a day", S("insights-day", "One day")],
            ["no Screen Time access", W("Connect Screen Time", ["Card asks for Screen Time access,", "or says it's off / unavailable"], ["Connect Screen Time"])],
        ],
    },
    {
        "id": "profile", "title": "Profile & settings", "eyebrow": "Tab 5",
        "lanes": [
            [S("profile", "Profile"), "gear or Settings", S("settings", "Settings", "Name, notifications, sounds, age, subscription, restore, legal, reset")],
        ],
    },
    {
        "id": "focus-setup", "title": "Focus setup", "eyebrow": "Not in the shipping onboarding",
        "text": "Only the older onboarding and the debug menu open this; the short onboarding skips it.",
        "lanes": [[S("focus-setup-1", "Pick apps"), "", S("focus-setup-2", "When to block"), "", S("focus-setup-3", "Turn on blocking")]],
    },
    {
        "id": "outside", "title": "Outside the app", "eyebrow": "Home screen",
        "lanes": [[W("Widget", ["Memo · small / medium", "Streak + “day streak”", "“Brain trained today.” or", "“No feed til you train.”"])]],
    },
]

CLEANUP = [
    "Five paywall sheets nothing opens anymore: ContentView's trigger sheet, and Home, Train, Insights and the game views' own sheets.",
    "The streak-freeze toast in ContentView is never shown.",
    "Insights' brain-score and “Set up Focus Mode” sections aren't in the page body.",
    "ExerciseInstructionsView (the old first-run gate) is only used by a debug target.",
]


def esc(s): return html.escape(s, quote=True)


def arrow(label, lead=False):
    cls = "arrow lead" if lead else "arrow"
    small = f"<small>{esc(label)}</small>" if label else ""
    return f'<div class="{cls}"><svg viewBox="0 0 52 14" aria-hidden="true"><path d="M2 7h46M42 2l6 5-6 5"/></svg>{small}</div>'


def node(n, have):
    if n[0] == "shot":
        _, i, name, note = n
        if i not in have:
            return f'<div class="node"><div class="wire missing"><b>{esc(name)}</b><span>not captured this run</span></div><div class="name">{esc(name)}</div></div>'
        return (f'<div class="node"><a class="shot" href="img/{i}.jpg" target="_blank" rel="noopener">'
                f'<img src="img/{i}.jpg" alt="{esc(name)}" loading="lazy"></a>'
                f'<div class="name">{esc(name)}</div>' + (f'<div class="note">{esc(note)}</div>' if note else "") + "</div>")
    _, name, lines, buttons, note = n
    body = "".join(f"<span>{esc(l)}</span>" for l in lines)
    btns = "".join(f"<i>{esc(b)}</i>" for b in buttons)
    return (f'<div class="node"><div class="wire"><em>WIREFRAME</em><b>{esc(name)}</b>{body}<div class="btns">{btns}</div></div>'
            f'<div class="name">{esc(name)}</div>' + (f'<div class="note">{esc(note)}</div>' if note else "") + "</div>")


def lane(items, have):
    out, first = [], True
    for k, it in enumerate(items):
        if isinstance(it, str):
            out.append(arrow(it, lead=(k == 0)))
        else:
            out.append(node(it, have))
        first = False
    return '<div class="lane"><div class="row">' + "".join(out) + "</div></div>"


CSS = """
:root{color-scheme:dark;--bg:#0a1220;--surface:#111b2e;--raise:#17233b;--line:#243453;--text:#edf2ff;--muted:#8f9cbd;--mint:#7be3c6;--amber:#ffd36b;--sky:#7fa8ff;
--display:"Bricolage Grotesque","Avenir Next",system-ui,sans-serif;--body:"Figtree",system-ui,-apple-system,sans-serif;--mono:"JetBrains Mono",ui-monospace,"SF Mono",Menlo,monospace}
body{background:var(--bg);color:var(--text);font:500 15px/1.5 var(--body);padding-inline:20px;padding-block:32px 72px}
.wrap{max-width:1280px;margin:0 auto;display:grid;gap:40px}
h1{font:800 clamp(32px,5vw,54px)/1 var(--display);letter-spacing:-.02em;margin:6px 0 12px}
h2{font:800 26px/1.15 var(--display);margin:0;text-wrap:balance}
.eyebrow{font:700 11px/1 var(--mono);letter-spacing:.14em;text-transform:uppercase;color:var(--muted)}
.lede,.head p{color:var(--muted);margin:0;max-width:72ch}
.nav{display:flex;flex-wrap:wrap;gap:8px}
.nav a{color:var(--text);text-decoration:none;font-size:13px;font-weight:600;padding:7px 12px;border-radius:999px;border:1px solid var(--line);background:var(--surface)}
.nav a:hover,.nav a:focus-visible{border-color:var(--sky);outline:none}
section{display:grid;gap:14px;scroll-margin-top:16px}
.head{display:grid;gap:6px}
.head .eyebrow{color:var(--sky)}
.lane{overflow-x:auto;background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:18px;scrollbar-color:var(--line) transparent}
.row{display:flex;align-items:flex-start;width:max-content}
.node{width:150px;display:grid;gap:7px;flex:none}
.shot{display:block;aspect-ratio:1179/2556;border-radius:16px;overflow:hidden;border:2px solid var(--line);background:#000}
.shot img{width:100%;height:100%;object-fit:cover;display:block}
.wire{aspect-ratio:1179/2556;border-radius:16px;border:2px dashed #3a4c72;background:repeating-linear-gradient(135deg,#0f182a 0 10px,#111c31 10px 20px);display:flex;flex-direction:column;justify-content:center;gap:6px;padding:14px;text-align:center}
.wire em{font:700 9px/1 var(--mono);letter-spacing:.12em;color:var(--sky);font-style:normal}
.wire b{font:800 15px/1.2 var(--display)}
.wire span{font-size:11.5px;line-height:1.35;color:var(--muted)}
.wire .btns{display:grid;gap:6px;margin-top:8px}
.wire i{font-style:normal;font-size:11px;font-weight:700;border:1.5px solid #4a5d86;border-radius:9px;padding:6px 4px}
.wire.missing{border-color:#6b4a4a}
.name{font:700 14px/1.25 var(--body)}
.note{font-size:12.5px;line-height:1.4;color:var(--muted)}
.arrow{width:74px;flex:none;align-self:stretch;display:grid;align-content:start;justify-items:center;padding-top:118px;gap:6px}
.arrow.lead{width:96px}
.arrow svg{width:52px;height:14px}
.arrow svg path{stroke:var(--muted);fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.arrow small{font-size:11px;line-height:1.25;color:var(--sky);font-weight:600;text-align:center;max-width:90px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:16px;background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:18px}
.grid .node{width:auto}
.cleanup{background:var(--raise);border:1px solid var(--line);border-radius:18px;padding:18px 20px}
.cleanup ul{margin:8px 0 0;padding-left:18px;color:var(--muted);display:grid;gap:4px}
footer{color:var(--muted);font-size:13px;border-top:1px solid var(--line);padding-top:18px}
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--site", required=True)
    ap.add_argument("--build", default="")
    a = ap.parse_args()
    os.makedirs(os.path.join(a.site, "img"), exist_ok=True)
    have = set()
    for f in os.listdir(a.raw):
        if f.endswith(".png"):
            i = f[:-4]
            im = Image.open(os.path.join(a.raw, f)).convert("RGB")
            im = im.resize((360, int(im.height * 360 / im.width)), Image.LANCZOS)
            im.save(os.path.join(a.site, "img", f"{i}.jpg"), quality=80)
            have.add(i)

    parts = []
    for fl in FLOWS:
        body = ""
        if "grid" in fl:
            body = '<div class="grid">' + "".join(node(S(i, n), have) for i, n in fl["grid"]) + "</div>"
        else:
            body = "".join(lane(l, have) for l in fl["lanes"])
        text = f'<p>{esc(fl["text"])}</p>' if fl.get("text") else ""
        parts.append(f'<section id="{fl["id"]}"><div class="head"><span class="eyebrow">{esc(fl["eyebrow"])}</span>'
                     f'<h2>{esc(fl["title"])}</h2>{text}</div>{body}</section>')
    nav = "".join(f'<a href="#{fl["id"]}">{esc(fl["title"])}</a>' for fl in FLOWS)
    cleanup = "".join(f"<li>{esc(c)}</li>" for c in CLEANUP)
    date = time.strftime("%B %-d, %Y")
    page = f"""<title>Memo Flow Map</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Figtree:wght@400;500;600;700&family=JetBrains+Mono:wght@600;700&display=swap">
<style>{CSS}</style>
<div class="wrap">
<header><div class="eyebrow">Memo {esc(a.build)} · every screen</div><h1>Memo Flow Map</h1>
<p class="lede">Every screen and every tap between them, left to right. Screenshots come from the simulator; striped boxes are wireframes of screens iOS draws itself (Screen Time's shield, prompts, the widget). Blue text is what you tap or the condition that sends you there. Tap any screen to open it full size.</p></header>
<nav class="nav" aria-label="Flows">{nav}</nav>
{''.join(parts)}
<section id="cleanup"><div class="cleanup"><span class="eyebrow">In the code, never shown</span><ul>{cleanup}</ul></div></section>
<footer>Captured {date} from Memo {esc(a.build)} on an iPhone 16 simulator with Scripts/flowmap/capture.py; page built by Scripts/flowmap/build_page.py.</footer>
</div>"""
    open(os.path.join(a.site, "index.html"), "w").write(page)
    print(f"{len(have)} screens, {sum(1 for fl in FLOWS for l in fl.get('lanes', []) for n in l if isinstance(n, tuple))} nodes")


if __name__ == "__main__":
    main()
