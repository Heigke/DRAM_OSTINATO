#!/usr/bin/env python3

import serial
import time
import random
from colorama import Fore, Style, init

# Initialize colorama for colored terminal output
init(autoreset=True)

# --- Configuration ---
SERIAL_PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.2  # Serial read timeout in seconds

# Test addresses - spread across different rows/banks for better decay measurement
ADDRESSES = [0x00000000, 0x00000004, 0x00000008, 0x00000100, 0x000003FC]

# Pattern for decay testing
PATTERN = "FFFFFFFF"   # All 1s is good for decay testing (1->0 transitions)

# Number of writes to ensure data is really written (overcomes lag)
NWRITES = 10  # Increased from 5 to ensure we overcome any lag

# Number of confirmation reads after writing
NCONFIRM = 5  # Increased to ensure we get stable readback

# Decay delay times in seconds
DECAY_DELAYS = [0, 1, 5, 10, 30, 60, 120, 300, 600]  # Added 0 for baseline

# Debug output control
DEBUG = True

def debug(msg):
    if DEBUG:
        print(Fore.YELLOW + "[DEBUG] " + str(msg) + Style.RESET_ALL)

def info(msg):
    print(Fore.CYAN + "[INFO] " + str(msg) + Style.RESET_ALL)

def error(msg):
    print(Fore.RED + "[ERROR] " + str(msg) + Style.RESET_ALL)

def success(msg):
    print(Fore.GREEN + "[SUCCESS] " + str(msg) + Style.RESET_ALL)

def write_cmd(ser, addr, data):
    """Send write command to DDR3 controller"""
    cmd = f"W{addr:08X} {data}\r"
    debug(f"Write: 0x{addr:08X} = {data}")
    ser.write(cmd.encode('ascii'))
    time.sleep(0.01)

def read_cmd(ser, addr):
    """Send read command and get response"""
    cmd = f"R{addr:08X}\r"
    ser.write(cmd.encode('ascii'))
    ser.flush()
    time.sleep(0.01)
    
    # Read response with timeout
    response = ""
    start_time = time.time()
    
    while time.time() - start_time < TIMEOUT:
        if ser.in_waiting:
            try:
                line = ser.readline().decode("ascii", errors="ignore").strip()
                if line:
                    response = line
                    break
            except Exception as e:
                debug(f"Read exception: {e}")
    
    return response

def extract_data(response):
    """Extract the 8-character hex data from response"""
    if not response or len(response) < 8:
        return None
    # Take last 8 characters which should be the data
    return response[-8:].upper()

def hamming_distance(hex1, hex2):
    """Calculate Hamming distance between two hex strings"""
    try:
        if not hex1 or not hex2:
            return 32
        v1 = int(hex1, 16)
        v2 = int(hex2, 16)
        xor = v1 ^ v2
        return bin(xor).count('1')
    except ValueError:
        return 32

def count_bit_flips(original, readback):
    """Count and analyze bit flips"""
    if not original or not readback:
        return None, None, None
    
    try:
        orig_val = int(original, 16)
        read_val = int(readback, 16)
        
        # Count 1->0 flips (decay)
        flips_1_to_0 = bin(orig_val & ~read_val).count('1')
        
        # Count 0->1 flips (unexpected)
        flips_0_to_1 = bin(~orig_val & read_val).count('1')
        
        total_flips = flips_1_to_0 + flips_0_to_1
        
        return total_flips, flips_1_to_0, flips_0_to_1
    except ValueError:
        return None, None, None

def write_pattern_with_flush(ser, addr, pattern, nwrites):
    """Write pattern multiple times to ensure it's really written"""
    info(f"Writing {pattern} to 0x{addr:08X} ({nwrites} times)")
    for i in range(nwrites):
        write_cmd(ser, addr, pattern)
        time.sleep(0.005)  # Small delay between writes

def verify_write(ser, addr, expected, nreads):
    """Verify that the write was successful by reading multiple times"""
    successes = 0
    last_read = None
    
    for i in range(nreads):
        response = read_cmd(ser, addr)
        data = extract_data(response)
        
        if data:
            last_read = data
            if data == expected.upper():
                successes += 1
                debug(f"Verify read {i+1}/{nreads}: {data} [OK]")
            else:
                debug(f"Verify read {i+1}/{nreads}: {data} [Expected: {expected}]")
        else:
            debug(f"Verify read {i+1}/{nreads}: NO DATA")
    
    # Consider write verified if at least the last few reads are correct
    # (accounts for initial lag reads)
    return successes >= min(3, nreads//2), last_read

# --- Main Program ---
def main():
    # Open serial port
    try:
        info(f"Opening serial port {SERIAL_PORT} at {BAUDRATE} baud")
        ser = serial.Serial(SERIAL_PORT, BAUDRATE, timeout=TIMEOUT)
        time.sleep(0.1)  # Let serial settle
        
        # Clear any pending data
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        
    except serial.SerialException as e:
        error(f"Failed to open serial port: {e}")
        return 1
    
    print("\n" + "="*60)
    print("DDR3 DECAY MEASUREMENT TOOL")
    print("="*60)
    print(f"Port: {SERIAL_PORT} @ {BAUDRATE} baud")
    print(f"Test addresses: {[f'0x{a:08X}' for a in ADDRESSES]}")
    print(f"Write pattern: {PATTERN}")
    print(f"Decay delays: {DECAY_DELAYS} seconds")
    print("="*60 + "\n")
    
    # Results storage
    all_results = []
    
    # Test each decay delay
    for delay_idx, delay_sec in enumerate(DECAY_DELAYS):
        print(f"\n{Fore.BLUE}{'='*50}")
        print(f"TEST {delay_idx+1}/{len(DECAY_DELAYS)}: Decay delay = {delay_sec} seconds")
        print(f"{'='*50}{Style.RESET_ALL}\n")
        
        decay_results = {
            'delay': delay_sec,
            'addresses': {}
        }
        
        # Phase 1: Write pattern to all addresses
        info("Phase 1: Writing pattern to all addresses")
        for addr in ADDRESSES:
            write_pattern_with_flush(ser, addr, PATTERN, NWRITES)
        
        # Phase 2: Verify writes
        info("\nPhase 2: Verifying writes")
        all_verified = True
        
        for addr in ADDRESSES:
            verified, last_read = verify_write(ser, addr, PATTERN, NCONFIRM)
            
            if verified:
                success(f"0x{addr:08X}: Write verified")
            else:
                error(f"0x{addr:08X}: Write verification failed (last read: {last_read})")
                all_verified = False
        
        if not all_verified:
            error(f"Skipping decay test for {delay_sec}s due to write failures")
            continue
        
        # Phase 3: Wait for decay
        if delay_sec > 0:
            info(f"\nPhase 3: Waiting {delay_sec} seconds for decay...")
            
            # Show progress for long delays
            if delay_sec >= 30:
                chunk = max(1, delay_sec // 10)
                for i in range(0, delay_sec, chunk):
                    remaining = delay_sec - i
                    print(f"\r{Fore.YELLOW}Waiting... {remaining} seconds remaining{Style.RESET_ALL}", end='', flush=True)
                    time.sleep(min(chunk, remaining))
                print("\r" + " "*50 + "\r", end='')  # Clear the line
            else:
                time.sleep(delay_sec)
            
            info("Wait complete")
        else:
            info("\nPhase 3: No delay (baseline test)")
        
        # Phase 4: Read back and analyze decay
        info("\nPhase 4: Reading back and analyzing decay")
        print(f"\n{Fore.WHITE}Address      Expected    Readback    Hamming  1→0  0→1  Status{Style.RESET_ALL}")
        print("-" * 70)
        
        for addr in ADDRESSES:
            # Read multiple times and take the most common result
            reads = []
            for _ in range(3):
                response = read_cmd(ser, addr)
                data = extract_data(response)
                if data:
                    reads.append(data)
            
            if reads:
                # Use the most common readback
                readback = max(set(reads), key=reads.count)
            else:
                readback = "NO_DATA"
            
            # Analyze the decay
            if readback and readback != "NO_DATA":
                hamming = hamming_distance(PATTERN, readback)
                total, decay, corrupt = count_bit_flips(PATTERN, readback)
                
                # Determine status
                if readback == PATTERN:
                    status = f"{Fore.GREEN}OK{Style.RESET_ALL}"
                elif decay and not corrupt:
                    status = f"{Fore.YELLOW}DECAY{Style.RESET_ALL}"
                elif corrupt:
                    status = f"{Fore.RED}CORRUPT{Style.RESET_ALL}"
                else:
                    status = f"{Fore.MAGENTA}FLIP{Style.RESET_ALL}"
                
                print(f"0x{addr:08X}  {PATTERN}  {readback}  {hamming:>7}  {decay if decay else '':>3}  {corrupt if corrupt else '':>3}  {status}")
                
                decay_results['addresses'][addr] = {
                    'readback': readback,
                    'hamming': hamming,
                    'flips_1_to_0': decay,
                    'flips_0_to_1': corrupt
                }
            else:
                print(f"0x{addr:08X}  {PATTERN}  {'NO_DATA':<8}  {'--':>7}  {'--':>3}  {'--':>3}  {Fore.RED}FAIL{Style.RESET_ALL}")
                decay_results['addresses'][addr] = {
                    'readback': None,
                    'hamming': None,
                    'flips_1_to_0': None,
                    'flips_0_to_1': None
                }
        
        all_results.append(decay_results)
    
    # Final summary
    print(f"\n\n{Fore.CYAN}{'='*60}")
    print("DECAY TEST SUMMARY")
    print(f"{'='*60}{Style.RESET_ALL}\n")
    
    # Create summary table
    print(f"{'Delay(s)':>10} | ", end='')
    for addr in ADDRESSES:
        print(f"0x{addr:08X} ", end='')
    print("\n" + "-"*70)
    
    for result in all_results:
        print(f"{result['delay']:>10} | ", end='')
        for addr in ADDRESSES:
            if addr in result['addresses']:
                data = result['addresses'][addr]
                if data['hamming'] is not None:
                    if data['hamming'] == 0:
                        print(f"{'OK':^11} ", end='')
                    else:
                        print(f"{data['hamming']:^11} ", end='')
                else:
                    print(f"{'FAIL':^11} ", end='')
            else:
                print(f"{'SKIP':^11} ", end='')
        print()
    
    # Save results to file
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    filename = f"decay_results_{timestamp}.csv"
    
    info(f"\nSaving results to {filename}")
    with open(filename, 'w') as f:
        f.write("Delay_sec,Address,Readback,Hamming,Flips_1to0,Flips_0to1\n")
        for result in all_results:
            for addr, data in result['addresses'].items():
                f.write(f"{result['delay']},0x{addr:08X},{data['readback'] or 'NO_DATA'},"
                       f"{data['hamming'] if data['hamming'] is not None else ''},"
                       f"{data['flips_1_to_0'] if data['flips_1_to_0'] is not None else ''},"
                       f"{data['flips_0_to_1'] if data['flips_0_to_1'] is not None else ''}\n")
    
    ser.close()
    success("Decay test complete!")
    return 0

if __name__ == "__main__":
    exit(main())
