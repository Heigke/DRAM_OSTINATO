import csv

csv_file = "iladata_read_trust.csv"

# Column names in the file
KEY_FIELDS = {
    "sample": "Sample in Buffer",
    "fsm": "ila_state[5:0]",
    "timer": "ila_timer[15:0]",
    "cmd_valid": "ila_cmd_valid",
    "cmd_type": "ila_cmd_type[2:0]",
    "bank": "dfi_bank_s[2:0]",
    "addr": "dfi_address_s[9:0]",
    "wrdata_en": "ila_wrdata_en",
    "wrdata": "ila_wrdata[31:0]",
    "rddata_valid": "ila_rddata_valid",
    "rddata": "ila_rddata[31:0]",
    "captured_data": "ila_captured_data_1[31:0]",
    "captured_data_high": "ila_captured_data[127:32]",
    "data_match": "ila_data_match",
    "burst_done": "ila_read_burst_done",
    "rd_beat_cnt": "ila_rd_beat_cnt[1:0]",
    "write_burst_cnt": "ila_write_burst_cnt[2:0]",
    "write_delay_cnt": "ila_write_delay_cnt[3:0]",
    "init_done": "init_done_q",
}

# Typical READ command code; change if needed.
READ_CMD_TYPE = "5"

def hex2int(s):
    try:
        if "x" in s.lower() or "z" in s.lower():
            return 0
        return int(s, 16)
    except Exception:
        return 0

# --- Read and Parse the CSV ---
with open(csv_file, newline='') as f:
    reader = csv.reader(f, delimiter=',')
    header1 = next(reader)
    header2 = next(reader)

    # Strip whitespace from all header fields
    header1 = [h.strip() for h in header1]

    col_idx = {name: header1.index(KEY_FIELDS[name]) for name in KEY_FIELDS}
    rows = list(reader)

# --- Collect State Transitions, Commands, and Data Events ---
fsm_states = []
cmd_events = []
read_bursts = []
data_matches = []
init_seq = []
burst_data = []

last_fsm = None
last_cmd_valid = None
last_cmd_type = None
last_rddata_valid = None
last_data_match = None
last_init_done = None

for i, row in enumerate(rows):
    try:
        sample_idx = int(row[col_idx["sample"]])
        fsm = row[col_idx["fsm"]]
        timer = hex2int(row[col_idx["timer"]])
        cmd_valid = hex2int(row[col_idx["cmd_valid"]])
        cmd_type = str(int(row[col_idx["cmd_type"]], 16))
        wrdata_en = hex2int(row[col_idx["wrdata_en"]])
        wrdata = row[col_idx["wrdata"]]
        rddata_valid = hex2int(row[col_idx["rddata_valid"]])
        rddata = row[col_idx["rddata"]]
        bank = row[col_idx["bank"]]
        addr = row[col_idx["addr"]]
        data_match = hex2int(row[col_idx["data_match"]])
        burst_done = hex2int(row[col_idx["burst_done"]])
        rd_beat_cnt = hex2int(row[col_idx["rd_beat_cnt"]])
        write_burst_cnt = hex2int(row[col_idx["write_burst_cnt"]])
        write_delay_cnt = hex2int(row[col_idx["write_delay_cnt"]])
        init_done = hex2int(row[col_idx["init_done"]])
    except Exception as e:
        continue

    # --- FSM state transitions ---
    if fsm != last_fsm:
        fsm_states.append((sample_idx, fsm))
        last_fsm = fsm

    # --- Init sequence ---
    if init_done != last_init_done:
        init_seq.append((sample_idx, init_done))
        last_init_done = init_done

    # --- Data match changes ---
    if data_match != last_data_match:
        data_matches.append((sample_idx, data_match))
        last_data_match = data_match

    # --- Read Command events (rising edge, correct type) ---
    if cmd_valid == 1 and cmd_type == READ_CMD_TYPE:
        if last_cmd_type != READ_CMD_TYPE or last_cmd_valid != 1:
            cmd_events.append({"sample": sample_idx, "row": i, "bank": bank, "addr": addr, "timer": timer})

    # --- Burst Data Capture: every rddata_valid (for read bursts) ---
    if rddata_valid == 1:
        read_bursts.append({"sample": sample_idx, "beat_cnt": rd_beat_cnt, "data": rddata, "row": i})

    last_cmd_valid = cmd_valid
    last_cmd_type = cmd_type

# --- Summarize All Extracted Information ---

print("="*40)
print("FSM State Transitions (sample, state):")
for s, f in fsm_states:
    print(f"  Sample {s}: FSM state {f}")

print("="*40)
print("Init Sequence:")
for s, done in init_seq:
    print(f"  Sample {s}: init_done_q = {done}")

print("="*40)
print("Data Match Changes:")
for s, match in data_matches:
    print(f"  Sample {s}: ila_data_match = {match}")

print("="*40)
print("Read Commands and Read Bursts:")

for ci, cmd in enumerate(cmd_events):
    # Find first rddata_valid after command (first beat)
    bursts = [b for b in read_bursts if b["row"] > cmd["row"]]
    if bursts:
        first_burst = bursts[0]
        latency = first_burst["sample"] - cmd["sample"]
        print(f"\nREAD CMD at sample {cmd['sample']} (bank={cmd['bank']}, addr={cmd['addr']}), timer={cmd['timer']}")
        print(f"  First rddata_valid at {first_burst['sample']} (beat {first_burst['beat_cnt']}), latency: {latency} samples")
        # Print all subsequent beats for this burst (until beat_cnt rolls over or next cmd)
        print("  Burst read data:")
        burst_words = []
        for b in bursts[:4]:
            print(f"    Beat {b['beat_cnt']}: data = {b['data']}")
            burst_words.append(b['data'])
        # Optionally: Compare with expected/test pattern if available!
    else:
        print(f"\nREAD CMD at sample {cmd['sample']} (bank={cmd['bank']}, addr={cmd['addr']}), NO rddata_valid found after!")

print("="*40)
print("Summary of all read bursts (sample, beat, data):")
for b in read_bursts:
    print(f"  Sample {b['sample']}: beat {b['beat_cnt']}, data {b['data']}")

print("="*40)
print("Total read commands detected:", len(cmd_events))
print("Total burst read beats detected:", len(read_bursts))
print("="*40)
