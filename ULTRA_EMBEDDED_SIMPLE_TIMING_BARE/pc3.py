#!/usr/bin/env python3

import serial
import time
import random
import sys
import threading
import json
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from colorama import Fore, Back, Style, init
from datetime import datetime, timedelta
from collections import defaultdict
import pandas as pd
from pathlib import Path
import pickle

# Initialize colorama
init(autoreset=True)

# --- Configuration ---
SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.3

# Memory search parameters - aligned to 128-bit boundaries
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

# Quick test patterns for partial charge screening
QUICK_TEST_PATTERNS = [
    {"name": "Checkerboard", "pattern": "AAAAAAAA", "description": "Adjacent cell interference"},
    {"name": "All Ones", "pattern": "FFFFFFFF", "description": "Maximum charge stress"},
    {"name": "Row Stripe", "pattern": "FF00FF00", "description": "Row-wise stress"},
]

# Comprehensive decay times for neuromorphic characterization
DECAY_TIMES = [10, 30, 60, 120, 180, 300, 600, 900, 1200]  # Up to 20 minutes

# Quick decay times for partial charge testing
QUICK_DECAY_TIMES = [5, 10, 20, 30]  # Just up to 30 seconds

# Partial write configurations to test
PARTIAL_WRITE_CONFIGS = [
    {"cycles": 1, "name": "Ultra-weak", "description": "12.5% charge"},
    {"cycles": 2, "name": "Very weak", "description": "25% charge"},
    {"cycles": 3, "name": "Weak", "description": "37.5% charge"},
    {"cycles": 4, "name": "Half", "description": "50% charge"},
    {"cycles": 5, "name": "Moderate", "description": "62.5% charge"},
    {"cycles": 6, "name": "Strong", "description": "75% charge"},
    {"cycles": 7, "name": "Very strong", "description": "87.5% charge"},
    {"cycles": 8, "name": "Full", "description": "100% charge (reference)"},
]

# Fallback configs if gradient test fails
QUICK_PARTIAL_CONFIGS_FALLBACK = [
    {"cycles": 2, "name": "Weak", "description": "25% charge"},
    {"cycles": 4, "name": "Half", "description": "50% charge"},
    {"cycles": 8, "name": "Full", "description": "100% charge (reference)"},
]

# Write parameters
NWRITES = 10
NVERIFY = 5

# Global variables for animation
animation_running = False
current_status = ""
progress_value = 0
progress_max = 100

# ASCII art and animations
NEURO_DRAM_ART = """
    ╔══════════════════════════════════════════════════════════════════╗
    ║             NEUROMORPHIC DRAM CELL CHARACTERIZATION              ║
    ║                     ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄                      ║
    ║                   ▐░░░ NEURAL DRAM ░░░▌                     ║
    ║                   ▐░ ╔══╦══╦══╦══╗ ░▌                     ║
    ║                   ▐░ ║◉◉║◉◉║◉◉║◉◉║ ░▌                     ║
    ║                   ▐░ ╠══╬══╬══╬══╣ ░▌                     ║
    ║                   ▐░ ║◉◉║◉◉║◉◉║◉◉║ ░▌                     ║
    ║                   ▐░ ╚══╩══╩══╩══╝ ░▌                     ║
    ║                      ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀                     ║
    ║         "Leveraging Natural Decay for Computation"             ║
    ╚══════════════════════════════════════════════════════════════════╝
"""

ANIMATIONS = {
    'write': ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'],
    'read': ['◐', '◓', '◑', '◒'],
    'wait': ['🕐', '🕑', '🕒', '🕓', '🕔', '🕕', '🕖', '🕗', '🕘', '🕙', '🕚', '🕛'],
    'scan': [' ', '▂', '▃', '▄', '▅', '▆', '▇', '█', '▇', '▆', '▅', '▄', '▃', '▂'],
    'found': ['💥', '✨', '🌟', '⚡', '💫', '✨'],
    'neural': ['🧠', '⚡', '🧠', '💫', '🧠', '✨'],
    'charge': ['⚡', '💫', '✨', '🌟', '⚡', '💫'],
}

def clear_line():
    """Clear the current line"""
    print('\r' + ' ' * 100 + '\r', end='', flush=True)

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

def progress_bar(current, total, width=50, title="Progress", show_eta=True):
    """Display a colored progress bar with ETA"""
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

    # Calculate ETA
    eta_str = ""
    if show_eta and hasattr(progress_bar, 'start_time') and current > 0:
        elapsed = time.time() - progress_bar.start_time
        rate = current / elapsed
        remaining = (total - current) / rate if rate > 0 else 0
        eta = timedelta(seconds=int(remaining))
        eta_str = f" ETA: {eta}"

    print(f"\r{title}: [{bar}] {percentage*100:.1f}% ({current}/{total}){eta_str}", end='', flush=True)

def fancy_print(message, msg_type="info"):
    """Print messages with fancy formatting"""
    timestamp = datetime.now().strftime("%H:%M:%S")

    if msg_type == "header":
        print(f"\n{Fore.CYAN}{'═' * 80}")
        print(f"║{Style.BRIGHT} {message.center(76)} {Style.NORMAL}{Fore.CYAN}║")
        print(f"{'═' * 80}{Style.RESET_ALL}")
    elif msg_type == "success":
        print(f"{Fore.GREEN}[{timestamp}] ✓ {message}{Style.RESET_ALL}")
    elif msg_type == "error":
        print(f"{Fore.RED}[{timestamp}] ✗ {message}{Style.RESET_ALL}")
    elif msg_type == "warning":
        print(f"{Fore.YELLOW}[{timestamp}] ⚠ {message}{Style.RESET_ALL}")
    elif msg_type == "found":
        print(f"{Fore.MAGENTA}[{timestamp}] 🎯 {message}{Style.RESET_ALL}")
    elif msg_type == "neural":
        print(f"{Fore.BLUE}{Style.BRIGHT}[{timestamp}] 🧠 {message}{Style.RESET_ALL}")
    elif msg_type == "charge":
        print(f"{Fore.YELLOW}{Style.BRIGHT}[{timestamp}] ⚡ {message}{Style.RESET_ALL}")
    else:
        print(f"{Fore.BLUE}[{timestamp}] ℹ {message}{Style.RESET_ALL}")

def display_cell_characteristics(cell_data):
    """Display advanced cell characteristics visualization"""
    print(f"\n{Fore.CYAN}╔══════════════════════════════════════════════════════════════════════════════╗")
    print(f"║                         NEUROMORPHIC CELL CHARACTERISTICS                      ║")
    print(f"╚══════════════════════════════════════════════════════════════════════════════╝{Style.RESET_ALL}\n")

    # Group cells by behavior
    fast_decay = [c for c in cell_data if c.get('decay_class') == 'fast']
    slow_decay = [c for c in cell_data if c.get('decay_class') == 'slow']
    partial_sensitive = [c for c in cell_data if c.get('partial_sensitive', False)]

    print(f"  {Fore.RED}Fast Decay Cells (Excitatory Neurons): {len(fast_decay)}")
    print(f"  {Fore.BLUE}Slow Decay Cells (Memory Units): {len(slow_decay)}")
    print(f"  {Fore.YELLOW}Partial-Charge Sensitive (Tunable Synapses): {len(partial_sensitive)}")
    print(f"  {Fore.GREEN}Total Characterized: {len(cell_data)}{Style.RESET_ALL}\n")

class NeuromorphicDRAMAnalyzer:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.cell_profiles = {}
        self.weak_cells = []
        self.partial_sensitive_cells = []
        self.partial_write_results = defaultdict(list)
        self.decay_curves = defaultdict(list)
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.results_dir = Path(f"neuromorphic_dram_{self.session_id}")
        self.results_dir.mkdir(exist_ok=True)
        self.quick_partial_configs = QUICK_PARTIAL_CONFIGS_FALLBACK

        self.initialize_system()

    def initialize_system(self):
        """Initialize DDR3 system"""
        fancy_print("Initializing DDR3 Controller for Neuromorphic Analysis...", "neural")

        # Wait for DDR3 to be ready
        max_retries = 20
        for retry in range(max_retries):
            try:
                self.ser.write(b"?\r")
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

                if response and 'R' in response:
                    fancy_print("DDR3 Controller Ready - Neural Analysis Mode Active!", "success")
                    break
                elif response and 'W' in response:
                    fancy_print(f"DDR3 initializing... ({retry+1}/{max_retries})", "warning")
                    time.sleep(1.0)

            except Exception as e:
                fancy_print(f"Error: {e}", "error")
                time.sleep(0.5)

        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()

    ### ================================================================================= ###
    ### FIX: Restoring the missing configure_timing and configure_timing_raw methods.     ###
    ### ================================================================================= ###
    def configure_timing(self, twr=0, tras=0, burst_len=0, skip_refresh=0):
        """Configure DDR3 timing parameters"""
        config_value = (skip_refresh << 20) | (burst_len << 16) | (tras << 8) | twr
        cmd = f"T{config_value:08X}\r"  # Use 'T' command for timing config
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.1)
        
        # Read response to confirm
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
        
        # This check was removed from printing every time to reduce clutter in the original script
        # if "T:" in response:
        #     fancy_print(f"Timing configured: {response}", "success",)
        
        self.ser.reset_input_buffer()
        
    def configure_timing_raw(self, config_value):
        """Configure DDR3 timing with raw value"""
        cmd = f"T{config_value:08X}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.1)
        
        # Read response to confirm
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
        
        if "T:" in response:
            fancy_print(f"Timing configured: {response}", "success")
        
        self.ser.reset_input_buffer()
        
    def burst_length_gradient_test(self):
        """Test different burst lengths to find the minimum working configuration"""
        fancy_print("BURST LENGTH GRADIENT TEST - Finding the sweet spot", "charge")
        
        test_addr = 0x00001000  # Use a known address
        test_pattern = "AAAAAAAA"
        
        # Test burst lengths from 1 to 8
        results = []
        
        print(f"\n{Fore.CYAN}Testing burst lengths 1-8 cycles:{Style.RESET_ALL}")
        print(f"Pattern: {test_pattern}")
        print(f"Address: 0x{test_addr:08X}\n")
        
        for burst_len in range(1, 9):
            config_value = burst_len << 16
            
            print(f"Burst length {burst_len}: ", end='', flush=True)
            
            # Configure timing
            self.configure_timing(burst_len=burst_len)
            time.sleep(0.1)
            
            # Write multiple times
            for _ in range(10):
                self.write_cmd(test_addr, test_pattern)
                time.sleep(0.001)
            
            time.sleep(0.1)
            
            # Read back
            read_data = self.read_cmd(test_addr)
            
            if read_data:
                hamming = self.hamming_distance(test_pattern, read_data)
                
                # Color code the result
                if hamming == 0:
                    status = f"{Fore.GREEN}PERFECT{Style.RESET_ALL}"
                elif hamming < 8:
                    status = f"{Fore.YELLOW}GOOD ({hamming} errors){Style.RESET_ALL}"
                elif hamming < 16:
                    status = f"{Fore.MAGENTA}WEAK ({hamming} errors){Style.RESET_ALL}"
                else:
                    status = f"{Fore.RED}FAILED ({hamming} errors){Style.RESET_ALL}"
                
                print(f"Read: {read_data} - {status}")
                
                results.append({
                    'burst_len': burst_len,
                    'read_data': read_data,
                    'errors': hamming,
                    'working': hamming < 8 # A working burst has few errors
                })
            else:
                print(f"{Fore.RED}NO READ!{Style.RESET_ALL}")
                results.append({
                    'burst_len': burst_len,
                    'read_data': None,
                    'errors': 32,
                    'working': False
                })
        
        # Reset timing
        self.configure_timing(burst_len=0)
        
        # Analysis
        print(f"\n{Fore.CYAN}{'='*60}")
        print("BURST LENGTH ANALYSIS")
        print(f"{'='*60}{Style.RESET_ALL}\n")
        
        working_bursts = [r for r in results if r['working']]
        
        if working_bursts:
            min_working = min(r['burst_len'] for r in working_bursts)
            print(f"{Fore.GREEN}Minimum working burst length: {min_working} cycles{Style.RESET_ALL}")
            
            # Show gradient
            print(f"\nError gradient:")
            for r in results:
                bar_length = 20 - r['errors'] // 2
                bar = '█' * max(0, bar_length)
                print(f"  Burst {r['burst_len']}: {bar} ({r['errors']} errors)")
            
            # Suggest testing range
            if min_working > 1:
                print(f"\n{Fore.YELLOW}Suggested partial charge testing:")
                print(f"  • Weak charge: {min_working} cycles")
                print(f"  • Medium charge: {min_working + 2} cycles")
                print(f"  • Strong charge: {min_working + 4} cycles")
                print(f"  • Full charge: 8 cycles{Style.RESET_ALL}")
        else:
            print(f"{Fore.RED}NO BURST LENGTHS WORKED!{Style.RESET_ALL}")
        
        return results

    def test_charge_decay_relationship(self):
        """Test how different charge levels affect decay rate"""
        fancy_print("CHARGE-DECAY RELATIONSHIP TEST", "neural")
        
        # Based on gradient test, use working burst lengths
        test_configs = [
            {"burst": 2, "name": "Minimal charge"},
            {"burst": 4, "name": "Half charge"},
            {"burst": 6, "name": "Most charge"},
            {"burst": 8, "name": "Full charge"}
        ]
        
        test_addr = 0x00001000
        test_pattern = "AAAAAAAA"
        decay_times = [1, 5, 10, 20, 30]
        
        print(f"\n{Fore.CYAN}Testing decay rates with different charge levels:{Style.RESET_ALL}")
        
        for config in test_configs:
            print(f"\n{Fore.YELLOW}{config['name']} ({config['burst']} cycles):{Style.RESET_ALL}")
            
            # Configure burst length
            self.configure_timing(burst_len=config['burst'])
            time.sleep(0.1)
            
            # Write pattern
            for _ in range(10):
                self.write_cmd(test_addr, test_pattern)
                time.sleep(0.001)
            
            # Test decay at different times
            decay_profile = []
            
            for decay_time in decay_times:
                # Re-write
                for _ in range(10):
                    self.write_cmd(test_addr, test_pattern)
                    time.sleep(0.001)
                
                # Wait
                time.sleep(decay_time)
                
                # Read
                read_data = self.read_cmd(test_addr)
                if read_data:
                    errors = self.hamming_distance(test_pattern, read_data)
                    print(f"  After {decay_time:2d}s: {errors:2d} errors", end='')
                    
                    # Visual representation
                    error_bar = '▓' * min(errors, 20)
                    print(f" {error_bar}")
                    
                    decay_profile.append((decay_time, errors))
            
            # Reset timing
            self.configure_timing(burst_len=0)
        
        print(f"\n{Fore.GREEN}Lower charge = Faster decay (neuromorphic behavior!){Style.RESET_ALL}")

    def extreme_timing_test(self, addr, pattern="AAAAAAAA"):
        """Test with ALL timing parameters set to absolute minimum"""
        
        # Set EXTREME timing - everything to minimum
        # tWR (write recovery) = 1 cycle
        # tRAS (row active time) = 1 cycle  
        # burst_len = 1 cycle
        # skip_refresh = 1 (disable refresh)
        
        extreme_config = (1 << 20) | (1 << 16) | (1 << 8) | 1  # All minimums + skip refresh
        
        fancy_print(f"Setting EXTREME timing config: 0x{extreme_config:08X}", "warning")
        self.configure_timing_raw(extreme_config)
        time.sleep(0.1)
        
        # Write with extreme timings
        for _ in range(5):
            self.write_cmd(addr, pattern)
            time.sleep(0.001)
        
        time.sleep(0.1)
        
        # Read immediately
        extreme_read = self.read_cmd(addr)
        
        # Now test with NORMAL timing for comparison
        self.configure_timing_raw(0x00000000)  # Reset to defaults
        time.sleep(0.1)
        
        # Write with normal timings
        for _ in range(5):
            self.write_cmd(addr, pattern)
            time.sleep(0.001)
        
        time.sleep(0.1)
        
        # Read immediately
        normal_read = self.read_cmd(addr)
        
        # Analysis
        if extreme_read and normal_read:
            extreme_hamming = self.hamming_distance(pattern, extreme_read)
            normal_hamming = self.hamming_distance(pattern, normal_read)
            
            return {
                'extreme_read': extreme_read,
                'normal_read': normal_read,
                'extreme_errors': extreme_hamming,
                'normal_errors': normal_hamming,
                'difference': extreme_hamming - normal_hamming
            }
        
        return None

    def extreme_timing_sweep(self):
        """Test with absolute minimum timings to see if DRAM even works"""
        fancy_print("EXTREME TIMING TEST - Pushing DRAM to the limits!", "warning")
        
        print(f"\n{Fore.RED}Testing with:")
        print(f"  • tWR = 1 cycle (minimum write recovery)")
        print(f"  • tRAS = 1 cycle (minimum row active)")
        print(f"  • Burst = 1 cycle (minimum write)")
        print(f"  • Refresh DISABLED")
        print(f"  This may cause errors or crashes!{Style.RESET_ALL}\n")
        
        # Test different timing combinations
        timing_configs = [
            {"name": "Normal", "value": 0x00000000},
            {"name": "Min burst only", "value": 0x00010000},
            {"name": "Min burst + tWR", "value": 0x00010001},
            {"name": "Min burst + tRAS", "value": 0x00010100},
            {"name": "Min everything", "value": 0x00010101},
            {"name": "Min + no refresh", "value": 0x00110101},
        ]
        
        test_addresses = [0x00000000, 0x00001000, 0x00010000, 0x00100000]
        test_pattern = "AAAAAAAA"
        
        results = []
        
        for config in timing_configs:
            print(f"\n{Fore.YELLOW}Testing: {config['name']} (0x{config['value']:08X}){Style.RESET_ALL}")
            
            self.configure_timing_raw(config['value'])
            time.sleep(0.2)
            
            config_results = []
            
            for addr in test_addresses:
                # Try to write
                try:
                    for _ in range(5):
                        self.write_cmd(addr, test_pattern)
                        time.sleep(0.001)
                    
                    time.sleep(0.1)
                    
                    # Try to read
                    read_data = self.read_cmd(addr)
                    
                    if read_data:
                        hamming = self.hamming_distance(test_pattern, read_data)
                        print(f"  0x{addr:08X}: Read {read_data}, {hamming} errors")
                        
                        config_results.append({
                            'addr': addr,
                            'read': read_data,
                            'errors': hamming
                        })
                    else:
                        print(f"  0x{addr:08X}: Read FAILED!")
                        
                except Exception as e:
                    print(f"  0x{addr:08X}: EXCEPTION: {e}")
            
            results.append({
                'config': config,
                'results': config_results
            })
            
            # Reset to safe timing before next test
            self.configure_timing_raw(0x00000000)
            time.sleep(0.2)
        
        # Analyze results
        print(f"\n{Fore.CYAN}{'='*60}")
        print("EXTREME TIMING ANALYSIS")
        print(f"{'='*60}{Style.RESET_ALL}\n")
        
        working_configs = []
        
        for res in results:
            config = res['config']
            config_results = res['results']
            
            if config_results:
                avg_errors = sum(r['errors'] for r in config_results) / len(config_results)
                print(f"{config['name']}:")
                print(f"  Average errors: {avg_errors:.1f}")
                
                if avg_errors < 16:  # Less than half the bits wrong
                    working_configs.append(config['name'])
                    print(f"  Status: {Fore.GREEN}WORKING{Style.RESET_ALL}")
                else:
                    print(f"  Status: {Fore.RED}FAILING{Style.RESET_ALL}")
            else:
                print(f"{config['name']}: {Fore.RED}NO READS{Style.RESET_ALL}")
        
        if working_configs:
            print(f"\n{Fore.GREEN}Working configurations: {', '.join(working_configs)}{Style.RESET_ALL}")
        else:
            print(f"\n{Fore.RED}NO CONFIGURATIONS WORKED! Check DDR3 controller.{Style.RESET_ALL}")
        
        return results

    def write_cmd(self, addr, data):
        """Write command"""
        cmd = f"W{addr:08X} {data}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.01)

    def read_cmd(self, addr):
        """Read command with error handling"""
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
                        hex_part = line[-8:].upper()
                        int(hex_part, 16)
                        response = hex_part
                        break
                except:
                    continue

        return response if response else None

    def hamming_distance(self, hex1, hex2):
        """Calculate Hamming distance between two hex strings"""
        try:
            v1 = int(hex1, 16)
            v2 = int(hex2, 16)
            return bin(v1 ^ v2).count('1')
        except:
            return 32

    ### ================================================================================= ###
    ### MODIFICATION BLOCK: Replacing the three slow/flawed sweep functions with one      ###
    ### that is correct and efficient. ALL OTHER FUNCTIONS ARE PRESERVED.                 ###
    ### ================================================================================= ###
    
    def hybrid_neuromorphic_candidate_sweep(self):
        """
        Finds leaky cells using a time-efficient hybrid strategy. For each cell, it
        performs a fast gradient check, and ONLY if the cell is promising, it then
        performs the slow decay test before moving to the next address.
        """
        fancy_print("PHASE 1: Hybrid Neuromorphic Candidate Sweep", "charge")
        all_addresses = [addr for r in MEMORY_REGIONS for addr in range(r['start'], r['end'], r['step'])]
        leaky_cells = []
        pattern = "AAAAAAAA"
        DECAY_WAIT_SECONDS = 30  # Wait 30s to observe decay

        global current_status
        stop_event = threading.Event()
        animator = threading.Thread(target=animate_spinner, args=(stop_event, 'scan'))
        
        fancy_print(f"Scanning {len(all_addresses)} addresses using hybrid approach.", "info")
        animator.start()
        progress_bar.start_time = time.time()

        try:
            for i, addr in enumerate(all_addresses):
                current_status = f"Scanning ({i+1}/{len(all_addresses)}) | Found: {len(leaky_cells)}"
                
                # --- Step 1: Fast Immediate Gradient Check ---
                imm_hammings = {}
                for config in self.quick_partial_configs:
                    cycles = config['cycles']
                    self.configure_timing(burst_len=cycles)
                    for _ in range(5): self.write_cmd(addr, pattern)
                    imm_hammings[cycles] = self.hamming_distance(pattern, self.read_cmd(addr))

                # --- Step 2: Analyze Gradient and Decide ---
                cycles = sorted(imm_hammings.keys())
                if len(cycles) < 3: continue
                
                h_sub, h_thresh, h_super = imm_hammings[cycles[0]], imm_hammings[cycles[1]], imm_hammings[cycles[2]]
                
                is_promising_candidate = (h_sub > 10) and (h_thresh < 4) and (h_super < 4)
                if not is_promising_candidate:
                    continue

                # --- Step 3: Slow Decay Test (only for promising candidates) ---
                stop_event.set(); animator.join(); clear_line()
                
                fancy_print(f"Promising gradient at 0x{addr:08X}. Pausing scan for decay test...", "info")
                
                threshold_cycles = cycles[1]
                self.configure_timing(burst_len=threshold_cycles)
                for _ in range(5): self.write_cmd(addr, pattern)
                
                fancy_print(f"Waiting {DECAY_WAIT_SECONDS}s...", "neural")
                time.sleep(DECAY_WAIT_SECONDS)
                
                hamming_decay = self.hamming_distance(pattern, self.read_cmd(addr))
                
                if (hamming_decay - h_thresh) > 2:
                    fancy_print(f"CONFIRMED LEAKY CELL at 0x{addr:08X}!", "found")
                    print(f"  {Fore.YELLOW}└─ Immediate errors: {list(imm_hammings.values())} → Decay at threshold: {hamming_decay} (Degradation!){Style.RESET_ALL}")
                    leaky_cells.append({
                        'addr': addr,
                        'region': next((r['name'] for r in MEMORY_REGIONS if r['start'] <= addr < r['end']), 'Unknown'),
                        'results': {'imm': imm_hammings, 'decay_thresh': hamming_decay}
                    })
                else:
                    fancy_print(f"Cell 0x{addr:08X} was stable. Resuming scan.", "info")

                stop_event.clear()
                animator = threading.Thread(target=animate_spinner, args=(stop_event, 'scan'))
                animator.start()
        finally:
            stop_event.set(); animator.join(); clear_line()

        self.configure_timing(burst_len=0)
        fancy_print(f"Hybrid sweep complete! Found {len(leaky_cells)} leaky cells.", "success")
        return leaky_cells

    ### ================================================================================= ###
    ### END OF MODIFICATION BLOCK. ORIGINAL FUNCTIONS ARE PRESERVED BELOW.                ###
    ### ================================================================================= ###

    def detailed_partial_charge_characterization(self, candidates):
        """Detailed characterization of partial charge sensitive cells"""
        fancy_print(f"PHASE 2: Detailed Partial Charge Characterization of {len(candidates)} cells", "charge")
        
        characterized = []
        
        for i, candidate in enumerate(candidates[:20]):  # Limit to 20 for time
            addr = candidate['addr']
            
            print(f"\n{Fore.YELLOW}Partial Charge Cell {i+1}/{min(len(candidates), 20)}: 0x{addr:08X}{Style.RESET_ALL}")
            print(f"{Fore.WHITE}{'─' * 60}{Style.RESET_ALL}")
            
            cell_profile = {
                'address': addr,
                'region': candidate['region'],
                'partial_charge_profiles': {}
            }
            
            # Test with multiple patterns
            for pattern_info in QUICK_TEST_PATTERNS:
                print(f"\n  Testing with pattern: {pattern_info['name']}")
                
                # Full partial write test
                partial_results = self.test_partial_writes_detailed(addr, pattern_info)
                cell_profile['partial_charge_profiles'][pattern_info['name']] = partial_results
                
                # Show summary
                if partial_results:
                    charge_sensitivity = self.analyze_charge_sensitivity(partial_results)
                    print(f"    {Fore.GREEN}Charge sensitivity score: {charge_sensitivity:.2f}{Style.RESET_ALL}")
            
            cell_profile['partial_sensitive'] = True
            self.cell_profiles[addr] = cell_profile
            characterized.append(cell_profile)
            
            # Progress
            progress = (i + 1) / min(len(candidates), 20)
            bar_length = 40
            filled = int(bar_length * progress)
            bar = f"{Fore.YELLOW}{'█' * filled}{Fore.WHITE}{'░' * (bar_length - filled)}"
            print(f"\nPartial Charge Analysis: [{bar}] {progress*100:.0f}%")
        
        return characterized

    def test_partial_writes_detailed(self, addr, pattern_info):
        """Detailed test of partial write responses"""
        results = []
        pattern = pattern_info['pattern']
        
        for config in PARTIAL_WRITE_CONFIGS:
            cycles = config['cycles']
            
            # Configure partial writes
            self.configure_timing(burst_len=cycles)
            time.sleep(0.1)
            
            # Write with partial configuration
            for _ in range(NWRITES):
                self.write_cmd(addr, pattern)
                time.sleep(0.001)
            
            time.sleep(0.1)
            
            # Test decay at quick intervals
            decay_profile = []
            for decay_time in QUICK_DECAY_TIMES:
                # Re-write
                for _ in range(NWRITES):
                    self.write_cmd(addr, pattern)
                
                # Wait
                time.sleep(decay_time)
                
                # Read back
                data = self.read_cmd(addr)
                if data:
                    hamming = self.hamming_distance(pattern, data)
                    decay_profile.append({
                        'time': decay_time,
                        'hamming': hamming,
                        'readback': data
                    })
            
            results.append({
                'cycles': cycles,
                'config_name': config['name'],
                'decay_profile': decay_profile
            })
        
        # Reset to normal operation
        self.configure_timing(burst_len=0)
        
        return results

    def analyze_charge_sensitivity(self, partial_results):
        """Calculate a sensitivity score from partial charge results"""
        scores = []
        
        for i in range(len(partial_results) - 1):
            curr = partial_results[i]
            next_res = partial_results[i + 1]
            
            # Compare decay rates at same time points
            if curr['decay_profile'] and next_res['decay_profile']:
                for j in range(min(len(curr['decay_profile']), len(next_res['decay_profile']))):
                    curr_hamming = curr['decay_profile'][j]['hamming']
                    next_hamming = next_res['decay_profile'][j]['hamming']
                    
                    # Score based on difference in decay between charge levels
                    diff = abs(curr_hamming - next_hamming)
                    scores.append(diff)
        
        return np.mean(scores) if scores else 0

    def optional_decay_analysis(self, partial_sensitive_cells):
        """Optional: Run decay analysis on the most interesting partial-sensitive cells"""
        fancy_print("PHASE 3 (Optional): Decay Analysis of Top Partial-Sensitive Cells", "neural")
        
        # Select top 10 most sensitive cells
        sorted_cells = sorted(partial_sensitive_cells, 
                              key=lambda x: self.analyze_charge_sensitivity(
                                  self.cell_profiles.get(x['addr'], {}).get('partial_charge_profiles', {}).get('Checkerboard', [])),
                              reverse=True)
        
        top_cells = sorted_cells[:10]
        
        fancy_print(f"Running decay analysis on {len(top_cells)} most sensitive cells", "info")
        
        for i, cell in enumerate(top_cells):
            addr = cell['addr']
            profile = self.cell_profiles.get(addr, {})
            
            print(f"\n{Fore.CYAN}Decay Test {i+1}/{len(top_cells)}: Cell 0x{addr:08X}{Style.RESET_ALL}")
            
            # Run decay test with one pattern
            test_pattern = {"name": "Checkerboard", "pattern": "AAAAAAAA"}
            decay_profile = self.characterize_cell_decay(addr, test_pattern)
            
            if decay_profile:
                profile['decay_profile'] = decay_profile
                
                # Classify decay rate
                decay_times = [p['time'] for p in decay_profile if p['hamming'] > 0]
                if decay_times:
                    first_decay = min(decay_times)
                    if first_decay < 30:
                        profile['decay_class'] = 'fast'
                    elif first_decay > 300:
                        profile['decay_class'] = 'slow'
                    else:
                        profile['decay_class'] = 'medium'
                
                self.cell_profiles[addr] = profile

    def characterize_cell_decay(self, addr, pattern_info):
        """Decay characterization (simplified for optional use)"""
        pattern = pattern_info['pattern']
        decay_points = []
        
        # Write pattern
        for _ in range(NWRITES):
            self.write_cmd(addr, pattern)
            time.sleep(0.001)
        
        time.sleep(0.1)
        
        # Verify initial write
        initial = self.read_cmd(addr)
        if self.hamming_distance(pattern, initial) > 4: # Allow for some initial errors on weak cells
             fancy_print(f"Cell 0x{addr:08X} failed initial write, cannot characterize decay.", "warning")
             return None
        
        # Test decay at limited intervals (faster)
        test_intervals = [10, 30, 60, 120, 300]
        
        for interval in test_intervals:
            # Re-write
            for _ in range(NWRITES):
                self.write_cmd(addr, pattern)
            
            # Wait
            time.sleep(interval)
            
            # Read and measure
            data = self.read_cmd(addr)
            if data:
                hamming = self.hamming_distance(pattern, data)
                decay_points.append({
                    'time': interval,
                    'hamming': hamming,
                    'readback': data,
                    'pattern': pattern
                })
                
                # Early exit if significant decay
                if hamming > 16:
                    break
        
        return decay_points


    def sub_threshold_charge_test(self):
        """Test if sub-threshold charges exist and decay differently"""
        fancy_print("SUB-THRESHOLD CHARGE DETECTION TEST", "neural")
        
        test_addr = 0x00001000
        
        print(f"\n{Fore.CYAN}Hypothesis: Burst 1-2 DO charge cells, just below sense threshold{Style.RESET_ALL}")
        print(f"Testing by looking at charge accumulation and decay patterns\n")
        
        # Test 1: Charge accumulation
        print(f"{Fore.YELLOW}Test 1: Repeated sub-threshold writes (accumulation test){Style.RESET_ALL}")
        
        for burst_len in [1, 2, 3]:
            print(f"\nBurst {burst_len}:")
            
            self.configure_timing(burst_len=burst_len)
            time.sleep(0.1)
            
            # Try different numbers of repeated writes
            for num_writes in [1, 5, 10, 20, 50]:
                # Clear cell first
                self.configure_timing(burst_len=8)
                self.write_cmd(test_addr, "00000000")
                time.sleep(0.1)
                
                # Now do repeated writes with test burst length
                self.configure_timing(burst_len=burst_len)
                for _ in range(num_writes):
                    self.write_cmd(test_addr, "FFFFFFFF")
                    time.sleep(0.001)
                
                time.sleep(0.01)
                read_data = self.read_cmd(test_addr)
                
                if read_data:
                    hamming = self.hamming_distance("00000000", read_data)
                    if hamming > 0:
                        print(f"  {num_writes:2d} writes: {read_data} ({hamming} bits set)")
                    else:
                        print(f"  {num_writes:2d} writes: Still reads as 00000000")
        
        # Reset
        self.configure_timing(burst_len=0)
        
        # Test 2: Pre-charge assist
        print(f"\n{Fore.YELLOW}Test 2: Pre-charge assist test{Style.RESET_ALL}")
        print("Writing burst=2 on top of existing partial charge\n")
        
        # First, put cell at different charge levels
        pre_charges = [
            {"burst": 0, "name": "No pre-charge"},
            {"burst": 1, "name": "Burst 1 pre-charge"},
            {"burst": 2, "name": "Burst 2 pre-charge"},
            {"burst": 3, "name": "Burst 3 pre-charge"}
        ]
        
        for pre in pre_charges:
            print(f"{pre['name']}:")
            
            # Clear cell
            self.configure_timing(burst_len=8)
            self.write_cmd(test_addr, "00000000")
            time.sleep(0.1)
            
            if pre['burst'] > 0:
                # Apply pre-charge
                self.configure_timing(burst_len=pre['burst'])
                for _ in range(5):
                    self.write_cmd(test_addr, "AAAAAAAA")
                time.sleep(0.01)
            
            # Now write with burst=2
            self.configure_timing(burst_len=2)
            for _ in range(5):
                self.write_cmd(test_addr, "AAAAAAAA")
            time.sleep(0.01)
            
            read_data = self.read_cmd(test_addr)
            if read_data:
                hamming = self.hamming_distance("AAAAAAAA", read_data)
                if hamming < 16:
                    print(f"  → Read: {read_data} ({32-hamming} correct bits)")
                else:
                    print(f"  → Failed to read pattern")
        
        # Reset
        self.configure_timing(burst_len=0)
        
        # Test 3: Decay from sub-threshold
        print(f"\n{Fore.YELLOW}Test 3: Sub-threshold decay test{Style.RESET_ALL}")
        print("Do sub-threshold charges decay faster?\n")
        
        decay_times = [0, 1, 5, 10, 20]
        
        for burst_len in [2, 3, 4]:
            print(f"\nBurst {burst_len}:")
            
            for decay_time in decay_times:
                # Configure and write
                self.configure_timing(burst_len=burst_len)
                for _ in range(10):
                    self.write_cmd(test_addr, "FFFFFFFF")
                
                # Wait
                time.sleep(decay_time)
                
                # Read
                read_data = self.read_cmd(test_addr)
                if read_data:
                    hamming = self.hamming_distance("FFFFFFFF", read_data)
                    set_bits = 32 - hamming
                    print(f"  After {decay_time:2d}s: {set_bits:2d} bits still set")
        
        # Reset
        self.configure_timing(burst_len=0)
        
        print(f"\n{Fore.GREEN}If burst 1-2 show accumulation or assist effects,")
        print(f"they ARE storing charge below the sense threshold!{Style.RESET_ALL}")

    def analog_charge_levels_test(self):
        """Test if we can create multiple analog levels"""
        fancy_print("ANALOG CHARGE LEVELS TEST", "neural")
        
        test_addr = 0x00001000
        
        print(f"\n{Fore.CYAN}Testing charge mixture to create analog levels{Style.RESET_ALL}\n")
        
        # Test: Mix different burst lengths
        mix_configs = [
            {"seq": [1,1,1,1,1], "name": "5x burst=1"},
            {"seq": [2,2,2], "name": "3x burst=2"},
            {"seq": [1,1,1,2], "name": "3x burst=1 + 1x burst=2"},
            {"seq": [2,1,2,1], "name": "Alternating 2,1"},
            {"seq": [3], "name": "1x burst=3 (reference)"},
            {"seq": [1,1,1,1,1,1,1,1,1,1], "name": "10x burst=1"},
        ]
        
        for config in mix_configs:
            print(f"{config['name']}:")
            
            # Clear cell
            self.configure_timing(burst_len=8)
            self.write_cmd(test_addr, "00000000")
            time.sleep(0.1)
            
            # Apply sequence
            for burst in config['seq']:
                self.configure_timing(burst_len=burst)
                self.write_cmd(test_addr, "FFFFFFFF")
                time.sleep(0.001)
            
            time.sleep(0.01)
            
            # Read immediately
            read_data = self.read_cmd(test_addr)
            if read_data:
                # Count set bits
                val = int(read_data, 16)
                set_bits = bin(val).count('1')
                
                # Show analog level
                level_bar = '█' * (set_bits // 2)
                print(f"  → {read_data} ({set_bits}/32 bits) {level_bar}")
        
        # Reset
        self.configure_timing(burst_len=0)
        
        print(f"\n{Fore.GREEN}Multiple burst=1 or burst=2 writes might accumulate")
        print(f"to eventually cross the threshold!{Style.RESET_ALL}")
        
    def run_comprehensive_analysis(self):
        """Run neuromorphic characterization prioritizing partial charges"""
        print(f"{Fore.CYAN}{NEURO_DRAM_ART}{Style.RESET_ALL}")
        fancy_print("INITIATING NEUROMORPHIC DRAM CHARACTERIZATION", "header")
        fancy_print("Prioritizing Partial Charge Testing for Rapid Discovery", "charge")
        
        fancy_print("PHASE 0: Extreme Timing Limits Test", "warning")
        self.extreme_timing_sweep()

        fancy_print("PHASE 0.5: Burst Length Gradient Test", "charge")
        gradient_results = self.burst_length_gradient_test()
        
        working_bursts = [r for r in gradient_results if r['working']]
        if working_bursts:
            min_working_burst = min(r['burst_len'] for r in working_bursts)
            fancy_print(f"Minimum working burst length is {min_working_burst}. Adjusting quick test.", "info")
            
            c1 = max(1, min_working_burst - 1)
            c2 = min_working_burst
            c3 = min(8, min_working_burst + 1)

            self.quick_partial_configs = [
                {"cycles": c1, "name": "Sub-Threshold", "description": "Below working threshold"},
                {"cycles": c2, "name": "Threshold", "description": "Minimum working charge"},
                {"cycles": c3, "name": "Super-Threshold", "description": "Reliable working charge"},
            ]
            fancy_print(f"Quick partial sweep will now use burst cycles: [{c1}, {c2}, {c3}]", "charge")
        else:
            fancy_print("No working burst length found! Using fallback quick test configs.", "warning")
            self.quick_partial_configs = QUICK_PARTIAL_CONFIGS_FALLBACK

        fancy_print("PHASE 0.7: Sub-threshold charge test", "charge")
        self.sub_threshold_charge_test()
        
        # ### THIS IS THE LINE THAT WAS CHANGED ###
        partial_sensitive_cells = self.hybrid_neuromorphic_candidate_sweep()
        
        if not partial_sensitive_cells:
            fancy_print("No leaky neuromorphic cells found with this test.", "warning")
            fancy_print("Consider increasing the decay wait time or adjusting voltage/temperature.", "info")
            return self.cell_profiles
        
        self.detailed_partial_charge_characterization(partial_sensitive_cells)
        
        user_input = input(f"\n{Fore.YELLOW}Run optional full decay analysis on found candidates? (y/N): {Style.RESET_ALL}")
        if user_input.lower() == 'y':
            self.optional_decay_analysis(partial_sensitive_cells)
        
        fancy_print("PHASE 4: Generating Neuromorphic Profile Report", "neural")
        self.generate_comprehensive_report()
        
        return self.cell_profiles


    def traditional_decay_sweep(self):
        """Fallback to traditional decay-based discovery"""
        fancy_print("Running traditional decay-based discovery (this will take time)", "warning")
        return {}

    def generate_comprehensive_report(self):
        """Generate detailed neuromorphic characterization report"""
        fancy_print("Generating Comprehensive Neuromorphic Report", "neural")

        report = {
            'session_id': self.session_id,
            'timestamp': datetime.now().isoformat(),
            'total_cells_analyzed': len(self.cell_profiles),
            'cell_classifications': defaultdict(int),
            'partial_charge_statistics': {},
            'decay_statistics': {},
            'neuromorphic_candidates': []
        }

        partial_sensitive_count = 0
        decay_characterized_count = 0
        
        for addr, profile in self.cell_profiles.items():
            if profile.get('partial_sensitive', False):
                partial_sensitive_count += 1
                report['cell_classifications']['partial_sensitive'] += 1
            
            if 'decay_class' in profile:
                decay_characterized_count += 1
                report['cell_classifications'][profile['decay_class'] + '_decay'] += 1
            
            if profile.get('partial_sensitive', False):
                report['neuromorphic_candidates'].append({
                    'address': addr,
                    'type': 'tunable_synapse',
                    'decay_class': profile.get('decay_class', 'unknown')
                })

        profiles_file = self.results_dir / "cell_profiles.json"
        with open(profiles_file, 'w') as f:
            serializable_profiles = {}
            for addr, profile in self.cell_profiles.items():
                serializable_profiles[f"0x{addr:08X}"] = profile
            json.dump(serializable_profiles, f, indent=2)

        report_file = self.results_dir / "neuromorphic_report.json"
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)

        print(f"\n{Fore.CYAN}{'═' * 80}")
        print(f"║{Style.BRIGHT}{'NEUROMORPHIC CHARACTERIZATION SUMMARY'.center(76)}{Style.NORMAL}{Fore.CYAN}║")
        print(f"{'═' * 80}{Style.RESET_ALL}\n")

        print(f"  {Fore.GREEN}Total Cells Profiled: {len(self.cell_profiles)}")
        print(f"  {Fore.YELLOW}Leaky 'Synapse' Candidates Found: {partial_sensitive_count}")
        print(f"  {Fore.BLUE}Decay Class Characterized: {decay_characterized_count}")
        
        print(f"\n  {Fore.YELLOW}Cell Classifications:")
        for classification, count in report['cell_classifications'].items():
           print(f"    • {classification}: {count}")

        print(f"\n  {Fore.MAGENTA}Neuromorphic Candidates: {len(report['neuromorphic_candidates'])}")

        if report['neuromorphic_candidates']:
           print(f"\n  {Fore.CYAN}Top Tunable Synapse Candidates:")
           for i, candidate in enumerate(report['neuromorphic_candidates'][:10], 1):
               print(f"    {i}. 0x{candidate['address']:08X} - {candidate['type']}")

        print(f"\n  {Fore.GREEN}Results saved to: {self.results_dir}/")
        print(f"    • Cell profiles: cell_profiles.json")
        print(f"    • Summary report: neuromorphic_report.json")

        return report

def main():
    try:
        fancy_print("Establishing Neural Link to DRAM Controller...", "neural")
        ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)
        time.sleep(0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        fancy_print(f"Neural Link Established: {SERIAL_PORT} @ {BAUDRATE} baud", "success")

    except serial.SerialException as e:
        fancy_print(f"Failed to establish neural link: {e}", "error")
        return 1

    analyzer = NeuromorphicDRAMAnalyzer(ser)

    print(f"\n{Fore.CYAN}", end='')
    startup_msg = "INITIATING NEUROMORPHIC DISCOVERY (DECAY-FOCUSED)..."
    for char in startup_msg:
        print(char, end='', flush=True)
        time.sleep(0.05)
    print(f"{Style.RESET_ALL}\n")

    print(f"\n{Fore.YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗")
    print(f"║                               ANALYSIS STRATEGY                                ║")
    print(f"╠══════════════════════════════════════════════════════════════════════════════╣")
    print(f"║  1. Gradient Test - Find the critical write threshold.                         ║")
    print(f"║  2. Quick Scan - Find cells that DECAY faster than the stable baseline.        ║")
    print(f"║  3. Detailed Characterization - Profile the most promising leaky cells.        ║")
    print(f"╚══════════════════════════════════════════════════════════════════════════════╝{Style.RESET_ALL}\n")

    fancy_print("Testing timing configuration...", "info")
    analyzer.configure_timing(burst_len=4)
    time.sleep(0.1)
    analyzer.configure_timing(burst_len=0)
    
    start_time = time.time()
    try:
        cell_profiles = analyzer.run_comprehensive_analysis()
        elapsed = time.time() - start_time

        fancy_print("NEUROMORPHIC CHARACTERIZATION COMPLETE!", "header")
        fancy_print(f"Total Analysis Time: {elapsed/60:.1f} minutes", "info")
        
        if not cell_profiles:
            fancy_print("No cells were fully profiled. Check logs for details.", "warning")
            return
            
        fancy_print(f"Cells Profiled: {len(cell_profiles)}", "success")

        print(f"\n{Fore.MAGENTA}{'─' * 80}")
        print(f"{Style.BRIGHT}KEY NEUROMORPHIC FINDINGS:{Style.RESET_ALL}")
        print(f"{Fore.MAGENTA}{'─' * 80}{Style.RESET_ALL}\n")

        synapse_cells = []
        fast_decay_cells = []
        slow_decay_cells = []
        
        for addr, profile in cell_profiles.items():
            if profile.get('partial_sensitive', False):
                synapse_cells.append(addr)
            if profile.get('decay_class') == 'fast':
                fast_decay_cells.append(addr)
            elif profile.get('decay_class') == 'slow':
                slow_decay_cells.append(addr)

        print(f"  {Fore.YELLOW}🔄 Tunable Synapses (Leaky Cells): {len(synapse_cells)}")
        if synapse_cells:
            for addr in synapse_cells[:5]:
                print(f"        → 0x{addr:08X}")
            if len(synapse_cells) > 5:
                print(f"        ... and {len(synapse_cells) - 5} more")

        if fast_decay_cells:
            print(f"\n  {Fore.RED}⚡ Fast Decay Cells: {len(fast_decay_cells)}")
            for addr in fast_decay_cells[:3]:
                print(f"        → 0x{addr:08X}")

        if slow_decay_cells:
            print(f"\n  {Fore.BLUE}📦 Slow Decay Cells: {len(slow_decay_cells)}")
            for addr in slow_decay_cells[:3]:
                print(f"        → 0x{addr:08X}")

        print(f"\n{Fore.CYAN}{'═' * 80}")
        print(f"║{Style.BRIGHT}{'NEUROMORPHIC IMPLEMENTATION SUGGESTIONS'.center(76)}{Style.NORMAL}{Fore.CYAN}║")
        print(f"{'═' * 80}{Style.RESET_ALL}\n")

        if len(synapse_cells) > 0:
            print(f"  {Fore.GREEN}✓ Found cells with promising analog decay behavior!")
            print(f"  {Fore.GREEN}✓ Partial charge control + natural decay enables temporal dynamics.")
            print(f"\n  {Style.BRIGHT}Recommended Applications:{Style.RESET_ALL}")
            print(f"    • Spiking Neural Networks with plastic synapses")
            print(f"    • Reservoir Computing / Liquid State Machines")
            print(f"    • Temporal pattern recognition")
        else:
            print(f"  {Fore.YELLOW}⚠ No leaky cells found with current settings.")
            print(f"  Suggestions:")
            print(f"    • Increase the DECAY_WAIT_SECONDS in `quick_partial_charge_test`.")
            print(f"    • Slightly increase temperature or lower voltage to induce more errors.")

        architecture_file = analyzer.results_dir / "neuromorphic_architecture.json"
        architecture = {
            'timestamp': datetime.now().isoformat(),
            'tunable_synapses': [f"0x{addr:08X}" for addr in synapse_cells],
            'fast_decay_neurons': [f"0x{addr:08X}" for addr in fast_decay_cells],
            'slow_decay_memory': [f"0x{addr:08X}" for addr in slow_decay_cells],
            'statistics': {
                'total_characterized': len(cell_profiles),
                'synapse_count': len(synapse_cells),
                'fast_decay_count': len(fast_decay_cells),
                'slow_decay_count': len(slow_decay_cells)
            }
        }

        with open(architecture_file, 'w') as f:
            json.dump(architecture, f, indent=2)
        print(f"\n  {Fore.GREEN}Architecture mapping saved to: {architecture_file}")

    except KeyboardInterrupt:
        clear_line()
        fancy_print("\nAnalysis interrupted by user", "warning")
    except Exception as e:
        fancy_print(f"Analysis error: {e}", "error")
        import traceback
        traceback.print_exc()
    finally:
        ser.close()

    print(f"\n{Fore.MAGENTA}", end='')
    for char in "⚡ ✨ Neuromorphic Discovery Complete! ✨ ⚡":
        print(char, end='', flush=True)
        time.sleep(0.05)
    print(Style.RESET_ALL)
    
    return 0

if __name__ == "__main__":
    try:
        exit(main())
    except KeyboardInterrupt:
        clear_line()
        fancy_print("\nNeural analysis terminated", "warning")
        exit(1)
