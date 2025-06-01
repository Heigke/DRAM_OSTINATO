import serial
import time
import random
from colorama import Fore, Style, init

# Initialize colorama
init(autoreset=True)

# --- Configuration ---
SERIAL_PORT = "/dev/ttyUSB1"  # Serial port for communication
BAUDRATE = 115200             # Baudrate for serial communication
TIMEOUT = 0.2                 # Read timeout in seconds for serial communication

# Memory addresses to test
ADDRESSES = [0x00000000, 0x00000004, 0x00000008, 0x00000100, 0x000003FC]

# Data patterns to write (32-bit, hex strings)
PATTERNS = [
    "00000000", "FFFFFFFF", "AAAAAAAA", "55555555",
    "DEADBEEF", "CAFEBABE", "12345678", "87654321",
    "F0F0F0F0", "0F0F0F0F", "B9125134", "F6108000",
    "D9285A15", "BB93024A", "996B0914", "5AB427C8",
    "C74B5E4E", "116532CC", "22CD0CD0", "E51AAF27"
]
# Add some random patterns
for _ in range(5): # The original code had 5, the log output suggests more patterns were run.
                  # Matching to the log provided (23 distinct patterns before randoms for 0x00000000)
                  # For consistency with the problem description's log, we'll stick to the original set + 5 random.
    PATTERNS.append("%08X" % random.randint(0, 0xFFFFFFFF))

NREADS = 5          # Number of read attempts after each write
LAG_DEPTH = 20      # How many previous write patterns to keep in history for lag checking

# --- Get PHY and Test settings from user ---
DQS_TAP_DELAY = input("DQS_TAP_DELAY_INIT? ")
TPHY_RDLAT = input("TPHY_RDLAT? ")
try:
    MAX_NEAR_HIT_input = input(f"MAX_NEAR_HIT (defines 'close match' Hamming distance, default: 2)? ")
    MAX_NEAR_HIT = int(MAX_NEAR_HIT_input) if MAX_NEAR_HIT_input.strip() else 2
except ValueError:
    print(Fore.YELLOW + "Invalid input for MAX_NEAR_HIT, using default 2." + Style.RESET_ALL)
    MAX_NEAR_HIT = 2

# --- Initialize Serial Connection ---
try:
    ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)
except serial.SerialException as e:
    print(Fore.RED + f"Error opening serial port {SERIAL_PORT}: {e}" + Style.RESET_ALL)
    exit(1)

# --- Core Functions ---
def write_cmd(addr, data):
    """Sends a write command to the serial device."""
    cmd = "W%08X %s\r" % (addr, data)
    ser.write(cmd.encode('ascii'))
    time.sleep(0.01)  # Short delay for command processing

def read_cmd(addr):
    """Sends a read command and retrieves the response."""
    cmd = "R%08X\r" % addr
    ser.write(cmd.encode('ascii'))
    time.sleep(0.01)  # Short delay for command processing
    out = ""
    t0 = time.time()
    while True:
        try:
            line = ser.readline().decode("ascii", errors="ignore").strip()
            if line:
                out = line
                break
        except Exception:
            # Ignore serial exceptions during readline, rely on timeout
            pass
        if time.time() - t0 > TIMEOUT:
            break
    return out

def hamming_distance(hex1, hex2):
    """Calculates the Hamming distance between two 8-char hex strings."""
    try:
        val1_str = hex1[-8:]
        val2_str = hex2[-8:] # prev_pattern is already 8 chars
        
        v1 = int(val1_str, 16)
        v2 = int(val2_str, 16)
        return bin(v1 ^ v2).count('1')
    except ValueError:
        return 32

def color_tag(val, tag_str):
    """Applies color to the readback value based on its tag."""
    reset_style = Style.RESET_ALL
    if tag_str == "OK":
        return Fore.GREEN + val + "[OK]" + reset_style
    elif tag_str.startswith("LAG-"):
        return Fore.BLUE + val + f"[{tag_str}]" + reset_style
    elif tag_str.startswith("NEAR-LAG-"):
        return Fore.MAGENTA + val + f"[{tag_str}]" + reset_style
    elif tag_str == "TIMEOUT":
        return Fore.YELLOW + val + "[TIMEOUT]" + reset_style
    else: # FAIL
        return Fore.RED + val + "[FAIL]" + reset_style

# --- Main Test Logic ---
results = []

print("\n=== DDR3 BRING-UP SWEEP ===")
print(f"Serial Port: {SERIAL_PORT}, Baudrate: {BAUDRATE}")
print(f"PHY Settings - DQS_TAP_DELAY: {DQS_TAP_DELAY}, TPHY_RDLAT: {TPHY_RDLAT}")
print(f"Test Params - NRead: {NREADS}, LagDepth: {LAG_DEPTH}, MaxNearHit: {MAX_NEAR_HIT}")
print(f"Addresses: {['0x%08X'%a for a in ADDRESSES]}")
print(f"Patterns: {len(PATTERNS)} patterns\n")


for addr in ADDRESSES:
    print(Fore.CYAN + f"\n--- Testing address 0x{addr:08X} ---" + Style.RESET_ALL)
    write_history = []

    for pattern_idx, pattern in enumerate(PATTERNS):
        write_cmd(addr, pattern)
        time.sleep(0.02)

        current_readbacks = []
        for i in range(NREADS):
            rb = read_cmd(addr)
            current_readbacks.append(rb if rb else "TIMEOUT_STR")
            if i < NREADS -1 : time.sleep(0.01)

        current_tags = []
        for rb_val in current_readbacks:
            if rb_val == "TIMEOUT_STR":
                current_tags.append("TIMEOUT")
                continue

            rb_upper = rb_val.upper()
            if rb_upper[-8:] == pattern:
                current_tags.append("OK")
            else:
                found_lag_match = False
                # Ensure write_history is not empty before trying to access elements
                if write_history: # Check only if history is not empty
                    for lag_idx in range(1, min(LAG_DEPTH, len(write_history)) + 1):
                        # Check if lag_idx is a valid index for write_history
                        if lag_idx <= len(write_history):
                            prev_pattern = write_history[-lag_idx]
                            
                            if rb_upper[-8:] == prev_pattern:
                                current_tags.append(f"LAG-{lag_idx} (exp:{prev_pattern})")
                                found_lag_match = True
                                break
                            
                            hd = hamming_distance(rb_upper, prev_pattern)
                            if hd <= MAX_NEAR_HIT:
                                current_tags.append(f"NEAR-LAG-{lag_idx} (exp:{prev_pattern},hd:{hd})")
                                found_lag_match = True
                                break
                
                if not found_lag_match:
                    current_tags.append("FAIL")
        
        write_history.append(pattern)
        if len(write_history) > LAG_DEPTH:
            write_history.pop(0)

        display_readbacks = [rb if rb != "TIMEOUT_STR" else "TIMEOUT" for rb in current_readbacks]

        print(f"Write: {pattern:>8} @ 0x{addr:08X} -> " +
              ", ".join([color_tag(rb_disp, tag) for rb_disp, tag in zip(display_readbacks, current_tags)]))

        results.append({
            "addr": addr,
            "pattern": pattern,
            "readbacks": display_readbacks,
            "tags": current_tags
        })

# --- Summary and Output ---
print("\n\n=== SUMMARY TABLE ===")
print("Addr        Pattern     Readbacks (with tags)")
for r_item in results:
    addr_str = f"0x{r_item['addr']:08X}"
    pattern_str = r_item['pattern']
    reads_str = ", ".join([f"{rb}[{tag}]" for rb, tag in zip(r_item['readbacks'], r_item['tags'])])
    print(f"{addr_str}  {pattern_str}    {reads_str}")

csv_filename = "ddr3_sweep_lagged_labeled_"+DQS_TAP_DELAY+"_"+TPHY_RDLAT+"_.csv"
with open(csv_filename, "w") as f:
    f.write("Address,PatternWritten,ReadbackValues,Tags\n")
    for r_item in results:
        readbacks_csv = "|".join(r_item['readbacks'])
        tags_csv = "|".join(r_item['tags'])
        f.write(f"0x{r_item['addr']:08X},{r_item['pattern']},\"{readbacks_csv}\",\"{tags_csv}\"\n")

print(f"\nDone! See {csv_filename} for CSV summary.")

ser.close()
