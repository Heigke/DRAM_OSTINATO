import serial
import time
import re
import random
from collections import defaultdict

SERIAL_PORT = '/dev/ttyUSB1'
BAUDRATE = 115200
TIMEOUT = 0.2

ADDRESSES = [0x0, 0x4, 0x8, 0x10, 0x20, 0x100, 0x200, 0x3FC, 0x7F0, 0x800, 0x1FFC]
PATTERNS = [
    0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555, 0xCAFEBABE, 0xDEADBEEF, 0x12345678,
    0x87654321, 0xF0F0F0F0, 0x0F0F0F0F,
    # random ones:
] + [random.randint(0, 0xFFFFFFFF) for _ in range(10)]

# regex for hex data from the board (case-insensitive, up to 9 hex chars)
HEX_RE = re.compile(r'([0-9a-fA-F]{8,9})')

def send_cmd(ser, cmd):
    # Each command must be terminated with CR (\r)
    ser.write((cmd + '\r').encode('ascii'))
    time.sleep(0.02)  # Give time for response

def read_response(ser):
    lines = []
    t0 = time.time()
    while time.time() - t0 < TIMEOUT:
        line = ser.readline().decode('ascii', errors='ignore').strip()
        if line:
            lines.append(line)
    return lines

def hexstr(val, width=8):
    return f"{val:0{width}X}"

def write_address(ser, addr, data):
    cmd = f'W{hexstr(addr,8)} {hexstr(data,8)}'
    send_cmd(ser, cmd)
    # Optional: read back echo/OK lines
    return read_response(ser)

def read_address(ser, addr):
    cmd = f'R{hexstr(addr,8)}'
    send_cmd(ser, cmd)
    lines = read_response(ser)
    # Extract hex values using regex
    found = []
    for line in lines:
        m = HEX_RE.search(line)
        if m:
            found.append(m.group(1).lower())
    return found or lines

def run_ddr_test():
    print(f"Connecting to {SERIAL_PORT} at {BAUDRATE}...")
    ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)
    time.sleep(0.5)
    results = defaultdict(list)

    for addr in ADDRESSES:
        print(f"\n--- Testing address {hexstr(addr)} ---")
        for pat in PATTERNS:
            print(f"Write: {hexstr(addr)} <= {hexstr(pat)}")
            write_address(ser, addr, pat)
            time.sleep(0.02)

            readbacks = []
            # Read 4 times to check stability
            for i in range(4):
                vals = read_address(ser, addr)
                if vals:
                    readbacks.append(vals[0])
                time.sleep(0.02)

            expected = hexstr(pat, 8).lower()
            all_pass = all(rb == expected for rb in readbacks)
            partials = [rb for rb in readbacks if expected in rb]
            bit_matches = [bin(int(rb,16) ^ pat).count('0')-1 for rb in readbacks if len(rb)==8 and rb.isalnum()]

            results[addr].append({
                "pattern": expected,
                "readbacks": readbacks,
                "all_pass": all_pass,
                "partial": partials,
                "bit_matches": bit_matches,
            })
            if all_pass:
                print(f"  [PASS] {expected} matched {readbacks}")
            elif partials:
                print(f"  [PARTIAL] {expected} in {readbacks}")
            elif any(len(rb) == 8 for rb in readbacks):
                diffs = [f"{int(rb,16) ^ pat:08X}" for rb in readbacks if len(rb) == 8]
                print(f"  [MISMATCH] {expected} got {readbacks} diffs {diffs}")
            else:
                print(f"  [FAIL] No good reads ({readbacks})")

    print("\n==== SUMMARY ====")
    for addr, tests in results.items():
        good = sum(1 for t in tests if t['all_pass'])
        partial = sum(1 for t in tests if t['partial'] and not t['all_pass'])
        total = len(tests)
        print(f"Address {hexstr(addr)}: {good}/{total} OK, {partial} partial")
    ser.close()

if __name__ == '__main__':
    run_ddr_test()
