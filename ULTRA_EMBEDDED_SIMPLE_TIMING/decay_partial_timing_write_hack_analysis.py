#!/usr/bin/env python3
"""
DRAM Vulnerability Analysis Suite v2.1
Tests Decay, Partial Charge, and Targeted Susceptibility to find high-value fault injection targets.
"""

import serial
import time
import csv
import json
import sys
import threading
import itertools
from datetime import datetime
from colorama import Fore, Back, Style, init
from collections import defaultdict
import argparse

# Initialize colorama
init(autoreset=True)

# --- Configuration ---
DEFAULT_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.2

# Memory regions to test (can be overridden by --quick)
MEMORY_REGIONS = [
    {"name": "Region 0", "start": 0x00000000, "end": 0x00010000, "step": 0x1000},
    {"name": "Region 1", "start": 0x00100000, "end": 0x00110000, "step": 0x1000},
]

# Test patterns
TEST_PATTERNS = [
    {"name": "All Ones", "value": 0xFFFFFFFF, "hex": "FFFFFFFF"},
    {"name": "All Zeros", "value": 0x00000000, "hex": "00000000"},
    {"name": "Checkerboard", "value": 0xAAAAAAAA, "hex": "AAAAAAAA"},
    {"name": "Inv Checker", "value": 0x55555555, "hex": "55555555"},
]

# Decay test parameters
DECAY_DELAYS = [0.01, 0.1, 0.5, 1.0, 2.0, 5.0, 10.0]  # seconds
DECAY_NWRITES = 10
DECAY_NVERIFY = 5

# Partial charge timing parameters (tWR, tRAS, Burst Len)
# Format: (name, tWR_val, tRAS_val, burst_len)
TIMING_CONFIGS = [
    ("Normal", 0, 0, 8),          # Baseline
    ("tWR-4", 4, 0, 8),           # tWR Trim
    ("tRAS-4", 0, 4, 8),          # tRAS Trim
    ("Burst 4", 0, 0, 4),         # Half burst length
    ("Burst 2", 0, 0, 2),         # Quarter burst
    ("tWR-4_tRAS-4", 4, 4, 8),    # Combo Trim
    ("tWR-4_Burst-4", 4, 0, 4),   # Combo Trim + Burst
    ("tRAS-4_Burst-4", 0, 4, 4),  # Combo Trim + Burst
    ("Extreme", 8, 8, 2),         # Aggressive combo
]


# ASCII art
HEADER_ART = """
██████╗ ██████╗  █████╗ ███╗   ███╗     ╦═╗╔═╗╔═╗╦╔═╗╔╦╗╔═╗╦═╗
██╔══██╗██╔══██╗██╔══██╗████╗ ████║     ╠╦╝║╣ ╚═╗║║ ║ ║║║╣ ╠╦╝
██████╔╝██████╔╝███████║██╔████╔██║     ╩╚═╚═╝╚═╝╩╚═╝═╩╝╚═╝╩╚═
██╔══██╗██╔══██╗██╔══██║██║╚██╔╝██║     V U L N E R A B I L I T Y
██║  ██║██║  ██║██║  ██║██║ ╚═╝ ██║     A N A L Y S I S   S U I T E
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝                 v2.1
"""

class Spinner:
    """A simple spinner context manager for showing activity during waits."""
    def __init__(self, message="Waiting..."):
        self.message = message
        self._thread = None
        self.running = False

    def _spin(self):
        spinner_chars = itertools.cycle(['-', '\\', '|', '/'])
        while self.running:
            sys.stdout.write(f"\r{Fore.YELLOW}{self.message} {next(spinner_chars)}{Style.RESET_ALL}")
            sys.stdout.flush()
            time.sleep(0.1)

    def __enter__(self):
        self.running = True
        self._thread = threading.Thread(target=self._spin)
        self._thread.start()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.running = False
        self._thread.join()
        sys.stdout.write(f"\r{' ' * (len(self.message) + 2)}\r") # Clear line
        sys.stdout.flush()


class DRAMTester:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.results = {
            'decay': [],
            'partial_charge': [],
            'targeted_susceptibility': [],
            'combined_vulnerable_addrs': []
        }

    def _read_response(self, timeout=TIMEOUT):
        """Helper function to read a single response line, removing duplicated code."""
        return self.ser.readline().decode("ascii", errors="ignore").strip()

    def write_cmd(self, addr, data):
        """Standard write command (W<addr_hex> <data_hex>)"""
        if isinstance(data, int):
            data = f"{data:08X}"
        cmd = f"W{addr:08X} {data}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.005) # Reduced delay for faster writes

    def read_cmd(self, addr):
        """Read command (R<addr_hex>)"""
        cmd = f"R{addr:08X}\r"
        self.ser.write(cmd.encode('ascii'))
        self.ser.flush()
        response = self._read_response()
        if response:
            hex_chars = ''.join(c for c in response if c in '0123456789ABCDEFabcdef')
            if len(hex_chars) >= 8:
                return hex_chars[-8:].upper()
        return None

    def config_timing(self, twr, tras, burst, custom=0):
        """
        FIXED: Configure timing parameters using 'T' command.
        Format: T<twr_hex_byte><tras_hex_byte><burst_hex_byte><custom_hex_byte>
        """
        data_hex = f"{twr:02X}{tras:02X}{burst:02X}{custom:02X}"
        cmd = f"T{data_hex}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.2)

    def reset_timing(self):
        """FIXED: Reset to normal timing by sending all zeros."""
        self.config_timing(0, 0, 0, 0)

    def check_init_status(self):
        """Check if DDR3 is initialized by sending '?'"""
        self.ser.write(b"?\r")
        time.sleep(0.2) # Wait for response
        response = self._read_response()
        print(response)
        print(f"Init response from board: '{response}'")
        return "R" in response

    def get_timing_status(self):
        """FIXED: Get current timing configuration using 't' command"""
        self.ser.write(b"t\r")
        self.ser.write(b"t\r")
        self.ser.write(b"t\r")
        self.ser.write(b"t\r")
        response = self._read_response()
        print("Timing response: "+str(response))
        # Expected format from Verilog: T:<twr><tras><burst><custom> e.g., "T:04040800"
        if response and response.startswith("T:") and len(response) >= 11:
            try:
                return {
                    'twr': int(response[2:4], 16),
                    'tras': int(response[4:6], 16),
                    'burst': int(response[6:8], 16),
                    'custom': int(response[8:10], 16)
                }
            except (ValueError, IndexError):
                return None
        return None

    def hamming_distance(self, val1, val2):
        if isinstance(val1, str): val1 = int(val1, 16)
        if isinstance(val2, str): val2 = int(val2, 16)
        return bin(val1 ^ val2).count('1')

    def analyze_bit_flips(self, expected, actual):
        if isinstance(expected, str): expected = int(expected, 16)
        if isinstance(actual, str): actual = int(actual, 16)
        return [i for i in range(32) if ((expected ^ actual) >> i) & 1]

    def _execute_test(self, addresses, pattern, action, **kwargs):
        """A generic test executor to reduce code duplication."""
        results = []
        for addr in addresses:
            data = action(addr, pattern, **kwargs)
            if data:
                results.append(data)
        return results

    def _decay_action(self, addr, pattern, delay):
        # Write pattern multiple times
        for _ in range(DECAY_NWRITES):
            self.write_cmd(addr, pattern['hex'])
        
        # Verify write before waiting
        if self.read_cmd(addr) != pattern['hex']:
            return None # Write failed, skip this address

        # Wait for decay
        time.sleep(delay)

        # Read back and check
        data = self.read_cmd(addr)
        if data and data != pattern['hex']:
            return {
                'addr': addr, 'pattern': pattern['name'], 'expected': pattern['hex'],
                'actual': data, 'delay': delay,
                'hamming': self.hamming_distance(pattern['hex'], data),
                'flipped_bits': self.analyze_bit_flips(pattern['hex'], data),
                'type': 'decay'
            }
        return None

    def test_decay(self, addresses, pattern, delay):
        """Test data decay with specified pattern and delay"""
        with Spinner(f"Decaying for {delay}s..."):
            # This is a bit complex to fit into the generic executor due to the single long sleep
            # So we keep its structure but could refactor the inner loop logic
            results = []
            
            # Prepare all addresses first
            for addr in addresses:
                for _ in range(DECAY_NWRITES):
                    self.write_cmd(addr, pattern['hex'])

            # Wait for decay
            time.sleep(delay)

            # Read back and check
            for addr in addresses:
                read_back = self.read_cmd(addr)
                if read_back and read_back != pattern['hex']:
                     results.append({
                        'addr': addr, 'pattern': pattern['name'], 'expected': pattern['hex'],
                        'actual': read_back, 'delay': delay,
                        'hamming': self.hamming_distance(pattern['hex'], read_back),
                        'flipped_bits': self.analyze_bit_flips(pattern['hex'], read_back),
                        'type': 'decay'
                    })
            return results


    def test_partial_charge(self, addresses, pattern, timing_config):
        """Test partial charge vulnerability with timing modifications"""
        pattern_hex = pattern['hex']
        opposite_hex = f"{pattern['value'] ^ 0xFFFFFFFF:08X}"
        results = []
        name, twr, tras, burst = timing_config

        self.config_timing(twr, tras, burst)

        for addr in addresses:
            self.write_cmd(addr, opposite_hex)
            self.write_cmd(addr, pattern_hex)
            data = self.read_cmd(addr)
            if data and data != pattern_hex:
                results.append({
                    'addr': addr, 'pattern': pattern['name'], 'expected': pattern_hex,
                    'actual': data, 'timing_config': name, 'twr': twr, 'tras': tras,
                    'burst': burst, 'hamming': self.hamming_distance(pattern_hex, data),
                    'flipped_bits': self.analyze_bit_flips(pattern_hex, data),
                    'type': 'partial_charge'
                })
        self.reset_timing()
        return results

    def test_targeted_susceptibility(self, vulnerable_addrs, timing_configs, pattern):
        """
        NEW: A focused test on known weak cells.
        Takes addresses that failed the decay test and hits them with partial charge attacks.
        """
        if not vulnerable_addrs: return []
        
        results = []
        pattern_hex = pattern['hex']
        opposite_hex = f"{pattern['value'] ^ 0xFFFFFFFF:08X}"

        for addr in vulnerable_addrs:
            for config in timing_configs:
                name, twr, tras, burst = config
                self.config_timing(twr, tras, burst)
                self.write_cmd(addr, opposite_hex)
                self.write_cmd(addr, pattern_hex)
                data = self.read_cmd(addr)
                if data and data != pattern_hex:
                    results.append({
                        'addr': addr, 'pattern': pattern['name'],
                        'timing_config': name, 'twr': twr, 'tras': tras, 'burst': burst,
                        'expected': pattern_hex, 'actual': data,
                        'hamming': self.hamming_distance(pattern_hex, data),
                        'type': 'targeted_susceptibility'
                    })
        self.reset_timing()
        return results

    def run_comprehensive_test(self, test_decay=True, test_partial=True, test_targeted=False):
        """Run comprehensive vulnerability testing suite."""
        print(f"{Fore.CYAN}{HEADER_ART}{Style.RESET_ALL}")
        
        print(f"{Fore.YELLOW}Checking DDR3 initialization...{Style.RESET_ALL}")
        if not self.check_init_status():
            print(f"{Fore.RED}✗ ERROR: DDR3 not initialized! Aborting.{Style.RESET_ALL}")
            return False
        print(f"{Fore.GREEN}✓ DDR3 ready.{Style.RESET_ALL}")
        
        print(f"{Fore.YELLOW}Verifying timing control...{Style.RESET_ALL}")
        self.config_timing(twr=1, tras=2, burst=3)
        status = self.get_timing_status()
        if status and status['twr'] == 1 and status['tras'] == 2 and status['burst'] == 3:
             print(f"{Fore.GREEN}✓ Timing control verified.{Style.RESET_ALL}")
        else:
            print(f"{Fore.RED}✗ ERROR: Timing control verification failed! Got: {status}{Style.RESET_ALL}")
        self.reset_timing()

        all_addresses = [addr for r in MEMORY_REGIONS for addr in range(r['start'], r['end'], r['step'])]
        print(f"\n{Back.BLUE} Testing {len(all_addresses)} addresses across {len(MEMORY_REGIONS)} regions. {Style.RESET_ALL}")

        if test_decay:
            print(f"\n{Fore.CYAN}{'='*20} PHASE 1: DECAY TESTING (Finding Weak Cells) {'='*21}{Style.RESET_ALL}")
            for pattern in TEST_PATTERNS:
                print(f"\n{Fore.MAGENTA}Pattern: {pattern['name']}{Style.RESET_ALL}")
                results = self.test_decay(all_addresses, pattern, DECAY_DELAYS[-1]) # Use longest delay for initial screen
                if results:
                    print(f"  └─ {Fore.RED}Found {len(results)} potentially weak cells.{Style.RESET_ALL}")
                    self.results['decay'].extend(results)

        if test_partial:
            print(f"\n{Fore.CYAN}{'='*15} PHASE 2: PARTIAL CHARGE TESTING (Finding Timing-Sensitive Cells) {'='*16}{Style.RESET_ALL}")
            for pattern in TEST_PATTERNS:
                print(f"\n{Fore.MAGENTA}Pattern: {pattern['name']}{Style.RESET_ALL}")
                for timing_config in TIMING_CONFIGS:
                    print(f"  Config: {timing_config[0]:<15}... ", end='', flush=True)
                    results = self.test_partial_charge(all_addresses, pattern, timing_config)
                    if results:
                        print(f"{Fore.RED}{len(results)} flips!{Style.RESET_ALL}")
                        self.results['partial_charge'].extend(results)
                    else:
                        print(f"{Fore.GREEN}OK{Style.RESET_ALL}")

        decay_addrs = sorted(list({r['addr'] for r in self.results['decay']}))
        if test_targeted and decay_addrs:
            print(f"\n{Fore.CYAN}{'='*10} PHASE 3: TARGETED SUSCEPTIBILITY (Confirming High-Value Targets) {'='*11}{Style.RESET_ALL}")
            print(f"{Fore.YELLOW}Focusing on the {len(decay_addrs)} addresses identified as weak.{Style.RESET_ALL}")
            for pattern in TEST_PATTERNS:
                print(f"  Targeting with pattern {pattern['name']}... ", end='', flush=True)
                results = self.test_targeted_susceptibility(decay_addrs, TIMING_CONFIGS, pattern)
                if results:
                    print(f"{Fore.RED}SUCCESS! Found {len(results)} reproducible flips in weak cells.{Style.RESET_ALL}")
                    self.results['targeted_susceptibility'].extend(results)
                else:
                    print(f"{Fore.GREEN}No flips.{Style.RESET_ALL}")
        
        self.results['combined_vulnerable_addrs'] = sorted(list(
            {r['addr'] for r in self.results['decay']} & {r['addr'] for r in self.results['partial_charge']}
        ))
        
        return True


    def generate_report(self, filename_prefix="dram_test"):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_files = []
        json_file = f"{filename_prefix}_{timestamp}.json"
        with open(json_file, 'w') as f: json.dump(self.results, f, indent=2)
        report_files.append(json_file)

        for key, data in self.results.items():
            if isinstance(data, list) and data:
                csv_file = f"{filename_prefix}_{key}_{timestamp}.csv"
                try:
                    fieldnames = sorted(list(set(k for d in data for k in d.keys())))
                    with open(csv_file, 'w', newline='') as f:
                        writer = csv.DictWriter(f, fieldnames=fieldnames); writer.writeheader(); writer.writerows(data)
                    report_files.append(csv_file)
                except (IOError, IndexError): pass

        summary_file = f"{filename_prefix}_summary_{timestamp}.txt"
        with open(summary_file, 'w') as f:
            f.write(HEADER_ART + "\n")
            f.write("="*60 + "\n" + "DRAM VULNERABILITY TEST - EXECUTIVE SUMMARY\n" + "="*60 + "\n")
            f.write(f"Test Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            
            f.write("\n--- KEY FINDINGS ---\n")
            f.write(f"[✓] Decay Vulnerabilities (Weak Cells) Found:       {'YES' if self.results['decay'] else 'NO'}\n")
            f.write(f"[✓] Partial Charge Vulns (Timing Sensitive) Found:  {'YES' if self.results['partial_charge'] else 'NO'}\n")
            f.write(f"[✓] Targeted Susceptibility (Prime Targets) Found:  {'YES' if self.results['targeted_susceptibility'] else 'NO'}\n")
            if self.results['targeted_susceptibility']:
                f.write("\n>>> HIGH-VALUE TARGETS IDENTIFIED <<<\n"
                        "    Cells vulnerable to both decay and targeted partial charge attacks were found.\n"
                        "    These are prime candidates for reliable fault injection.\n")

            if self.results['targeted_susceptibility']:
                f.write("\n\n" + "="*60 + "\nTARGETED SUSCEPTIBILITY ANALYSIS (PRIME TARGETS)\n" + "="*60 + "\n")
                f.write("The following weak cells were successfully flipped using specific timing configs:\n\n")
                by_addr = defaultdict(list); [by_addr[r['addr']].append(r) for r in self.results['targeted_susceptibility']]
                for addr, records in list(by_addr.items())[:15]:
                    f.write(f"  [+] Address: 0x{addr:08X} (Pattern: {records[0]['pattern']})\n")
                    for r in records: f.write(f"      - Flipped with Timing Config: {r['timing_config']}\n")
                f.write("\n(See targeted_susceptibility CSV for full details)\n")

            if self.results['decay']:
                f.write("\n\n" + "="*60 + "\nDECAY VULNERABILITIES (WEAK CELLS)\n" + "="*60 + "\n")
                decay_by_delay = defaultdict(list); [decay_by_delay[r['delay']].append(r) for r in self.results['decay']]
                f.write(f"Total decay events: {len(self.results['decay'])}\n")
                f.write(f"Unique vulnerable addresses: {len(set(r['addr'] for r in self.results['decay']))}\n")
                f.write("\nEvents by delay time:\n")
                for delay in sorted(decay_by_delay.keys()): f.write(f"  {delay:6.3f}s: {len(decay_by_delay[delay])} events\n")

            if self.results['partial_charge']:
                f.write("\n\n" + "="*60 + "\nPARTIAL CHARGE VULNERABILITIES (TIMING SENSITIVE CELLS)\n" + "="*60 + "\n")
                partial_by_config = defaultdict(list); [partial_by_config[r['timing_config']].append(r) for r in self.results['partial_charge']]
                f.write(f"Total partial charge events: {len(self.results['partial_charge'])}\n")
                f.write(f"Unique vulnerable addresses: {len(set(r['addr'] for r in self.results['partial_charge']))}\n")
                f.write("\nEvents by timing configuration:\n")
                for config in TIMING_CONFIGS:
                    if config[0] in partial_by_config: f.write(f"  {config[0]:<15s}: {len(partial_by_config[config[0]])} events\n")

        print(f"\n{Fore.GREEN}Reports generated:{Style.RESET_ALL}")
        for f in report_files: print(f"  - {f}")
        return summary_file


def main():
    parser = argparse.ArgumentParser(
        description='DRAM Vulnerability Analysis Suite v2.1',
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument('-p', '--port', default=DEFAULT_PORT, help='Serial port to use (e.g., /dev/ttyUSB1 or COM3)')
    parser.add_argument('-d', '--decay-only', action='store_true', help='Run only decay tests to find weak cells.')
    parser.add_argument('-c', '--charge-only', action='store_true', help='Run only broad partial charge tests.')
    parser.add_argument('--targeted', action='store_true', help='Run all tests, including the advanced targeted susceptibility test.')
    parser.add_argument('-o', '--output', default='dram_report', help='Output file prefix for reports.')
    parser.add_argument('--quick', action='store_true', help='Quick test with reduced parameters for a fast overview.')
    args = parser.parse_args()

    if args.quick:
        global DECAY_DELAYS, TIMING_CONFIGS, MEMORY_REGIONS
        print(f"{Back.YELLOW}{Fore.BLACK} QUICK MODE ENABLED {Style.RESET_ALL}")
        DECAY_DELAYS = [0.1, 1.0]
        TIMING_CONFIGS = [TIMING_CONFIGS[0], TIMING_CONFIGS[-1]] # Normal and Extreme
        MEMORY_REGIONS = [{"name": "Quick Region", "start": 0x00000000, "end": 0x00004000, "step": 0x1000}]

    print(f"{Fore.CYAN}{HEADER_ART}{Style.RESET_ALL}")
    
    try:
        print(f"Connecting to {args.port} at {BAUDRATE} baud...")
        ser = serial.Serial(args.port, BAUDRATE, timeout=TIMEOUT)
        time.sleep(1)
        ser.reset_input_buffer()
        print(f"{Fore.GREEN}✓ Connected successfully.{Style.RESET_ALL}")
    except serial.SerialException as e:
        print(f"{Fore.RED}✗ Failed to open serial port: {e}{Style.RESET_ALL}")
        return 1

    tester = DRAMTester(ser)
    
    test_decay = not args.charge_only
    test_partial = not args.decay_only
    test_targeted = args.targeted
    if test_targeted: test_decay = test_partial = True

    start_time = time.time()
    success = False
    
    try:
        success = tester.run_comprehensive_test(test_decay, test_partial, test_targeted)
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Test interrupted by user.{Style.RESET_ALL}")
    except Exception as e:
        print(f"\n{Fore.RED}An unexpected error occurred: {e}{Style.RESET_ALL}")
    finally:
        tester.reset_timing()
        ser.close()

    elapsed = time.time() - start_time
    print(f"\nTotal runtime: {elapsed / 60:.1f} minutes")

    if success and any(tester.results.values()):
        tester.generate_report(args.output)
    else:
        print(f"\n{Fore.YELLOW}No vulnerabilities found or test was incomplete. No report generated.{Style.RESET_ALL}")
        
    print(f"\n{Fore.GREEN}⚡ Test complete! ⚡{Style.RESET_ALL}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
