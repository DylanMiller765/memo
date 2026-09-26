# Memo Rive tweaks (no Rive editor needed)

`riv.py` decodes/encodes `.riv` runtime files byte-for-byte (registry snapshot from rive-runtime in `registry.json`).
`blend.py` rebuilds Memo's `happy` pose as `neutral + t * (happy - neutral)` per part group.

Shipped happy pose (2026-09-26, Dylan: original happy "kinda too much"):

    cd Scripts/rive
    python3 blend.py memori-original.riv "../../MindRestore/memori (1).riv" \
      '{"colors":0.3,"glow":0.25,"sparkles":0.35,"mouth":0.55,"bones":0.6,"other":0.6}'

Groups: colors (fill colors), glow (outline stroke thickness), sparkles (sparkle opacity),
mouth (mouth path points), bones (body bounce), other. 1 = original happy, 0 = neutral.

The Rive editor source is `~/Downloads/memori.rev` (unchanged). If the mascot is re-exported from Rive,
re-run the command above on the new export.

Check a pose on the simulator: `--screenshot-mode --home-games 3 --home-mood happy` (DEBUG).
