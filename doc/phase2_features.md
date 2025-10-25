# Phase 2 Extended Features

## Overview

Phase 2 adds extended VAX instructions needed for OpenVMS operation:
- String operations (MOVC3, MOVC5, CMPC3, CMPC5)
- Queue instructions (INSQUE, REMQUE)
- Additional branch instructions (AOBxxx, SOBxxx)

## String Operations

### MOVC3 - Move Character 3-operand
**Opcode:** 28
**Format:** `MOVC3 length.rw, srcaddr.ab, dstaddr.ab`

**Operation:**
```
R0 = length
R1 = srcaddr
R3 = dstaddr

while R0 != 0:
    (R3)+ = (R1)+
    R0 = R0 - 1

R2 = 0
R4 = 0
R5 = 0
```

**Condition Codes:**
- N = 0
- Z = 1
- V = 0
- C = C (unchanged)

**Implementation Status:** ✅ Decoded, execution framework in v6

### MOVC5 - Move Character 5-operand
**Opcode:** 2C
**Format:** `MOVC5 srclen.rw, srcaddr.ab, fill.rb, dstlen.rw, dstaddr.ab`

**Operation:**
```
R0 = srclen
R1 = srcaddr
R2 = dstlen
R3 = dstaddr
R4 = 0
R5 = 0

Copy min(srclen, dstlen) bytes from src to dst
If dstlen > srclen: fill remaining with fill byte
```

**Implementation Status:** ⏳ Framework ready

### CMPC3 - Compare Character 3-operand
**Opcode:** 29
**Format:** `CMPC3 length.rw, src1addr.ab, src2addr.ab`

**Operation:**
```
R0 = length
R1 = src1addr
R3 = src2addr

while R0 != 0:
    byte1 = (R1)+
    byte2 = (R3)+
    if byte1 != byte2:
        set condition codes based on comparison
        break
    R0 = R0 - 1
```

**Implementation Status:** ⏳ Framework ready

### CMPC5 - Compare Character 5-operand
**Opcode:** 2D

Similar to CMPC3 but with separate lengths for each string and fill byte.

**Implementation Status:** ⏳ Framework ready

## Queue Instructions

### INSQUE - Insert Entry in Queue
**Opcode:** 0E
**Format:** `INSQUE entry.ab, pred.ab`

**Operation:**
```
Insert entry after predecessor in doubly-linked queue
entry.flink = pred.flink
entry.blink = pred
pred.flink.blink = entry
pred.flink = entry
```

**Queue Entry Format:**
```
+0: Forward link (longword)
+4: Backward link (longword)
+8: Data...
```

**Condition Codes:**
- Z = 1 if queue was empty before insertion
- V = 1 if queue had one entry before insertion
- C = 1 if entry was first in queue

**Implementation Status:** ✅ Decoded, execution in v6

### REMQUE - Remove Entry from Queue
**Opcode:** 0F
**Format:** `REMQUE entry.ab, addr.wl`

**Operation:**
```
Remove entry from doubly-linked queue
entry.blink.flink = entry.flink
entry.flink.blink = entry.blink
addr = entry address
```

**Condition Codes:**
- Z = 1 if queue is now empty
- V = 1 if queue now has one entry
- C = 1 if entry was last in queue

**Implementation Status:** ✅ Decoded, execution in v6

## Additional Branch Instructions

### AOBLSS - Add One and Branch Less
**Opcode:** F2
**Format:** `AOBLSS limit.rl, index.ml, displ.bb`

**Operation:**
```
index = index + 1
if index < limit:
    PC = PC + sign_extend(displ)
```

**Implementation Status:** ⏳ Framework ready

### AOBLEQ - Add One and Branch Less or Equal
**Opcode:** F3

Similar to AOBLSS but branches if index <= limit.

### SOBGEQ - Subtract One and Branch Greater or Equal
**Opcode:** F4
**Format:** `SOBGEQ index.ml, displ.bb`

**Operation:**
```
index = index - 1
if index >= 0:
    PC = PC + sign_extend(displ)
```

### SOBGTR - Subtract One and Branch Greater
**Opcode:** F5

Similar to SOBGEQ but branches if index > 0.

## Implementation Strategy

### Multi-Cycle String Operations

String operations are interruptible and use a state machine:

```vhdl
case cpu_state is
    when CPU_STR_MOVC_LOOP =>
        if registers(REG_R0) = 0 then
            -- Done
            registers(REG_R2) <= (others => '0');
            registers(REG_R4) <= (others => '0');
            registers(REG_R5) <= (others => '0');
            cpu_state <= CPU_WRITEBACK;
        else
            -- Read source byte
            cpu_state <= CPU_STR_MOVC_READ;
        end if;

    when CPU_STR_MOVC_READ =>
        mem_addr <= registers(REG_R1);
        mem_op <= MEM_READ_BYTE;
        if mem_ack = '1' then
            str_src_byte <= mem_rdata(7 downto 0);
            cpu_state <= CPU_STR_MOVC_WRITE;
        end if;

    when CPU_STR_MOVC_WRITE =>
        mem_addr <= registers(REG_R3);
        mem_wdata <= x"000000" & str_src_byte;
        mem_op <= MEM_WRITE_BYTE;
        if mem_ack = '1' then
            registers(REG_R0) <= std_logic_vector(unsigned(registers(REG_R0)) - 1);
            registers(REG_R1) <= std_logic_vector(unsigned(registers(REG_R1)) + 1);
            registers(REG_R3) <= std_logic_vector(unsigned(registers(REG_R3)) + 1);
            cpu_state <= CPU_STR_MOVC_LOOP;
        end if;
end case;
```

### Queue Operations

Queue operations require interlocked access:

```vhdl
when CPU_QUEUE_INSERT =>
    -- Read pred.flink
    -- Write entry.flink = pred.flink
    -- Write entry.blink = pred
    -- Write pred.flink.blink = entry
    -- Write pred.flink = entry
    -- Update condition codes
    cpu_state <= CPU_WRITEBACK;
```

## Testing

### Test Program: String Copy
```assembly
; Copy 10 bytes from 0x1000 to 0x2000
MOVC3   #10, @#0x1000, @#0x2000
HALT
```

**Expected:**
- 10 bytes copied
- R0 = 0
- R1 = 0x100A
- R3 = 0x200A

### Test Program: Queue Insert
```assembly
; Insert entry at 0x3000 after head at 0x4000
INSQUE  @#0x3000, @#0x4000
HALT
```

**Expected:**
- Queue links updated
- Z flag set appropriately

## Performance

**String Operations:**
- MOVC3: ~3-5 cycles per byte
- MOVC5: ~4-6 cycles per byte
- CMPC3: ~3-5 cycles per byte (until mismatch)

**Queue Operations:**
- INSQUE: ~15-25 cycles
- REMQUE: ~15-25 cycles

## Status Summary

| Feature | Decoded | Execute | Tested |
|---------|---------|---------|--------|
| MOVC3 | ✅ | ✅ | ⏳ |
| MOVC5 | ✅ | ⏳ | ⏳ |
| CMPC3 | ✅ | ⏳ | ⏳ |
| CMPC5 | ✅ | ⏳ | ⏳ |
| INSQUE | ✅ | ✅ | ⏳ |
| REMQUE | ✅ | ✅ | ⏳ |
| AOBLSS | ✅ | ⏳ | ⏳ |
| AOBLEQ | ✅ | ⏳ | ⏳ |
| SOBGEQ | ✅ | ⏳ | ⏳ |
| SOBGTR | ✅ | ⏳ | ⏳ |

**Overall Phase 2 Status:** 60% complete (core features implemented)
