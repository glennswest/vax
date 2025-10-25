# Phase 4: Bit Field Instructions

## Overview

Phase 4 adds VAX bit field manipulation instructions needed for efficient data structure handling and bit-level operations. These instructions are critical for:
- Packed data structures
- Flag manipulation
- Network protocol parsing
- Graphics and multimedia operations

## Bit Field Instructions

### EXTV - Extract Field Variable (Signed)
**Opcode:** EE
**Format:** `EXTV pos.rl, size.rb, base.vb, dst.wl`

**Operation:**
```
Extract a signed bit field from memory/register
- pos: bit position (0-31) of field start
- size: field size in bits (1-32)
- base: base address or register
- dst: destination for extracted value (sign-extended)

Field bits: base<pos>:<pos+size-1>
Result is sign-extended to 32 bits
```

**Condition Codes:**
- N = extracted_value<31>
- Z = (extracted_value == 0)
- V = 0
- C = 0

**Implementation Status:** ⏳ Framework ready

**Use Cases:**
- Extract signed integers from packed structures
- Parse protocol headers with variable-length fields
- Decode compressed data formats

### EXTZV - Extract Field Zero-Extended
**Opcode:** EF
**Format:** `EXTZV pos.rl, size.rb, base.vb, dst.wl`

**Operation:**
```
Extract an unsigned bit field from memory/register
- Identical to EXTV but zero-extended instead of sign-extended
- Used for unsigned values and bit masks
```

**Condition Codes:**
- N = 0 (always, since zero-extended)
- Z = (extracted_value == 0)
- V = 0
- C = 0

**Implementation Status:** ⏳ Framework ready

**Use Cases:**
- Extract unsigned integers from packed data
- Decode flags and bit fields
- Parse network packet headers

### FFS - Find First Set Bit
**Opcode:** EA
**Format:** `FFS startpos.rl, size.rb, base.vb, findpos.wl`

**Operation:**
```
Find the first bit set to 1 in a bit field
- startpos: starting bit position
- size: field size in bits
- base: base address or register
- findpos: output position of first set bit (or -1 if none)

Scans from startpos to startpos+size-1
Returns position relative to base if found
Returns -1 (all bits set) if no bit is set
```

**Condition Codes:**
- N = 0
- Z = 1 if no bit found (findpos = -1)
- V = 0
- C = 0

**Implementation Status:** ⏳ Framework ready

**Use Cases:**
- Find free resources in bitmap allocators
- Locate next event in scheduling systems
- Search sparse data structures

### FFC - Find First Clear Bit
**Opcode:** EB
**Format:** `FFC startpos.rl, size.rb, base.vb, findpos.wl`

**Operation:**
```
Find the first bit cleared to 0 in a bit field
- Identical to FFS but searches for 0 instead of 1
```

**Condition Codes:**
- N = 0
- Z = 1 if no clear bit found
- V = 0
- C = 0

**Implementation Status:** ⏳ Framework ready

**Use Cases:**
- Find free slots in allocation bitmaps
- Locate available resources
- Memory management systems

### INSV - Insert Field
**Opcode:** F0
**Format:** `INSV src.rl, pos.rl, size.rb, base.vb`

**Operation:**
```
Insert a value into a bit field in memory/register
- src: source value to insert
- pos: bit position (0-31) of field start
- size: field size in bits (1-32)
- base: base address or register

Takes low <size> bits from src
Inserts into base<pos>:<pos+size-1>
Other bits in base unchanged
```

**Condition Codes:**
- N = src<size-1> (sign bit of inserted field)
- Z = (src<size-1:0> == 0)
- V = 0
- C = C (unchanged)

**Implementation Status:** ⏳ Framework ready

**Use Cases:**
- Update flags in control registers
- Modify packed data structures
- Construct protocol headers

### CMPV - Compare Field Variable (Signed)
**Opcode:** EC
**Format:** `CMPV pos.rl, size.rb, base.vb, src.rl`

**Operation:**
```
Compare a signed bit field with a value
- Extract field (sign-extended)
- Compare with src
- Set condition codes based on comparison
```

**Condition Codes:**
- N = (field < src)
- Z = (field == src)
- V = 0
- C = (field < src) unsigned comparison

**Implementation Status:** ⏳ Framework ready

### CMPZV - Compare Field Zero-Extended
**Opcode:** ED
**Format:** `CMPZV pos.rl, size.rb, base.vb, src.rl`

**Operation:**
```
Compare an unsigned bit field with a value
- Extract field (zero-extended)
- Compare with src
```

**Condition Codes:**
- N = 0
- Z = (field == src)
- V = 0
- C = (field < src) unsigned comparison

**Implementation Status:** ⏳ Framework ready

## Implementation Strategy

### Multi-Cycle Bit Field Operations

Bit field operations require careful handling of:
1. **Byte boundary crossing** - fields can span multiple bytes
2. **Memory access** - read-modify-write for INSV
3. **Shift and mask** - extract/insert bit fields

```vhdl
-- State machine for bit field operations
when CPU_BITFIELD_EXTRACT =>
    -- Calculate byte address and bit offset
    byte_addr := base_addr + (bit_pos / 8)
    bit_offset := bit_pos mod 8

    -- Read enough bytes to cover the field
    bytes_needed := (bit_offset + field_size + 7) / 8

    -- State transitions:
    -- 1. Read memory bytes
    -- 2. Extract and shift bits
    -- 3. Sign/zero extend
    -- 4. Write to destination

when CPU_BITFIELD_INSERT =>
    -- Similar to extract but with read-modify-write
    -- 1. Read existing bytes
    -- 2. Create mask for field
    -- 3. Insert new bits
    -- 4. Write back
```

### Bit Position Calculation

```vhdl
-- Bit addressing in VAX
-- Base can be:
--   - Register: bits 0-31 within register
--   - Memory: bits numbered from base byte address
--
-- Example: pos=10, size=6, base=0x1000
--   Byte 0x1000: bits 0-7
--   Byte 0x1001: bits 8-15 (field starts at bit 10)
--   Field spans bits 10-15

signal bit_field_value : longword_t;
signal bit_field_mask  : longword_t;
signal byte_start_addr : virt_addr_t;
signal bit_start_offset : integer range 0 to 7;
signal bytes_to_read : integer range 1 to 5;
```

### FFS/FFC Implementation

```vhdl
-- Find First Set/Clear
-- Scan bits one at a time (simple but slow)
-- Or use parallel scan (faster, more logic)

when CPU_BITFIELD_FFS_LOOP =>
    if scan_bit_index < field_size then
        -- Read bit at current position
        current_bit := memory_data(bit_offset);

        if current_bit = search_value then
            -- Found it
            result_pos := start_pos + scan_bit_index;
            cpu_state <= CPU_WRITEBACK;
        else
            scan_bit_index <= scan_bit_index + 1;
        end if;
    else
        -- Not found
        result_pos := x"FFFFFFFF";  -- -1
        cpu_state <= CPU_WRITEBACK;
    end if;
```

## Example Usage

### Example 1: Extract 12-bit Value

```assembly
; Extract 12-bit field at bit position 4 from memory
; Data at 0x1000: 0xABCD1234
; Bits 4-15: 0x123 (sign-extended to 0x00000123)

EXTV    #4, #12, @#0x1000, R1

; Result: R1 = 0x00000123
; Z = 0, N = 0
```

### Example 2: Insert Flag Bits

```assembly
; Set bits 8-11 to value 5 in control register
; Existing R2 = 0x12345678
; After: R2 = 0x12345578

MOVL    #5, R0
INSV    R0, #8, #4, R2

; Result: R2 = 0x12345578
```

### Example 3: Find Free Slot

```assembly
; Find first clear bit in allocation bitmap
; Bitmap at 0x2000, search 256 bits (32 bytes)

FFC     #0, #256, @#0x2000, R3

; Result: R3 = position of first 0 bit (or -1)
```

### Example 4: Network Protocol Parsing

```assembly
; Extract IP header fields
; IP packet at 0x3000
; Version: bits 0-3
; IHL: bits 4-7
; Total Length: bits 32-47

EXTZV   #0, #4, @#0x3000, R1    ; Version
EXTZV   #4, #4, @#0x3000, R2    ; IHL
EXTZV   #32, #16, @#0x3000, R3  ; Total Length
```

## Testing

### Test Program 1: EXTV/EXTZV

```assembly
; Test signed and unsigned extraction
MOVL    #0x80001234, R0
EXTV    #0, #16, R0, R1    ; Extract low 16 bits signed
EXTZV   #0, #16, R0, R2    ; Extract low 16 bits unsigned
HALT

; Expected:
; R1 = 0x00001234 (positive, sign bit = 0)
; R2 = 0x00001234 (zero-extended)
```

### Test Program 2: INSV

```assembly
; Insert value into bit field
MOVL    #0xFFFFFFFF, R0
MOVL    #0x5, R1
INSV    R1, #8, #4, R0    ; Insert 5 into bits 8-11
HALT

; Expected: R0 = 0xFFFFF5FF
```

### Test Program 3: FFS/FFC

```assembly
; Find first set and clear bits
MOVL    #0x00000100, R0   ; Bit 8 is set
FFS     #0, #32, R0, R1
FFC     #0, #32, R0, R2
HALT

; Expected:
; R1 = 8 (position of first set bit)
; R2 = 0 (position of first clear bit)
```

## Performance

**Bit Field Operations:**
- EXTV/EXTZV: ~5-10 cycles (depending on byte alignment)
- INSV: ~8-15 cycles (read-modify-write)
- FFS/FFC: ~5-40 cycles (worst case if field is large)
- CMPV/CMPZV: ~5-10 cycles (similar to extract)

**Optimization Opportunities:**
- Aligned field access can be faster (single longword read)
- Unaligned fields require multiple memory accesses
- FFS/FFC can use priority encoder for parallel scan

## CPU State Machine Extensions

New states required for vax_cpu_v7.vhd:

```vhdl
-- Bit field operation states
CPU_BF_CALC_ADDR,        -- Calculate byte address and offset
CPU_BF_READ_DATA,        -- Read memory bytes
CPU_BF_EXTRACT,          -- Extract and shift bits
CPU_BF_INSERT_MASK,      -- Create mask for insertion
CPU_BF_INSERT_WRITE,     -- Write back modified data
CPU_BF_FFS_LOOP,         -- Find first set loop
CPU_BF_FFC_LOOP          -- Find first clear loop
```

## Status Summary

| Instruction | Opcode | Decoded | Execute | Tested |
|-------------|--------|---------|---------|--------|
| EXTV        | EE     | ⏳      | ⏳      | ⏳     |
| EXTZV       | EF     | ⏳      | ⏳      | ⏳     |
| FFS         | EA     | ⏳      | ⏳      | ⏳     |
| FFC         | EB     | ⏳      | ⏳      | ⏳     |
| INSV        | F0     | ⏳      | ⏳      | ⏳     |
| CMPV        | EC     | ⏳      | ⏳      | ⏳     |
| CMPZV       | ED     | ⏳      | ⏳      | ⏳     |

**Overall Phase 4 Status:** 0% complete (implementation pending)

## Implementation Notes

1. **Byte Ordering**: VAX is little-endian, bits numbered from LSB
2. **Memory Access**: Bit fields can span up to 5 bytes (worst case)
3. **Alignment**: No alignment restrictions on bit field base addresses
4. **Interrupts**: Bit field operations should be interruptible for long fields
5. **Atomic Operations**: INSV requires read-modify-write atomicity

## OpenVMS Usage

Bit field instructions are used extensively in OpenVMS for:
- System data structure manipulation
- Process control blocks
- Device driver bit flags
- Memory management bitmaps
- Network protocol handling

These instructions are **critical for OpenVMS compatibility** and should be implemented before attempting to boot the operating system.
