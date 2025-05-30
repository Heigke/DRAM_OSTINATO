import csv

# Put your CSV file path here
csv_file = "iladata_read_trust.csv"

# Define the key fields for analysis
KEY_FIELDS = {
    "sample": "Sample in Buffer",
    "cmd_valid": "ila_cmd_valid",
    "cmd_type": "ila_cmd_type[2:0]",
    "rddata_valid": "ila_rddata_valid"
}

# Typically DDR3 READ command: RAS=1, CAS=0, WE=1. Your FSM likely codes this as 0b101 = 5 or similar.
# Adjust as needed (use your FSM definitions or check the .csv for what values appear).
READ_CMD_TYPE = "5"  # This is common for DDR3, but double-check if yours differs.

def hex2int(s):
    try:
        if "x" in s.lower() or "z" in s.lower():
            return 0
        return int(s, 16)
    except Exception:
        return 0

# Read in the CSV, skip headers, get column indexes
with open(csv_file, newline='') as f:
#    reader = csv.reader(f, delimiter='\t')
    reader = csv.reader(f, delimiter=',')

    header1 = next(reader)
    header2 = next(reader)  # radix row, not used here
    print("HEADER 1:", header1)
    print("HEADER 2:", header2)

    col_idx = {name: header1.index(KEY_FIELDS[name]) for name in KEY_FIELDS}

    last_cmd_valid = None
    last_cmd_type = None
    last_rddata_valid = None

    read_cmds = []
    rddata_valid_events = []

    rows = list(reader)

    for i, row in enumerate(rows):
        try:
            sample_idx = int(row[col_idx["sample"]])
            cmd_valid = hex2int(row[col_idx["cmd_valid"]])
            cmd_type = str(int(row[col_idx["cmd_type"]], 16))
            rddata_valid = hex2int(row[col_idx["rddata_valid"]])
        except Exception:
            continue

        # Detect rising edge of a READ command (active valid, correct type, not just a repeat)
        if cmd_valid == 1 and cmd_type == READ_CMD_TYPE:
            if last_cmd_type != READ_CMD_TYPE or last_cmd_valid != 1:
                read_cmds.append((sample_idx, i))

        # Detect rising edge of rddata_valid
        if rddata_valid == 1 and (last_rddata_valid is None or last_rddata_valid == 0):
            rddata_valid_events.append((sample_idx, i))

        last_cmd_valid = cmd_valid
        last_cmd_type = cmd_type
        last_rddata_valid = rddata_valid

# Now, match each read command to the next rddata_valid and print latency
print("Read Command to Data Valid Latency:")
for cmd_sample, cmd_row in read_cmds:
    next_rd = next((rd_sample for rd_sample, rd_row in rddata_valid_events if rd_row > cmd_row), None)
    if next_rd is not None:
        latency = next_rd - cmd_sample
        print(f"Read command at sample {cmd_sample}, first rddata_valid at {next_rd}, latency: {latency} samples")
    else:
        print(f"Read command at sample {cmd_sample}, no rddata_valid found after.")

