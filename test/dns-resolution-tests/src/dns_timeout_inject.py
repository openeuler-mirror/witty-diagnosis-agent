#!/usr/bin/env python3
"""
DNS Timeout Injector (Branch A)
Drops all UDP/TCP DNS packets using iptables to simulate DNS timeout.
"""
import subprocess
import sys
import time
import signal

def main():
    duration = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    print(f"[DNS Timeout Injector] Blocking DNS port 53 for {duration}s")

    # Drop outbound DNS packets
    subprocess.run(["iptables", "-A", "OUTPUT", "-p", "udp", "--dport", "53", "-j", "DROP"], check=True)
    subprocess.run(["iptables", "-A", "OUTPUT", "-p", "tcp", "--dport", "53", "-j", "DROP"], check=True)
    print("[+] DNS port 53 blocked (UDP + TCP)")

    def cleanup(signum, frame):
        subprocess.run(["iptables", "-D", "OUTPUT", "-p", "udp", "--dport", "53", "-j", "DROP"])
        subprocess.run(["iptables", "-D", "OUTPUT", "-p", "tcp", "--dport", "53", "-j", "DROP"])
        print("\n[Cleanup] DNS rules removed")
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    try:
        time.sleep(duration)
    finally:
        cleanup(None, None)

if __name__ == "__main__":
    main()
