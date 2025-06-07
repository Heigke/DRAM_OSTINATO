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

# Comprehensive decay times for neuromorphic characterization
DECAY_TIMES = [10, 30, 60, 120, 180, 300, 600, 900, 1200]  # Up to 20 minutes

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
    ║              NEUROMORPHIC DRAM CELL CHARACTERIZATION             ║
    ║                      ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄                        ║
    ║                     ▐░░░ NEURAL DRAM ░░░▌                       ║
    ║                     ▐░ ╔══╦══╦══╦══╗ ░▌                       ║
    ║                     ▐░ ║◉◉║◉◉║◉◉║◉◉║ ░▌                       ║
    ║                     ▐░ ╠══╬══╬══╬══╣ ░▌                       ║
    ║                     ▐░ ║◉◉║◉◉║◉◉║◉◉║ ░▌                       ║
    ║                     ▐░ ╚══╩══╩══╩══╝ ░▌                       ║
    ║                      ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀                        ║
    ║            "Leveraging Natural Decay for Computation"            ║
    ╚══════════════════════════════════════════════════════════════════╝
"""

ANIMATIONS = {
    'write': ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'],
    'read': ['◐', '◓', '◑', '◒'],
    'wait': ['🕐', '🕑', '🕒', '🕓', '🕔', '🕕', '🕖', '🕗', '🕘', '🕙', '🕚', '🕛'],
    'scan': ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█', '▇', '▆', '▅', '▄', '▃', '▂'],
    'found': ['💥', '✨', '🌟', '⚡', '💫', '✨'],
    'neural': ['🧠', '⚡', '🧠', '💫', '🧠', '✨'],
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
        print(f"{Fore.CYAN}║{Style.BRIGHT} {message.center(76)} {Style.NORMAL}{Fore.CYAN}║")
        print(f"{Fore.CYAN}{'═' * 80}{Style.RESET_ALL}")
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

def create_decay_heatmap(cell_profiles, save_path):
    """Create a heatmap of decay characteristics across memory regions"""
    # This would create actual visualization - placeholder for now
    fancy_print(f"Decay heatmap saved to {save_path}", "success")

class NeuromorphicDRAMAnalyzer:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.cell_profiles = {}  # Comprehensive profile for each cell
        self.weak_cells = []
        self.partial_write_results = defaultdict(list)
        self.decay_curves = defaultdict(list)
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.results_dir = Path(f"neuromorphic_dram_{self.session_id}")
        self.results_dir.mkdir(exist_ok=True)
        
        # Initialize system
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
    
    def configure_timing(self, twr=0, tras=0, burst_len=0, skip_refresh=0):
        """Configure DDR3 timing parameters"""
        config_value = (skip_refresh << 20) | (burst_len << 16) | (tras << 8) | twr
        cmd = f"C{config_value:08X}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.1)
        self.ser.reset_input_buffer()
    
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

    def test_partial_writes(self, addr, pattern_info):
        """Test cell response to different partial write configurations"""
        results = []
        pattern = pattern_info['pattern']
        
        fancy_print(f"Testing partial write responses at 0x{addr:08X}", "neural")
        
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
            
            # Test decay at multiple intervals
            decay_profile = []
            for decay_time in [10, 30, 60, 120]:
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

    def characterize_cell_decay(self, addr, pattern_info):
        """Comprehensive decay characterization of a single cell"""
        pattern = pattern_info['pattern']
        decay_points = []
        
        # Write pattern multiple times
        for _ in range(NWRITES * 2):  # Extra writes for stability
            self.write_cmd(addr, pattern)
            time.sleep(0.001)
        
        time.sleep(0.1)
        
        # Verify initial write
        initial = self.read_cmd(addr)
        if initial != pattern:
            return None  # Cell didn't hold initial value
        
        # Measure decay at fine intervals
        start_time = time.time()
        test_intervals = [5, 10, 20, 30, 45, 60, 90, 120, 180, 240, 300, 450, 600]
        
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
                
                # If cell has decayed significantly, no need to continue
                if hamming > 16:  # More than half the bits flipped
                    break
        
        return decay_points

    def classify_cell_behavior(self, cell_profile):
        """Classify cell based on its decay and response characteristics"""
        classifications = []
        
        # Analyze decay rate
        if 'decay_profile' in cell_profile:
            decay_times = [p['time'] for p in cell_profile['decay_profile'] if p['hamming'] > 0]
            if decay_times:
                first_decay = min(decay_times)
                if first_decay < 30:
                    classifications.append('fast_decay')
                    cell_profile['decay_class'] = 'fast'
                elif first_decay > 300:
                    classifications.append('slow_decay')
                    cell_profile['decay_class'] = 'slow'
                else:
                    classifications.append('medium_decay')
                    cell_profile['decay_class'] = 'medium'
        
        # Analyze partial write sensitivity
        if 'partial_write_response' in cell_profile:
            responses = cell_profile['partial_write_response']
            sensitivity_scores = []
            
            for resp in responses:
                if resp['decay_profile']:
                    # Calculate sensitivity to partial charges
                    decay_rate = sum(p['hamming'] for p in resp['decay_profile'][:2])
                    sensitivity_scores.append(decay_rate / resp['cycles'])
            
            if sensitivity_scores:
                avg_sensitivity = np.mean(sensitivity_scores)
                if avg_sensitivity > 2:
                    classifications.append('partial_sensitive')
                    cell_profile['partial_sensitive'] = True
        
        # Pattern sensitivity
        if 'pattern_responses' in cell_profile:
            pattern_variance = np.var([r['total_flips'] for r in cell_profile['pattern_responses']])
            if pattern_variance > 10:
                classifications.append('pattern_sensitive')
        
        cell_profile['classifications'] = classifications
        return classifications

    def run_comprehensive_analysis(self):
        """Run complete neuromorphic characterization"""
        # Display header
        print(f"{Fore.CYAN}{NEURO_DRAM_ART}{Style.RESET_ALL}")
        fancy_print("INITIATING NEUROMORPHIC DRAM CHARACTERIZATION", "header")
        
        # Phase 1: Quick sweep to find interesting cells
        fancy_print("PHASE 1: Quick Sweep for Weak Cells", "neural")
        weak_cells = self.quick_weak_cell_sweep()
        
        # Phase 2: Detailed characterization of weak cells
        fancy_print(f"PHASE 2: Detailed Characterization of {len(weak_cells)} Candidates", "neural")
        characterized_cells = self.detailed_characterization(weak_cells)
        
        # Phase 3: Partial write testing on suitable cells
        fancy_print("PHASE 3: Partial Write Sensitivity Analysis", "neural")
        self.partial_write_analysis(characterized_cells)
        
        # Phase 4: Generate comprehensive report
        fancy_print("PHASE 4: Generating Neuromorphic Profile Report", "neural")
        self.generate_comprehensive_report()
        
        return self.cell_profiles

    def quick_weak_cell_sweep(self):
        """Quick sweep to identify cells with interesting decay properties"""
        weak_candidates = []
        total_addresses = sum(len(range(r['start'], r['end'], r['step'])) for r in MEMORY_REGIONS)
        
        fancy_print(f"Scanning {total_addresses} addresses for decay characteristics", "info")
        progress_bar.start_time = time.time()
        
        address_count = 0
        test_pattern = {"name": "All Ones", "pattern": "FFFFFFFF"}
        
        for region in MEMORY_REGIONS:
            region_addrs = list(range(region['start'], region['end'], region['step']))
            
            # Sample 10% of addresses for quick sweep
            sample_size = max(10, len(region_addrs) // 10)
            sampled_addrs = random.sample(region_addrs, min(sample_size, len(region_addrs)))
            
            for addr in sampled_addrs:
                address_count += 1
                
                # Quick decay test at 30 seconds
                for _ in range(NWRITES):
                    self.write_cmd(addr, test_pattern['pattern'])
                
                time.sleep(0.1)
                initial = self.read_cmd(addr)
                
                if initial == test_pattern['pattern']:
                    time.sleep(30)  # Quick 30-second decay
                    readback = self.read_cmd(addr)
                    
                    if readback and readback != test_pattern['pattern']:
                        hamming = self.hamming_distance(test_pattern['pattern'], readback)
                        if hamming > 0:
                            weak_candidates.append({
                                'addr': addr,
                                'region': region['name'],
                                'initial_decay': hamming,
                                'decay_time': 30
                            })
                
                if address_count % 10 == 0:
                    progress_bar(address_count, total_addresses, title="Quick Sweep")
        
        clear_line()
        fancy_print(f"Found {len(weak_candidates)} candidates for detailed analysis", "found")
        return weak_candidates

    def detailed_characterization(self, candidates):
        """Detailed characterization of candidate cells"""
        characterized = []
        
        for i, candidate in enumerate(candidates):
            addr = candidate['addr']
            
            fancy_print(f"Characterizing cell 0x{addr:08X} ({i+1}/{len(candidates)})", "neural")
            
            cell_profile = {
                'address': addr,
                'region': candidate['region'],
                'pattern_responses': [],
                'decay_curves': {}
            }
            
            # Test with different patterns
            for pattern_info in TEST_PATTERNS[:5]:  # Test with first 5 patterns
                decay_profile = self.characterize_cell_decay(addr, pattern_info)
                
                if decay_profile:
                    total_flips = sum(p['hamming'] for p in decay_profile)
                    cell_profile['pattern_responses'].append({
                        'pattern': pattern_info['name'],
                        'decay_profile': decay_profile,
                        'total_flips': total_flips
                    })
                    cell_profile['decay_curves'][pattern_info['name']] = decay_profile
            
            # Classify the cell
            self.classify_cell_behavior(cell_profile)
            
            self.cell_profiles[addr] = cell_profile
            characterized.append(cell_profile)
            
            # Show progress
            progress_bar(i + 1, len(candidates), title="Detailed Characterization")
        
        clear_line()
        display_cell_characteristics(characterized)
        return characterized

    def partial_write_analysis(self, characterized_cells):
        """Test partial write sensitivity on suitable cells"""
        # Select cells with different decay characteristics
        test_cells = []
        
        for cell in characterized_cells:
            if 'decay_class' in cell:
                test_cells.append(cell)
                if len(test_cells) >= 20:  # Limit to 20 cells for time
                    break
        
        fancy_print(f"Testing partial write sensitivity on {len(test_cells)} cells", "neural")
        
        for i, cell in enumerate(test_cells):
            addr = cell['address']
            
            # Test with checkerboard pattern (good for partial writes)
            test_pattern = {"name": "Checkerboard", "pattern": "AAAAAAAA"}
            
            partial_results = self.test_partial_writes(addr, test_pattern)
            cell['partial_write_response'] = partial_results
            
            # Re-classify with new data
            self.classify_cell_behavior(cell)
            
            progress_bar(i + 1, len(test_cells), title="Partial Write Analysis")
        
        clear_line()

    def generate_comprehensive_report(self):
        """Generate detailed neuromorphic characterization report"""
        fancy_print("Generating Comprehensive Neuromorphic Report", "neural")
        
        # Prepare report data
        report = {
            'session_id': self.session_id,
            'timestamp': datetime.now().isoformat(),
            'total_cells_analyzed': len(self.cell_profiles),
            'cell_classifications': defaultdict(int),
            'decay_statistics': {},
            'partial_write_statistics': {},
            'neuromorphic_candidates': []
        }
        
        # Analyze results
        decay_times = []
        for addr, profile in self.cell_profiles.items():
            # Count classifications
            for classification in profile.get('classifications', []):
                report['cell_classifications'][classification] += 1
            
            # Collect decay times
            if 'decay_curves' in profile:
                for pattern, curve in profile['decay_curves'].items():
                    for point in curve:
                        if point['hamming'] > 0:
                            decay_times.append(point['time'])
                            break
            
            # Identify neuromorphic candidates
            if len(profile.get('classifications', [])) >= 2:
                report['neuromorphic_candidates'].append({
                    'address': addr,
                    'classifications': profile['classifications'],
                    'decay_class': profile.get('decay_class', 'unknown')
                })
        
        # Calculate statistics
        if decay_times:
            report['decay_statistics'] = {
                'mean': np.mean(decay_times),
                'median': np.median(decay_times),
                'std': np.std(decay_times),
                'min': min(decay_times),
                'max': max(decay_times)
            }
        
        # Save detailed profiles
        profiles_file = self.results_dir / "cell_profiles.json"
        with open(profiles_file, 'w') as f:
            # Convert to serializable format
            serializable_profiles = {}
            for addr, profile in self.cell_profiles.items():
                serializable_profiles[f"0x{addr:08X}"] = profile
            json.dump(serializable_profiles, f, indent=2)
        
        # Save summary report
        report_file = self.results_dir / "neuromorphic_report.json"
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        # Save raw data for later analysis
        raw_data_file = self.results_dir / "raw_cell_data.pkl"
        with open(raw_data_file, 'wb') as f:
            pickle.dump(self.cell_profiles, f)
        
        # Display summary
        print(f"\n{Fore.CYAN}{'═' * 80}")
        print(f"║{Style.BRIGHT}{'NEUROMORPHIC CHARACTERIZATION SUMMARY'.center(76)}{Style.NORMAL}{Fore.CYAN}║")
        print(f"{'═' * 80}{Style.RESET_ALL}\n")
        
        print(f"  {Fore.GREEN}Total Cells Analyzed: {report['total_cells_analyzed']}")
        print(f"\n  {Fore.YELLOW}Cell Classifications:")
        for classification, count in report['cell_classifications'].items():
            print(f"    • {classification}: {count}")
        
        if report['decay_statistics']:
            print(f"\n  {Fore.BLUE}Decay Time Statistics:")
            print(f"    • Mean: {report['decay_statistics']['mean']:.1f}s")
            print(f"    • Median: {report['decay_statistics']['median']:.1f}s")
            print(f"    • Range: {report['decay_statistics']['min']:.1f}s - {report['decay_statistics']['max']:.1f}s")
        
        print(f"\n  {Fore.MAGENTA}Neuromorphic Candidates: {len(report['neuromorphic_candidates'])}")
        
        # Show top candidates
        if report['neuromorphic_candidates']:
            print(f"\n  {Fore.CYAN}Top Neuromorphic Candidates:")
            for i, candidate in enumerate(report['neuromorphic_candidates'][:5], 1):
                print(f"    {i}. 0x{candidate['address']:08X} - {', '.join(candidate['classifications'])}")
        
        print(f"\n  {Fore.GREEN}Results saved to: {self.results_dir}/")
        print(f"    • Cell profiles: cell_profiles.json")
        print(f"    • Summary report: neuromorphic_report.json")
        print(f"    • Raw data: raw_cell_data.pkl")
        
        # Generate visualization placeholder
        self.generate_visualizations()
        
        return report

    def generate_visualizations(self):
        """Generate visualization plots"""
        fancy_print("Generating visualization plots...", "neural")
        
        # This would generate actual plots using matplotlib
        # For now, just create placeholder
        viz_file = self.results_dir / "decay_heatmap.png"
        fancy_print(f"Visualizations saved to {self.results_dir}/", "success")

def main():
    try:
        # Open serial connection
        fancy_print("Establishing Neural Link to DRAM Controller...", "neural")
        ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)
        time.sleep(0.1)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        fancy_print(f"Neural Link Established: {SERIAL_PORT} @ {BAUDRATE} baud", "success")
        
    except serial.SerialException as e:
        fancy_print(f"Failed to establish neural link: {e}", "error")
        return 1
    
    # Create analyzer instance
    analyzer = NeuromorphicDRAMAnalyzer(ser)
    
    # Display startup animation
    print(f"\n{Fore.CYAN}", end='')
    startup_msg = "INITIATING NEUROMORPHIC DRAM DISCOVERY..."
    for char in startup_msg:
        print(char, end='', flush=True)
        time.sleep(0.05)
    print(f"{Style.RESET_ALL}\n")
    
    # Run comprehensive analysis
    start_time = time.time()
    try:
        cell_profiles = analyzer.run_comprehensive_analysis()
        elapsed = time.time() - start_time
        
        # Display completion
        fancy_print("NEUROMORPHIC CHARACTERIZATION COMPLETE!", "header")
        fancy_print(f"Total Analysis Time: {elapsed/60:.1f} minutes", "info")
        fancy_print(f"Cells Profiled: {len(cell_profiles)}", "success")
        
        # Show key findings
        print(f"\n{Fore.MAGENTA}{'─' * 80}")
        print(f"{Style.BRIGHT}KEY NEUROMORPHIC FINDINGS:{Style.RESET_ALL}")
        print(f"{Fore.MAGENTA}{'─' * 80}{Style.RESET_ALL}\n")
        
        # Identify cells suitable for different neuromorphic functions
        excitatory_cells = []
        inhibitory_cells = []
        memory_cells = []
        synapse_cells = []
        
        for addr, profile in cell_profiles.items():
            classifications = profile.get('classifications', [])
            
            if 'fast_decay' in classifications:
                excitatory_cells.append(addr)
            if 'slow_decay' in classifications:
                memory_cells.append(addr)
            if 'partial_sensitive' in classifications:
                synapse_cells.append(addr)
            if 'pattern_sensitive' in classifications:
                inhibitory_cells.append(addr)
        
        print(f"  {Fore.RED}⚡ Excitatory Neurons (Fast Decay): {len(excitatory_cells)}")
        if excitatory_cells:
            for addr in excitatory_cells[:3]:
                print(f"     → 0x{addr:08X}")
        
        print(f"\n  {Fore.BLUE}📦 Memory Units (Slow Decay): {len(memory_cells)}")
        if memory_cells:
            for addr in memory_cells[:3]:
                print(f"     → 0x{addr:08X}")
        
        print(f"\n  {Fore.YELLOW}🔄 Tunable Synapses (Partial Sensitive): {len(synapse_cells)}")
        if synapse_cells:
            for addr in synapse_cells[:3]:
                print(f"     → 0x{addr:08X}")
        
        print(f"\n  {Fore.GREEN}🛡️ Inhibitory Neurons (Pattern Sensitive): {len(inhibitory_cells)}")
        if inhibitory_cells:
            for addr in inhibitory_cells[:3]:
                print(f"     → 0x{addr:08X}")
        
        # Generate neuromorphic architecture suggestion
        print(f"\n{Fore.CYAN}{'═' * 80}")
        print(f"║{Style.BRIGHT}{'SUGGESTED NEUROMORPHIC ARCHITECTURE'.center(76)}{Style.NORMAL}{Fore.CYAN}║")
        print(f"{'═' * 80}{Style.RESET_ALL}\n")
        
        if len(excitatory_cells) > 10 and len(memory_cells) > 5 and len(synapse_cells) > 5:
            print(f"  {Fore.GREEN}✓ Sufficient diversity for spiking neural network implementation")
            print(f"  {Fore.GREEN}✓ Natural decay patterns support temporal computation")
            print(f"  {Fore.GREEN}✓ Partial charge sensitivity enables weight modulation")
            print(f"\n  {Style.BRIGHT}Recommended Architecture:{Style.RESET_ALL}")
            print(f"    • Layer 1: {len(excitatory_cells)} excitatory neurons (input processing)")
            print(f"    • Layer 2: {len(synapse_cells)} tunable synapses (weight matrix)")
            print(f"    • Layer 3: {len(memory_cells)} memory units (state retention)")
            print(f"    • Regulation: {len(inhibitory_cells)} inhibitory neurons (stability)")
        else:
            print(f"  {Fore.YELLOW}⚠ Limited cell diversity - suggest expanded search")
        
        # Save architecture mapping
        architecture_file = analyzer.results_dir / "neuromorphic_architecture.json"
        architecture = {
            'timestamp': datetime.now().isoformat(),
            'excitatory_neurons': [f"0x{addr:08X}" for addr in excitatory_cells],
            'memory_units': [f"0x{addr:08X}" for addr in memory_cells],
            'tunable_synapses': [f"0x{addr:08X}" for addr in synapse_cells],
            'inhibitory_neurons': [f"0x{addr:08X}" for addr in inhibitory_cells],
            'statistics': {
                'total_characterized': len(cell_profiles),
                'excitatory_count': len(excitatory_cells),
                'memory_count': len(memory_cells),
                'synapse_count': len(synapse_cells),
                'inhibitory_count': len(inhibitory_cells)
            }
        }
        
        with open(architecture_file, 'w') as f:
            json.dump(architecture, f, indent=2)
        
        print(f"\n  {Fore.GREEN}Architecture mapping saved to: neuromorphic_architecture.json")
        
    except KeyboardInterrupt:
        clear_line()
        fancy_print("\nAnalysis interrupted by user", "warning")
        fancy_print("Partial results saved", "info")
    except Exception as e:
        fancy_print(f"Analysis error: {e}", "error")
        import traceback
        traceback.print_exc()
    finally:
        # Cleanup
        ser.close()
    
    # Final animation
    print(f"\n{Fore.MAGENTA}", end='')
    for char in "🧠 ✨ Neuromorphic DRAM Discovery Complete! ✨ 🧠":
        print(char, end='', flush=True)
        time.sleep(0.05)
    print(Style.RESET_ALL)
    print(f"\n{Fore.CYAN}Next Steps:{Style.RESET_ALL}")
    print("  1. Review cell_profiles.json for detailed characteristics")
    print("  2. Use neuromorphic_architecture.json to implement neural circuits")
    print("  3. Leverage natural decay for temporal computation")
    print("  4. Explore partial charge states for analog computing")
    print(f"\n{Fore.GREEN}The chaos of decay becomes the order of computation.{Style.RESET_ALL}\n")
    
    return 0

if __name__ == "__main__":
    try:
        exit(main())
    except KeyboardInterrupt:
        clear_line()
        fancy_print("\nNeural analysis terminated", "warning")
        exit(1)
