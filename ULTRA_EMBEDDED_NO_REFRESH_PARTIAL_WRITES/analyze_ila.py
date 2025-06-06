import pandas as pd
import sys
import numpy as np
from collections import defaultdict

def analyze_ila_data(csv_file):
    """
    Comprehensive analysis of DDR3 partial write ILA data
    """
    # Read the CSV file - first row has column names, second row has radix info
    with open(csv_file, 'r') as f:
        header_line = f.readline().strip()
        radix_line = f.readline().strip()
    
    # Parse column names
    column_names = [col.strip() for col in header_line.split(',')]
    
    # Read the data, skipping the first two rows
    df = pd.read_csv(csv_file, sep=',', skiprows=2, names=column_names)
    
    print("=== DDR3 Partial Write Debug Analysis ===\n")
    print(f"Total samples: {len(df)}")
    print(f"Columns found: {len(column_names)}")
    
    # Find trigger point if it exists
    if 'TRIGGER' in df.columns:
        trigger_samples = df[df['TRIGGER'] == 1]
        if len(trigger_samples) > 0:
            print(f"Trigger at sample: {trigger_samples.index[0]}")
        else:
            print("No trigger found in capture")
    
    # Convert hex columns to integers for analysis
    hex_columns = ['ddr3_core_state[3:0]', 'ddr3_seq_wrdata[31:0]', 'ddr3_seq_wrdata_mask[3:0]',
                   'dfi_wrdata[31:0]', 'dfi_wrdata_mask[3:0]', 'ila_seq_wr_cycle_cnt[3:0]',
                   'ila_seq_partial_cycles[3:0]']
    
    for col in hex_columns:
        if col in df.columns:
            # Create integer version of hex columns
            df[col + '_int'] = df[col].apply(lambda x: int(str(x), 16) if pd.notna(x) and str(x).strip() != '' else 0)
    
    # State mapping
    state_names = {
        0: 'INIT', 1: 'DELAY', 2: 'IDLE', 3: 'ACTIVATE',
        4: 'READ', 5: 'WRITE', 6: 'PRECHARGE', 7: 'REFRESH'
    }
    
    # Find all state transitions
    print("\n=== DDR3 Controller State Transitions ===")
    state_changes = []
    prev_state = -1
    
    for idx, row in df.iterrows():
        curr_state = row['ddr3_core_state[3:0]_int']
        if curr_state != prev_state:
            state_name = state_names.get(curr_state, f'UNKNOWN({curr_state})')
            state_changes.append((idx, curr_state, state_name))
            if len(state_changes) > 1:
                duration = idx - state_changes[-2][0]
                print(f"Sample {state_changes[-2][0]:5d}: {state_changes[-2][2]:10s} -> {state_name:10s} (duration: {duration} cycles)")
            prev_state = curr_state
    
    # Find write operations
    print("\n=== Write Operations Analysis ===")
    write_states = df[df['ddr3_core_state[3:0]_int'] == 5]  # STATE_WRITE
    print(f"Total samples in WRITE state: {len(write_states)}")
    
    # Analyze write bursts based on ddr3_seq_wrdata_en
    print("\n=== Write Burst Analysis (Sequencer Level) ===")
    
    # Find bursts where wrdata_en is active
    bursts = []
    in_burst = False
    burst_start = 0
    
    for idx, row in df.iterrows():
        if row['ddr3_seq_wrdata_en'] == 1 and not in_burst:
            in_burst = True
            burst_start = idx
        elif row['ddr3_seq_wrdata_en'] == 0 and in_burst:
            in_burst = False
            bursts.append((burst_start, idx - 1))
    
    if in_burst:  # Handle case where burst extends to end of capture
        bursts.append((burst_start, len(df) - 1))
    
    print(f"Found {len(bursts)} write burst(s)")
    
    if len(bursts) == 0:
        print("\nNo write bursts found! Check if:")
        print("  - The capture includes a write operation")
        print("  - The trigger is set correctly")
        print("  - The ILA is connected to the right signals")
        return
    
    for burst_num, (start, end) in enumerate(bursts, 1):
        print(f"\n{'='*60}")
        print(f"Write Burst #{burst_num}")
        print(f"{'='*60}")
        print(f"Start: Sample {start}, End: Sample {end}, Length: {end - start + 1} cycles")
        
        # Get configuration
        partial_en = df.loc[start, 'ila_seq_partial_en']
        partial_cycles = df.loc[start, 'ila_seq_partial_cycles[3:0]_int']
        
        print(f"\nConfiguration:")
        print(f"  Partial Write Enabled: {'Yes' if partial_en == 1 else 'No'}")
        print(f"  Partial Write Cycles: {partial_cycles}")
        
        # Detailed cycle analysis
        print("\nDetailed Cycle Analysis:")
        print("Cycle | wr_cnt | wr_en | seq_data   | seq_mask | dfi_en | dfi_data   | dfi_mask | burst_act | wr_en_w")
        print("-" * 105)
        
        cycle_masks = []
        dfi_masks = []
        
        for i, idx in enumerate(range(start, end + 1)):
            row = df.loc[idx]
            cycle_cnt = row['ila_seq_wr_cycle_cnt[3:0]_int']
            wr_en = row['ddr3_seq_wrdata_en']
            seq_wrdata = row['ddr3_seq_wrdata[31:0]']
            seq_mask = row['ddr3_seq_wrdata_mask[3:0]_int']
            dfi_en = row['dfi_wrdata_en']
            dfi_data = row['dfi_wrdata[31:0]']
            dfi_mask = row['dfi_wrdata_mask[3:0]_int']
            burst_active = row['ila_seq_wr_burst_active']
            wr_en_w = row['ila_seq_wr_en_w']
            
            cycle_masks.append(seq_mask)
            dfi_masks.append(dfi_mask)
            
            # Format the data nicely
            seq_mask_str = f"0x{seq_mask:X}"
            dfi_mask_str = f"0x{dfi_mask:X}"
            
            print(f"{i+1:5} | {cycle_cnt:6} | {wr_en:5} | {seq_wrdata:10} | {seq_mask_str:8} | "
                  f"{dfi_en:6} | {dfi_data:10} | {dfi_mask_str:8} | {burst_active:9} | {wr_en_w:7}")
        
        # Analyze mask behavior
        print("\nMask Analysis:")
        unique_seq_masks = list(set(cycle_masks))
        unique_dfi_masks = list(set(dfi_masks))
        print(f"  Unique sequencer mask values: {[f'0x{m:X}' for m in unique_seq_masks]}")
        print(f"  Unique DFI mask values: {[f'0x{m:X}' for m in unique_dfi_masks]}")
        
        # Determine actual burst length
        max_cycle_cnt = max(df.loc[start:end, 'ila_seq_wr_cycle_cnt[3:0]_int'])
        print(f"\n  Detected burst length: {max_cycle_cnt} (based on max wr_cycle_cnt)")
        
        if partial_en == 1:
            print(f"\n  Partial Write Analysis (enabled, {partial_cycles} cycles):")
            
            # Expected behavior
            print(f"    Expected behavior with burst_len={max_cycle_cnt}, partial_cycles={partial_cycles}:")
            for cycle in range(1, max_cycle_cnt + 1):
                if cycle <= partial_cycles:
                    print(f"      Cycle {cycle}: Write data (mask = 0x0)")
                else:
                    print(f"      Cycle {cycle}: Mask data (mask = 0xF)")
            
            # Actual behavior
            print("\n    Actual mask values by cycle:")
            for i, (seq_mask, dfi_mask) in enumerate(zip(cycle_masks[:max_cycle_cnt], dfi_masks[:max_cycle_cnt])):
                print(f"      Cycle {i+1}: seq_mask = 0x{seq_mask:X}, dfi_mask = 0x{dfi_mask:X}")
            
            # Check if it's working
            all_dfi_masks_zero = all(m == 0 for m in dfi_masks)
            if all_dfi_masks_zero:
                print("\n    ❌ ISSUE: All DFI masks are 0 - partial write is NOT working!")
                print("       The mask logic is not propagating to the DFI interface.")
            else:
                # Check if masks change at the right time
                correct_masking = True
                for i in range(max_cycle_cnt):
                    expected_mask = 0xF if (i + 1) > partial_cycles else 0x0
                    if i < len(dfi_masks) and dfi_masks[i] != expected_mask:
                        correct_masking = False
                        break
                
                if correct_masking:
                    print("\n    ✅ Partial write masking appears to be working correctly!")
                else:
                    print("\n    ⚠️  Partial write masking is active but not at the expected cycles.")
        else:
            print("\n  Partial write is DISABLED - all masks should be 0x0")
            if all(m == 0 for m in dfi_masks):
                print("    ✅ Correct - all masks are 0x0")
            else:
                print("    ❌ ISSUE: Masks are non-zero even though partial write is disabled!")
    
    # Check timing relationships
    print("\n=== Timing Analysis ===")
    
    for burst_num, (start, end) in enumerate(bursts[:1], 1):  # Analyze first burst
        # Find when wr_en_w goes high
        wr_en_w_high = df.loc[start:end][df.loc[start:end, 'ila_seq_wr_en_w'] == 1]
        if len(wr_en_w_high) > 0:
            print(f"\nBurst #{burst_num}:")
            print(f"  ila_seq_wr_en_w active for {len(wr_en_w_high)} cycles")
            
            # Check relationship between wr_en_w and wr_cycle_cnt
            print("\n  Relationship between wr_en_w and wr_cycle_cnt:")
            for idx in wr_en_w_high.index[:5]:  # Show first 5
                cycle_cnt = df.loc[idx, 'ila_seq_wr_cycle_cnt[3:0]_int']
                print(f"    Sample {idx}: wr_en_w=1, wr_cycle_cnt={cycle_cnt}")
    
    # Final diagnosis
    print("\n" + "="*60)
    print("DIAGNOSIS AND RECOMMENDATIONS")
    print("="*60)
    
    issues = []
    
    # Check burst length
    if len(bursts) > 0:
        actual_burst_len = max(df['ila_seq_wr_cycle_cnt[3:0]_int'])
        if actual_burst_len != 8:
            issues.append(f"DDR burst length is {actual_burst_len}, not 8")
    
    # Check if masks ever change
    all_dfi_masks = df['dfi_wrdata_mask[3:0]_int']
    if all(all_dfi_masks == 0):
        issues.append("DFI write masks never change from 0")
    
    # Check configuration issues
    for burst_num, (start, end) in enumerate(bursts, 1):
        partial_en = df.loc[start, 'ila_seq_partial_en']
        partial_cycles = df.loc[start, 'ila_seq_partial_cycles[3:0]_int']
        if partial_en == 1:
            if partial_cycles >= actual_burst_len:
                issues.append(f"Burst #{burst_num}: partial_cycles ({partial_cycles}) >= burst_length ({actual_burst_len}) - no masking will occur")
    
    if issues:
        print("\nIssues Found:")
        for i, issue in enumerate(issues, 1):
            print(f"  {i}. {issue}")
        
        print("\nRecommendations:")
        if actual_burst_len < 8:
            print(f"\n  For burst length = {actual_burst_len}, test with these configurations:")
            for cycles in range(1, actual_burst_len):
                print(f"    - C1{cycles}: Should write {cycles} cycle{'s' if cycles > 1 else ''}, mask {actual_burst_len - cycles} cycle{'s' if actual_burst_len - cycles > 1 else ''}")
        
        if all(all_dfi_masks == 0):
            print("\n  The partial write logic is not working. Check:")
            print("    1. The mask logic in ddr3_dfi_seq (around line 300)")
            print("    2. The comparison: wr_beat_cnt_q vs partial_write_cycles_i")
            print("    3. Make sure wr_burst_active_q is being set correctly")
            print("    4. Verify the mask assignment happens during wr_en_w high")
    else:
        print("\nNo obvious issues found. The implementation appears to be working.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python analyze_ddr3_ila.py <csv_file>")
        sys.exit(1)
    
    try:
        analyze_ila_data(sys.argv[1])
    except Exception as e:
        print(f"Error analyzing file: {e}")
        import traceback
        traceback.print_exc()
