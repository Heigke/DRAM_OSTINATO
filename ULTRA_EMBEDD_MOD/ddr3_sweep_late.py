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
LAG_DEPTH = 10    # How many previous patterns to check for lagged responses

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
        v1 = int(hex1, 16)
        v2 = int(hex2, 16)
        return bin(v1 ^ v2).count('1')
    except:
        return 32

def color_tag(val, tag):
    if tag == "OK":
        return Fore.GREEN + val + "[OK]" + Style.RESET_ALL
    elif tag == "NEAR":
        return Fore.YELLOW + val + "[NEAR]" + Style.RESET_ALL
    elif tag.startswith("LATE-"):
        return Fore.BLUE + val + f"[{tag}]" + Style.RESET_ALL
    elif tag.startswith("LATE-NEAR-"):
        return Fore.MAGENTA + val + f"[{tag}]" + Style.RESET_ALL
    else:
        return Fore.RED + val + "[FAIL]" + Style.RESET_ALL

def fuzzy_late_match(rb, lag_history, max_near=MAX_NEAR_HIT):
    # Try substring, aligned, and near match in the lag history
    rb = rb.upper()
    for lagidx, oldpat in enumerate(reversed(lag_history)):
        oldpat = oldpat.upper()
        if oldpat in rb:
            return f"LATE-{lagidx+1}", oldpat
        # Also try if low or high 32 bits of rb match oldpat
        try:
            val_rb = int(rb[-8:], 16)
            val_old = int(oldpat, 16)
            if val_rb == val_old:
                return f"LATE-{lagidx+1}", oldpat
            # Hamming distance
            if hamming_distance(rb[-8:], oldpat) <= max_near:
                return f"LATE-NEAR-{lagidx+1}", oldpat
        except:
            pass
    return None, None

results = []

print("\n=== DDR3 BRING-UP SWEEP ===")
print(f"Tap delay: {DQS_TAP_DELAY}, TPHY_RDLAT: {TPHY_RDLAT}")
print(f"Addresses: {['0x%08X'%a for a in ADDRESSES]}")
print(f"Patterns: {len(PATTERNS)} patterns\n")

for addr in ADDRESSES:
    print(Fore.CYAN + f"\n--- Testing address 0x{addr:08X} ---" + Style.RESET_ALL)
    lag_history = []  # rolling buffer of previous patterns
    for p_idx, pattern in enumerate(PATTERNS):
        write_cmd(addr, pattern)
        time.sleep(0.02)
        readbacks = []
        for _ in range(NREADS):
            rb = read_cmd(addr)
            readbacks.append(rb if rb else "TIMEOUT")
            time.sleep(0.01)

        pass_count = 0
        near_hit_count = 0
        match_types = []
        for rb in readbacks:
            rb_up = rb.upper()
            tag = "FAIL"
            if rb_up == pattern:
                pass_count += 1
                tag = "OK"
            elif hamming_distance(rb_up[-8:], pattern) <= MAX_NEAR_HIT:
                near_hit_count += 1
                tag = "NEAR"
            else:
                # Fuzzy late hit: substring or low 32 bits
                tag, whichpat = fuzzy_late_match(rb_up, lag_history)
                if tag is None:
                    tag = "FAIL"
            match_types.append(tag)
        color_summary = [color_tag(rb.upper(), tag) for rb, tag in zip(readbacks, match_types)]
        results.append({
            "addr": addr,
            "pattern": pattern,
            "readbacks": readbacks,
            "match_types": match_types,
            "passes": pass_count,
            "near_hits": near_hit_count,
        })
        print(f"Write: {pattern:>8} @ 0x{addr:08X} -> " + ", ".join(color_summary))
        lag_history.append(pattern)
        if len(lag_history) > LAG_DEPTH:
            lag_history.pop(0)

print("\n\n=== SUMMARY TABLE ===")
print("Addr        Pattern     Passes  NearHits   Readbacks (with tags)")
for r in results:
    addr = f"0x{r['addr']:08X}"
    pattern = r['pattern']
    passes = r['passes']
    near = r['near_hits']
    reads = ", ".join([f"{rb.upper()}[{tag}]" for rb, tag in zip(r['readbacks'], r['match_types'])])
    print(f"{addr}  {pattern}   {passes}/{NREADS}    {near}      {reads}")

with open("ddr3_sweep_lagged_fuzzy_results.csv", "w") as f:
    f.write("Addr,Pattern,Passes,NearHits,Readbacks,MatchTypes\n")
    for r in results:
        f.write(f"0x{r['addr']:08X},{r['pattern']},{r['passes']},{r['near_hits']},\"{'|'.join(r['readbacks'])}\",\"{'|'.join(r['match_types'])}\"\n")

print("\nDone! See ddr3_sweep_lagged_fuzzy_results.csv for CSV summary.")

ser.close()
