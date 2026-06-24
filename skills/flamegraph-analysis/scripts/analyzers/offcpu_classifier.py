#!/usr/bin/env python3
# =============================================================================
# 脚本：offcpu_classifier.py
# 用途：Off-CPU 等待原因分类器
# 使用：python3 offcpu_classifier.py <folded_file> [--min-confidence W] [--json]
# 参数：
#   <folded_file>     : Off-CPU folded 文件
#   --min-confidence W : 最小置信度阈值（0-1，默认0.5）
#   --json            : 输出 JSON 格式
#   --help / -h       : 显示帮助信息
# 分类类型：
#   lock          : 锁等待（futex_wait、pthread_mutex_lock等）
#   disk_io       : 磁盘 I/O（io_schedule、wait_on_page_bit等）
#   network_io    : 网络 I/O（sk_wait_data、tcp_recvmsg等）
#   timer         : 定时器/睡眠（hrtimer_nanosleep、schedule_timeout等）
#   gc_pause      : GC 暂停（SafepointSynchronize、GC_task_thread等）
#   page_fault    : 页错误/交换（do_page_fault、swapin等）
#   thread_mgmt   : 线程管理（schedule、pthread_join等）
#   memory_alloc  : 内存分配（hugetlbfs_fault、out_of_memory等）
# =============================================================================
import sys
import json
import re
from collections import defaultdict

OFFCPU_PATTERNS = {
    'lock': {
        'futex_wait': 1.0, 'futex_wait_setup': 0.9,
        '__lll_lock_wait': 1.0, 'pthread_mutex_lock': 0.9,
        '__pthread_mutex_lock': 0.9, 'sync.(*Mutex).Lock': 1.0,
        'Monitor::wait': 1.0, 'Object.wait': 0.8,
        'pthread_cond_wait': 0.7, 'pthread_cond_timedwait': 0.7,
        'pthread_rwlock_wrlock': 0.8, 'pthread_rwlock_rdlock': 0.7,
        'pthread_spin_lock': 0.9, '__spin_lock': 0.9,
        'LockSupport.park': 0.8,
    },
    'disk_io': {
        'io_schedule': 1.0, 'wait_on_page_bit': 0.9,
        'folio_wait_bit': 0.9, 'blkdev_issue_flush': 0.8,
        'blk_mq_get_tag': 0.7, 'ext4_file_read': 0.8,
        'xfs_file_read': 0.8, 'nfs_read': 0.8,
        'filemap_fault': 0.7, 'page_fault': 0.7,
        '__do_page_fault': 0.7,
    },
    'network_io': {
        'sk_wait_data': 1.0, 'tcp_recvmsg': 0.9,
        'inet_recvmsg': 0.9, 'sock_recvmsg': 0.9,
        'tcp_sendmsg': 0.9, 'inet_sendmsg': 0.9,
        'sock_sendmsg': 0.9, 'epoll_wait': 0.8,
        'epoll_pwait': 0.8, 'sys_epoll_wait': 0.8,
        'poll_schedule_timeout': 0.7, 'do_select': 0.7,
        'inet_csk_accept': 0.8, 'tcp_v4_connect': 0.8,
    },
    'timer': {
        'hrtimer_nanosleep': 1.0, 'hrtimer_run_queues': 0.8,
        'schedule_timeout': 0.8, 'schedule_hrtimeout_range': 0.8,
        'do_nanosleep': 0.8, 'msleep': 0.7,
        'ssleep': 0.7, 'do_usleep_range': 0.7,
        'idle_cpu': 0.5,
    },
    'gc_pause': {
        'SafepointSynchronize::begin': 1.0, 'VMThread::execute': 1.0,
        'gcBgMarkWorker': 1.0, 'GC_task_thread': 1.0,
        'GC_locker::lock': 0.9, 'GCCause': 0.7,
    },
    'page_fault': {
        'do_page_fault': 1.0, 'handle_mm_fault': 0.9,
        'swapin': 1.0, 'folio_swapin': 0.9,
        'do_swap_page': 0.9, 'mmap_region': 0.7,
        'filemap_fault': 0.7,
    },
    'thread_mgmt': {
        'schedule': 0.5, 'finish_task_switch': 0.5,
        'pick_next_task_fair': 0.5, 'wait4': 0.6,
        'waitid': 0.6, 'do_wait': 0.6,
        'pthread_join': 0.7, 'Thread.join': 0.7,
        'sync.WaitGroup.Wait': 0.7, 'flush_signal': 0.5,
        'deliver_signal': 0.5,
    },
    'memory_alloc': {
        'hugetlbfs_fault': 0.8, 'alloc_huge_page': 0.8,
        'out_of_memory': 0.9, 'pagefault_out_of_memory': 0.9,
        'kmem_cache_alloc': 0.5, '____slab_alloc': 0.5,
        'kmem_cache_alloc': 0.5, '____slab_alloc': 0.5,
    },
    'signal_wait': {
        'sigtimedwait': 1.0, 'sigwaitinfo': 1.0,
        'do_sigtimedwait': 1.0, 'pause': 0.7,
        'do_pause': 0.7, 'flush_signals': 0.6,
        'signal_wakeup': 0.6,
    },
    'memory_wait': {
        'alloc_pages': 1.0, 'alloc_pages_vma': 0.9,
        'kswapd': 1.0, 'balance_pgdat': 0.9,
        'wakeup_kswapd': 0.8, 'shrink_page_list': 0.8,
        'reclaim_pages': 0.8, 'try_to_free_pages': 0.8,
        'compaction_alloc': 0.7, 'compact_zone': 0.7,
    },
    'barrier': {
        'pthread_barrier_wait': 1.0,
        'cyclic_barrier': 0.9,
        'java.util.concurrent.CyclicBarrier': 0.8,
        'CountDownLatch': 0.7,
    },
    'rcu_wait': {
        'synchronize_rcu': 1.0, 'rcu_barrier': 0.9,
        'call_rcu': 0.9, 'rcu_gp_kthread': 0.8,
    },
    'net_io_detailed': {
        'tcp_connect': 0.9, 'tls_handshake': 0.9,
        'dns_query': 0.8, 'ssl_connect': 0.9,
        'res_query': 0.8,
    },
}

def parse_folded(content: str):
    stacks = []
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.rsplit(None, 1)
        if len(parts) == 2:
            stack, count = parts
            try:
                count = int(count)
                stacks.append((stack, count))
            except ValueError:
                pass
    return stacks

def classify_offcpu(stacks, min_confidence=0.5):
    category_stats = {cat: {'samples': 0, 'count': 0, 'frames': set()} for cat in OFFCPU_PATTERNS}
    category_stats['unknown'] = {'samples': 0, 'count': 0, 'frames': set()}

    for stack, count in stacks:
        frames = stack.split(';')
        leaf = frames[-1] if frames else ''

        best_category = 'unknown'
        best_confidence = 0

        for cat_name, patterns in OFFCPU_PATTERNS.items():
            for pattern, confidence in patterns.items():
                if confidence >= min_confidence and pattern in leaf:
                    if confidence > best_confidence:
                        best_confidence = confidence
                        best_category = cat_name

        category_stats[best_category]['samples'] += count
        category_stats[best_category]['count'] += 1
        category_stats[best_category]['frames'].add(leaf)

    return category_stats

def main():
    if len(sys.argv) < 2:
        print('Usage: offcpu_classifier.py <folded_file> [--min-confidence W] [--json]')
        sys.exit(1)

    file_path = sys.argv[1]
    min_confidence = 0.5
    if '--min-confidence' in sys.argv:
        idx = sys.argv.index('--min-confidence')
        if idx + 1 < len(sys.argv):
            min_confidence = float(sys.argv[idx + 1])

    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    stacks = parse_folded(content)
    total = sum(c for _, c in stacks)
    results = classify_offcpu(stacks, min_confidence)

    category_names = {
        'lock': 'Lock & Synchronization',
        'disk_io': 'Disk I/O',
        'network_io': 'Network I/O',
        'timer': 'Timer & Sleep',
        'gc_pause': 'GC Pause',
        'page_fault': 'Page Fault & Swap',
        'thread_mgmt': 'Thread Management',
        'memory_alloc': 'Memory Allocation',
        'signal_wait': 'Signal Wait',
        'memory_wait': 'Memory Wait (Alloc/Reclaim)',
        'barrier': 'Barrier Synchronization',
        'rcu_wait': 'RCU Wait',
        'net_io_detailed': 'Network I/O (Detailed)',
        'unknown': 'Unknown/Other'
    }

    output = {
        'total_samples': total,
        'total_stacks': len(stacks),
        'categories': []
    }

    for cat, stats in results.items():
        if stats['samples'] > 0:
            pct = (stats['samples'] / total * 100) if total > 0 else 0
            output['categories'].append({
                'category': cat,
                'name': category_names.get(cat, cat),
                'samples': stats['samples'],
                'percent': round(pct, 2),
                'stack_count': stats['count'],
                'sample_frames': list(stats['frames'])[:10]
            })

    output['categories'].sort(key=lambda x: -x['percent'])

    if '--json' in sys.argv:
        print(json.dumps(output, indent=2))
    else:
        print("=" * 80)
        print(f"Off-CPU Classification - Total Samples: {total}")
        print("=" * 80)
        print(f"\n{'Category':<30} {'Samples':<12} {'Percent':<10}")
        print("-" * 55)
        for cat in output['categories']:
            print(f"{cat['name']:<30} {cat['samples']:<12} {cat['percent']:.2f}%")

if __name__ == '__main__':
    main()
