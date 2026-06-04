#!/usr/bin/env python3
"""NXDOMAIN Fake DNS on 127.0.0.1:53 - intercepts all local DNS queries."""
import socket
import struct
import threading

def handle(data, addr, sock):
    if len(data) < 12:
        return
    # Only respond to DNS queries (QR=0)
    flags = struct.unpack("!H", data[2:4])[0]
    if flags & 0x8000:  # QR=1 (response), skip
        return
    tid = data[0:2]
    resp_flags = struct.pack("!H", 0x8183)  # QR=1, NXDOMAIN(RCODE=3)
    resp = tid + resp_flags + data[4:]
    sock.sendto(resp, addr)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("127.0.0.1", 53))
print("NXDOMAIN on 127.0.0.1:53", flush=True)
while True:
    d, a = sock.recvfrom(1024)
    threading.Thread(target=handle, args=(d, a, sock), daemon=True).start()
