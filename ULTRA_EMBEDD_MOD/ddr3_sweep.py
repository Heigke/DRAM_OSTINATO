import serial
import time
import random
from colorama import Fore, Style, init

init(autoreset=True)

# --------------- CONFIGURATION ---------------
SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.2

# Addresses to test (add more as needed)
ADDRESSES = [0x00000000, 0x00000004, 0x00000008, 0x00000100, 0x000003FC]
# Patterns to write (hex strings, all uppercase)
PATTERNS = [
    "00000000", "FFFFFFFF", "AAAAAAAA", "55555555",
    "DEADBEEF", "CAFEBABE", "12345678", "87654321",
    "F0F0F0F0", "0F0F0F0F", "B9125134", "F6108000",
    "D9285A15", "BB93024A", "996B0914", "5AB427C8",
    "C74B5E4E", "116532CC", "22CD0CD0", "E51AAF27"
]
# Optional: Add randomized patterns
for _ in range(5):
    PATTERNS.append("%08X" % random.randint(0, 0xFFFFFFFF))

# Number of readbacks to do after each write
NREADS = 5

# How many bits difference is considered a "near hit"
MAX_NEAR_HIT = 2

# Prompt for tap/rdlat to log, or hardcode here
DQS_TAP_DELAY = input("DQS_TAP_DELAY_INIT? ")
TPHY_RDLAT = input("TPHY_RDLAT? ")

# --------------- SERIAL SETUP ---------------
ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)

def write_cmd(addr, data):
    cmd = "W%08X %s\r" % (addr, data)
    ser.write(cmd.encode('ascii'))
    time.sleep(0.01) # Let it process

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
        return 32  # Worst case

def colorize_match(w, r):
    if w == r:
        return Fore.GREEN + r + Style.RESET_ALL
    else:
        errors = hamming_distance(w, r)
        if errors <= MAX_NEAR_HIT:
            return Fore.YELLOW + r + f" ({errors} bits off)" + Style.RESET_ALL
        else:
            return Fore.RED + r + f" ({errors} bits off)" + Style.RESET_ALL

# --------------- TEST LOGIC ---------------
results = []

print("\n=== DDR3 BRING-UP SWEEP ===")
print(f"Tap delay: {DQS_TAP_DELAY}, TPHY_RDLAT: {TPHY_RDLAT}")
print(f"Addresses: {['0x%08X'%a for a in ADDRESSES]}")
print(f"Patterns: {len(PATTERNS)} patterns\n")

for addr in ADDRESSES:
    print(Fore.CYAN + f"\n--- Testing address 0x{addr:08X} ---" + Style.RESET_ALL)
    for pattern in PATTERNS:
        # Write pattern
        write_cmd(addr, pattern)
        time.sleep(0.02)

        # Read back multiple times
        readbacks = []
        for i in range(NREADS):
            rb = read_cmd(addr)
            readbacks.append(rb if rb else "TIMEOUT")
            time.sleep(0.01)
        
        # Analyze
        pass_count = 0
        near_hit_count = 0
        for rb in readbacks:
            if rb.upper() == pattern:
                pass_count += 1
            elif hamming_distance(rb, pattern) <= MAX_NEAR_HIT:
                near_hit_count += 1
        
        match_summary = [colorize_match(pattern, rb.upper()) for rb in readbacks]
        stat = {
            "addr": addr,
            "pattern": pattern,
            "readbacks": readbacks,
            "match_summary": match_summary,
            "passes": pass_count,
            "near_hits": near_hit_count
        }
        results.append(stat)
        # Print summary live
        print(f"Write: {pattern:>8} @ 0x{addr:08X} -> " +
              ", ".join(match_summary))

# --------------- FINAL SUMMARY ---------------
print("\n\n=== SUMMARY TABLE ===")
print("Addr        Pattern     Passes  NearHits   Readbacks")
for r in results:
    addr = f"0x{r['addr']:08X}"
    pattern = r['pattern']
    passes = r['passes']
    near = r['near_hits']
    reads = ", ".join(r['match_summary'])
    print(f"{addr}  {pattern}   {passes}/{NREADS}    {near}      {reads}")

# Optional: save to file for post-analysis
with open("ddr3_sweep_results.csv", "w") as f:
    f.write("Addr,Pattern,Passes,NearHits,Readbacks\n")
    for r in results:
        f.write(f"0x{r['addr']:08X},{r['pattern']},{r['passes']},{r['near_hits']},\"{'|'.join(r['readbacks'])}\"\n")

print("\nDone! See ddr3_sweep_results.csv for CSV summary.")

ser.close()
