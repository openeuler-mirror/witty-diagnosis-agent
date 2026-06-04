#!/usr/bin/env python3
"""Check if 127.0.0.1:53 is available."""
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("127.0.0.1", 53))
    print("127.0.0.1:53 is FREE")
    s.close()
except OSError as e:
    print(f"127.0.0.1:53 is TAKEN: {e}")
# Also check 0.0.0.0:53
s2 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s2.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s2.bind(("0.0.0.0", 53))
    print("0.0.0.0:53 is FREE")
    s2.close()
except OSError as e:
    print(f"0.0.0.0:53 is TAKEN: {e}")
