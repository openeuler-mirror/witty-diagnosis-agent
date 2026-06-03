#!/usr/bin/env python3
"""
DNS TCP Block Injector (Branch G)
Blocks only TCP DNS traffic, leaving UDP DNS untouched.
This forces clients to experience TCP fallback failures.
"""
import subprocess
import sys
import time
import signal

def main():
    duration = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    print(f"[DNS TCP Block Injector] Blocking TCP DNS for {duration}s")

    # Drop only TCP DNS packets
    subprocess.run(["iptables", "-A", "OUTPUT", "-p", "tcp", "--dport", "53", "-j", "DROP"], check=True)
    print("[+] TCP DNS (port 53) blocked")
    print("[*] UDP DNS (port 53) remains open")

    def cleanup(signum, frame):
        subprocess.run(["iptables", "-D", "OUTPUT", "-p", "tcp", "--dport", "53", "-j", "DROP"])
        print("\n[Cleanup] TCP DNS rule removed")
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    try:
        time.sleep(duration)
    finally:
        cleanup(None, None)

if __name__ == "__main__":
    main()
