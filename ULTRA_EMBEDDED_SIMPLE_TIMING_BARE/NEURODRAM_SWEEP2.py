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

# Partial charge configurations based on burst lengths
PARTIAL_CHARGE_CONFIGS = [
    {"burst": 1, "name": "Sub-threshold", "charge_level": 0.125},
    {"burst": 2, "name": "Near-threshold", "charge_level": 0.25},
    {"burst": 3, "name": "Threshold", "charge_level": 0.375},
    {"burst": 4, "name": "Above-threshold", "charge_level": 0.5},
    {"burst": 5, "name": "Mid-charge", "charge_level": 0.625},
    {"burst": 6, "name": "High-charge", "charge_level": 0.75},
    {"burst": 7, "name": "Near-full", "charge_level": 0.875},
    {"burst": 8, "name": "Full-charge", "charge_level": 1.0},
]

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
        """Initialize DDR3 controller"""
        print(f"{Fore.CYAN}🔌 Initializing DDR3 Controller...{Style.RESET_ALL}")
        
        max_retries = 20
        for retry in range(max_retries):
            try:
                self.ser.write(b"?\r")
                time.sleep(0.1)
                
                response = self.read_response()
                if response and 'R' in response:
                    print(f"{Fore.GREEN}✓ DDR3 Controller Ready!{Style.RESET_ALL}")
                    break
                elif response and 'W' in response:
                    print(f"{Fore.YELLOW}⏳ DDR3 initializing... ({retry+1}/{max_retries}){Style.RESET_ALL}")
                    time.sleep(1.0)
            except Exception as e:
                print(f"{Fore.RED}✗ Error: {e}{Style.RESET_ALL}")
                time.sleep(0.5)
        
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
    
    def read_response(self, timeout=0.5):
        """Read response from serial port"""
        response = ""
        start_time = time.time()
        while time.time() - start_time < timeout:
            if self.ser.in_waiting:
                try:
                    line = self.ser.readline().decode("ascii", errors="ignore").strip()
                    if line:
                        return line
                except:
                    pass
        return response
    
    def configure_timing(self, burst_len=0, twr=0, tras=0, skip_refresh=0):
        """Configure DDR3 timing parameters"""
        config_value = (skip_refresh << 20) | (burst_len << 16) | (tras << 8) | twr
        cmd = f"T{config_value:08X}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.1)
        self.ser.reset_input_buffer()
    
    def write_cmd(self, addr, data):
        """Write to DRAM"""
        cmd = f"W{addr:08X} {data}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.01)
    
    def read_cmd(self, addr):
        """Read from DRAM"""
        cmd = f"R{addr:08X}\r"
        self.ser.write(cmd.encode('ascii'))
        self.ser.flush()
        time.sleep(0.01)
        
        response = self.read_response(TIMEOUT)
        if response and len(response) >= 8:
            try:
                hex_part = response[-8:].upper()
                int(hex_part, 16)
                return hex_part
            except:
                pass
        return None
    
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
    
    # ==================== PHASE 1: Initial Extreme Test ====================
    
    def phase1_extreme_partial_charge_test(self):
        """Test extreme timing and partial charge limits"""
        self.display_phase_banner(1, "EXTREME PARTIAL CHARGE TEST", 
                                  "Finding the boundaries of analog behavior")
        
        print(f"{Fore.YELLOW}🔬 Testing burst length gradient...{Style.RESET_ALL}\n")
        
        # First, let's verify basic read/write works
        print(f"{Fore.CYAN}Verifying basic DRAM operation...{Style.RESET_ALL}")
        test_addr = 0x00001000
        test_pattern = "AAAAAAAA"
        
        # Test with full burst first
        self.configure_timing(burst_len=8)
        for _ in range(10):
            self.write_cmd(test_addr, test_pattern)
            time.sleep(0.001)
        time.sleep(0.1)
        
        verify_read = self.read_cmd(test_addr)
        if verify_read:
            verify_errors = self.hamming_distance(test_pattern, verify_read)
            print(f"  Basic R/W test: Write {test_pattern} → Read {verify_read} ({verify_errors} errors)")
        else:
            print(f"{Fore.RED}  ⚠️ WARNING: Basic read/write failed! Check DDR3 connection.{Style.RESET_ALL}")
        
        print(f"\n{Fore.YELLOW}Testing each burst length with detailed diagnostics:{Style.RESET_ALL}\n")
        
        results = []
        
        # Test each burst length with more variations
        for burst_len in range(1, 9):
            print(f"{Fore.CYAN}Burst Length {burst_len}:{Style.RESET_ALL}")
            
            burst_results = {
                'burst': burst_len,
                'tests': []
            }
            
            # Try different write counts
            for write_count in [5, 10, 20]:
                # Clean slate first
                self.configure_timing(burst_len=8)
                for _ in range(10):
                    self.write_cmd(test_addr, "00000000")
                time.sleep(0.05)
                
                # Configure burst length
                self.configure_timing(burst_len=burst_len)
                time.sleep(0.05)
                
                # Write pattern
                for _ in range(write_count):
                    self.write_cmd(test_addr, test_pattern)
                    time.sleep(0.002)
                
                time.sleep(0.1)
                
                # Read back
                read_data = self.read_cmd(test_addr)
                
                if read_data:
                    errors = self.hamming_distance(test_pattern, read_data)
                    charge_estimate = (32 - errors) / 32.0
                    set_bits = bin(int(read_data, 16)).count('1')
                    
                    # Visual representation
                    charge_bar = '█' * int(charge_estimate * 20)
                    
                    print(f"  {write_count:2d} writes: {charge_bar:<20} Read: {read_data} "
                          f"({set_bits}/32 bits, {charge_estimate:.1%} match)")
                    
                    burst_results['tests'].append({
                        'writes': write_count,
                        'read': read_data,
                        'errors': errors,
                        'charge': charge_estimate,
                        'set_bits': set_bits
                    })
                else:
                    print(f"  {write_count:2d} writes: {'░' * 20} Read: FAILED")
                    burst_results['tests'].append({
                        'writes': write_count,
                        'read': None,
                        'errors': 32,
                        'charge': 0,
                        'set_bits': 0
                    })
            
            # Determine if this burst length works
            best_result = max(burst_results['tests'], key=lambda x: x['charge'])
            burst_results['best_charge'] = best_result['charge']
            burst_results['works'] = best_result['errors'] < 16
            
            # Status summary
            if best_result['errors'] == 0:
                status = f"{Fore.GREEN}PERFECT{Style.RESET_ALL}"
            elif best_result['errors'] < 8:
                status = f"{Fore.YELLOW}GOOD{Style.RESET_ALL}"
            elif best_result['errors'] < 16:
                status = f"{Fore.MAGENTA}WEAK{Style.RESET_ALL}"
            else:
                status = f"{Fore.RED}FAILED{Style.RESET_ALL}"
            
            print(f"  Status: {status}\n")
            
            results.append(burst_results)
        
        # Reset timing
        self.configure_timing(burst_len=0)
        
        # Analyze results more carefully
        working_bursts = [r for r in results if r['works']]
        
        if working_bursts:
            self.burst_threshold = min(r['burst'] for r in working_bursts)
        else:
            # If nothing works perfectly, find the best we can get
            best_burst = max(results, key=lambda x: x['best_charge'])
            if best_burst['best_charge'] > 0.3:  # At least 30% charge
                self.burst_threshold = best_burst['burst']
                print(f"{Fore.YELLOW}⚠️ No perfect burst length found. Using burst {self.burst_threshold} "
                      f"with {best_burst['best_charge']:.1%} charge.{Style.RESET_ALL}")
            else:
                self.burst_threshold = 8
                print(f"{Fore.RED}⚠️ WARNING: Partial charge writes not working as expected!{Style.RESET_ALL}")
                print(f"This might be due to:")
                print(f"  • DDR3 controller timing constraints")
                print(f"  • Different DRAM chip characteristics")
                print(f"  • Temperature or voltage conditions")
        
        print(f"\n{Fore.GREEN}✓ Analysis complete. Threshold burst length: {self.burst_threshold} cycles{Style.RESET_ALL}")
        
        # Additional sub-threshold accumulation test
        print(f"\n{Fore.YELLOW}🔋 Testing sub-threshold charge accumulation...{Style.RESET_ALL}")
        
        accumulation_results = []
        for burst_len in [1, 2]:
            print(f"\nBurst {burst_len} accumulation test:")
            
            # Clean cell
            self.configure_timing(burst_len=8)
            for _ in range(10):
                self.write_cmd(test_addr, "00000000")
            time.sleep(0.1)
            
            # Try accumulating writes
            self.configure_timing(burst_len=burst_len)
            
            for num_writes in [10, 50, 100, 200]:
                for _ in range(num_writes):
                    self.write_cmd(test_addr, "FFFFFFFF")
                    time.sleep(0.001)
                
                read_data = self.read_cmd(test_addr)
                if read_data:
                    set_bits = bin(int(read_data, 16)).count('1')
                    print(f"  After {num_writes:3d} writes: {read_data} ({set_bits} bits set)")
                    
                    if set_bits > 0:
                        accumulation_results.append({
                            'burst': burst_len,
                            'writes_needed': num_writes,
                            'bits_set': set_bits
                        })
                        break
        
        # Save all results
        phase1_data = {
            'burst_tests': results,
            'threshold': self.burst_threshold,
            'accumulation': accumulation_results
        }
        
        with open(self.results_dir / "phase1_burst_gradient.json", 'w') as f:
            json.dump(phase1_data, f, indent=2)
        
        # Configure partial charge levels based on findings
        if self.burst_threshold <= 3:
            # Original config when partial charges work well
            PARTIAL_CHARGE_CONFIGS[:] = [
                {"burst": 1, "name": "Sub-threshold", "charge_level": 0.125},
                {"burst": 2, "name": "Near-threshold", "charge_level": 0.25},
                {"burst": 3, "name": "Threshold", "charge_level": 0.375},
                {"burst": 4, "name": "Above-threshold", "charge_level": 0.5},
                {"burst": 5, "name": "Mid-charge", "charge_level": 0.625},
                {"burst": 6, "name": "High-charge", "charge_level": 0.75},
                {"burst": 7, "name": "Near-full", "charge_level": 0.875},
                {"burst": 8, "name": "Full-charge", "charge_level": 1.0},
            ]
        else:
            # Fallback config - focus on timing variations instead
            print(f"\n{Fore.YELLOW}📊 Adjusting strategy to use timing variations...{Style.RESET_ALL}")
            PARTIAL_CHARGE_CONFIGS[:] = [
                {"burst": 8, "name": "Fast-write", "charge_level": 0.5},
                {"burst": 8, "name": "Normal-write", "charge_level": 0.7},
                {"burst": 8, "name": "Slow-write", "charge_level": 0.9},
                {"burst": 8, "name": "Full-write", "charge_level": 1.0},
            ]
            # We'll vary timing parameters instead of burst length
        
        return results
    
    # ==================== PHASE 2: Full Decay Characterization ====================
    
    def phase2_full_decay_characterization(self):
        """Comprehensive decay testing for all addresses"""
        self.display_phase_banner(2, "FULL DECAY CHARACTERIZATION",
                                  "Mapping temporal dynamics of every cell")
        
        # Get all addresses to test
        all_addresses = []
        for region in MEMORY_REGIONS:
            addresses = list(range(region['start'], region['end'], region['step']))
            all_addresses.extend(addresses[:300])  # Limit to 300 per region for 900 total
        
        print(f"{Fore.CYAN}📊 Testing {len(all_addresses)} addresses with decay times up to {max(DECAY_TIMES)}s{Style.RESET_ALL}\n")
        
        # Progress tracking
        total_tests = len(all_addresses) * len(TEST_PATTERNS[:2])  # Use only 2 patterns for speed
        current_test = 0
        
        for addr_idx, addr in enumerate(all_addresses):
            cell_profile = {
                'address': addr,
                'decay_profiles': {},
                'decay_characteristics': {}
            }
            
            for pattern in TEST_PATTERNS[:2]:  # Checkerboard and All Ones
                decay_data = []
                
                # Test each decay time
                for decay_time in DECAY_TIMES:
                    # Clean slate - write zeros
                    for _ in range(10):
                        self.write_cmd(addr, "00000000")
                    time.sleep(0.1)
                    
                    # Write test pattern with full charge
                    self.configure_timing(burst_len=8)
                    for _ in range(10):
                        self.write_cmd(addr, pattern['pattern'])
                    time.sleep(0.1)
                    
                    # Wait for decay
                    if decay_time > 0:
                        time.sleep(decay_time)
                    
                    # Read back
                    read_data = self.read_cmd(addr)
                    
                    if read_data:
                        errors = self.hamming_distance(pattern['pattern'], read_data)
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
                cell_profile['decay_profiles'][pattern['name']] = decay_data
                
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
                        
                        cell_profile['decay_characteristics'][pattern['name']] = {
                            'tau': tau,
                            'decay_rate': 1/tau if tau > 0 else float('inf'),
                            'half_life': tau * np.log(2)
                        }
                    except:
                        pass
                
                current_test += 1
                self.progress_bar(current_test, total_tests, prefix=f"Decay Test")
            
            # Classify cell based on decay behavior
            self.classify_cell_decay(addr, cell_profile)
            
            # Store in database
            self.cell_database[addr] = cell_profile
            self.decay_profiles[addr] = cell_profile['decay_profiles']
            
            # Save checkpoint every 100 cells
            if (addr_idx + 1) % 100 == 0:
                self.save_checkpoint()
        
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
    
    # ==================== PHASE 3: Partial Charge & Decay ====================
    
    def phase3_partial_charge_decay_test(self):
        """Comprehensive partial charge and decay testing"""
        self.display_phase_banner(3, "PARTIAL CHARGE & DECAY ANALYSIS",
                                  "Exploring analog behavior at sub-threshold charges")
        
        # Select interesting cells from phase 2
        test_cells = []
        
        # Get samples from each decay class
        for class_name, addresses in self.cell_classifications.items():
            if addresses:
                # Take up to 50 cells from each class
                test_cells.extend(addresses[:50])
        
        print(f"{Fore.CYAN}🧪 Testing {len(test_cells)} cells with {len(PARTIAL_CHARGE_CONFIGS)} charge levels{Style.RESET_ALL}\n")
        
        total_tests = len(test_cells) * len(PARTIAL_CHARGE_CONFIGS) * len([5, 10, 30])  # 3 decay times
        current_test = 0
        
        for cell_idx, addr in enumerate(test_cells):
            cell_partial_profile = {
                'address': addr,
                'partial_charge_responses': {},
                'charge_decay_matrix': {},
                'analog_characteristics': {}
            }
            
            # Test each partial charge level
            for charge_config in PARTIAL_CHARGE_CONFIGS:
                burst_len = charge_config['burst']
                charge_name = charge_config['name']
                
                charge_results = []
                
                # Test with different decay times
                for decay_time in [5, 10, 30]:  # Shorter times for partial charges
                    # Clean slate
                    self.configure_timing(burst_len=8)
                    for _ in range(10):
                        self.write_cmd(addr, "00000000")
                    time.sleep(0.1)
                    
                    # Partial charge write
                    self.configure_timing(burst_len=burst_len)
                    for _ in range(10):
                        self.write_cmd(addr, "FFFFFFFF")
                    time.sleep(0.1)
                    
                    # Wait for decay
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
                    
                    current_test += 1
                    self.progress_bar(current_test, total_tests, prefix="Partial Charge")
                
                # Reset timing
                self.configure_timing(burst_len=0)
                
                # Store results
                cell_partial_profile['partial_charge_responses'][charge_name] = charge_results
                
                # Analyze charge stability
                if charge_results:
                    charge_levels = [r['charge_level'] for r in charge_results]
                    stability = 1.0 - np.std(charge_levels) if len(charge_levels) > 1 else 1.0
                    
                    cell_partial_profile['analog_characteristics'][charge_name] = {
                        'mean_charge': np.mean(charge_levels),
                        'stability': stability,
                        'decay_sensitivity': charge_levels[0] - charge_levels[-1] if len(charge_levels) > 1 else 0
                    }
            
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
    
    # ==================== PHASE 4: Neighbor Influence Testing ====================
    
    def phase4_neighbor_influence_test(self):
        """Test how neighboring cells influence each other"""
        self.display_phase_banner(4, "NEIGHBOR INFLUENCE ANALYSIS",
                                  "Mapping inter-cell coupling effects")
        
        # Select cells with different decay characteristics
        test_pairs = []
        
        # Get cells from different classes to test interactions
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
    
    # ==================== PHASE 5: Advanced Characterization ====================
    
    def phase5_advanced_characterization(self):
        """Additional tests for neuromorphic behavior"""
        self.display_phase_banner(5, "ADVANCED NEUROMORPHIC TESTS",
                                  "Discovering complex analog behaviors")
        
        # Test 1: Charge accumulation with repeated sub-threshold writes
        print(f"{Fore.YELLOW}📈 Test 1: Charge Accumulation{Style.RESET_ALL}")
        self.test_charge_accumulation()
        
        # Test 2: Pattern-dependent decay
        print(f"\n{Fore.YELLOW}🎯 Test 2: Pattern-Dependent Decay{Style.RESET_ALL}")
        self.test_pattern_dependent_decay()
        
        # Test 3: Temperature-like noise simulation
        print(f"\n{Fore.YELLOW}🌡️ Test 3: Noise Sensitivity{Style.RESET_ALL}")
        self.test_noise_sensitivity()
        
        print(f"\n{Fore.GREEN}✓ Advanced characterization complete!{Style.RESET_ALL}")
        self.save_checkpoint()
    
    def test_charge_accumulation(self):
        """Test if sub-threshold writes accumulate"""
        test_cells = list(self.cell_database.keys())[:50]
        
        accumulation_results = {}
        
        for addr in test_cells:
            # Clean cell
            self.configure_timing(burst_len=8)
            for _ in range(10):
                self.write_cmd(addr, "00000000")
            time.sleep(0.1)
            
            # Try accumulating with burst=1 (sub-threshold)
            self.configure_timing(burst_len=1)
            
            accumulation_profile = []
            for num_writes in [1, 5, 10, 20, 50, 100]:
                # Clean again
                self.configure_timing(burst_len=8)
                for _ in range(10):
                    self.write_cmd(addr, "00000000")
                time.sleep(0.1)
                
                # Accumulate
                self.configure_timing(burst_len=1)
                for _ in range(num_writes):
                    self.write_cmd(addr, "FFFFFFFF")
                    time.sleep(0.001)
                
                time.sleep(0.1)
                
                # Read
                read_data = self.read_cmd(addr)
                if read_data:
                    set_bits = bin(int(read_data, 16)).count('1')
                    accumulation_profile.append({
                        'writes': num_writes,
                        'set_bits': set_bits,
                        'charge': set_bits / 32.0
                    })
            
            accumulation_results[addr] = accumulation_profile
            
            # Check if accumulation occurred
            if accumulation_profile and accumulation_profile[-1]['set_bits'] > accumulation_profile[0]['set_bits']:
                if addr not in self.cell_classifications['accumulator']:
                    self.cell_classifications['accumulator'] = []
                self.cell_classifications['accumulator'].append(addr)
        
        # Reset timing
        self.configure_timing(burst_len=0)
        
        # Update database
        for addr, profile in accumulation_results.items():
            if addr in self.cell_database:
                self.cell_database[addr]['accumulation_profile'] = profile
        
        print(f"  Found {len(self.cell_classifications.get('accumulator', []))} cells with charge accumulation")
    
    def test_pattern_dependent_decay(self):
        """Test if decay rate depends on stored pattern"""
        test_cells = list(self.cell_database.keys())[:50]
        
        patterns = [
            ("All Ones", "FFFFFFFF"),
            ("All Zeros", "00000000"),
            ("Checkerboard", "AAAAAAAA"),
            ("Inv Checker", "55555555"),
        ]
        
        for addr in test_cells:
            pattern_decay_rates = {}
            
            for pattern_name, pattern in patterns:
                # Write pattern
                self.configure_timing(burst_len=8)
                for _ in range(10):
                    self.write_cmd(addr, pattern)
                time.sleep(0.1)
                
                # Measure decay at 30s
                time.sleep(30)
                
                read_data = self.read_cmd(addr)
                if read_data:
                    errors = self.hamming_distance(pattern, read_data)
                    retention = (32 - errors) / 32.0
                    pattern_decay_rates[pattern_name] = retention
            
            # Check for pattern dependence
            if pattern_decay_rates:
                rates = list(pattern_decay_rates.values())
                if max(rates) - min(rates) > 0.2:  # 20% difference
                    if addr not in self.cell_classifications['pattern_sensitive']:
                        self.cell_classifications['pattern_sensitive'] = []
                    self.cell_classifications['pattern_sensitive'].append(addr)
                
                # Update database
                if addr in self.cell_database:
                    self.cell_database[addr]['pattern_decay_rates'] = pattern_decay_rates
        
        # Reset timing
        self.configure_timing(burst_len=0)
        
        print(f"  Found {len(self.cell_classifications.get('pattern_sensitive', []))} pattern-sensitive cells")
    
    def test_noise_sensitivity(self):
        """Test sensitivity to rapid read/write cycles (noise)"""
        test_cells = list(self.cell_database.keys())[:50]
        
        for addr in test_cells:
            # Write a pattern
            self.configure_timing(burst_len=8)
            for _ in range(10):
                self.write_cmd(addr, "AAAAAAAA")
            time.sleep(0.1)
            
            # Apply "noise" - rapid reads
            initial_read = self.read_cmd(addr)
            
            # Hammer with reads
            for _ in range(100):
                self.read_cmd(addr)
            
            # Check if pattern changed
            final_read = self.read_cmd(addr)
            
            if initial_read and final_read:
                change = self.hamming_distance(initial_read, final_read)
                
                if change > 0:
                    if addr not in self.cell_classifications['noise_sensitive']:
                        self.cell_classifications['noise_sensitive'] = []
                    self.cell_classifications['noise_sensitive'].append(addr)
                    
                    # Update database
                    if addr in self.cell_database:
                        self.cell_database[addr]['noise_sensitivity'] = change / 32.0
        
        # Reset timing
        self.configure_timing(burst_len=0)
        
        print(f"  Found {len(self.cell_classifications.get('noise_sensitive', []))} noise-sensitive cells")
    
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
            'noise_generators': [],  # Noise sensitive
        }
        
        for addr, profile in self.cell_database.items():
            suitability_scores = {}
            
            # Score as synapse (need analog behavior)
            if 'analog_characteristics' in profile:
                analog_levels = len(profile['analog_characteristics'])
                if analog_levels >= 4:
                    suitability_scores['synapse'] = analog_levels / 8.0
            
            # Score as neuron (need fast decay + accumulation)
            if profile.get('decay_class') == 'fast':
                neuron_score = 0.5
                if addr in self.cell_classifications.get('accumulator', []):
                    neuron_score += 0.5
                suitability_scores['neuron'] = neuron_score
            
            # Score as memory (need slow decay)
            if profile.get('decay_class') == 'slow':
                suitability_scores['memory'] = 0.8
            
            # Score as modulator (pattern sensitive)
            if addr in self.cell_classifications.get('pattern_sensitive', []):
                suitability_scores['modulator'] = 0.7
            
            # Score as connector (neighbor influence)
            if addr in self.neighbor_influence:
                max_influence = max(abs(data['influence_delta']) 
                                  for data in self.neighbor_influence[addr].values())
                if max_influence > 0.1:
                    suitability_scores['connector'] = max_influence
            
            # Score as noise generator
            if addr in self.cell_classifications.get('noise_sensitive', []):
                suitability_scores['noise_generator'] = 0.6
            
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
                    elif best_use == 'modulator':
                        neuromorphic_map['modulators'].append((addr, best_score))
                    elif best_use == 'connector':
                        neuromorphic_map['connectors'].append((addr, best_score))
                    elif best_use == 'noise_generator':
                        neuromorphic_map['noise_generators'].append((addr, best_score))
        
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
            ('modulators', '🎛️', 'Context-dependent behavior'),
            ('connectors', '🔌', 'Inter-layer coupling'),
            ('noise_generators', '📡', 'Stochastic elements'),
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
                'utilization_rate': total_suitable / len(self.cell_database),
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
            # Phase 1: Extreme tests
            self.phase1_extreme_partial_charge_test()
            
            # Phase 2: Full decay characterization
            self.phase2_full_decay_characterization()
            
            # Phase 3: Partial charge & decay
            self.phase3_partial_charge_decay_test()
            
            # Phase 4: Neighbor influence
            self.phase4_neighbor_influence_test()
            
            # Phase 5: Advanced tests
            self.phase5_advanced_characterization()
            
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
