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

# Memory search parameters
MEMORY_REGIONS = [
    {"name": "Low Memory", "start": 0x00000000, "end": 0x00100000, "step": 0x1000},
    {"name": "Bank Boundaries", "start": 0x00100000, "end": 0x01000000, "step": 0x8000},
    {"name": "High Memory", "start": 0x01000000, "end": 0x02000000, "step": 0x10000},
]

# Test patterns - different patterns stress cells differently
TEST_PATTERNS = [
    {"name": "All Ones", "pattern": "FFFFFFFF", "description": "Maximum charge stress"},
    {"name": "All Zeros", "pattern": "00000000", "description": "Minimum charge stress"},
    {"name": "Checkerboard", "pattern": "AAAAAAAA", "description": "Adjacent cell interference"},
    {"name": "Inv Checkerboard", "pattern": "55555555", "description": "Inverse interference"},
    {"name": "Walking Ones", "pattern": "80000001", "description": "Isolated high bits"},
    {"name": "Row Stripe", "pattern": "FF00FF00", "description": "Row-wise stress"},
    {"name": "Col Stripe", "pattern": "F0F0F0F0", "description": "Column-wise stress"},
    {"name": "Random 1", "pattern": "DEADBEEF", "description": "Random pattern 1"},
    {"name": "Random 2", "pattern": "CAFEBABE", "description": "Random pattern 2"},
]

# Decay times to test (seconds)
DECAY_TIMES = [30, 60, 120, 300, 600]

# Write parameters
NWRITES = 10
NVERIFY = 5

# Global variables for animation
animation_running = False
current_status = ""
progress_value = 0
progress_max = 100

# ASCII art and animations
DRAM_ART = """
    ╔═══════════════════════════════════════╗
    ║         DDR3 WEAK CELL FINDER         ║
    ║              ▄▄▄▄▄▄▄▄▄▄▄              ║
    ║             ▐░░░░░░░░░░░▌             ║
    ║             ▐░█▀▀▀▀▀▀▀█░▌             ║
    ║             ▐░▌ DRAM  ▐░▌             ║
    ║             ▐░█▄▄▄▄▄▄▄█░▌             ║
    ║             ▐░░░░░░░░░░░▌             ║
    ║              ▀▀▀▀▀▀▀▀▀▀▀              ║
    ╚═══════════════════════════════════════╝
"""

ANIMATIONS = {
    'write': ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'],
    'read': ['◐', '◓', '◑', '◒'],
    'wait': ['🕐', '🕑', '🕒', '🕓', '🕔', '🕕', '🕖', '🕗', '🕘', '🕙', '🕚', '🕛'],
    'scan': ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█', '▇', '▆', '▅', '▄', '▃', '▂'],
    'found': ['💥', '✨', '🌟', '⚡', '💫', '✨'],
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
    else:
        print(f"{Fore.BLUE}[{timestamp}] ℹ {message}{Style.RESET_ALL}")

def display_weak_cell_map(weak_cells, max_display=20):
    """Display weak cells as a visual map"""
    if not weak_cells:
        return
    
    print(f"\n{Fore.CYAN}╔══════════════════════════════════════════════════════════╗")
    print(f"║                    WEAK CELL MAP                         ║")
    print(f"╚══════════════════════════════════════════════════════════╝{Style.RESET_ALL}\n")
    
    # Sort by address
    sorted_cells = sorted(weak_cells, key=lambda x: x['addr'])[:max_display]
    
    for cell in sorted_cells:
        addr = cell['addr']
        flips = cell['flipped_bits']
        pattern = cell['pattern_name']
        decay_time = cell['decay_time']
        
        # Create a visual representation of bit flips
        flip_visual = ""
        if flips <= 2:
            flip_visual = Fore.YELLOW + "▪" * flips
        elif flips <= 8:
            flip_visual = Fore.RED + "▪" * min(flips, 8)
        else:
            flip_visual = Fore.MAGENTA + "█" * min(flips // 4, 8)
        
        print(f"  0x{addr:08X} │ {flip_visual:<32} │ {flips:2d} bits │ {pattern:<15} │ {decay_time}s")

class DDR3Tester:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.weak_cells = []
        self.total_tests = 0
        self.tests_completed = 0
        
    def write_cmd(self, addr, data):
        cmd = f"W{addr:08X} {data}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.01)
    
    def read_cmd(self, addr):
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
        
        return response[-8:].upper() if response and len(response) >= 8 else None
    
    def hamming_distance(self, hex1, hex2):
        try:
            v1 = int(hex1, 16)
            v2 = int(hex2, 16)
            return bin(v1 ^ v2).count('1')
        except:
            return 32
    
    def test_pattern_at_addresses(self, addresses, pattern_info, decay_time):
        """Test a specific pattern at given addresses with decay time"""
        pattern = pattern_info['pattern']
        pattern_name = pattern_info['name']
        
        # Write phase with animation
        stop_event = threading.Event()
        global current_status
        current_status = f"Writing {pattern_name} to {len(addresses)} addresses"
        
        animator = threading.Thread(target=animate_spinner, args=(stop_event, 'write'))
        animator.start()
        
        try:
            for addr in addresses:
                for _ in range(NWRITES):
                    self.write_cmd(addr, pattern)
        finally:
            stop_event.set()
            animator.join()
        
        # Verify phase
        verified = []
        current_status = f"Verifying {pattern_name} writes"
        
        stop_event = threading.Event()
        animator = threading.Thread(target=animate_spinner, args=(stop_event, 'read'))
        animator.start()
        
        try:
            for addr in addresses:
                success = False
                for _ in range(NVERIFY):
                    data = self.read_cmd(addr)
                    if data == pattern:
                        success = True
                        break
                if success:
                    verified.append(addr)
        finally:
            stop_event.set()
            animator.join()
        
        if not verified:
            return []
        
        # Decay wait phase with fancy countdown
        fancy_print(f"Waiting {decay_time}s for decay (Pattern: {pattern_name})", "info")
        
        start_time = time.time()
        while time.time() - start_time < decay_time:
            elapsed = int(time.time() - start_time)
            remaining = decay_time - elapsed
            
            # Create a visual countdown
            bar_length = 40
            filled = int(bar_length * elapsed / decay_time)
            
            # Animate the waiting bar with colors
            if remaining > decay_time * 0.66:
                bar_color = Fore.GREEN
            elif remaining > decay_time * 0.33:
                bar_color = Fore.YELLOW
            else:
                bar_color = Fore.RED
            
            bar = f"{bar_color}{'█' * filled}{Fore.WHITE}{'░' * (bar_length - filled)}"
            
            # Add clock animation
            clock_idx = int(elapsed * 2) % len(ANIMATIONS['wait'])
            clock = ANIMATIONS['wait'][clock_idx]
            
            print(f"\r{clock} Decay Timer: [{bar}] {remaining}s remaining   ", end='', flush=True)
            time.sleep(0.5)
        
        clear_line()
        
        # Read back phase
        weak_found = []
        current_status = f"Reading back {pattern_name}"
        
        stop_event = threading.Event()
        animator = threading.Thread(target=animate_spinner, args=(stop_event, 'scan'))
        animator.start()
        
        try:
            for addr in verified:
                data = self.read_cmd(addr)
                if data and data != pattern:
                    hamming = self.hamming_distance(pattern, data)
                    if hamming > 0:
                        weak_found.append({
                            'addr': addr,
                            'expected': pattern,
                            'readback': data,
                            'flipped_bits': hamming,
                            'pattern_name': pattern_name,
                            'decay_time': decay_time
                        })
        finally:
            stop_event.set()
            animator.join()
        
        return weak_found
    
    def run_comprehensive_test(self):
        """Run comprehensive weak cell detection"""
        # Display header
        print(f"{Fore.CYAN}{DRAM_ART}{Style.RESET_ALL}")
        fancy_print("STARTING COMPREHENSIVE WEAK CELL DETECTION", "header")
        
        # Calculate total tests
        total_addresses = sum(len(range(r['start'], r['end'], r['step'])) for r in MEMORY_REGIONS)
        self.total_tests = len(TEST_PATTERNS) * len(DECAY_TIMES)
        
        fancy_print(f"Memory regions: {len(MEMORY_REGIONS)}", "info")
        fancy_print(f"Test patterns: {len(TEST_PATTERNS)}", "info")
        fancy_print(f"Decay times: {DECAY_TIMES}", "info")
        fancy_print(f"Total address count: {total_addresses}", "info")
        
        test_number = 0
        
        # Main test loop
        for pattern_info in TEST_PATTERNS:
            for decay_time in DECAY_TIMES:
                test_number += 1
                
                fancy_print(f"TEST {test_number}/{self.total_tests}", "header")
                fancy_print(f"Pattern: {pattern_info['name']} ({pattern_info['description']})", "info")
                fancy_print(f"Decay time: {decay_time} seconds", "info")
                
                # Collect addresses from all regions
                all_addresses = []
                for region in MEMORY_REGIONS:
                    region_addrs = list(range(region['start'], region['end'], region['step']))
                    all_addresses.extend(region_addrs)
                    fancy_print(f"Testing {region['name']}: {len(region_addrs)} addresses", "info")
                
                # Run the test
                weak = self.test_pattern_at_addresses(all_addresses, pattern_info, decay_time)
                
                if weak:
                    fancy_print(f"Found {len(weak)} weak cells! 🎯", "found")
                    self.weak_cells.extend(weak)
                    
                    # Show some examples
                    for cell in weak[:3]:
                        print(f"    → 0x{cell['addr']:08X}: {cell['expected']} → {cell['readback']} ({cell['flipped_bits']} bits)")
                else:
                    fancy_print("No weak cells found in this test", "warning")
                
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
    tester = DDR3Tester(ser)
    
    # Run comprehensive test
    start_time = time.time()
    weak_cells = tester.run_comprehensive_test()
    elapsed = time.time() - start_time
    
    # Display final results
    fancy_print("TEST COMPLETE!", "header")
    fancy_print(f"Total runtime: {elapsed/60:.1f} minutes", "info")
    fancy_print(f"Total weak cells found: {len(weak_cells)}", "success" if weak_cells else "warning")
    
    if weak_cells:
        # Display weak cell map
        display_weak_cell_map(weak_cells)
        
        # Find the weakest cells
        weakest = sorted(weak_cells, key=lambda x: x['flipped_bits'], reverse=True)[:10]
        
        print(f"\n{Fore.MAGENTA}Top 10 Weakest Cells:{Style.RESET_ALL}")
        print("─" * 70)
        for i, cell in enumerate(weakest, 1):
            print(f"{i:2d}. 0x{cell['addr']:08X} - {cell['flipped_bits']} bits flipped "
                  f"({cell['pattern_name']}, {cell['decay_time']}s)")
        
        # Save results
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"weak_cells_comprehensive_{timestamp}.csv"
        
        with open(filename, 'w') as f:
            f.write("Address,Pattern,PatternName,Expected,Readback,FlippedBits,DecayTime\n")
            for cell in weak_cells:
                f.write(f"0x{cell['addr']:08X},{cell['pattern_name']},{cell['pattern_name']},"
                       f"{cell['expected']},{cell['readback']},{cell['flipped_bits']},{cell['decay_time']}\n")
        
        fancy_print(f"Results saved to {filename}", "success")
        
        # Generate address list for further testing
        unique_addrs = list(set(cell['addr'] for cell in weak_cells))[:20]
        
        print(f"\n{Fore.CYAN}Suggested addresses for decay testing:{Style.RESET_ALL}")
        print("ADDRESSES = [")
        for addr in unique_addrs:
            print(f"    0x{addr:08X},")
        print("]")
        
    else:
        fancy_print("No weak cells found!", "warning")
        print("\nSuggestions:")
        print("1. Heat the DRAM module to 70-85°C")
        print("2. Increase decay times in DECAY_TIMES")
        print("3. Add more test patterns")
        print("4. Test different memory regions")
    
    # Cleanup
    ser.close()
    
    # Final animation
    print(f"\n{Fore.GREEN}", end='')
    for char in "✨ Test Complete! ✨":
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
