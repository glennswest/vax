# VAX Instruction Set Quick Reference

## Instruction Format

VAX instructions are variable length:
```
[Opcode: 1-2 bytes] [Operand Specifier 1] [Operand Specifier 2] ...
```

## Common Opcodes (Hex)

### Integer Arithmetic
| Mnemonic | Opcode | Operands | Description |
|----------|--------|----------|-------------|
| ADDB2    | 80     | src.rb, dst.mb | Add byte (2 operand) |
| ADDW2    | A0     | src.rw, dst.mw | Add word (2 operand) |
| ADDL2    | C0     | src.rl, dst.ml | Add long (2 operand) |
| ADDB3    | 81     | src1.rb, src2.rb, dst.wb | Add byte (3 operand) |
| ADDW3    | A1     | src1.rw, src2.rw, dst.ww | Add word (3 operand) |
| ADDL3    | C1     | src1.rl, src2.rl, dst.wl | Add long (3 operand) |
| SUBB2    | 82     | src.rb, dst.mb | Subtract byte (2 operand) |
| SUBW2    | A2     | src.rw, dst.mw | Subtract word (2 operand) |
| SUBL2    | C2     | src.rl, dst.ml | Subtract long (2 operand) |
| SUBL3    | C3     | src1.rl, src2.rl, dst.wl | Subtract long (3 operand) |
| MULB2    | 84     | src.rb, dst.mb | Multiply byte (2 operand) |
| MULW2    | A4     | src.rw, dst.mw | Multiply word (2 operand) |
| MULL2    | C4     | src.rl, dst.ml | Multiply long (2 operand) |
| MULL3    | C5     | src1.rl, src2.rl, dst.wl | Multiply long (3 operand) |
| DIVB2    | 86     | src.rb, dst.mb | Divide byte (2 operand) |
| DIVW2    | A6     | src.rw, dst.mw | Divide word (2 operand) |
| DIVL2    | C6     | src.rl, dst.ml | Divide long (2 operand) |
| DIVL3    | C7     | src1.rl, src2.rl, dst.wl | Divide long (3 operand) |
| INCB     | 96     | dst.mb | Increment byte |
| INCW     | B6     | dst.mw | Increment word |
| INCL     | D6     | dst.ml | Increment long |
| DECB     | 97     | dst.mb | Decrement byte |
| DECW     | B7     | dst.mw | Decrement word |
| DECL     | D7     | dst.ml | Decrement long |

### Logical Operations
| Mnemonic | Opcode | Operands | Description |
|----------|--------|----------|-------------|
| BISB2    | 88     | mask.rb, dst.mb | Bit Set byte |
| BISW2    | A8     | mask.rw, dst.mw | Bit Set word |
| BISL2    | C8     | mask.rl, dst.ml | Bit Set long |
| BICB2    | 8A     | mask.rb, dst.mb | Bit Clear byte |
| BICW2    | AA     | mask.rw, dst.mw | Bit Clear word |
| BICL2    | CA     | mask.rl, dst.ml | Bit Clear long |
| XORB2    | 8C     | mask.rb, dst.mb | XOR byte |
| XORW2    | AC     | mask.rw, dst.mw | XOR word |
| XORL2    | CC     | mask.rl, dst.ml | XOR long |

### Move Instructions
| Mnemonic | Opcode | Operands | Description |
|----------|--------|----------|-------------|
| MOVB     | 90     | src.rb, dst.wb | Move byte |
| MOVW     | B0     | src.rw, dst.ww | Move word |
| MOVL     | D0     | src.rl, dst.wl | Move long |
| MOVQ     | 7D     | src.rq, dst.wq | Move quadword |
| MOVA{B,W,L} | 9E/3E/DE | src.ax, dst.wl | Move address |
| PUSHA{B,W,L} | 9F/3F/DF | src.ax | Push address |
| PUSHL    | DD     | src.rl | Push long |
| CLRB     | 94     | dst.wb | Clear byte |
| CLRW     | B4     | dst.ww | Clear word |
| CLRL     | D4     | dst.wl | Clear long |
| CLRQ     | 7C     | dst.wq | Clear quadword |

### Compare and Test
| Mnemonic | Opcode | Operands | Description |
|----------|--------|----------|-------------|
| CMPB     | 91     | src1.rb, src2.rb | Compare byte |
| CMPW     | B1     | src1.rw, src2.rw | Compare word |
| CMPL     | D1     | src1.rl, src2.rl | Compare long |
| TSTB     | 95     | src.rb | Test byte |
| TSTW     | B5     | src.rw | Test word |
| TSTL     | D5     | src.rl | Test long |
| BITB     | 93     | mask.rb, src.rb | Bit test byte |
| BITW     | B3     | mask.rw, src.rw | Bit test word |
| BITL     | D3     | mask.rl, src.rl | Bit test long |

### Branch Instructions
| Mnemonic | Opcode | Operands | Description |
|----------|--------|----------|-------------|
| BRB      | 11     | disp.bb | Branch (byte) |
| BRW      | 31     | disp.bw | Branch (word) |
| BEQ{L,U} | 13     | disp.bb | Branch if equal |
| BNEQ{L,U} | 12    | disp.bb | Branch if not equal |
| BLSS     | 19     | disp.bb | Branch if less than |
| BLEQ     | 15     | disp.bb | Branch if less or equal |
| BGTR     | 14     | disp.bb | Branch if greater |
| BGEQ     | 18     | disp.bb | Branch if greater or equal |
| BVC      | 1C     | disp.bb | Branch if overflow clear |
| BVS      | 1D     | disp.bb | Branch if overflow set |
| BCC/BGEQU | 1E    | disp.bb | Branch if carry clear |
| BCS/BLSSU | 1F    | disp.bb | Branch if carry set |

### Procedure Call
| Mnemonic | Opcode | Operands | Description |
|----------|--------|----------|-------------|
| CALLS    | FB     | numarg.rl, dst.ab | Call procedure |
| CALLG    | FA     | arglist.ab, dst.ab | Call with arg list |
| RET      | 04     | - | Return from procedure |
| JSB      | 16     | dst.ab | Jump to subroutine |
| RSB      | 05     | - | Return from subroutine |

### Privileged Instructions
| Mnemonic | Opcode | Operands | Description |
|----------|--------|----------|-------------|
| REI      | 02     | - | Return from exception/interrupt |
| LDPCTX   | 06     | - | Load process context |
| SVPCTX   | 07     | - | Save process context |
| MTPR     | DA     | src.rl, procreg.rl | Move to processor register |
| MFPR     | DB     | procreg.rl, dst.wl | Move from processor register |
| HALT     | 00     | - | Halt processor |

### String/Block Operations
| Mnemonic | Opcode | Operands | Description |
|----------|--------|----------|-------------|
| MOVC3    | 28     | len.rw, src.ab, dst.ab | Move characters (3 op) |
| MOVC5    | 2C     | srclen.rw, src.ab, fill.rb, dstlen.rw, dst.ab | Move with fill |
| CMPC3    | 29     | len.rw, src1.ab, src2.ab | Compare characters |
| LOCC     | 3A     | char.rb, len.rw, addr.ab | Locate character |
| SKPC     | 3B     | char.rb, len.rw, addr.ab | Skip character |

### Shift and Rotate
| Mnemonic | Opcode | Operands | Description |
|----------|--------|----------|-------------|
| ASHL     | 78     | cnt.rb, src.rl, dst.wl | Arithmetic shift long |
| ASHQ     | 79     | cnt.rb, src.rq, dst.wq | Arithmetic shift quad |
| ROTL     | 9C     | cnt.rb, src.rl, dst.wl | Rotate long |

## Operand Specifier Format

Each operand has a specifier byte that determines addressing mode:

| Mode | Format | Description |
|------|--------|-------------|
| 0-3  | `0n`   | Literal (value 0-63) |
| 4    | `4n`   | Indexed: [Rn] + next_specifier |
| 5    | `5n`   | Register: Rn |
| 6    | `6n`   | Register deferred: [Rn] |
| 7    | `7n`   | Autodecrement: [--Rn] |
| 8    | `8n`   | Autoincrement: [Rn++] |
| 9    | `9n`   | Autoincrement deferred: [[Rn++]] |
| A    | `An bb` | Byte displacement: [Rn + byte] |
| B    | `Bn bb` | Byte displacement deferred: [[Rn + byte]] |
| C    | `Cn ww` | Word displacement: [Rn + word] |
| D    | `Dn ww` | Word displacement deferred: [[Rn + word]] |
| E    | `En ll` | Long displacement: [Rn + long] |
| F    | `Fn ll` | Long displacement deferred: [[Rn + long]] |

### Special Cases (PC modes)
- `8F xx xx xx xx` - Immediate (autoincrement from PC)
- `9F xx xx xx xx` - Absolute (autoincrement deferred from PC)
- `AF bb` - Relative (byte displacement from PC)
- `CF ww` - Relative (word displacement from PC)
- `EF ll ll ll ll` - Relative (long displacement from PC)

## Example Instruction Encodings

### MOVL #42, R1
```
D0 8F 2A 00 00 00 51
```
- `D0` - MOVL opcode
- `8F 2A 00 00 00` - Immediate mode: #42 (0x0000002A)
- `51` - Register mode: R1

### ADDL3 R1, R2, R3
```
C1 51 52 53
```
- `C1` - ADDL3 opcode
- `51` - Register R1
- `52` - Register R2
- `53` - Register R3

### BRB loop (back 10 bytes)
```
11 F6
```
- `11` - BRB opcode
- `F6` - Displacement -10 (0xF6 = -10 in signed byte)

### CALLS #0, @#1000
```
FB 00 9F 00 10 00 00
```
- `FB` - CALLS opcode
- `00` - Literal 0 (no arguments)
- `9F 00 10 00 00` - Absolute mode: @#0x1000

## Processor Registers (for MTPR/MFPR)

| Number | Name | Description |
|--------|------|-------------|
| 00     | KSP  | Kernel Stack Pointer |
| 01     | ESP  | Executive Stack Pointer |
| 02     | SSP  | Supervisor Stack Pointer |
| 03     | USP  | User Stack Pointer |
| 08     | P0BR | P0 Base Register |
| 09     | P0LR | P0 Length Register |
| 0A     | P1BR | P1 Base Register |
| 0B     | P1LR | P1 Length Register |
| 0C     | SBR  | System Base Register |
| 0D     | SLR  | System Length Register |
| 10     | PCBB | Process Control Block Base |
| 11     | SCBB | System Control Block Base |
| 12     | IPL  | Interrupt Priority Level |
| 18     | ASTLVL | AST Level |
| 20     | ICCS | Interval Clock Control/Status |
| 24     | TODR | Time of Day Register |
| 38     | MAPEN | Memory Management Enable |

## Implementation Priority

### Phase 1 (Boot Capable)
1. MOVL, MOVB, MOVW - data movement
2. ADDL, SUBL - basic arithmetic
3. CMPL - comparisons
4. Branch instructions (BEQ, BNE, BRB)
5. JSB, RSB - subroutine calls
6. HALT - stop execution

### Phase 2 (VMS Compatible)
7. CALLS, RET - procedure calls
8. PUSHL, POPL - stack operations
9. All arithmetic (MUL, DIV, INC, DEC)
10. Logical operations (BIS, BIC, XOR)
11. MTPR, MFPR - processor registers
12. REI - return from interrupt

### Phase 3 (Full Implementation)
13. String operations (MOVC3, MOVC5, CMPC3)
14. Bit field instructions
15. Queue instructions
16. Floating point (if needed)

## Resources

- VAX Architecture Reference Manual (EY-3459E-DP)
- VAX-11 Instruction Set (AA-N648A-TE)
- MicroVAX 78032 Microprocessor User's Guide
