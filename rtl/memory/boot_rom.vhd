-- VAX Boot ROM
-- Contains initial boot code and test programs
-- ROM is mapped to address 0x20000000 at reset

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity boot_rom is
    port (
        clk         : in  std_logic;
        addr        : in  virt_addr_t;
        rdata       : out longword_t;
        req         : in  std_logic;
        ack         : out std_logic
    );
end boot_rom;

architecture rtl of boot_rom is

    -- ROM size: 4KB (1024 longwords)
    type rom_t is array(0 to 1023) of byte_t;

    -- Initialize ROM with boot code and test programs
    constant ROM_CONTENTS : rom_t := (
        --=====================================================
        -- Boot ROM Contents
        -- Base Address: 0x20000000
        --=====================================================

        ----------------------------------------------------
        -- Test Program 1: Basic Arithmetic (0x000)
        -- Tests: MOVL, ADDL3, HALT
        ----------------------------------------------------
        -- MOVL #42, R1
        16#000# => x"D0",  -- MOVL opcode
        16#001# => x"8F",  -- Immediate mode
        16#002# => x"2A",  -- 42 (low byte)
        16#003# => x"00",
        16#004# => x"00",
        16#005# => x"00",  -- 42 (high byte)
        16#006# => x"51",  -- R1

        -- MOVL #10, R2
        16#007# => x"D0",  -- MOVL opcode
        16#008# => x"8F",  -- Immediate mode
        16#009# => x"0A",  -- 10
        16#00A# => x"00",
        16#00B# => x"00",
        16#00C# => x"00",
        16#00D# => x"52",  -- R2

        -- ADDL3 R1, R2, R3
        16#00E# => x"C1",  -- ADDL3 opcode
        16#00F# => x"51",  -- R1
        16#010# => x"52",  -- R2
        16#011# => x"53",  -- R3

        -- HALT
        16#012# => x"00",

        ----------------------------------------------------
        -- Test Program 2: Procedure Call (0x100)
        -- Tests: CALLS, RET
        ----------------------------------------------------
        16#100# => x"FB",  -- CALLS
        16#101# => x"00",  -- #0 args
        16#102# => x"AF",  -- Absolute mode
        16#103# => x"20",  -- Address 0x00000120
        16#104# => x"01",
        16#105# => x"00",
        16#106# => x"00",
        16#107# => x"00",  -- HALT

        -- Simple procedure at 0x120
        16#120# => x"00",  -- Entry mask (no registers)
        16#121# => x"00",
        16#122# => x"D0",  -- MOVL #99, R0
        16#123# => x"8F",
        16#124# => x"63",  -- 99
        16#125# => x"00",
        16#126# => x"00",
        16#127# => x"00",
        16#128# => x"50",  -- R0
        16#129# => x"04",  -- RET

        ----------------------------------------------------
        -- Test Program 3: Exception Test (0x200)
        -- Tests: Reserved instruction exception, REI
        ----------------------------------------------------
        -- Set up SCB first (manually initialize)
        -- Then execute invalid opcode

        16#200# => x"FF",  -- Reserved instruction
        16#201# => x"00",  -- HALT

        ----------------------------------------------------
        -- Exception Handler (0x300)
        -- Used by exception tests
        ----------------------------------------------------
        16#300# => x"D0",  -- MOVL #255, R0 (mark exception occurred)
        16#301# => x"8F",
        16#302# => x"FF",
        16#303# => x"00",
        16#304# => x"00",
        16#305# => x"00",
        16#306# => x"50",  -- R0
        16#307# => x"02",  -- REI

        ----------------------------------------------------
        -- Test Program 4: Stack Operations (0x400)
        -- Tests: PUSHL, POPL (when implemented)
        ----------------------------------------------------
        16#400# => x"DD",  -- PUSHL #100
        16#401# => x"64",
        16#402# => x"DD",  -- PUSHL #200
        16#403# => x"C8",  -- Extended literal
        16#404# => x"C8",
        16#405# => x"00",
        16#406# => x"00",
        16#407# => x"00",
        16#408# => x"00",  -- HALT

        ----------------------------------------------------
        -- Test Program 5: Branches (0x500)
        -- Tests: BRB, BEQL, BNEQ
        ----------------------------------------------------
        -- Set R0 = 0
        16#500# => x"D0",  -- MOVL #0, R0
        16#501# => x"00",  -- Literal 0
        16#502# => x"50",  -- R0

        -- CMPL R0, #0
        16#503# => x"D1",  -- CMPL
        16#504# => x"50",  -- R0
        16#505# => x"00",  -- #0

        -- BEQL forward
        16#506# => x"13",  -- BEQL
        16#507# => x"03",  -- +3 bytes

        -- Should skip
        16#508# => x"00",  -- HALT (skipped)

        -- Target
        16#509# => x"D0",  -- MOVL #55, R0
        16#50A# => x"37",  -- #55
        16#50B# => x"50",  -- R0
        16#50C# => x"00",  -- HALT

        ----------------------------------------------------
        -- Boot Entry Point (0x000)
        -- This is where CPU starts at reset
        -- Already contains Test Program 1
        ----------------------------------------------------

        -- Default: fill rest with HALTs
        others => x"00"
    );

    signal rom_data : rom_t := ROM_CONTENTS;

begin

    process(clk)
        variable addr_int : integer;
        variable offset : integer;
    begin
        if rising_edge(clk) then
            ack <= '0';

            if req = '1' then
                -- Convert address to ROM offset
                -- ROM is at 0x20000000, size 4KB
                addr_int := to_integer(unsigned(addr));
                offset := (addr_int mod 4096) / 4;  -- Longword offset

                -- Read longword from ROM
                if offset < 1024 then
                    rdata <= rom_data(offset*4 + 3) &
                             rom_data(offset*4 + 2) &
                             rom_data(offset*4 + 1) &
                             rom_data(offset*4);
                    ack <= '1';
                else
                    rdata <= x"00000000";
                    ack <= '1';
                end if;
            end if;
        end if;
    end process;

end rtl;
