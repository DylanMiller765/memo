"""Rebuild Memo's `happy` pose as neutral + t * (happy - neutral), per part group."""
import sys, json, riv, anim
VALUE = {70: 2, 88: 3}  # KeyFrameDouble.value (float), KeyFrameColor.value (color)

def value_of(f, i):
    for pk, fid, v in f['objs'][i][1]:
        if pk in VALUE: return pk, v
    t = riv.tname(f['objs'][i][0])
    return (88 if t == 'KeyFrameColor' else 70), 0

def set_value(f, i, pk, v):
    props = f['objs'][i][1]
    for p in props:
        if p[0] == pk: p[2] = v; return
    props.append([pk, VALUE[pk], v])

def sample(f, idxs, frame):
    """Linear sample of a keyed property at `frame` (colors per channel)."""
    pts = [(anim.props(f['objs'][i]).get('frame', 0), value_of(f, i)[1]) for i in idxs]
    if frame <= pts[0][0]: return pts[0][1]
    for (f0, v0), (f1, v1) in zip(pts, pts[1:]):
        if f0 <= frame <= f1:
            u = (frame - f0) / max(f1 - f0, 1)
            return lerp(v0, v1, u, isinstance(v0, int) and not isinstance(v0, bool) and v0 > 0xFFFF)
    return pts[-1][1]

def lerp(a, b, t, color=False):
    if color:
        out = 0
        for sh in (24, 16, 8, 0):
            ca, cb = (a >> sh) & 255, (b >> sh) & 255
            out |= int(round(ca + (cb - ca) * t)) << sh
        return out
    return a + (b - a) * t

def group(obj, prop):
    if prop == 18 and obj == 42: return 'sparkles'
    if prop == 37: return 'colors'
    if 2 <= obj <= 15: return 'bones'
    if obj == 648: return 'glow'
    if 139 <= obj <= 181: return 'mouth'
    return 'other'

def main(src, dst, weights):
    f = riv.load(src); A = anim.animations(f)
    happy, neutral = A['happy'], A['neutral']
    changed = {}
    for key, idxs in happy.items():
        t = weights.get(group(*key), weights['other'])
        if t == 1 or key not in neutral: continue
        for i in idxs:
            frame = anim.props(f['objs'][i]).get('frame', 0)
            pk, hv = value_of(f, i)
            nv = sample(f, neutral[key], frame)
            set_value(f, i, pk, lerp(nv, hv, t, pk == 88))
            changed[group(*key)] = changed.get(group(*key), 0) + 1
    riv.dump(f, dst)
    print('changed keyframes:', changed)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], json.loads(sys.argv[3]))
