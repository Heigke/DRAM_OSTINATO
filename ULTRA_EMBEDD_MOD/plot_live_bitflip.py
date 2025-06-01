#!/usr/bin/env python3
"""
DDR3 Decay Test - Live Data Plotter
Reads data from UART and plots bit flip statistics vs decay time
"""

import serial
import struct
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from collections import defaultdict
import time
import sys

# Configuration
SERIAL_PORT = '/dev/ttyUSB1'  # Update this to match your system
BAUD_RATE = 115200
NUM_ADDRESSES = 16
SAMPLES_PER_DECAY = 4
DECAY_TIMES_MS = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 3000]

class DDR3DecayPlotter:
    def __init__(self, port, baudrate):
        # Serial connection
        try:
            self.ser = serial.Serial(port, baudrate, timeout=0.1)
            print(f"Connected to {port} at {baudrate} baud")
        except Exception as e:
            print(f"Error opening serial port: {e}")
            sys.exit(1)
        
        # Data storage
        self.data = defaultdict(lambda: defaultdict(list))
        self.start_time = time.time()
        
        # Statistics
        self.total_bits = 128  # 128 bits per burst
        
        # Setup plot
        self.fig, (self.ax1, self.ax2, self.ax3) = plt.subplots(3, 1, figsize=(12, 10))
        self.fig.suptitle('DDR3 Decay Analysis - Real-time Results')
        
        # Configure axes
        self.ax1.set_xlabel('Decay Time (ms)')
        self.ax1.set_ylabel('Average Flipped Bits (0→1)')
        self.ax1.set_xscale('log')
        self.ax1.grid(True, alpha=0.3)
        self.ax1.set_xlim(0.8, 4000)
        
        self.ax2.set_xlabel('Decay Time (ms)')
        self.ax2.set_ylabel('Bit Flip Rate (%)')
        self.ax2.set_xscale('log')
        self.ax2.grid(True, alpha=0.3)
        self.ax2.set_xlim(0.8, 4000)
        self.ax2.set_ylim(0, 100)
        
        self.ax3.set_xlabel('Time (s)')
        self.ax3.set_ylabel('Data Points Received')
        self.ax3.grid(True, alpha=0.3)
        
        # Initialize plot lines
        self.line1, = self.ax1.plot([], [], 'b-o', label='Average Bit Flips')
        self.line1_err = self.ax1.errorbar([], [], yerr=[], fmt='none', ecolor='blue', alpha=0.5)
        
        self.line2, = self.ax2.plot([], [], 'r-o', label='Flip Rate %')
        self.line2_err = self.ax2.errorbar([], [], yerr=[], fmt='none', ecolor='red', alpha=0.5)
        
        self.line3, = self.ax3.plot([], [], 'g-', label='Cumulative Data Points')
        
        # Add legends
        self.ax1.legend(loc='upper left')
        self.ax2.legend(loc='upper left')
        self.ax3.legend(loc='upper left')
        
        # Data point counter
        self.point_counter = []
        self.time_stamps = []
        
        plt.tight_layout()
        
    def read_data_packet(self):
        """Read and parse a data packet from UART"""
        # Look for start marker
        while True:
            byte = self.ser.read(1)
            if not byte:
                return None
            if byte[0] == 0xAA:
                break
        
        # Read rest of packet
        packet = self.ser.read(7)
        if len(packet) != 7:
            return None
        
        # Parse packet
        decay_idx = packet[0]
        sample_idx = packet[1]
        addr_idx = packet[2]
        ones_count = struct.unpack('>H', packet[3:5])[0]
        zeros_count = struct.unpack('>H', packet[5:7])[0]
        
        # Validate
        if decay_idx >= len(DECAY_TIMES_MS):
            return None
        if sample_idx >= SAMPLES_PER_DECAY:
            return None
        if addr_idx >= NUM_ADDRESSES:
            return None
        
        return {
            'decay_idx': decay_idx,
            'decay_ms': DECAY_TIMES_MS[decay_idx],
            'sample_idx': sample_idx,
            'addr_idx': addr_idx,
            'ones_count': ones_count,
            'zeros_count': zeros_count,
            'flipped_bits': self.total_bits - ones_count  # Bits that flipped from 1→0
        }
    
    def update_plot(self, frame):
        """Update plot with new data"""
        # Read available data
        packets_read = 0
        while self.ser.in_waiting > 0 and packets_read < 10:
            packet = self.read_data_packet()
            if packet:
                # Store data
                decay_ms = packet['decay_ms']
                self.data[decay_ms]['flipped_bits'].append(packet['flipped_bits'])
                self.data[decay_ms]['flip_rate'].append(100.0 * packet['flipped_bits'] / self.total_bits)
                
                # Update counter
                self.point_counter.append(len(self.point_counter) + 1)
                self.time_stamps.append(time.time() - self.start_time)
                
                packets_read += 1
                
                # Print to console
                print(f"Decay: {decay_ms:4d}ms, Sample: {packet['sample_idx']}, "
                      f"Addr: {packet['addr_idx']:2d}, Flipped: {packet['flipped_bits']:3d}/128 "
                      f"({100.0 * packet['flipped_bits'] / self.total_bits:.1f}%)")
        
        # Calculate statistics
        decay_times = []
        avg_flips = []
        std_flips = []
        avg_rates = []
        std_rates = []
        
        for decay_ms in sorted(self.data.keys()):
            if len(self.data[decay_ms]['flipped_bits']) > 0:
                decay_times.append(decay_ms)
                
                flips = np.array(self.data[decay_ms]['flipped_bits'])
                avg_flips.append(np.mean(flips))
                std_flips.append(np.std(flips))
                
                rates = np.array(self.data[decay_ms]['flip_rate'])
                avg_rates.append(np.mean(rates))
                std_rates.append(np.std(rates))
        
        # Update plots
        if len(decay_times) > 0:
            # Plot 1: Average bit flips
            self.line1.set_data(decay_times, avg_flips)
            
            # Update error bars for plot 1
            self.line1_err.remove()
            self.line1_err = self.ax1.errorbar(decay_times, avg_flips, yerr=std_flips,
                                               fmt='none', ecolor='blue', alpha=0.5)
            
            # Plot 2: Flip rate percentage
            self.line2.set_data(decay_times, avg_rates)
            
            # Update error bars for plot 2
            self.line2_err.remove()
            self.line2_err = self.ax2.errorbar(decay_times, avg_rates, yerr=std_rates,
                                               fmt='none', ecolor='red', alpha=0.5)
            
            # Auto-scale y-axis for plot 1
            if len(avg_flips) > 0:
                y_margin = 0.1 * (max(avg_flips) - min(avg_flips)) if max(avg_flips) > min(avg_flips) else 5
                self.ax1.set_ylim(max(0, min(avg_flips) - y_margin), 
                                  min(128, max(avg_flips) + y_margin))
        
        # Plot 3: Data points over time
        if len(self.time_stamps) > 0:
            self.line3.set_data(self.time_stamps, self.point_counter)
            self.ax3.set_xlim(0, max(self.time_stamps) * 1.1)
            self.ax3.set_ylim(0, len(self.point_counter) * 1.1)
        
        # Update layout
        self.fig.tight_layout()
        
        return self.line1, self.line2, self.line3
    
    def save_data(self, filename='ddr3_decay_data.csv'):
        """Save collected data to CSV file"""
        with open(filename, 'w') as f:
            f.write("decay_ms,sample_num,avg_flipped_bits,std_flipped_bits,avg_flip_rate_pct,std_flip_rate_pct,num_samples\n")
            
            for decay_ms in sorted(self.data.keys()):
                if len(self.data[decay_ms]['flipped_bits']) > 0:
                    flips = np.array(self.data[decay_ms]['flipped_bits'])
                    rates = np.array(self.data[decay_ms]['flip_rate'])
                    
                    f.write(f"{decay_ms},{len(flips)},{np.mean(flips):.2f},"
                           f"{np.std(flips):.2f},{np.mean(rates):.2f},"
                           f"{np.std(rates):.2f},{len(flips)}\n")
        
        print(f"\nData saved to {filename}")
    
    def run(self):
        """Start the animation"""
        # Clear serial buffer
        self.ser.reset_input_buffer()
        
        print("Starting live plot... Press Ctrl+C to stop")
        print("Make sure to press the start button on your FPGA board!\n")
        
        try:
            ani = FuncAnimation(self.fig, self.update_plot, interval=100, blit=False)
            plt.show()
        except KeyboardInterrupt:
            print("\nStopping...")
        finally:
            self.save_data()
            self.ser.close()

def main():
    if len(sys.argv) > 1:
        port = sys.argv[1]
    else:
        port = SERIAL_PORT
    
    print("DDR3 Decay Test - Live Plotter")
    print(f"Using serial port: {port}")
    print("=" * 50)
    
    plotter = DDR3DecayPlotter(port, BAUD_RATE)
    plotter.run()

if __name__ == "__main__":
    main()
