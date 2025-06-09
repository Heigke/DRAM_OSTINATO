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
]

# Decay times for characterization (in seconds)
DECAY_TIMES = [30, 60, 120, 300, 600]  # Up to 10 minutes

# Partial charge configurations (burst lengths)
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

# ASCII Art
BANNER = """
╔════════════════════════════════════════════════════════════════════════════════╗
║                                                                                ║
║  ██████╗ ██████╗  █████╗ ███╗   ███╗    ███╗   ██╗███████╗██╗   ██╗██████╗   ║
║  ██╔══██╗██╔══██╗██╔══██╗████╗ ████║    ████╗  ██║██╔════╝██║   ██║██╔══██╗  ║
║  ██║  ██║██████╔╝███████║██╔████╔██║    ██╔██╗ ██║█████╗  ██║   ██║██████╔╝  ║
║  ██║  ██║██╔══██╗██╔══██║██║╚██╔╝██║    ██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗  ║
║  ██████╔╝██║  ██║██║  ██║██║ ╚═╝ ██║    ██║ ╚████║███████╗╚██████╔╝██║  ██║  ║
║  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝    ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝  ║
║                                                                                ║
║               Neuromorphic DRAM Cell Characterization Suite v1.0               ║
║                    "Finding the Analog Soul in Digital Memory"                 ║
╚════════════════════════════════════════════════════════════════════════════════╝
"""

class NeuroCharacterizer:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.results_dir = Path(f"neuro_char_{self.session_id}")
        self.results_dir.mkdir(exist_ok=True)
        
        # Data structures
        self.cell_database = {}
        self.decay_profiles = defaultdict(dict)
        self.partial_charge_profiles = defaultdict(dict)
        self.neighbor_coupling = defaultdict(dict)
        
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
        time.sleep(0.005)  # Slightly longer delay for reliability
    
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
        
        print(f"\r{prefix}: [{bar}] {percent*100:.1f}% ({current}/{total}){eta_str}    ", 
              end='', flush=True)
    
    def get_test_addresses(self, sample_size_per_region=None):
        """Get a representative sample of addresses from each region"""
        addresses = []
        
        if sample_size_per_region is None:
            # Get all addresses from regions (matching reference script)
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
    
    # ==================== PHASE 1: Full Charge Decay Analysis ====================
    
    def phase1_full_decay_analysis(self):
        """Test decay characteristics with full charge"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"PHASE 1: FULL CHARGE DECAY ANALYSIS")
        print(f"Testing decay behavior with different patterns")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        phase_start = time.time()
        
        # Get test addresses - use more addresses for initial sweep
        print(f"{Fore.YELLOW}Selecting test addresses:{Style.RESET_ALL}")
        test_addresses = self.get_test_addresses()  # Get all addresses
        
        # If too many addresses, sample them
        if len(test_addresses) > 1000:
            print(f"  {Fore.YELLOW}Sampling 1000 addresses from {len(test_addresses)} total{Style.RESET_ALL}")
            import random
            random.seed(42)  # For reproducibility
            test_addresses = random.sample(test_addresses, 1000)
        
        print(f"\n📊 Testing {len(test_addresses)} addresses")
        print(f"⏱️  Decay times: {DECAY_TIMES} seconds")
        print(f"🎯 Patterns: {[p['name'] for p in TEST_PATTERNS]}\n")
        
        total_tests = len(TEST_PATTERNS) * len(DECAY_TIMES)
        current_test = 0
        test_start_time = time.time()
        
        # Track all weak cells found
        all_weak_cells = []
        
        # Don't configure timing initially - use defaults
        
        for pattern_info in TEST_PATTERNS:
            pattern = pattern_info['pattern']
            print(f"\n{Fore.YELLOW}Testing pattern: {pattern_info['name']} ({pattern}){Style.RESET_ALL}")
            
            for decay_time in DECAY_TIMES:
                current_test += 1
                print(f"\n  Test {current_test}/{total_tests} - Decay time: {decay_time}s")
                
                # Write pattern to all cells first
                print(f"  Writing to all cells...", end='', flush=True)
                for addr in test_addresses:
                    for _ in range(10):  # Multiple writes for reliability
                        self.write_cmd(addr, pattern)
                    if addr % 100 == 0:  # Small delay every 100 addresses
                        time.sleep(0.001)
                print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
                
                # Brief pause to ensure writes complete
                time.sleep(0.5)
                
                # Verify writes before decay test
                print(f"  Verifying writes...", end='', flush=True)
                verified_addresses = []
                verify_errors = 0
                for addr in test_addresses:
                    # Try reading multiple times
                    verified = False
                    for attempt in range(3):
                        read_data = self.read_cmd(addr)
                        if read_data == pattern:
                            verified = True
                            break
                        time.sleep(0.01)
                    
                    if verified:
                        verified_addresses.append(addr)
                    else:
                        verify_errors += 1
                
                if len(verified_addresses) == 0:
                    print(f" {Fore.RED}✗ No addresses verified!{Style.RESET_ALL}")
                    print(f"  {Fore.YELLOW}Debug: Trying with different timing...{Style.RESET_ALL}")
                    
                    # Try disabling refresh if verification failed
                    self.configure_timing(skip_refresh=1)
                    time.sleep(0.2)
                    
                    # Retry write and verify
                    for addr in test_addresses[:10]:  # Test first 10
                        self.write_cmd(addr, pattern)
                    time.sleep(0.1)
                    
                    test_read = self.read_cmd(test_addresses[0])
                    if test_read:
                        print(f"  {Fore.YELLOW}Read result: {test_read} (expected: {pattern}){Style.RESET_ALL}")
                    
                    continue
                else:
                    print(f" {Fore.GREEN}✓ {len(verified_addresses)}/{len(test_addresses)} verified{Style.RESET_ALL}")
                
                # Only now configure timing for decay test (disable refresh)
                self.configure_timing(skip_refresh=1)
                time.sleep(0.1)
                
                # Wait for decay
                if decay_time > 0:
                    print(f"  Waiting {decay_time}s for decay...", end='', flush=True)
                    # Show progress during long waits
                    if decay_time >= 60:
                        for i in range(decay_time):
                            if i % 30 == 0 and i > 0:
                                print(f" {i}s", end='', flush=True)
                            time.sleep(1)
                    else:
                        time.sleep(decay_time)
                    print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
                
                # Read all cells and analyze
                print(f"  Reading and analyzing cells...")
                decay_results = []
                weak_cells_found = []
                
                for i, addr in enumerate(verified_addresses):
                    read_data = self.read_cmd(addr)
                    
                    if read_data:
                        errors = self.hamming_distance(pattern, read_data)
                        retention = (32 - errors) / 32.0
                        
                        # Check for specific bit flips
                        written_val = int(pattern, 16)
                        read_val = int(read_data, 16)
                        flipped_bits = written_val ^ read_val
                        
                        result = {
                            'address': addr,
                            'pattern': pattern,
                            'pattern_name': pattern_info['name'],
                            'decay_time': decay_time,
                            'read_data': read_data,
                            'errors': errors,
                            'retention': retention,
                            'flipped_bits': f"{flipped_bits:032b}",
                            'flip_positions': [i for i in range(32) if flipped_bits & (1 << i)]
                        }
                        
                        decay_results.append(result)
                        
                        # Track weak cells
                        if errors > 0:
                            weak_cells_found.append(result)
                            all_weak_cells.append(result)
                        
                        # Store in cell database
                        if addr not in self.cell_database:
                            self.cell_database[addr] = {
                                'address': addr,
                                'decay_profiles': {},
                                'partial_charge_profiles': {},
                                'characteristics': {}
                            }
                        
                        if pattern not in self.cell_database[addr]['decay_profiles']:
                            self.cell_database[addr]['decay_profiles'][pattern] = []
                        
                        self.cell_database[addr]['decay_profiles'][pattern].append({
                            'time': decay_time,
                            'retention': retention,
                            'errors': errors
                        })
                    
                    # Show progress every 100 addresses
                    if (i + 1) % 100 == 0 or (i + 1) == len(verified_addresses):
                        percent = (i + 1) / len(verified_addresses) * 100
                        print(f"\r    Progress: {percent:.1f}% ({i+1}/{len(verified_addresses)}) - Found {len(weak_cells_found)} weak cells", 
                              end='', flush=True)
                
                print()  # New line after progress
                
                # Reset timing after test
                self.configure_timing(skip_refresh=0)
                time.sleep(0.1)
                
                # Quick analysis
                if decay_results:
                    avg_retention = np.mean([r['retention'] for r in decay_results])
                    cells_failed = sum(1 for r in decay_results if r['retention'] < 0.5)
                    cells_with_errors = len(weak_cells_found)
                    
                    print(f"  {Fore.CYAN}Average retention: {avg_retention:.1%}")
                    print(f"  Cells <50% retention: {cells_failed}/{len(decay_results)}")
                    print(f"  Cells with bit errors: {cells_with_errors}/{len(decay_results)}{Style.RESET_ALL}")
                    
                    # Show weak cells found
                    if cells_with_errors > 0:
                        print(f"  {Fore.MAGENTA}🎯 Found {cells_with_errors} cells with errors:{Style.RESET_ALL}")
                        for cell in weak_cells_found[:5]:  # Show first 5
                            print(f"     0x{cell['address']:08X}: {cell['pattern']} → {cell['read_data']} ({cell['errors']} bits)")
                        if cells_with_errors > 5:
                            print(f"     ... and {cells_with_errors - 5} more")
                
                # Save intermediate results
                self.save_decay_results(pattern_info['name'], decay_time, decay_results)
        
        # Summary of all weak cells found
        if all_weak_cells:
            print(f"\n{Fore.GREEN}{'='*60}")
            print(f"PHASE 1 SUMMARY: Found {len(all_weak_cells)} total weak cells!")
            print(f"{'='*60}{Style.RESET_ALL}")
            
            # Group by address
            unique_addresses = set(cell['address'] for cell in all_weak_cells)
            print(f"Unique weak addresses: {len(unique_addresses)}")
            
            # Show weakest cells
            weakest = sorted(all_weak_cells, key=lambda x: x['errors'], reverse=True)[:10]
            print(f"\nTop 10 weakest cells:")
            for i, cell in enumerate(weakest, 1):
                print(f"  {i:2d}. 0x{cell['address']:08X} - {cell['errors']} bits "
                      f"({cell['pattern_name']}, {cell['decay_time']}s)")
        
        phase_duration = time.time() - phase_start
        self.phase_times['phase1'] = phase_duration
        
        print(f"\n{Fore.GREEN}✓ Phase 1 complete in {phase_duration/60:.1f} minutes{Style.RESET_ALL}")
        self.analyze_decay_characteristics()
    
    def save_decay_results(self, pattern_name, decay_time, results):
        """Save decay results to file"""
        filename = self.results_dir / f"decay_{pattern_name}_{decay_time}s.json"
        with open(filename, 'w') as f:
            json.dump({
                'pattern': pattern_name,
                'decay_time': decay_time,
                'timestamp': datetime.now().isoformat(),
                'results': results
            }, f, indent=2)
    
    def analyze_decay_characteristics(self):
        """Analyze decay patterns and classify cells"""
        print(f"\n{Fore.CYAN}Analyzing decay characteristics...{Style.RESET_ALL}")
        
        for addr, cell_data in self.cell_database.items():
            if 'decay_profiles' not in cell_data:
                continue
            
            # Calculate decay rates for each pattern
            decay_rates = {}
            for pattern, measurements in cell_data['decay_profiles'].items():
                if len(measurements) >= 3:
                    # Simple linear fit to retention vs time
                    times = [m['time'] for m in measurements if m['time'] > 0]
                    retentions = [m['retention'] for m in measurements if m['time'] > 0]
                    
                    if times and retentions:
                        # Calculate average decay rate
                        decay_rate = (retentions[0] - retentions[-1]) / (times[-1] - times[0]) if times[-1] > times[0] else 0
                        decay_rates[pattern] = abs(decay_rate)
            
            # Classify cell based on decay behavior
            if decay_rates:
                avg_decay_rate = np.mean(list(decay_rates.values()))
                
                if avg_decay_rate > 0.01:  # >1% per second
                    cell_data['characteristics']['decay_class'] = 'fast'
                elif avg_decay_rate > 0.001:  # >0.1% per second
                    cell_data['characteristics']['decay_class'] = 'medium'
                else:
                    cell_data['characteristics']['decay_class'] = 'slow'
                
                cell_data['characteristics']['avg_decay_rate'] = avg_decay_rate
    
    # ==================== PHASE 2: Partial Charge Analysis ====================
    
    def phase2_partial_charge_analysis(self):
        """Test behavior with different partial charge levels"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"PHASE 2: PARTIAL CHARGE ANALYSIS")
        print(f"Testing analog behavior with different charge levels")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        phase_start = time.time()
        
        # Select cells based on Phase 1 results
        test_cells = self.select_cells_for_partial_charge()
        
        print(f"📊 Testing {len(test_cells)} selected cells")
        print(f"⚡ Charge levels: {[pc['name'] for pc in PARTIAL_CHARGES]}")
        print(f"⏱️  Test times: {[0, 10, 30, 60]}s\n")
        
        total_tests = len(test_cells) * len(PARTIAL_CHARGES) * 4  # 4 decay times
        current_test = 0
        test_start_time = time.time()
        
        for charge_config in PARTIAL_CHARGES:
            print(f"\n{Fore.YELLOW}Testing {charge_config['name']} (burst={charge_config['burst']}){Style.RESET_ALL}")
            
            # Configure burst length
            self.configure_timing(burst_len=charge_config['burst'], skip_refresh=1)
            
            for decay_time in [0, 10, 30, 60]:
                print(f"\n  Decay time: {decay_time}s")
                
                # First clean all cells
                print(f"  Cleaning cells...", end='', flush=True)
                self.configure_timing(burst_len=8)
                for addr in test_cells:
                    for _ in range(5):
                        self.write_cmd(addr, "00000000")
                print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
                
                # Write with partial charge
                print(f"  Writing partial charge...", end='', flush=True)
                self.configure_timing(burst_len=charge_config['burst'])
                for addr in test_cells:
                    for _ in range(5):
                        self.write_cmd(addr, "FFFFFFFF")
                print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
                
                # Wait for decay
                if decay_time > 0:
                    print(f"  Waiting {decay_time}s...", end='', flush=True)
                    time.sleep(decay_time)
                    print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
                
                # Read and analyze
                print(f"  Reading cells:")
                charge_results = []
                
                for i, addr in enumerate(test_cells):
                    read_data = self.read_cmd(addr)
                    
                    if read_data:
                        set_bits = bin(int(read_data, 16)).count('1')
                        charge_level = set_bits / 32.0
                        
                        result = {
                            'address': addr,
                            'charge_config': charge_config['name'],
                            'burst_len': charge_config['burst'],
                            'decay_time': decay_time,
                            'read_data': read_data,
                            'set_bits': set_bits,
                            'charge_level': charge_level,
                            'expected_level': charge_config['level']
                        }
                        
                        charge_results.append(result)
                        
                        # Store in cell database
                        if addr not in self.cell_database[addr]['partial_charge_profiles']:
                            self.cell_database[addr]['partial_charge_profiles'] = {}
                        
                        if charge_config['name'] not in self.cell_database[addr]['partial_charge_profiles']:
                            self.cell_database[addr]['partial_charge_profiles'][charge_config['name']] = []
                        
                        self.cell_database[addr]['partial_charge_profiles'][charge_config['name']].append({
                            'decay_time': decay_time,
                            'charge_level': charge_level,
                            'set_bits': set_bits
                        })
                    
                    # Update progress
                    current_test += 1
                    elapsed = time.time() - test_start_time
                    tests_per_second = current_test / elapsed if elapsed > 0 else 1
                    remaining_tests = total_tests - current_test
                    eta = remaining_tests / tests_per_second if tests_per_second > 0 else 0
                    
                    self.progress_bar(i + 1, len(test_cells), 
                                    prefix=f"    Reading", eta_seconds=eta)
                
                print()  # New line after progress bar
                
                # Quick analysis
                if charge_results:
                    avg_charge = np.mean([r['charge_level'] for r in charge_results])
                    cells_responding = sum(1 for r in charge_results if r['charge_level'] > 0.1)
                    
                    print(f"  {Fore.CYAN}Average charge level: {avg_charge:.1%}")
                    print(f"  Cells responding: {cells_responding}/{len(charge_results)}{Style.RESET_ALL}")
                
                # Save results
                self.save_partial_charge_results(charge_config['name'], decay_time, charge_results)
        
        # Reset timing
        self.configure_timing(burst_len=0, skip_refresh=0)
        
        phase_duration = time.time() - phase_start
        self.phase_times['phase2'] = phase_duration
        
        print(f"\n{Fore.GREEN}✓ Phase 2 complete in {phase_duration/60:.1f} minutes{Style.RESET_ALL}")
        self.analyze_partial_charge_characteristics()
    
    def select_cells_for_partial_charge(self):
        """Select cells for partial charge testing based on decay analysis"""
        selected = []
        
        # Get cells from each decay class
        decay_classes = defaultdict(list)
        for addr, cell_data in self.cell_database.items():
            if 'characteristics' in cell_data and 'decay_class' in cell_data['characteristics']:
                decay_classes[cell_data['characteristics']['decay_class']].append(addr)
        
        # Select up to 30 cells from each class
        for decay_class, addresses in decay_classes.items():
            selected.extend(addresses[:30])
        
        # If not enough, add more cells
        if len(selected) < 50:
            all_addresses = list(self.cell_database.keys())
            for addr in all_addresses:
                if addr not in selected:
                    selected.append(addr)
                    if len(selected) >= 100:
                        break
        
        return selected[:100]  # Limit to 100 cells
    
    def save_partial_charge_results(self, charge_name, decay_time, results):
        """Save partial charge results"""
        filename = self.results_dir / f"partial_{charge_name.replace(' ', '_')}_{decay_time}s.json"
        with open(filename, 'w') as f:
            json.dump({
                'charge_level': charge_name,
                'decay_time': decay_time,
                'timestamp': datetime.now().isoformat(),
                'results': results
            }, f, indent=2)
    
    def analyze_partial_charge_characteristics(self):
        """Analyze partial charge behavior"""
        print(f"\n{Fore.CYAN}Analyzing partial charge characteristics...{Style.RESET_ALL}")
        
        for addr, cell_data in self.cell_database.items():
            if 'partial_charge_profiles' not in cell_data:
                continue
            
            # Analyze charge resolution
            charge_levels = []
            for charge_name, measurements in cell_data['partial_charge_profiles'].items():
                if measurements:
                    # Get immediate charge level (decay_time = 0)
                    immediate = [m for m in measurements if m['decay_time'] == 0]
                    if immediate:
                        charge_levels.append(immediate[0]['charge_level'])
            
            if len(charge_levels) >= 4:
                # Check for good analog resolution
                sorted_levels = sorted(charge_levels)
                level_differences = [sorted_levels[i+1] - sorted_levels[i] 
                                   for i in range(len(sorted_levels)-1)]
                
                min_separation = min(level_differences) if level_differences else 0
                
                if min_separation > 0.05:  # At least 5% separation
                    cell_data['characteristics']['analog_resolution'] = len(charge_levels)
                    cell_data['characteristics']['min_level_separation'] = min_separation
                    cell_data['characteristics']['analog_suitable'] = True
                else:
                    cell_data['characteristics']['analog_suitable'] = False
    
    # ==================== PHASE 3: Neighbor Coupling Analysis ====================
    
    def phase3_neighbor_coupling(self):
        """Test coupling between neighboring cells"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"PHASE 3: NEIGHBOR COUPLING ANALYSIS")
        print(f"Testing inter-cell interference")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        phase_start = time.time()
        
        # Select cell pairs
        test_pairs = self.select_neighbor_pairs()
        
        print(f"📊 Testing {len(test_pairs)} cell pairs")
        print(f"🔗 Testing row, column, and diagonal neighbors\n")
        
        current_test = 0
        test_start_time = time.time()
        
        # Configure for full charge
        self.configure_timing(burst_len=8, skip_refresh=1)
        
        for pair_idx, (cell1, cell2, relation) in enumerate(test_pairs):
            # Test 1: Baseline decay of cell2
            for _ in range(5):
                self.write_cmd(cell2, "FFFFFFFF")
            time.sleep(0.1)
            
            time.sleep(10)  # 10 second decay
            baseline_read = self.read_cmd(cell2)
            baseline_retention = (32 - self.hamming_distance("FFFFFFFF", baseline_read)) / 32.0 if baseline_read else 0
            
            # Test 2: With neighbor charged
            # Clean both cells
            for _ in range(5):
                self.write_cmd(cell1, "00000000")
                self.write_cmd(cell2, "00000000")
            time.sleep(0.1)
            
            # Charge both
            for _ in range(5):
                self.write_cmd(cell1, "FFFFFFFF")
                self.write_cmd(cell2, "FFFFFFFF")
            time.sleep(0.1)
            
            time.sleep(10)  # 10 second decay
            
            coupled_read = self.read_cmd(cell2)
            coupled_retention = (32 - self.hamming_distance("FFFFFFFF", coupled_read)) / 32.0 if coupled_read else 0
            
            # Calculate coupling
            coupling_effect = coupled_retention - baseline_retention
            
            # Store result
            if cell2 not in self.neighbor_coupling:
                self.neighbor_coupling[cell2] = {}
            
            self.neighbor_coupling[cell2][cell1] = {
                'relation': relation,
                'baseline_retention': baseline_retention,
                'coupled_retention': coupled_retention,
                'coupling_effect': coupling_effect,
                'coupling_type': 'positive' if coupling_effect > 0.01 else 'negative' if coupling_effect < -0.01 else 'neutral'
            }
            
            # Update progress
            current_test += 1
            elapsed = time.time() - test_start_time
            tests_per_second = current_test / elapsed if elapsed > 0 else 1
            remaining_tests = len(test_pairs) - current_test
            eta = remaining_tests / tests_per_second if tests_per_second > 0 else 0
            
            self.progress_bar(current_test, len(test_pairs), 
                            prefix="Testing pairs", eta_seconds=eta)
        
        print()  # New line after progress
        
        # Reset timing
        self.configure_timing(burst_len=0, skip_refresh=0)
        
        phase_duration = time.time() - phase_start
        self.phase_times['phase3'] = phase_duration
        
        print(f"\n{Fore.GREEN}✓ Phase 3 complete in {phase_duration/60:.1f} minutes{Style.RESET_ALL}")
        self.analyze_coupling_results()
    
    def select_neighbor_pairs(self):
        """Select neighboring cell pairs for testing"""
        pairs = []
        
        # Get a subset of addresses
        all_addresses = list(self.cell_database.keys())[:50]  # Limit to 50 cells
        
        for addr in all_addresses:
            # Test different neighbor types
            neighbors = [
                (addr + 0x1000, "row"),      # Next row
                (addr + 0x0004, "column"),   # Next column (32-bit word)
                (addr + 0x1004, "diagonal"), # Diagonal
            ]
            
            for neighbor_addr, relation in neighbors:
                # Check if neighbor is in our test range
                if any(region['start'] <= neighbor_addr < region['end'] for region in MEMORY_REGIONS):
                    pairs.append((addr, neighbor_addr, relation))
                    if len(pairs) >= 100:  # Limit total pairs
                        return pairs
        
        return pairs
    
    def analyze_coupling_results(self):
        """Analyze neighbor coupling patterns"""
        print(f"\n{Fore.CYAN}Analyzing coupling patterns...{Style.RESET_ALL}")
        
        coupling_stats = {
            'positive': 0,
            'negative': 0,
            'neutral': 0,
            'max_positive': 0,
            'max_negative': 0
        }
        
        for cell, neighbors in self.neighbor_coupling.items():
            for neighbor, data in neighbors.items():
                coupling_stats[data['coupling_type']] += 1
                
                if data['coupling_effect'] > coupling_stats['max_positive']:
                    coupling_stats['max_positive'] = data['coupling_effect']
                elif data['coupling_effect'] < coupling_stats['max_negative']:
                    coupling_stats['max_negative'] = data['coupling_effect']
        
        print(f"Coupling types:")
        print(f"  {Fore.GREEN}➕ Positive: {coupling_stats['positive']} pairs{Style.RESET_ALL}")
        print(f"  {Fore.RED}➖ Negative: {coupling_stats['negative']} pairs{Style.RESET_ALL}")
        print(f"  {Fore.YELLOW}═ Neutral: {coupling_stats['neutral']} pairs{Style.RESET_ALL}")
        print(f"\nMax effects:")
        print(f"  Positive: +{coupling_stats['max_positive']:.1%}")
        print(f"  Negative: {coupling_stats['max_negative']:.1%}")
    
    # ==================== Final Analysis and Report ====================
    
    def generate_neuromorphic_report(self):
        """Generate comprehensive neuromorphic suitability report"""
        print(f"\n{Fore.CYAN}{'='*80}")
        print(f"NEUROMORPHIC SUITABILITY ANALYSIS")
        print(f"Mapping cells to neural network components")
        print(f"{'='*80}{Style.RESET_ALL}\n")
        
        # Categorize cells for neuromorphic use
        neuromorphic_map = {
            'synapses': [],      # Analog cells with good resolution
            'neurons': [],       # Fast decay, good for integrate-and-fire
            'memory': [],        # Slow decay, stable storage
            'weights': [],       # Medium decay, tunable
            'unsuitable': []     # Not good for neuromorphic use
        }
        
        for addr, cell_data in self.cell_database.items():
            if 'characteristics' not in cell_data:
                neuromorphic_map['unsuitable'].append(addr)
                continue
            
            chars = cell_data['characteristics']
            
            # Score for different uses
            scores = {}
            
            # Synapse score (need analog behavior)
            if chars.get('analog_suitable', False):
                analog_res = chars.get('analog_resolution', 0)
                scores['synapse'] = analog_res / 8.0
            
            # Neuron score (fast decay is good for spiking)
            if chars.get('decay_class') == 'fast':
                scores['neuron'] = 0.8
            elif chars.get('decay_class') == 'medium':
                scores['neuron'] = 0.5
            
            # Memory score (slow decay is good)
            if chars.get('decay_class') == 'slow':
                scores['memory'] = 0.9
            elif chars.get('decay_class') == 'medium':
                scores['memory'] = 0.5
            
            # Weight score (medium decay with analog)
            if chars.get('decay_class') == 'medium' and chars.get('analog_suitable', False):
                scores['weight'] = 0.8
            
            # Assign to best category
            if scores:
                best_use = max(scores, key=scores.get)
                best_score = scores[best_use]
                
                if best_score >= 0.5:
                    if best_use == 'synapse':
                        neuromorphic_map['synapses'].append((addr, best_score))
                    elif best_use == 'neuron':
                        neuromorphic_map['neurons'].append((addr, best_score))
                    elif best_use == 'memory':
                        neuromorphic_map['memory'].append((addr, best_score))
                    elif best_use == 'weight':
                        neuromorphic_map['weights'].append((addr, best_score))
                else:
                    neuromorphic_map['unsuitable'].append(addr)
            else:
                neuromorphic_map['unsuitable'].append(addr)
        
        # Sort by score
        for category in ['synapses', 'neurons', 'memory', 'weights']:
            neuromorphic_map[category].sort(key=lambda x: x[1], reverse=True)
        
        # Display report
        print(f"{Fore.GREEN}╔{'═'*78}╗")
        print(f"║{'NEUROMORPHIC COMPONENT MAPPING':^78}║")
        print(f"╚{'═'*78}╝{Style.RESET_ALL}\n")
        
        total_cells = len(self.cell_database)
        suitable_cells = total_cells - len(neuromorphic_map['unsuitable'])
        
        print(f"Total cells characterized: {total_cells}")
        print(f"Neuromorphic suitable: {suitable_cells} ({suitable_cells/total_cells*100:.1f}%)\n")
        
        # ASCII visualization
        print("Cell Distribution:")
        print("┌─────────────────────────────────────┐")
        print("│  ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉  │  ◉ = Synapse")
        print("│  ⚡ ⚡ ⚡ ⚡ ⚡ ⚡ ⚡ ⚡ ⚡ ⚡ ⚡ ⚡ ⚡ ⚡  │  ⚡ = Neuron")
        print("│  ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣  │  ▣ = Memory")
        print("│  ◈ ◈ ◈ ◈ ◈ ◈ ◈ ◈ ◈ ◈ ◈ ◈ ◈ ◈ ◈  │  ◈ = Weight")
        print("└─────────────────────────────────────┘\n")
        
        # Component breakdown
        components = [
            ('synapses', '🔗', 'Analog memory for synaptic weights', Fore.BLUE),
            ('neurons', '⚡', 'Integrate-and-fire spiking units', Fore.YELLOW),
            ('memory', '💾', 'Long-term stable storage', Fore.GREEN),
            ('weights', '⚖️', 'Tunable connection strengths', Fore.MAGENTA),
        ]
        
        for comp_name, icon, description, color in components:
            cells = neuromorphic_map[comp_name]
            count = len(cells)
            
            print(f"{icon} {color}{comp_name.upper()}{Style.RESET_ALL}: {count} cells")
            print(f"   {description}")
            
            if cells:
                # Show top 5
                print(f"   Top cells:")
                for i, (addr, score) in enumerate(cells[:5]):
                    print(f"     {i+1}. 0x{addr:08X} (score: {score:.2f})")
            print()
        
        # Save detailed report
        self.save_final_report(neuromorphic_map)
        
        # Display timing summary
        print(f"\n{Fore.CYAN}{'─'*60}")
        print(f"TIMING SUMMARY")
        print(f"{'─'*60}{Style.RESET_ALL}")
        
        total_time = time.time() - self.start_time
        print(f"Total characterization time: {total_time/60:.1f} minutes")
        
        for phase, duration in self.phase_times.items():
            print(f"  {phase}: {duration/60:.1f} minutes ({duration/total_time*100:.1f}%)")
        
        return neuromorphic_map
    
    def save_final_report(self, neuromorphic_map):
        """Save comprehensive final report"""
        report = {
            'session_id': self.session_id,
            'timestamp': datetime.now().isoformat(),
            'total_cells': len(self.cell_database),
            'test_duration': time.time() - self.start_time,
            'neuromorphic_mapping': {
                comp: [(f"0x{addr:08X}", float(score)) for addr, score in cells]
                for comp, cells in neuromorphic_map.items()
                if comp != 'unsuitable'
            },
            'unsuitable_cells': [f"0x{addr:08X}" for addr in neuromorphic_map['unsuitable']],
            'statistics': {
                'cells_per_category': {
                    comp: len(cells) for comp, cells in neuromorphic_map.items()
                },
                'utilization_rate': (len(self.cell_database) - len(neuromorphic_map['unsuitable'])) / len(self.cell_database) if len(self.cell_database) > 0 else 0
            }
        }
        
        # Save JSON report
        with open(self.results_dir / "neuromorphic_report.json", 'w') as f:
            json.dump(report, f, indent=2)
        
        # Save full cell database
        with open(self.results_dir / "cell_database.pkl", 'wb') as f:
            pickle.dump(self.cell_database, f)
        
        # Generate summary text file
        with open(self.results_dir / "summary.txt", 'w') as f:
            f.write("NEUROMORPHIC DRAM CHARACTERIZATION SUMMARY\n")
            f.write("="*60 + "\n\n")
            f.write(f"Session: {self.session_id}\n")
            f.write(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Total cells tested: {len(self.cell_database)}\n")
            f.write(f"Test duration: {report['test_duration']/60:.1f} minutes\n\n")
            
            f.write("NEUROMORPHIC SUITABILITY:\n")
            for comp, count in report['statistics']['cells_per_category'].items():
                percentage = count / len(self.cell_database) * 100 if len(self.cell_database) > 0 else 0
                f.write(f"  {comp:12s}: {count:4d} cells ({percentage:5.1f}%)\n")
        
        print(f"\n{Fore.GREEN}✅ Reports saved to: {self.results_dir}/")
        print(f"   • JSON report: neuromorphic_report.json")
        print(f"   • Cell database: cell_database.pkl")
        print(f"   • Summary: summary.txt{Style.RESET_ALL}")
    
    def run_complete_characterization(self):
        """Run all characterization phases"""
        print(f"{Fore.CYAN}{BANNER}{Style.RESET_ALL}")
        
        try:
            # Phase 1: Full charge decay analysis
            self.phase1_full_decay_analysis()
            
            # Phase 2: Partial charge analysis
            self.phase2_partial_charge_analysis()
            
            # Phase 3: Neighbor coupling
            self.phase3_neighbor_coupling()
            
            # Generate final report
            neuromorphic_map = self.generate_neuromorphic_report()
            
            # Final message
            print(f"\n{Fore.MAGENTA}{'✨ ' * 20}")
            print(f"NEUROMORPHIC CHARACTERIZATION COMPLETE!")
            print(f"Your DRAM is ready for neural computation.")
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
        if 'ser' in locals():
            ser.close()
            print(f"{Fore.CYAN}🔌 Serial port closed{Style.RESET_ALL}")

if __name__ == "__main__":
    exit(main())
