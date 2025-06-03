#!/usr/bin/env python3

import serial
import time
import random
import sys
import threading
from colorama import Fore, Back, Style, init
from datetime import datetime, timedelta

# Initialize colorama
init(autoreset=True)

# --- Configuration ---
SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.2

# Memory regions to test
MEMORY_REGIONS = [
    {"name": "Known Weak", "start": 0x00000000, "end": 0x00010000, "step": 0x1000},
]

# Test patterns for partial charge
TEST_PATTERNS = [
    {"name": "All Ones", "pattern": "FFFFFFFF", "description": "Maximum charge target"},
    {"name": "All Zeros", "pattern": "00000000", "description": "Minimum charge target"},
    {"name": "Checkerboard", "pattern": "AAAAAAAA", "description": "Adjacent cell interference"},
    {"name": "Inv Checkerboard", "pattern": "55555555", "description": "Inverse interference"},
]

# Partial write durations (in cycles)
PARTIAL_DURATIONS = [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20]

# Read delays after partial write (seconds)
READ_DELAYS = [0, 0.01, 0.05, 0.1, 0.5, 1.0]

# Write parameters (from working decay script)
NWRITES = 10
NVERIFY = 5

# Global variables for animation
animation_running = False
current_status = ""

# ASCII art
PARTIAL_CHARGE_ART = """
    ╔═══════════════════════════════════════╗
    ║      PARTIAL CHARGE WEAK CELL FINDER  ║
    ║              ⚡⚡⚡⚡⚡⚡⚡             ║
    ║         ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄            ║
    ║        ▐░░░░░▓▓▓▓▓░░░░░░░▌           ║
    ║        ▐░█▀▀▀▓▓▓▓▓▀▀▀▀█░▌           ║
    ║        ▐░▌  PARTIAL   ▐░▌           ║
    ║        ▐░█▄▄▄▓▓▓▓▓▄▄▄▄█░▌           ║
    ║        ▐░░░░░▓▓▓▓▓░░░░░░░▌           ║
    ║         ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀            ║
    ╚═══════════════════════════════════════╝
"""

ANIMATIONS = {
    'write': ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'],
    'read': ['◐', '◓', '◑', '◒'],
    'partial': ['⚡', '🔌', '⚡', '💡', '⚡', '🔋'],
    'wait': ['⏳', '⌛', '⏳', '⌛'],
}

def clear_line():
    """Clear the current line"""
    print('\r' + ' ' * 80 + '\r', end='', flush=True)

def animate_spinner(stop_event, animation_type='write'):
    """Animated spinner that runs in a separate thread"""
    frames = ANIMATIONS.get(animation_type, ANIMATIONS['write'])
    idx = 0
    while not stop_event.is_set():
        frame = frames[idx % len(frames)]
        status = f"{frame} {current_status}"
        print(f"\r{status}", end='', flush=True)
        idx += 1
        time.sleep(0.1)
    clear_line()

def progress_bar(current, total, width=50, title="Progress"):
    """Display a colored progress bar"""
    percentage = current / total if total > 0 else 0
    filled = int(width * percentage)
    
    # Color based on percentage
    if percentage < 0.33:
        color = Fore.RED
    elif percentage < 0.66:
        color = Fore.YELLOW
    else:
        color = Fore.GREEN
    
    bar = f"{color}{'█' * filled}{Fore.WHITE}{'░' * (width - filled)}"
    
    print(f"\r{title}: [{bar}] {percentage*100:.1f}% ({current}/{total})", end='', flush=True)

def fancy_print(message, msg_type="info"):
    """Print messages with fancy formatting"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    
    if msg_type == "header":
        print(f"\n{Fore.CYAN}{'═' * 60}")
        print(f"{Fore.CYAN}║{Style.BRIGHT} {message.center(56)} {Style.NORMAL}{Fore.CYAN}║")
        print(f"{Fore.CYAN}{'═' * 60}{Style.RESET_ALL}")
    elif msg_type == "success":
        print(f"{Fore.GREEN}[{timestamp}] ✓ {message}{Style.RESET_ALL}")
    elif msg_type == "error":
        print(f"{Fore.RED}[{timestamp}] ✗ {message}{Style.RESET_ALL}")
    elif msg_type == "warning":
        print(f"{Fore.YELLOW}[{timestamp}] ⚠ {message}{Style.RESET_ALL}")
    elif msg_type == "found":
        print(f"{Fore.MAGENTA}[{timestamp}] 🎯 {message}{Style.RESET_ALL}")
    elif msg_type == "partial":
        print(f"{Fore.YELLOW}[{timestamp}] ⚡ {message}{Style.RESET_ALL}")
    else:
        print(f"{Fore.BLUE}[{timestamp}] ℹ {message}{Style.RESET_ALL}")

class PartialChargeTester:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.weak_cells = []
        self.total_tests = 0
        self.tests_completed = 0
        
    def write_cmd(self, addr, data):
        """Standard write command (from working decay script)"""
        cmd = f"W{addr:08X} {data}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.01)
    
    def partial_write_cmd(self, addr, data, duration):
        """Partial write command: PAAAAAAAA DDDDDDDD TTTT"""
        cmd = f"P{addr:08X} {data} {duration:04X}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.02)
    
    def read_cmd(self, addr):
        """Read command (from working decay script)"""
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
        
        # Extract hex value from response (handle corrupted data)
        if response:
            # Try to extract 8 hex characters
            hex_chars = ''.join(c for c in response[-8:] if c in '0123456789ABCDEFabcdef')
            if len(hex_chars) == 8:
                return hex_chars.upper()
        
        return None
    
    def hamming_distance(self, hex1, hex2):
        """Calculate bit differences"""
        try:
            v1 = int(hex1, 16)
            v2 = int(hex2, 16)
            return bin(v1 ^ v2).count('1')
        except:
            return 32
    
    def calculate_charge_level(self, expected, actual):
        """Calculate charge level as percentage"""
        try:
            exp_val = int(expected, 16)
            act_val = int(actual, 16)
            
            # Count matching bits
            xor = exp_val ^ act_val
            matching_bits = 32 - bin(xor).count('1')
            
            return (matching_bits / 32) * 100
        except:
            return 0
    
    def test_partial_charge_pattern(self, addresses, pattern_info, duration, read_delay):
        """Test partial charge with specific pattern and duration"""
        pattern = pattern_info['pattern']
        pattern_name = pattern_info['name']
        
        # Prepare opposite pattern
        opposite = "FFFFFFFF" if pattern == "00000000" else "00000000"
        
        # Write opposite pattern to all addresses
        global current_status
        current_status = f"Writing opposite pattern to {len(addresses)} addresses"
        
        stop_event = threading.Event()
        animator = threading.Thread(target=animate_spinner, args=(stop_event, 'write'))
        animator.start()
        
        try:
            for addr in addresses:
                for _ in range(NWRITES):
                    self.write_cmd(addr, opposite)
        finally:
            stop_event.set()
            animator.join()
        
        # Verify writes
        verified = []
        current_status = f"Verifying opposite pattern"
        
        stop_event = threading.Event()
        animator = threading.Thread(target=animate_spinner, args=(stop_event, 'read'))
        animator.start()
        
        try:
            for addr in addresses:
                success = False
                for _ in range(NVERIFY):
                    data = self.read_cmd(addr)
                    if data and data == opposite:
                        success = True
                        break
                if success:
                    verified.append(addr)
        finally:
            stop_event.set()
            animator.join()
        
        if not verified:
            return []
        
        # Perform partial writes
        current_status = f"Partial write: {pattern_name} for {duration} cycles"
        
        stop_event = threading.Event()
        animator = threading.Thread(target=animate_spinner, args=(stop_event, 'partial'))
        animator.start()
        
        try:
            for addr in verified:
                # Multiple partial writes to ensure effect
                for _ in range(3):
                    self.partial_write_cmd(addr, pattern, duration)
                    time.sleep(0.01)
        finally:
            stop_event.set()
            animator.join()
        
        # Wait if specified
        if read_delay > 0:
            fancy_print(f"Waiting {read_delay}s after partial write", "info")
            time.sleep(read_delay)
        
        # Read back and analyze
        weak_found = []
        current_status = f"Reading back after partial write"
        
        stop_event = threading.Event()
        animator = threading.Thread(target=animate_spinner, args=(stop_event, 'read'))
        animator.start()
        
        try:
            for addr in verified:
                # Multiple reads to get stable value
                read_values = []
                for _ in range(3):
                    data = self.read_cmd(addr)
                    if data:
                        read_values.append(data)
                
                if read_values:
                    # Use most common value
                    final_value = max(set(read_values), key=read_values.count)
                    
                    charge_level = self.calculate_charge_level(pattern, final_value)
                    hamming = self.hamming_distance(pattern, final_value)
                    
                    # Check if partial charge achieved (not fully charged/discharged)
                    if 10 < charge_level < 90 and hamming > 0:
                        weak_found.append({
                            'addr': addr,
                            'expected': pattern,
                            'readback': final_value,
                            'charge_level': charge_level,
                            'flipped_bits': hamming,
                            'pattern_name': pattern_name,
                            'duration': duration,
                            'read_delay': read_delay
                        })
        finally:
            stop_event.set()
            animator.join()
        
        return weak_found
    
    def run_partial_charge_test(self):
        """Run partial charge detection test"""
        # Display header
        print(f"{Fore.CYAN}{PARTIAL_CHARGE_ART}{Style.RESET_ALL}")
        fancy_print("STARTING PARTIAL CHARGE DETECTION", "header")
        
        # Calculate total tests
        total_addresses = sum(len(range(r['start'], r['end'], r['step'])) for r in MEMORY_REGIONS)
        self.total_tests = len(TEST_PATTERNS) * len(PARTIAL_DURATIONS) * len(READ_DELAYS)
        
        fancy_print(f"Memory regions: {len(MEMORY_REGIONS)}", "info")
        fancy_print(f"Test patterns: {len(TEST_PATTERNS)}", "info")
        fancy_print(f"Partial durations: {PARTIAL_DURATIONS}", "info")
        fancy_print(f"Read delays: {READ_DELAYS}", "info")
        fancy_print(f"Total configurations: {self.total_tests}", "info")
        
        test_number = 0
        
        # Main test loop
        for pattern_info in TEST_PATTERNS:
            for duration in PARTIAL_DURATIONS:
                for read_delay in READ_DELAYS:
                    test_number += 1
                    
                    fancy_print(f"TEST {test_number}/{self.total_tests}", "header")
                    fancy_print(f"Pattern: {pattern_info['name']} ({pattern_info['description']})", "info")
                    fancy_print(f"Partial write duration: {duration} cycles", "partial")
                    fancy_print(f"Read delay: {read_delay} seconds", "info")
                    
                    # Collect addresses from all regions
                    all_addresses = []
                    for region in MEMORY_REGIONS:
                        region_addrs = list(range(region['start'], region['end'], region['step']))
                        all_addresses.extend(region_addrs)
                        fancy_print(f"Testing {region['name']}: {len(region_addrs)} addresses", "info")
                    
                    # Run the test
                    weak = self.test_partial_charge_pattern(all_addresses, pattern_info, duration, read_delay)
                    
                    if weak:
                        fancy_print(f"Found {len(weak)} cells with partial charge! ⚡", "found")
                        self.weak_cells.extend(weak)
                        
                        # Show some examples
                        for cell in weak[:3]:
                            print(f"    → 0x{cell['addr']:08X}: {cell['expected']} → {cell['readback']} "
                                  f"(Charge: {cell['charge_level']:.1f}%, {cell['flipped_bits']} bits different)")
                    else:
                        fancy_print("No partial charges detected", "warning")
                    
                    # Update progress
                    progress = (test_number / self.total_tests) * 100
                    progress_bar(test_number, self.total_tests, title="Overall Progress")
                    print()  # New line after progress bar
        
        return self.weak_cells

def main():
    try:
        # Open serial connection
        fancy_print("Initializing serial connection...", "info")
        ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)
        time.sleep(0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        fancy_print(f"Connected to {SERIAL_PORT} @ {BAUDRATE} baud", "success")
        
    except serial.SerialException as e:
        fancy_print(f"Failed to open serial port: {e}", "error")
        return 1
    
    # Create tester instance
    tester = PartialChargeTester(ser)
    
    # Run partial charge test
    start_time = time.time()
    weak_cells = tester.run_partial_charge_test()
    elapsed = time.time() - start_time
    
    # Display final results
    fancy_print("TEST COMPLETE!", "header")
    fancy_print(f"Total runtime: {elapsed/60:.1f} minutes", "info")
    fancy_print(f"Total cells with partial charge: {len(weak_cells)}", "success" if weak_cells else "warning")
    
    if weak_cells:
        # Find the most responsive cells
        print(f"\n{Fore.MAGENTA}Cells Most Responsive to Partial Writes:{Style.RESET_ALL}")
        print("─" * 70)
        
        # Sort by charge level (looking for 40-60% range as ideal)
        ideal_partial = sorted(weak_cells, 
                             key=lambda x: abs(x['charge_level'] - 50))[:10]
        
        for i, cell in enumerate(ideal_partial, 1):
            charge_bar = '█' * int(cell['charge_level'] / 10) + '░' * (10 - int(cell['charge_level'] / 10))
            print(f"{i:2d}. 0x{cell['addr']:08X} - Duration: {cell['duration']:2d} cycles - "
                  f"Charge: [{charge_bar}] {cell['charge_level']:.1f}% - "
                  f"Pattern: {cell['pattern_name']}")
        
        # Save results
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"partial_charge_results_{timestamp}.csv"
        
        with open(filename, 'w') as f:
            f.write("Address,Pattern,Duration,ReadDelay,Expected,Readback,ChargeLevel,FlippedBits\n")
            for cell in weak_cells:
                f.write(f"0x{cell['addr']:08X},{cell['pattern_name']},{cell['duration']},"
                       f"{cell['read_delay']},{cell['expected']},{cell['readback']},"
                       f"{cell['charge_level']:.1f},{cell['flipped_bits']}\n")
        
        fancy_print(f"Results saved to {filename}", "success")
        
        # Generate optimal parameters
        print(f"\n{Fore.CYAN}Optimal Parameters for Partial Charge Attack:{Style.RESET_ALL}")
        durations = [cell['duration'] for cell in weak_cells]
        if durations:
            optimal_duration = min(durations)
            print(f"Minimum duration for partial charge: {optimal_duration} cycles")
            
            vulnerable_addrs = list(set(cell['addr'] for cell in weak_cells if cell['duration'] <= optimal_duration + 2))
            print(f"\nMost vulnerable addresses:")
            for addr in vulnerable_addrs[:5]:
                print(f"  - 0x{addr:08X}")
    
    else:
        fancy_print("No partial charges detected!", "warning")
        print("\nSuggestions:")
        print("1. The partial write command may need different timing")
        print("2. Try testing known weak addresses from decay test")
        print("3. Increase temperature to make cells more vulnerable")
        print("4. Try different duration ranges")
    
    # Cleanup
    ser.close()
    
    # Final animation
    print(f"\n{Fore.GREEN}", end='')
    for char in "⚡ Partial Charge Test Complete! ⚡":
        print(char, end='', flush=True)
        time.sleep(0.05)
    print(Style.RESET_ALL)
    
    return 0

if __name__ == "__main__":
    try:
        exit(main())
    except KeyboardInterrupt:
        clear_line()
        fancy_print("\nTest interrupted by user", "warning")
        exit(1)
