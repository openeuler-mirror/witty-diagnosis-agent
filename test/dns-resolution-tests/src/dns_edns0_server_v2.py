#!/usr/bin/env python3
"""
EDNS0 Fault Server v2 — Simulates DNS resolver WITHOUT EDNS0 support.
Uses TCP forwarding to bypass WSL2 transparent UDP proxy.

Behavior:
- UDP queries WITH EDNS0 OPT record => truncated response (TC=1)
- UDP queries WITHOUT EDNS0 => forwarded upstream via TCP
- TCP queries => forwarded upstream as-is
"""

import socket
import struct
import sys

UPSTREAM = ('8.8.8.8', 53)
BIND_ADDR = ('127.0.0.1', 5353)


def has_edns0_opt(data: bytes) -> bool:
    if len(data) < 12:
        return False
    add_count = struct.unpack('>H', data[10:12])[0]
    if add_count == 0:
        return False
    for i in range(len(data) - 3):
        if data[i:i+2] == b'\x00\x29':
            return True
    return False


def build_truncated_response(query: bytes) -> bytes:
    dns_id = query[:2]
    flags = struct.pack('>H', 0x8002)
    counts = struct.pack('>HHHH', 1, 0, 0, 0)
    return dns_id + flags + counts + query[12:]


def forward_tcp(data: bytes) -> bytes | None:
    """Forward DNS query over TCP (bypasses WSL2 UDP proxy)."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect(UPSTREAM)
        s.sendall(struct.pack('>H', len(data)) + data)
        raw_len = s.recv(2)
        if len(raw_len) < 2:
            s.close()
            return None
        resp_len = struct.unpack('>H', raw_len)[0]
        resp = b''
        while len(resp) < resp_len:
            chunk = s.recv(resp_len - len(resp))
            if not chunk:
                break
            resp += chunk
        s.close()
        return resp
    except Exception as e:
        print(f'[EDNS0] TCP fwd error: {e}', flush=True)
        return None


def main():
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    udp.bind(BIND_ADDR)
    udp.settimeout(3)

    tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    tcp.bind(BIND_ADDR)
    tcp.listen(5)
    tcp.settimeout(3)

    print(f'[EDNS0] Listening UDP+TCP on {BIND_ADDR[0]}:{BIND_ADDR[1]}', flush=True)
    print(f'[EDNS0] Upstream via TCP: {UPSTREAM[0]}:{UPSTREAM[1]}', flush=True)
    print('[EDNS0] EDNS0 OPT -> TC=1 | no-EDNS0 -> fwd TCP', flush=True)

    while True:
        try:
            data, addr = udp.recvfrom(4096)
            opt = has_edns0_opt(data)
            if opt:
                resp = build_truncated_response(data)
                udp.sendto(resp, addr)
                print(f'[EDNS0] UDP {addr} EDNS0 -> TC=1 ({len(resp)}b)', flush=True)
            else:
                resp = forward_tcp(data)
                if resp:
                    udp.sendto(resp, addr)
                    print(f'[EDNS0] UDP {addr} No-EDNS0 -> OK ({len(resp)}b)', flush=True)
                else:
                    print(f'[EDNS0] UDP {addr} No-EDNS0 -> FWD FAILED', flush=True)
        except socket.timeout:
            pass
        except Exception as e:
            print(f'[EDNS0] UDP error: {e}', flush=True)

        try:
            conn, addr = tcp.accept()
            conn.settimeout(10)
            raw_len = conn.recv(2)
            if len(raw_len) >= 2:
                msg_len = struct.unpack('>H', raw_len)[0]
                data = b''
                while len(data) < msg_len:
                    chunk = conn.recv(msg_len - len(data))
                    if not chunk:
                        break
                    data += chunk
                if data:
                    resp = forward_tcp(data)
                    if resp:
                        conn.sendall(struct.pack('>H', len(resp)) + resp)
                        print(f'[EDNS0] TCP {addr} relay ({len(resp)}b)', flush=True)
            conn.close()
        except socket.timeout:
            pass
        except Exception as e:
            print(f'[EDNS0] TCP error: {e}', flush=True)
            try:
                conn.close()
            except:
                pass


if __name__ == '__main__':
    main()
