#!/usr/bin/env python3
"""
NXDOMAIN Injector (Branch B)
Runs a fake DNS server on port 53 that returns NXDOMAIN for all queries.
"""
import socket
import struct
import sys
import signal
import threading

def dns_response_nxdomain(data):
    """Build a DNS NXDOMAIN response from a query."""
    if len(data) < 12:
        return None
    header = struct.unpack('!HHHHHH', data[:12])
    tid = header[0]
    flags = 0x8183  # QR=1, OPCODE=0, AA=0, TC=0, RD=1, RA=1, RCODE=3(NXDOMAIN)
    qdcount = header[1]
    ancount = 0
    nscount = 0
    arcount = 0
    resp_header = struct.pack('!HHHHHH', tid, flags, qdcount, ancount, nscount, arcount)
    return resp_header + data[12:]

def handle_query(data, addr, sock):
    response = dns_response_nxdomain(data)
    if response:
        sock.sendto(response, addr)
        qname = extract_qname(data)
        print(f"[NXDOMAIN] Replied NXDOMAIN for {qname} from {addr[0]}:{addr[1]}")

def extract_qname(data):
    """Extract query name from DNS question."""
    idx = 12
    labels = []
    while idx < len(data):
        length = data[idx]
        if length == 0:
            break
        idx += 1
        labels.append(data[idx:idx+length].decode('ascii', errors='replace'))
        idx += length
    return '.'.join(labels)

def main():
    print("[NXDOMAIN Fake DNS] Listening on 0.0.0.0:53")
    print("[*] Returns NXDOMAIN (RCODE=3) for ALL queries")
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('0.0.0.0', 53))

    def cleanup(signum, frame):
        sock.close()
        print("\n[Cleanup] Fake DNS server stopped")
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    while True:
        try:
            data, addr = sock.recvfrom(1024)
            t = threading.Thread(target=handle_query, args=(data, addr, sock))
            t.daemon = True
            t.start()
        except OSError:
            break

if __name__ == "__main__":
    main()
