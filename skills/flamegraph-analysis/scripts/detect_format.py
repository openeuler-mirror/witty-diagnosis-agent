#!/usr/bin/env python3
# =============================================================================
# 脚本：detect_format.py
# 用途：自动检测性能分析文件格式
# 使用：python3 detect_format.py <file_path>
# 输出：JSON格式，包含format、confidence、needs_conversion、adapter等信息
# =============================================================================
import sys
import json
from pathlib import Path
from typing import Optional

MAGIC_SIGNATURES = {
    b'\x1f\x8b': 'gzip',  # pprof protobuf compressed
    b'{"nodes': 'cpuprofile',  # Chrome cpuprofile JSON
    b'{"startTime': 'cpuprofile',  # Chrome cpuprofile JSON alternative
    '<svg': 'svg',
    '<html': 'svg',  # HTML with embedded SVG
    '<?xml': 'svg',
    '{"schemaVersion":': 'pprof',  # pprof JSON format
}

# 格式检测模式
FORMAT_PATTERNS = {
    'folded': {
        'pattern': lambda line: ';' in line and line.rsplit(None, 1)[-1].isdigit(),
        'description': '折叠堆栈格式'
    },
    'perf': {
        'pattern': lambda line: ': cycles:' in line or ': events:' in line or ': cpu-clock:' in line or 'PERF_RECORD' in line,
        'description': 'Linux perf 输出'
    },
    'dtrace': {
        'pattern': lambda line: '`' in line and '+0x' in line,
        'description': 'DTrace 堆栈输出'
    },
    'bcc': {
        'pattern': lambda line: line.strip().isdigit(),
        'description': 'BCC/BPF 输出'
    },
    'jstack': {
        'pattern': lambda line: line.startswith('"') and ('daemon prio=' in line or 'prio=' in line) or 'java.lang.Thread.State:' in line,
        'description': 'Java jstack 线程转储'
    },
    'vtune': {
        'pattern': lambda line: line.startswith('Module:') or line.startswith('Function:') or line.startswith('Stack trace:'),
        'description': 'Intel VTune 输出'
    },
    'etw': {
        'pattern': lambda line: 'EventTrace' in line or 'Microsoft-Windows-Kernel' in line or 'ProviderGuid' in line,
        'description': 'Windows ETW 追踪'
    },
    'asyncprofiler': {
        'pattern': lambda line: 'async-profiler' in line or 'Name:' in line and 'Category:' in line,
        'description': 'async-profiler 输出'
    },
    'v8log': {
        'pattern': lambda line: line.startswith('tick') or line.startswith('code-creation') or line.startswith('shared-library'),
        'description': 'V8 日志格式'
    },
    'bpftrace': {
        'pattern': lambda line: line.startswith('@[') or (line.startswith('@[') and ',' in line),
        'description': 'bpftrace 输出'
    },
    'faulthandler': {
        'pattern': lambda line: line.startswith('Thread ') or (line.startswith('  File "') and 'line ' in line and ' in ' in line),
        'description': 'Python faulthandler 输出'
    },
    'stap': {
        'pattern': lambda line: line.startswith('0x') and ': ' in line and '[' in line,
        'description': 'SystemTap 输出'
    },
    'pmc': {
        'pattern': lambda line: 'END' in line and len(line.split()) >= 13,
        'description': 'FreeBSD pmcstat 输出'
    },
    'ljp': {
        'pattern': lambda line: line.strip().isdigit() and line.count(' ') == 0,
        'description': 'Lightweight Java Profiler 输出'
    },
    'java-exceptions': {
        'pattern': lambda line: 'Exception' in line or 'Error' in line or line.startswith('        at '),
        'description': 'Java 异常堆栈'
    },
    'gdb': {
        'pattern': lambda line: line.startswith('#') and line[1:].isdigit() and ' in ' in line,
        'description': 'gdb 调试器输出'
    },
    'wcp': {
        'pattern': lambda line: line.startswith('Thread ') or line.startswith('Count:'),
        'description': 'wallClockProfiler 输出'
    },
    'sample': {
        'pattern': lambda line: line.startswith('sample ') or line.startswith('Sample '),
        'description': '通用采样格式'
    },
    'xdebug': {
        'pattern': lambda line: len(line.split('\t')) >= 4 and line.split('\t')[2].isdigit(),
        'description': 'PHP Xdebug 输出'
    },
}

def detect_format(file_path: str) -> dict:
    result = {
        'format': 'unknown',
        'confidence': 'low',
        'metadata': {},
        'needs_conversion': True,
    }

    path = Path(file_path)
    if not path.exists():
        result['error'] = f'File not found: {file_path}'
        return result

    with open(file_path, 'rb') as f:
        header = f.read(8192)

    if isinstance(header, bytes):
        try:
            header_text = header.decode('utf-8', errors='replace')
        except:
            header_text = ''
    else:
        header_text = header

    # 首先检查魔法签名
    for magic, fmt in MAGIC_SIGNATURES.items():
        if isinstance(magic, str):
            if header_text.startswith(magic):
                result['format'] = fmt
                result['confidence'] = 'high'
                result['needs_conversion'] = fmt not in ['folded']
                break
        else:
            if header.startswith(magic):
                result['format'] = fmt
                result['confidence'] = 'high'
                result['needs_conversion'] = fmt not in ['folded']
                break

    # 如果还未识别，检查行模式
    if result['format'] == 'unknown':
        matched_lines = {}
        for line in header_text.split('\n')[:30]:
            line = line.strip()
            if not line:
                continue
            for fmt, config in FORMAT_PATTERNS.items():
                try:
                    if config['pattern'](line):
                        if fmt not in matched_lines:
                            matched_lines[fmt] = 0
                        matched_lines[fmt] += 1
                except:
                    pass
        
        # 选择匹配最多的格式
        if matched_lines:
            best_fmt = max(matched_lines, key=matched_lines.get)
            result['format'] = best_fmt
            result['confidence'] = 'high' if matched_lines[best_fmt] >= 3 else 'medium'
            result['needs_conversion'] = best_fmt not in ['folded']

    # 额外的格式识别和元数据提取
    if result['format'] == 'svg':
        if 'flamegraph.pl' in header_text:
            result['metadata']['generator'] = 'flamegraph.pl'
        elif 'async-profiler' in header_text:
            result['metadata']['generator'] = 'async-profiler'
        elif 'speedscope' in header_text:
            result['metadata']['generator'] = 'speedscope'
        elif 'diff' in header_text.lower():
            result['format'] = 'svg-diff'
            result['confidence'] = 'low'
            result['error'] = 'Differential SVG is not supported for reverse engineering'

    if result['format'] == 'gzip':
        import gzip
        try:
            decompressed = gzip.decompress(header)
            if b'protobuf' in decompressed[:1000] or b'\x0a' in decompressed[:100]:
                result['format'] = 'pprof'
                result['confidence'] = 'high'
                result['metadata']['compressed'] = True
        except:
            result['format'] = 'unknown'

    if result['format'] in FORMAT_PATTERNS:
        result['metadata']['description'] = FORMAT_PATTERNS[result['format']]['description']

    # 设置适配器名称
    if result['format'] != 'unknown':
        adapter_name = f"{result['format']}_to_folded"
        result['adapter'] = adapter_name
        result['metadata']['adapter_description'] = get_adapter_description(result['format'])

    return result

def get_adapter_description(fmt: str) -> str:
    """获取适配器描述"""
    descriptions = {
        'folded': '无需转换，已为折叠格式',
        'perf': 'perf_to_folded.py - Linux perf 输出转折叠格式',
        'dtrace': 'dtrace_to_folded.py - DTrace 堆栈转折叠格式',
        'bcc': 'bcc_to_folded.py - BCC/BPF 输出转折叠格式',
        'jstack': 'jstack_to_folded.py - Java jstack 转折叠格式',
        'vtune': 'vtune_to_folded.py - Intel VTune 输出转折叠格式',
        'etw': 'etw_to_folded.py - Windows ETW 追踪转折叠格式',
        'asyncprofiler': 'asyncprofiler_to_folded.py - async-profiler 转折叠格式',
        'v8log': 'v8log_to_folded.py - V8 日志转折叠格式',
        'cpuprofile': 'cpuprofile_to_folded.py - Chrome cpuprofile 转折叠格式',
        'pprof': 'pprof_to_folded.py - pprof 格式转折叠格式',
        'svg': 'svg_to_folded.py - SVG 火焰图逆向解析',
        'bpftrace': 'bpftrace_to_folded.py - bpftrace 输出转折叠格式',
        'faulthandler': 'faulthandler_to_folded.py - Python faulthandler 转折叠格式',
        'stap': 'stap_to_folded.py - SystemTap 输出转折叠格式',
        'pmc': 'pmc_to_folded.py - FreeBSD pmcstat 转折叠格式',
        'ljp': 'ljp_to_folded.py - Lightweight Java Profiler 转折叠格式',
        'java-exceptions': 'java_exceptions_to_folded.py - Java 异常堆栈转折叠格式',
        'gdb': 'gdb_to_folded.py - gdb 调试器输出转折叠格式',
        'wcp': 'wcp_to_folded.py - wallClockProfiler 转折叠格式',
        'sample': 'sample_to_folded.py - 通用采样格式转折叠格式',
        'xdebug': 'xdebug_to_folded.py - PHP Xdebug 输出转折叠格式',
    }
    return descriptions.get(fmt, f"{fmt}_to_folded.py")

def main():
    if len(sys.argv) < 2:
        print(json.dumps({'error': 'Usage: detect_format.py <file_path>'}))
        sys.exit(1)

    result = detect_format(sys.argv[1])
    print(json.dumps(result, indent=2, ensure_ascii=False))

if __name__ == '__main__':
    main()