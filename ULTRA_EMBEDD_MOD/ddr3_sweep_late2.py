import serial
import time
import random
from colorama import Fore, Style, init

init(autoreset=True)

SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.2

ADDRESSES = [0x00000000, 0x00000004, 0x00000008, 0x00000100, 0x000003FC]
PATTERNS = [
    "00000000", "FFFFFFFF", "AAAAAAAA", "55555555",
    "DEADBEEF", "CAFEBABE", "12345678", "87654321",
    "F0F0F0F0", "0F0F0F0F", "B9125134", "F6108000",
    "D9285A15", "BB93024A", "996B0914", "5AB427C8",
    "C74B5E4E", "116532CC", "22CD0CD0", "E51AAF27"
]
for _ in range(5):
    PATTERNS.append("%08X" % random.randint(0, 0xFFFFFFFF))

NREADS = 5
MAX_NEAR_HIT = 2
LAG_DEPTH = 20

DQS_TAP_DELAY = input("DQS_TAP_DELAY_INIT? ")
TPHY_RDLAT = input("TPHY_RDLAT? ")

ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)

def write_cmd(addr, data):
    cmd = "W%08X %s\r" % (addr, data)
    ser.write(cmd.encode('ascii'))
    time.sleep(0.01)

def read_cmd(addr):
    cmd = "R%08X\r" % addr
    ser.write(cmd.encode('ascii'))
    time.sleep(0.01)
    out = ""
    t0 = time.time()
    while True:
        try:
            line = ser.readline().decode("ascii", errors="ignore").strip()
            if line:
                out = line
                break
        except Exception:
            pass
        if time.time() - t0 > 0.2:
            break
    return out

def hamming_distance(hex1, hex2):
    try:
        v1 = int(hex1[-8:], 16)
        v2 = int(hex2[-8:], 16)
        return bin(v1 ^ v2).count('1')
    except:
        return 32

def color_tag(val, tag):
    if tag == "OK":
        return Fore.GREEN + val + "[OK]" + Style.RESET_ALL
    elif tag.startswith("LAG-"):
        return Fore.BLUE + val + f"[{tag}]" + Style.RESET_ALL
    elif tag.startswith("NEAR-LAG-"):
        return Fore.MAGENTA + val + f"[{tag}]" + Style.RESET_ALL
    else:
        return Fore.RED + val + "[FAIL]" + Style.RESET_ALL

results = []

print("\n=== DDR3 BRING-UP SWEEP ===")
print(f"Tap delay: {DQS_TAP_DELAY}, TPHY_RDLAT: {TPHY_RDLAT}")
print(f"Addresses: {['0x%08X'%a for a in ADDRESSES]}")
print(f"Patterns: {len(PATTERNS)} patterns\n")

for addr in ADDRESSES:
    print(Fore.CYAN + f"\n--- Testing address 0x{addr:08X} ---" + Style.RESET_ALL)
    write_history = []
    for pattern_idx, pattern in enumerate(PATTERNS):
        write_cmd(addr, pattern)
        time.sleep(0.02)
        readbacks = []
        for _ in range(NREADS):
            rb = read_cmd(addr)
            readbacks.append(rb if rb else "TIMEOUT")
            time.sleep(0.01)

        tags = []
        for rb in readbacks:
            rb_up = rb.upper()
            # Check direct match
            if rb_up[-8:] == pattern:
                tags.append("OK")
            else:
                # Check lag: does this readback match any previous write?
                found_lag = False
                for lag in range(1, min(LAG_DEPTH, len(write_history)) + 1):
                    prev_pattern = write_history[-lag]
                    if rb_up[-8:] == prev_pattern:
                        tags.append(f"LAG-{lag}")
                        found_lag = True
                        break
                    elif hamming_distance(rb_up, prev_pattern) <= MAX_NEAR_HIT:
                        tags.append(f"NEAR-LAG-{lag}")
                        found_lag = True
                        break
                if not found_lag:
                    tags.append("FAIL")
        write_history.append(pattern)
        if len(write_history) > LAG_DEPTH:
            write_history.pop(0)

        # Print result for this pattern
        print(f"Write: {pattern:>8} @ 0x{addr:08X} -> " +
              ", ".join([color_tag(rb, tag) for rb, tag in zip(readbacks, tags)]))

        results.append({
            "addr": addr,
            "pattern": pattern,
            "readbacks": readbacks,
            "tags": tags
        })

print("\n\n=== SUMMARY TABLE ===")
print("Addr        Pattern     Readbacks (with tags)")
for r in results:
    addr = f"0x{r['addr']:08X}"
    pattern = r['pattern']
    reads = ", ".join([f"{rb}[{tag}]" for rb, tag in zip(r['readbacks'], r['tags'])])
    print(f"{addr}  {pattern}   {reads}")

with open("ddr3_sweep_lagged_labeled.csv", "w") as f:
    f.write("Addr,Pattern,Readbacks,Tags\n")
    for r in results:
        f.write(f"0x{r['addr']:08X},{r['pattern']},\"{'|'.join(r['readbacks'])}\",\"{'|'.join(r['tags'])}\"\n")

print("\nDone! See ddr3_sweep_lagged_labeled.csv for CSV summary.")

ser.close()
