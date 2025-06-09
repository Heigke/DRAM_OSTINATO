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
from scipy.optimize import curve_fit
import warnings
warnings.filterwarnings('ignore')

# Initialize colorama
init(autoreset=True)

# --- Configuration ---
SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.3

# Memory regions to test - comprehensive sweep
MEMORY_REGIONS = [
    {"name": "Low Memory", "start": 0x00000000, "end": 0x00100000, "step": 0x1000},
    {"name": "Bank Boundaries", "start": 0x00100000, "end": 0x01000000, "step": 0x8000},
    {"name": "High Memory", "start": 0x01000000, "end": 0x02000000, "step": 0x10000},
]

# Test patterns for characterization
TEST_PATTERNS = [
    {"name": "Checkerboard", "pattern": "AAAAAAAA", "description": "Maximum interference"},
    {"name": "All Ones", "pattern": "FFFFFFFF", "description": "Maximum charge"},
    {"name": "All Zeros", "pattern": "00000000", "description": "Minimum charge"},
]

# Decay times for full characterization
DECAY_TIMES = [0, 5, 10, 20, 30, 60, 90, 120]  # seconds

# ASCII Art
NEURO_BANNER = """
╔══════════════════════════════════════════════════════════════════════════════════╗
║                                                                                  ║
║  ███╗   ██╗███████╗██╗   ██╗██████╗  ██████╗ ██████╗ ██████╗  █████╗ ███╗   ███╗║
║  ████╗  ██║██╔════╝██║   ██║██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔══██╗████╗ ████║║
║  ██╔██╗ ██║█████╗  ██║   ██║██████╔╝██║   ██║██║  ██║██████╔╝███████║██╔████╔██║║
║  ██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗██║   ██║██║  ██║██╔══██╗██╔══██║██║╚██╔╝██║║
║  ██║ ╚████║███████╗╚██████╔╝██║  ██║╚██████╔╝██████╔╝██║  ██║██║  ██║██║ ╚═╝ ██║║
║  ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝║
║                                                                                  ║
║                        DRAM Cell Characterization Suite v2.0                     ║
║                     "Mapping the Analog Soul of Digital Memory"                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
"""

CELL_VIS = """
    ┌─────────────────────┐
    │  ╔═══════════════╗  │
    │  ║ ◉ ◉ ◉ ◉ ◉ ◉ ║  │  Cell Matrix
    │  ║ ◉ ◉ ◉ ◉ ◉ ◉ ║  │  ◉ = Characterized
    │  ║ ◉ ◉ ◉ ◉ ◉ ◉ ║  │  ○ = Pending
    │  ║ ◉ ◉ ◉ ◉ ◉ ◉ ║  │  ⚡ = Leaky
    │  ╚═══════════════╝  │  ✨ = Analog
    └─────────────────────┘
"""

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

class NeuromorphicDRAMProfiler:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.results_dir = Path(f"neuromorphic_characterization_{self.session_id}")
        self.results_dir.mkdir(exist_ok=True)
        
        # Data structures for comprehensive profiling
        self.cell_database = {}
        self.decay_profiles = defaultdict(dict)
        self.partial_charge_responses = defaultdict(dict)
        self.neighbor_influence = defaultdict(dict)
        self.cell_classifications = defaultdict(list)
        
        # Initialize system
        self.initialize_ddr3()
        
    def initialize_ddr3(self):
        """Initialize DDR3 controller - using the working method from pc3.py"""
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
    
    def configure_timing(self, twr=0, tras=0, burst_len=0, skip_refresh=0):
        """Configure DDR3 timing parameters - using working method from pc3.py"""
        config_value = (skip_refresh << 20) | (burst_len << 16) | (tras << 8) | twr
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
    
    def write_cmd(self, addr, data):
        """Write to DRAM - using working method from pc3.py"""
        cmd = f"W{addr:08X} {data}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.01)
    
    def read_cmd(self, addr):
        """Read from DRAM - using working method from pc3.py"""
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
        """Calculate bit differences"""
        try:
            v1 = int(hex1, 16)
            v2 = int(hex2, 16)
            return bin(v1 ^ v2).count('1')
        except:
            return 32
    
    def display_phase_banner(self, phase_num, phase_name, description):
        """Display fancy phase banner"""
        print(f"\n{Fore.CYAN}{'═' * 80}")
        print(f"║ PHASE {phase_num}: {phase_name.center(68)} ║")
        print(f"║ {description.center(76)} ║")
        print(f"{'═' * 80}{Style.RESET_ALL}\n")
    
    def progress_bar(self, current, total, width=50, prefix="Progress"):
        """Enhanced progress bar"""
        percent = current / total
        filled = int(width * percent)
        
        # Color based on progress
        if percent < 0.33:
            color = Fore.RED
        elif percent < 0.66:
            color = Fore.YELLOW
        else:
            color = Fore.GREEN
        
        bar = f"{color}{'█' * filled}{Fore.WHITE}{'░' * (width - filled)}"
        print(f"\r{prefix}: [{bar}] {percent*100:.1f}% ({current}/{total})", end='', flush=True)
    
    # ==================== PHASE 1: Initial Tests ====================
    
    def phase1_initial_tests(self):
        """Initial tests including extreme timing and burst gradient"""
        self.display_phase_banner(1, "INITIAL SYSTEM TESTS", 
                                  "Testing DDR3 boundaries and partial charge behavior")
        
        # Test 1: Extreme timing test
        print(f"{Fore.YELLOW}Test 1: Extreme Timing Test{Style.RESET_ALL}")
        self.extreme_timing_test()
        
        # Test 2: Burst length gradient
        print(f"\n{Fore.YELLOW}Test 2: Burst Length Gradient Test{Style.RESET_ALL}")
        burst_results = self.burst_length_gradient_test()
        
        # Test 3: Sub-threshold charge accumulation
        print(f"\n{Fore.YELLOW}Test 3: Sub-threshold Charge Accumulation{Style.RESET_ALL}")
        self.sub_threshold_charge_test()
        
        return burst_results
    
    def extreme_timing_test(self):
        """Test with extreme timing parameters"""
        print(f"\n{Fore.RED}Testing with minimal timings:{Style.RESET_ALL}")
        print(f"  • tWR = 1 cycle (minimum write recovery)")
        print(f"  • tRAS = 1 cycle (minimum row active)")
        print(f"  • Burst = 1 cycle (minimum write)")
        print(f"  • Refresh DISABLED\n")
        
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
            print(f"\nTesting: {config['name']} (0x{config['value']:08X})")
            
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
        
        return results
    
    def burst_length_gradient_test(self):
        """Test different burst lengths to find the minimum working configuration"""
        test_addr = 0x00001000
        test_pattern = "AAAAAAAA"
        
        # Test burst lengths from 1 to 8
        results = []
        
        print(f"\nTesting burst lengths 1-8 cycles:")
        print(f"Pattern: {test_pattern}")
        print(f"Address: 0x{test_addr:08X}\n")
        
        for burst_len in range(1, 9):
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
                    'working': hamming < 8
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
            
            self.min_working_burst = min_working
        else:
            print(f"{Fore.RED}NO BURST LENGTHS WORKED!{Style.RESET_ALL}")
            self.min_working_burst = 8
        
        return results
    
    def sub_threshold_charge_test(self):
        """Test if sub-threshold charges exist and decay differently"""
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
        
        # Test 2: Decay from sub-threshold
        print(f"\n{Fore.YELLOW}Test 2: Sub-threshold decay test{Style.RESET_ALL}")
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
    
    # ==================== PHASE 2: Quick Leaky Cell Discovery ====================
    
    def phase2_quick_leaky_discovery(self):
        """Quick scan to find leaky cells using partial charges"""
        self.display_phase_banner(2, "QUICK LEAKY CELL DISCOVERY",
                                  "Finding cells with interesting decay behavior")
        
        # Configure test parameters based on phase 1 results
        if hasattr(self, 'min_working_burst') and self.min_working_burst <= 3:
            test_configs = [
                {"burst": self.min_working_burst - 1, "name": "Sub-threshold"},
                {"burst": self.min_working_burst, "name": "Threshold"},
                {"burst": self.min_working_burst + 1, "name": "Above-threshold"},
            ]
        else:
            # Fallback configuration
            test_configs = [
                {"burst": 2, "name": "Weak"},
                {"burst": 3, "name": "Medium"},
                {"burst": 4, "name": "Strong"},
            ]
        
        # Select subset of addresses for quick scan
        test_addresses = []
        for region in MEMORY_REGIONS:
            addresses = list(range(region['start'], region['end'], region['step']))
            test_addresses.extend(addresses[:100])  # 100 per region = 300 total
        
        print(f"{Fore.CYAN}Testing {len(test_addresses)} addresses with {len(test_configs)} charge levels{Style.RESET_ALL}\n")
        
        leaky_cells = []
        pattern = "AAAAAAAA"
        
        for i, addr in enumerate(test_addresses):
            # Test immediate response at different charge levels
            charge_responses = {}
            
            for config in test_configs:
                # Clean cell
                self.configure_timing(burst_len=8)
                for _ in range(10):
                    self.write_cmd(addr, "00000000")
                time.sleep(0.05)
                
                # Write with partial charge
                self.configure_timing(burst_len=config['burst'])
                for _ in range(10):
                    self.write_cmd(addr, pattern)
                time.sleep(0.05)
                
                # Read immediately
                immediate_read = self.read_cmd(addr)
                if immediate_read:
                    immediate_errors = self.hamming_distance(pattern, immediate_read)
                else:
                    immediate_errors = 32
                
                # Wait 30 seconds
                time.sleep(30)
                
                # Read after decay
                decay_read = self.read_cmd(addr)
                if decay_read:
                    decay_errors = self.hamming_distance(pattern, decay_read)
                else:
                    decay_errors = 32
                
                charge_responses[config['name']] = {
                    'immediate': immediate_errors,
                    'decay': decay_errors,
                    'degradation': decay_errors - immediate_errors
                }
            
            # Reset timing
            self.configure_timing(burst_len=0)
            
            # Check if this is a leaky cell
            # Criteria: works at threshold but degrades significantly
            if 'Threshold' in charge_responses:
                threshold_response = charge_responses['Threshold']
                if threshold_response['immediate'] < 8 and threshold_response['degradation'] > 2:
                    leaky_cells.append({
                        'addr': addr,
                        'responses': charge_responses
                    })
                    fancy_print(f"Found leaky cell at 0x{addr:08X}!", "found")
            
            # Progress
            self.progress_bar(i + 1, len(test_addresses), prefix="Quick Scan")
        
        print(f"\n\n{Fore.GREEN}✓ Found {len(leaky_cells)} leaky cells{Style.RESET_ALL}")
        
        # Save quick scan results
        with open(self.results_dir / "quick_scan_results.json", 'w') as f:
            json.dump({
                'leaky_cells': [{'addr': f"0x{c['addr']:08X}", 'responses': c['responses']} 
                               for c in leaky_cells],
                'test_configs': test_configs
            }, f, indent=2)
        
        return leaky_cells
    
    # ==================== PHASE 3: Full Decay Characterization ====================
    
    def phase3_full_decay_characterization(self, target_cells=None):
        """Comprehensive decay testing for selected cells"""
        self.display_phase_banner(3, "FULL DECAY CHARACTERIZATION",
                                  "Mapping temporal dynamics of cells")
        
        # Use provided cells or select from all regions
        if target_cells is None:
            test_addresses = []
            for region in MEMORY_REGIONS:
                addresses = list(range(region['start'], region['end'], region['step']))
                test_addresses.extend(addresses[:300])  # 300 per region
        else:
            test_addresses = [c['addr'] for c in target_cells]
        
        print(f"{Fore.CYAN}📊 Testing {len(test_addresses)} addresses with decay times up to {max(DECAY_TIMES)}s{Style.RESET_ALL}\n")
        
        # Test patterns
        patterns = [
            {"name": "Checkerboard", "pattern": "AAAAAAAA"},
            {"name": "All Ones", "pattern": "FFFFFFFF"}
        ]
        
        total_tests = len(test_addresses) * len(patterns)
        current_test = 0
        
        for addr in test_addresses:
            cell_profile = {
                'address': addr,
                'decay_profiles': {},
                'decay_characteristics': {}
            }
            
            for pattern_info in patterns:
                pattern = pattern_info['pattern']
                decay_data = []
                
                # Test each decay time
                for decay_time in DECAY_TIMES:
                    # Clean slate - write zeros
                    self.configure_timing(burst_len=8)
                    for _ in range(10):
                        self.write_cmd(addr, "00000000")
                    time.sleep(0.1)
                    
                    # Write test pattern with full charge
                    for _ in range(10):
                        self.write_cmd(addr, pattern)
                    time.sleep(0.1)
                    
                    # Wait for decay
                    if decay_time > 0:
                        time.sleep(decay_time)
                    
                    # Read back
                    read_data = self.read_cmd(addr)
                    
                    if read_data:
                        errors = self.hamming_distance(pattern, read_data)
                        retention = (32 - errors) / 32.0
                        
                        decay_data.append({
                            'time': decay_time,
                            'read': read_data,
                            'errors': errors,
                            'retention': retention
                        })
                
                # Reset timing
                self.configure_timing(burst_len=0)
                
                # Store decay profile
                cell_profile['decay_profiles'][pattern_info['name']] = decay_data
                
                # Fit exponential decay if we have good data
                if len([d for d in decay_data if d['retention'] < 0.9]) >= 3:
                    try:
                        times = np.array([d['time'] for d in decay_data])
                        retentions = np.array([d['retention'] for d in decay_data])
                        
                        # Fit exponential: retention = A * exp(-t/tau)
                        def exp_decay(t, A, tau):
                            return A * np.exp(-t/tau)
                        
                        popt, _ = curve_fit(exp_decay, times, retentions, p0=[1.0, 30.0])
                        tau = popt[1]
                        
                        cell_profile['decay_characteristics'][pattern_info['name']] = {
                            'tau': tau,
                            'decay_rate': 1/tau if tau > 0 else float('inf'),
                            'half_life': tau * np.log(2)
                        }
                    except:
                        pass
                
                current_test += 1
                self.progress_bar(current_test, total_tests, prefix="Decay Test")
            
            # Classify cell based on decay behavior
            self.classify_cell_decay(addr, cell_profile)
            
            # Store in database
            self.cell_database[addr] = cell_profile
            self.decay_profiles[addr] = cell_profile['decay_profiles']
        
        print(f"\n\n{Fore.GREEN}✓ Decay characterization complete!{Style.RESET_ALL}")
        self.save_checkpoint()
        
        # Display summary
        self.display_decay_summary()
    
    def classify_cell_decay(self, addr, profile):
        """Classify cell based on decay characteristics"""
        # Get average tau across patterns
        taus = []
        for pattern, chars in profile.get('decay_characteristics', {}).items():
            if 'tau' in chars:
                taus.append(chars['tau'])
        
        if taus:
            avg_tau = np.mean(taus)
            
            if avg_tau < 20:
                self.cell_classifications['fast_decay'].append(addr)
                profile['decay_class'] = 'fast'
            elif avg_tau < 60:
                self.cell_classifications['medium_decay'].append(addr)
                profile['decay_class'] = 'medium'
            else:
                self.cell_classifications['slow_decay'].append(addr)
                profile['decay_class'] = 'slow'
        else:
            # No significant decay observed
            self.cell_classifications['stable'].append(addr)
            profile['decay_class'] = 'stable'
    
    def display_decay_summary(self):
        """Display decay characterization summary"""
        print(f"\n{Fore.CYAN}{'─' * 60}")
        print(f"DECAY CHARACTERIZATION SUMMARY")
        print(f"{'─' * 60}{Style.RESET_ALL}\n")
        
        total = len(self.cell_database)
        
        for class_name, addresses in self.cell_classifications.items():
            count = len(addresses)
            percent = (count / total * 100) if total > 0 else 0
            
            # Color based on class
            if class_name == 'fast_decay':
                color = Fore.RED
                icon = "⚡"
            elif class_name == 'medium_decay':
                color = Fore.YELLOW
                icon = "⏱"
            elif class_name == 'slow_decay':
                color = Fore.BLUE
                icon = "🐌"
            else:
                color = Fore.GREEN
                icon = "🔒"
            
            print(f"{color}{icon} {class_name.replace('_', ' ').title()}: {count} cells ({percent:.1f}%){Style.RESET_ALL}")
            
            # Show example addresses
            if addresses:
                examples = addresses[:3]
                print(f"   Examples: {', '.join(f'0x{addr:08X}' for addr in examples)}")
    
    # ==================== PHASE 4: Partial Charge Analysis ====================
    
    def phase4_partial_charge_analysis(self, target_cells=None):
        """Detailed partial charge characterization"""
        self.display_phase_banner(4, "PARTIAL CHARGE ANALYSIS",
                                  "Exploring analog behavior at different charge levels")
        
        # Select cells to test
        if target_cells is None:
            # Get samples from each decay class
            test_cells = []
            for class_name, addresses in self.cell_classifications.items():
                if addresses:
                    test_cells.extend(addresses[:50])
        else:
            test_cells = target_cells
        
        # Define partial charge configurations
        if hasattr(self, 'min_working_burst') and self.min_working_burst <= 3:
            charge_configs = [
                {"burst": 1, "name": "Sub-threshold", "level": 0.125},
                {"burst": 2, "name": "Near-threshold", "level": 0.25},
                {"burst": 3, "name": "Threshold", "level": 0.375},
                {"burst": 4, "name": "Above-threshold", "level": 0.5},
                {"burst": 5, "name": "Mid-charge", "level": 0.625},
                {"burst": 6, "name": "High-charge", "level": 0.75},
                {"burst": 7, "name": "Near-full", "level": 0.875},
                {"burst": 8, "name": "Full-charge", "level": 1.0},
            ]
        else:
            # Use timing variations instead
            charge_configs = [
                {"burst": 8, "name": "Fast-write", "level": 0.5},
                {"burst": 8, "name": "Normal-write", "level": 0.7},
                {"burst": 8, "name": "Slow-write", "level": 0.9},
                {"burst": 8, "name": "Full-write", "level": 1.0},
            ]
        
        print(f"{Fore.CYAN}🧪 Testing {len(test_cells)} cells with {len(charge_configs)} charge levels{Style.RESET_ALL}\n")
        
        total_tests = len(test_cells) * len(charge_configs)
        current_test = 0
        
        for addr in test_cells:
            if isinstance(addr, dict):
                addr = addr['addr']
            
            cell_partial_profile = {
                'address': addr,
                'partial_charge_responses': {},
                'analog_characteristics': {}
            }
            
            # Test each partial charge level
            for config in charge_configs:
                charge_results = []
                
                # Test with different decay times
                for decay_time in [0, 5, 10, 30]:
                    # Clean slate
                    self.configure_timing(burst_len=8)
                    for _ in range(10):
                        self.write_cmd(addr, "00000000")
                    time.sleep(0.1)
                    
                    # Partial charge write
                    self.configure_timing(burst_len=config['burst'])
                    for _ in range(10):
                        self.write_cmd(addr, "FFFFFFFF")
                    time.sleep(0.1)
                    
                    # Wait for decay
                    if decay_time > 0:
                        time.sleep(decay_time)
                    
                    # Read back
                    read_data = self.read_cmd(addr)
                    
                    if read_data:
                        set_bits = bin(int(read_data, 16)).count('1')
                        charge_level = set_bits / 32.0
                        
                        charge_results.append({
                            'decay_time': decay_time,
                            'read': read_data,
                            'set_bits': set_bits,
                            'charge_level': charge_level
                        })
                
                # Reset timing
                self.configure_timing(burst_len=0)
                
                # Store results
                cell_partial_profile['partial_charge_responses'][config['name']] = charge_results
                
                # Analyze charge stability
                if charge_results:
                    charge_levels = [r['charge_level'] for r in charge_results]
                    stability = 1.0 - np.std(charge_levels) if len(charge_levels) > 1 else 1.0
                    
                    cell_partial_profile['analog_characteristics'][config['name']] = {
                        'mean_charge': np.mean(charge_levels),
                        'stability': stability,
                        'decay_sensitivity': charge_levels[0] - charge_levels[-1] if len(charge_levels) > 1 else 0
                    }
                
                current_test += 1
                self.progress_bar(current_test, total_tests, prefix="Partial Charge")
            
            # Update cell database
            if addr in self.cell_database:
                self.cell_database[addr].update(cell_partial_profile)
            else:
                self.cell_database[addr] = cell_partial_profile
            
            self.partial_charge_responses[addr] = cell_partial_profile['partial_charge_responses']
        
        print(f"\n\n{Fore.GREEN}✓ Partial charge analysis complete!{Style.RESET_ALL}")
        self.save_checkpoint()
        
        # Display analog behavior summary
        self.display_analog_summary()
    
    def display_analog_summary(self):
        """Display summary of analog behavior"""
        print(f"\n{Fore.CYAN}{'─' * 60}")
        print(f"ANALOG BEHAVIOR SUMMARY")
        print(f"{'─' * 60}{Style.RESET_ALL}\n")
        
        # Find cells with good analog behavior
        analog_cells = []
        
        for addr, profile in self.cell_database.items():
            if 'analog_characteristics' in profile:
                # Check for good analog resolution
                charge_levels = []
                for config_name, chars in profile['analog_characteristics'].items():
                    if 'mean_charge' in chars:
                        charge_levels.append(chars['mean_charge'])
                
                if len(charge_levels) >= 4:
                    # Check if we have good separation between levels
                    sorted_levels = sorted(charge_levels)
                    separations = [sorted_levels[i+1] - sorted_levels[i] for i in range(len(sorted_levels)-1)]
                    
                    if min(separations) > 0.05:  # At least 5% separation
                        analog_cells.append({
                            'addr': addr,
                            'levels': len(charge_levels),
                            'min_separation': min(separations)
                        })
        
        print(f"{Fore.GREEN}✨ Found {len(analog_cells)} cells with good analog behavior{Style.RESET_ALL}")
        
        if analog_cells:
            # Sort by number of distinguishable levels
            analog_cells.sort(key=lambda x: x['levels'], reverse=True)
            
            print(f"\nTop analog cells:")
            for i, cell in enumerate(analog_cells[:10]):
                print(f"  {i+1}. 0x{cell['addr']:08X} - {cell['levels']} levels, "
                      f"min separation: {cell['min_separation']:.1%}")
    
    # ==================== PHASE 5: Neighbor Influence Testing ====================
    
    def phase5_neighbor_influence_test(self):
        """Test how neighboring cells influence each other"""
        self.display_phase_banner(5, "NEIGHBOR INFLUENCE ANALYSIS",
                                  "Mapping inter-cell coupling effects")
        
        # Select test pairs from different decay classes
        test_pairs = []
        
        # Get cells from different classes
        for class1 in ['fast_decay', 'slow_decay']:
            if class1 in self.cell_classifications:
                cells1 = self.cell_classifications[class1][:20]
                
                for addr in cells1:
                    # Test with neighbors at different offsets
                    neighbors = [
                        addr + 0x1000,  # Next row
                        addr + 0x0001,  # Next column
                        addr + 0x1001,  # Diagonal
                    ]
                    
                    for neighbor in neighbors:
                        if neighbor in self.cell_database:
                            test_pairs.append((addr, neighbor))
        
        print(f"{Fore.CYAN}🔗 Testing {len(test_pairs)} cell pairs for coupling effects{Style.RESET_ALL}\n")
        
        for pair_idx, (addr1, addr2) in enumerate(test_pairs[:100]):  # Limit to 100 pairs
            # Test pattern: charge one cell, see effect on neighbor
            
            # First, measure baseline decay of addr2
            self.configure_timing(burst_len=8)
            for _ in range(10):
                self.write_cmd(addr2, "FFFFFFFF")
            time.sleep(0.1)
            
            time.sleep(10)  # 10 second decay
            baseline_read = self.read_cmd(addr2)
            baseline_retention = (32 - self.hamming_distance("FFFFFFFF", baseline_read)) / 32.0 if baseline_read else 0
            
            # Now test with neighbor charged
            # Clean both cells
            for _ in range(10):
                self.write_cmd(addr1, "00000000")
                self.write_cmd(addr2, "00000000")
            time.sleep(0.1)
            
            # Charge both cells
            for _ in range(10):
                self.write_cmd(addr1, "FFFFFFFF")  # Neighbor at full charge
                self.write_cmd(addr2, "FFFFFFFF")  # Test cell
            time.sleep(0.1)
            
            time.sleep(10)  # 10 second decay
            
            influenced_read = self.read_cmd(addr2)
            influenced_retention = (32 - self.hamming_distance("FFFFFFFF", influenced_read)) / 32.0 if influenced_read else 0
            
            # Calculate influence
            influence = influenced_retention - baseline_retention
            
            # Store result
            if addr2 not in self.neighbor_influence:
                self.neighbor_influence[addr2] = {}
            
            self.neighbor_influence[addr2][addr1] = {
                'baseline_retention': baseline_retention,
                'influenced_retention': influenced_retention,
                'influence_delta': influence,
                'influence_type': 'positive' if influence > 0 else 'negative' if influence < 0 else 'neutral'
            }
            
            # Reset timing
            self.configure_timing(burst_len=0)
            
            # Progress
            self.progress_bar(pair_idx + 1, min(len(test_pairs), 100), prefix="Neighbor Test")
        
        print(f"\n\n{Fore.GREEN}✓ Neighbor influence analysis complete!{Style.RESET_ALL}")
        self.save_checkpoint()
        
        # Display influence summary
        self.display_influence_summary()
    
    def display_influence_summary(self):
        """Display neighbor influence summary"""
        print(f"\n{Fore.CYAN}{'─' * 60}")
        print(f"NEIGHBOR INFLUENCE SUMMARY")
        print(f"{'─' * 60}{Style.RESET_ALL}\n")
        
        # Analyze influence patterns
        positive_influences = 0
        negative_influences = 0
        max_influence = 0
        max_influence_pair = None
        
        for addr, influences in self.neighbor_influence.items():
            for neighbor, data in influences.items():
                if data['influence_type'] == 'positive':
                    positive_influences += 1
                elif data['influence_type'] == 'negative':
                    negative_influences += 1
                
                if abs(data['influence_delta']) > max_influence:
                    max_influence = abs(data['influence_delta'])
                    max_influence_pair = (neighbor, addr)
        
        print(f"{Fore.GREEN}➕ Positive coupling: {positive_influences} pairs{Style.RESET_ALL}")
        print(f"{Fore.RED}➖ Negative coupling: {negative_influences} pairs{Style.RESET_ALL}")
        
        if max_influence_pair:
            print(f"\n{Fore.YELLOW}⚡ Strongest coupling: {max_influence:.1%} between")
            print(f"   0x{max_influence_pair[0]:08X} → 0x{max_influence_pair[1]:08X}{Style.RESET_ALL}")
    
    # ==================== Final Report Generation ====================
    
    def generate_neuromorphic_report(self):
        """Generate comprehensive neuromorphic suitability report"""
        self.display_phase_banner(6, "NEUROMORPHIC SUITABILITY REPORT",
                                  "Mapping cells to neural network components")
        
        print(f"{Fore.CYAN}{CELL_VIS}{Style.RESET_ALL}")
        
        # Analyze all data to classify cells for neuromorphic use
        neuromorphic_map = {
            'synapses': [],          # Analog, stable partial charge
            'neurons': [],           # Fast decay, good accumulation
            'memory': [],            # Slow decay, stable
            'modulators': [],        # Pattern sensitive
            'connectors': [],        # High neighbor influence
        }
        
        for addr, profile in self.cell_database.items():
            suitability_scores = {}
            
            # Score as synapse (need analog behavior)
            if 'analog_characteristics' in profile:
                analog_levels = len(profile['analog_characteristics'])
                if analog_levels >= 4:
                    suitability_scores['synapse'] = analog_levels / 8.0
            
            # Score as neuron (need fast decay)
            if profile.get('decay_class') == 'fast':
                suitability_scores['neuron'] = 0.8
            
            # Score as memory (need slow decay)
            if profile.get('decay_class') == 'slow':
                suitability_scores['memory'] = 0.8
            
            # Score as connector (neighbor influence)
            if addr in self.neighbor_influence:
                max_influence = max(abs(data['influence_delta']) 
                                  for data in self.neighbor_influence[addr].values())
                if max_influence > 0.1:
                    suitability_scores['connector'] = max_influence
            
            # Assign to best category
            if suitability_scores:
                best_use = max(suitability_scores, key=suitability_scores.get)
                best_score = suitability_scores[best_use]
                
                if best_score > 0.5:
                    if best_use == 'synapse':
                        neuromorphic_map['synapses'].append((addr, best_score))
                    elif best_use == 'neuron':
                        neuromorphic_map['neurons'].append((addr, best_score))
                    elif best_use == 'memory':
                        neuromorphic_map['memory'].append((addr, best_score))
                    elif best_use == 'connector':
                        neuromorphic_map['connectors'].append((addr, best_score))
        
        # Sort by score
        for category in neuromorphic_map:
            neuromorphic_map[category].sort(key=lambda x: x[1], reverse=True)
        
        # Display report
        print(f"\n{Fore.GREEN}{'═' * 80}")
        print(f"NEUROMORPHIC COMPONENT MAPPING")
        print(f"{'═' * 80}{Style.RESET_ALL}\n")
        
        total_suitable = sum(len(cells) for cells in neuromorphic_map.values())
        print(f"Total suitable cells: {total_suitable} / {len(self.cell_database)}")
        print(f"Neuromorphic utilization: {total_suitable/len(self.cell_database)*100:.1f}%\n")
        
        # Component breakdown
        components = [
            ('synapses', '🔗', 'Tunable weights, analog memory'),
            ('neurons', '⚡', 'Spiking units, integrate-and-fire'),
            ('memory', '💾', 'Long-term storage, slow decay'),
            ('connectors', '🔌', 'Inter-layer coupling'),
        ]
        
        for comp_name, icon, description in components:
            cells = neuromorphic_map[comp_name]
            count = len(cells)
            
            print(f"{icon} {Fore.CYAN}{comp_name.upper()}{Style.RESET_ALL}: {count} cells")
            print(f"   {description}")
            
            if cells:
                # Show top 3
                print(f"   Top cells:")
                for i, (addr, score) in enumerate(cells[:3]):
                    print(f"     {i+1}. 0x{addr:08X} (score: {score:.2f})")
            print()
        
        # Save final report
        report_data = {
            'session_id': self.session_id,
            'timestamp': datetime.now().isoformat(),
            'total_cells_tested': len(self.cell_database),
            'neuromorphic_map': {
                comp: [(f"0x{addr:08X}", float(score)) for addr, score in cells]
                for comp, cells in neuromorphic_map.items()
            },
            'cell_classifications': {
                class_name: [f"0x{addr:08X}" for addr in addresses]
                for class_name, addresses in self.cell_classifications.items()
            },
            'statistics': {
                'utilization_rate': total_suitable / len(self.cell_database) if len(self.cell_database) > 0 else 0,
                'component_counts': {comp: len(cells) for comp, cells in neuromorphic_map.items()}
            }
        }
        
        with open(self.results_dir / "neuromorphic_report.json", 'w') as f:
            json.dump(report_data, f, indent=2)
        
        # Save complete cell database
        with open(self.results_dir / "cell_database.pkl", 'wb') as f:
            pickle.dump(self.cell_database, f)
        
        print(f"{Fore.GREEN}✨ Report saved to: {self.results_dir}/")
        print(f"   • Neuromorphic mapping: neuromorphic_report.json")
        print(f"   • Complete cell database: cell_database.pkl{Style.RESET_ALL}")
        
        return neuromorphic_map
    
    def save_checkpoint(self):
        """Save current progress"""
        checkpoint_data = {
            'timestamp': datetime.now().isoformat(),
            'cell_database_size': len(self.cell_database),
            'classifications': {k: len(v) for k, v in self.cell_classifications.items()}
        }
        
        with open(self.results_dir / "checkpoint.json", 'w') as f:
            json.dump(checkpoint_data, f, indent=2)
        
        # Save cell database
        with open(self.results_dir / "cell_database_checkpoint.pkl", 'wb') as f:
            pickle.dump(self.cell_database, f)
    
    def run_complete_characterization(self):
        """Run all characterization phases"""
        print(f"{Fore.CYAN}{NEURO_BANNER}{Style.RESET_ALL}")
        
        start_time = time.time()
        
        try:
            # Phase 1: Initial tests
            burst_results = self.phase1_initial_tests()
            
            # Phase 2: Quick leaky cell discovery
            leaky_cells = self.phase2_quick_leaky_discovery()
            
            # Phase 3: Full decay characterization
            # Prioritize leaky cells but also test others
            if leaky_cells:
                self.phase3_full_decay_characterization(leaky_cells)
            else:
                self.phase3_full_decay_characterization()
            
            # Phase 4: Partial charge analysis
            self.phase4_partial_charge_analysis()
            
            # Phase 5: Neighbor influence
            self.phase5_neighbor_influence_test()
            
            # Generate final report
            neuromorphic_map = self.generate_neuromorphic_report()
            
            elapsed = time.time() - start_time
            print(f"\n{Fore.GREEN}{'═' * 80}")
            print(f"CHARACTERIZATION COMPLETE!")
            print(f"Total time: {elapsed/60:.1f} minutes")
            print(f"{'═' * 80}{Style.RESET_ALL}")
            
            return neuromorphic_map
            
        except KeyboardInterrupt:
            print(f"\n{Fore.YELLOW}⚠ Characterization interrupted by user{Style.RESET_ALL}")
            self.save_checkpoint()
            print(f"Progress saved to: {self.results_dir}/")
            raise
        except Exception as e:
            print(f"\n{Fore.RED}✗ Error during characterization: {e}{Style.RESET_ALL}")
            self.save_checkpoint()
            raise

def main():
    """Main entry point"""
    try:
        # Connect to DDR3 controller
        print(f"{Fore.CYAN}🔌 Connecting to DDR3 controller...{Style.RESET_ALL}")
        ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)
        time.sleep(0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        print(f"{Fore.GREEN}✓ Connected to {SERIAL_PORT} @ {BAUDRATE} baud{Style.RESET_ALL}")
        
        # Create profiler and run characterization
        profiler = NeuromorphicDRAMProfiler(ser)
        neuromorphic_map = profiler.run_complete_characterization()
        
        # Display final message
        print(f"\n{Fore.MAGENTA}{'🧠 ' * 10}")
        print(f"NEUROMORPHIC DRAM CHARACTERIZATION COMPLETE!")
        print(f"Your memory is ready for neural computation.")
        print(f"{'🧠 ' * 10}{Style.RESET_ALL}\n")
        
        return 0
        
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Characterization terminated by user{Style.RESET_ALL}")
        return 1
    except Exception as e:
        print(f"\n{Fore.RED}Fatal error: {e}{Style.RESET_ALL}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        if 'ser' in locals():
            ser.close()

if __name__ == "__main__":
    exit(main())
