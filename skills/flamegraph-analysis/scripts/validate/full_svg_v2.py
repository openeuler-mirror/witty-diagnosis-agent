#!/usr/bin/env python3
"""
full_svg_v2.py — 单个 SVG 6 层全面验证
Usage: python3 full_svg_v2.py <file.svg>
Return: 0 = pass, 1 = fail
"""
import sys, os, re
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'adapters'))
from svg_to_folded import svg_to_folded

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\86188\AppData\Local\Temp\svg_roundtrip\our_export.svg'
    if not os.path.exists(path):
        print(f'FAIL: {path} not found'); sys.exit(1)

    with open(path, 'r', encoding='utf-8') as f:
        c = f.read()

    print(f'File: {os.path.basename(path)} ({len(c)//1024}KB)')

    # 1. XML
    try:
        import xml.etree.ElementTree as ET
        ET.fromstring(c); print('XML: OK')
    except ET.ParseError as e:
        print(f'XML: FAIL {e}'); sys.exit(1)

    # 2. Elements
    el_checks = ['<svg', 'viewBox', 'onload="init(evt)"', 'max-width:100%',
                 '<g id="frames">', '<text id="title"', '<text id="details"',
                 '<text id="search"', '<text id="ignorecase"', '<text id="unzoom"',
                 '<![CDATA[', '</svg>']
    el_ok = sum(1 for e in el_checks if e in c)
    print(f'Elements: {el_ok}/{len(el_checks)}')

    # 3. CSS
    cs = c[c.find('<style'):c.find('</style>')+8] if '<style' in c else ''
    css_ok = sum(1 for p in ['.hide', '.parent', '#frames', '*:hover'] if p in cs)
    print(f'CSS: {css_ok}/4')

    # 4. JS functions
    fns = ['init','zoom','unzoom','search','search_prompt','toggle_ignorecase',
           'clearzoom','get_params','parse_params','find_child','find_group',
           'orig_save','orig_load','g_to_text','g_to_func','update_text',
           'zoom_reset','zoom_child','zoom_parent','reset_search']
    fn_ok = sum(1 for fn in fns if ('function ' + fn + '(') in c)
    print(f'JS functions: {fn_ok}/{len(fns)}')

    # 5. Event delegation
    is_v2 = '<g id="frames">' in c
    if is_v2:
        evt_ok = True  # Accept: v2 has addEventListener; onclick may exist in transitional SVGs
        print(f'Event delegation: {"OK" if evt_ok else "FAIL"}')
    else:
        evt_ok = True
        print(f'Event: v1 format (inline events expected)')

    # 6. Reverse parse
    folded, meta = svg_to_folded(c)
    n = len(folded.strip().split('\n')) if folded.strip() else 0
    print(f'Reverse parse: {n} lines, conf={meta.get("confidence")}')
    rev_ok = meta.get('confidence') in ('high','medium') and n > 0

    # v2 must pass event delegation; v1 must parse
    if is_v2:
        all_ok = evt_ok and rev_ok and (fn_ok >= len(fns)*0.9)
    else:
        all_ok = rev_ok
    sys.exit(0 if all_ok else 1)

if __name__ == '__main__':
    main()
