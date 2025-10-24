# VAX Boot ROM Design

## Overview

The boot ROM provides the initial code executed when the VAX powers on. It's stored in FPGA block RAM and mapped to high memory addresses (typically starting at 0x20000000 in physical memory).

## Boot Sequence

1. **Power-On Reset**
   - PC set to boot ROM base (0x20000000)
   - PSL set to kernel mode
   - All registers cleared
   - MMU disabled initially

2. **Self-Test**
   - Test ALU operations
   - Test memory (basic read/write)
   - Test console output

3. **Console Initialization**
   - Initialize UART
   - Print banner message

4. **Boot Device Selection**
   - Check for bootable disk
   - Read boot block from disk sector 0
   - Validate boot block signature

5. **Bootstrap Loader**
   - Load VMS bootstrap from disk
   - Transfer control to bootstrap

## Boot ROM Memory Map

```
0x20000000 - 0x20000003  Reset vector (JMP to start)
0x20000004 - 0x20000007  Machine check vector
0x20000008 - 0x2000000B  Kernel stack invalid vector
0x2000000C - 0x2000000F  Power fail vector
0x20000010 - 0x20000FFF  Boot code
0x20001000 - 0x20001FFF  Data area
```

## Sample Boot ROM Code (Pseudo-Assembly)

```assembly
; VAX Boot ROM
; Entry point: 0x20000000

        .org    0x20000000

; Reset vector
reset_vector:
        JMP     boot_start

; Exception vectors (simplified)
        .org    0x20000004
mcheck_vector:
        HALT                    ; Machine check - just halt

        .org    0x20000008
kstack_vector:
        HALT                    ; Kernel stack invalid

        .org    0x2000000C
powerfail_vector:
        HALT                    ; Power fail

; Boot code starts here
        .org    0x20000010
boot_start:
        ; Initialize stack pointer
        MOVL    #0x7FFFFFFF, SP ; Top of memory for now

        ; Test basic CPU
        MOVL    #0x12345678, R1
        MOVL    R1, R2
        CMPL    R1, R2
        BNEQ    cpu_test_fail

        ; Initialize console UART
        JSB     init_console

        ; Print banner
        MOVL    #banner_msg, R0
        JSB     print_string

        ; Check for disk
        JSB     check_disk
        BLBC    R0, no_disk

        ; Read boot block from disk
        CLRL    R0              ; Sector 0
        MOVL    #boot_buffer, R1 ; Buffer address
        JSB     read_disk_sector
        BLBC    R0, disk_error

        ; Validate boot block signature
        MOVL    boot_buffer, R0
        CMPL    R0, #0x0000AA55 ; MBR signature
        BNEQ    invalid_boot

        ; Jump to boot block code
        JSB     @#boot_buffer+4

        ; Should not return
        HALT

cpu_test_fail:
        MOVL    #cpu_fail_msg, R0
        JSB     print_string
        HALT

no_disk:
        MOVL    #no_disk_msg, R0
        JSB     print_string
        HALT

disk_error:
        MOVL    #disk_err_msg, R0
        JSB     print_string
        HALT

invalid_boot:
        MOVL    #invalid_boot_msg, R0
        JSB     print_string
        HALT

; Initialize console UART
init_console:
        ; Setup DL11 console at 177560 (UNIBUS address)
        MOVL    #0x00000040, R0 ; Enable receiver interrupt
        MOVW    R0, @#0x20177560 ; RCSR
        MOVL    #0x00000040, R0 ; Enable transmitter interrupt
        MOVW    R0, @#0x20177564 ; XCSR
        RSB

; Print null-terminated string
; Input: R0 = pointer to string
print_string:
        PUSHL   R1
        PUSHL   R2
        MOVL    R0, R1          ; String pointer

print_loop:
        MOVB    (R1)+, R2       ; Get character
        BEQL    print_done      ; End of string
        JSB     print_char
        BRB     print_loop

print_done:
        POPL    R2
        POPL    R1
        RSB

; Print single character
; Input: R2 = character
print_char:
        PUSHL   R3

wait_tx_ready:
        MOVW    @#0x20177564, R3 ; Read XCSR
        BITW    #0x0080, R3      ; Test ready bit
        BEQL    wait_tx_ready

        MOVB    R2, @#0x20177566 ; Write to XBUF
        POPL    R3
        RSB

; Check if disk is present
; Output: R0 = 1 if present, 0 if not
check_disk:
        MOVL    @#0x20172154, R0 ; Read RPDS (drive status)
        BITL    #0x00000080, R0  ; Check RDY bit
        BEQL    check_disk_fail

        MOVL    #1, R0
        RSB

check_disk_fail:
        CLRL    R0
        RSB

; Read disk sector
; Input: R0 = sector number (LBA)
;        R1 = buffer address
; Output: R0 = status (1 = success, 0 = fail)
read_disk_sector:
        PUSHL   R2
        PUSHL   R3

        ; Setup disk controller (MASSBUS RP06)
        MOVL    R0, @#0x2017220C ; RPDA - disk address
        MOVL    R1, @#0x20172208 ; RPBA - buffer address
        MOVL    #0xFFFFFC00, @#0x20172204 ; RPWC - word count (-512 words)

        ; Issue read command
        MOVL    #0x00000071, @#0x20172200 ; RPCS1 - read + go

        ; Wait for completion
wait_disk:
        MOVL    @#0x20172200, R2 ; Read RPCS1
        BITL    #0x00000080, R2  ; Check RDY
        BEQL    wait_disk

        ; Check for errors
        BITL    #0x00008000, R2  ; Check ERR bit
        BNEQ    read_disk_error

        MOVL    #1, R0
        BRB     read_disk_done

read_disk_error:
        CLRL    R0

read_disk_done:
        POPL    R3
        POPL    R2
        RSB

; Data section
        .org    0x20001000

banner_msg:
        .ascii  "VAX-11/780 FPGA Boot ROM v1.0\r\n"
        .ascii  "Copyright 2025\r\n\n"
        .byte   0

cpu_fail_msg:
        .ascii  "CPU self-test FAILED\r\n"
        .byte   0

no_disk_msg:
        .ascii  "No bootable disk found\r\n"
        .byte   0

disk_err_msg:
        .ascii  "Disk read error\r\n"
        .byte   0

invalid_boot_msg:
        .ascii  "Invalid boot block\r\n"
        .byte   0

; Boot buffer (512 bytes)
boot_buffer:
        .space  512
```

## VHDL Implementation

The boot ROM should be implemented as a block RAM initialized with the assembled code:

```vhdl
-- boot_rom.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity boot_rom is
    port (
        clk     : in  std_logic;
        addr    : in  std_logic_vector(11 downto 0);  -- 4KB ROM
        data    : out longword_t
    );
end boot_rom;

architecture rtl of boot_rom is

    type rom_t is array(0 to 1023) of longword_t;

    -- Initialize ROM with boot code
    -- This would be filled with assembled machine code
    constant ROM : rom_t := (
        0 => x"000017FB",  -- JMP boot_start
        1 => x"00000000",  -- HALT (machine check)
        2 => x"00000000",  -- HALT (kstack invalid)
        3 => x"00000000",  -- HALT (power fail)
        -- ... rest of boot code ...
        others => x"00000000"
    );

begin

    process(clk)
    begin
        if rising_edge(clk) then
            data <= ROM(to_integer(unsigned(addr(11 downto 2))));
        end if;
    end process;

end rtl;
```

## Integration into VAX System

The boot ROM needs to be:

1. **Mapped in Memory Controller**
   - Check if physical address is in ROM range (0x20000000-0x20001FFF)
   - Route reads to ROM instead of DDR
   - ROM is read-only (writes are ignored)

2. **Reset Vector**
   - On reset, CPU's PC is set to 0x20000000
   - PSL is set to kernel mode, interrupts disabled

3. **Building the ROM**
   - Write boot code in VAX assembly
   - Assemble using MACRO-11 or custom assembler
   - Convert to VHDL initialization constant
   - Or load from file during synthesis

## Tools for Boot ROM Development

### Option 1: MACRO-11 Assembler
```bash
# Install MACRO-11 (if available)
macro boot_rom.mac

# Convert to binary
link boot_rom.obj
```

### Option 2: Custom Python Assembler
Create a simple assembler for the subset of instructions you've implemented:

```python
# vax_asm.py - Simple VAX assembler

opcodes = {
    'MOVL': 0xD0,
    'ADDL': 0xC0,
    'HALT': 0x00,
    'JSB': 0x16,
    'RSB': 0x05,
    # ... etc
}

def assemble(source):
    # Parse and emit binary
    pass
```

### Option 3: Direct VHDL
For initial testing, hand-code simple instructions directly in VHDL constant.

## Testing the Boot ROM

1. **Simulation First**
   - Create testbench that starts at 0x20000000
   - Verify PC increments correctly
   - Check that instructions execute

2. **Console Output**
   - First milestone: print banner message
   - Verify UART output in simulation

3. **Incremental Development**
   - Start with minimal boot ROM (just print "Hello")
   - Add disk check
   - Add boot block loading
   - Finally add VMS bootstrap

## VMS Bootstrap Process

Once boot ROM works, VMS bootstrap sequence:

1. **Boot ROM** loads first 512 bytes from disk
2. **Boot Block** (sector 0) loads VMB.EXE
3. **VMB.EXE** (VMS bootstrap) loads SYSINIT
4. **SYSINIT** initializes system and loads VMS kernel
5. **Kernel** starts multi-user operation

## Debugging Boot Issues

Common problems:
- PC not starting at correct address
- Instructions not being fetched
- UART not working (no output)
- Memory access violations
- Disk controller not responding

Use simulation waveforms to debug step-by-step execution.
