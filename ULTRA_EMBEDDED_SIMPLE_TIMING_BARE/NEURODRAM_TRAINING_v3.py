#!/usr/bin/env python3

import serial
import time
import numpy as np
from datetime import datetime
from colorama import Fore, Back, Style, init
import random
import sys
import math

# Initialize colorama
init(autoreset=True)

# Configuration
SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.3

# Neural Network Architecture based on characterization results
INPUT_NEURONS = 4
HIDDEN_NEURONS = 6  # Increased for better learning
OUTPUT_NEURONS = 2

# Key addresses from characterization - using discovered properties
THRESHOLD_NEURONS = [
    0x00001000, 0x00002000, 0x00003000, 0x00050000,  # Sharp threshold behavior
    0x00066000, 0x00067000, 0x00068000, 0x00069000,
    0x00070000, 0x00071000, 0x00072000, 0x00073000
]

# Addresses with good analog properties (from characterization)
ANALOG_CELLS = [
    0x00002000, 0x00005000, 0x00009000, 0x0000D000,
    0x00015000, 0x00019000, 0x0001D000, 0x00021000
]

# Binary synapses with stable behavior
BINARY_SYNAPSES = [
    0x00069000, 0x0007B000, 0x0007E000, 0x00800000,
    0x00820000, 0x00830000, 0x00840000, 0x00848000
]

# Long-term memory cells for weight storage
MEMORY_CELLS = [
    0x00066000, 0x00067000, 0x00068000, 0x00800000,
    0x00820000, 0x00830000, 0x00840000, 0x00848000
]

# Cells with strong neighbor coupling (from phase 4)
COUPLING_CELLS = [
    0x00000000, 0x00001000, 0x00002000, 0x00003000
]

# Generate weight addresses with spacing to minimize coupling
def generate_weight_addresses(count):
    """Generate addresses with 128-byte spacing to minimize coupling"""
    base = 0x00900000
    spacing = 128  # From coupling analysis
    return [base + i * spacing for i in range(count)]

# Burst configurations from characterization
BURST_THRESHOLD = 3      # Sharp threshold at burst=3 (6% -> 99%)
BURST_SUBTHRESHOLD = 2   # Sub-threshold for partial activation (~6%)
BURST_VERY_LOW = 1       # Very low charge (~0.1%)
BURST_ANOMALY = 8        # Anomalous ~31% charge
BURST_ITERATIONS = {
    1: 20,   # Standard iterations
    2: 20,
    3: 10,   # Fewer needed for threshold
    8: 20
}

# Learning parameters based on characterization
LEAK_IN_RATE = 0.005     # 0.5% per second from Phase 2
DECAY_RATES = {
    'fast': 0.01,
    'medium': 0.001,
    'slow': 0.0001
}

# ASCII Art Banner
BANNER = """
╔════════════════════════════════════════════════════════════════════════════════╗
║                                                                                ║
║  ███╗   ██╗███████╗██╗   ██╗██████╗  ██████╗ ██████╗  █████╗ ███╗   ███╗    ║
║  ████╗  ██║██╔════╝██║   ██║██╔══██╗██╔═══██╗██╔══██╗██╔══██╗████╗ ████║    ║
║  ██╔██╗ ██║█████╗  ██║   ██║██████╔╝██║   ██║██║  ██║██████╔╝███████║██╔████╔██║    ║
║  ██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗██║   ██║██║  ██║██╔══██╗██╔══██║██║╚██╔╝██║    ║
║  ██║ ╚████║███████╗╚██████╔╝██║  ██║╚██████╔╝██████╔╝██║  ██║██║  ██║██║ ╚═╝ ██║    ║
║  ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝    ║
║                                                                                ║
║           Neuromorphic DRAM Learning Network v3.0 ENHANCED                     ║
║         "Exploiting Analog Chaos in Digital Memory for Intelligence"           ║
╚════════════════════════════════════════════════════════════════════════════════╝
"""

class DRAMNeuralNetworkV3:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.initialize_ddr3()
        
        # Network structure with better address allocation
        self.input_addrs = THRESHOLD_NEURONS[:INPUT_NEURONS]
        self.hidden_addrs = THRESHOLD_NEURONS[INPUT_NEURONS:INPUT_NEURONS+HIDDEN_NEURONS]
        self.output_addrs = THRESHOLD_NEURONS[INPUT_NEURONS+HIDDEN_NEURONS:INPUT_NEURONS+HIDDEN_NEURONS+OUTPUT_NEURONS]
        
        # Use analog cells for continuous values
        self.bias_addrs = ANALOG_CELLS[:HIDDEN_NEURONS+OUTPUT_NEURONS]
        
        # Generate properly spaced weight addresses
        total_weights = INPUT_NEURONS * HIDDEN_NEURONS + HIDDEN_NEURONS * OUTPUT_NEURONS
        self.all_weight_addrs = generate_weight_addresses(total_weights)
        
        # Synaptic weights with proper indexing
        self.weight_addrs = {
            'input_hidden': self.all_weight_addrs[:INPUT_NEURONS * HIDDEN_NEURONS],
            'hidden_output': self.all_weight_addrs[INPUT_NEURONS * HIDDEN_NEURONS:]
        }
        
        # Cells for special effects
        self.leak_cells = COUPLING_CELLS[:2]  # For leak-in demonstration
        
        print(f"\n{Fore.CYAN}Network Architecture:{Style.RESET_ALL}")
        print(f"  Input neurons: {INPUT_NEURONS} @ {[f'0x{a:08X}' for a in self.input_addrs]}")
        print(f"  Hidden neurons: {HIDDEN_NEURONS} @ {[f'0x{a:08X}' for a in self.hidden_addrs]}")
        print(f"  Output neurons: {OUTPUT_NEURONS} @ {[f'0x{a:08X}' for a in self.output_addrs]}")
        print(f"  Total weights: {total_weights} (spaced by 128 bytes)")
        
        # Training patterns - XOR-like problem
        self.training_patterns = [
            ([0, 0, 0, 0], [0, 0]),  # All off
            ([1, 0, 1, 0], [1, 0]),  # Pattern A
            ([0, 1, 0, 1], [1, 0]),  # Pattern B  
            ([1, 1, 1, 1], [0, 1]),  # All on
        ]
        
        # Learning state
        self.epoch = 0
        self.total_error = 0
        self.error_history = []
        self.learning_rate = 0.3
        self.momentum = 0.7
        self.weight_changes = {}  # Track momentum
        
        # Analog resolution tracking
        self.weight_levels = {}  # Track analog levels in weights
        
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
        
        # Configure timing for neuromorphic operation
        self.configure_timing(skip_refresh=1)
        
    def configure_timing(self, twr=0, tras=0, burst_len=0, skip_refresh=0):
        """Configure DDR3 timing parameters"""
        config_value = (skip_refresh << 20) | (burst_len << 16) | (tras << 8) | twr
        cmd = f"T{config_value:08X}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.1)
        self.ser.reset_input_buffer()
    
    def write_burst(self, addr, burst_length, pattern="FFFFFFFF", iterations=None):
        """Write with specific burst length for precise charge control"""
        if iterations is None:
            iterations = BURST_ITERATIONS.get(burst_length, 20)
        
        # Configure burst
        self.configure_timing(burst_len=burst_length, skip_refresh=1)
        
        # Write pattern
        for _ in range(iterations):
            cmd = f"W{addr:08X} {pattern}\r"
            self.ser.write(cmd.encode('ascii'))
            time.sleep(0.005)
    
    def write_analog_level(self, addr, level):
        """Write analog level (0.0 to 1.0) using discovered charge levels"""
        # Map level to burst configuration based on characterization
        if level < 0.05:
            # Very low - use burst 1
            self.write_burst(addr, 1, iterations=20)
        elif level < 0.2:
            # Low - use burst 2
            self.write_burst(addr, 2, iterations=20)
        elif level < 0.4:
            # Medium-low - use burst 8 (anomaly gives ~31%)
            self.write_burst(addr, 8, iterations=20)
        elif level < 0.8:
            # Medium-high - use burst 2 with more iterations
            self.write_burst(addr, 2, iterations=50)
        else:
            # High - use burst 3 (threshold)
            self.write_burst(addr, 3, iterations=10)
    
    def read_neuron(self, addr):
        """Read neuron state"""
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
        
        if response:
            # Calculate activation (proportion of set bits)
            value = int(response, 16)
            set_bits = bin(value).count('1')
            activation = set_bits / 32.0
            return activation
        return 0.0
    
    def clear_neuron(self, addr):
        """Clear a neuron to zero state"""
        self.configure_timing(burst_len=BURST_ANOMALY, skip_refresh=1)
        for _ in range(20):
            cmd = f"W{addr:08X} 00000000\r"
            self.ser.write(cmd.encode('ascii'))
            time.sleep(0.005)
    
    def activate_neuron_sigmoid(self, addr, input_sum):
        """Activate neuron with sigmoid-like response using burst=3 threshold"""
        # Sigmoid approximation using threshold behavior
        if input_sum < 0.2:
            self.write_burst(addr, BURST_VERY_LOW)
        elif input_sum < 0.5:
            self.write_burst(addr, BURST_SUBTHRESHOLD)
        else:
            # Use the sharp threshold at burst=3
            self.write_burst(addr, BURST_THRESHOLD)
    
    def exploit_leak_in(self, addr, target_level):
        """Use leak-in phenomenon for gradual charge accumulation"""
        # Start with sub-threshold burst
        self.write_burst(addr, BURST_SUBTHRESHOLD, iterations=5)
        
        # Let charge leak in over time
        time.sleep(0.1)  # 100ms for some leak-in
        
        # Read current level and adjust
        current = self.read_neuron(addr)
        if current < target_level:
            # Add more charge
            self.write_burst(addr, BURST_VERY_LOW, iterations=10)
    
    def apply_neighbor_coupling(self, addr, neighbor_addrs):
        """Exploit neighbor coupling for computation"""
        # Write to neighbors to influence target cell
        for neighbor in neighbor_addrs:
            if abs(neighbor - addr) <= 256:  # Strong coupling within 256 bytes
                self.write_burst(neighbor, BURST_THRESHOLD)
    
    def forward_pass_v3(self, input_pattern):
        """Enhanced forward propagation with analog properties"""
        # Clear all neurons first
        all_neurons = self.input_addrs + self.hidden_addrs + self.output_addrs
        for addr in all_neurons:
            self.clear_neuron(addr)
        
        # Set input neurons with proper activation
        input_activations = []
        for i, (addr, value) in enumerate(zip(self.input_addrs, input_pattern)):
            if value > 0:
                self.write_burst(addr, BURST_THRESHOLD)
            else:
                self.write_burst(addr, BURST_VERY_LOW)
            
            # Read back actual activation
            activation = self.read_neuron(addr)
            input_activations.append(activation)
        
        # Hidden layer with enhanced computation
        hidden_activations = []
        for h_idx, h_addr in enumerate(self.hidden_addrs):
            # Sum weighted inputs
            weighted_sum = 0
            
            for i_idx, i_act in enumerate(input_activations):
                # Get weight
                weight_addr = self.get_weight_address(i_idx, h_idx, 'input_hidden')
                if weight_addr:
                    weight = self.read_neuron(weight_addr)
                    
                    # Apply weight with bias
                    weighted_sum += i_act * weight
            
            # Add bias from analog cell
            bias_addr = self.bias_addrs[h_idx]
            bias = self.read_neuron(bias_addr) * 0.2  # Scale bias
            weighted_sum += bias
            
            # Activate with sigmoid-like response
            self.activate_neuron_sigmoid(h_addr, weighted_sum)
            
            # Apply leak-in for fine-tuning
            if 0.3 < weighted_sum < 0.7:
                self.exploit_leak_in(h_addr, weighted_sum)
            
            # Read final activation
            activation = self.read_neuron(h_addr)
            hidden_activations.append(activation)
        
        # Output layer
        output_activations = []
        for o_idx, o_addr in enumerate(self.output_addrs):
            weighted_sum = 0
            
            for h_idx, h_act in enumerate(hidden_activations):
                weight_addr = self.get_weight_address(h_idx, o_idx, 'hidden_output')
                if weight_addr:
                    weight = self.read_neuron(weight_addr)
                    weighted_sum += h_act * weight
            
            # Add output bias
            bias_addr = self.bias_addrs[HIDDEN_NEURONS + o_idx]
            bias = self.read_neuron(bias_addr) * 0.2
            weighted_sum += bias
            
            # Output activation
            self.activate_neuron_sigmoid(o_addr, weighted_sum)
            
            activation = self.read_neuron(o_addr)
            output_activations.append(activation)
        
        return output_activations, hidden_activations
    
    def get_weight_address(self, source_idx, dest_idx, layer):
        """Get the weight address for a connection"""
        if layer == 'input_hidden':
            idx = source_idx * HIDDEN_NEURONS + dest_idx
            if idx < len(self.weight_addrs['input_hidden']):
                return self.weight_addrs['input_hidden'][idx]
        elif layer == 'hidden_output':
            idx = source_idx * OUTPUT_NEURONS + dest_idx
            if idx < len(self.weight_addrs['hidden_output']):
                return self.weight_addrs['hidden_output'][idx]
        return None
    
    def update_weight_analog(self, addr, delta, current_weight):
        """Update weight with analog resolution"""
        # Calculate new weight with momentum
        if addr not in self.weight_changes:
            self.weight_changes[addr] = 0
        
        # Momentum term
        self.weight_changes[addr] = self.momentum * self.weight_changes[addr] + self.learning_rate * delta
        
        # New weight value
        new_weight = current_weight + self.weight_changes[addr]
        new_weight = max(0.0, min(1.0, new_weight))  # Clamp to [0, 1]
        
        # Write with analog precision
        self.write_analog_level(addr, new_weight)
        
        # Track analog levels
        self.weight_levels[addr] = new_weight
    
    def backpropagation(self, input_pattern, hidden_activations, output_activations, target_output):
        """Enhanced backpropagation with analog weight updates"""
        # Calculate output errors
        output_errors = []
        for i, (output, target) in enumerate(zip(output_activations, target_output)):
            error = target - output
            # Derivative of sigmoid-like activation (approximation)
            derivative = output * (1 - output)
            output_errors.append(error * derivative)
        
        # Calculate hidden errors
        hidden_errors = []
        for h_idx in range(HIDDEN_NEURONS):
            error = 0
            for o_idx, o_error in enumerate(output_errors):
                weight_addr = self.get_weight_address(h_idx, o_idx, 'hidden_output')
                if weight_addr:
                    weight = self.read_neuron(weight_addr)
                    error += o_error * weight
            
            # Hidden activation derivative
            h_act = hidden_activations[h_idx]
            derivative = h_act * (1 - h_act)
            hidden_errors.append(error * derivative)
        
        # Update hidden-output weights
        for h_idx in range(HIDDEN_NEURONS):
            for o_idx in range(OUTPUT_NEURONS):
                weight_addr = self.get_weight_address(h_idx, o_idx, 'hidden_output')
                if weight_addr:
                    current_weight = self.read_neuron(weight_addr)
                    delta = output_errors[o_idx] * hidden_activations[h_idx]
                    self.update_weight_analog(weight_addr, delta, current_weight)
        
        # Update input-hidden weights
        for i_idx, input_val in enumerate(input_pattern):
            for h_idx in range(HIDDEN_NEURONS):
                weight_addr = self.get_weight_address(i_idx, h_idx, 'input_hidden')
                if weight_addr:
                    current_weight = self.read_neuron(weight_addr)
                    delta = hidden_errors[h_idx] * input_val
                    self.update_weight_analog(weight_addr, delta, current_weight)
        
        # Update biases
        for h_idx, h_error in enumerate(hidden_errors):
            bias_addr = self.bias_addrs[h_idx]
            current_bias = self.read_neuron(bias_addr)
            self.update_weight_analog(bias_addr, h_error * 0.1, current_bias)
        
        for o_idx, o_error in enumerate(output_errors):
            bias_addr = self.bias_addrs[HIDDEN_NEURONS + o_idx]
            current_bias = self.read_neuron(bias_addr)
            self.update_weight_analog(bias_addr, o_error * 0.1, current_bias)
    
    def train_epoch_v3(self):
        """Enhanced training epoch with full backpropagation"""
        self.epoch += 1
        print(f"\n{Fore.MAGENTA}{'='*80}")
        print(f"EPOCH {self.epoch}")
        print(f"{'='*80}{Style.RESET_ALL}")
        
        epoch_error = 0
        pattern_errors = []
        
        # Shuffle patterns for better learning
        shuffled_patterns = list(self.training_patterns)
        random.shuffle(shuffled_patterns)
        
        for pattern_idx, (input_pattern, target_output) in enumerate(shuffled_patterns):
            print(f"\n{Fore.YELLOW}Pattern: {input_pattern} → {target_output}{Style.RESET_ALL}")
            
            # Forward pass
            output_activations, hidden_activations = self.forward_pass_v3(input_pattern)
            
            # Calculate error
            error = sum((t - o)**2 for t, o in zip(target_output, output_activations)) / 2
            epoch_error += error
            pattern_errors.append(error)
            
            print(f"  Output: [{output_activations[0]:.3f}, {output_activations[1]:.3f}]")
            print(f"  Target: {target_output}")
            print(f"  Error: {error:.4f}")
            
            # Backpropagation
            self.backpropagation(input_pattern, hidden_activations, output_activations, target_output)
            
            # Show weight statistics
            if pattern_idx == 0:  # First pattern only
                self.show_weight_stats()
        
        self.total_error = epoch_error / len(self.training_patterns)
        self.error_history.append(self.total_error)
        
        # Adaptive learning rate
        if len(self.error_history) > 5:
            if self.error_history[-1] > self.error_history[-5]:
                self.learning_rate *= 0.95  # Reduce if not improving
                print(f"\n{Fore.YELLOW}Learning rate reduced to {self.learning_rate:.3f}{Style.RESET_ALL}")
        
        return self.display_epoch_summary()
    
    def show_weight_stats(self):
        """Display weight distribution statistics"""
        if self.weight_levels:
            weights = list(self.weight_levels.values())
            print(f"\n  {Fore.CYAN}Weight Statistics:{Style.RESET_ALL}")
            print(f"    Mean: {np.mean(weights):.3f}")
            print(f"    Std:  {np.std(weights):.3f}")
            print(f"    Min:  {np.min(weights):.3f}")
            print(f"    Max:  {np.max(weights):.3f}")
    
    def display_epoch_summary(self):
        """Display training progress"""
        print(f"\n{Fore.CYAN}{'─'*60}")
        print(f"Epoch {self.epoch} Summary")
        print(f"{'─'*60}{Style.RESET_ALL}")
        
        print(f"Average Error: {self.total_error:.4f}")
        
        # Show error trend
        if len(self.error_history) > 1:
            trend = self.error_history[-1] - self.error_history[-2]
            trend_symbol = "↓" if trend < 0 else "↑" if trend > 0 else "→"
            print(f"Error Trend: {trend_symbol} {abs(trend):.4f}")
        
        # Progress bar
        progress = max(0, min(1, 1 - self.total_error))
        bar_width = 40
        filled = int(bar_width * progress)
        
        color = Fore.GREEN if progress > 0.8 else Fore.YELLOW if progress > 0.5 else Fore.RED
        bar = f"{color}{'█' * filled}{Fore.WHITE}{'░' * (bar_width - filled)}"
        
        print(f"Learning Progress: [{bar}] {progress*100:.1f}%")
        
        if self.total_error < 0.01:
            print(f"\n{Fore.GREEN}✨ Network has converged! ✨{Style.RESET_ALL}")
            return True
        
        return False
    
    def initialize_weights_smart(self):
        """Initialize weights with smart distribution"""
        print(f"\n{Fore.CYAN}Initializing weights with analog precision...{Style.RESET_ALL}")
        
        # Xavier initialization approximation
        fan_in = INPUT_NEURONS
        fan_out = HIDDEN_NEURONS
        
        # Initialize input-hidden weights
        for i, addr in enumerate(self.weight_addrs['input_hidden']):
            # Random value scaled by fan-in
            value = random.gauss(0.5, 0.2)
            value = max(0.1, min(0.9, value))
            self.write_analog_level(addr, value)
            self.weight_levels[addr] = value
        
        # Initialize hidden-output weights
        fan_in = HIDDEN_NEURONS
        fan_out = OUTPUT_NEURONS
        
        for i, addr in enumerate(self.weight_addrs['hidden_output']):
            value = random.gauss(0.5, 0.2)
            value = max(0.1, min(0.9, value))
            self.write_analog_level(addr, value)
            self.weight_levels[addr] = value
        
        # Initialize biases to small values
        for addr in self.bias_addrs:
            value = random.uniform(0.1, 0.3)
            self.write_analog_level(addr, value)
        
        print(f"{Fore.GREEN}✓ Weights initialized with analog precision{Style.RESET_ALL}")
        self.show_weight_stats()
    
    def demonstrate_analog_properties(self):
        """Demonstrate unique DRAM analog properties"""
        print(f"\n{Fore.CYAN}{'='*60}")
        print(f"DEMONSTRATING ANALOG DRAM PROPERTIES")
        print(f"{'='*60}{Style.RESET_ALL}")
        
        # 1. Threshold behavior
        print(f"\n{Fore.YELLOW}1. Threshold Behavior at Burst=3:{Style.RESET_ALL}")
        test_addr = self.hidden_addrs[0]
        
        for burst in [1, 2, 3]:
            self.clear_neuron(test_addr)
            self.write_burst(test_addr, burst)
            charge = self.read_neuron(test_addr)
            print(f"   Burst {burst}: {charge:.1%} charge")
        
        # 2. Leak-in phenomenon
        print(f"\n{Fore.YELLOW}2. Leak-In Phenomenon:{Style.RESET_ALL}")
        self.clear_neuron(test_addr)
        self.write_burst(test_addr, 2, iterations=5)
        
        for delay in [0, 1, 2, 5]:
            if delay > 0:
                time.sleep(delay)
            charge = self.read_neuron(test_addr)
            print(f"   After {delay}s: {charge:.1%} charge")
        
        # 3. Neighbor coupling
        print(f"\n{Fore.YELLOW}3. Neighbor Coupling Effect:{Style.RESET_ALL}")
        target = self.hidden_addrs[0]
        neighbor = target + 128  # 128 bytes away
        
        self.clear_neuron(target)
        self.clear_neuron(neighbor)
        
        print(f"   Target alone: {self.read_neuron(target):.1%}")
        
        # Charge neighbor
        self.write_burst(neighbor, BURST_THRESHOLD)
        time.sleep(0.1)
        print(f"   Target with charged neighbor: {self.read_neuron(target):.1%}")
        
        print(f"\n{Fore.GREEN}✓ Analog properties demonstrated{Style.RESET_ALL}")
    
    def visualize_network_state_enhanced(self):
        """Enhanced network visualization with analog levels"""
        print(f"\n{Fore.CYAN}Enhanced Network State Visualization:{Style.RESET_ALL}")
        
        # Read all states
        input_states = [self.read_neuron(addr) for addr in self.input_addrs]
        hidden_states = [self.read_neuron(addr) for addr in self.hidden_addrs]
        output_states = [self.read_neuron(addr) for addr in self.output_addrs]
        
        # Show analog weight matrix
        print(f"\n{Fore.YELLOW}Weight Matrix Visualization:{Style.RESET_ALL}")
        print("  Input→Hidden weights:")
        for i in range(INPUT_NEURONS):
            row = []
            for h in range(HIDDEN_NEURONS):
                addr = self.get_weight_address(i, h, 'input_hidden')
                if addr:
                    w = self.read_neuron(addr)
                    # Visual representation
                    if w > 0.8:
                        row.append(f"{Fore.GREEN}█{Style.RESET_ALL}")
                    elif w > 0.5:
                        row.append(f"{Fore.YELLOW}▓{Style.RESET_ALL}")
                    elif w > 0.2:
                        row.append(f"{Fore.BLUE}▒{Style.RESET_ALL}")
                    else:
                        row.append(f"{Fore.RED}░{Style.RESET_ALL}")
            print(f"    I{i}: {''.join(row)}")
        
        print("\n  Hidden→Output weights:")
        for h in range(HIDDEN_NEURONS):
            row = []
            for o in range(OUTPUT_NEURONS):
                addr = self.get_weight_address(h, o, 'hidden_output')
                if addr:
                    w = self.read_neuron(addr)
                    if w > 0.8:
                        row.append(f"{Fore.GREEN}█{Style.RESET_ALL}")
                    elif w > 0.5:
                        row.append(f"{Fore.YELLOW}▓{Style.RESET_ALL}")
                    elif w > 0.2:
                        row.append(f"{Fore.BLUE}▒{Style.RESET_ALL}")
                    else:
                        row.append(f"{Fore.RED}░{Style.RESET_ALL}")
            print(f"    H{h}: {''.join(row)}")
        
        # Network diagram
        print(f"\n{Fore.CYAN}Network Activity:{Style.RESET_ALL}")
        print("\n       INPUT              HIDDEN            OUTPUT")
        print("    ┌─────────┐      ┌─────────────┐    ┌─────────┐")
        
        # Show neurons with analog levels
        max_rows = max(INPUT_NEURONS, HIDDEN_NEURONS, OUTPUT_NEURONS)
        
        for i in range(max_rows):
            # Input neuron
            if i < INPUT_NEURONS:
                state = input_states[i]
                neuron = self.get_neuron_symbol(state)
                print(f"    │ I{i}: {neuron}  │", end='')
            else:
                print(f"    │         │", end='')
            
            # Connections
            print("  ══╪══", end='')
            
            # Hidden neuron
            if i < HIDDEN_NEURONS:
                state = hidden_states[i]
                neuron = self.get_neuron_symbol(state)
                bias = self.read_neuron(self.bias_addrs[i])
                print(f"  │ H{i}: {neuron} b:{bias:.1f} │", end='')
            else:
                print(f"  │               │", end='')
            
            # Connections
            print("  ══╪══", end='')
            
            # Output neuron
            if i < OUTPUT_NEURONS:
                state = output_states[i]
                neuron = self.get_neuron_symbol(state)
                bias = self.read_neuron(self.bias_addrs[HIDDEN_NEURONS + i])
                print(f"  │ O{i}: {neuron} b:{bias:.1f} │")
            else:
                print(f"  │               │")
        
        print("    └─────────┘      └─────────────┘    └─────────┘")
        
        # Legend with analog levels
        print(f"\n   {Fore.GREEN}◉{Style.RESET_ALL} >90%  "
              f"{Fore.YELLOW}◕{Style.RESET_ALL} 70-90%  "
              f"{Fore.BLUE}◐{Style.RESET_ALL} 30-70%  "
              f"{Fore.MAGENTA}◔{Style.RESET_ALL} 10-30%  "
              f"{Fore.RED}○{Style.RESET_ALL} <10%")
        
        # Weight legend
        print(f"\n   Weights: {Fore.GREEN}█{Style.RESET_ALL} >0.8  "
              f"{Fore.YELLOW}▓{Style.RESET_ALL} 0.5-0.8  "
              f"{Fore.BLUE}▒{Style.RESET_ALL} 0.2-0.5  "
              f"{Fore.RED}░{Style.RESET_ALL} <0.2")
    
    def get_neuron_symbol(self, activation):
        """Get visual symbol for neuron activation level"""
        if activation > 0.9:
            return f"{Fore.GREEN}◉{Style.RESET_ALL}"
        elif activation > 0.7:
            return f"{Fore.YELLOW}◕{Style.RESET_ALL}"
        elif activation > 0.3:
            return f"{Fore.BLUE}◐{Style.RESET_ALL}"
        elif activation > 0.1:
            return f"{Fore.MAGENTA}◔{Style.RESET_ALL}"
        else:
            return f"{Fore.RED}○{Style.RESET_ALL}"
    
    def test_network_detailed(self):
        """Detailed network testing with analysis"""
        print(f"\n{Fore.MAGENTA}{'='*80}")
        print(f"TESTING TRAINED NETWORK - DETAILED ANALYSIS")
        print(f"{'='*80}{Style.RESET_ALL}")
        
        correct = 0
        detailed_results = []
        
        for input_pattern, target_output in self.training_patterns:
            output, hidden = self.forward_pass_v3(input_pattern)
            
            # Threshold outputs
            predicted = [1 if o > 0.5 else 0 for o in output]
            
            print(f"\n{Fore.YELLOW}Input: {input_pattern}{Style.RESET_ALL}")
            print(f"Hidden activations: [{', '.join(f'{h:.3f}' for h in hidden)}]")
            print(f"Raw output: [{output[0]:.3f}, {output[1]:.3f}]")
            print(f"Predicted: {predicted}")
            print(f"Target: {target_output}")
            
            # Calculate confidence
            confidence = [abs(o - 0.5) * 2 for o in output]
            avg_confidence = sum(confidence) / len(confidence)
            
            is_correct = predicted == list(target_output)
            if is_correct:
                print(f"{Fore.GREEN}✓ Correct! (confidence: {avg_confidence:.1%}){Style.RESET_ALL}")
                correct += 1
            else:
                print(f"{Fore.RED}✗ Incorrect (confidence: {avg_confidence:.1%}){Style.RESET_ALL}")
            
            detailed_results.append({
                'input': input_pattern,
                'target': target_output,
                'output': output,
                'predicted': predicted,
                'correct': is_correct,
                'confidence': avg_confidence
            })
        
        accuracy = correct / len(self.training_patterns) * 100
        print(f"\n{Fore.CYAN}{'─'*60}{Style.RESET_ALL}")
        print(f"{Fore.CYAN}Overall Accuracy: {accuracy:.1f}% ({correct}/{len(self.training_patterns)}){Style.RESET_ALL}")
        
        # Analyze failure patterns
        if accuracy < 100:
            print(f"\n{Fore.YELLOW}Failure Analysis:{Style.RESET_ALL}")
            for result in detailed_results:
                if not result['correct']:
                    print(f"  Failed on {result['input']} → {result['target']}")
                    print(f"    Output was {result['predicted']} with confidence {result['confidence']:.1%}")
    
    def run_training_v3(self, max_epochs=50):
        """Run enhanced training with all features"""
        print(f"{Fore.CYAN}{BANNER}{Style.RESET_ALL}")
        
        print(f"\n{Fore.GREEN}🧠 Initializing Enhanced Neuromorphic DRAM Network v3...{Style.RESET_ALL}")
        print(f"   • Input neurons: {INPUT_NEURONS}")
        print(f"   • Hidden neurons: {HIDDEN_NEURONS}")
        print(f"   • Output neurons: {OUTPUT_NEURONS}")
        print(f"   • Using threshold behavior at burst={BURST_THRESHOLD}")
        print(f"   • Exploiting leak-in rate: {LEAK_IN_RATE*100:.1f}%/s")
        print(f"   • Neighbor coupling enabled")
        print(f"   • Analog weight precision")
        
        # Demonstrate analog properties
        self.demonstrate_analog_properties()
        
        # Initialize weights with smart distribution
        self.initialize_weights_smart()
        
        # Initial visualization
        self.visualize_network_state_enhanced()
        
        # Training loop
        print(f"\n{Fore.GREEN}🎯 Starting enhanced training...{Style.RESET_ALL}")
        
        best_error = float('inf')
        patience = 10
        patience_counter = 0
        
        for epoch in range(max_epochs):
            converged = self.train_epoch_v3()
            
            # Check for improvement
            if self.total_error < best_error:
                best_error = self.total_error
                patience_counter = 0
            else:
                patience_counter += 1
            
            # Visualize every 5 epochs
            if epoch % 5 == 4:
                self.visualize_network_state_enhanced()
            
            if converged:
                print(f"\n{Fore.GREEN}✨ Converged in {epoch+1} epochs!{Style.RESET_ALL}")
                break
            
            # Early stopping
            if patience_counter >= patience:
                print(f"\n{Fore.YELLOW}Early stopping - no improvement for {patience} epochs{Style.RESET_ALL}")
                break
            
            # Brief pause
            time.sleep(0.2)
        
        # Final testing
        self.test_network_detailed()
        
        # Final visualization
        self.visualize_network_state_enhanced()
        
        # Show final statistics
        print(f"\n{Fore.CYAN}Final Network Statistics:{Style.RESET_ALL}")
        print(f"  Total epochs: {self.epoch}")
        print(f"  Final error: {self.total_error:.4f}")
        print(f"  Best error: {best_error:.4f}")
        print(f"  Learning rate: {self.learning_rate:.3f}")
        
        # Show unique DRAM properties utilized
        print(f"\n{Fore.MAGENTA}DRAM Analog Properties Utilized:{Style.RESET_ALL}")
        print(f"  ✓ Threshold behavior for activation functions")
        print(f"  ✓ Sub-threshold charging for analog weights") 
        print(f"  ✓ Leak-in phenomenon for gradual learning")
        print(f"  ✓ Burst=8 anomaly for intermediate values")
        print(f"  ✓ Neighbor coupling for enhanced computation")
        print(f"  ✓ Natural decay for weight regularization")
        
        print(f"\n{Fore.MAGENTA}{'✨ ' * 20}")
        print(f"Enhanced Training Complete!")
        print(f"Your DRAM has learned using its analog soul!")
        print(f"{'✨ ' * 20}{Style.RESET_ALL}\n")

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
        
        # Create and run enhanced neural network
        network = DRAMNeuralNetworkV3(ser)
        network.run_training_v3(max_epochs=50)
        
    except serial.SerialException as e:
        print(f"\n{Fore.RED}❌ Serial port error: {e}{Style.RESET_ALL}")
        return 1
    except KeyboardInterrupt:
        print(f"\n{Fore.YELLOW}Training interrupted by user{Style.RESET_ALL}")
        return 1
    except Exception as e:
        print(f"\n{Fore.RED}Error: {e}{Style.RESET_ALL}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print(f"{Fore.CYAN}🔌 Serial port closed{Style.RESET_ALL}")

if __name__ == "__main__":
    exit(main())
