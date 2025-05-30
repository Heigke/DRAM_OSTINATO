import csv

csv_file = "iladata_r.csv"

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
    "burst_done": "ila_read_burst_done",
    "rd_beat_cnt": "ila_rd_beat_cnt[1:0]",
    "write_burst_cnt": "ila_write_burst_cnt[2:0]",
    "write_delay_cnt": "ila_write_delay_cnt[3:0]",
    "data_match": "ila_data_match",
    "init_done": "init_done_q",
}

READ_CMD_TYPE = "5"
WRITE_CMD_TYPE = "4"

def hex2int(s):
    try:
        if "x" in s.lower() or "z" in s.lower():
            return 0
        return int(s, 16)
    except Exception:
        return 0

with open(csv_file, newline='') as f:
    reader = csv.reader(f, delimiter=',')
    header1 = next(reader)
    header2 = next(reader)
    header1 = [h.strip() for h in header1]
    col_idx = {name: header1.index(KEY_FIELDS[name]) for name in KEY_FIELDS}
    rows = list(reader)

# --- Event lists and state tracking ---
fsm_transitions, init_done_events, data_match_events = [], [], []
raw_cmd_events, grouped_read_bursts, grouped_write_bursts = [], [], []
raw_read_beats, raw_write_beats = [], []
timing_latencies = []

current_read_burst, current_write_burst = [], []
pending_read_cmd, pending_write_cmd = None, None

used_read_samples, used_write_samples = set(), set()
extra_read_beats, extra_write_beats = [], []

last_fsm = last_cmd_valid = last_cmd_type = last_rddata_valid = last_wrdata_en = None
last_data_match = last_init_done = None

for i, row in enumerate(rows):
    try:
        sample_idx = int(row[col_idx["sample"]])
        fsm = row[col_idx["fsm"]]
        timer = hex2int(row[col_idx["timer"]])
        cmd_valid = hex2int(row[col_idx["cmd_valid"]])
        cmd_type = str(int(row[col_idx["cmd_type"]], 16))
        bank = row[col_idx["bank"]]
        addr = row[col_idx["addr"]]
        wrdata_en = hex2int(row[col_idx["wrdata_en"]])
        wrdata = row[col_idx["wrdata"]]
        rddata_valid = hex2int(row[col_idx["rddata_valid"]])
        rddata = row[col_idx["rddata"]]
        burst_done = hex2int(row[col_idx["burst_done"]])
        rd_beat_cnt = hex2int(row[col_idx["rd_beat_cnt"]])
        write_burst_cnt = hex2int(row[col_idx["write_burst_cnt"]])
        write_delay_cnt = hex2int(row[col_idx["write_delay_cnt"]])
        data_match = hex2int(row[col_idx["data_match"]])
        init_done = hex2int(row[col_idx["init_done"]])
    except Exception:
        continue

    # FSM transitions
    if fsm != last_fsm:
        fsm_transitions.append({"sample": sample_idx, "fsm": fsm})
        last_fsm = fsm

    # Init done events
    if init_done != last_init_done:
        init_done_events.append({"sample": sample_idx, "init_done": init_done})
        last_init_done = init_done

    # Data match events
    if data_match != last_data_match:
        data_match_events.append({"sample": sample_idx, "data_match": data_match})
        last_data_match = data_match

    # Command events: capture all, plus for read/write burst matching
    if cmd_valid == 1 and (last_cmd_valid != 1 or last_cmd_type != cmd_type):
        cmd_evt = {
            "sample": sample_idx,
            "cmd_type": cmd_type,
            "bank": bank,
            "addr": addr,
            "fsm": fsm,
            "timer": timer
        }
        raw_cmd_events.append(cmd_evt)
        # Save for matching data burst to command
        if cmd_type == READ_CMD_TYPE:
            pending_read_cmd = cmd_evt.copy()
        elif cmd_type == WRITE_CMD_TYPE:
            pending_write_cmd = cmd_evt.copy()
    last_cmd_valid = cmd_valid
    last_cmd_type = cmd_type

    # Write burst handling and latency
    if wrdata_en == 1:
        beat = {
            "sample": sample_idx,
            "beat_cnt": write_burst_cnt,
            "data": wrdata,
            "bank": bank,
            "addr": addr,
            "timer": timer,
            "fsm": fsm
        }
        raw_write_beats.append(beat)
        current_write_burst.append(beat)
        used_write_samples.add(sample_idx)
        # For first beat, measure latency from last pending write cmd
        if pending_write_cmd and len(current_write_burst) == 1:
            timing_latencies.append({
                "event": "write_latency",
                "cmd_sample": pending_write_cmd["sample"],
                "data_sample": sample_idx,
                "latency": sample_idx - pending_write_cmd["sample"],
                "bank": bank,
                "addr": addr,
                "timer_cmd": pending_write_cmd["timer"],
                "timer_data": timer
            })
            pending_write_cmd = None
        if write_burst_cnt == 3 or len(current_write_burst) == 4 or burst_done == 1:
            grouped_write_bursts.append(current_write_burst)
            current_write_burst = []

    last_wrdata_en = wrdata_en

    # Read burst handling and latency
    if rddata_valid == 1:
        beat = {
            "sample": sample_idx,
            "beat_cnt": rd_beat_cnt,
            "data": rddata,
            "bank": bank,
            "addr": addr,
            "timer": timer,
            "fsm": fsm
        }
        raw_read_beats.append(beat)
        current_read_burst.append(beat)
        used_read_samples.add(sample_idx)
        # For first beat, measure latency from last pending read cmd
        if pending_read_cmd and len(current_read_burst) == 1:
            timing_latencies.append({
                "event": "read_latency",
                "cmd_sample": pending_read_cmd["sample"],
                "data_sample": sample_idx,
                "latency": sample_idx - pending_read_cmd["sample"],
                "bank": bank,
                "addr": addr,
                "timer_cmd": pending_read_cmd["timer"],
                "timer_data": timer
            })
            pending_read_cmd = None
        if rd_beat_cnt == 3 or len(current_read_burst) == 4 or burst_done == 1:
            grouped_read_bursts.append(current_read_burst)
            current_read_burst = []

    last_rddata_valid = rddata_valid

# Find extra/stray beats (not in any burst)
seen_read_samples = set([w['sample'] for burst in grouped_read_bursts for w in burst])
seen_write_samples = set([w['sample'] for burst in grouped_write_bursts for w in burst])
for beat in raw_read_beats:
    if beat["sample"] not in seen_read_samples:
        extra_read_beats.append(beat)
for beat in raw_write_beats:
    if beat["sample"] not in seen_write_samples:
        extra_write_beats.append(beat)

# --- Output ---
print("="*80)
print("FSM State Transitions:")
for t in fsm_transitions:
    print(f"  Sample {t['sample']}: FSM state {t['fsm']}")
print("="*80)
print("Init Done Events:")
for t in init_done_events:
    print(f"  Sample {t['sample']}: init_done = {t['init_done']}")
print("="*80)
print("Data Match Events:")
for t in data_match_events:
    print(f"  Sample {t['sample']}: data_match = {t['data_match']}")
print("="*80)
print("Command Events:")
for t in raw_cmd_events:
    print(f"  Sample {t['sample']}: CMD type {t['cmd_type']}, bank {t['bank']}, addr {t['addr']}, FSM {t['fsm']}, timer {t['timer']}")
print("="*80)
print("Grouped Read Bursts:")
for idx, burst in enumerate(grouped_read_bursts):
    print(f"  Burst {idx}:")
    for word in burst:
        print(f"    Sample {word['sample']}, Beat {word['beat_cnt']}, Data {word['data']}, Timer {word['timer']}, FSM {word['fsm']}")
print("="*80)
print("Grouped Write Bursts:")
for idx, burst in enumerate(grouped_write_bursts):
    print(f"  Burst {idx}:")
    for word in burst:
        print(f"    Sample {word['sample']}, Beat {word['beat_cnt']}, Data {word['data']}, Timer {word['timer']}, FSM {word['fsm']}")
print("="*80)
print("All Read Beats:")
for beat in raw_read_beats:
    print(f"  Sample {beat['sample']}: beat {beat['beat_cnt']}, data {beat['data']}, timer {beat['timer']}, FSM {beat['fsm']}")
print("="*80)
print("All Write Beats:")
for beat in raw_write_beats:
    print(f"  Sample {beat['sample']}: beat {beat['beat_cnt']}, data {beat['data']}, timer {beat['timer']}, FSM {beat['fsm']}")
print("="*80)
print("Extra/Stray Read Beats (not in burst):")
for beat in extra_read_beats:
    print(f"  Sample {beat['sample']}: beat {beat['beat_cnt']}, data {beat['data']}")
print("="*80)
print("Extra/Stray Write Beats (not in burst):")
for beat in extra_write_beats:
    print(f"  Sample {beat['sample']}: beat {beat['beat_cnt']}, data {beat['data']}")
print("="*80)
print("Burst Latencies:")
for t in timing_latencies:
    print(f"  {t['event'].upper()}: CMD at {t['cmd_sample']}, first data at {t['data_sample']} -> latency {t['latency']} (timer {t['timer_cmd']}->{t['timer_data']}), bank {t['bank']}, addr {t['addr']}")
print("="*80)

# Export to CSV for ML/post-processing
with open("ila_debug_events_export.csv", "w", newline='') as outcsv:
    fieldnames = [
        "event", "burst_idx", "sample", "beat_cnt", "data", "timer", "fsm", "bank", "addr",
        "cmd_type", "init_done", "data_match", "cmd_sample", "data_sample", "latency", "timer_cmd", "timer_data"
    ]
    writer = csv.DictWriter(outcsv, fieldnames=fieldnames)
    writer.writeheader()
    for idx, burst in enumerate(grouped_read_bursts):
        for word in burst:
            writer.writerow({"event": "read_burst", "burst_idx": idx, **word})
    for idx, burst in enumerate(grouped_write_bursts):
        for word in burst:
            writer.writerow({"event": "write_burst", "burst_idx": idx, **word})
    for beat in raw_read_beats:
        writer.writerow({"event": "raw_read", "burst_idx": "", **beat})
    for beat in raw_write_beats:
        writer.writerow({"event": "raw_write", "burst_idx": "", **beat})
    for t in fsm_transitions:
        writer.writerow({"event": "fsm_transition", "burst_idx": "", "sample": t['sample'], "fsm": t['fsm']})
    for t in init_done_events:
        writer.writerow({"event": "init_done", "burst_idx": "", "sample": t['sample'], "init_done": t['init_done']})
    for t in data_match_events:
        writer.writerow({"event": "data_match", "burst_idx": "", "sample": t['sample'], "data_match": t['data_match']})
    for t in raw_cmd_events:
        writer.writerow({
            "event": "cmd_event", "burst_idx": "", "sample": t['sample'], "cmd_type": t.get("cmd_type", ""),
            "bank": t.get("bank", ""), "addr": t.get("addr", ""), "fsm": t.get("fsm", ""), "timer": t.get("timer", "")
        })
    for t in timing_latencies:
        writer.writerow({
            "event": t["event"], "burst_idx": "", "cmd_sample": t["cmd_sample"], "data_sample": t["data_sample"],
            "latency": t["latency"], "bank": t["bank"], "addr": t["addr"],
            "timer_cmd": t["timer_cmd"], "timer_data": t["timer_data"]
        })

print("Exported all events to 'ila_debug_events_export.csv' for model input/post-processing.")
print("="*80)
print(f"Total FSM transitions: {len(fsm_transitions)}")
print(f"Total init_done events: {len(init_done_events)}")
print(f"Total data_match events: {len(data_match_events)}")
print(f"Total read bursts: {len(grouped_read_bursts)}")
print(f"Total write bursts: {len(grouped_write_bursts)}")
print(f"Total raw read beats: {len(raw_read_beats)}")
print(f"Total raw write beats: {len(raw_write_beats)}")
print(f"Total extra read beats: {len(extra_read_beats)}")
print(f"Total extra write beats: {len(extra_write_beats)}")
print(f"Total burst latencies: {len(timing_latencies)}")
print("="*80)
