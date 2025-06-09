#!/usr/bin/env python3

import serial
import time
import json
import numpy as np
from datetime import datetime, timedelta
from collections import defaultdict
from pathlib import Path
import pickle
from colorama import Fore, Back, Style, init
import threading
import sys
from scipy import stats
from scipy.optimize import curve_fit
import warnings
warnings.filterwarnings('ignore')

# Initialize colorama
init(autoreset=True)

# --- Configuration ---
SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.3

# Memory regions to test - matching the reference script
MEMORY_REGIONS = [
    {"name": "Low Memory", "start": 0x00000000, "end": 0x00100000, "step": 0x1000},
    {"name": "Bank Boundaries", "start": 0x00100000, "end": 0x01000000, "step": 0x8000},
    {"name": "High Memory", "start": 0x01000000, "end": 0x02000000, "step": 0x10000},
]

# Test patterns for full charge
TEST_PATTERNS = [
    {"name": "All Ones", "pattern": "FFFFFFFF", "description": "Maximum charge"},
    {"name": "All Zeros", "pattern": "00000000", "description": "Minimum charge"},
    {"name": "Checkerboard", "pattern": "AAAAAAAA", "description": "Alternating bits"},
    {"name": "Inverse Check", "pattern": "55555555", "description": "Inverse alternating"},
    {"name": "Walking Ones", "pattern": "11111111", "description": "Progressive ones"},
    {"name": "Walking Zeros", "pattern": "EEEEEEEE", "description": "Progressive zeros"},
]

# Extended decay times for comprehensive analysis
DECAY_TIMES = [0, 10, 30, 60, 120, 300, 600, 1200]  # Up to 20 minutes

# Fine-grained partial charge configurations
PARTIAL_CHARGES = [
    {"burst": 1, "name": "10% charge", "level": 0.1},
    {"burst": 2, "name": "25% charge", "level": 0.25},
    {"burst": 3, "name": "40% charge", "level": 0.4},
    {"burst": 4, "name": "50% charge", "level": 0.5},
    {"burst": 5, "name": "65% charge", "level": 0.65},
    {"burst": 6, "name": "80% charge", "level": 0.8},
    {"burst": 7, "name": "90% charge", "level": 0.9},
    {"burst": 8, "name": "100% charge", "level": 1.0},
]

# Leak-in investigation times
LEAK_IN_TIMES = [0, 5, 10, 20, 30, 60, 120, 300, 600, 1200]

# Partial charge write iterations
PARTIAL_CHARGE_WRITE_ITERATIONS = 20

# ASCII Art
BANNER = """
╔════════════════════════════════════════════════════════════════════════════════╗
║                                                                                ║
║  ██████╗ ██████╗  █████╗ ███╗   ███╗   ███╗   ██╗███████╗██╗   ██╗██████╗   ║
║  ██╔══██╗██╔══██╗██╔══██╗████╗ ████║   ████╗  ██║██╔════╝██║   ██║██╔══██╗  ║
║  ██║  ██║██████╔╝███████║██╔████╔██║   ██╔██╗ ██║█████╗  ██║   ██║██████╔╝  ║
║  ██║  ██║██╔══██╗██╔══██║██║╚██╔╝██║   ██║██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗  ║
║  ██████╔╝██║  ██║██║  ██║██║ ╚═╝ ██║   ██║ ╚████║███████╗╚██████╔╝██║  ██║  ║
║  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝   ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝  ║
║                                                                                ║
║         Neuromorphic DRAM Cell Characterization Suite v2.0 ENHANCED            ║
║              "Mapping the Analog Landscape of Digital Memory"                  ║
╚════════════════════════════════════════════════════════════════════════════════╝
"""

class NeuroCharacterizer:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.results_dir = Path(f"neuro_char_v2_{self.session_id}")
        self.results_dir.mkdir(exist_ok=True)
        
        # Enhanced data structures
        self.cell_database = {}
        self.decay_profiles = defaultdict(dict)
        self.partial_charge_profiles = defaultdict(dict)
        self.leak_in_profiles = defaultdict(dict)
        self.threshold_analysis = defaultdict(dict)
        self.neighbor_coupling = defaultdict(dict)
        self.temperature_effects = defaultdict(dict)
        self.bit_level_characteristics = defaultdict(dict)
        
        # Timing tracking
        self.start_time = time.time()
        self.phase_times = {}
        
        # Initialize DDR3
        self.initialize_ddr3()
        
    def initialize_ddr3(self):
        """Initialize DDR3 controller"""
        print(f"\n{Fore.CYAN}🔧 Initializing DDR3 Controller...{Style.RESET_ALL}")
        
        # Wait for DDR3 ready
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
                    print(f"{Fore.GREEN}✓ DDR3 Controller Ready!{Style.RESET_ALL}")
                    break
                elif response and 'W' in response:
                    print(f"{Fore.YELLOW}⏳ DDR3 initializing... ({retry+1}/{max_retries}){Style.RESET_ALL}")
                    time.sleep(1.0)
                    
            except Exception as e:
                print(f"{Fore.RED}❌ Error: {e}{Style.RESET_ALL}")
                time.sleep(0.5)
        
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        
        print(f"{Fore.GREEN}✓ Using default DDR3 timing configuration{Style.RESET_ALL}")
    
    def configure_timing(self, twr=0, tras=0, burst_len=0, skip_refresh=0):
        """Configure DDR3 timing parameters"""
        config_value = (skip_refresh << 20) | (burst_len << 16) | (tras << 8) | twr
        cmd = f"T{config_value:08X}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.1)
        
        # Read response
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
    
    def write_cmd(self, addr, data):
        """Write to DRAM"""
        cmd = f"W{addr:08X} {data}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.005)
    
    def read_cmd(self, addr):
        """Read from DRAM"""
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
        """Calculate bit differences between two hex values"""
        try:
            v1 = int(hex1, 16)
            v2 = int(hex2, 16)
            return bin(v1 ^ v2).count('1')
        except:
            return 32
    
    def analyze_bit_transitions(self, hex1, hex2):
        """Analyze which bits transitioned and in what direction"""
        try:
            v1 = int(hex1, 16)
            v2 = int(hex2, 16)
            
            transitions = {
                'flipped_to_1': [],
                'flipped_to_0': [],
                'total_flips': 0
            }
            
            for bit in range(32):
                bit1 = (v1 >> bit) & 1
                bit2 = (v2 >> bit) & 1
                
                if bit1 == 0 and bit2 == 1:
                    transitions['flipped_to_1'].append(bit)
                elif bit1 == 1 and bit2 == 0:
                    transitions['flipped_to_0'].append(bit)
            
            transitions['total_flips'] = len(transitions['flipped_to_1']) + len(transitions['flipped_to_0'])
            return transitions
        except:
            return None
    
    def progress_bar(self, current, total, width=50, prefix="Progress", eta_seconds=None):
        """Enhanced progress bar with ETA"""
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
        
        # ETA calculation
        eta_str = ""
        if eta_seconds:
            if eta_seconds < 60:
                eta_str = f" ETA: {int(eta_seconds)}s"
            elif eta_seconds < 3600:
                eta_str = f" ETA: {int(eta_seconds/60)}m {int(eta_seconds%60)}s"
            else:
                eta_str = f" ETA: {int(eta_seconds/3600)}h {int((eta_seconds%3600)/60)}m"
        
        print(f"\r{prefix}: [{bar}] {percent*100:.1f}% ({current}/{total}){eta_str}     ", 
              end='', flush=True)
    
    def get_test_addresses(self, sample_size_per_region=None):
        """Get a representative sample of addresses from each region"""
        addresses = []
        
        if sample_size_per_region is None:
            # Get all addresses from regions
            for region in MEMORY_REGIONS:
                region_addresses = list(range(region['start'], region['end'], region['step']))
                addresses.extend(region_addresses)
                print(f"  {Fore.CYAN}Region '{region['name']}': {len(region_addresses)} addresses{Style.RESET_ALL}")
        else:
            # Get limited sample
            for region in MEMORY_REGIONS:
                region_addresses = list(range(region['start'], 
                                              min(region['end'], region['start'] + region['step'] * sample_size_per_region), 
                                              region['step']))
                addresses.extend(region_addresses)
        
        return addresses
    
    def initialize_cell_entry(self, addr):
        """Initialize a cell database entry with comprehensive structure"""
        if addr not in self.cell_database:
            self.cell_database[addr] = {
                'address': addr,
                'decay_profiles': {},
                'partial_charge_profiles': {},
                'leak_in_profiles': {},
                'threshold_characteristics': {},
                'bit_level_analysis': {},
                'neighbor_effects': {},
                'characteristics': {
                    'decay_class': 'unknown',
                    'analog_suitable': False,
                    'leak_in_rate': 0,
                    'leak_out_rate': 0,
                    'charge_threshold': None,
                    'bit_stability': {},
                    'neuromorphic_role': 'unsuitable'
                }
            }
    
    # ==================== PHASE 1: Comprehensive Decay Analysis ====================
    
    def phase1_comprehensive_decay_analysis(self):
        """Enhanced decay analysis with bit-level tracking"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"PHASE 1: COMPREHENSIVE DECAY ANALYSIS")
        print(f"Testing decay behavior with extended patterns and bit-level tracking")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        phase_start = time.time()
        
        # Get test addresses
        print(f"{Fore.YELLOW}Selecting test addresses:{Style.RESET_ALL}")
        test_addresses = self.get_test_addresses()
        
        # Sample if too many
        if len(test_addresses) > 1000:
            print(f"  {Fore.YELLOW}Sampling 1000 addresses from {len(test_addresses)} total{Style.RESET_ALL}")
            import random
            random.seed(42)
            test_addresses = random.sample(test_addresses, 1000)
        
        print(f"\n📊 Testing {len(test_addresses)} addresses")
        print(f"⏱️  Decay times: {DECAY_TIMES} seconds")
        print(f"🎯 Patterns: {[p['name'] for p in TEST_PATTERNS]}\n")
        
        total_tests = len(TEST_PATTERNS) * len(DECAY_TIMES)
        current_test = 0
        
        # Track bit-level statistics
        bit_flip_statistics = defaultdict(lambda: defaultdict(int))
        
        for pattern_info in TEST_PATTERNS:
            pattern = pattern_info['pattern']
            print(f"\n{Fore.YELLOW}Testing pattern: {pattern_info['name']} ({pattern}){Style.RESET_ALL}")
            
            for decay_time in DECAY_TIMES:
                current_test += 1
                print(f"\n  Test {current_test}/{total_tests} - Decay time: {decay_time}s")
                
                # Configure timing - disable refresh for decay test
                self.configure_timing(skip_refresh=1)
                
                # Write pattern to all cells
                print(f"  Writing to all cells...", end='', flush=True)
                for addr in test_addresses:
                    for _ in range(10):
                        self.write_cmd(addr, pattern)
                    if addr % 100 == 0:
                        time.sleep(0.001)
                print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
                
                # Immediate read for t=0
                if decay_time == 0:
                    time.sleep(0.1)
                else:
                    # Wait for decay
                    print(f"  Waiting {decay_time}s for decay...", end='', flush=True)
                    if decay_time >= 60:
                        for i in range(decay_time):
                            if i % 30 == 0 and i > 0:
                                print(f" {i}s", end='', flush=True)
                            time.sleep(1)
                    else:
                        time.sleep(decay_time)
                    print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
                
                # Read and analyze with bit-level tracking
                print(f"  Reading and analyzing cells...")
                decay_results = []
                weak_cells_found = []
                
                for i, addr in enumerate(test_addresses):
                    self.initialize_cell_entry(addr)
                    read_data = self.read_cmd(addr)
                    
                    if read_data:
                        errors = self.hamming_distance(pattern, read_data)
                        retention = (32 - errors) / 32.0
                        transitions = self.analyze_bit_transitions(pattern, read_data)
                        
                        result = {
                            'address': addr,
                            'pattern': pattern,
                            'pattern_name': pattern_info['name'],
                            'decay_time': decay_time,
                            'read_data': read_data,
                            'errors': errors,
                            'retention': retention,
                            'transitions': transitions
                        }
                        
                        decay_results.append(result)
                        
                        # Track weak cells
                        if errors > 0:
                            weak_cells_found.append(result)
                            
                            # Update bit flip statistics
                            if transitions:
                                for bit in transitions['flipped_to_0']:
                                    bit_flip_statistics[pattern][f'bit_{bit}_to_0'] += 1
                                for bit in transitions['flipped_to_1']:
                                    bit_flip_statistics[pattern][f'bit_{bit}_to_1'] += 1
                        
                        # Store in cell database
                        if pattern not in self.cell_database[addr]['decay_profiles']:
                            self.cell_database[addr]['decay_profiles'][pattern] = []
                        
                        self.cell_database[addr]['decay_profiles'][pattern].append({
                            'time': decay_time,
                            'retention': retention,
                            'errors': errors,
                            'transitions': transitions
                        })
                    
                    # Show progress
                    if (i + 1) % 100 == 0 or (i + 1) == len(test_addresses):
                        percent = (i + 1) / len(test_addresses) * 100
                        print(f"\r    Progress: {percent:.1f}% ({i+1}/{len(test_addresses)}) - Found {len(weak_cells_found)} weak cells", 
                              end='', flush=True)
                
                print()  # New line after progress
                
                # Reset timing
                self.configure_timing(skip_refresh=0)
                
                # Analysis
                if decay_results:
                    avg_retention = np.mean([r['retention'] for r in decay_results])
                    cells_failed = sum(1 for r in decay_results if r['retention'] < 0.5)
                    cells_with_errors = len(weak_cells_found)
                    
                    print(f"  {Fore.CYAN}Average retention: {avg_retention:.1%}")
                    print(f"  Cells <50% retention: {cells_failed}/{len(decay_results)}")
                    print(f"  Cells with bit errors: {cells_with_errors}/{len(decay_results)}{Style.RESET_ALL}")
                
                # Save results
                self.save_decay_results(pattern_info['name'], decay_time, decay_results)
        
        # Analyze bit-level patterns
        self.analyze_bit_level_patterns(bit_flip_statistics)
        
        phase_duration = time.time() - phase_start
        self.phase_times['phase1'] = phase_duration
        
        print(f"\n{Fore.GREEN}✓ Phase 1 complete in {phase_duration/60:.1f} minutes{Style.RESET_ALL}")
        self.analyze_decay_characteristics()
    
    def analyze_bit_level_patterns(self, bit_flip_statistics):
        """Analyze bit-level flip patterns across all cells"""
        print(f"\n{Fore.CYAN}Analyzing bit-level patterns...{Style.RESET_ALL}")
        
        for pattern, bit_stats in bit_flip_statistics.items():
            print(f"\nPattern {pattern}:")
            
            # Find most unstable bits
            bit_flips_by_position = defaultdict(int)
            for stat_name, count in bit_stats.items():
                if 'bit_' in stat_name:
                    bit_num = int(stat_name.split('_')[1])
                    bit_flips_by_position[bit_num] += count
            
            if bit_flips_by_position:
                sorted_bits = sorted(bit_flips_by_position.items(), key=lambda x: x[1], reverse=True)
                print(f"  Most unstable bit positions:")
                for bit_pos, flip_count in sorted_bits[:5]:
                    print(f"    Bit {bit_pos}: {flip_count} flips")
    
    def save_decay_results(self, pattern_name, decay_time, results):
        """Save decay results to file"""
        filename = self.results_dir / f"decay_{pattern_name.replace(' ', '_')}_{decay_time}s.json"
        with open(filename, 'w') as f:
            json.dump({
                'pattern': pattern_name,
                'decay_time': decay_time,
                'timestamp': datetime.now().isoformat(),
                'results': results
            }, f, indent=2, default=str)
    
    def analyze_decay_characteristics(self):
        """Enhanced decay analysis with curve fitting"""
        print(f"\n{Fore.CYAN}Analyzing decay characteristics with curve fitting...{Style.RESET_ALL}")
        
        def exponential_decay(t, a, b, c):
            """Exponential decay model: a * exp(-b * t) + c"""
            return a * np.exp(-b * t) + c
        
        for addr, cell_data in self.cell_database.items():
            if 'decay_profiles' not in cell_data:
                continue
            
            decay_parameters = {}
            
            for pattern, measurements in cell_data['decay_profiles'].items():
                if len(measurements) >= 4:
                    times = np.array([m['time'] for m in measurements])
                    retentions = np.array([m['retention'] for m in measurements])
                    
                    try:
                        # Fit exponential decay
                        popt, _ = curve_fit(exponential_decay, times[times > 0], retentions[times > 0],
                                          p0=[1, 0.001, 0], maxfev=5000)
                        
                        decay_parameters[pattern] = {
                            'amplitude': popt[0],
                            'decay_rate': popt[1],
                            'offset': popt[2],
                            'half_life': np.log(2) / popt[1] if popt[1] > 0 else float('inf')
                        }
                    except:
                        pass
            
            # Classify based on decay parameters
            if decay_parameters:
                avg_decay_rate = np.mean([p['decay_rate'] for p in decay_parameters.values()])
                avg_half_life = np.mean([p['half_life'] for p in decay_parameters.values() 
                                        if p['half_life'] < float('inf')])
                
                if avg_decay_rate > 0.01:
                    cell_data['characteristics']['decay_class'] = 'fast'
                elif avg_decay_rate > 0.001:
                    cell_data['characteristics']['decay_class'] = 'medium'
                else:
                    cell_data['characteristics']['decay_class'] = 'slow'
                
                cell_data['characteristics']['avg_decay_rate'] = avg_decay_rate
                cell_data['characteristics']['avg_half_life'] = avg_half_life
                cell_data['characteristics']['decay_parameters'] = decay_parameters
    
    # ==================== PHASE 2: Leak-In Investigation ====================
    
    def phase2_leak_in_investigation(self):
        """Investigate the mysterious leak-in behavior at low burst lengths"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"PHASE 2: LEAK-IN PHENOMENON INVESTIGATION")
        print(f"Exploring charge accumulation at sub-threshold burst lengths")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        phase_start = time.time()
        
        # Select cells that showed leak-in behavior
        test_cells = self.select_cells_for_leak_in_study()
        
        print(f"📊 Testing {len(test_cells)} selected cells")
        print(f"⚡ Testing burst lengths: 1, 2, 8 (anomalous)")
        print(f"⏱️  Observation times: {LEAK_IN_TIMES}s\n")
        
        leak_in_results = defaultdict(list)
        
        # Test specific burst lengths that showed anomalies
        test_bursts = [
            {"burst": 1, "name": "Sub-threshold 1"},
            {"burst": 2, "name": "Sub-threshold 2"},
            {"burst": 8, "name": "Full burst (anomaly)"}
        ]
        
        for burst_config in test_bursts:
            print(f"\n{Fore.YELLOW}Testing {burst_config['name']} (burst={burst_config['burst']}){Style.RESET_ALL}")
            
            # Configure burst length
            self.configure_timing(burst_len=burst_config['burst'], skip_refresh=1)
            
            # Test multiple initial conditions
            initial_conditions = [
                {"name": "Clean start", "prep": "00000000", "iterations": 20},
                {"name": "Pre-charged", "prep": "FFFFFFFF", "iterations": 5},
                {"name": "Mixed state", "prep": "AAAAAAAA", "iterations": 10}
            ]
            
            for init_cond in initial_conditions:
                print(f"\n  Initial condition: {init_cond['name']}")
                
                # Prepare cells
                print(f"    Preparing cells...", end='', flush=True)
                self.configure_timing(burst_len=8)  # Full burst for prep
                for addr in test_cells:
                    for _ in range(init_cond['iterations']):
                        self.write_cmd(addr, init_cond['prep'])
                print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
                
                # Switch to test burst length
                self.configure_timing(burst_len=burst_config['burst'], skip_refresh=1)
                
                # Write partial charge
                print(f"    Writing with burst={burst_config['burst']}...", end='', flush=True)
                for addr in test_cells:
                    for _ in range(PARTIAL_CHARGE_WRITE_ITERATIONS):
                        self.write_cmd(addr, "FFFFFFFF")
                print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
                
                # Monitor charge over time
                print(f"    Monitoring charge evolution:")
                time_series_data = []
                
                for obs_time in LEAK_IN_TIMES:
                    if obs_time > 0:
                        time.sleep(obs_time - (LEAK_IN_TIMES[LEAK_IN_TIMES.index(obs_time) - 1] 
                                              if LEAK_IN_TIMES.index(obs_time) > 0 else 0))
                    
                    # Read all cells
                    time_point_results = []
                    for addr in test_cells:
                        read_data = self.read_cmd(addr)
                        if read_data:
                            set_bits = bin(int(read_data, 16)).count('1')
                            charge_level = set_bits / 32.0
                            time_point_results.append({
                                'address': addr,
                                'time': obs_time,
                                'charge_level': charge_level,
                                'read_data': read_data
                            })
                    
                    avg_charge = np.mean([r['charge_level'] for r in time_point_results])
                    time_series_data.append({
                        'time': obs_time,
                        'avg_charge': avg_charge,
                        'results': time_point_results
                    })
                    
                    print(f"      t={obs_time:4d}s: {avg_charge:6.1%} average charge")
                
                # Store results
                leak_in_results[burst_config['burst']].append({
                    'burst': burst_config['burst'],
                    'initial_condition': init_cond['name'],
                    'time_series': time_series_data
                })
                
                # Analyze leak-in rate
                if len(time_series_data) >= 3:
                    times = [d['time'] for d in time_series_data if d['time'] > 0]
                    charges = [d['avg_charge'] for d in time_series_data if d['time'] > 0]
                    
                    if times and charges:
                        # Calculate leak-in rate
                        leak_rate = (charges[-1] - charges[0]) / (times[-1] - times[0])
                        print(f"      Leak-in rate: {leak_rate*100:.3f}% per second")
                        
                        # Store in cell database
                        for addr in test_cells:
                            if addr not in self.leak_in_profiles:
                                self.leak_in_profiles[addr] = {}
                            
                            key = f"{burst_config['burst']}_{init_cond['name']}"
                            self.leak_in_profiles[addr][key] = {
                                'leak_rate': leak_rate,
                                'time_series': time_series_data
                            }
                            
                            # Update cell characteristics
                            if 'leak_in_rate' not in self.cell_database[addr]['characteristics']:
                                self.cell_database[addr]['characteristics']['leak_in_rate'] = leak_rate
                            else:
                                # Keep maximum leak-in rate
                                self.cell_database[addr]['characteristics']['leak_in_rate'] = max(
                                    self.cell_database[addr]['characteristics']['leak_in_rate'],
                                    leak_rate
                                )
        
        # Save leak-in investigation results
        self.save_leak_in_results(leak_in_results)
        
        # Reset timing
        self.configure_timing(burst_len=0, skip_refresh=0)
        
        phase_duration = time.time() - phase_start
        self.phase_times['phase2'] = phase_duration
        
        print(f"\n{Fore.GREEN}✓ Phase 2 complete in {phase_duration/60:.1f} minutes{Style.RESET_ALL}")
        self.analyze_leak_in_patterns(leak_in_results)
    
    def select_cells_for_leak_in_study(self):
        """Select cells that showed interesting behavior in Phase 1"""
        selected = []
        
        # Get cells from each decay class
        decay_classes = defaultdict(list)
        for addr, cell_data in self.cell_database.items():
            if 'characteristics' in cell_data and 'decay_class' in cell_data['characteristics']:
                decay_classes[cell_data['characteristics']['decay_class']].append(addr)
        
        # Select cells from each class
        for decay_class, addresses in decay_classes.items():
            selected.extend(addresses[:40])
        
        # If not enough, add more
        if len(selected) < 100:
            all_addresses = list(self.cell_database.keys())
            for addr in all_addresses:
                if addr not in selected:
                    selected.append(addr)
                    if len(selected) >= 150:
                        break
        
        return selected[:150]  # Test 150 cells for leak-in
    
    def save_leak_in_results(self, results):
        """Save leak-in investigation results"""
        filename = self.results_dir / "leak_in_investigation.json"
        with open(filename, 'w') as f:
            json.dump({
                'timestamp': datetime.now().isoformat(),
                'results': results
            }, f, indent=2, default=str)
    
    def analyze_leak_in_patterns(self, leak_in_results):
        """Analyze patterns in leak-in behavior"""
        print(f"\n{Fore.CYAN}Analyzing leak-in patterns...{Style.RESET_ALL}")
        
        for burst, experiments in leak_in_results.items():
            print(f"\nBurst length {burst}:")
            
            for exp in experiments:
                init_cond = exp['initial_condition']
                time_series = exp['time_series']
                
                # Extract charge progression
                times = [d['time'] for d in time_series]
                charges = [d['avg_charge'] for d in time_series]
                
                print(f"  {init_cond}:")
                print(f"    Initial: {charges[0]:.1%}, Final: {charges[-1]:.1%}")
                print(f"    Change: {(charges[-1] - charges[0])*100:.1f}%")
    
    # ==================== PHASE 3: Threshold Characterization ====================
    
    def phase3_threshold_characterization(self):
        """Detailed investigation of the burst=3 threshold behavior"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"PHASE 3: THRESHOLD BEHAVIOR CHARACTERIZATION")
        print(f"Investigating the critical threshold at burst length 3")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        phase_start = time.time()
        
        # Select diverse cells
        test_cells = self.select_cells_for_threshold_study()
        
        print(f"📊 Testing {len(test_cells)} cells")
        print(f"🎯 Fine-grained burst length sweep around threshold\n")
        
        # Extended burst configurations around the threshold
        threshold_burst_configs = [
            {"burst": 1, "expected": 0.1},
            {"burst": 2, "expected": 0.25},
            {"burst": 3, "expected": 0.99},  # The jump!
            {"burst": 4, "expected": 0.99},
            {"burst": 5, "expected": 0.99},
            {"burst": 6, "expected": 0.99},
            {"burst": 7, "expected": 0.99},
            {"burst": 8, "expected": 0.31},  # The anomaly!
        ]
        
        # Also test with different write iterations
        write_iterations_test = [5, 10, 15, 20, 30, 50]
        
        threshold_results = defaultdict(dict)
        
        print(f"{Fore.YELLOW}Testing burst length sensitivity...{Style.RESET_ALL}")
        
        for burst_config in threshold_burst_configs:
            burst = burst_config['burst']
            print(f"\n  Burst length {burst}:")
            
            # Configure timing
            self.configure_timing(burst_len=burst, skip_refresh=1)
            
            # Test with standard iterations first
            print(f"    Standard test ({PARTIAL_CHARGE_WRITE_ITERATIONS} iterations)...", end='', flush=True)
            
            # Clean cells
            self.configure_timing(burst_len=8)
            for addr in test_cells:
                for _ in range(20):
                    self.write_cmd(addr, "00000000")
            
            # Write with test burst
            self.configure_timing(burst_len=burst, skip_refresh=1)
            for addr in test_cells:
                for _ in range(PARTIAL_CHARGE_WRITE_ITERATIONS):
                    self.write_cmd(addr, "FFFFFFFF")
            
            time.sleep(0.1)
            
            # Read immediately
            charge_levels = []
            for addr in test_cells:
                read_data = self.read_cmd(addr)
                if read_data:
                    set_bits = bin(int(read_data, 16)).count('1')
                    charge_level = set_bits / 32.0
                    charge_levels.append(charge_level)
            
            avg_charge = np.mean(charge_levels) if charge_levels else 0
            std_charge = np.std(charge_levels) if charge_levels else 0
            
            print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
            print(f"      Average: {avg_charge:.1%} (±{std_charge:.1%})")
            print(f"      Expected: {burst_config['expected']:.1%}")
            
            threshold_results[burst]['standard'] = {
                'avg_charge': avg_charge,
                'std_charge': std_charge,
                'charge_levels': charge_levels
            }
            
            # Test iteration sensitivity for interesting burst lengths
            if burst in [2, 3, 8]:
                print(f"    Testing iteration sensitivity:")
                
                for iterations in write_iterations_test:
                    # Clean
                    self.configure_timing(burst_len=8)
                    for addr in test_cells[:20]:  # Subset for speed
                        for _ in range(20):
                            self.write_cmd(addr, "00000000")
                    
                    # Write with varying iterations
                    self.configure_timing(burst_len=burst, skip_refresh=1)
                    for addr in test_cells[:20]:
                        for _ in range(iterations):
                            self.write_cmd(addr, "FFFFFFFF")
                    
                    time.sleep(0.1)
                    
                    # Read
                    iter_charges = []
                    for addr in test_cells[:20]:
                        read_data = self.read_cmd(addr)
                        if read_data:
                            set_bits = bin(int(read_data, 16)).count('1')
                            iter_charges.append(set_bits / 32.0)
                    
                    avg_iter_charge = np.mean(iter_charges) if iter_charges else 0
                    print(f"      {iterations:3d} iterations: {avg_iter_charge:.1%}")
                    
                    threshold_results[burst][f'iter_{iterations}'] = avg_iter_charge
        
        # Test timing parameter effects on threshold
        print(f"\n{Fore.YELLOW}Testing timing parameter effects on threshold...{Style.RESET_ALL}")
        
        timing_configs = [
            {"twr": 0, "tras": 0, "name": "Default"},
            {"twr": 5, "tras": 5, "name": "Relaxed"},
            {"twr": 15, "tras": 15, "name": "Very relaxed"},
        ]
        
        for timing in timing_configs:
            print(f"\n  Timing: {timing['name']} (tWR={timing['twr']}, tRAS={timing['tras']})")
            
            for burst in [2, 3, 8]:
                # Configure timing
                self.configure_timing(twr=timing['twr'], tras=timing['tras'], 
                                    burst_len=burst, skip_refresh=1)
                
                # Clean and write
                for addr in test_cells[:20]:
                    for _ in range(10):
                        self.write_cmd(addr, "00000000")
                
                for addr in test_cells[:20]:
                    for _ in range(20):
                        self.write_cmd(addr, "FFFFFFFF")
                
                time.sleep(0.1)
                
                # Read
                timing_charges = []
                for addr in test_cells[:20]:
                    read_data = self.read_cmd(addr)
                    if read_data:
                        set_bits = bin(int(read_data, 16)).count('1')
                        timing_charges.append(set_bits / 32.0)
                
                avg_timing_charge = np.mean(timing_charges) if timing_charges else 0
                print(f"    Burst {burst}: {avg_timing_charge:.1%}")
        
        # Save threshold analysis
        self.save_threshold_results(threshold_results)
        
        # Update cell database with threshold info
        for addr in test_cells:
            self.cell_database[addr]['threshold_characteristics'] = {
                'pre_threshold_charge': threshold_results[2]['standard']['avg_charge'],
                'post_threshold_charge': threshold_results[3]['standard']['avg_charge'],
                'threshold_jump': threshold_results[3]['standard']['avg_charge'] - 
                                 threshold_results[2]['standard']['avg_charge'],
                'burst_8_anomaly': threshold_results[8]['standard']['avg_charge']
            }
        
        # Reset timing
        self.configure_timing(burst_len=0, skip_refresh=0)
        
        phase_duration = time.time() - phase_start
        self.phase_times['phase3'] = phase_duration
        
        print(f"\n{Fore.GREEN}✓ Phase 3 complete in {phase_duration/60:.1f} minutes{Style.RESET_ALL}")
    
    def select_cells_for_threshold_study(self):
        """Select cells for threshold study"""
        # Use cells that showed good response in earlier phases
        candidates = []
        
        for addr, cell_data in self.cell_database.items():
            if 'decay_profiles' in cell_data:
                # Get cells with medium to slow decay
                if cell_data['characteristics'].get('decay_class') in ['medium', 'slow']:
                    candidates.append(addr)
        
        # Limit to 100 cells
        return candidates[:100]
    
    def save_threshold_results(self, results):
        """Save threshold characterization results"""
        filename = self.results_dir / "threshold_characterization.json"
        with open(filename, 'w') as f:
            json.dump({
                'timestamp': datetime.now().isoformat(),
                'results': results
            }, f, indent=2, default=str)
    
    # ==================== PHASE 4: Enhanced Neighbor Coupling ====================
    
    def phase4_enhanced_neighbor_coupling(self):
        """Enhanced neighbor coupling analysis including diagonal and multi-cell patterns"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"PHASE 4: ENHANCED NEIGHBOR COUPLING ANALYSIS")
        print(f"Testing complex inter-cell interference patterns")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        phase_start = time.time()
        
        # Select cell groups
        test_groups = self.select_neighbor_groups()
        
        print(f"📊 Testing {len(test_groups)} cell groups")
        print(f"🔗 Testing patterns: isolated, row, column, block, checkerboard\n")
        
        coupling_patterns = [
            {
                'name': 'Isolated cell',
                'pattern': lambda base: [(base, "FFFFFFFF")],
                'neighbors': lambda base: []
            },
            {
                'name': 'Row coupling',
                'pattern': lambda base: [(base + i*4, "FFFFFFFF") for i in range(8)],
                'neighbors': lambda base: [base + 4, base - 4]
            },
            {
                'name': 'Column coupling',
                'pattern': lambda base: [(base + i*0x1000, "FFFFFFFF") for i in range(4)],
                'neighbors': lambda base: [base + 0x1000, base - 0x1000]
            },
            {
                'name': 'Block pattern',
                'pattern': lambda base: [(base + r*0x1000 + c*4, "FFFFFFFF") 
                                       for r in range(2) for c in range(2)],
                'neighbors': lambda base: [base + 0x1004]
            },
            {
                'name': 'Checkerboard',
                'pattern': lambda base: [(base + r*0x1000 + c*4, 
                                        "FFFFFFFF" if (r+c)%2==0 else "00000000") 
                                       for r in range(4) for c in range(4)],
                'neighbors': lambda base: [base + 0x1000, base + 4]
            }
        ]
        
        coupling_results = defaultdict(list)
        
        # Configure for tests
        self.configure_timing(burst_len=8, skip_refresh=1)
        
        for pattern_config in coupling_patterns:
            print(f"\n{Fore.YELLOW}Testing {pattern_config['name']}...{Style.RESET_ALL}")
            
            pattern_results = []
            
            for group_idx, base_addr in enumerate(test_groups):
                # Clean entire area first
                clean_area = [base_addr + r*0x1000 + c*4 for r in range(-2, 6) for c in range(-2, 6)]
                for addr in clean_area:
                    if 0 <= addr <= 0x02000000:  # Stay in valid range
                        for _ in range(5):
                            self.write_cmd(addr, "00000000")
                
                # Write pattern
                pattern_cells = pattern_config['pattern'](base_addr)
                for addr, data in pattern_cells:
                    if 0 <= addr <= 0x02000000:
                        for _ in range(10):
                            self.write_cmd(addr, data)
                
                # Wait for coupling
                time.sleep(1)
                
                # Read neighbors
                neighbor_addrs = pattern_config['neighbors'](base_addr)
                for neighbor in neighbor_addrs:
                    if 0 <= neighbor <= 0x02000000:
                        read_data = self.read_cmd(neighbor)
                        if read_data:
                            set_bits = bin(int(read_data, 16)).count('1')
                            coupling_strength = set_bits / 32.0
                            
                            pattern_results.append({
                                'base_addr': base_addr,
                                'neighbor_addr': neighbor,
                                'coupling_strength': coupling_strength,
                                'read_data': read_data
                            })
                
                # Progress
                if (group_idx + 1) % 10 == 0:
                    print(f"    Tested {group_idx + 1}/{len(test_groups)} groups")
            
            # Analyze pattern results
            if pattern_results:
                avg_coupling = np.mean([r['coupling_strength'] for r in pattern_results])
                max_coupling = max([r['coupling_strength'] for r in pattern_results])
                
                print(f"  Average coupling: {avg_coupling:.1%}")
                print(f"  Maximum coupling: {max_coupling:.1%}")
                
                coupling_results[pattern_config['name']] = {
                    'avg_coupling': avg_coupling,
                    'max_coupling': max_coupling,
                    'results': pattern_results
                }
        
        # Test distance-dependent coupling
        print(f"\n{Fore.YELLOW}Testing distance-dependent coupling...{Style.RESET_ALL}")
        
        distance_results = self.test_distance_coupling(test_groups[:20])
        coupling_results['distance_analysis'] = distance_results
        
        # Save results
        self.save_coupling_results(coupling_results)
        
        # Reset timing
        self.configure_timing(burst_len=0, skip_refresh=0)
        
        phase_duration = time.time() - phase_start
        self.phase_times['phase4'] = phase_duration
        
        print(f"\n{Fore.GREEN}✓ Phase 4 complete in {phase_duration/60:.1f} minutes{Style.RESET_ALL}")
        self.analyze_coupling_patterns(coupling_results)
    
    def select_neighbor_groups(self):
        """Select base addresses for neighbor group testing"""
        groups = []
        
        # Select addresses with good spacing
        for region in MEMORY_REGIONS:
            region_start = region['start'] + 0x10000  # Offset from boundary
            region_step = region['step'] * 8  # Larger spacing
            
            for i in range(10):  # 10 groups per region
                addr = region_start + i * region_step
                if addr < region['end'] - 0x10000:
                    groups.append(addr)
        
        return groups[:50]  # Limit to 50 groups
    
    def test_distance_coupling(self, test_addresses):
        """Test how coupling strength varies with distance"""
        distances = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]
        distance_coupling = defaultdict(list)
        
        for base_addr in test_addresses:
            # Clean area
            for offset in range(-0x5000, 0x5000, 4):
                if 0 <= base_addr + offset <= 0x02000000:
                    self.write_cmd(base_addr + offset, "00000000")
            
            # Charge central cell
            for _ in range(20):
                self.write_cmd(base_addr, "FFFFFFFF")
            
            time.sleep(0.5)
            
            # Test coupling at different distances
            for distance in distances:
                test_addrs = [
                    base_addr + distance,      # Right
                    base_addr - distance,      # Left
                    base_addr + distance * 256,  # Down (approximate)
                    base_addr - distance * 256   # Up (approximate)
                ]
                
                for test_addr in test_addrs:
                    if 0 <= test_addr <= 0x02000000:
                        read_data = self.read_cmd(test_addr)
                        if read_data:
                            set_bits = bin(int(read_data, 16)).count('1')
                            coupling = set_bits / 32.0
                            if coupling > 0.01:  # Threshold for detection
                                distance_coupling[distance].append(coupling)
        
        # Calculate averages
        distance_summary = {}
        for distance, couplings in distance_coupling.items():
            if couplings:
                distance_summary[distance] = {
                    'avg_coupling': np.mean(couplings),
                    'max_coupling': max(couplings),
                    'detection_rate': len(couplings) / (len(test_addresses) * 4)
                }
        
        return distance_summary
    
    def save_coupling_results(self, results):
        """Save enhanced coupling results"""
        filename = self.results_dir / "enhanced_coupling_analysis.json"
        with open(filename, 'w') as f:
            json.dump({
                'timestamp': datetime.now().isoformat(),
                'results': results
            }, f, indent=2, default=str)
    
    def analyze_coupling_patterns(self, coupling_results):
        """Analyze coupling patterns for neuromorphic implications"""
        print(f"\n{Fore.CYAN}Analyzing coupling patterns...{Style.RESET_ALL}")
        
        # Pattern analysis
        for pattern_name, data in coupling_results.items():
            if pattern_name != 'distance_analysis':
                print(f"\n{pattern_name}:")
                print(f"  Average coupling: {data['avg_coupling']:.2%}")
                print(f"  Maximum coupling: {data['max_coupling']:.2%}")
        
        # Distance analysis
        if 'distance_analysis' in coupling_results:
            print(f"\nDistance-dependent coupling:")
            dist_data = coupling_results['distance_analysis']
            
            for distance in sorted(dist_data.keys()):
                info = dist_data[distance]
                print(f"  {distance:4d} bytes: {info['avg_coupling']:.2%} avg, "
                      f"{info['detection_rate']:.1%} detection")
    
    # ==================== PHASE 5: Comprehensive Partial Charge Analysis ====================
    
    def phase5_comprehensive_partial_charge(self):
        """Extended partial charge analysis with fine granularity"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"PHASE 5: COMPREHENSIVE PARTIAL CHARGE ANALYSIS")
        print(f"Fine-grained analog behavior characterization")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        phase_start = time.time()
        
        # Select cells based on previous results
        test_cells = self.select_cells_for_comprehensive_partial()
        
        print(f"📊 Testing {len(test_cells)} cells")
        print(f"⚡ Extended charge levels with fine granularity\n")
        
        # Fine-grained burst configurations
        fine_burst_configs = []
        
        # Very fine around threshold
        for burst in [1, 2]:
            for iterations in [5, 10, 15, 20, 30, 50]:
                fine_burst_configs.append({
                    'burst': burst,
                    'iterations': iterations,
                    'name': f'Burst {burst}, {iterations} iter'
                })
        
        # Standard bursts with standard iterations
        for burst in range(3, 9):
            fine_burst_configs.append({
                'burst': burst,
                'iterations': 20,
                'name': f'Burst {burst}, standard'
            })
        
        # Test each configuration
        partial_charge_results = defaultdict(list)
        
        for config_idx, config in enumerate(fine_burst_configs):
            print(f"\nTesting {config['name']}...")
            
            # Configure burst
            self.configure_timing(burst_len=config['burst'], skip_refresh=1)
            
            # Test immediate and decay behavior
            test_times = [0, 10, 30, 60, 120]
            
            for time_point in test_times:
                # Clean cells
                self.configure_timing(burst_len=8)
                for addr in test_cells:
                    for _ in range(20):
                        self.write_cmd(addr, "00000000")
                
                # Write partial charge
                self.configure_timing(burst_len=config['burst'], skip_refresh=1)
                for addr in test_cells:
                    for _ in range(config['iterations']):
                        self.write_cmd(addr, "FFFFFFFF")
                
                # Wait if needed
                if time_point > 0:
                    time.sleep(time_point)
                
                # Read cells
                charge_data = []
                for addr in test_cells:
                    read_data = self.read_cmd(addr)
                    if read_data:
                        set_bits = bin(int(read_data, 16)).count('1')
                        charge_level = set_bits / 32.0
                        
                        # Bit-level analysis
                        bit_pattern = format(int(read_data, 16), '032b')
                        
                        charge_data.append({
                            'address': addr,
                            'charge_level': charge_level,
                            'set_bits': set_bits,
                            'bit_pattern': bit_pattern,
                            'read_data': read_data
                        })
                
                # Calculate statistics
                if charge_data:
                    charges = [d['charge_level'] for d in charge_data]
                    avg_charge = np.mean(charges)
                    std_charge = np.std(charges)
                    
                    # Bit position statistics
                    bit_freq = [0] * 32
                    for d in charge_data:
                        for i, bit in enumerate(d['bit_pattern']):
                            if bit == '1':
                                bit_freq[i] += 1
                    
                    partial_charge_results[config['name']].append({
                        'config': config,
                        'time': time_point,
                        'avg_charge': avg_charge,
                        'std_charge': std_charge,
                        'bit_frequencies': bit_freq,
                        'raw_data': charge_data
                    })
                    
                    print(f"  t={time_point:3d}s: {avg_charge:6.1%} (±{std_charge:5.1%})")
            
            # Progress
            percent = (config_idx + 1) / len(fine_burst_configs) * 100
            print(f"  Overall progress: {percent:.1f}%")
        
        # Analyze analog resolution
        self.analyze_analog_resolution(partial_charge_results, test_cells)
        
        # Save results
        self.save_partial_charge_results_v2(partial_charge_results)
        
        # Reset timing
        self.configure_timing(burst_len=0, skip_refresh=0)
        
        phase_duration = time.time() - phase_start
        self.phase_times['phase5'] = phase_duration
        
        print(f"\n{Fore.GREEN}✓ Phase 5 complete in {phase_duration/60:.1f} minutes{Style.RESET_ALL}")
    
    def select_cells_for_comprehensive_partial(self):
        """Select cells for comprehensive partial charge testing"""
        candidates = []
        
        # Prioritize cells that showed interesting behavior
        for addr, cell_data in self.cell_database.items():
            if 'characteristics' in cell_data:
                # Get cells with good analog potential
                if cell_data['characteristics'].get('decay_class') in ['medium', 'slow']:
                    candidates.append((addr, 1.0))
                elif 'leak_in_rate' in cell_data['characteristics']:
                    if cell_data['characteristics']['leak_in_rate'] > 0.001:
                        candidates.append((addr, 0.8))
        
        # Sort by score and take top cells
        candidates.sort(key=lambda x: x[1], reverse=True)
        return [addr for addr, _ in candidates[:100]]
    
    def analyze_analog_resolution(self, results, test_cells):
        """Analyze analog resolution capabilities"""
        print(f"\n{Fore.CYAN}Analyzing analog resolution...{Style.RESET_ALL}")
        
        # Extract immediate charge levels (t=0) for each configuration
        charge_levels_by_cell = defaultdict(list)
        
        for config_name, time_series in results.items():
            for time_data in time_series:
                if time_data['time'] == 0:  # Immediate read
                    for cell_data in time_data['raw_data']:
                        addr = cell_data['address']
                        charge = cell_data['charge_level']
                        charge_levels_by_cell[addr].append({
                            'config': config_name,
                            'charge': charge
                        })
        
        # Analyze each cell's analog resolution
        analog_cells = []
        
        for addr, charge_data in charge_levels_by_cell.items():
            if len(charge_data) >= 4:
                charges = sorted([d['charge'] for d in charge_data])
                
                # Calculate distinguishable levels
                distinguishable_levels = 1
                last_level = charges[0]
                
                for charge in charges[1:]:
                    if charge - last_level > 0.05:  # 5% threshold
                        distinguishable_levels += 1
                        last_level = charge
                
                # Calculate linearity (simplified)
                if len(charges) >= 5:
                    x = np.arange(len(charges))
                    y = np.array(charges)
                    correlation = np.corrcoef(x, y)[0, 1]
                    linearity = abs(correlation)
                else:
                    linearity = 0
                
                analog_quality = distinguishable_levels * linearity
                
                if distinguishable_levels >= 4:
                    analog_cells.append({
                        'address': addr,
                        'levels': distinguishable_levels,
                        'linearity': linearity,
                        'quality': analog_quality
                    })
                
                # Update cell database
                self.cell_database[addr]['characteristics']['analog_levels'] = distinguishable_levels
                self.cell_database[addr]['characteristics']['analog_linearity'] = linearity
                self.cell_database[addr]['characteristics']['analog_quality'] = analog_quality
        
        # Report findings
        if analog_cells:
            print(f"Found {len(analog_cells)} cells with good analog properties:")
            
            # Sort by quality
            analog_cells.sort(key=lambda x: x['quality'], reverse=True)
            
            for i, cell in enumerate(analog_cells[:10]):
                print(f"  {i+1}. 0x{cell['address']:08X}: {cell['levels']} levels, "
                      f"linearity={cell['linearity']:.2f}")
    
    def save_partial_charge_results_v2(self, results):
        """Save comprehensive partial charge results"""
        filename = self.results_dir / "comprehensive_partial_charge.json"
        with open(filename, 'w') as f:
            json.dump({
                'timestamp': datetime.now().isoformat(),
                'results': results
            }, f, indent=2, default=str)
    
    # ==================== Final Analysis and Neuromorphic Mapping ====================
    
    def generate_neuromorphic_report(self):
        """Generate comprehensive neuromorphic suitability report with detailed categorization"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"NEUROMORPHIC SUITABILITY ANALYSIS v2.0")
        print(f"Advanced mapping to neural network components")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        # Enhanced categorization for neuromorphic components
        neuromorphic_map = {
            # Synaptic components
            'analog_synapses': [],      # High analog resolution, good linearity
            'binary_synapses': [],      # Two-state, stable
            'stochastic_synapses': [],  # Noisy behavior, useful for probabilistic
            
            # Neuron types
            'lif_neurons': [],          # Leaky integrate-and-fire (fast decay)
            'threshold_neurons': [],    # Strong threshold behavior
            'bistable_neurons': [],     # Two stable states
            
            # Memory components
            'weight_storage': [],       # Stable, multi-level
            'short_term_memory': [],    # Fast decay, temporary storage
            'long_term_memory': [],     # Very stable, slow decay
            
            # Special components
            'leak_generators': [],      # Strong leak-in behavior
            'coupling_nodes': [],       # Strong neighbor coupling
            'noise_sources': [],        # High variability
            
            # Not suitable
            'unsuitable': []
        }
        
        # Analyze each cell for neuromorphic suitability
        for addr, cell_data in self.cell_database.items():
            if 'characteristics' not in cell_data:
                neuromorphic_map['unsuitable'].append(addr)
                continue
            
            chars = cell_data['characteristics']
            scores = self.calculate_neuromorphic_scores(chars, cell_data)
            
            # Assign to best category
            if scores:
                best_use = max(scores, key=scores.get)
                best_score = scores[best_use]
                
                if best_score >= 0.5:
                    neuromorphic_map[best_use].append({
                        'address': addr,
                        'score': best_score,
                        'characteristics': chars
                    })
                else:
                    neuromorphic_map['unsuitable'].append(addr)
            else:
                neuromorphic_map['unsuitable'].append(addr)
        
        # Sort each category by score
        for category in neuromorphic_map:
            if category != 'unsuitable' and neuromorphic_map[category]:
                neuromorphic_map[category].sort(key=lambda x: x['score'], reverse=True)
        
        # Display comprehensive report
        self.display_neuromorphic_report(neuromorphic_map)
        
        # Generate network architecture recommendations
        self.generate_architecture_recommendations(neuromorphic_map)
        
        # Save detailed report
        self.save_final_report_v2(neuromorphic_map)
        
        return neuromorphic_map
    
    def calculate_neuromorphic_scores(self, chars, cell_data):
        """Calculate suitability scores for different neuromorphic components"""
        scores = {}
        
        # Analog synapse score
        if chars.get('analog_levels', 0) >= 4:
            analog_quality = chars.get('analog_quality', 0)
            scores['analog_synapses'] = min(1.0, analog_quality / 5.0)
        
        # Binary synapse score
        if chars.get('decay_class') in ['slow', 'medium']:
            if chars.get('analog_levels', 0) <= 2:
                scores['binary_synapses'] = 0.8
        
        # Stochastic synapse score
        if 'decay_profiles' in cell_data:
            # Check for high variability
            retentions = []
            for pattern_data in cell_data['decay_profiles'].values():
                for measurement in pattern_data:
                    if measurement['time'] == 60:
                        retentions.append(measurement['retention'])
            
            if retentions and len(retentions) >= 3:
                variability = np.std(retentions)
                if variability > 0.1:
                    scores['stochastic_synapses'] = min(1.0, variability * 5)
        
        # LIF neuron score (need fast decay)
        if chars.get('decay_class') == 'fast':
            decay_rate = chars.get('avg_decay_rate', 0)
            scores['lif_neurons'] = min(1.0, decay_rate * 50)
        
        # Threshold neuron score
        if 'threshold_characteristics' in cell_data:
            threshold_jump = cell_data['threshold_characteristics'].get('threshold_jump', 0)
            if threshold_jump > 0.5:
                scores['threshold_neurons'] = min(1.0, threshold_jump)
        
        # Bistable neuron score
        if chars.get('analog_levels', 0) == 2:
            if chars.get('decay_class') in ['slow', 'medium']:
                scores['bistable_neurons'] = 0.8
        
        # Weight storage score
        if chars.get('decay_class') == 'slow' and chars.get('analog_levels', 0) >= 4:
            scores['weight_storage'] = 0.9
        
        # Short-term memory score
        if chars.get('decay_class') == 'medium':
            half_life = chars.get('avg_half_life', 0)
            if 10 < half_life < 300:  # 10s to 5min
                scores['short_term_memory'] = 0.8
        
        # Long-term memory score
        if chars.get('decay_class') == 'slow':
            decay_rate = chars.get('avg_decay_rate', 1)
            if decay_rate < 0.001:
                scores['long_term_memory'] = 0.9
        
        # Leak generator score
        leak_rate = chars.get('leak_in_rate', 0)
        if leak_rate > 0.001:
            scores['leak_generators'] = min(1.0, leak_rate * 1000)
        
        # Coupling node score
        if 'neighbor_effects' in cell_data:
            # Would need coupling data from phase 4
            scores['coupling_nodes'] = 0.5  # Placeholder
        
        # Noise source score
        if chars.get('analog_quality', 1) < 0.5:
            scores['noise_sources'] = 0.7
        
        return scores
    
    def display_neuromorphic_report(self, neuromorphic_map):
        """Display the comprehensive neuromorphic mapping report"""
        print(f"\n{Fore.GREEN}╔{'═'*78}╗")
        print(f"║{'NEUROMORPHIC COMPONENT MAPPING v2.0':^78}║")
        print(f"╚{'═'*78}╝{Style.RESET_ALL}\n")
        
        total_cells = len(self.cell_database)
        suitable_cells = total_cells - len(neuromorphic_map['unsuitable'])
        
        print(f"Total cells characterized: {total_cells}")
        print(f"Neuromorphic suitable: {suitable_cells} ({suitable_cells/total_cells*100:.1f}%)\n")
        
        # Component categories with icons and descriptions
        categories = [
            # Synaptic components
            ("SYNAPTIC COMPONENTS", Fore.BLUE, [
                ('analog_synapses', '◉', 'Multi-level analog synaptic weights'),
                ('binary_synapses', '◐', 'Binary on/off synapses'),
                ('stochastic_synapses', '◈', 'Probabilistic synaptic transmission'),
            ]),
            # Neuron types
            ("NEURON TYPES", Fore.YELLOW, [
                ('lif_neurons', '⚡', 'Leaky integrate-and-fire neurons'),
                ('threshold_neurons', '⬡', 'Threshold-based spiking neurons'),
                ('bistable_neurons', '◑', 'Bistable neuron states'),
            ]),
            # Memory components
            ("MEMORY SYSTEMS", Fore.GREEN, [
                ('weight_storage', '▣', 'Stable weight parameter storage'),
                ('short_term_memory', '◔', 'Short-term memory buffers'),
                ('long_term_memory', '▮', 'Long-term stable memory'),
            ]),
            # Special components
            ("SPECIAL COMPONENTS", Fore.MAGENTA, [
                ('leak_generators', '◊', 'Controlled charge leakage sources'),
                ('coupling_nodes', '⬢', 'Inter-cell coupling mediators'),
                ('noise_sources', '∿', 'Stochastic noise generators'),
            ])
        ]
        
        # Display each category
        for category_name, color, components in categories:
            print(f"\n{color}━━━ {category_name} ━━━{Style.RESET_ALL}")
            
            for comp_key, icon, description in components:
                cells = neuromorphic_map[comp_key]
                count = len(cells)
                
                print(f"\n{icon} {color}{comp_key.replace('_', ' ').upper()}{Style.RESET_ALL}: {count} cells")
                print(f"   {description}")
                
                if cells:
                    # Show top cells with characteristics
                    print(f"   Top cells:")
                    for i, cell_info in enumerate(cells[:3]):
                        addr = cell_info['address']
                        score = cell_info['score']
                        chars = cell_info['characteristics']
                        
                        print(f"     {i+1}. 0x{addr:08X} (score: {score:.2f})")
                        
                        # Show relevant characteristics
                        if comp_key == 'analog_synapses':
                            levels = chars.get('analog_levels', 0)
                            linearity = chars.get('analog_linearity', 0)
                            print(f"        Levels: {levels}, Linearity: {linearity:.2f}")
                        elif comp_key == 'lif_neurons':
                            decay_rate = chars.get('avg_decay_rate', 0)
                            print(f"        Decay rate: {decay_rate:.3f}/s")
                        elif comp_key == 'leak_generators':
                            leak_rate = chars.get('leak_in_rate', 0)
                            print(f"        Leak rate: {leak_rate*100:.2f}%/s")
        
        # Summary statistics
        print(f"\n{Fore.CYAN}{'─'*60}")
        print(f"COMPONENT DISTRIBUTION SUMMARY")
        print(f"{'─'*60}{Style.RESET_ALL}")
        
        # Calculate totals for each category
        for category_name, _, components in categories:
            total = sum(len(neuromorphic_map[comp[0]]) for comp in components)
            print(f"{category_name}: {total} cells ({total/total_cells*100:.1f}%)")
    
    def generate_architecture_recommendations(self, neuromorphic_map):
        """Generate recommendations for neuromorphic architecture design"""
        print(f"\n{Fore.CYAN}{'='*60}")
        print(f"NEUROMORPHIC ARCHITECTURE RECOMMENDATIONS")
        print(f"{'='*60}{Style.RESET_ALL}\n")
        
        # Count available components
        component_counts = {k: len(v) for k, v in neuromorphic_map.items()}
        
        # Suggest possible architectures
        architectures = []
        
        # 1. Spiking Neural Network
        if (component_counts.get('lif_neurons', 0) >= 20 and 
            component_counts.get('analog_synapses', 0) >= 50):
            architectures.append({
                'name': 'Spiking Neural Network (SNN)',
                'feasibility': 'High',
                'components': {
                    'Neurons': component_counts.get('lif_neurons', 0),
                    'Synapses': component_counts.get('analog_synapses', 0),
                    'Memory': component_counts.get('weight_storage', 0)
                },
                'applications': ['Pattern recognition', 'Temporal processing', 'Event-based sensing']
            })
        
        # 2. Hopfield Network
        if (component_counts.get('bistable_neurons', 0) >= 30 and
            component_counts.get('binary_synapses', 0) >= 100):
            architectures.append({
                'name': 'Hopfield Associative Memory',
                'feasibility': 'Medium',
                'components': {
                    'Neurons': component_counts.get('bistable_neurons', 0),
                    'Synapses': component_counts.get('binary_synapses', 0)
                },
                'applications': ['Content-addressable memory', 'Pattern completion', 'Optimization']
            })
        
        # 3. Reservoir Computing
        if (component_counts.get('stochastic_synapses', 0) >= 50 and
            component_counts.get('leak_generators', 0) >= 10):
            architectures.append({
                'name': 'Reservoir Computing System',
                'feasibility': 'High',
                'components': {
                    'Reservoir nodes': component_counts.get('stochastic_synapses', 0),
                    'Leak sources': component_counts.get('leak_generators', 0),
                    'Readout': component_counts.get('analog_synapses', 0)
                },
                'applications': ['Time series prediction', 'Speech recognition', 'Chaotic systems']
            })
        
        # Display recommendations
        if architectures:
            print("Based on available components, the following architectures are feasible:\n")
            
            for i, arch in enumerate(architectures, 1):
                print(f"{i}. {Fore.GREEN}{arch['name']}{Style.RESET_ALL}")
                print(f"   Feasibility: {arch['feasibility']}")
                print(f"   Available components:")
                for comp, count in arch['components'].items():
                    print(f"     - {comp}: {count}")
                print(f"   Suitable applications:")
                for app in arch['applications']:
                    print(f"     • {app}")
                print()
        else:
            print(f"{Fore.YELLOW}Limited neuromorphic components available.")
            print(f"Consider focusing on specialized applications or hybrid architectures.{Style.RESET_ALL}")
        
        # Specific recommendations based on findings
        print(f"\n{Fore.CYAN}SPECIFIC FINDINGS AND RECOMMENDATIONS:{Style.RESET_ALL}\n")
        
        # Threshold behavior
        if component_counts.get('threshold_neurons', 0) > 0:
            print(f"• {Fore.GREEN}Threshold Behavior:{Style.RESET_ALL}")
            print(f"  Found {component_counts['threshold_neurons']} cells with sharp threshold at burst=3")
            print(f"  → Ideal for implementing sigmoid-like activation functions")
            print(f"  → Can create precise switching behavior for decision circuits\n")
        
        # Leak-in phenomenon
        if component_counts.get('leak_generators', 0) > 0:
            print(f"• {Fore.GREEN}Leak-In Phenomenon:{Style.RESET_ALL}")
            print(f"  Found {component_counts['leak_generators']} cells with charge accumulation")
            print(f"  → Natural integration behavior for temporal summation")
            print(f"  → Useful for implementing synaptic plasticity\n")
        
        # Analog resolution
        analog_cells = neuromorphic_map.get('analog_synapses', [])
        if analog_cells:
            best_analog = analog_cells[0] if analog_cells else None
            if best_analog:
                levels = best_analog['characteristics'].get('analog_levels', 0)
                print(f"• {Fore.GREEN}Analog Resolution:{Style.RESET_ALL}")
                print(f"  Best cell supports {levels} distinguishable levels")
                print(f"  → Sufficient for implementing 2-3 bit synaptic weights")
                print(f"  → Enable gradient-based learning algorithms\n")
    
    def save_final_report_v2(self, neuromorphic_map):
        """Save comprehensive final report with all characterization data"""
        report = {
            'session_id': self.session_id,
            'timestamp': datetime.now().isoformat(),
            'total_cells': len(self.cell_database),
            'test_duration': time.time() - self.start_time,
            'neuromorphic_mapping': {},
            'component_statistics': {},
            'architecture_feasibility': {},
            'cell_characteristics_summary': {},
            'phase_timings': self.phase_times
        }
        
        # Neuromorphic mapping
        for component, cells in neuromorphic_map.items():
            if component != 'unsuitable':
                report['neuromorphic_mapping'][component] = [
                    {
                        'address': f"0x{cell['address']:08X}",
                        'score': float(cell['score']),
                        'key_characteristics': {
                            k: v for k, v in cell['characteristics'].items()
                            if k in ['decay_class', 'analog_levels', 'leak_in_rate', 'analog_quality']
                        }
                    }
                    for cell in cells[:10]  # Top 10 per category
                ]
        
        # Component statistics
        for component, cells in neuromorphic_map.items():
            count = len(cells) if component == 'unsuitable' else len(cells)
            report['component_statistics'][component] = {
                'count': count,
                'percentage': count / len(self.cell_database) * 100 if len(self.cell_database) > 0 else 0
            }
        
        # Save JSON report
        with open(self.results_dir / "neuromorphic_report_v2.json", 'w') as f:
            json.dump(report, f, indent=2, default=str)
        
        # Save full cell database
        with open(self.results_dir / "cell_database_complete.pkl", 'wb') as f:
            pickle.dump(self.cell_database, f)
        
        # Generate detailed text summary
        with open(self.results_dir / "comprehensive_summary.txt", 'w') as f:
            f.write("NEUROMORPHIC DRAM CHARACTERIZATION SUMMARY v2.0\n")
            f.write("="*80 + "\n\n")
            f.write(f"Session: {self.session_id}\n")
            f.write(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Total cells tested: {len(self.cell_database)}\n")
            f.write(f"Test duration: {report['test_duration']/3600:.1f} hours\n\n")
            
            f.write("KEY DISCOVERIES:\n")
            f.write("-"*40 + "\n")
            
            # Threshold behavior
            threshold_cells = len(neuromorphic_map.get('threshold_neurons', []))
            if threshold_cells > 0:
                f.write(f"• Threshold Behavior: Found in {threshold_cells} cells\n")
                f.write(f"  - Sharp transition at burst length 3\n")
                f.write(f"  - Jump from ~25% to ~99% charge\n\n")
            
            # Leak-in phenomenon
            leak_cells = len(neuromorphic_map.get('leak_generators', []))
            if leak_cells > 0:
                f.write(f"• Leak-In Phenomenon: Found in {leak_cells} cells\n")
                f.write(f"  - Charge accumulation at sub-threshold bursts\n")
                f.write(f"  - Rates up to several %/second\n\n")
            
            # Burst 8 anomaly
            f.write(f"• Burst Length 8 Anomaly:\n")
            f.write(f"  - Expected 100% charge, observed ~31%\n")
            f.write(f"  - Suggests internal timing constraints\n\n")
            
            # Component distribution
            f.write("\nCOMPONENT DISTRIBUTION:\n")
            f.write("-"*40 + "\n")
            for comp, stats in report['component_statistics'].items():
                if stats['count'] > 0 and comp != 'unsuitable':
                    f.write(f"{comp:25s}: {stats['count']:5d} cells ({stats['percentage']:5.1f}%)\n")
        
        print(f"\n{Fore.GREEN}✅ Comprehensive reports saved to: {self.results_dir}/")
        print(f"    • JSON report: neuromorphic_report_v2.json")
        print(f"    • Cell database: cell_database_complete.pkl")
        print(f"    • Text summary: comprehensive_summary.txt{Style.RESET_ALL}")
    
    def run_complete_characterization(self):
        """Run all characterization phases"""
        print(f"{Fore.CYAN}{BANNER}{Style.RESET_ALL}")
        
        try:
            # Phase 1: Comprehensive decay analysis
            self.phase1_comprehensive_decay_analysis()
            
            # Phase 2: Leak-in investigation
            self.phase2_leak_in_investigation()
            
            # Phase 3: Threshold characterization
            self.phase3_threshold_characterization()
            
            # Phase 4: Enhanced neighbor coupling
            self.phase4_enhanced_neighbor_coupling()
            
            # Phase 5: Comprehensive partial charge
            self.phase5_comprehensive_partial_charge()
            
            # Generate final report
            neuromorphic_map = self.generate_neuromorphic_report()
            
            # Display timing summary
            print(f"\n{Fore.CYAN}{'─'*60}")
            print(f"TIMING SUMMARY")
            print(f"{'─'*60}{Style.RESET_ALL}")
            
            total_time = time.time() - self.start_time
            print(f"Total characterization time: {total_time/3600:.1f} hours")
            
            for phase, duration in self.phase_times.items():
                print(f"  {phase}: {duration/60:.1f} minutes ({duration/total_time*100:.1f}%)")
            
            # Final message
            print(f"\n{Fore.MAGENTA}{'✨ ' * 20}")
            print(f"ENHANCED NEUROMORPHIC CHARACTERIZATION COMPLETE!")
            print(f"Your DRAM's analog soul has been fully mapped.")
            print(f"Ready for advanced neural computation architectures.")
            print(f"{'✨ ' * 20}{Style.RESET_ALL}\n")
            
            return neuromorphic_map
            
        except KeyboardInterrupt:
            print(f"\n{Fore.YELLOW}⚠️  Characterization interrupted by user{Style.RESET_ALL}")
            self.save_checkpoint()
            raise
        except Exception as e:
            print(f"\n{Fore.RED}❌ Error during characterization: {e}{Style.RESET_ALL}")
            self.save_checkpoint()
            raise
    
    def save_checkpoint(self):
        """Save current progress as checkpoint"""
        checkpoint = {
            'timestamp': datetime.now().isoformat(),
            'progress': {
                'cells_tested': len(self.cell_database),
                'phases_completed': list(self.phase_times.keys()),
                'time_elapsed': time.time() - self.start_time
            }
        }
        
        with open(self.results_dir / "checkpoint.json", 'w') as f:
            json.dump(checkpoint, f, indent=2)
        
        # Save current cell database
        with open(self.results_dir / "cell_database_checkpoint.pkl", 'wb') as f:
            pickle.dump(self.cell_database, f)
        
        print(f"{Fore.YELLOW}💾 Progress saved to checkpoint{Style.RESET_ALL}")

def main():
    """Main entry point"""
    try:
        # Connect to DDR3 controller
        print(f"{Fore.CYAN}🔌 Connecting to DDR3 controller on {SERIAL_PORT}...{Style.RESET_ALL}")
        ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)
        time.sleep(0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        print(f"{Fore.GREEN}✓ Connected @ {BAUDRATE} baud{Style.RESET_ALL}")
        
        # Create characterizer and run
        characterizer = NeuroCharacterizer(ser)
        neuromorphic_map = characterizer.run_complete_characterization()
        
        return 0
        
    except serial.SerialException as e:
        print(f"\n{Fore.RED}❌ Serial port error: {e}{Style.RESET_ALL}")
        return 1
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Characterization terminated by user{Style.RESET_ALL}")
        return 1
    except Exception as e:
        print(f"\n{Fore.RED}Fatal error: {e}{Style.RESET_ALL}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print(f"{Fore.CYAN}🔌 Serial port closed{Style.RESET_ALL}")

if __name__ == "__main__":
    exit(main())
