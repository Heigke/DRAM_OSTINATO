#!/usr/bin/env python3

import serial
import time
import numpy as np
from datetime import datetime
from colorama import Fore, Back, Style, init
import random
import sys

# Initialize colorama
init(autoreset=True)

# Configuration
SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.3

# Neural Network Architecture based on characterization results
NEURONS_PER_LAYER = 4
INPUT_NEURONS = 4
HIDDEN_NEURONS = 4
OUTPUT_NEURONS = 2

# Key addresses from characterization (threshold neurons and binary synapses)
# We need more addresses for all the connections
THRESHOLD_NEURONS = [
    0x00001000, 0x00002000, 0x00003000, 0x00050000,
    0x00066000, 0x00067000, 0x00068000, 0x00069000,
    0x00070000, 0x00071000  # Extra neurons
]

# We need INPUT_NEURONS * HIDDEN_NEURONS + HIDDEN_NEURONS * OUTPUT_NEURONS addresses
# That's 4*4 + 4*2 = 16 + 8 = 24 addresses for weights
WEIGHT_ADDRESSES = [
    # Input-Hidden weights (16 addresses)
    0x00800000, 0x00801000, 0x00802000, 0x00803000,
    0x00804000, 0x00805000, 0x00806000, 0x00807000,
    0x00808000, 0x00809000, 0x0080A000, 0x0080B000,
    0x0080C000, 0x0080D000, 0x0080E000, 0x0080F000,
    # Hidden-Output weights (8 addresses)
    0x00810000, 0x00811000, 0x00812000, 0x00813000,
    0x00814000, 0x00815000, 0x00816000, 0x00817000
]

# Burst configurations from characterization
BURST_THRESHOLD = 3  # Sharp threshold at burst=3
BURST_SUBTHRESHOLD = 2  # Sub-threshold for partial activation
BURST_FULL = 8  # Full charge (but anomalous ~31%)
BURST_CLEAR = 8  # For clearing cells

# ASCII Art Banner
BANNER = """
╔════════════════════════════════════════════════════════════════════════════════╗
║                                                                                ║
║  ███╗   ██╗███████╗██╗   ██╗██████╗  ██████╗ ██████╗ ██████╗  █████╗ ███╗   ███╗  ║
║  ████╗  ██║██╔════╝██║   ██║██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔══██╗████╗ ████║  ║
║  ██╔██╗ ██║█████╗  ██║   ██║██████╔╝██║   ██║██║  ██║██████╔╝███████║██╔████╔██║  ║
║  ██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗██║   ██║██║  ██║██╔══██╗██╔══██║██║╚██╔╝██║  ║
║  ██║ ╚████║███████╗╚██████╔╝██║  ██║╚██████╔╝██████╔╝██║  ██║██║  ██║██║ ╚═╝ ██║  ║
║  ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ║
║                                                                                ║
║              Neuromorphic DRAM Learning Network v1.0                           ║
║           "Teaching Silicon to Think with Analog Memory"                       ║
╚════════════════════════════════════════════════════════════════════════════════╝
"""

class DRAMNeuralNetwork:
    def __init__(self, serial_port):
        self.ser = serial_port
        self.initialize_ddr3()
        
        # Network structure
        self.input_addrs = THRESHOLD_NEURONS[:INPUT_NEURONS]
        self.hidden_addrs = THRESHOLD_NEURONS[INPUT_NEURONS:INPUT_NEURONS+HIDDEN_NEURONS]
        self.output_addrs = THRESHOLD_NEURONS[INPUT_NEURONS+HIDDEN_NEURONS:INPUT_NEURONS+HIDDEN_NEURONS+OUTPUT_NEURONS]
        
        # Synaptic weights - properly indexed
        self.weight_addrs = {
            'input_hidden': WEIGHT_ADDRESSES[:INPUT_NEURONS * HIDDEN_NEURONS],
            'hidden_output': WEIGHT_ADDRESSES[INPUT_NEURONS * HIDDEN_NEURONS:INPUT_NEURONS * HIDDEN_NEURONS + HIDDEN_NEURONS * OUTPUT_NEURONS]
        }
        
        print(f"\n{Fore.CYAN}Weight allocation:{Style.RESET_ALL}")
        print(f"  Input→Hidden weights: {len(self.weight_addrs['input_hidden'])} addresses")
        print(f"  Hidden→Output weights: {len(self.weight_addrs['hidden_output'])} addresses")
        
        # Training patterns (XOR-like problem)
        self.training_patterns = [
            ([0, 0, 0, 0], [0, 0]),  # Pattern 1
            ([1, 0, 1, 0], [1, 0]),  # Pattern 2
            ([0, 1, 0, 1], [1, 0]),  # Pattern 3
            ([1, 1, 1, 1], [0, 1]),  # Pattern 4
        ]
        
        self.epoch = 0
        self.total_error = 0
        self.learning_rate = 0.5
        
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
        # Disable refresh to allow natural decay
        self.configure_timing(skip_refresh=1)
        
    def configure_timing(self, twr=0, tras=0, burst_len=0, skip_refresh=0):
        """Configure DDR3 timing parameters"""
        config_value = (skip_refresh << 20) | (burst_len << 16) | (tras << 8) | twr
        cmd = f"T{config_value:08X}\r"
        self.ser.write(cmd.encode('ascii'))
        time.sleep(0.1)
        self.ser.reset_input_buffer()
    
    def write_neuron(self, addr, burst_length, pattern="FFFFFFFF", iterations=20):
        """Write to a neuron with specific burst length (activation)"""
        # Configure burst
        self.configure_timing(burst_len=burst_length, skip_refresh=1)
        
        # Write pattern
        for _ in range(iterations):
            cmd = f"W{addr:08X} {pattern}\r"
            self.ser.write(cmd.encode('ascii'))
            time.sleep(0.005)
    
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
        self.configure_timing(burst_len=BURST_CLEAR, skip_refresh=1)
        for _ in range(20):
            cmd = f"W{addr:08X} 00000000\r"
            self.ser.write(cmd.encode('ascii'))
            time.sleep(0.005)
    
    def activate_neuron(self, addr, strength):
        """Activate neuron based on input strength"""
        if strength < 0.3:
            # Sub-threshold - use burst 2
            self.write_neuron(addr, BURST_SUBTHRESHOLD)
        elif strength < 0.7:
            # Near threshold - use burst 3 with fewer iterations
            self.write_neuron(addr, BURST_THRESHOLD, iterations=10)
        else:
            # Full activation - use burst 3
            self.write_neuron(addr, BURST_THRESHOLD)
    
    def get_weight_address(self, source_idx, dest_idx, layer):
        """Get the weight address for a connection"""
        if layer == 'input_hidden':
            # Map from input neuron i to hidden neuron h
            idx = source_idx * HIDDEN_NEURONS + dest_idx
            if idx < len(self.weight_addrs['input_hidden']):
                return self.weight_addrs['input_hidden'][idx]
        elif layer == 'hidden_output':
            # Map from hidden neuron h to output neuron o
            idx = source_idx * OUTPUT_NEURONS + dest_idx
            if idx < len(self.weight_addrs['hidden_output']):
                return self.weight_addrs['hidden_output'][idx]
        return None
    
    def update_weight(self, addr, delta):
        """Update synaptic weight (binary for now)"""
        if addr is None:
            return
            
        if delta > 0:
            # Strengthen connection
            self.write_neuron(addr, BURST_THRESHOLD)
        else:
            # Weaken connection
            self.clear_neuron(addr)
    
    def forward_pass(self, input_pattern):
        """Perform forward propagation through the network"""
        print(f"\n{Fore.CYAN}→ Forward Pass{Style.RESET_ALL}")
        
        # Clear all neurons first
        print("  Clearing neurons...", end='', flush=True)
        for addr in self.input_addrs + self.hidden_addrs + self.output_addrs:
            self.clear_neuron(addr)
        print(f" {Fore.GREEN}✓{Style.RESET_ALL}")
        
        # Set input neurons
        print("  Setting inputs: ", end='')
        for i, (addr, value) in enumerate(zip(self.input_addrs, input_pattern)):
            if value > 0:
                self.activate_neuron(addr, 1.0)
            activation = self.read_neuron(addr)
            print(f"{Fore.YELLOW}N{i}:{activation:.1f}{Style.RESET_ALL} ", end='')
        print()
        
        # Hidden layer computation
        print("  Computing hidden layer:")
        hidden_activations = []
        
        for h_idx, h_addr in enumerate(self.hidden_addrs):
            # Sum weighted inputs
            total_input = 0
            
            for i_idx, i_addr in enumerate(self.input_addrs):
                # Read input activation
                input_act = self.read_neuron(i_addr)
                
                # Get weight address
                weight_addr = self.get_weight_address(i_idx, h_idx, 'input_hidden')
                if weight_addr:
                    weight = self.read_neuron(weight_addr)
                else:
                    weight = 0.5  # Default weight if address not found
                
                total_input += input_act * weight
            
            # Apply activation based on total input
            if total_input > 0.5:
                self.activate_neuron(h_addr, total_input)
            
            activation = self.read_neuron(h_addr)
            hidden_activations.append(activation)
            
            print(f"    H{h_idx}: input={total_input:.2f} → activation={activation:.2f}")
        
        # Output layer computation
        print("  Computing output layer:")
        output_activations = []
        
        for o_idx, o_addr in enumerate(self.output_addrs):
            # Sum weighted inputs from hidden layer
            total_input = 0
            
            for h_idx, h_act in enumerate(hidden_activations):
                # Get weight address
                weight_addr = self.get_weight_address(h_idx, o_idx, 'hidden_output')
                if weight_addr:
                    weight = self.read_neuron(weight_addr)
                else:
                    weight = 0.5  # Default weight
                
                total_input += h_act * weight
            
            # Apply activation
            if total_input > 0.3:
                self.activate_neuron(o_addr, total_input)
            
            activation = self.read_neuron(o_addr)
            output_activations.append(activation)
            
            print(f"    O{o_idx}: input={total_input:.2f} → activation={activation:.2f}")
        
        return output_activations
    
    def train_epoch(self):
        """Train one epoch on all patterns"""
        self.epoch += 1
        print(f"\n{Fore.MAGENTA}{'='*80}")
        print(f"EPOCH {self.epoch}")
        print(f"{'='*80}{Style.RESET_ALL}")
        
        epoch_error = 0
        
        for pattern_idx, (input_pattern, target_output) in enumerate(self.training_patterns):
            print(f"\n{Fore.YELLOW}Pattern {pattern_idx + 1}: {input_pattern} → {target_output}{Style.RESET_ALL}")
            
            # Forward pass
            output = self.forward_pass(input_pattern)
            
            # Calculate error
            error = sum(abs(t - o) for t, o in zip(target_output, output))
            epoch_error += error
            
            print(f"\n  Target: {target_output}")
            print(f"  Output: [{output[0]:.2f}, {output[1]:.2f}]")
            print(f"  Error: {error:.3f}")
            
            # Simple weight update (Hebbian-like)
            if error > 0.1:
                print(f"\n  {Fore.CYAN}Updating weights...{Style.RESET_ALL}")
                
                # Update weights based on error
                for o_idx, (target, actual) in enumerate(zip(target_output, output)):
                    if abs(target - actual) > 0.1:
                        # Update hidden-output weights
                        for h_idx in range(HIDDEN_NEURONS):
                            weight_addr = self.get_weight_address(h_idx, o_idx, 'hidden_output')
                            
                            if weight_addr:
                                if target > actual:
                                    # Strengthen connection
                                    self.update_weight(weight_addr, 1)
                                    print(f"    ↑ H{h_idx}→O{o_idx} strengthened")
                                else:
                                    # Weaken connection
                                    self.update_weight(weight_addr, -1)
                                    print(f"    ↓ H{h_idx}→O{o_idx} weakened")
                        
                        # Also update input-hidden weights based on input pattern
                        for i_idx, input_val in enumerate(input_pattern):
                            if input_val > 0:  # Only update active inputs
                                for h_idx in range(HIDDEN_NEURONS):
                                    weight_addr = self.get_weight_address(i_idx, h_idx, 'input_hidden')
                                    if weight_addr and random.random() < self.learning_rate:
                                        if target > actual:
                                            self.update_weight(weight_addr, 1)
                                        else:
                                            self.update_weight(weight_addr, -1)
            
            # Visual separator
            time.sleep(0.5)
        
        self.total_error = epoch_error / len(self.training_patterns)
        
        # Display epoch summary
        return self.display_epoch_summary()
    
    def display_epoch_summary(self):
        """Display training progress"""
        print(f"\n{Fore.CYAN}{'─'*60}")
        print(f"Epoch {self.epoch} Summary")
        print(f"{'─'*60}{Style.RESET_ALL}")
        
        print(f"Average Error: {self.total_error:.3f}")
        
        # Progress bar
        progress = max(0, min(1, 1 - self.total_error))
        bar_width = 40
        filled = int(bar_width * progress)
        
        color = Fore.GREEN if progress > 0.8 else Fore.YELLOW if progress > 0.5 else Fore.RED
        bar = f"{color}{'█' * filled}{Fore.WHITE}{'░' * (bar_width - filled)}"
        
        print(f"Learning Progress: [{bar}] {progress*100:.1f}%")
        
        if self.total_error < 0.1:
            print(f"\n{Fore.GREEN}✨ Network has converged! ✨{Style.RESET_ALL}")
            return True
        
        return False
    
    def test_network(self):
        """Test the trained network"""
        print(f"\n{Fore.MAGENTA}{'='*80}")
        print(f"TESTING TRAINED NETWORK")
        print(f"{'='*80}{Style.RESET_ALL}")
        
        correct = 0
        
        for input_pattern, target_output in self.training_patterns:
            output = self.forward_pass(input_pattern)
            
            # Threshold outputs
            predicted = [1 if o > 0.5 else 0 for o in output]
            
            print(f"\nInput: {input_pattern}")
            print(f"Target: {target_output}")
            print(f"Output: {predicted} (raw: [{output[0]:.2f}, {output[1]:.2f}])")
            
            if predicted == list(target_output):
                print(f"{Fore.GREEN}✓ Correct!{Style.RESET_ALL}")
                correct += 1
            else:
                print(f"{Fore.RED}✗ Incorrect{Style.RESET_ALL}")
        
        accuracy = correct / len(self.training_patterns) * 100
        print(f"\n{Fore.CYAN}Accuracy: {accuracy:.1f}% ({correct}/{len(self.training_patterns)}){Style.RESET_ALL}")
    
    def initialize_weights(self):
        """Initialize synaptic weights randomly"""
        print(f"\n{Fore.CYAN}Initializing synaptic weights...{Style.RESET_ALL}")
        
        # Initialize input-hidden weights
        for i in range(len(self.weight_addrs['input_hidden'])):
            if random.random() > 0.5:
                self.write_neuron(self.weight_addrs['input_hidden'][i], BURST_THRESHOLD)
            else:
                self.clear_neuron(self.weight_addrs['input_hidden'][i])
        
        # Initialize hidden-output weights
        for i in range(len(self.weight_addrs['hidden_output'])):
            if random.random() > 0.5:
                self.write_neuron(self.weight_addrs['hidden_output'][i], BURST_THRESHOLD)
            else:
                self.clear_neuron(self.weight_addrs['hidden_output'][i])
        
        print(f"{Fore.GREEN}✓ Weights initialized{Style.RESET_ALL}")
    
    def visualize_network_state(self):
        """ASCII visualization of network state"""
        print(f"\n{Fore.CYAN}Network State Visualization:{Style.RESET_ALL}")
        
        # Read all neuron states
        input_states = [self.read_neuron(addr) for addr in self.input_addrs]
        hidden_states = [self.read_neuron(addr) for addr in self.hidden_addrs]
        output_states = [self.read_neuron(addr) for addr in self.output_addrs]
        
        print("\n     INPUT           HIDDEN          OUTPUT")
        print("   ┌─────────┐    ┌─────────┐    ┌─────────┐")
        
        max_neurons = max(len(input_states), len(hidden_states), len(output_states))
        
        for i in range(max_neurons):
            # Input neuron
            if i < len(input_states):
                state = input_states[i]
                if state > 0.8:
                    neuron = f"{Fore.GREEN}◉{Style.RESET_ALL}"
                elif state > 0.3:
                    neuron = f"{Fore.YELLOW}◐{Style.RESET_ALL}"
                else:
                    neuron = f"{Fore.RED}○{Style.RESET_ALL}"
                print(f"   │    {neuron}    │", end='')
            else:
                print(f"   │         │", end='')
            
            # Connections
            print("  ══╪══", end='')
            
            # Hidden neuron
            if i < len(hidden_states):
                state = hidden_states[i]
                if state > 0.8:
                    neuron = f"{Fore.GREEN}◉{Style.RESET_ALL}"
                elif state > 0.3:
                    neuron = f"{Fore.YELLOW}◐{Style.RESET_ALL}"
                else:
                    neuron = f"{Fore.RED}○{Style.RESET_ALL}"
                print(f"  │    {neuron}    │", end='')
            else:
                print(f"  │         │", end='')
            
            # Connections
            print("  ══╪══", end='')
            
            # Output neuron
            if i < len(output_states):
                state = output_states[i]
                if state > 0.8:
                    neuron = f"{Fore.GREEN}◉{Style.RESET_ALL}"
                elif state > 0.3:
                    neuron = f"{Fore.YELLOW}◐{Style.RESET_ALL}"
                else:
                    neuron = f"{Fore.RED}○{Style.RESET_ALL}"
                print(f"  │    {neuron}    │")
            else:
                print(f"  │         │")
        
        print("   └─────────┘    └─────────┘    └─────────┘")
        
        # Legend
        print(f"\n   {Fore.GREEN}◉{Style.RESET_ALL} Active (>80%)  "
              f"{Fore.YELLOW}◐{Style.RESET_ALL} Partial (30-80%)  "
              f"{Fore.RED}○{Style.RESET_ALL} Inactive (<30%)")
    
    def run_training(self, max_epochs=20):
        """Run the complete training process"""
        print(f"{Fore.CYAN}{BANNER}{Style.RESET_ALL}")
        
        print(f"\n{Fore.GREEN}🧠 Initializing Neuromorphic DRAM Network...{Style.RESET_ALL}")
        print(f"   • Input neurons: {INPUT_NEURONS}")
        print(f"   • Hidden neurons: {HIDDEN_NEURONS}")
        print(f"   • Output neurons: {OUTPUT_NEURONS}")
        print(f"   • Using threshold behavior at burst={BURST_THRESHOLD}")
        print(f"   • Training patterns: {len(self.training_patterns)}")
        
        # Initialize weights
        self.initialize_weights()
        
        # Visualize initial state
        self.visualize_network_state()
        
        # Training loop
        print(f"\n{Fore.GREEN}🎯 Starting training...{Style.RESET_ALL}")
        
        for epoch in range(max_epochs):
            converged = self.train_epoch()
            
            # Visualize network state every few epochs
            if epoch % 5 == 4:
                self.visualize_network_state()
            
            if converged:
                break
            
            # Brief pause between epochs
            time.sleep(0.5)
        
        # Test the network
        self.test_network()
        
        # Final visualization
        self.visualize_network_state()
        
        print(f"\n{Fore.MAGENTA}{'✨ ' * 20}")
        print(f"Training Complete! Your DRAM has learned!")
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
        
        # Create and run neural network
        network = DRAMNeuralNetwork(ser)
        network.run_training(max_epochs=20)
        
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
