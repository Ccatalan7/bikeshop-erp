#!/usr/bin/env python3
"""Which source files fill a dart2js output file, by bytes.

Build with source maps, then read any `main.dart.js` or part:

    fvm flutter build web --release --source-maps -t lib/main_store.dart \
        -o <dir>
    python3 -I scripts/dev/web_bundle_attribution.py <dir>/main.dart.js_3.part.js 4

The number is how many path segments to group by (2: `lib:modules/website`,
4: one file). Every byte of generated JavaScript is charged to the source the
map points at; minified names hide everything else.

2026-10-14: this read the storefront's over-budget chunks in minutes: the
whole world's time zone table (charged to `internal/internal.dart`, ~0.8 MB),
the Dart HTML widget and the full chat were in pages no visitor opens.
"""

import json
import sys
from collections import Counter

_B64 = {c: i for i, c in enumerate(
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/')}


def _vlq(segment):
    values, shift, value = [], 0, 0
    for ch in segment:
        digit = _B64[ch]
        more = digit & 32
        value += (digit & 31) << shift
        if more:
            shift += 5
            continue
        values.append(-(value >> 1) if value & 1 else value >> 1)
        value, shift = 0, 0
    return values


def attribute(js_path, depth):
    lines = open(js_path, encoding='utf-8', errors='replace').read().split('\n')
    source_map = json.load(open(js_path + '.map'))
    sources = source_map['sources']
    totals = Counter()
    source = 0
    for line_no, mapping in enumerate(source_map['mappings'].split(';')):
        text = lines[line_no] if line_no < len(lines) else ''
        column, segments = 0, []
        for segment in mapping.split(','):
            if not segment:
                continue
            fields = _vlq(segment)
            column += fields[0]
            if len(fields) >= 4:
                source += fields[1]
                segments.append((column, source))
            else:
                segments.append((column, None))
        for i, (start, index) in enumerate(segments):
            end = segments[i + 1][0] if i + 1 < len(segments) else len(text)
            key = sources[index] if index is not None else '(unmapped)'
            totals[key] += max(0, end - start)

    grouped = Counter()
    for path, size in totals.items():
        if 'packages/' in path:
            parts = path.split('packages/', 1)[1].split('/')
            if parts[0] == 'vinabike_erp':
                path = 'app:' + '/'.join(parts[1:1 + depth])
            else:
                path = 'pkg:' + parts[0]
        elif 'lib/' in path:
            path = 'lib:' + '/'.join(path.split('lib/', 1)[1].split('/')[:depth])
        grouped[path] += size
    return grouped


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 64
    depth = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    for path, size in attribute(sys.argv[1], depth).most_common(40):
        print(f'{size:>10} {path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
