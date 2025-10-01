Standard UART with Integrated Trivium Security
+ Overview

This project is a graduation thesis in VLSI System Design, focusing on the integration of a 16550-compliant UART with a hardware Trivium stream cipher for secure serial communication. The design emphasizes performance optimization and intelligent initialization control, ensuring both standard UART functionality and enhanced data confidentiality.

+ Tools & Technologies

Languages: Verilog, SystemVerilog

Simulation: ModelSim / QuestaSim

Design Domain: UART, Stream Cipher (Trivium), VLSI system integration

+ Key Components
1. Trivium Security Engine

Hardware-efficient implementation of the Trivium cipher (288-bit NLFSR).

Supports 32-bit parallel interface for Key/IV loading and 8-bit interface for byte-oriented data.

Integrated handshaking mechanism ensures synchronization between cipher and UART.

2. 16550-Compliant UART Core

Fully compliant with the 16550 UART specification.

Includes:

Configurable baud rate generator

TX/RX FIFOs (buffering for reliable data flow)

Parallel-to-serial and serial-to-parallel conversion logic

3. Top-Level Integration

A Master FSM coordinates all operations.

Latency optimization: Trivium’s 1152-cycle warm-up runs in parallel with UART register setup, minimizing startup delay.

Placement strategy: Trivium engine positioned before the TX FIFO → ensures ciphertext-only storage in on-chip memory, enhancing system security and enabling pipelined throughput.

+ Simulation & Verification

Simulated in ModelSim/QuestaSim.

Verified both encryption/transmission and reception/decryption paths.

Waveforms confirm correct integration:

Encryption & TX: plaintext → Trivium → ciphertext → UART TX

Reception & Decryption: UART RX → ciphertext → Trivium → plaintext

+ Project Resources

Source files for UART, Trivium, and System Integration

Testbenches for simulation and waveform verification

Documentation for design methodology and system evaluation

+ Results

The project successfully demonstrates a secure UART communication system with:

Full compliance with UART 16550

On-chip encryption/decryption via Trivium

Optimized initialization latency and pipelined data flow

Verified functionality in simulation with correct end-to-end secure communication
