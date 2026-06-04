#!/usr/bin/env python3
"""
EDNS0 Fault Server — Simulates DNS resolver WITHOUT EDNS0 support.

Behavior:
- Queries WITH EDNS0 OPT record → returned truncated (TC=1)
- Queries WITHOUT EDNS0 → forwarded to upstream (8.8.8.8)
- Queries over TCP → forwarded as-is (TCP bypasses EDNS0 logic)

This simulates a legacy/EDNS0-incapable resolver.
"""

import socket
import struct
import sys

UPSTREAM = ('8.8.8.8', 53)
BIND_ADDR = ('127.0.0.1', 5353)


def has_edns0_opt(data: bytes) -> bool:
    """Check if DNS query contains EDNS0 OPT pseudo-record (type 41 = 0x0029)."""
    if len(data) < 12:
        return False
    # Additional section RR count is at offset 10-11
    add_count = struct.unpack('>H', data[10:12])[0]
    if add_count == 0:
        return False
    # Scan for Type=0x0029 (OPT) in the query
    # OPT record is always the last RR in additional section
    for i in range(len(data) - 3):
        if data[i:i+2] == b'\x00\x29':
            return True
    return False


def build_truncated_response(query: bytes) -> bytes:
    """Build a response with TC=1 bit set, no answer section."""
    if len(query) < 12:
        return b''
    dns_id = query[:2]
    # Flags: QR=1 (response), TC=1 (truncated), RA=1 (recursion available)
    flags = struct.pack('>H', 0x8002)
    # QDCOUNT=1, ANCOUNT=0, NSCOUNT=0, ARCOUNT=0
    counts = struct.pack('>HHHH', 1, 0, 0, 0)
    # Copy question section from query
    qsection = query[12:]
    return dns_id + flags + counts + qsection


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(BIND_ADDR)
    sock.settimeout(60)

    fwd = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    fwd.settimeout(10)

    print(f'[EDNS0-FAULT] Listening on {BIND_ADDR[0]}:{BIND_ADDR[1]}')
    print(f'[EDNS0-FAULT] Upstream: {UPSTREAM[0]}:{UPSTREAM[1]}')
    print('[EDNS0-FAULT] Queries WITH EDNS0 OPT → TC=1 truncated')
    print('[EDNS0-FAULT] Queries WITHOUT EDNS0 → forwarded upstream')

    while True:
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            continue
        except Exception as e:
            print(f'[EDNS0-FAULT] Recv error: {e}')
            continue

        opt = has_edns0_opt(data)

        if opt:
            # EDNS0 detected → return truncated response
            resp = build_truncated_response(data)
            try:
                sock.sendto(resp, addr)
            except Exception as e:
                print(f'[EDNS0-FAULT] Send error: {e}')
        else:
            # No EDNS0 → forward upstream
            try:
                fwd.sendto(data, UPSTREAM)
                resp, _ = fwd.recvfrom(4096)
                sock.sendto(resp, addr)
            except socket.timeout:
                print('[EDNS0-FAULT] Upstream timeout')
            except Exception as e:
                print(f'[EDNS0-FAULT] Forward error: {e}')


if __name__ == '__main__':
    main()
