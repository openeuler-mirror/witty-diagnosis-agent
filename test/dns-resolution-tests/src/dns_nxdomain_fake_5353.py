#!/usr/bin/env python3
"""NXDOMAIN Fake DNS Server on port 5353.
Simpler approach: keep query data intact, just set NXDOMAIN in header."""
import socket
import struct
import threading

def handle(data, addr, sock):
    if len(data) < 12:
        return
    tid = data[0:2]
    # flags: QR=1, NXDOMAIN=3, keep other bits from query
    flags = struct.pack("!H", 0x8183)
    # Build response: same transaction ID, new flags, rest unchanged
    resp = tid + flags + data[4:]
    sock.sendto(resp, addr)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("0.0.0.0", 5353))
print("NXDOMAIN fake DNS on :5353", flush=True)
while True:
    d, a = sock.recvfrom(1024)
    threading.Thread(target=handle, args=(d, a, sock), daemon=True).start()
