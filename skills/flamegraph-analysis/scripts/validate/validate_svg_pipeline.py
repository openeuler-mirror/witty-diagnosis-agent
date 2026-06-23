#!/usr/bin/env python3
"""
validate_svg_pipeline.py — HTML -> SVG -> 反向解析 一键验证
Usage: python3 validate_svg_pipeline.py
Return: 0 = all pass, 1 = failed
"""
import json, re, subprocess, sys, os, tempfile
SAMPLE_DIR = r'G:\witty-diagnosis-agent\memleak-temp-repo\flamegraph-samples'
TMPL_PATH = r'G:\witty-diagnosis-agent\memleak-temp-repo\skills\flamegraph-analysis\templates\flamegraph-viewer.html'
sys.path.insert(0, r'G:\witty-diagnosis-agent\memleak-temp-repo\skills\flamegraph-analysis\scripts\adapters')
from svg_to_folded import svg_to_folded

def extract_profile(html_path):
    with open(html_path, 'r', encoding='utf-8') as f:
        html = f.read()
    m = re.search(r'<script id="profile-data" type="application/json">(.*?)</script>', html, re.DOTALL)
    return json.loads(m.group(1)) if m else None

def gen_svg(profile_data):
    with open(TMPL_PATH, 'r', encoding='utf-8') as f:
        tmpl = f.read()
    s = tmpl.find('function exportSvg() {')
    e = tmpl.find('function renderFindings()', s)
    fn = tmpl[s:e]
    script = '''const profileData = %s;
global.document = {createElement:function(t){return t==='a'?{download:'',href:'',click:function(){}}:{}}};
global.window = {open:function(){return null;}};
global.URL = {createObjectURL:function(){return'blob:';},revokeObjectURL:function(){}};
global.alert = function(){};
var _o=null;global.Blob=function(p){_o=p[0];};
%s
try{exportSvg();if(_o)process.stdout.write(_o);else{process.stderr.write('NO SVG\\n');process.exit(1);}}
catch(e){process.stderr.write(e.message+'\\n');process.exit(1);}
''' % (json.dumps(profile_data), fn)
    with tempfile.NamedTemporaryFile(mode='w', suffix='.js', delete=False, encoding='utf-8') as tf:
        tf.write(script)
        js_path = tf.name
    r = subprocess.run(['node', js_path], capture_output=True, text=True, timeout=30)
    os.unlink(js_path)
    return r.stdout if r.returncode == 0 else None

def main():
    samples = sorted([f for f in os.listdir(SAMPLE_DIR) if f.endswith('.html') and 'async' not in f])
    all_ok = True
    for fname in samples:
        path = os.path.join(SAMPLE_DIR, fname)
        data = extract_profile(path)
        if not data:
            print(f'FAIL {fname}: no profile data'); all_ok = False; continue
        svg = gen_svg(data)
        if not svg:
            print(f'FAIL {fname}: SVG gen failed'); all_ok = False; continue
        folded, meta = svg_to_folded(svg)
        n = len(folded.strip().split('\n')) if folded.strip() else 0
        ok = meta.get('confidence') in ('high', 'medium') and n > 0
        print(f'{"PASS" if ok else "FAIL"} {fname:40s} {data["value"]:>6d} samples folded={n:3d} conf={meta.get("confidence")}')
        if not ok:
            all_ok = False
    print(f'\n{"ALL PASS" if all_ok else "SOME FAILED"}')
    sys.exit(0 if all_ok else 1)

if __name__ == '__main__':
    main()
