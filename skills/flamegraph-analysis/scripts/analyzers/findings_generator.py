#!/usr/bin/env python3
# =============================================================================
# 脚本：findings_generator.py
# 用途：生成结构化的 Findings 列表，用于 HTML 和 Markdown 报告（通用多语言支持）
# 使用：作为模块被 import 使用，生成性能问题的结构化发现列表
# 参数：通过 FindingGenerator 类传入数据
# =============================================================================

import json
from typing import Dict, List, Any, Tuple
import sys
import os

# 添加当前模块路径
if __name__ == '__main__':
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

SEVERITY_CONFIG = {
    'critical': {'icon': '🔴', 'label': 'Critical', 'threshold': 0.25},
    'high': {'icon': '🟠', 'label': 'High', 'threshold': 0.1},
    'medium': {'icon': '🟡', 'label': 'Medium', 'threshold': 0.05},
    'low': {'icon': '🟢', 'label': 'Low', 'threshold': 0.01}
}

# 要过滤的系统库和框架函数（这些是基础设施，不应作为主要问题报告）
SYSTEM_FRAMES = {
    '[libpthread-', '[libc-', '[libjvm.so]', '[libnio.so]',
    'start_thread', 'java_start', 'JavaThread::',
    'thread_entry', 'JavaCalls::', 'call_stub_',
    'Interpreter_[j]', 'swapper', 'wrk', 'perf',
    # 内核函数
    'sys_write_[k]', 'vfs_write_[k]', 'do_sync_write_[k]', 'sock_aio_write_[k]',
    'native_write_msr_safe_[k]', 'native_load_tls_[k]', '__switch_to_[k]',
    'start_secondary_[k]', 'x86_64_start_kernel_[k]', 'intel_idle_[k]',
    'menu_select_[k]', 'generic_exec_single_[k]', 'kfree_[k]',
    'link_path_walk_[k]', 'ep_send_events_proc_[k]', 'tcp_sendmsg_[k]',
    # Go runtime
    'runtime.', 'runtime/',
    # Python runtime
    '_PyEval_EvalFrameDefault', 'PyEval_EvalFrame',
    # C++ standard library
    'std::', '__libc_start_main',
    # Rust standard library
    'core::', 'alloc::', 'std::'
}

# 语言特定配置
LANGUAGE_CONFIG = {
    'java': {
        'name': 'Java',
        'suffix': '[j]',
        'title_suffix': 'Java 函数 CPU 消耗',
        'desc_prefix': 'Java 函数',
        'impact_prefix': '该 Java 函数',
        'detect_desc': '通过 Java 帧分析检测到的热点函数',
        'recommendations': [
            {'priority_marker': '①', 'label': '分析热点代码', 'detail': '使用 Profiler 定位具体的热点代码路径。'},
            {'priority_marker': '②', 'label': '算法优化', 'detail': '检查是否存在低效算法或重复计算。'},
            {'priority_marker': '③', 'label': '缓存优化', 'detail': '考虑引入缓存减少重复计算。'}
        ]
    },
    'go': {
        'name': 'Go',
        'suffix': '[g]',
        'title_suffix': 'Go 函数 CPU 消耗',
        'desc_prefix': 'Go 函数',
        'impact_prefix': '该 Go 函数',
        'detect_desc': '通过 Go 帧分析检测到的热点函数',
        'recommendations': [
            {'priority_marker': '①', 'label': '分析热点代码', 'detail': '使用 pprof 定位具体的热点代码路径。'},
            {'priority_marker': '②', 'label': '并发优化', 'detail': '检查 goroutine 使用是否合理。'},
            {'priority_marker': '③', 'label': '内存优化', 'detail': '减少不必要的内存分配。'}
        ]
    },
    'python': {
        'name': 'Python',
        'suffix': '[p]',
        'title_suffix': 'Python 函数 CPU 消耗',
        'desc_prefix': 'Python 函数',
        'impact_prefix': '该 Python 函数',
        'detect_desc': '通过 Python 帧分析检测到的热点函数',
        'recommendations': [
            {'priority_marker': '①', 'label': '分析热点代码', 'detail': '使用 cProfile 定位具体的热点代码路径。'},
            {'priority_marker': '②', 'label': '使用 C 扩展', 'detail': '考虑将热点代码用 C/Cython 重写。'},
            {'priority_marker': '③', 'label': 'JIT 编译', 'detail': '考虑使用 PyPy 或 Numba 进行 JIT 编译。'}
        ]
    },
    'cpp': {
        'name': 'C++',
        'suffix': '[c]',
        'title_suffix': 'C++ 函数 CPU 消耗',
        'desc_prefix': 'C++ 函数',
        'impact_prefix': '该 C++ 函数',
        'detect_desc': '通过 C++ 帧分析检测到的热点函数',
        'recommendations': [
            {'priority_marker': '①', 'label': '分析热点代码', 'detail': '使用 perf 或 Intel VTune 定位热点。'},
            {'priority_marker': '②', 'label': '算法优化', 'detail': '检查是否存在低效算法或内存访问模式。'},
            {'priority_marker': '③', 'label': '编译器优化', 'detail': '启用更高等级的编译器优化。'}
        ]
    },
    'rust': {
        'name': 'Rust',
        'suffix': '[r]',
        'title_suffix': 'Rust 函数 CPU 消耗',
        'desc_prefix': 'Rust 函数',
        'impact_prefix': '该 Rust 函数',
        'detect_desc': '通过 Rust 帧分析检测到的热点函数',
        'recommendations': [
            {'priority_marker': '①', 'label': '分析热点代码', 'detail': '使用 perf 或 flamegraph 定位热点。'},
            {'priority_marker': '②', 'label': '内存优化', 'detail': '减少不必要的内存分配和拷贝。'},
            {'priority_marker': '③', 'label': '并发优化', 'detail': '检查 async/await 使用是否合理。'}
        ]
    }
}

# 框架特定配置（跨语言）
FRAMEWORK_CONFIG = {
    'netty': {
        'patterns': ['fireChannelRead', 'fireChannelReadComplete', 'processSelectedKeys', 
                     'channelRead', 'flush', 'write', 'read'],
        'title_suffix': 'Netty 事件处理耗时',
        'desc_prefix': 'Netty 函数',
        'impact_prefix': '该 Netty 函数',
        'detect_desc': '通过 Netty 热点分析检测到的高频调用函数',
        'recommendations': [
            {'priority_marker': '①', 'label': '检查 ChannelHandler 链', 'detail': '分析 pipeline 中的 handler 是否过多或存在阻塞操作。'},
            {'priority_marker': '②', 'label': '启用批量读写', 'detail': '考虑使用 ByteBuf 池化和批量操作减少 GC 压力。'},
            {'priority_marker': '③', 'label': '异步化处理', 'detail': '将耗时操作移到 EventLoop 外部执行。'}
        ]
    },
    'tokio': {
        'patterns': ['tokio::', 'poll', 'waker', 'runtime'],
        'title_suffix': 'Tokio 异步运行时耗时',
        'desc_prefix': 'Tokio 函数',
        'impact_prefix': '该 Tokio 函数',
        'detect_desc': '通过 Tokio 热点分析检测到的高频调用函数',
        'recommendations': [
            {'priority_marker': '①', 'label': '检查任务调度', 'detail': '分析任务是否合理分配到工作线程。'},
            {'priority_marker': '②', 'label': '减少唤醒次数', 'detail': '优化事件循环的唤醒频率。'},
            {'priority_marker': '③', 'label': '使用高效 I/O', 'detail': '考虑使用 io_uring 或其他高性能 I/O 接口。'}
        ]
    },
    'runtime': {
        'patterns': ['runtime.', 'gc', 'malloc', 'free', 'sync'],
        'title_suffix': '运行时函数耗时',
        'desc_prefix': '运行时函数',
        'impact_prefix': '该运行时函数',
        'detect_desc': '通过运行时热点分析检测到的高频调用函数',
        'recommendations': [
            {'priority_marker': '①', 'label': '内存优化', 'detail': '减少内存分配频率，使用对象池。'},
            {'priority_marker': '②', 'label': 'GC 调优', 'detail': '调整垃圾回收参数优化性能。'},
            {'priority_marker': '③', 'label': '同步优化', 'detail': '减少锁竞争，使用无锁数据结构。'}
        ]
    }
}


class FindingGenerator:
    def __init__(self, stacks: List[Tuple[str, int]], total_samples: int,
                 hotspots: Dict = None, attribution: Dict = None):
        self.stacks = stacks
        self.total_samples = total_samples
        self.hotspots = hotspots or {}
        self.attribution = attribution or {}
        self.findings = []
        self.finding_counter = 1
        self.seen_frames = set()
        self.detected_language = self.hotspots.get('detected_language')

    def generate_all(self) -> List[Dict[str, Any]]:
        """生成所有 Findings（从多个数据源生成）"""
        self.findings = []
        self.seen_frames = set()
        self.finding_counter = 1

        # 1. 从框架热点生成 findings（通用）
        self._from_framework_hotspots()
        
        # 2. 从语言特定帧生成 findings（根据检测到的语言）
        self._from_language_frames()
        
        # 3. 从 bottom_up 生成（叶节点热点，过滤系统库）
        self._from_bottom_up_filtered()

        # 4. 从 top_down 生成（只选取重要的业务相关热点）
        self._from_top_down_filtered()

        # 对 findings 排序
        self._sort_findings()

        # 过滤掉被其他发现项包含的父函数发现项
        self._filter_redundant_findings()

        return self.findings

    def _is_system_frame(self, frame: str) -> bool:
        """判断是否为系统/框架帧，不应作为主要问题报告"""
        frame_lower = frame.lower()
        for sys_frame in SYSTEM_FRAMES:
            if sys_frame.lower() in frame_lower:
                return True
        return False

    def _from_framework_hotspots(self):
        """从框架热点数据生成 findings（通用）"""
        if 'framework_hotspots' not in self.hotspots:
            return
        
        # 确定适用的框架配置
        detected_framework = self._detect_framework()
        
        for hotspot in self.hotspots['framework_hotspots']:
            if not isinstance(hotspot, dict):
                continue
            
            name = hotspot.get('name', hotspot.get('frame', ''))
            if not name or self._is_system_frame(name):
                continue
            
            count = hotspot.get('samples', hotspot.get('count', 0))
            percent = count / self.total_samples if self.total_samples > 0 else 0
            
            # 过滤掉 LOW 级别（小于1%）和重复的
            if percent < 0.01 or name in self.seen_frames:
                continue
            
            severity = self._determine_severity(percent)
            if severity == 'low':
                continue
            
            # 获取框架配置
            config = FRAMEWORK_CONFIG.get(detected_framework, FRAMEWORK_CONFIG['runtime'])
            
            # 构建路径
            path = self._build_path_from_context(hotspot.get('top_contexts', []))
            if not path:
                path = ['all', name]
            
            self.seen_frames.add(name)
            
            finding = {
                'id': f'F-{self.finding_counter:03d}',
                'severity': severity,
                'title': f'{name[:60]} - {config["title_suffix"]}',
                'description': f'{config["desc_prefix"]} `{name}` 消耗了 {percent*100:.1f}% 的 CPU 时间，可能是性能瓶颈。',
                'evidence_path': path,
                'evidence_leaf': name,
                'evidence_stack': self._format_evidence_stack(path, percent),
                'metrics': {
                    'samples': count,
                    'percent': round(percent * 100, 1)
                },
                'business_impact': [
                    f'{config["impact_prefix"]} 消耗了 {percent*100:.1f}% 的 CPU，可能影响系统性能。',
                    '高频调用的函数可能导致线程阻塞或延迟增加。'
                ],
                'recommendations': config['recommendations'],
                'detection_explanation': config['detect_desc'],
                'one_sentence': f'{config["desc_prefix"]} `{name[:60]}` 消耗了 {percent*100:.1f}% 的 CPU 时间。',
                'severity_icon': SEVERITY_CONFIG[severity]['icon'],
                'severity_label': SEVERITY_CONFIG[severity]['label']
            }
            
            self.findings.append(finding)
            self.finding_counter += 1

    def _detect_framework(self) -> str:
        """检测主要框架"""
        if 'framework_hotspots' not in self.hotspots:
            return 'runtime'
        
        for hotspot in self.hotspots['framework_hotspots']:
            name = hotspot.get('name', hotspot.get('frame', ''))
            for framework, config in FRAMEWORK_CONFIG.items():
                for pattern in config['patterns']:
                    if pattern.lower() in name.lower():
                        return framework
        
        return 'runtime'

    def _from_language_frames(self):
        """从语言特定帧数据生成 findings（通用）"""
        if not self.detected_language:
            return
        
        lang_key = f'{self.detected_language}_frames'
        if lang_key not in self.hotspots:
            return
        
        lang_config = LANGUAGE_CONFIG.get(self.detected_language, LANGUAGE_CONFIG['java'])
        lang_hotspots = self.hotspots[lang_key][:10]
        
        for hotspot in lang_hotspots:
            if not isinstance(hotspot, dict):
                continue
            
            name = hotspot.get('name', hotspot.get('frame', ''))
            if not name or self._is_system_frame(name):
                continue
            
            count = hotspot.get('samples', hotspot.get('count', 0))
            percent = count / self.total_samples if self.total_samples > 0 else 0
            
            if percent < 0.01 or name in self.seen_frames:
                continue
            
            severity = self._determine_severity(percent)
            if severity == 'low':
                continue
            
            path = self._build_path_from_context(hotspot.get('top_contexts', []))
            if not path:
                path = ['all', name]
            
            self.seen_frames.add(name)
            
            finding = {
                'id': f'F-{self.finding_counter:03d}',
                'severity': severity,
                'title': f'{name[:60]} - {lang_config["title_suffix"]}',
                'description': f'{lang_config["desc_prefix"]} `{name}` 消耗了 {percent*100:.1f}% 的 CPU 时间。',
                'evidence_path': path,
                'evidence_leaf': name,
                'evidence_stack': self._format_evidence_stack(path, percent),
                'metrics': {
                    'samples': count,
                    'percent': round(percent * 100, 1)
                },
                'business_impact': [f'{lang_config["impact_prefix"]} 消耗了 {percent*100:.1f}% 的 CPU，可能是业务性能瓶颈。'],
                'recommendations': lang_config['recommendations'],
                'detection_explanation': lang_config['detect_desc'],
                'one_sentence': f'{lang_config["desc_prefix"]} `{name[:60]}` 消耗了 {percent*100:.1f}% 的 CPU 时间。',
                'severity_icon': SEVERITY_CONFIG[severity]['icon'],
                'severity_label': SEVERITY_CONFIG[severity]['label']
            }
            
            self.findings.append(finding)
            self.finding_counter += 1

    def _from_bottom_up_filtered(self):
        """从 bottom_up 数据生成 findings（叶节点热点，过滤系统库）
        
        bottom_up 按叶节点（调用栈的最后一帧）聚合，适合捕获真正的 CPU 热点。
        与 _from_framework_hotspots 和 _from_language_frames 类似，也是基于
        叶节点的分析，但使用更通用的过滤规则。
        """
        if 'bottom_up' not in self.hotspots:
            return
        
        for hotspot in self.hotspots['bottom_up'][:10]:
            if not isinstance(hotspot, dict):
                continue
            
            name = hotspot.get('name', hotspot.get('frame', ''))
            if not name or self._is_system_frame(name):
                continue
            
            if name in self.seen_frames:
                continue
            
            count = hotspot.get('samples', hotspot.get('count', 0))
            percent = count / self.total_samples if self.total_samples > 0 else 0
            
            if percent < 0.01:
                continue
            
            severity = self._determine_severity(percent)
            if severity == 'low':
                continue
            
            path = self._build_path_from_context(hotspot.get('top_contexts', []))
            if not path:
                path = ['all', name]
            
            self.seen_frames.add(name)
            
            finding = {
                'id': f'F-{self.finding_counter:03d}',
                'severity': severity,
                'title': f'{name[:60]} CPU 使用率高',
                'description': f'{name[:80]} 消耗了 {percent*100:.1f}% 的 CPU 时间。',
                'evidence_path': path,
                'evidence_leaf': name,
                'evidence_stack': self._format_evidence_stack(path, percent),
                'metrics': {
                    'samples': count,
                    'percent': round(percent * 100, 1)
                },
                'business_impact': [f'该函数消耗了 {percent*100:.1f}% 的 CPU，可能是性能瓶颈。'],
                'recommendations': [
                    {'priority_marker': '①', 'label': '分析热点', 'detail': '使用火焰图定位具体的热点代码路径。'},
                    {'priority_marker': '②', 'label': '审查算法', 'detail': '检查此函数是否可以优化或缓存。'}
                ],
                'detection_explanation': '通过自底向上分析检测到的叶节点 CPU 消耗者。',
                'one_sentence': f'{name[:80]} 消耗了 {percent*100:.1f}% 的 CPU 时间。',
                'severity_icon': SEVERITY_CONFIG[severity]['icon'],
                'severity_label': SEVERITY_CONFIG[severity]['label']
            }
            
            self.findings.append(finding)
            self.finding_counter += 1

    def _from_top_down_filtered(self):
        """从 top_down 数据生成 findings（过滤系统库）"""
        if 'top_down' not in self.hotspots:
            return
        
        # 只处理非系统帧的热点
        filtered_hotspots = [
            h for h in self.hotspots['top_down'][:10]
            if isinstance(h, dict) and not self._is_system_frame(h.get('frame', ''))
        ]
        
        for hotspot in filtered_hotspots:
            name = hotspot.get('name', hotspot.get('frame', ''))
            if not name or name in self.seen_frames:
                continue
            
            count = hotspot.get('samples', hotspot.get('count', 0))
            percent = count / self.total_samples if self.total_samples > 0 else 0
            
            if percent < 0.01:
                continue
            
            severity = self._determine_severity(percent)
            if severity == 'low':
                continue
            
            path = ['all', name]
            self.seen_frames.add(name)
            
            finding = {
                'id': f'F-{self.finding_counter:03d}',
                'severity': severity,
                'title': f'{name[:60]} CPU 使用率高',
                'description': f'{name[:80]} 消耗了 {percent*100:.1f}% 的 CPU 时间。',
                'evidence_path': path,
                'evidence_leaf': name,
                'evidence_stack': self._format_evidence_stack(path, percent),
                'metrics': {
                    'samples': count,
                    'percent': round(percent * 100, 1)
                },
                'business_impact': [f'该函数消耗了 {percent*100:.1f}% 的 CPU，可能是性能瓶颈。'],
                'recommendations': [
                    {'priority_marker': '①', 'label': '分析热点', 'detail': '使用火焰图定位具体的热点代码路径。'},
                    {'priority_marker': '②', 'label': '审查算法', 'detail': '检查此函数是否可以优化或缓存。'}
                ],
                'detection_explanation': '通过自顶向下分析检测到的顶级 CPU 消耗者。',
                'one_sentence': f'{name[:80]} 消耗了 {percent*100:.1f}% 的 CPU 时间。',
                'severity_icon': SEVERITY_CONFIG[severity]['icon'],
                'severity_label': SEVERITY_CONFIG[severity]['label']
            }
            
            self.findings.append(finding)
            self.finding_counter += 1

    def _build_path_from_context(self, contexts: List[Dict]) -> List[str]:
        """从上下文构建路径（保留完整路径，用于火焰图匹配）"""
        if not contexts:
            return []
        
        # 取第一个上下文构建路径
        first_context = contexts[0].get('context', '')
        if not first_context:
            return []
        
        # 保留完整路径，不过滤系统帧
        # 因为火焰图匹配需要完整的路径才能正确高亮
        frames = first_context.split(';')
        
        if frames:
            # 返回完整路径，确保能定位到目标热点帧
            return ['all'] + frames
        return []

    def _determine_severity(self, percent: float) -> str:
        """根据百分比确定严重程度"""
        if percent >= SEVERITY_CONFIG['critical']['threshold']:
            return 'critical'
        elif percent >= SEVERITY_CONFIG['high']['threshold']:
            return 'high'
        elif percent >= SEVERITY_CONFIG['medium']['threshold']:
            return 'medium'
        else:
            return 'low'

    def _format_evidence_stack(self, path: List[str], percent: float) -> List[Dict]:
        """格式化证据栈用于 Markdown"""
        stack = []
        for i, frame in enumerate(path):
            indent = '  ' * i
            pct_str = f'({percent*100:.1f}%)' if i == len(path)-1 else ''
            annotation = '← evidence' if i == len(path)-1 else ''
            
            stack.append({
                'indent': indent,
                'frame': frame,
                'spaces': ' ' * (50 - len(frame[:50])),
                'percent': pct_str,
                'annotation': annotation
            })
        return stack

    def _sort_findings(self):
        """按严重程度和 CPU 消耗排序"""
        severity_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
        
        self.findings.sort(key=lambda x: (
            severity_order.get(x['severity'], 3),
            -x['metrics']['percent']
        ))

    def _filter_redundant_findings(self):
        """过滤掉被其他发现项包含的父函数发现项
        
        规则：
        1. 如果发现项 A 的 evidence_path 是发现项 B 的 evidence_path 的前缀，移除 A
        2. 如果两个发现项的 evidence_path 相同，比较 evidence_leaf 在路径中的位置，
           保留更深的（子帧），移除较浅的（父帧）
        3. 如果发现项 A 的 evidence_leaf 是发现项 B 的 evidence_path 中的某一帧（非最后一帧），
           且 B 的 CPU 占比 >= A 的 CPU 占比的 80%，说明 A 的 CPU 消耗主要由 B 贡献，移除 A
        """
        if len(self.findings) <= 1:
            return
        
        to_remove = set()
        
        for i, finding_a in enumerate(self.findings):
            if i in to_remove:
                continue
            
            path_a = finding_a.get('evidence_path', [])
            leaf_a = finding_a.get('evidence_leaf', '')
            cpu_a = finding_a.get('metrics', {}).get('percent', 0)
            
            if len(path_a) < 2:
                continue
            
            for j, finding_b in enumerate(self.findings):
                if i == j or j in to_remove:
                    continue
                
                path_b = finding_b.get('evidence_path', [])
                leaf_b = finding_b.get('evidence_leaf', '')
                cpu_b = finding_b.get('metrics', {}).get('percent', 0)
                
                if len(path_b) < 2:
                    continue
                
                # 情况1：path_a 是 path_b 的前缀（A 是 B 的祖先帧）
                if len(path_a) < len(path_b) and path_a == path_b[:len(path_a)]:
                    to_remove.add(i)
                    break
                
                # 情况2：路径相同，比较 evidence_leaf 的位置
                if path_a == path_b:
                    try:
                        idx_a = path_a.index(leaf_a) if leaf_a in path_a else -1
                        idx_b = path_b.index(leaf_b) if leaf_b in path_b else -1
                        
                        # 如果 A 的 leaf 在 B 的 leaf 之前（A 是 B 的父帧），移除 A
                        if idx_a != -1 and idx_b != -1 and idx_a < idx_b:
                            to_remove.add(i)
                            break
                    except ValueError:
                        pass
                
                # 情况3：A 的 evidence_leaf 在 B 的 evidence_path 中（非最后一帧），
                # 且 B 的 CPU 占比接近 A 的 CPU 占比，说明 A 的消耗主要由 B 贡献
                if leaf_a in path_b:
                    idx_in_b = path_b.index(leaf_a)
                    # 不是最后一帧，说明后面还有子帧
                    if idx_in_b < len(path_b) - 1:
                        # 如果 B 的 CPU 占比 >= A 的 80%，说明 A 的消耗主要由 B 贡献
                        if cpu_b >= cpu_a * 0.8:
                            to_remove.add(i)
                            break
        
        if to_remove:
            self.findings = [f for i, f in enumerate(self.findings) if i not in to_remove]
            # 重新分配 ID
            for idx, finding in enumerate(self.findings, 1):
                finding['id'] = f'F-{idx:03d}'


def main():
    if len(sys.argv) < 3:
        print('使用：python findings_generator.py --input <folded_file> --hotspots <hotspot_json> --output <output_json>')
        sys.exit(1)
    
    input_file = None
    hotspots_file = None
    output_file = None
    
    i = 1
    while i < len(sys.argv):
        if sys.argv[i] == '--input' and i + 1 < len(sys.argv):
            input_file = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == '--hotspots' and i + 1 < len(sys.argv):
            hotspots_file = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == '--output' and i + 1 < len(sys.argv):
            output_file = sys.argv[i + 1]
            i += 2
        else:
            i += 1
    
    if not input_file or not hotspots_file:
        print('错误：缺少输入参数')
        print('使用：python findings_generator.py --input <folded_file> --hotspots <hotspot_json> --output <output_json>')
        sys.exit(1)
    
    # 读取 folded 文件
    with open(input_file, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    
    stacks = []
    total = 0
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.rsplit(None, 1)
        if len(parts) == 2:
            stack, count = parts
            try:
                stacks.append((stack, int(count)))
                total += int(count)
            except ValueError:
                pass
    
    # 读取 hotspots 文件
    with open(hotspots_file, 'r', encoding='utf-8') as f:
        hotspots = json.load(f)
    
    # 生成 findings
    generator = FindingGenerator(stacks, total, hotspots)
    findings = generator.generate_all()
    
    # 输出结果
    result = {'findings': findings}
    
    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        print(f'Generated findings in {output_file}')
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
