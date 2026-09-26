"""Minimal .riv decoder/encoder built from rive-runtime's generated core registry."""
import re, struct, glob, os, json
RR = os.path.join(os.path.dirname(__file__), '..', 'rr')

def _registry():
    types, props = {}, {}   # typeKey -> ClassName ; propKey -> (Class, name)
    for f in glob.glob(f'{RR}/include/rive/generated/**/*_base.hpp', recursive=True):
        s = open(f).read()
        cm = re.search(r'class (\w+)Base\b', s)
        if not cm: continue
        cls = cm.group(1)
        tk = re.search(r'static const uint16_t typeKey = (\d+);', s)
        if tk: types[int(tk.group(1))] = cls
        for n, k in re.findall(r'static const uint16_t (\w+)PropertyKey = (\d+);', s):
            props[int(k)] = (cls, n)
    reg = open(f'{RR}/include/rive/generated/core_registry.hpp').read()
    body = reg[reg.index('static int propertyFieldId'):]
    body = body[:body.index('return -1;')]
    field = {}
    pending = []
    for line in re.split(r'\n', body):
        for c, n in re.findall(r'(\w+)Base::\s*(\w+)PropertyKey', line):
            pending.append((c, n))
        m = re.search(r'return Core(\w+)Type::id;', line)
        if m:
            t = m.group(1)
            for c, n in pending:
                for k, v in props.items():
                    if v == (c, n): field[k] = t
            pending = []
    return types, props, field

_REG = os.path.join(os.path.dirname(__file__), 'registry.json')
if os.path.exists(_REG):  # snapshot of rive-runtime's core registry
    _j = json.load(open(_REG))
    TYPES = {int(k): v for k, v in _j['types'].items()}
    PROPS = {int(k): tuple(v) for k, v in _j['props'].items()}
    FIELD = {int(k): v for k, v in _j['field'].items()}
else:
    TYPES, PROPS, FIELD = _registry()
IDMAP = {'Uint': 0, 'Id': 0, 'Int': 0, 'FractionalIndex': 0, 'String': 1, 'Bytes': 1, 'Double': 2, 'Color': 3, 'Bool': 4}

class R:
    def __init__(s, b): s.b, s.i = b, 0
    def byte(s): v = s.b[s.i]; s.i += 1; return v
    def varuint(s):
        v = sh = 0
        while True:
            c = s.byte(); v |= (c & 0x7f) << sh; sh += 7
            if not c & 0x80: return v
    def u32(s): v = struct.unpack_from('<I', s.b, s.i)[0]; s.i += 4; return v
    def f32(s): v = struct.unpack_from('<f', s.b, s.i)[0]; s.i += 4; return v
    def raw(s, n): v = s.b[s.i:s.i+n]; s.i += n; return v

def enc_varuint(v):
    out = bytearray()
    while True:
        c = v & 0x7f; v >>= 7
        if v: out.append(c | 0x80)
        else: out.append(c); return bytes(out)

def load(path):
    b = open(path, 'rb').read(); r = R(b)
    assert r.raw(4) == b'RIVE'
    major, minor, fid = r.varuint(), r.varuint(), r.varuint()
    toc_keys = []
    while True:
        k = r.varuint()
        if k == 0: break
        toc_keys.append(k)
    toc = {}; cur = 0; bit = 8; toc_words = []
    for k in toc_keys:
        if bit == 8: cur = r.u32(); toc_words.append(cur); bit = 0
        toc[k] = (cur >> bit) & 3; bit += 2
    header = b[:r.i]
    objs = []
    while r.i < len(b):
        tk = r.varuint(); props = []
        while True:
            pk = r.varuint()
            if pk == 0: break
            t = FIELD.get(pk)
            fid_ = IDMAP[t] if t else toc.get(pk)
            if fid_ is None: raise ValueError(f'unknown prop {pk} on type {tk} at {r.i}')
            if fid_ == 0: v = r.varuint()
            elif fid_ == 1: n = r.varuint(); v = r.raw(n)
            elif fid_ == 2: v = r.f32()
            elif fid_ == 3: v = r.u32()
            elif fid_ == 4: v = r.byte()
            props.append([pk, fid_, v])
        objs.append([tk, props])
    return {'header': header, 'objs': objs, 'major': major, 'minor': minor}

def dump(f, path):
    out = bytearray(f['header'])
    for tk, props in f['objs']:
        out += enc_varuint(tk)
        for pk, fid_, v in props:
            out += enc_varuint(pk)
            if fid_ == 0: out += enc_varuint(v)
            elif fid_ == 1: out += enc_varuint(len(v)) + v
            elif fid_ == 2: out += struct.pack('<f', v)
            elif fid_ == 3: out += struct.pack('<I', v)
            elif fid_ == 4: out.append(v)
        out += b'\x00'
    open(path, 'wb').write(bytes(out))
    return bytes(out)

def tname(tk): return TYPES.get(tk, f'?{tk}')
def pname(pk): return PROPS.get(pk, ('?', str(pk)))[1]
