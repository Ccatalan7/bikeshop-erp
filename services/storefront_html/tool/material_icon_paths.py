#!/usr/bin/env python3
"""Extract Material icon outlines from Flutter's MaterialIcons-Regular.otf
(CFF) as SVG path data on the 24 px grid. No dependencies.

usage: python3 services/storefront_html/tool/material_icon_paths.py \
  .fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf \
  lockOutline=0xe3b1 ...

The code point of `Icons.<name>` is in the Flutter SDK's
packages/flutter/lib/src/material/icons.dart. Paste the output into
lib/src/material_icons.dart as `md<Name>` constants.
"""
import struct
import sys


def u16(b, o): return struct.unpack('>H', b[o:o + 2])[0]
def i16(b, o): return struct.unpack('>h', b[o:o + 2])[0]
def u32(b, o): return struct.unpack('>I', b[o:o + 4])[0]


def tables(font):
    n = u16(font, 4)
    out = {}
    for i in range(n):
        rec = 12 + 16 * i
        tag = font[rec:rec + 4].decode('latin1')
        out[tag] = (u32(font, rec + 8), u32(font, rec + 12))
    return out


def cmap_lookup(font, t):
    off, _ = t['cmap']
    n = u16(font, off + 2)
    best = None
    for i in range(n):
        pid, eid, sub = u16(font, off + 4 + 8 * i), u16(font, off + 6 + 8 * i), u32(font, off + 8 + 8 * i)
        fmt = u16(font, off + sub)
        if fmt == 12:
            best = off + sub
    groups = {}
    ngroups = u32(font, best + 12)
    ranges = []
    for g in range(ngroups):
        o = best + 16 + 12 * g
        ranges.append((u32(font, o), u32(font, o + 4), u32(font, o + 8)))
    def look(cp):
        for start, end, gid in ranges:
            if start <= cp <= end:
                return gid + cp - start
        return None
    return look


def read_index(b, o):
    count = u16(b, o)
    if count == 0:
        return [], o + 2
    osize = b[o + 2]
    offs = []
    for i in range(count + 1):
        p = o + 3 + i * osize
        v = 0
        for k in range(osize):
            v = (v << 8) | b[p + k]
        offs.append(v)
    data = o + 3 + (count + 1) * osize - 1
    items = [b[data + offs[i]:data + offs[i + 1]] for i in range(count)]
    return items, data + offs[-1]


def parse_dict(d):
    out, ops, i = {}, [], 0
    while i < len(d):
        b0 = d[i]
        if b0 <= 21:
            op = b0
            i += 1
            if b0 == 12:
                op = 1200 + d[i]
                i += 1
            out[op] = ops
            ops = []
        elif b0 == 28:
            ops.append(struct.unpack('>h', d[i + 1:i + 3])[0]); i += 3
        elif b0 == 29:
            ops.append(struct.unpack('>i', d[i + 1:i + 5])[0]); i += 5
        elif b0 == 30:
            i += 1
            s = ''
            while True:
                nib = [d[i] >> 4, d[i] & 15]
                i += 1
                done = False
                for n in nib:
                    if n == 15: done = True; break
                    s += '0123456789.EE-?-'[n] if n != 12 else 'E-'
                if done: break
            ops.append(float(s))
        elif 32 <= b0 <= 246:
            ops.append(b0 - 139); i += 1
        elif 247 <= b0 <= 250:
            ops.append((b0 - 247) * 256 + d[i + 1] + 108); i += 2
        elif 251 <= b0 <= 254:
            ops.append(-(b0 - 251) * 256 - d[i + 1] - 108); i += 2
        else:
            raise ValueError(b0)
    return out


def bias(n):
    return 107 if n < 1240 else 1131 if n < 33900 else 32768


class Path:
    def __init__(self):
        self.cmds = []
        self.x = self.y = 0.0
        self.open = False

    def move(self, dx, dy):
        if self.open: self.cmds.append(('Z',))
        self.x += dx; self.y += dy
        self.cmds.append(('M', self.x, self.y)); self.open = True

    def line(self, dx, dy):
        self.x += dx; self.y += dy
        self.cmds.append(('L', self.x, self.y))

    def curve(self, a, b, c, d, e, f):
        x1, y1 = self.x + a, self.y + b
        x2, y2 = x1 + c, y1 + d
        self.x, self.y = x2 + e, y2 + f
        self.cmds.append(('C', x1, y1, x2, y2, self.x, self.y))


def run(code, gsubrs, lsubrs, path, state):
    s = state['stack']
    i = 0
    while i < len(code):
        b0 = code[i]
        if b0 == 28:
            s.append(struct.unpack('>h', code[i + 1:i + 3])[0]); i += 3; continue
        if b0 >= 32:
            if b0 <= 246: s.append(b0 - 139); i += 1
            elif b0 <= 250: s.append((b0 - 247) * 256 + code[i + 1] + 108); i += 2
            elif b0 <= 254: s.append(-(b0 - 251) * 256 - code[i + 1] - 108); i += 2
            else: s.append(struct.unpack('>i', code[i + 1:i + 5])[0] / 65536.0); i += 5
            continue
        i += 1
        op = b0
        if op == 12:
            op = 1200 + code[i]; i += 1

        def width(expected_even):
            if not state['width'] and (len(s) % 2 == 1) == expected_even:
                s.pop(0)
            state['width'] = True

        if op in (1, 3, 18, 23):  # hstem vstem hstemhm vstemhm
            if not state['width'] and len(s) % 2 == 1: s.pop(0)
            state['width'] = True
            state['stems'] += len(s) // 2; s.clear()
        elif op in (19, 20):  # hintmask cntrmask
            if not state['width'] and len(s) % 2 == 1: s.pop(0)
            state['width'] = True
            state['stems'] += len(s) // 2; s.clear()
            i += (state['stems'] + 7) // 8
        elif op == 21:  # rmoveto
            if not state['width'] and len(s) > 2: s.pop(0)
            state['width'] = True
            path.move(s[0], s[1]); s.clear()
        elif op == 22:  # hmoveto
            if not state['width'] and len(s) > 1: s.pop(0)
            state['width'] = True
            path.move(s[0], 0); s.clear()
        elif op == 4:  # vmoveto
            if not state['width'] and len(s) > 1: s.pop(0)
            state['width'] = True
            path.move(0, s[0]); s.clear()
        elif op == 5:
            for k in range(0, len(s), 2): path.line(s[k], s[k + 1])
            s.clear()
        elif op in (6, 7):
            horiz = op == 6
            for v in s:
                path.line(v, 0) if horiz else path.line(0, v)
                horiz = not horiz
            s.clear()
        elif op == 8:
            for k in range(0, len(s), 6): path.curve(*s[k:k + 6])
            s.clear()
        elif op == 24:  # rcurveline
            k = 0
            while k + 6 <= len(s) - 2: path.curve(*s[k:k + 6]); k += 6
            path.line(s[k], s[k + 1]); s.clear()
        elif op == 25:  # rlinecurve
            k = 0
            while k + 2 <= len(s) - 6: path.line(s[k], s[k + 1]); k += 2
            path.curve(*s[k:k + 6]); s.clear()
        elif op == 26:  # vvcurveto
            k = 0; dx1 = 0
            if len(s) % 4 == 1: dx1 = s[0]; k = 1
            while k < len(s):
                path.curve(dx1, s[k], s[k + 1], s[k + 2], 0, s[k + 3]); dx1 = 0; k += 4
            s.clear()
        elif op == 27:  # hhcurveto
            k = 0; dy1 = 0
            if len(s) % 4 == 1: dy1 = s[0]; k = 1
            while k < len(s):
                path.curve(s[k], dy1, s[k + 1], s[k + 2], s[k + 3], 0); dy1 = 0; k += 4
            s.clear()
        elif op in (30, 31):  # vhcurveto hvcurveto
            horiz = op == 31
            k = 0
            while k < len(s):
                last = len(s) - k == 5
                if horiz:
                    path.curve(s[k], 0, s[k + 1], s[k + 2], s[k + 4] if last else 0, s[k + 3])
                else:
                    path.curve(0, s[k], s[k + 1], s[k + 2], s[k + 3], s[k + 4] if last else 0)
                k += 5 if last else 4
                horiz = not horiz
            s.clear()
        elif op == 10:
            n = int(s.pop()) + bias(len(lsubrs))
            if run(lsubrs[n], gsubrs, lsubrs, path, state): return True
        elif op == 29:
            n = int(s.pop()) + bias(len(gsubrs))
            if run(gsubrs[n], gsubrs, lsubrs, path, state): return True
        elif op == 11:
            return False
        elif op == 14:
            if not state['width'] and s: s.pop(0)
            state['width'] = True
            if path.open: path.cmds.append(('Z',)); path.open = False
            return True
        elif op == 1235:  # flex
            path.curve(*s[0:6]); path.curve(*s[6:12]); s.clear()
        elif op == 1234:  # hflex
            d = s
            path.curve(d[0], 0, d[1], d[2], d[3], 0)
            path.curve(d[4], 0, d[5], -d[2], d[6], 0); s.clear()
        elif op == 1236:  # hflex1
            d = s
            path.curve(d[0], d[1], d[2], d[3], d[4], 0)
            path.curve(d[5], 0, d[6], d[7], d[8], -(d[1] + d[3] + d[7])); s.clear()
        elif op == 1237:  # flex1
            d = s
            dx = d[0] + d[2] + d[4] + d[6] + d[8]
            dy = d[1] + d[3] + d[5] + d[7] + d[9]
            path.curve(*d[0:6])
            if abs(dx) > abs(dy): path.curve(d[6], d[7], d[8], d[9], d[10], -dy)
            else: path.curve(d[6], d[7], d[8], d[9], -dx, d[10])
            s.clear()
        else:
            raise ValueError('op %d' % op)
    return False


def fmt(v):
    v = round(v, 3)
    s = ('%.3f' % v).rstrip('0').rstrip('.')
    if s == '-0': s = '0'
    return s


def main():
    font = open(sys.argv[1], 'rb').read()
    t = tables(font)
    head = t['head'][0]
    upm = u16(font, head + 18)
    hhea = t['hhea'][0]
    ascent = i16(font, hhea + 4)
    look = cmap_lookup(font, t)
    cff = t['CFF '][0]
    b = font[cff:cff + t['CFF '][1]]
    hdr = b[2]
    names, o = read_index(b, hdr)
    tops, o = read_index(b, o)
    strings, o = read_index(b, o)
    gsubrs, o = read_index(b, o)
    top = parse_dict(tops[0])
    charstrings, _ = read_index(b, top[17][0])
    psize, poff = top[18]
    priv = parse_dict(b[poff:poff + psize])
    lsubrs = []
    if 19 in priv:
        lsubrs, _ = read_index(b, poff + priv[19][0])
    scale = 24.0 / upm
    for arg in sys.argv[2:]:
        name, code = arg.split('=')
        gid = look(int(code, 16))
        path = Path()
        state = {'stack': [], 'width': False, 'stems': 0}
        run(charstrings[gid], gsubrs, lsubrs, path, state)
        out = []
        for c in path.cmds:
            if c[0] == 'Z': out.append('z'); continue
            pts = c[1:]
            xy = []
            for k in range(0, len(pts), 2):
                xy.append(fmt(pts[k] * scale) + ' ' + fmt((ascent - pts[k + 1]) * scale))
            out.append(c[0] + ' '.join(xy))
        print('%s\t%s' % (name, ''.join(out)))


main()
