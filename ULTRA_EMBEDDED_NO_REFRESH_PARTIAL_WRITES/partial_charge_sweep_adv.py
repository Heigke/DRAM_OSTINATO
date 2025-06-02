#!/usr/bin/env python3

import serial
import time
import random
import sys
import threading
from colorama import Fore, Back, Style, init
from datetime import datetime, timedelta
import numpy as np
from collections import defaultdict

# Initialize colorama
init(autoreset=True)

# --- Configuration ---
SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.2

# Test addresses - use your weak cells from decay test
TEST_ADDRESSES = [
    0x00007000, 0x00008000, 0x0008F000, 0x00B60000,
    0x00ED8000, 0x00908000, 0x00F10000, 0x01E40000,
    0x00990000, 0x00AE8000, 0x00B58000, 0x00B90000,
    0x00BB0000, 0x00BC0000, 0x01E00000, 0x01000000,
    0x00A00000, 0x00C00000, 0x01C00000, 0x01030000,
]

# Partial write durations to test (in DDR cycles)
PARTIAL_DURATIONS = [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20, 25, 30]

# Test patterns with descriptions
TEST_PATTERNS = [
    {"name": "All High", "value": "FFFFFFFF", "description": "Maximum charge target"},
    {"name": "All Low", "value": "00000000", "description": "Minimum charge target"},
    {"name": "Checker", "value": "AAAAAAAA", "description": "Alternating bits"},
    {"name": "InvCheck", "value": "55555555", "description": "Inverse alternating"},
    {"name": "HighLow", "value": "FFFF0000", "description": "Half high, half low"},
    {"name": "LowHigh", "value": "0000FFFF", "description": "Half low, half high"},
    {"name": "Single1", "value": "00000001", "description": "Single bit high"},
    {"name": "Single0", "value": "FFFFFFFE", "description": "Single bit low"},
]

# Read delays after partial write (ms)
READ_DELAYS = [0, 10, 50, 100, 500, 1000]

# Number of repetitions per test
REPETITIONS = 3

# ASCII Art and animations
BANNER = f"""{Fore.CYAN}
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║   ██████╗  █████╗ ██████╗ ████████╗██╗ █████╗ ██╗          ██████╗██╗  ██╗ ║
║   ██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██║██╔══██╗██║         ██╔════╝██║  ██║ ║
║   ██████╔╝███████║██████╔╝   ██║   ██║███████║██║         ██║     ███████║ ║
║   ██╔═══╝ ██╔══██║██╔══██╗   ██║   ██║██╔══██║██║         ██║     ██╔══██║ ║
║   ██║     ██║  ██║██║  ██║   ██║   ██║██║  ██║███████╗    ╚██████╗██║  ██║ ║
║   ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝  ╚═╝╚══════╝     ╚═════╝╚═╝  ╚═╝ ║
║                                                                              ║
║                      {Fore.YELLOW}⚡ DRAM Partial Charge Analyzer ⚡{Fore.CYAN}                      ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
{Style.RESET_ALL}"""

CHARGE_LEVELS = [
    "░░░░░░░░",  # 0-12.5%
    "█░░░░░░░",  # 12.5-25%
    "██░░░░░░",  # 25-37.5%
    "███░░░░░",  # 37.5-50%
    "████░░░░",  # 50-62.5%
    "█████░░░",  # 62.5-75%
    "██████░░",  # 75-87.5%
    "███████░",  # 87.5-100%
    "████████",  # 100%
]

ANIMATIONS = {
    'charge': ['⚡', '🔌', '⚡', '💡', '⚡', '🔋', '⚡'],
    'test': ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'],
    'wait': ['⏳', '⌛', '⏳', '⌛'],
    'success': ['✨', '💫', '⭐', '🌟'],
}

def clear_line():
    """Clear the current line"""
    print('\r' + ' ' * 100 + '\r', end='', flush=True)

def fancy_print(message, msg_type="info", indent=0):
    """Print messages with fancy formatting"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    indent_str = "  " * indent
    
    if msg_type == "header":
        print(f"\n{Fore.CYAN}{'═' * 80}")
        print(f"{Fore.CYAN}║{Style.BRIGHT} {message.center(76)} {Style.NORMAL}{Fore.CYAN}║")
        print(f"{Fore.CYAN}{'═' * 80}{Style.RESET_ALL}")
    elif msg_type == "subheader":
        print(f"\n{indent_str}{Fore.BLUE}┌─ {message} {'─' * (60 - len(message) - len(indent_str))}")
    elif msg_type == "success":
        print(f"{indent_str}{Fore.GREEN}[{timestamp}] ✓ {message}{Style.RESET_ALL}")
    elif msg_type == "error":
        print(f"{indent_str}{Fore.RED}[{timestamp}] ✗ {message}{Style.RESET_ALL}")
    elif msg_type == "warning":
        print(f"{indent_str}{Fore.YELLOW}[{timestamp}] ⚠ {message}{Style.RESET_ALL}")
    elif msg_type == "found":
        print(f"{indent_str}{Fore.MAGENTA}[{timestamp}] 🎯 {message}{Style.RESET_ALL}")
    elif msg_type == "charge":
        print(f"{indent_str}{Fore.YELLOW}[{timestamp}] ⚡ {message}{Style.RESET_ALL}")
    elif msg_type == "data":
        print(f"{indent_str}{Fore.CYAN}[{timestamp}] 📊 {message}{Style.RESET_ALL}")
    else:
        print(f"{indent_str}{Fore.BLUE}[{timestamp}] ℹ {message}{Style.RESET_ALL}")

def progress_bar(current, total, width=50, title="Progress", show_percent=True, color_mode="gradient"):
    """Enhanced progress bar with multiple color modes"""
    percentage = current / total if total > 0 else 0
    filled = int(width * percentage)
    
    # Color selection based on mode
    if color_mode == "gradient":
        if percentage < 0.25:
            bar_color = Fore.RED
        elif percentage < 0.50:
            bar_color = Fore.YELLOW
        elif percentage < 0.75:
            bar_color = Fore.CYAN
        else:
            bar_color = Fore.GREEN
    elif color_mode == "charge":
        bar_color = Fore.YELLOW
    else:
        bar_color = Fore.BLUE
    
    # Create the bar
    bar_filled = bar_color + '█' * filled
    bar_empty = Fore.WHITE + '░' * (width - filled)
    bar = f"{bar_filled}{bar_empty}"
    
    # Percentage display
    percent_str = f" {percentage*100:.1f}%" if show_percent else ""
    
    # Stats display
    stats = f" ({current}/{total})"
    
    print(f"\r{title}: [{bar}]{percent_str}{stats}  ", end='', flush=True)

def visualize_bits(value1, value2):
    """Visualize bit differences between two values"""
    try:
        v1 = int(value1, 16)
        v2 = int(value2, 16)
        
        visual = ""
        for i in range(31, -1, -1):
            bit1 = (v1 >> i) & 1
            bit2 = (v2 >> i) & 1
            
            if bit1 == bit2 == 1:
                visual += f"{Fore.GREEN}1"
            elif bit1 == bit2 == 0:
                visual += f"{Fore.BLUE}0"
            elif bit1 == 1 and bit2 == 0:
                visual += f"{Fore.RED}↓"  # Discharged
            else:
                visual += f"{Fore.YELLOW}↑"  # Charged up
            
            if i % 4 == 0 and i > 0:
                visual += " "
        
        return visual + Style.RESET_ALL
    except:
        return "ERROR"

def calculate_charge_level(expected, actual):
    """Calculate and visualize charge level"""
    try:
        exp_val = int(expected, 16)
        act_val = int(actual, 16)
        
        # Count matching bits weighted by position
        match_score = 0
        total_score = 0
        
        for i in range(32):
            exp_bit = (exp_val >> i) & 1
            act_bit = (act_val >> i) & 1
            weight = 1  # Could weight MSBs higher
            
            total_score += weight
            if exp_bit == act_bit:
                match_score += weight
        
        charge_percent = (match_score / total_score) * 100 if total_score > 0 else 0
        
        # Select charge visualization
        level_idx = min(int(charge_percent / 12.5), 8)
        charge_visual = CHARGE_LEVELS[level_idx]
        
        # Color based on charge level
        if charge_percent > 90:
            color = Fore.GREEN
        elif charge_percent > 70:
            color = Fore.CYAN
        elif charge_percent > 50:
            color = Fore.YELLOW
        elif charge_percent > 30:
            color = Fore.MAGENTA
        else:
            color = Fore.RED
        
        return {
            'percent': charge_percent,
            'visual': f"{color}{charge_visual}{Style.RESET_ALL}",
            'match_bits': match_score,
            'total_bits': total_score
        }
    except:
        return {
            'percent': 0,
            'visual': f"{Fore.RED}ERROR{Style.RESET_ALL}",
            'match_bits': 0,
            'total_bits': 32
        }

class PartialChargeTester:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.results = []
        self.summary_stats = defaultdict(lambda: defaultdict(int))
        
    def write_cmd(self, addr, data):
        """Standard write command"""
        cmd = f"W{addr:08X} {data}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.01)
    
    def partial_write_cmd(self, addr, data, duration):
        """Partial write command: PAAAAAAAA DDDDDDDD TTTT"""
        cmd = f"P{addr:08X} {data} {duration:04X}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.02)  # Slightly longer delay for partial writes
    
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
                    if line and len(line) >= 8:
                        response = line
                        break
                except:
                    pass
        
        return response[-8:].upper() if response and len(response) >= 8 else None
    
    def test_partial_charge(self, addr, pattern, duration, read_delay_ms=0):
        """Test partial charge at specific address"""
        pattern_val = pattern['value']
        
        # Step 1: Write opposite pattern to ensure we can detect changes
        opposite = "FFFFFFFF" if pattern_val == "00000000" else "00000000"
        self.write_cmd(addr, opposite)
        time.sleep(0.01)
        
        # Verify opposite pattern
        verify = self.read_cmd(addr)
        if verify != opposite:
            return None
        
        # Step 2: Perform partial write
        self.partial_write_cmd(addr, pattern_val, duration)
        
        # Step 3: Wait if specified
        if read_delay_ms > 0:
            time.sleep(read_delay_ms / 1000.0)
        
        # Step 4: Read back
        readback = self.read_cmd(addr)
        
        if readback:
            charge_info = calculate_charge_level(pattern_val, readback)
            
            result = {
                'addr': addr,
                'pattern': pattern['name'],
                'pattern_val': pattern_val,
                'duration': duration,
                'read_delay_ms': read_delay_ms,
                'opposite': opposite,
                'readback': readback,
                'charge_level': charge_info['percent'],
                'charge_visual': charge_info['visual'],
                'match_bits': charge_info['match_bits'],
                'bit_visual': visualize_bits(pattern_val, readback)
            }
            
            return result
        
        return None
    
    def run_comprehensive_test(self, addresses=None):
        """Run comprehensive partial charge characterization"""
        
        if addresses is None:
            addresses = TEST_ADDRESSES
        
        # Display banner
        print(BANNER)
        
        fancy_print("INITIALIZING PARTIAL CHARGE CHARACTERIZATION", "header")
        
        # Calculate total tests
        total_tests = len(addresses) * len(TEST_PATTERNS) * len(PARTIAL_DURATIONS) * len(READ_DELAYS) * REPETITIONS
        fancy_print(f"Test Configuration:", "info")
        fancy_print(f"Addresses to test: {len(addresses)}", "data", 1)
        fancy_print(f"Patterns: {len(TEST_PATTERNS)}", "data", 1)
        fancy_print(f"Duration steps: {len(PARTIAL_DURATIONS)} ({min(PARTIAL_DURATIONS)}-{max(PARTIAL_DURATIONS)} cycles)", "data", 1)
        fancy_print(f"Read delays: {len(READ_DELAYS)} ({min(READ_DELAYS)}-{max(READ_DELAYS)}ms)", "data", 1)
        fancy_print(f"Repetitions: {REPETITIONS}", "data", 1)
        fancy_print(f"Total measurements: {total_tests:,}", "data", 1)
        
        # Estimate time
        time_per_test = 0.1  # seconds
        estimated_time = total_tests * time_per_test
        fancy_print(f"Estimated time: {estimated_time/60:.1f} minutes", "info", 1)
        
        test_num = 0
        vulnerable_cells = []
        charge_profiles = defaultdict(list)
        
        # Main test loop
        for addr_idx, addr in enumerate(addresses):
            fancy_print(f"TESTING ADDRESS 0x{addr:08X} [{addr_idx+1}/{len(addresses)}]", "subheader")
            
            addr_results = []
            
            for pattern in TEST_PATTERNS:
                pattern_charge_data = []
                
                for duration in PARTIAL_DURATIONS:
                    duration_results = []
                    
                    for delay_ms in READ_DELAYS:
                        delay_charge_sum = 0
                        valid_tests = 0
                        
                        for rep in range(REPETITIONS):
                            test_num += 1
                            
                            # Update progress every 10 tests
                            if test_num % 10 == 0:
                                progress_bar(test_num, total_tests, 
                                           title=f"  Testing {pattern['name']} @ {duration} cycles",
                                           color_mode="charge")
                            
                            # Run test
                            result = self.test_partial_charge(addr, pattern, duration, delay_ms)
                            
                            if result:
                                self.results.append(result)
                                delay_charge_sum += result['charge_level']
                                valid_tests += 1
                                
                                # Check for interesting results
                                if 20 < result['charge_level'] < 80:  # Partial charge detected
                                    vulnerable_cells.append(result)
                        
                        # Calculate average for this delay
                        if valid_tests > 0:
                            avg_charge = delay_charge_sum / valid_tests
                            duration_results.append({
                                'delay_ms': delay_ms,
                                'avg_charge': avg_charge
                            })
                    
                    # Store results for this duration
                    if duration_results:
                        pattern_charge_data.append({
                            'duration': duration,
                            'delays': duration_results
                        })
                
                # Visualize pattern results
                if pattern_charge_data:
                    clear_line()
                    print(f"\n    {Fore.CYAN}Pattern: {pattern['name']} - {pattern['description']}{Style.RESET_ALL}")
                    print(f"    {'Duration':<10} {'Charge Level by Read Delay (ms)':<50}")
                    print(f"    {'(cycles)':<10} {'0':<8} {'10':<8} {'50':<8} {'100':<8} {'500':<8} {'1000':<8}")
                    print(f"    {'-'*70}")
                    
                    for dur_data in pattern_charge_data[:8]:  # Show first 8 durations
                        dur = dur_data['duration']
                        line = f"    {dur:<10}"
                        
                        for delay_info in dur_data['delays']:
                            charge = delay_info['avg_charge']
                            
                            # Color code the charge level
                            if charge > 90:
                                color = Fore.GREEN
                            elif charge > 70:
                                color = Fore.CYAN
                            elif charge > 50:
                                color = Fore.YELLOW
                            elif charge > 30:
                                color = Fore.MAGENTA
                            else:
                                color = Fore.RED
                            
                            line += f"{color}{charge:>6.1f}%{Style.RESET_ALL}  "
                        
                        print(line)
            
            print()  # Blank line between addresses
        
        clear_line()
        fancy_print("ANALYSIS COMPLETE!", "header")
        
        # Generate comprehensive analysis
        self.analyze_results(vulnerable_cells)
        
        return vulnerable_cells
    
    def analyze_results(self, vulnerable_cells):
        """Analyze and display comprehensive results"""
        
        if not self.results:
            fancy_print("No test results to analyze!", "warning")
            return
        
        # 1. Charge Profile Analysis
        fancy_print("CHARGE RETENTION PROFILES", "subheader")
        
        # Group by duration
        duration_stats = defaultdict(list)
        for r in self.results:
            duration_stats[r['duration']].append(r['charge_level'])
        
        print(f"\n  {Fore.CYAN}Average Charge Level by Write Duration:{Style.RESET_ALL}")
        print(f"  {'Duration':<12} {'Avg Charge':<12} {'Visualization':<30} {'Samples':<10}")
        print(f"  {'-'*65}")
        
        for duration in sorted(duration_stats.keys()):
            charges = duration_stats[duration]
            avg_charge = sum(charges) / len(charges)
            
            # Create visual bar
            bar_len = int(avg_charge / 5)  # 20 char max
            bar = '█' * bar_len + '░' * (20 - bar_len)
            
            # Color based on charge
            if avg_charge > 80:
                color = Fore.GREEN
            elif avg_charge > 60:
                color = Fore.CYAN
            elif avg_charge > 40:
                color = Fore.YELLOW
            else:
                color = Fore.RED
            
            print(f"  {duration:<12} {avg_charge:>10.1f}% {color}{bar}{Style.RESET_ALL} {len(charges):>8}")
        
        # 2. Vulnerable Cells Summary
        if vulnerable_cells:
            fancy_print("CELLS WITH PARTIAL CHARGE VULNERABILITY", "subheader")
            
            # Find cells most sensitive to partial writes
            addr_vulnerability = defaultdict(list)
            for cell in vulnerable_cells:
                addr_vulnerability[cell['addr']].append(cell)
            
            print(f"\n  {Fore.MAGENTA}Top Vulnerable Addresses:{Style.RESET_ALL}")
            print(f"  {'Address':<12} {'Min Duration':<15} {'Avg Partial':<15} {'Pattern':<15}")
            print(f"  {'-'*60}")
            
            # Sort by number of vulnerable conditions
            sorted_addrs = sorted(addr_vulnerability.items(), 
                                key=lambda x: len(x[1]), reverse=True)[:10]
            
            for addr, cells in sorted_addrs:
                min_duration = min(c['duration'] for c in cells)
                avg_partial = sum(c['charge_level'] for c in cells) / len(cells)
                common_pattern = max(set(c['pattern'] for c in cells), 
                                   key=lambda p: sum(1 for c in cells if c['pattern'] == p))
                
                # Vulnerability indicator
                if min_duration <= 3:
                    vuln_color = Fore.RED
                    vuln_text = "CRITICAL"
                elif min_duration <= 6:
                    vuln_color = Fore.YELLOW
                    vuln_text = "HIGH"
                else:
                    vuln_color = Fore.GREEN
                    vuln_text = "MEDIUM"
                
                print(f"  0x{addr:08X}   {min_duration:<15} {avg_partial:>13.1f}% {common_pattern:<15} "
                      f"{vuln_color}[{vuln_text}]{Style.RESET_ALL}")
        
        # 3. Optimal Attack Parameters
        fancy_print("OPTIMAL PARTIAL CHARGE PARAMETERS", "subheader")
        
        # Find duration that creates most partial charges (30-70% range)
        partial_by_duration = defaultdict(int)
        for r in self.results:
            if 30 <= r['charge_level'] <= 70:
                partial_by_duration[r['duration']] += 1
        
        if partial_by_duration:
            optimal_duration = max(partial_by_duration.items(), key=lambda x: x[1])[0]
            print(f"\n  {Fore.GREEN}Recommended partial write duration: {optimal_duration} cycles{Style.RESET_ALL}")
            print(f"  This duration created partial charges in {partial_by_duration[optimal_duration]} tests")
        
        # 4. Charge Decay Analysis
        fancy_print("CHARGE DECAY CHARACTERISTICS", "subheader")
        
        # Analyze how charge changes with read delay
        delay_stats = defaultdict(list)
        for r in self.results:
            if r['read_delay_ms'] > 0:
                delay_stats[r['read_delay_ms']].append(r['charge_level'])
        
        if delay_stats:
            print(f"\n  {Fore.CYAN}Average Charge Retention Over Time:{Style.RESET_ALL}")
            print(f"  {'Delay (ms)':<12} {'Avg Charge':<12} {'Decay':<12}")
            print(f"  {'-'*36}")
            
            baseline = sum(self.results[i]['charge_level'] for i in range(len(self.results)) 
                         if self.results[i]['read_delay_ms'] == 0) / len([r for r in self.results if r['read_delay_ms'] == 0])
            
            for delay in sorted(delay_stats.keys()):
                charges = delay_stats[delay]
                avg_charge = sum(charges) / len(charges)
                decay = baseline - avg_charge
                
                decay_color = Fore.GREEN if decay < 5 else Fore.YELLOW if decay < 10 else Fore.RED
                
                print(f"  {delay:<12} {avg_charge:>10.1f}% {decay_color}{decay:>10.1f}%{Style.RESET_ALL}")
        
        # 5. Save Results
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"partial_charge_analysis_{timestamp}.csv"
        
        with open(filename, 'w') as f:
            f.write("Address,Pattern,Duration,ReadDelay,ChargeLevel,Readback\n")
            for r in self.results:
                f.write(f"0x{r['addr']:08X},{r['pattern']},{r['duration']},"
                       f"{r['read_delay_ms']},{r['charge_level']:.1f},{r['readback']}\n")
        
        fancy_print(f"Detailed results saved to: {filename}", "success")
        
        # 6. Visual Summary
        print(f"\n{Fore.CYAN}{'═' * 80}")
        print(f"║{' TEST SUMMARY '.center(78)}║")
        print(f"{'═' * 80}{Style.RESET_ALL}")
        
        total_tests = len(self.results)
        vulnerable_count = len(vulnerable_cells)
        
        print(f"\n  Total measurements: {total_tests:,}")
        print(f"  Vulnerable conditions found: {vulnerable_count:,}")
        print(f"  Vulnerability rate: {(vulnerable_count/total_tests)*100:.2f}%")
        
        if vulnerable_cells:
            min_duration = min(c['duration'] for c in vulnerable_cells)
            print(f"\n  {Fore.YELLOW}⚡ Minimum cycles for partial charge: {min_duration}")
            print(f"  ⚡ Most vulnerable pattern: {max(set(c['pattern'] for c in vulnerable_cells), key=lambda p: sum(1 for c in vulnerable_cells if c['pattern'] == p))}")
            print(f"  ⚡ Addresses with partial charge: {len(set(c['addr'] for c in vulnerable_cells))}{Style.RESET_ALL}")

def main():
    try:
        # Initialize serial connection
        fancy_print("Initializing serial connection...", "info")
        ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)
        time.sleep(0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        fancy_print(f"Connected to {SERIAL_PORT} @ {BAUDRATE} baud", "success")
        
        # Check if DDR3 is initialized
        fancy_print("Checking DDR3 status...", "info")
        ser.write(b"?\r")
        time.sleep(0.1)
        response = ser.readline().decode("ascii", errors="ignore").strip()
        
        if response == "W":
            fancy_print("DDR3 still initializing, please wait...", "warning")
            while response != "R":
                time.sleep(1)
                ser.write(b"?\r")
                response = ser.readline().decode("ascii", errors="ignore").strip()
        
        fancy_print("DDR3 ready!", "success")
        
    except serial.SerialException as e:
        fancy_print(f"Failed to open serial port: {e}", "error")
        return 1
    
    # Create tester
    tester = PartialChargeTester(ser)
    
    # Run comprehensive test
    start_time = time.time()
    vulnerable_cells = tester.run_comprehensive_test(TEST_ADDRESSES[:10])  # Test first 10 addresses
    elapsed = time.time() - start_time
    
    # Final summary
    print(f"\n{Fore.GREEN}{'═' * 80}")
    print(f"║{' ⚡ PARTIAL CHARGE ANALYSIS COMPLETE ⚡ '.center(78)}║")
    print(f"{'═' * 80}{Style.RESET_ALL}")
    
    print(f"\nTotal runtime: {elapsed/60:.1f} minutes")
    print(f"Tests per second: {len(tester.results)/elapsed:.1f}")
    
    # Cleanup
    ser.close()
    
    # Exit animation
    print(f"\n{Fore.YELLOW}", end='')
    exit_msg = "⚡ Thank you for using Partial Charge Analyzer! ⚡"
    for i, char in enumerate(exit_msg):
        print(char, end='', flush=True)
        time.sleep(0.03)
    print(Style.RESET_ALL + "\n")
    
    return 0

if __name__ == "__main__":
    try:
        exit(main())
    except KeyboardInterrupt:
        clear_line()
        fancy_print("\nTest interrupted by user", "warning")
        exit(1)
