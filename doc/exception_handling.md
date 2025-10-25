# VAX Exception and Interrupt Handling

## Overview

The VAX architecture provides a sophisticated exception and interrupt mechanism using the System Control Block (SCB) for vectored dispatch. This document describes the implementation of exception handling in the VAX FPGA design.

## Architecture

### System Control Block (SCB)

The SCB is a table of exception and interrupt vectors located in system space. The base address is stored in the SCBB (System Control Block Base) processor register.

**SCB Structure:**
```
SCB Base (SCBB)
├── 0x00: Machine Check Exception
├── 0x04: Kernel Stack Not Valid
├── 0x08: Power Fail
├── 0x0C: Reserved/Privileged Instruction
├── 0x10: Customer Reserved Instruction
├── 0x14: Reserved Operand
├── 0x18: Reserved Addressing Mode
├── 0x1C: Access Violation
├── 0x20: Translation Not Valid
├── 0x24: Trace Trap
├── 0x28: Breakpoint Fault
├── 0x2C: Compatibility Mode Fault
├── 0x30: Arithmetic Trap
├── 0x34-0x3C: Unused
├── 0x40-0x7C: Software Interrupts (IPL 1-15)
├── 0x80: Interval Timer Interrupt
├── 0x84-0xFC: Device Interrupts
└── ... (up to 0x3FF)
```

Each SCB entry contains:
- **Longword 0:** Address of exception handler
- **Longword 1:** Reserved (for future use)

## Exception Types

### Hardware Exceptions

| Exception | Vector | Priority | Description |
|-----------|--------|----------|-------------|
| Machine Check | 0x00 | Highest | Hardware error |
| Kernel Stack Invalid | 0x04 | 2 | KSP not valid |
| Power Fail | 0x08 | 3 | Power failure |
| Reserved Instruction | 0x0C | 4 | Illegal opcode |
| Reserved Operand | 0x14 | 5 | Invalid operand |
| Reserved Addressing | 0x18 | 6 | Invalid addressing mode |
| Access Violation | 0x1C | 7 | Memory protection |
| Translation Not Valid | 0x20 | 8 | Page fault |
| Trace Trap | 0x24 | 9 | Single-step debug |
| Breakpoint | 0x28 | 10 | BPT instruction |
| Arithmetic Trap | 0x30 | 11 | Overflow, divide by zero |

### Software Interrupts

- **IPL 1-15:** Software-initiated interrupts
- Vector offset: 0x40 + (IPL * 4)
- Lower IPL = lower priority

### Hardware Interrupts

- **Device interrupts:** 0x80 and above
- Each device has assigned vector
- Interrupt priority level (IPL) determines scheduling

## Exception Processing

### Exception Entry Sequence

When an exception occurs:

1. **Save PC and PSL**
   ```
   -(SP) = PC      // Return address
   -(SP) = PSL     // Processor status
   ```

2. **Push exception-specific parameters**
   - Varies by exception type
   - May include fault address, error code, etc.

3. **Look up handler in SCB**
   ```
   handler_addr = (SCBB) + vector_offset
   handler = (handler_addr)
   ```

4. **Update processor mode**
   ```
   PSL[PRVMOD] = PSL[CURMOD]  // Save previous mode
   PSL[CURMOD] = KERNEL        // Switch to kernel mode
   ```

5. **Clear trace pending**
   ```
   PSL[TP] = 0
   ```

6. **Jump to handler**
   ```
   PC = handler
   ```

### Stack Frame Format

```
High Address
┌──────────────────────────┐
│  Exception Parameters    │  (varies by exception)
├──────────────────────────┤
│  Saved PSL               │  (4 bytes)
├──────────────────────────┤
│  Saved PC                │  (4 bytes)
├──────────────────────────┤  ← SP after exception
│  (Handler's stack frame) │
└──────────────────────────┘
Low Address
```

## REI Instruction (Return from Exception/Interrupt)

**Opcode:** 02

### Operation

1. **Pop PC from stack**
   ```
   PC = (SP)+
   ```

2. **Pop PSL from stack**
   ```
   PSL = (SP)+
   ```

3. **Validate new PSL**
   - Check reserved bits
   - Verify mode transition is legal

4. **Update processor state**
   - Restore condition codes
   - Restore IPL
   - Restore processor mode
   - Restore trace pending

5. **Continue execution**
   - Execution resumes at restored PC

### Legal Mode Transitions

| Current Mode | Can REI to |
|--------------|-----------|
| Kernel | Kernel, Executive, Supervisor, User |
| Executive | Executive, Supervisor, User |
| Supervisor | Supervisor, User |
| User | User only |

**Rule:** Can only REI to same or less privileged mode

## Exception-Specific Details

### Machine Check (Vector 0x00)

**Parameters pushed:**
- Byte count (length of error info)
- Error information (varies by implementation)

**Handler must:**
- Log error information
- Attempt recovery or halt system

### Access Violation (Vector 0x1C)

**Parameters pushed:**
- Fault address (virtual address that caused fault)
- Access type (read/write/execute)
- Protection code

**Handler must:**
- Check if valid access
- Update page table if needed
- Signal process if invalid

### Translation Not Valid (Vector 0x20)

**Parameters pushed:**
- Fault address
- Access type

**Handler must:**
- Load page from disk
- Update TLB
- REI to retry instruction

### Arithmetic Trap (Vector 0x30)

**Parameters pushed:**
- Exception type (overflow, divide by zero, etc.)

**Handler must:**
- Fix up result or signal process

## Implementation States

### CPU State Machine Extensions

```vhdl
type cpu_state_t is (
    -- ... existing states ...
    CPU_EXCEPTION,               -- Exception entry
    CPU_EXCEPTION_PUSH_PC,       -- Push PC onto stack
    CPU_EXCEPTION_PUSH_PSL,      -- Push PSL onto stack
    CPU_EXCEPTION_PUSH_PARAMS,   -- Push exception parameters
    CPU_EXCEPTION_READ_SCB,      -- Read handler from SCB
    CPU_EXCEPTION_DISPATCH,      -- Jump to handler
    -- REI states
    CPU_REI_POP_PC,              -- Pop PC from stack
    CPU_REI_POP_PSL,             -- Pop PSL from stack
    CPU_REI_VALIDATE,            -- Validate PSL
    CPU_REI_RESTORE              -- Restore and continue
);
```

### Exception State Variables

```vhdl
signal exc_vector       : std_logic_vector(9 downto 0);  -- Exception vector (0-1023)
signal exc_param_count  : integer range 0 to 16;         -- Number of params to push
signal exc_params       : longword_array_t(0 to 15);     -- Exception parameters
signal exc_handler_addr : virt_addr_t;                   -- Handler address from SCB
signal exc_saved_pc     : virt_addr_t;                   -- PC at exception
signal exc_saved_psl    : longword_t;                    -- PSL at exception
```

## Exception Priority

When multiple exceptions occur simultaneously:

1. **Machine Check** - Highest priority
2. **Kernel Stack Invalid**
3. **Interrupt** (by IPL, higher IPL first)
4. **Trace Trap**
5. **Reserved Instruction**
6. **Reserved Operand**
7. **Reserved Addressing**
8. **Access Violation**
9. **Translation Not Valid**
10. **Arithmetic Trap** - Lowest priority

## Interrupt Processing

### Interrupt Priority Level (IPL)

- IPL is stored in PSL[20:16]
- Range: 0-31
- 0 = No interrupts masked
- 31 = All maskable interrupts masked

### Interrupt Recognition

Interrupts are recognized between instructions when:
```
interrupt_ipl > PSL[IPL]
```

### Interrupt Sequence

1. Check pending interrupts
2. Find highest priority interrupt with IPL > current IPL
3. Save current IPL
4. Set new IPL to interrupt IPL
5. Vector through SCB
6. Execute interrupt handler
7. REI restores old IPL

## Examples

### Example 1: Reserved Instruction Exception

**Instruction:** 0xFF (invalid opcode)

**Sequence:**
1. Decode detects invalid opcode
2. exc_vector = 0x0C (reserved instruction)
3. Push PC (address of invalid instruction)
4. Push PSL
5. Read handler from SCB[0x0C]
6. Switch to kernel mode
7. PC = handler address
8. Handler analyzes instruction, signals process
9. REI (may skip instruction or terminate process)

### Example 2: Page Fault

**Instruction:** MOVL R1, (R2)

**Sequence:**
1. Calculate address from R2
2. MMU detects page not valid
3. exc_vector = 0x20 (translation not valid)
4. exc_params[0] = fault address
5. exc_params[1] = access type (write)
6. Push params, PC, PSL
7. Read handler from SCB[0x20]
8. PC = handler
9. Handler loads page from disk
10. Handler updates page table
11. Handler executes REI
12. Instruction retries and succeeds

### Example 3: Arithmetic Overflow

**Instruction:** ADDL2 R1, R2 (with overflow)

**Sequence:**
1. ALU detects overflow
2. If PSL[IV] = 1 (integer overflow trap enabled):
   - exc_vector = 0x30
   - exc_params[0] = exception type (overflow)
   - Push params, PC, PSL
   - Dispatch to handler
3. If PSL[IV] = 0:
   - Just set PSL[V] flag
   - Continue execution

## Testing Strategy

### Test Cases

1. **Reserved Instruction**
   - Execute invalid opcode
   - Verify exception vector
   - Verify handler dispatch

2. **Arithmetic Overflow**
   - Enable integer overflow trap
   - Execute ADDL2 with overflow
   - Verify exception

3. **REI Instruction**
   - Build exception stack frame
   - Execute REI
   - Verify PC and PSL restoration

4. **Nested Exceptions**
   - Exception occurs during exception handler
   - Verify stack growth
   - Verify correct unwinding

5. **Interrupt Processing**
   - Raise interrupt with IPL > current IPL
   - Verify interrupt recognized
   - Verify handler dispatch
   - Verify IPL update

## Performance

### Cycle Estimates

**Exception Entry:**
- Base: 15-20 cycles
- Push PC/PSL: 4 cycles
- Push parameters: 2-4 cycles per param
- SCB read: 5 cycles
- Total: 25-35 cycles typical

**REI:**
- Pop PC: 5 cycles
- Pop PSL: 5 cycles
- Validation: 2 cycles
- Restore: 3 cycles
- Total: 15-20 cycles

## Known Limitations

1. **Simplified parameter pushing**
   - Some exceptions have complex parameter sets
   - Implementation provides basic support

2. **No double exception handling**
   - Exception during exception may cause issues
   - Need robust error handling

3. **Limited interrupt support**
   - Basic IPL mechanism
   - Device-specific handling may be incomplete

## References

- VAX Architecture Reference Manual - Chapter 6 (Exceptions and Interrupts)
- VAX Architecture Reference Manual - Appendix C (SCB Layout)
- OpenVMS Internals and Data Structures
