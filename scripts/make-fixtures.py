#!/usr/bin/env python3
"""Generate small, deterministic PNG fixtures without third-party dependencies."""
import argparse
import json
from pathlib import Path
import struct
import zlib


def png(path, pixels, width=2, compression=6, note=None):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    height = len(pixels) // 4 // width
    rows = b''.join(b'\0' + bytes(pixels[y * width * 4:(y + 1) * width * 4]) for y in range(height))
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    data += chunk(b'sRGB', b'\0')
    if note:
        data += chunk(b'tEXt', b'Description\0' + note.encode())
    data += chunk(b'IDAT', zlib.compress(rows, compression)) + chunk(b'IEND', b'')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def generate(root):
    red = [255, 0, 0, 255, 50, 60, 70, 0]
    incoming = root / 'Incoming'
    png(incoming / 'renamed.png', red, compression=0, note='different encoding and metadata')
    png(incoming / 'hidden-colour.png', [255, 0, 0, 255, 200, 100, 10, 0])
    png(incoming / 'new.png', [0, 255, 0, 255, 50, 60, 70, 0])
    png(incoming / 'resized.png', red * 2, width=4)
    png(incoming / 'padded.png', red + [0, 0, 0, 0], width=3)
    png(incoming / 'partial.png', [255, 0, 0, 1, 50, 60, 70, 0])
    (incoming / 'broken.png').write_bytes(b'not an image')
    for catalog in ['App/Primary.xcassets', 'Packages/Other.xcassets']:
        entry = root / catalog / 'Icon.imageset'
        png(entry / 'light.png', red)
        png(entry / 'dark.png', [0, 0, 255, 255, 0, 0, 0, 0])
        (entry / 'Contents.json').write_text(json.dumps({'images': [
            {'filename': 'light.png', 'idiom': 'universal', 'scale': '1x'},
            {'filename': 'dark.png', 'idiom': 'universal', 'scale': '2x',
             'appearances': [{'appearance': 'luminosity', 'value': 'dark'}]}],
            'info': {'version': 1, 'author': 'xcode'}}, indent=2))
    broken = root / 'App/Primary.xcassets/Broken.imageset'
    broken.mkdir(parents=True, exist_ok=True)
    (broken / 'Contents.json').write_text('{broken')
    (root / 'expectations.json').write_text(json.dumps({
        'assets': 3, 'skipped': 1,
        'matches': {'renamed.png': 2, 'hidden-colour.png': 2, 'new.png': 0,
                    'resized.png': 0, 'padded.png': 0, 'partial.png': 0},
        'errors': ['broken.png']}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    generate(parser.parse_args().output.resolve())
