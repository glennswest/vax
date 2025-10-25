# VAX-11/780 Architecture

## CPU Architecture

### Registers
- **R0-R11**: General purpose registers (32-bit)
- **R12 (AP)**: Argument Pointer
- **R13 (FP)**: Frame Pointer
- **R14 (SP)**: Stack Pointer
- **R15 (PC)**: Program Counter
- **PSL**: Processor Status Longword
  - Bits 31-24: Reserved
  - Bits 23-16: Current mode, previous mode, interrupt priority level
  - Bits 15-8: Reserved
  - Bits 7-0: Condition codes (N, Z, V, C) and flags

### Instruction Set
VAX instructions are variable length (1-37 bytes):
- Opcode (1-2 bytes)
- Operand specifiers (0-6 operands, variable length each)

Major instruction categories:
1. Integer arithmetic: ADDL, SUBL, MULL, DIVL, etc.
2. Logical: BIS, BIC, XOR, etc.
3. Shift/rotate: ASHL, ROTL, etc.
4. Control: BR, BEQ, BNE, JSB, RET, etc.
5. Memory: MOVL, MOVB, MOVC3, etc.
6. Privileged: MTPR, MFPR, LDPCTX, etc.

### Addressing Modes
VAX supports 16 addressing modes:
- 0x0-0x3: Literal short (0-3)
- 0x4: Indexed
- 0x5: Register
- 0x6: Register deferred
- 0x7: Autodecrement
- 0x8: Autoincrement
- 0x9: Autoincrement deferred
- 0xA: Byte displacement
- 0xB: Byte displacement deferred
- 0xC: Word displacement
- 0xD: Word displacement deferred
- 0xE: Long displacement
- 0xF: Long displacement deferred

## Memory Management

### Virtual Memory
- 32-bit virtual address space per process
- 4GB address space divided into 4 regions:
  - P0 (0x00000000-0x3FFFFFFF): Process private, grows up
  - P1 (0x40000000-0x7FFFFFFF): Process private, grows down
  - S0 (0x80000000-0xBFFFFFFF): System space
  - S1 (0xC0000000-0xFFFFFFFF): Reserved

### Page Tables
- 512-byte pages (9-bit offset)
- 21-bit virtual page number
- Two-level page table structure
- Page Table Entries (PTEs):
  - Bit 31: Valid
  - Bits 30-27: Protection code
  - Bit 26: Modified
  - Bits 25-0: Physical frame number

### Translation Process
1. Extract VPN from virtual address
2. Determine region (P0, P1, S0, S1)
3. Look up in Translation Buffer (TLB) first
4. On TLB miss, walk page table
5. Check protection and validity
6. Form physical address

## I/O Architecture

### MASSBUS
High-performance I/O bus for disk controllers:
- 32-bit data path
- Memory-mapped registers
- Direct memory access (DMA)

### UNIBUS
Peripheral bus for slower devices:
- 18-bit address space
- 16-bit data path
- Interrupt vector system

### Console TTY
Serial console for operator interaction:
- TX/RX buffers
- Interrupt-driven I/O
- Standard VAX console protocol

### PCIe Interface
Modern peripheral device support:
- PCIe Ethernet controllers (network connectivity)
- PCIe GPU devices (graphics acceleration)
- PCIe NVMe storage (high-speed disk I/O)
- PCIe SATA controllers (legacy disk support)
- Other PCIe expansion cards
- Configuration space and BAR (Base Address Register) mapping
- Multiple device support with proper enumeration

## Pipeline Design

For initial implementation, simple 5-stage pipeline:
1. **Fetch**: Get instruction bytes from memory
2. **Decode**: Parse opcode and operand specifiers
3. **Execute**: Perform ALU/memory operations
4. **Memory**: Access data memory if needed
5. **Writeback**: Update registers and condition codes

Variable-length instructions make this challenging:
- May need multiple fetch cycles
- Operand specifier parsing is complex
- Consider microcoded implementation

## Boot Process

1. Power-on reset
2. Console ROM loads boot loader
3. Boot loader reads boot block from disk
4. Boot block loads VMS bootstrap
5. VMS initializes and loads kernel
6. System enters multi-user mode

## OpenVMS Requirements

Must implement for VMS compatibility:
- Full instruction set (including privileged)
- Memory management with protection
- Interrupt and exception handling
- Interval timer
- Console interface
- Boot ROM
- At least one disk controller
