# VAX-11/780 FPGA Implementation Guide

## Project Overview

This project provides a complete VAX-11/780 processor implementation in VHDL for modern Xilinx FPGAs. It's designed to run OpenVMS with virtual disk and console devices.

## Current Status

### Completed Components

1. **CPU Core** (`rtl/cpu/vax_cpu.vhd`)
   - Register file (R0-R15)
   - Instruction fetch and decode state machine
   - Basic instruction support (MOVL, ADDL, SUBL, MULL, CMPL, HALT)
   - Condition code generation

2. **ALU** (`rtl/cpu/vax_alu.vhd`)
   - Arithmetic operations (ADD, SUB, MUL, DIV)
   - Logical operations (AND, OR, XOR, BIC)
   - Shift and rotate
   - Condition code flags (N, Z, V, C)

3. **MMU** (`rtl/mmu/vax_mmu.vhd`)
   - Virtual-to-physical address translation
   - 64-entry TLB
   - Page table walker
   - Support for P0, P1, S0, S1 regions

4. **Memory Controller** (`rtl/memory/memory_controller.vhd`)
   - Interface to Xilinx MIG for DDR4/DDR5
   - Clock domain crossing
   - Command and data FIFOs
   - 32-bit to 512-bit data width conversion

5. **MASSBUS Controller** (`rtl/bus/massbus_controller.vhd`)
   - Emulates RP06/RP07 disk controller
   - Memory-mapped registers
   - DMA support
   - Interrupt generation

6. **UNIBUS Controller** (`rtl/bus/unibus_controller.vhd`)
   - DL11 console interface
   - Transmit and receive buffers
   - Interrupt support

7. **TTY UART** (`rtl/io/tty_uart.vhd`)
   - Configurable baud rate
   - 8N1 format
   - Simple serial interface

8. **PCIe Interface** (`rtl/io/pcie_interface.vhd`)
   - AXI Stream interface to Xilinx PCIe IP
   - Virtual disk image access
   - Console multiplexing
   - Message protocol for host communication

### TODO: Critical Implementation Work

#### 1. Complete Instruction Set

The current CPU decoder only implements a handful of instructions. To run OpenVMS, you need:

**Priority 1 - Core Instructions:**
- All integer arithmetic (ADDL, SUBL, MULL, DIVL, etc.)
- Move variants (MOVL, MOVB, MOVW, MOVC3, MOVC5)
- Branch instructions (BR, BEQ, BNE, BGT, BLT, etc.)
- Subroutine calls (CALLS, CALLG, RET, JSB, RSB)
- Stack operations (PUSHL, POPL)

**Priority 2 - System Instructions:**
- Privileged instructions (MTPR, MFPR, LDPCTX, SVPCTX)
- REI (Return from Exception/Interrupt)
- Exception handling

**Priority 3 - Additional:**
- Bit field instructions
- Queue instructions
- String instructions
- Floating point (can be deferred)

**Implementation Strategy:**
- Study VAX Architecture Reference Manual
- Create comprehensive decoder ROM or state machine
- Implement variable-length instruction parsing
- Handle all 16 addressing modes properly

#### 2. Complete Addressing Modes

Current implementation has placeholder addressing mode logic. VAX has 16 addressing modes:
- Register (mode 5)
- Register deferred (mode 6)
- Autoincrement/decrement (modes 7, 8, 9)
- Displacement modes (modes A, B, C, D, E, F)
- Indexed (mode 4)
- Literal (modes 0-3)

Each operand specifier must be parsed to determine the mode and fetch the operand.

#### 3. Exception and Interrupt Handling

Implement full exception mechanism:
- Exception vector table
- PSL saving and restoration
- Stack switching (kernel, executive, supervisor, user stacks)
- SCB (System Control Block) lookup
- REI instruction for return

Interrupt handling:
- 16-level priority
- Interrupt vectors
- Device interrupt requests
- Software interrupts

#### 4. Page Table Management

MMU needs:
- MTPR/MFPR for page table base registers (P0BR, P0LR, P1BR, P1LR, SBR, SLR)
- TLB flush on context switch
- Memory protection checking
- Modified bit updates
- Access violation exceptions

#### 5. Boot ROM

Create boot ROM with:
- Power-on self-test
- Console prompt
- Boot device selection
- Bootstrap loader

Store in FPGA block RAM, mapped to high memory addresses.

#### 6. Xilinx IP Integration

**MIG (Memory Interface Generator):**
```
Tools -> IP Catalog -> Memory Interface Generators -> MIG
```
- Configure for DDR4 or DDR5
- Set data width to 512 bits
- Enable AXI4 interface
- Connect to memory_controller.vhd

**PCIe IP:**
```
Tools -> IP Catalog -> PCIe -> AXI Bridge for PCI Express
```
- Configure for Gen3 x8 or Gen4 x4
- Enable AXI Stream interface
- Connect to pcie_interface.vhd

#### 7. Host Software

Create host driver (Linux/Windows) for:
- Disk image management
- Console access
- Control and status
- Debugging interface

Use standard PCIe driver framework:
- Linux: VFIO or UIO
- Windows: WDF

#### 8. Testing and Validation

**Unit Tests:**
- Test each instruction individually
- ALU verification
- MMU translation tests
- Device register access

**Integration Tests:**
- Simple programs (add, loop, subroutine)
- Memory access patterns
- Interrupt handling
- DMA operations

**System Tests:**
- Boot sequence
- VMS loader
- Console interaction
- Disk I/O

## Building the Project

### Prerequisites

- Xilinx Vivado (2020.2 or later)
- GHDL (for simulation, optional)
- GTKWave (for waveform viewing, optional)

### Synthesis

```bash
cd scripts
vivado -source build_vivado.tcl
```

In Vivado GUI:
1. Add MIG and PCIe IP cores
2. Configure for target board
3. Run synthesis: `launch_runs synth_1`
4. Run implementation: `launch_runs impl_1`
5. Generate bitstream: `launch_runs impl_1 -to_step write_bitstream`

### Simulation

```bash
cd scripts
chmod +x simulate.sh
./simulate.sh
```

View waveforms:
```bash
cd sim_build
gtkwave vax_cpu.ghw
```

## Development Workflow

1. **Start with CPU core:** Complete instruction decoder and execution
2. **Test incrementally:** Write small test programs, verify behavior
3. **Add peripherals:** Get console working first, then disk
4. **Build boot ROM:** Simple loader to test boot sequence
5. **VMS attempt:** Try booting VMS, fix issues as they arise

## References

- **VAX Architecture Reference Manual** - Essential for instruction set
- **VAX-11/780 Hardware Handbook** - System architecture
- **OpenVMS Internals and Data Structures** - OS requirements
- **Xilinx UG473** - 7 Series FPGAs Memory Interface Solutions
- **Xilinx PG194** - PCIe DMA/Bridge Subsystem

## Performance Targets

- **Clock Speed:** 100-200 MHz (VAX-11/780 was 5 MHz)
- **IPC:** 0.5-1.0 (original was ~0.3)
- **Memory Bandwidth:** DDR4 provides 25+ GB/s (original: ~13 MB/s)
- **Compatibility:** Should run all VMS software

## Resource Estimates

For Xilinx Kintex-7 XC7K325T:
- **LUTs:** ~50,000-100,000 (15-30% of chip)
- **FFs:** ~30,000-60,000
- **Block RAM:** ~200-300 (36Kb blocks)
- **DSP Slices:** 10-20 (for multiply/divide)

Larger FPGAs (UltraScale+) provide more headroom for optimization.

## Known Issues

1. CPU decoder is incomplete (only ~5 instructions)
2. Addressing modes are not fully implemented
3. No exception handling yet
4. MMU page table base registers not writable
5. Boot ROM not implemented
6. PCIe DMA not fully functional
7. No floating point support

## Next Steps

**Immediate (1-2 weeks):**
- [ ] Complete instruction decoder for top 20 instructions
- [ ] Implement basic addressing modes (register, immediate)
- [ ] Create simple boot ROM
- [ ] Test with hand-assembled programs

**Short-term (1-2 months):**
- [ ] Full instruction set implementation
- [ ] All addressing modes
- [ ] Exception handling
- [ ] Console I/O working

**Long-term (3-6 months):**
- [ ] Disk I/O functional
- [ ] Boot VMS to single-user mode
- [ ] Full system testing
- [ ] Performance optimization

## Contributing

Focus areas for contribution:
1. Instruction decoder
2. Addressing mode parser
3. Test programs
4. Boot ROM
5. Host software

## License

This project is for educational and research purposes. VAX architecture is a trademark of HP/DEC.
