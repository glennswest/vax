# VAX Procedure Calling Convention

## Overview

The VAX architecture provides sophisticated procedure calling instructions (CALLS/CALLG/RET) that automate the creation and destruction of stack frames, register saving/restoring, and argument passing.

This document describes the implementation of the procedure calling convention in the VAX FPGA design.

## Architecture

### Stack Frame Layout

```
High Address
┌──────────────────────────┐
│  Caller's Stack Frame    │
├──────────────────────────┤
│  Argument N              │  \
│  Argument N-1            │   │
│  ...                     │   ├─ Arguments (pushed by caller)
│  Argument 2              │   │
│  Argument 1              │  /
├──────────────────────────┤
│  Argument Count          │  ← AP points here (4 bytes)
├──────────────────────────┤
│  Return PC               │  (4 bytes, saved by CALLS)
├──────────────────────────┤
│  Saved FP                │  (4 bytes)
├──────────────────────────┤
│  Saved AP                │  (4 bytes)
├──────────────────────────┤
│  Saved PSW (16 bits)     │  (2 bytes, aligned to 4)
│  Save Mask (16 bits)     │  (2 bytes)
├──────────────────────────┤
│  Saved R11               │  \ Only if bit 11 of mask set
│  Saved R10               │   │
│  Saved R9                │   │
│  Saved R8                │   │
│  Saved R7                │   ├─ Saved registers (if in mask)
│  Saved R6                │   │
│  Saved R5                │   │
│  Saved R4                │   │
│  Saved R3                │   │
│  Saved R2                │  /
├──────────────────────────┤  ← FP points here
│  Condition Handler       │  (4 bytes, optional)
├──────────────────────────┤
│  Local Variables         │
│  ...                     │
├──────────────────────────┤  ← SP points here
│  (Future stack growth)   │
└──────────────────────────┘
Low Address
```

## CALLS Instruction

### Format
```
CALLS  numarg.rl, dst.ab
Opcode: FB
```

### Operands
- **numarg** - Number of arguments (longword)
- **dst** - Destination address of procedure (address mode)

### Operation

1. **Push argument count**
   ```
   SP = SP - 4
   (SP) = numarg
   ```

2. **Push return PC**
   ```
   SP = SP - 4
   (SP) = PC
   ```

3. **Push FP and AP**
   ```
   SP = SP - 4
   (SP) = FP
   SP = SP - 4
   (SP) = AP
   ```

4. **Push PSW and save mask**
   ```
   SP = SP - 4
   (SP)[31:16] = PSW
   (SP)[15:0] = entry_mask   // From procedure entry point
   ```

5. **Save registers**
   - For each bit set in entry_mask (bits 11:0):
     ```
     if entry_mask[i] = '1' then
         SP = SP - 4
         (SP) = R[i]
     ```

6. **Set new FP and AP**
   ```
   FP = SP
   AP = FP + 20 + 4*(number of saved regs)
   ```

7. **Jump to procedure**
   ```
   PC = dst + 2   // Skip entry mask
   ```

### Entry Mask

The first word at the procedure entry point is the **entry mask**:
- Bits 15:12 - Reserved
- Bits 11:0 - Register save mask (R11:R0)
  - Bit 11 = 1: Save R11
  - Bit 10 = 1: Save R10
  - ...
  - Bit 0 = 1: Save R0

**Note:** Typically only R2-R11 are saved (bits 11:2). R0-R1 are scratch registers.

## CALLG Instruction

### Format
```
CALLG  arglist.ab, dst.ab
Opcode: FA
```

### Operands
- **arglist** - Address of argument list (first longword is count)
- **dst** - Destination address of procedure

### Operation

Similar to CALLS, but:
1. Read argument count from (arglist)
2. Set AP = arglist
3. Proceed with steps 2-7 from CALLS

**Key Difference:** Arguments are already in memory; CALLG just points to them.

## RET Instruction

### Format
```
RET
Opcode: 04
```

### Operation

1. **Restore registers**
   - Read save mask from FP-4
   - For each bit set in save mask:
     ```
     if mask[i] = '1' then
         R[i] = (SP)
         SP = SP + 4
     ```

2. **Restore PSW**
   ```
   PSW = (FP-4)[31:16]
   ```

3. **Restore AP and FP**
   ```
   temp_fp = FP
   AP = (temp_fp - 8)
   FP = (temp_fp - 12)
   SP = temp_fp
   ```

4. **Get return PC**
   ```
   PC = (SP)
   SP = SP + 4
   ```

5. **Get argument count**
   ```
   argcount = (SP)
   SP = SP + 4
   ```

6. **Pop arguments**
   ```
   SP = SP + (argcount * 4)
   ```

7. **Continue execution**
   - PC now points to instruction after CALLS/CALLG

## Implementation States

### CPU State Machine Extensions

```vhdl
type cpu_state_t is (
    CPU_RESET,
    CPU_FETCH_INST,
    CPU_DECODE_INST,
    CPU_FETCH_OPERAND,
    CPU_EXECUTE,
    CPU_WRITEBACK,
    CPU_EXCEPTION,
    CPU_HALT,
    -- Procedure call states
    CPU_CALLS_PUSH_ARGS,       -- Push numarg onto stack
    CPU_CALLS_PUSH_PC,         -- Push return PC
    CPU_CALLS_PUSH_FP_AP,      -- Push FP and AP
    CPU_CALLS_READ_MASK,       -- Read entry mask from procedure
    CPU_CALLS_PUSH_PSW_MASK,   -- Push PSW and save mask
    CPU_CALLS_SAVE_REGS,       -- Save registers (loop)
    CPU_CALLS_SET_POINTERS,    -- Set new FP and AP
    CPU_CALLS_JUMP,            -- Jump to procedure
    -- Return states
    CPU_RET_RESTORE_REGS,      -- Restore registers (loop)
    CPU_RET_RESTORE_PTRS,      -- Restore AP, FP, SP
    CPU_RET_GET_PC,            -- Get return PC
    CPU_RET_POP_ARGS           -- Pop arguments and return
);
```

### State Variables

```vhdl
signal call_numarg       : longword_t;        -- Argument count
signal call_entry_mask   : word_t;            -- Entry mask
signal call_saved_count  : integer;           -- Number of saved regs
signal call_reg_index    : integer;           -- Current register being saved/restored
signal call_return_pc    : virt_addr_t;       -- Return PC
signal call_saved_fp     : longword_t;        -- Saved FP
signal call_saved_ap     : longword_t;        -- Saved AP
signal call_new_fp       : longword_t;        -- New FP value
```

## Example: Simple Procedure Call

### C Code
```c
int add(int a, int b) {
    return a + b;
}

int main() {
    int result = add(5, 10);
    return result;
}
```

### VAX Assembly

```assembly
; Procedure: add
; Entry mask: 0x0000 (no registers saved)
add:
    .word   0x0000              ; Entry mask
    addl3   4(ap), 8(ap), r0    ; R0 = arg1 + arg2
    ret                         ; Return

; Main program
main:
    .word   0x0000              ; Entry mask
    pushl   #10                 ; Push arg2
    pushl   #5                  ; Push arg1
    calls   #2, add             ; Call add with 2 args
    movl    r0, result          ; Store result
    ret
```

### Machine Code

```
; add procedure at 0x1000
1000: 00 00              ; Entry mask
1002: C1 A4 04 A8 08 50 ; ADDL3 4(AP), 8(AP), R0
1008: 04                 ; RET

; main at 0x2000
2000: 00 00              ; Entry mask
2002: DD 0A              ; PUSHL #10
2004: DD 05              ; PUSHL #5
2006: FB 02 AF 00 10     ; CALLS #2, @#0x1000
200B: D0 50 A0           ; MOVL R0, result
200E: 04                 ; RET
```

### Execution Trace

**Before CALLS:**
```
R0-R15: (caller state)
SP: 0x7FFE0000
FP: 0x7FFE0100
AP: 0x7FFE0200
PC: 0x2006
Stack: [10, 5, ...]
```

**During CALLS:**
1. Push numarg=2 → SP=0x7FFDFFFC, (SP)=2
2. Push PC=0x200B → SP=0x7FFDFFFB, (SP)=0x200B
3. Push FP=0x7FFE0100 → SP=0x7FFDFFB4
4. Push AP=0x7FFE0200 → SP=0x7FFDFFB0
5. Read mask from 0x1000 → mask=0x0000
6. Push PSW+mask → SP=0x7FFDFFAC
7. No registers to save (mask=0)
8. Set FP=0x7FFDFFAC, AP=0x7FFDFFBC (points to numarg)
9. PC=0x1002 (skip entry mask)

**During add execution:**
```
Fetch 4(AP):  AP=0x7FFDFFBC, (0x7FFDFFBC+4)=(0x7FDFFC0)=5
Fetch 8(AP):  AP=0x7FFDFFBC, (0x7FFDFFBC+8)=(0x7FDFFC4)=10
ADDL3: R0 = 5 + 10 = 15
```

**During RET:**
1. Read mask from FP-4 → mask=0x0000
2. No registers to restore
3. Restore PSW from (FP-4)
4. Restore AP=(FP-8)=0x7FFE0200
5. Restore FP=(FP-12)=0x7FFE0100
6. SP=FP=0x7FFDFFAC
7. PC=(SP)=0x200B, SP=0x7FFDFFB0
8. argcount=(SP)=2, SP=0x7FFDFFB4
9. SP=SP+8=0x7FFDFFBC (pop 2 args)
10. Continue at PC=0x200B

## Testing Strategy

### Test Cases

1. **Simple call with no args**
   ```
   CALLS #0, proc
   ```

2. **Call with arguments**
   ```
   PUSHL #10
   PUSHL #5
   CALLS #2, add
   ```

3. **Call with register saves**
   ```
   Procedure with entry mask 0x0FFC (save R2-R11)
   ```

4. **Nested calls**
   ```
   main → proc1 → proc2 → proc2 returns → proc1 returns → main
   ```

5. **CALLG vs CALLS**
   ```
   Test both calling mechanisms
   ```

## Performance

### Cycle Estimates

**CALLS:**
- Base: 15-20 cycles
- Per saved register: +2 cycles
- Entry mask read: +5 cycles (memory access)
- Total: 20-30 cycles typical

**RET:**
- Base: 15-20 cycles
- Per restored register: +2 cycles
- Total: 20-30 cycles typical

**Optimization opportunities:**
- Parallel stack operations
- Register save burst mode
- Prefetch entry mask

## Known Limitations

1. **Condition handler not implemented**
   - Stack frame reserves space but not used
   - Will be needed for exception handling

2. **Argument list validation**
   - No checking of argument count vs available stack
   - Could cause stack overflow

3. **Entry mask at procedure**
   - Assumes procedure has proper entry mask
   - Invalid mask could cause incorrect behavior

## References

- VAX Architecture Reference Manual - Chapter 5 (Procedure Calling)
- VAX Architecture Reference Manual - Appendix B (Stack Frame Format)
- OpenVMS Calling Standard
