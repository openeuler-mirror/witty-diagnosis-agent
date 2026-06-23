"""Unit tests for joint_analysis, offcpu_classifier, and diff_report_generator"""
import sys, os, json, tempfile

TEST_DIR = os.path.dirname(os.path.abspath(__file__))
ANALYZERS = os.path.join(TEST_DIR, '..', '..', 'skills', 'flamegraph-analysis', 'scripts', 'analyzers')
RENDER = os.path.join(TEST_DIR, '..', '..', 'skills', 'flamegraph-analysis', 'scripts', 'render')
sys.path.insert(0, ANALYZERS)
sys.path.insert(0, RENDER)


# ---------- Test Data ----------
ONCPU_DATA = """main;handleRequest;processData;sort 1000
main;handleRequest;processData;matrixMultiply 800
main;handleRequest;encrypt;AES_encrypt 500
"""

OFFCPU_DATA = """main;handleRequest;processData;io_schedule 4000
main;handleRequest;processData;wait_on_page_bit 3000
main;handleRequest;encrypt;sk_wait_data 2000
main;handleRequest;encrypt;tcp_recvmsg 1500
main;background;gc;SafepointSynchronize::begin 3000
main;background;gc;VMThread::execute 2000
main;background;signal;sigtimedwait 1000
main;background;barrier;pthread_barrier_wait 800
main;background;rcu;synchronize_rcu 500
"""


def test_offcpu_classifier():
    """Test offcpu classifier with all pattern categories"""
    from offcpu_classifier import parse_folded, classify_offcpu

    stacks = parse_folded(OFFCPU_DATA)
    assert len(stacks) == 9, f"Expected 9 stacks, got {len(stacks)}"

    results = classify_offcpu(stacks)
    total = sum(c for _, c in stacks)
    assert total == 17800, f"Expected 17800 samples, got {total}"

    # Check key categories exist
    categories = {k: v['samples'] for k, v in results.items() if v['samples'] > 0}
    assert 'disk_io' in categories, "disk_io not found"
    assert 'network_io' in categories, "network_io not found"
    assert 'gc_pause' in categories, "gc_pause not found"
    assert 'signal_wait' in categories, "signal_wait not found (new pattern)"
    assert 'barrier' in categories, "barrier not found (new pattern)"
    assert 'rcu_wait' in categories, "rcu_wait not found (new pattern)"

    # Verify samples distribution
    assert categories.get('disk_io', 0) == 7000, f"Expected disk_io=7000, got {categories.get('disk_io', 0)}"

    print("  PASS test_offcpu_classifier")


def test_joint_analysis():
    """Test joint analysis with prefix matching"""
    from joint_analysis import joint_analysis

    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as on_f:
        on_f.write(ONCPU_DATA)
        on_path = on_f.name
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as off_f:
        off_f.write(OFFCPU_DATA)
        off_path = off_f.name

    try:
        result = joint_analysis(on_path, off_path)
        assert 'joint_stacks' in result, "joint_stacks missing"
        assert 'wall_clock' in result, "wall_clock missing"
        assert 'alignment' in result, "alignment missing"

        wc = result['wall_clock']
        assert wc['on_cpu_pct'] > 0, "on_cpu_pct should be > 0"
        assert wc['off_cpu_pct'] > 0, "off_cpu_pct should be > 0"

        js = result['joint_stacks']
        assert len(js) > 0, f"Expected >0 joint stacks, got {len(js)}"

        # Check prefix matching works
        prefix_matches = [j for j in js if j['match_type'] == 'prefix']
        assert len(prefix_matches) > 0, f"Expected prefix matches, got {len(prefix_matches)}"

        print("  PASS test_joint_analysis")
    finally:
        os.unlink(on_path)
        os.unlink(off_path)


def test_joint_alignment():
    """Test data alignment verification"""
    from joint_analysis import joint_analysis

    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as on_f:
        on_f.write(ONCPU_DATA)
        on_path = on_f.name
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as off_f:
        off_f.write(OFFCPU_DATA)
        off_path = off_f.name

    try:
        result = joint_analysis(on_path, off_path)
        align = result['alignment']
        assert 'pid_match_pct' in align, "pid_match_pct missing"
        assert 'sample_ratio' in align, "sample_ratio missing"
        assert 'on_samples' in align and align['on_samples'] > 0
        print("  PASS test_joint_alignment")
    finally:
        os.unlink(on_path)
        os.unlink(off_path)


def test_joint_time_decomposition():
    """Test wall clock time decomposition"""
    from joint_analysis import joint_analysis

    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as on_f:
        on_f.write(ONCPU_DATA)
        on_path = on_f.name
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as off_f:
        off_f.write(OFFCPU_DATA)
        off_path = off_f.name

    try:
        result = joint_analysis(on_path, off_path)
        td = result['time_decomposition']
        assert len(td) > 0, "time_decomposition empty"

        total_pct = sum(v['percent'] for v in td.values())
        assert abs(total_pct - 100) < 1, f"Decomposition should sum to ~100%, got {total_pct}%"

        print("  PASS test_joint_time_decomposition")
    finally:
        os.unlink(on_path)
        os.unlink(off_path)


if __name__ == '__main__':
    print("=== Unit Tests ===")
    test_offcpu_classifier()
    test_joint_analysis()
    test_joint_alignment()
    test_joint_time_decomposition()
    print("\nALL PASS\n    sys.exit(0)")
