#!/usr/bin/env python3
"""
DDR3 Decay Test Data Visualizer
Real-time plotting of DRAM cell decay characteristics
"""

import serial
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import numpy as np
from collections import defaultdict
import datetime
import csv
import os
import re
from threading import Thread, Lock
import queue

class DDR3DecayVisualizer:
    def __init__(self, port='COM3', baudrate=115200):
        self.port = port
        self.baudrate = baudrate
        self.serial_conn = None
        self.data_queue = queue.Queue()
        self.data_lock = Lock()
        self.decay_data = defaultdict(lambda: defaultdict(list))
        self.current_test_params = {}
        self.output_dir = f"ddr3_decay_data_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}"
        os.makedirs(self.output_dir, exist_ok=True)
        self.fig, self.axes = plt.subplots(2, 2, figsize=(15, 10))
        self.fig.suptitle('DDR3 Decay Characteristics Analysis', fontsize=16)
        self.ax_heatmap = self.axes[0, 0]
        self.ax_decay_curve = self.axes[0, 1]
        self.ax_error_dist = self.axes[1, 0]
        self.ax_statistics = self.axes[1, 1]
        self.csv_filename = os.path.join(self.output_dir, 'decay_data.csv')
        self.csv_file = None
        self.csv_writer = None
        # --- Heatmap initialization: empty data and colorbar ---
        self._heatmap_shape = (10, 10)
        self.im = self.ax_heatmap.imshow(np.zeros(self._heatmap_shape), aspect='auto', cmap='hot', interpolation='nearest')
        self.heatmap_cb = self.fig.colorbar(self.im, ax=self.ax_heatmap)
        self.setup_plots()

    def setup_plots(self):
        self.ax_heatmap.set_title('Bit Error Rate Heatmap')
        self.ax_heatmap.set_xlabel('Decay Time (ms)')
        self.ax_heatmap.set_ylabel('Memory Address')
        self.ax_decay_curve.set_title('Average Decay Curve')
        self.ax_decay_curve.set_xlabel('Decay Time (ms)')
        self.ax_decay_curve.set_ylabel('Bit Error Rate (%)')
        self.ax_decay_curve.set_xscale('log')
        self.ax_decay_curve.grid(True, alpha=0.3)
        self.ax_error_dist.set_title('Error Count Distribution')
        self.ax_error_dist.set_xlabel('Number of Bit Errors')
        self.ax_error_dist.set_ylabel('Frequency')
        self.ax_statistics.set_title('Test Statistics')
        self.ax_statistics.axis('off')
        plt.tight_layout()

    def connect_serial(self):
        try:
            self.serial_conn = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                timeout=0.1,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE
            )
            print(f"Connected to {self.port} at {self.baudrate} baud")
            return True
        except Exception as e:
            print(f"Failed to connect to serial port: {e}")
            return False

    def parse_uart_line(self, line):
        pattern = r'DT:([0-9A-F]+),ADDR:([0-9A-F]+),MEAS:([0-9A-F]),ERR:([0-9A-F]+),PASS:([01]),RD:([0-9A-F]+)'
        match = re.match(pattern, line.strip())
        if match:
            return {
                'timestamp': datetime.datetime.now(),
                'decay_time_cycles': int(match.group(1), 16),
                'decay_time_ms': int(match.group(1), 16) / 200000.0,
                'address': int(match.group(2), 16),
                'measurement': int(match.group(3), 16),
                'bit_errors': int(match.group(4), 16),
                'pass': match.group(5) == '1',
                'read_data': match.group(6)
            }
        return None

    def serial_reader_thread(self):
        if not self.serial_conn:
            return
        buffer = ""
        while True:
            try:
                if self.serial_conn.in_waiting:
                    data = self.serial_conn.read(self.serial_conn.in_waiting).decode('utf-8', errors='ignore')
                    buffer += data
                    while '\n' in buffer:
                        line, buffer = buffer.split('\n', 1)
                        parsed = self.parse_uart_line(line)
                        if parsed:
                            self.data_queue.put(parsed)
                            self.log_to_csv(parsed)
            except Exception as e:
                print(f"Serial read error: {e}")

    def log_to_csv(self, data):
        if self.csv_file is None:
            self.csv_file = open(self.csv_filename, 'w', newline='')
            self.csv_writer = csv.DictWriter(
                self.csv_file,
                fieldnames=[
                    'timestamp',
                    'decay_time_cycles',
                    'decay_time_ms',
                    'address',
                    'measurement',
                    'bit_errors',
                    'pass',
                    'read_data'
                ]
            )
            self.csv_writer.writeheader()
        filtered_data = {k: v for k, v in data.items() if k in self.csv_writer.fieldnames}
        self.csv_writer.writerow(filtered_data)
        self.csv_file.flush()

    def update_plots(self, frame):
        processed = 0
        while not self.data_queue.empty() and processed < 100:
            try:
                data = self.data_queue.get_nowait()
                with self.data_lock:
                    self.decay_data[data['address']][data['decay_time_ms']].append(data['bit_errors'])
                processed += 1
            except queue.Empty:
                break
        if processed == 0:
            return
        self.update_heatmap()
        self.update_decay_curve()
        self.update_error_distribution()
        self.update_statistics()

    """ def update_heatmap(self):
        with self.data_lock:
            if not self.decay_data:
                self.im.set_data(np.zeros(self._heatmap_shape))
                return
            addresses = sorted(self.decay_data.keys())
            decay_times = sorted(set(time for addr_data in self.decay_data.values()
                                    for time in addr_data.keys()))
            if not addresses or not decay_times:
                self.im.set_data(np.zeros(self._heatmap_shape))
                return
            heatmap_data = np.zeros((len(addresses), len(decay_times)))
            for i, addr in enumerate(addresses):
                for j, time in enumerate(decay_times):
                    if time in self.decay_data[addr]:
                        errors = self.decay_data[addr][time]
                        heatmap_data[i, j] = (sum(errors) / len(errors)) / 128.0 * 100
            # Update heatmap image and color scale
            self.im.set_data(heatmap_data)
            self.im.set_extent((0, heatmap_data.shape[1], 0, heatmap_data.shape[0]))
            self.im.set_clim(np.nanmin(heatmap_data), np.nanmax(heatmap_data) if np.nanmax(heatmap_data) > 0 else 1)
            self.heatmap_cb.update_normal(self.im)
            # Set labels
            self.ax_heatmap.set_xticks(np.arange(len(decay_times))[::max(1, len(decay_times)//10)])
            self.ax_heatmap.set_xticklabels(
                [f'{t:.1f}' for t in decay_times][::max(1, len(decay_times)//10)],
                rotation=45)
            self.ax_heatmap.set_yticks(np.arange(len(addresses))[::max(1, len(addresses)//20)])
            self.ax_heatmap.set_yticklabels(
                [f'0x{addr:04X}' for addr in addresses][::max(1, len(addresses)//20)])
            self.ax_heatmap.set_title('Bit Error Rate Heatmap (%)')
            self.ax_heatmap.set_xlabel('Decay Time (ms)')
            self.ax_heatmap.set_ylabel('Memory Address')
 """
    def update_heatmap(self):
        with self.data_lock:
            if not self.decay_data:
                self.im.set_data(np.zeros(self._heatmap_shape))
                # Fix: Also reset the extent so axes stay correct even if empty
                self.im.set_extent((0, 1, 0, 1))
                self.ax_heatmap.set_xticks([])
                self.ax_heatmap.set_yticks([])
                return

            addresses = sorted(self.decay_data.keys())
            decay_times = sorted(set(time for addr_data in self.decay_data.values()
                                    for time in addr_data.keys()))

            if not addresses or not decay_times:
                self.im.set_data(np.zeros(self._heatmap_shape))
                self.im.set_extent((0, 1, 0, 1))
                self.ax_heatmap.set_xticks([])
                self.ax_heatmap.set_yticks([])
                return

            heatmap_data = np.zeros((len(addresses), len(decay_times)))
            for i, addr in enumerate(addresses):
                for j, time in enumerate(decay_times):
                    if time in self.decay_data[addr]:
                        errors = self.decay_data[addr][time]
                        heatmap_data[i, j] = (sum(errors) / len(errors)) / 128.0 * 100

            # Fix: Use extent to map data to decay_times and addresses
            x0, x1 = decay_times[0], decay_times[-1]
            y0, y1 = addresses[0], addresses[-1]
            self.im.set_data(heatmap_data)
            self.im.set_extent((x0, x1, y0, y1))  # left, right, bottom, top

            # Fix: Custom ticks (optional: limit number of ticks for clarity)
            n_xticks = min(10, len(decay_times))
            xtick_indices = np.linspace(0, len(decay_times) - 1, n_xticks, dtype=int)
            xticks = [decay_times[i] for i in xtick_indices]
            self.ax_heatmap.set_xticks(xticks)
            self.ax_heatmap.set_xticklabels([f'{t:.1f}' for t in xticks], rotation=45)

            n_yticks = min(12, len(addresses))
            ytick_indices = np.linspace(0, len(addresses) - 1, n_yticks, dtype=int)
            yticks = [addresses[i] for i in ytick_indices]
            self.ax_heatmap.set_yticks(yticks)
            self.ax_heatmap.set_yticklabels([f'0x{addr:04X}' for addr in yticks])

            self.im.set_clim(np.nanmin(heatmap_data), np.nanmax(heatmap_data) if np.nanmax(heatmap_data) > 0 else 1)
            self.heatmap_cb.update_normal(self.im)
            self.ax_heatmap.set_title('Bit Error Rate Heatmap (%)')
            self.ax_heatmap.set_xlabel('Decay Time (ms)')
            self.ax_heatmap.set_ylabel('Memory Address')

    def update_decay_curve(self):
        self.ax_decay_curve.clear()
        with self.data_lock:
            if not self.decay_data:
                return
            decay_times = []
            avg_errors = []
            std_errors = []
            all_times = sorted(set(time for addr_data in self.decay_data.values()
                                   for time in addr_data.keys()))
            for time in all_times:
                all_errors = []
                for addr in self.decay_data:
                    if time in self.decay_data[addr]:
                        all_errors.extend(self.decay_data[addr][time])
                if all_errors:
                    decay_times.append(time)
                    error_percentages = [e / 128.0 * 100 for e in all_errors]
                    avg_errors.append(np.mean(error_percentages))
                    std_errors.append(np.std(error_percentages))
            if decay_times:
                self.ax_decay_curve.errorbar(decay_times, avg_errors, yerr=std_errors,
                                             fmt='o-', capsize=5, capthick=2)
                if len(decay_times) > 3:
                    try:
                        log_times = np.log(decay_times)
                        coeffs = np.polyfit(log_times, avg_errors, 2)
                        fit_times = np.logspace(np.log10(min(decay_times)),
                                                np.log10(max(decay_times)), 100)
                        fit_errors = np.polyval(coeffs, np.log(fit_times))
                        self.ax_decay_curve.plot(fit_times, fit_errors, 'r--',
                                                label='Polynomial fit', alpha=0.7)
                        self.ax_decay_curve.legend()
                    except Exception:
                        pass
        self.ax_decay_curve.set_title('Average Bit Error Rate vs Decay Time')
        self.ax_decay_curve.set_xlabel('Decay Time (ms)')
        self.ax_decay_curve.set_ylabel('Bit Error Rate (%)')
        self.ax_decay_curve.set_xscale('log')
        self.ax_decay_curve.grid(True, alpha=0.3)

    def update_error_distribution(self):
        self.ax_error_dist.clear()
        with self.data_lock:
            all_errors = []
            for addr_data in self.decay_data.values():
                for time_data in addr_data.values():
                    all_errors.extend(time_data)
            if all_errors:
                bins = np.arange(0, max(all_errors) + 2) - 0.5
                self.ax_error_dist.hist(all_errors, bins=bins, edgecolor='black')
        self.ax_error_dist.set_title('Bit Error Count Distribution')
        self.ax_error_dist.set_xlabel('Number of Bit Errors (out of 128)')
        self.ax_error_dist.set_ylabel('Frequency')
        self.ax_error_dist.grid(True, alpha=0.3, axis='y')

    def update_statistics(self):
        self.ax_statistics.clear()
        self.ax_statistics.axis('off')
        with self.data_lock:
            total_tests = sum(len(time_data) for addr_data in self.decay_data.values()
                              for time_data in addr_data.values())
            if total_tests == 0:
                return
            total_passes = 0
            total_errors = 0
            max_errors = 0
            addresses_tested = len(self.decay_data)
            decay_times_tested = set()
            error_addresses = set()
            for addr, addr_data in self.decay_data.items():
                for time, errors in addr_data.items():
                    decay_times_tested.add(time)
                    for e in errors:
                        if e == 0:
                            total_passes += 1
                        else:
                            error_addresses.add(addr)
                        total_errors += e
                        max_errors = max(max_errors, e)
            avg_error_rate = (total_errors / (total_tests * 128)) * 100
            pass_rate = (total_passes / total_tests) * 100
            stats_text = f"""Test Statistics:

Total Tests: {total_tests:,}
Addresses Tested: {addresses_tested}
Decay Times Tested: {len(decay_times_tested)}
Addresses with Errors: {len(error_addresses)}

Pass Rate: {pass_rate:.2f}%
Average Error Rate: {avg_error_rate:.4f}%
Maximum Bit Errors: {max_errors}/128
Total Bit Errors: {total_errors:,}

Test Started: {self.output_dir.split('_')[-2]} {self.output_dir.split('_')[-1]}
Current Time: {datetime.datetime.now().strftime('%H:%M:%S')}
"""
            self.ax_statistics.text(0.05, 0.95, stats_text, transform=self.ax_statistics.transAxes,
                                   fontsize=10, verticalalignment='top', fontfamily='monospace',
                                   bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

    def save_analysis(self):
        plot_filename = os.path.join(self.output_dir,
                                    f'decay_analysis_{datetime.datetime.now().strftime("%Y%m%d_%H%M%S")}.png')
        plt.savefig(plot_filename, dpi=300, bbox_inches='tight')
        print(f"Saved plot to {plot_filename}")
        summary_filename = os.path.join(self.output_dir, 'summary_statistics.txt')
        with open(summary_filename, 'w') as f:
            f.write("DDR3 Decay Test Summary\n")
            f.write("=" * 50 + "\n\n")
            with self.data_lock:
                total_tests = sum(len(time_data) for addr_data in self.decay_data.values()
                                  for time_data in addr_data.values())
                f.write(f"Total Tests Performed: {total_tests}\n")
                f.write(f"Unique Addresses Tested: {len(self.decay_data)}\n")
                all_times = sorted(set(time for addr_data in self.decay_data.values()
                                      for time in addr_data.keys()))
                f.write("\nError Rates by Decay Time:\n")
                f.write("-" * 30 + "\n")
                for time in all_times:
                    all_errors = []
                    for addr in self.decay_data:
                        if time in self.decay_data[addr]:
                            all_errors.extend(self.decay_data[addr][time])
                    if all_errors:
                        avg_error = np.mean(all_errors)
                        std_error = np.std(all_errors)
                        max_error = max(all_errors)
                        pass_count = sum(1 for e in all_errors if e == 0)
                        f.write(f"\nDecay Time: {time:.1f} ms\n")
                        f.write(f"  Tests: {len(all_errors)}\n")
                        f.write(f"  Pass Rate: {(pass_count/len(all_errors))*100:.2f}%\n")
                        f.write(f"  Avg Bit Errors: {avg_error:.2f} ± {std_error:.2f}\n")
                        f.write(f"  Max Bit Errors: {max_error}\n")
                        f.write(f"  Error Rate: {(avg_error/128)*100:.4f}%\n")
        print(f"Saved summary to {summary_filename}")

    def run(self):
        if not self.connect_serial():
            print("Failed to connect to serial port. Please check settings.")
            return
        reader_thread = Thread(target=self.serial_reader_thread, daemon=True)
        reader_thread.start()
        ani = animation.FuncAnimation(self.fig, self.update_plots, interval=1000,
                                      cache_frame_data=False)
        def on_key(event):
            if event.key == 's':
                self.save_analysis()
            elif event.key == 'q':
                plt.close('all')
        self.fig.canvas.mpl_connect('key_press_event', on_key)
        print("\nDDR3 Decay Test Visualizer Started")
        print("Press 's' to save current analysis")
        print("Press 'q' to quit")
        print("-" * 40)
        try:
            plt.show()
        except KeyboardInterrupt:
            pass
        finally:
            if self.csv_file:
                self.csv_file.close()
            if self.serial_conn:
                self.serial_conn.close()
            print("\nTest completed. Data saved to:", self.output_dir)

def main():
    import argparse
    parser = argparse.ArgumentParser(description='DDR3 Decay Test Data Visualizer')
    parser.add_argument('-p', '--port', default='COM3', help='Serial port (default: COM3)')
    parser.add_argument('-b', '--baud', type=int, default=115200, help='Baud rate (default: 115200)')
    args = parser.parse_args()
    visualizer = DDR3DecayVisualizer(port=args.port, baudrate=args.baud)
    visualizer.run()

if __name__ == '__main__':
    main()

