#!/usr/bin/env python3
"""Capture every Memo screen for the flow map.

Usage:
  python3 Scripts/flowmap/capture.py --udid <simulator> --app <MindRestore.app> --out <dir> [--only id1,id2]

Needs a DEBUG build (screenshot targets and --unlock-game only exist there) and
idb (https://fbidb.io). Writes <out>/<id>.png plus <out>/manifest.json; build the
page with build_page.py. Each shot is independent, so a failure skips that shot
and moves on.
"""
import argparse, json, os, subprocess, sys, time

BUNDLE = "com.dylanmiller.mindrestore"
BASE_ARGS = ["--screenshot-mode", "--hide-dev-controls"]

# Each shot: id -> list of steps. Steps:
#   ("launch", [args])   fresh launch with screenshot mode + args
#   ("reinstall",)       wipe app data (fresh pending spin / free pass)
#   ("url", url)         open a deep link and accept iOS's "Open in Memo?"
#   ("tap", label)       tap the element whose accessibility label matches
#   ("wait", seconds)
#   ("chimp", "solve"|"miss", n)   play the Chimp Test from its accessibility labels
#   ("shot",)
SHOTS = {}

def add(sid, *steps):
    SHOTS[sid] = list(steps)

# Onboarding (the concise route that ships)
for t in ["welcome", "attribution", "bridge", "slot", "game", "game-reward", "rank", "trial-free", "trial-reminder"]:
    add(f"ob-{t}", ("launch", ["--onboarding-variant", "concise", "--screenshot-target", f"onboarding-{t}"]), ("wait", 7), ("shot",))
add("ob-slot-landed", ("launch", ["--onboarding-variant", "concise", "--screenshot-target", "onboarding-slot"]), ("wait", 7), ("tap", "Spin"), ("wait", 6), ("shot",))
add("paywall-yearly", ("launch", ["--screenshot-target", "paywall-concise"]), ("wait", 10), ("shot",))
add("paywall-weekly", ("launch", ["--screenshot-target", "paywall-concise"]), ("wait", 10), ("tap", "Weekly"), ("wait", 1.5), ("shot",))

# Onboarding test, arm B ("guided"): new screens after the demo
for t in ["age", "screen-time", "shock", "years-back", "screen-time-access", "notifications", "plan", "congrats"]:
    add(f"g-{t}", ("launch", ["--onboarding-variant", "guided", "--screenshot-target", f"onboarding-guided-{t}"]), ("wait", 8), ("shot",))
add("g-calculating", ("launch", ["--onboarding-variant", "guided", "--screenshot-target", "onboarding-guided-calculating"]), ("wait", 6), ("shot",))

# One-time offer: the paywall's X shows once and opens it; "No thanks" returns to the paywall without the X
add("offer", ("reinstall",), ("launch", ["--screenshot-target", "paywall-concise"]), ("wait", 10), ("tap", "Close paywall"), ("wait", 2), ("shot",),
    ("tap", "No thanks"), ("wait", 1.5), ("shot", "paywall-after-offer"))

# Home
for n in range(4):
    add(f"home-{n}", ("launch", ["--screenshot-target", "home", "--home-games", str(n)]), ("wait", 7), ("shot",))
add("home-rain", ("launch", ["--screenshot-target", "home", "--home-games", "0", "--home-rain-days", "3"]), ("wait", 7), ("shot",))
add("home-blocking", ("launch", ["--screenshot-target", "home", "--home-demo-blocking"]), ("wait", 7), ("shot",))
add("home-memo-tap", ("launch", ["--screenshot-target", "home"]), ("wait", 7), ("tap", "Memo"), ("wait", 1), ("shot",))

# Train: grid, intros, gameplay, results
add("train", ("launch", ["--screenshot-target", "train"]), ("wait", 7), ("shot",))
for g in ["visualMemory", "sequentialMemory", "chimpTest", "mathSpeed", "colorMatch", "reactionTime"]:
    add(f"intro-{g}", ("launch", ["--screenshot-target", f"intro-{g}"]), ("wait", 7), ("shot",))
    add(f"play-{g}", ("launch", ["--screenshot-target", f"intro-{g}"]), ("wait", 7), ("tap", "Play"), ("wait", 1.3), ("shot",))
add("info-sheet", ("launch", ["--screenshot-target", "intro-chimpTest"]), ("wait", 7), ("tap", "questionmark.circle.fill"), ("wait", 1.5), ("shot",))
for t in ["flow-normal", "flow-pb", "flow-out", "flow-zero"]:
    add(f"result-{t[5:]}", ("launch", ["--screenshot-target", t]), ("wait", 10), ("shot",))

# Unlock a blocked app (booth). Free pass first, on a fresh install.
add("free-pass", ("reinstall",), ("launch", ["--unlock-game", "freePass"]), ("wait", 8), ("url", "memori://focus-unlock"),
    ("tap", "Spin"), ("wait", 9), ("shot",))
add("booth", ("reinstall",), ("launch", ["--unlock-game", "chimpTest"]), ("wait", 8), ("url", "memori://focus-unlock"), ("wait", 1), ("shot",))
add("booth-game", ("launch", ["--unlock-game", "chimpTest"]), ("wait", 8), ("url", "memori://focus-unlock"),
    ("tap", "Spin"), ("wait", 6), ("tap", "Play"), ("wait", 1.5), ("shot",))
add("cash-out", ("reinstall",), ("launch", ["--unlock-game", "chimpTest"]), ("wait", 8), ("url", "memori://focus-unlock"),
    ("tap", "Spin"), ("wait", 6), ("tap", "Play"), ("wait", 1.5), ("chimp", "solve", 6), ("wait", 1.5), ("shot",),
    ("tap", "Cash out"), ("wait", 2.5), ("shot", "unlocked-ticket"), ("wait", 6), ("shot", "unlocked-rank"))
add("denied", ("reinstall",), ("launch", ["--unlock-game", "chimpTest"]), ("wait", 8), ("url", "memori://focus-unlock"),
    ("tap", "Spin"), ("wait", 6), ("tap", "Play"), ("wait", 1.5), ("chimp", "miss", 3), ("wait", 3), ("shot",),
    ("tap", "Try again"), ("wait", 2), ("chimp", "miss", 3), ("wait", 3), ("shot", "denied-2"),
    ("tap", "I really need it"), ("wait", 2), ("shot", "escape-hatch"))

# Compete
add("compete", ("launch", ["--screenshot-target", "compete"]), ("wait", 8), ("shot",))
add("compete-chimp", ("launch", ["--screenshot-target", "compete", "--league", "Chimp"]), ("wait", 8), ("shot",))
add("compete-streak", ("launch", ["--screenshot-target", "compete", "--league", "Streak"]), ("wait", 8), ("shot",))
add("compete-sparse", ("launch", ["--screenshot-target", "compete", "--league", "Chimp", "--league-sparse"]), ("wait", 8), ("shot",))

# Insights
add("insights", ("launch", ["--screenshot-target", "insights"]), ("wait", 9), ("shot",))
add("insights-day", ("launch", ["--screenshot-target", "insights", "--insights-day", "2"]), ("wait", 9), ("shot",))

# Profile and settings
add("profile", ("launch", ["--screenshot-target", "profile"]), ("wait", 7), ("shot",))
add("settings", ("launch", ["--screenshot-target", "profile"]), ("wait", 7), ("tap", "Settings"), ("wait", 2), ("shot",))

# Focus setup (reachable from the control onboarding and Settings' debug card)
for n in (1, 2, 3):
    add(f"focus-setup-{n}", ("launch", ["--screenshot-target", "focus-setup", "--focus-setup-step", str(n)]), ("wait", 7), ("shot",))


class Sim:
    def __init__(self, udid, app, out):
        self.udid, self.app, self.out = udid, app, out

    def run(self, *cmd, check=False):
        return subprocess.run(list(cmd), capture_output=True, text=True, check=check)

    def elements(self):
        r = self.run("idb", "ui", "describe-all", "--udid", self.udid)
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return []

    def tap_xy(self, x, y):
        self.run("idb", "ui", "tap", "--udid", self.udid, str(int(x)), str(int(y)))

    def tap(self, label):
        els = [e for e in self.elements() if e.get("AXLabel")]
        exact = [e for e in els if e["AXLabel"] == label]
        loose = [e for e in els if label.lower() in e["AXLabel"].lower()]
        # Prefer buttons, then the smallest (most specific) match.
        for pool in (exact, loose):
            pool = sorted(pool, key=lambda e: (e.get("type") != "Button", e["frame"]["width"] * e["frame"]["height"]))
            if pool:
                f = pool[0]["frame"]
                self.tap_xy(f["x"] + f["width"] / 2, f["y"] + f["height"] / 2)
                return True
        return False

    def launch(self, args):
        self.run("xcrun", "simctl", "terminate", self.udid, BUNDLE)
        self.run("xcrun", "simctl", "launch", self.udid, BUNDLE, *BASE_ARGS, *args)

    def reinstall(self):
        self.run("xcrun", "simctl", "terminate", self.udid, BUNDLE)
        self.run("xcrun", "simctl", "uninstall", self.udid, BUNDLE)
        self.run("xcrun", "simctl", "install", self.udid, self.app, check=True)

    def url(self, url):
        self.run("xcrun", "simctl", "openurl", self.udid, url)
        # iOS asks "Open in “Memo”?" for simctl deep links; it can take a few seconds to show.
        for _ in range(12):
            time.sleep(0.5)
            opens = [e for e in self.elements() if e.get("AXLabel") == "Open" and e.get("type") == "Button"]
            if opens:
                f = opens[0]["frame"]
                self.tap_xy(f["x"] + f["width"] / 2, f["y"] + f["height"] / 2)
                break
        # Wait for the booth's Spin button.
        for _ in range(12):
            time.sleep(0.5)
            if any(e.get("AXLabel") == "Spin" for e in self.elements()):
                break
        time.sleep(1)

    def chimp(self, how, n):
        """Play the Chimp Test from its labels: 'solve' clears n levels, 'miss' loses n lives."""
        for _ in range(n):
            nums = {}
            for _ in range(10):
                nums = {int(e["AXLabel"].split()[1]): e["frame"] for e in self.elements()
                        if (e.get("AXLabel") or "").startswith("Number ")}
                if nums:
                    break
                time.sleep(0.5)
            if not nums:
                return
            order = sorted(nums) if how == "solve" else [2 if 2 in nums else max(nums)]
            for k in order:
                f = nums[k]
                self.tap_xy(f["x"] + f["width"] / 2, f["y"] + f["height"] / 2)
                time.sleep(0.2)
            time.sleep(1.4)
            if how == "solve" and any(e.get("AXLabel", "").startswith("Cash out") for e in self.elements()):
                return

    def shot(self, name):
        path = os.path.join(self.out, f"{name}.png")
        self.run("xcrun", "simctl", "io", self.udid, "screenshot", path)
        return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--udid", required=True)
    ap.add_argument("--app", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    sim = Sim(a.udid, a.app, a.out)
    sim.run("xcrun", "simctl", "status_bar", a.udid, "override", "--time", "9:41", "--batteryLevel", "100")
    sim.reinstall()
    only = set(filter(None, a.only.split(",")))
    manifest_path = os.path.join(a.out, "manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    for sid, steps in SHOTS.items():
        if only and sid not in only:
            continue
        taken = []
        try:
            for step in steps:
                kind = step[0]
                if kind == "launch": sim.launch(step[1])
                elif kind == "reinstall": sim.reinstall()
                elif kind == "url": sim.url(step[1])
                elif kind == "tap":
                    if not sim.tap(step[1]): print(f"  {sid}: no element '{step[1]}'")
                elif kind == "wait": time.sleep(step[1])
                elif kind == "chimp": sim.chimp(step[1], step[2])
                elif kind == "shot":
                    name = step[1] if len(step) > 1 else sid
                    sim.shot(name); taken.append(name)
        except Exception as e:  # keep going; one broken shot shouldn't stop the run
            print(f"  {sid}: {e}")
        for name in taken:
            manifest[name] = {"captured": time.strftime("%Y-%m-%d %H:%M")}
        print(f"{sid}: {', '.join(taken) or 'nothing captured'}")
        json.dump(manifest, open(manifest_path, "w"), indent=1)


if __name__ == "__main__":
    sys.exit(main())
