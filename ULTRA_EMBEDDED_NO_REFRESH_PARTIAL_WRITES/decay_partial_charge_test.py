#!/usr/bin/env python3
"""
Combined DRAM Decay and Partial Charge Test Script
Tests both data retention (decay) and partial charge vulnerabilities
"""

import serial
import time
import csv
import json
import sys
import threading
from datetime import datetime, timedelta
from colorama import Fore, Back, Style, init
from collections import defaultdict
import numpy as np
import argparse

# Initialize colorama
init(autoreset=True)

# --- Configuration ---
DEFAULT_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.2

# Memory regions to test
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
    {"name": "Walking 1s", "value": 0x11111111, "hex": "11111111"},
    {"name": "Walking 0s", "value": 0xEEEEEEEE, "hex": "EEEEEEEE"},
]

# Decay test parameters
DECAY_DELAYS = [0.001, 0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0]  # seconds
DECAY_NWRITES = 10
DECAY_NVERIFY = 5

# Partial charge timing parameters
TIMING_CONFIGS = [
    # Format: (name, tRAS_trim, tWR_trim, write_cycles)
    ("Normal", 0, 0, 8),           # Baseline
    ("Light trim", 1, 1, 8),       # Slight timing reduction
    ("Medium trim", 2, 2, 8),      # Moderate reduction
    ("Heavy trim", 4, 4, 8),       # Aggressive reduction
    ("Burst 6", 0, 0, 6),          # Reduced burst length
    ("Burst 4", 0, 0, 4),          # Half burst
    ("Burst 2", 0, 0, 2),          # Quarter burst
    ("Burst 1", 0, 0, 1),          # Single beat
    ("Combo 1", 2, 2, 6),          # Combined timing+burst
    ("Combo 2", 4, 4, 4),          # Aggressive combo
    ("Extreme", 6, 6, 2),          # Very aggressive
]

# ASCII art
HEADER_ART = """
╔══════════════════════════════════════════════════════════════╗
║           DRAM VULNERABILITY ANALYSIS SUITE v2.0             ║
║                 Decay & Partial Charge Testing               ║
╚══════════════════════════════════════════════════════════════╝
"""

class DRAMTester:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.results = {
            'decay': [],
            'partial_charge': [],
            'combined_vulnerable': []
        }
        self.timing_enabled = False
        
    def write_cmd(self, addr, data):
        """Standard write command"""
        if isinstance(data, int):
            data = f"{data:08X}"
        cmd = f"W{addr:08X} {data}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.01)
    
    def read_cmd(self, addr):
        """Read command"""
        cmd = f"R{addr:08X}\r"
        self.ser.write(cmd.encode('ascii'))
        self.ser.flush()
        time.sleep(0.01)
        
        response = ""
        start_time = time.time()
        
        while time.time() - start_time < TIMEOUT:
            if self.ser.in_waiting:
                try:
                    line = self.ser.readline().decode("ascii", errors="ignore").strip()
                    if line:
                        response = line
                        break
                except:
                    pass
        
        # Extract hex value
        if response:
            hex_chars = ''.join(c for c in response[-8:] if c in '0123456789ABCDEFabcdef')
            if len(hex_chars) == 8:
                return hex_chars.upper()
        return None
    
    def config_timing(self, tras_trim, twr_trim, write_cycles, enable=True):
        """Configure timing parameters using C command"""
        # Format: C<tRAS><tWR><enable+cycles><reserved>
        enable_bit = 0x8 if enable else 0x0
        cycles_bits = write_cycles & 0x7
        nibble1 = enable_bit | cycles_bits
        
        cmd = f"C{tras_trim:01X}{twr_trim:01X}{nibble1:01X}0\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.02)
        self.timing_enabled = enable
        
    def reset_timing(self):
        """Reset to normal timing"""
        cmd = "C0\r"  # Special case to disable all modifications
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.02)
        self.timing_enabled = False
        
    def check_init_status(self):
        """Check if DDR3 is initialized"""
        self.ser.write(b"?\r")
        time.sleep(0.2)
        
        response = ""
        start_time = time.time()
        
        while time.time() - start_time < 0.5:
            if self.ser.in_waiting:
                try:
                    line = self.ser.readline().decode("ascii", errors="ignore").strip()
                    if line:
                        response = line
                        break
                except:
                    pass
        print("Init response: "+str(response))
        return response == "R"
    
    def get_timing_status(self):
        """Get current timing configuration"""
        self.ser.write(b"T\r")
        time.sleep(0.1)
        
        response = ""
        start_time = time.time()
        
        while time.time() - start_time < 0.5:
            if self.ser.in_waiting:
                try:
                    line = self.ser.readline().decode("ascii", errors="ignore").strip()
                    if line:
                        response = line
                        break
                except:
                    pass
        
        if len(response) >= 4:
            return {
                'enabled': response[0] == 'E',
                'tras_trim': int(response[1], 16),
                'twr_trim': int(response[2], 16),
                'write_cycles': int(response[3], 16)
            }
        return None
    
    def hamming_distance(self, val1, val2):
        """Calculate bit differences between two values"""
        if isinstance(val1, str):
            val1 = int(val1, 16)
        if isinstance(val2, str):
            val2 = int(val2, 16)
        return bin(val1 ^ val2).count('1')
    
    def analyze_bit_flips(self, expected, actual):
        """Analyze which bits flipped"""
        if isinstance(expected, str):
            expected = int(expected, 16)
        if isinstance(actual, str):
            actual = int(actual, 16)
            
        xor = expected ^ actual
        flipped_bits = []
        
        for i in range(32):
            if xor & (1 << i):
                flipped_bits.append(i)
                
        return flipped_bits
    
    def test_decay(self, addresses, pattern, delay):
        """Test data decay with specified pattern and delay"""
        pattern_hex = pattern['hex']
        results = []
        
        # Write pattern to all addresses
        for addr in addresses:
            for _ in range(DECAY_NWRITES):
                self.write_cmd(addr, pattern_hex)
        
        # Verify initial writes
        verified = []
        for addr in addresses:
            success = False
            for _ in range(DECAY_NVERIFY):
                data = self.read_cmd(addr)
                if data and data == pattern_hex:
                    success = True
                    break
            if success:
                verified.append(addr)
        
        if not verified:
            return results
        
        # Wait for decay
        time.sleep(delay)
        
        # Read back and check for decay
        for addr in verified:
            read_values = []
            for _ in range(3):
                data = self.read_cmd(addr)
                if data:
                    read_values.append(data)
            
            if read_values:
                # Use most common value
                final_value = max(set(read_values), key=read_values.count)
                
                if final_value != pattern_hex:
                    hamming = self.hamming_distance(pattern_hex, final_value)
                    flipped_bits = self.analyze_bit_flips(pattern_hex, final_value)
                    
                    results.append({
                        'addr': addr,
                        'pattern': pattern['name'],
                        'expected': pattern_hex,
                        'actual': final_value,
                        'delay': delay,
                        'hamming': hamming,
                        'flipped_bits': flipped_bits,
                        'type': 'decay'
                    })
        
        return results
    
    def test_partial_charge(self, addresses, pattern, timing_config):
        """Test partial charge vulnerability with timing modifications"""
        pattern_hex = pattern['hex']
        opposite_hex = "FFFFFFFF" if pattern_hex == "00000000" else "00000000"
        results = []
        
        # Configure timing
        name, tras_trim, twr_trim, write_cycles = timing_config
        self.config_timing(tras_trim, twr_trim, write_cycles, enable=True)
        
        # Write opposite pattern first
        for addr in addresses:
            for _ in range(3):
                self.write_cmd(addr, opposite_hex)
        
        # Quick verify
        verified = []
        for addr in addresses:
            data = self.read_cmd(addr)
            if data and data == opposite_hex:
                verified.append(addr)
        
        if not verified:
            return results
        
        # Write target pattern with modified timing
        for addr in verified:
            for _ in range(3):
                self.write_cmd(addr, pattern_hex)
        
        # Small delay
        time.sleep(0.01)
        
        # Read back immediately
        for addr in verified:
            read_values = []
            for _ in range(3):
                data = self.read_cmd(addr)
                if data:
                    read_values.append(data)
            
            if read_values:
                final_value = max(set(read_values), key=read_values.count)
                
                # Check for partial charge (incomplete write)
                if final_value != pattern_hex and final_value != opposite_hex:
                    hamming_from_target = self.hamming_distance(pattern_hex, final_value)
                    hamming_from_opposite = self.hamming_distance(opposite_hex, final_value)
                    flipped_bits = self.analyze_bit_flips(pattern_hex, final_value)
                    
                    # Calculate charge percentage (0% = opposite, 100% = target)
                    charge_percent = (32 - hamming_from_target) / 32 * 100
                    
                    results.append({
                        'addr': addr,
                        'pattern': pattern['name'],
                        'expected': pattern_hex,
                        'actual': final_value,
                        'timing_config': name,
                        'tras_trim': tras_trim,
                        'twr_trim': twr_trim,
                        'write_cycles': write_cycles,
                        'hamming_from_target': hamming_from_target,
                        'hamming_from_opposite': hamming_from_opposite,
                        'charge_percent': charge_percent,
                        'flipped_bits': flipped_bits,
                        'type': 'partial_charge'
                    })
        
        # Reset timing
        self.reset_timing()
        
        return results
    
    def run_comprehensive_test(self, test_decay=True, test_partial=True):
        """Run comprehensive vulnerability testing"""
        print(f"{Fore.CYAN}{HEADER_ART}{Style.RESET_ALL}")
        
        # Check initialization
        print(f"{Fore.YELLOW}Checking DDR3 initialization...{Style.RESET_ALL}")
        if not self.check_init_status():
            print(f"{Fore.RED}ERROR: DDR3 not initialized!{Style.RESET_ALL}")
            return False
        print(f"{Fore.GREEN}✓ DDR3 ready{Style.RESET_ALL}")
        
        # Collect all addresses
        all_addresses = []
        for region in MEMORY_REGIONS:
            region_addrs = list(range(region['start'], region['end'], region['step']))
            all_addresses.extend(region_addrs)
        
        print(f"\n{Fore.BLUE}Testing {len(all_addresses)} addresses across {len(MEMORY_REGIONS)} regions{Style.RESET_ALL}")
        
        # Phase 1: Decay Testing
        if test_decay:
            print(f"\n{Fore.YELLOW}{'='*60}{Style.RESET_ALL}")
            print(f"{Fore.YELLOW}PHASE 1: DECAY TESTING{Style.RESET_ALL}")
            print(f"{Fore.YELLOW}{'='*60}{Style.RESET_ALL}")
            
            decay_vulnerable = []
            
            for pattern in TEST_PATTERNS:
                print(f"\n{Fore.CYAN}Testing pattern: {pattern['name']}{Style.RESET_ALL}")
                
                for delay in DECAY_DELAYS:
                    print(f"  Delay: {delay}s... ", end='', flush=True)
                    
                    results = self.test_decay(all_addresses, pattern, delay)
                    
                    if results:
                        print(f"{Fore.RED}Found {len(results)} decayed cells!{Style.RESET_ALL}")
                        decay_vulnerable.extend(results)
                        self.results['decay'].extend(results)
                    else:
                        print(f"{Fore.GREEN}No decay{Style.RESET_ALL}")
        
        # Phase 2: Partial Charge Testing
        if test_partial:
            print(f"\n{Fore.YELLOW}{'='*60}{Style.RESET_ALL}")
            print(f"{Fore.YELLOW}PHASE 2: PARTIAL CHARGE TESTING{Style.RESET_ALL}")
            print(f"{Fore.YELLOW}{'='*60}{Style.RESET_ALL}")
            
            partial_vulnerable = []
            
            for pattern in TEST_PATTERNS:
                print(f"\n{Fore.CYAN}Testing pattern: {pattern['name']}{Style.RESET_ALL}")
                
                for timing_config in TIMING_CONFIGS:
                    name = timing_config[0]
                    print(f"  Config: {name}... ", end='', flush=True)
                    
                    results = self.test_partial_charge(all_addresses, pattern, timing_config)
                    
                    if results:
                        print(f"{Fore.RED}Found {len(results)} partial charges!{Style.RESET_ALL}")
                        partial_vulnerable.extend(results)
                        self.results['partial_charge'].extend(results)
                    else:
                        print(f"{Fore.GREEN}No partial charge{Style.RESET_ALL}")
        
        # Phase 3: Combined Analysis
        if test_decay and test_partial:
            print(f"\n{Fore.YELLOW}{'='*60}{Style.RESET_ALL}")
            print(f"{Fore.YELLOW}PHASE 3: COMBINED VULNERABILITY ANALYSIS{Style.RESET_ALL}")
            print(f"{Fore.YELLOW}{'='*60}{Style.RESET_ALL}")
            
            # Find addresses vulnerable to both
            decay_addrs = set(r['addr'] for r in self.results['decay'])
            partial_addrs = set(r['addr'] for r in self.results['partial_charge'])
            both_vulnerable = decay_addrs & partial_addrs
            
            if both_vulnerable:
                print(f"\n{Fore.MAGENTA}Found {len(both_vulnerable)} addresses vulnerable to BOTH decay and partial charge!{Style.RESET_ALL}")
                
                for addr in list(both_vulnerable)[:10]:  # Show first 10
                    print(f"  - 0x{addr:08X}")
                    
                self.results['combined_vulnerable'] = list(both_vulnerable)
        
        return True
    
    def generate_report(self, filename_prefix="dram_test"):
        """Generate comprehensive test report"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # JSON report with full data
        json_file = f"{filename_prefix}_{timestamp}.json"
        with open(json_file, 'w') as f:
            json.dump(self.results, f, indent=2)
        
        # CSV reports
        if self.results['decay']:
            csv_file = f"{filename_prefix}_decay_{timestamp}.csv"
            with open(csv_file, 'w', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=self.results['decay'][0].keys())
                writer.writeheader()
                writer.writerows(self.results['decay'])
        
        if self.results['partial_charge']:
            csv_file = f"{filename_prefix}_partial_{timestamp}.csv"
            with open(csv_file, 'w', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=self.results['partial_charge'][0].keys())
                writer.writeheader()
                writer.writerows(self.results['partial_charge'])
        
        # Summary report
        summary_file = f"{filename_prefix}_summary_{timestamp}.txt"
        with open(summary_file, 'w') as f:
            f.write("DRAM VULNERABILITY TEST SUMMARY\n")
            f.write("="*60 + "\n")
            f.write(f"Test Date: {datetime.now()}\n")
            f.write(f"Total Addresses Tested: {sum(len(range(r['start'], r['end'], r['step'])) for r in MEMORY_REGIONS)}\n")
            f.write("\n")
            
            # Decay summary
            f.write("DECAY VULNERABILITIES\n")
            f.write("-"*30 + "\n")
            if self.results['decay']:
                decay_by_delay = defaultdict(list)
                for r in self.results['decay']:
                    decay_by_delay[r['delay']].append(r)
                
                f.write(f"Total decay-vulnerable cells: {len(self.results['decay'])}\n")
                f.write(f"Unique addresses: {len(set(r['addr'] for r in self.results['decay']))}\n")
                f.write("\nBy delay time:\n")
                for delay in sorted(decay_by_delay.keys()):
                    f.write(f"  {delay:6.3f}s: {len(decay_by_delay[delay])} cells\n")
                
                # Find fastest decay
                if decay_by_delay:
                    min_delay = min(decay_by_delay.keys())
                    f.write(f"\nFastest decay: {min_delay}s\n")
                    f.write("Most vulnerable addresses (fastest decay):\n")
                    for r in decay_by_delay[min_delay][:5]:
                        f.write(f"  0x{r['addr']:08X} - {r['pattern']} pattern, {r['hamming']} bits flipped\n")
            else:
                f.write("No decay vulnerabilities found\n")
            
            f.write("\n")
            
            # Partial charge summary
            f.write("PARTIAL CHARGE VULNERABILITIES\n")
            f.write("-"*30 + "\n")
            if self.results['partial_charge']:
                partial_by_config = defaultdict(list)
                for r in self.results['partial_charge']:
                    partial_by_config[r['timing_config']].append(r)
                
                f.write(f"Total partial-charge vulnerable cells: {len(self.results['partial_charge'])}\n")
                f.write(f"Unique addresses: {len(set(r['addr'] for r in self.results['partial_charge']))}\n")
                f.write("\nBy timing configuration:\n")
                for config in TIMING_CONFIGS:
                    name = config[0]
                    if name in partial_by_config:
                        f.write(f"  {name:15s}: {len(partial_by_config[name])} cells\n")
                
                # Find best partial charge configs
                best_partials = sorted(self.results['partial_charge'], 
                                     key=lambda x: abs(x['charge_percent'] - 50))[:10]
                
                f.write("\nBest partial charge results (closest to 50% charge):\n")
                for r in best_partials:
                    f.write(f"  0x{r['addr']:08X} - {r['timing_config']} - "
                           f"{r['charge_percent']:.1f}% charged\n")
            else:
                f.write("No partial charge vulnerabilities found\n")
            
            f.write("\n")
            
            # Combined vulnerabilities
            if self.results['combined_vulnerable']:
                f.write("COMBINED VULNERABILITIES\n")
                f.write("-"*30 + "\n")
                f.write(f"Addresses vulnerable to BOTH decay and partial charge: "
                       f"{len(self.results['combined_vulnerable'])}\n")
                f.write("These are prime targets for advanced attacks:\n")
                for addr in self.results['combined_vulnerable'][:10]:
                    f.write(f"  0x{addr:08X}\n")
            
            f.write("\n")
            
            # Bit analysis
            f.write("BIT FLIP ANALYSIS\n")
            f.write("-"*30 + "\n")
            all_flipped_bits = []
            for r in self.results['decay'] + self.results['partial_charge']:
                all_flipped_bits.extend(r['flipped_bits'])
            
            if all_flipped_bits:
                bit_counts = defaultdict(int)
                for bit in all_flipped_bits:
                    bit_counts[bit] += 1
                
                f.write("Most frequently flipped bits:\n")
                for bit, count in sorted(bit_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
                    f.write(f"  Bit {bit:2d}: {count} flips ({count/len(all_flipped_bits)*100:.1f}%)\n")
            
            f.write("\n")
            
            # Recommendations
            f.write("ATTACK RECOMMENDATIONS\n")
            f.write("-"*30 + "\n")
            
            if self.results['decay'] and self.results['partial_charge']:
                min_decay_delay = min(r['delay'] for r in self.results['decay'])
                best_partial = min(self.results['partial_charge'], 
                                 key=lambda x: abs(x['charge_percent'] - 50))
                
                f.write("For ROWHAMMER attacks:\n")
                f.write(f"  - Target addresses with decay time < {min_decay_delay*2}s\n")
                f.write(f"  - Use timing config: {best_partial['timing_config']}\n")
                f.write(f"  - tRAS trim: {best_partial['tras_trim']}, tWR trim: {best_partial['twr_trim']}\n")
                f.write(f"  - Write cycles: {best_partial['write_cycles']}\n")
                
                if self.results['combined_vulnerable']:
                    f.write("\nFor maximum effect:\n")
                    f.write(f"  - Focus on {len(self.results['combined_vulnerable'])} combined-vulnerable addresses\n")
                    f.write("  - These show both decay and partial charge susceptibility\n")
            
        print(f"\n{Fore.GREEN}Reports generated:{Style.RESET_ALL}")
        print(f"  - {json_file}")
        print(f"  - {summary_file}")
        
        return summary_file

def print_banner():
    """Print colorful banner"""
    colors = [Fore.RED, Fore.YELLOW, Fore.GREEN, Fore.CYAN, Fore.BLUE, Fore.MAGENTA]
    lines = HEADER_ART.strip().split('\n')
    
    for i, line in enumerate(lines):
        color = colors[i % len(colors)]
        print(f"{color}{line}{Style.RESET_ALL}")
    
    print(f"\n{Fore.CYAN}Advanced DRAM vulnerability testing combining:")
    print(f"  • Data retention (decay) analysis")
    print(f"  • Partial charge vulnerability detection")
    print(f"  • Timing parameter manipulation")
    print(f"  • Combined attack vector identification{Style.RESET_ALL}\n")

def main():
    parser = argparse.ArgumentParser(description='DRAM Vulnerability Test Suite')
    parser.add_argument('-p', '--port', default=DEFAULT_PORT, help='Serial port')
    parser.add_argument('-d', '--decay-only', action='store_true', help='Run only decay tests')
    parser.add_argument('-c', '--charge-only', action='store_true', help='Run only partial charge tests')
    parser.add_argument('-o', '--output', default='dram_test', help='Output file prefix')
    parser.add_argument('--quick', action='store_true', help='Quick test with reduced parameters')
    args = parser.parse_args()
    
    # Reduce test parameters for quick mode
    if args.quick:
        global DECAY_DELAYS, TIMING_CONFIGS
        DECAY_DELAYS = [0.01, 0.1, 1.0]
        TIMING_CONFIGS = TIMING_CONFIGS[:5]
    
    print_banner()
    
    # Open serial connection
    try:
        print(f"{Fore.YELLOW}Connecting to {args.port}...{Style.RESET_ALL}")
        ser = serial.Serial(args.port, BAUDRATE, timeout=TIMEOUT)
        time.sleep(0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        print(f"{Fore.GREEN}✓ Connected successfully{Style.RESET_ALL}")
    except serial.SerialException as e:
        print(f"{Fore.RED}✗ Failed to open serial port: {e}{Style.RESET_ALL}")
        return 1
    
    # Create tester
    tester = DRAMTester(ser)
    
    # Determine test mode
    test_decay = not args.charge_only
    test_partial = not args.decay_only
    
    if args.decay_only:
        print(f"\n{Fore.YELLOW}Running DECAY tests only{Style.RESET_ALL}")
    elif args.charge_only:
        print(f"\n{Fore.YELLOW}Running PARTIAL CHARGE tests only{Style.RESET_ALL}")
    else:
        print(f"\n{Fore.YELLOW}Running FULL test suite{Style.RESET_ALL}")
    
    # Run tests
    start_time = time.time()
    success = False
    
    try:
        success = tester.run_comprehensive_test(test_decay=test_decay, test_partial=test_partial)
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Test interrupted by user{Style.RESET_ALL}")
    except Exception as e:
        print(f"\n{Fore.RED}Test error: {e}{Style.RESET_ALL}")
    
    elapsed = time.time() - start_time
    
    # Generate reports
    if success and (tester.results['decay'] or tester.results['partial_charge']):
        print(f"\n{Fore.YELLOW}Generating reports...{Style.RESET_ALL}")
        summary_file = tester.generate_report(args.output)
        
        # Print summary
        print(f"\n{Fore.CYAN}{'='*60}{Style.RESET_ALL}")
        print(f"{Fore.CYAN}TEST SUMMARY{Style.RESET_ALL}")
        print(f"{Fore.CYAN}{'='*60}{Style.RESET_ALL}")
        
        print(f"Total runtime: {elapsed/60:.1f} minutes")
        print(f"Decay vulnerabilities: {len(tester.results['decay'])}")
        print(f"Partial charge vulnerabilities: {len(tester.results['partial_charge'])}")
        
        if tester.results['combined_vulnerable']:
            print(f"{Fore.MAGENTA}Combined vulnerabilities: {len(tester.results['combined_vulnerable'])}{Style.RESET_ALL}")
            print(f"\n{Fore.GREEN}✓ High-value targets identified for advanced attacks!{Style.RESET_ALL}")
        
        # Show example attack command
        if tester.results['partial_charge']:
            best = min(tester.results['partial_charge'], 
                      key=lambda x: abs(x['charge_percent'] - 50))
            print(f"\n{Fore.YELLOW}Example attack configuration:{Style.RESET_ALL}")
            print(f"  C{best['tras_trim']:X}{best['twr_trim']:X}{0x8|best['write_cycles']:X}0")
            print(f"  This gives: tRAS-{best['tras_trim']}, tWR-{best['twr_trim']}, "
                  f"{best['write_cycles']} write cycles")
    else:
        print(f"\n{Fore.YELLOW}No vulnerabilities found or test incomplete{Style.RESET_ALL}")
    
    # Cleanup
    ser.close()
    
    # Fun exit message
    if success:
        print(f"\n{Fore.GREEN}", end='')
        for char in "⚡ Test complete! Happy hacking! ⚡":
            print(char, end='', flush=True)
            time.sleep(0.05)
        print(Style.RESET_ALL)
    
    return 0

if __name__ == "__main__":
    try:
        exit(main())
    except Exception as e:
        print(f"{Fore.RED}Unexpected error: {e}{Style.RESET_ALL}")
        exit(1)
