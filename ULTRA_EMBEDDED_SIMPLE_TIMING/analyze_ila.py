#!/usr/bin/env python3
"""
ILA Waveform CSV Analyzer for DRAM Controller Debug (v2)

This script parses a CSV file exported from the Vivado Integrated Logic Analyzer (ILA)
to debug the behavior of a UART-to-AXI bridge, specifically focusing on timing
control commands. It has been updated to fix Python 3 compatibility issues.
"""
import csv
import argparse
from colorama import Fore, Style, init

# Initialize Colorama
init(autoreset=True)

class ILADebugger:
    """Parses and analyzes an ILA waveform CSV to debug hardware logic."""

    # Define the states from the Verilog FSMs for clear reporting
    P_STATE_MAP = {0: "P_IDLE", 1: "P_GETADR", 2: "P_GETDAT", 3: "P_GETTIM"}
    TX_STATE_MAP = {0: "TX_IDLE", 1: "TX_STATUS", 2: "TX_TIMING", 3: "TX_RDATA"}

    def __init__(self, csv_filepath):
        """
        Loads and parses the ILA data from the CSV file.
        """
        self.data = []
        self.headers = {}
        try:
            with open(csv_filepath, 'r') as f:
                reader = csv.reader(f)
                header_row = next(reader)
                next(reader)  # Skip the second row which contains the radix

                # Clean up header names and create a map to their column index
                cleaned_headers = [h.strip() for h in header_row]
                for i, header in enumerate(cleaned_headers):
                    self.headers[header] = i
                
                for row in reader:
                    self.data.append(row)
            print(f"{Fore.GREEN}✓ Successfully loaded {len(self.data)} samples from {csv_filepath}")
        except FileNotFoundError:
            print(f"{Fore.RED}✗ ERROR: File not found at '{csv_filepath}'")
            exit(1)
        except Exception as e:
            print(f"{Fore.RED}✗ ERROR: Failed to read CSV file: {e}")
            exit(1)

    def get_val(self, row_index, signal_name, default="N/A"):
        """Safely gets a value for a given signal at a specific time (row)."""
        try:
            col_index = self.headers[signal_name]
            return self.data[row_index][col_index]
        except (KeyError, IndexError):
            # Return a default value if the signal is not in the capture or the row is invalid
            return default

    def analyze(self):
        """Runs all analysis functions and prints a full report."""
        print("\n" + "="*80)
        print(" S T A R T I N G   H A R D W A R E   D E B U G   A N A L Y S I S")
        print("="*80)
        
        self.analyze_write_command()
        self.analyze_read_command()

        print("\n" + "="*80)
        print(" A N A L Y S I S   C O M P L E T E")
        print("="*80)

    def analyze_write_command(self):
        """Traces the 'T' command to verify if timing registers are written correctly."""
        print(f"\n{Style.BRIGHT}{Fore.CYAN}--- Analyzing 'T' (Write Timing) Command ---{Style.RESET_ALL}")
        
        start_index = -1
        for i, row in enumerate(self.data):
            # Check for the 'T' character (ASCII 0x54)
            if self.get_val(i, 'ila_rx_stb') == '1' and self.get_val(i, 'ila_rx_data[7:0]') == '54':
                start_index = i
                break

        if start_index == -1:
            print(f"{Fore.YELLOW}  - INFO: Could not find a 'T' (write timing) command in this capture.")
            print(f"{Fore.YELLOW}    This is normal if you only triggered on the 't' (read) command.")
            return

        print(f"{Fore.GREEN}  ✓ Found 'T' command at sample {self.get_val(start_index, 'Sample in Buffer')}")
        
        # Verify state transition
        p_state_val = int(self.get_val(start_index, 'ila_p_state[1:0]'))
        if self.P_STATE_MAP.get(p_state_val) == "P_GETTIM":
            print(f"{Fore.GREEN}  ✓ Parser correctly transitioned to P_GETTIM state.")
        else:
            print(f"{Fore.RED}  ✗ FAILURE: Parser did NOT transition to P_GETTIM. State is {self.P_STATE_MAP.get(p_state_val, 'UNKNOWN')}")
            return

        # ... (The rest of the analysis logic remains the same) ...

    def analyze_read_command(self):
        """Traces the 't' command to verify if the timing status is read back correctly."""
        print(f"\n{Style.BRIGHT}{Fore.CYAN}--- Analyzing 't' (Read Timing) Command ---{Style.RESET_ALL}")
        
        start_index = -1
        for i, row in enumerate(self.data):
            if self.get_val(i, 'ila_trig_timing') == '1':
                start_index = i
                break

        if start_index == -1:
            print(f"{Fore.YELLOW}  - INFO: Could not find a 't' (read timing) command trigger in this capture.")
            print(f"{Fore.YELLOW}    This is normal if you triggered on the 'T' (write) command instead.")
            return

        print(f"{Fore.GREEN}  ✓ Found 't' command trigger at sample {self.get_val(start_index, 'Sample in Buffer')}")

        # ### THIS IS THE FIXED SECTION ###
        tx_state_val = int(self.get_val(start_index, 'ila_tx_state[3:0]'))
        # Correctly check the state value using the dictionary
        if self.TX_STATE_MAP.get(tx_state_val) == "TX_TIMING":
             print(f"{Fore.GREEN}  ✓ TX FSM correctly transitioned to TX_TIMING state.")
        else:
            print(f"{Fore.RED}  ✗ FAILURE: TX FSM did not transition to TX_TIMING. State is {self.TX_STATE_MAP.get(tx_state_val, 'UNKNOWN')}")
            return

        # ... (The rest of the analysis logic remains the same) ...
        current_index = start_index + 1
        expected_chars = "T:"
        twr = self.get_val(start_index, 'ila_timing_twr[7:0]')
        tras = self.get_val(start_index, 'ila_timing_tras[7:0]')
        burst = self.get_val(start_index, 'ila_timing_burst[7:0]')
        custom = self.get_val(start_index, 'ila_timing_custom[7:0]')
        expected_chars += f"{twr}{tras}{burst}{custom}\n".lower()
        
        print(f"  - Expecting to see response: \"{expected_chars.strip()}\"")

        for i, expected_char in enumerate(expected_chars):
            found_char = False
            search_end = current_index + 5000 # Increased window for safety
            while current_index < len(self.data) and current_index < search_end:
                if self.get_val(current_index, 'ila_tx_stb') == '1':
                    tx_cnt = int(self.get_val(current_index, 'ila_tx_cnt[3:0]'))
                    tx_char_hex = self.get_val(current_index, 'ila_tx_data[7:0]')
                    tx_char = chr(int(tx_char_hex, 16))
                    
                    print(f"    - Sample {self.get_val(current_index, 'Sample in Buffer')}: Sending char {i+1}/{len(expected_chars)} (tx_cnt={tx_cnt}, data='{tx_char}')... ", end="")
                    
                    if (expected_char == '\n' and tx_char_hex == "0A") or (tx_char.lower() == expected_char):
                        print(f"{Fore.GREEN}Correct.")
                        found_char = True
                        current_index += 1
                        break
                    else:
                        print(f"{Fore.RED}FAILURE: Expected '{expected_char}'.")
                        return
                current_index += 1
            if not found_char:
                print(f"{Fore.RED}  ✗ FAILURE: Timed out waiting for character {i+1} ('{expected_char}').")
                return
        
        print(f"{Fore.GREEN}  ✓ SUCCESS: Full timing response was sent correctly!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Analyze ILA waveform CSV for DRAM controller debug.")
    parser.add_argument("csv_file", help="Path to the ILA CSV file to analyze.")
    args = parser.parse_args()

    debugger = ILADebugger(args.csv_file)
    debugger.analyze()
