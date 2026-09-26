import riv
def props(o): return {riv.pname(p[0]):p[2] for p in o[1]}
def animations(f):
    """name -> {(objectId, propKey): [obj indices of keyframes]}"""
    out = {}; cur = None; ko = None; kp = None
    for i, o in enumerate(f['objs']):
        n = riv.tname(o[0]); p = props(o)
        if n == 'LinearAnimation': cur = out.setdefault(p['name'].decode(), {})
        elif n == 'StateMachine': cur = None
        elif cur is None: continue
        elif n == 'KeyedObject': ko = p.get('objectId', 0)
        elif n == 'KeyedProperty': kp = p.get('propertyKey'); cur[(ko, kp)] = []
        elif n.startswith('KeyFrame'): cur[(ko, kp)].append(i)
    return out
def kf(f, i):
    p = props(f['objs'][i]); return p.get('frame', 0), p.get('value')
