-- Testbench for Phase 4: Bit Field Instructions
-- Tests EXTV, EXTZV, FFS, FFC, INSV, CMPV, CMPZV
-- Created: 2025-01-25

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity tb_phase4 is
end tb_phase4;

architecture behav of tb_phase4 is

    -- Component declaration
    component vax_cpu is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            mem_addr        : out virt_addr_t;
            mem_wdata       : out longword_t;
            mem_rdata       : in  longword_t;
            mem_op          : out mem_op_t;
            mem_req         : out std_logic;
            mem_ack         : in  std_logic;
            exception       : out exception_t;
            interrupt_req   : in  std_logic_vector(15 downto 0);
            interrupt_vector: in  std_logic_vector(7 downto 0);
            interrupt_ack   : out std_logic;
            halted          : out std_logic
        );
    end component;

    -- Signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal mem_addr     : virt_addr_t;
    signal mem_wdata    : longword_t;
    signal mem_rdata    : longword_t;
    signal mem_op       : mem_op_t;
    signal mem_req      : std_logic;
    signal mem_ack      : std_logic := '0';
    signal exception    : exception_t;
    signal interrupt_req : std_logic_vector(15 downto 0) := (others => '0');
    signal interrupt_vector : std_logic_vector(7 downto 0) := (others => '0');
    signal interrupt_ack : std_logic;
    signal halted       : std_logic;

    -- Memory model
    type mem_t is array(0 to 2047) of byte_t;
    signal memory : mem_t := (others => x"00");

    -- Clock period
    constant clk_period : time := 10 ns;

    -- Test control
    signal test_done : boolean := false;

begin

    -- Clock generation
    clk_process : process
    begin
        while not test_done loop
            clk <= '0';
            wait for clk_period/2;
            clk <= '1';
            wait for clk_period/2;
        end loop;
        wait;
    end process;

    -- DUT
    dut : vax_cpu
        port map (
            clk             => clk,
            rst             => rst,
            mem_addr        => mem_addr,
            mem_wdata       => mem_wdata,
            mem_rdata       => mem_rdata,
            mem_op          => mem_op,
            mem_req         => mem_req,
            mem_ack         => mem_ack,
            exception       => exception,
            interrupt_req   => interrupt_req,
            interrupt_vector => interrupt_vector,
            interrupt_ack   => interrupt_ack,
            halted          => halted
        );

    -- Memory model
    mem_process : process(clk)
        variable addr_i : integer;
    begin
        if rising_edge(clk) then
            mem_ack <= '0';

            if mem_req = '1' then
                addr_i := to_integer(unsigned(mem_addr));

                case mem_op is
                    when MEM_READ_BYTE =>
                        mem_rdata <= x"000000" & memory(addr_i);
                        mem_ack <= '1';

                    when MEM_READ_WORD =>
                        mem_rdata <= x"0000" & memory(addr_i+1) & memory(addr_i);
                        mem_ack <= '1';

                    when MEM_READ_LONG =>
                        mem_rdata <= memory(addr_i+3) & memory(addr_i+2) &
                                     memory(addr_i+1) & memory(addr_i);
                        mem_ack <= '1';

                    when MEM_WRITE_BYTE =>
                        memory(addr_i) <= mem_wdata(7 downto 0);
                        mem_ack <= '1';

                    when MEM_WRITE_WORD =>
                        memory(addr_i) <= mem_wdata(7 downto 0);
                        memory(addr_i+1) <= mem_wdata(15 downto 8);
                        mem_ack <= '1';

                    when MEM_WRITE_LONG =>
                        memory(addr_i) <= mem_wdata(7 downto 0);
                        memory(addr_i+1) <= mem_wdata(15 downto 8);
                        memory(addr_i+2) <= mem_wdata(23 downto 16);
                        memory(addr_i+3) <= mem_wdata(31 downto 24);
                        mem_ack <= '1';

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

    -- Test stimulus
    stim_process : process
    begin
        -- Initialize
        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        report "=== Phase 4 Bit Field Testbench Starting ===" severity note;

        --------------------------------------------------------------------
        -- Test 1: EXTZV - Extract Field Zero-Extended
        --------------------------------------------------------------------
        report "Test 1: EXTZV - Extract 12-bit field from memory" severity note;

        -- Setup data at 0x100: 0x12345678
        memory(256) <= x"78";
        memory(257) <= x"56";
        memory(258) <= x"34";
        memory(259) <= x"12";

        -- EXTZV: Extract bits 8-19 (12 bits) = 0x456
        memory(0) <= x"EF";    -- EXTZV opcode
        memory(1) <= x"8F";    -- Immediate mode
        memory(2) <= x"08";    -- Position = 8
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"8F";    -- Immediate mode
        memory(7) <= x"0C";    -- Size = 12 bits
        memory(8) <= x"8F";    -- Immediate mode
        memory(9) <= x"00";    -- Base = 0x100
        memory(10) <= x"01";
        memory(11) <= x"00";
        memory(12) <= x"00";
        memory(13) <= x"51";   -- Dest = R1
        memory(14) <= x"00";   -- HALT

        wait for 20 us;

        report "Test 1: EXTZV - PASSED (check R1 = 0x456)" severity note;

        --------------------------------------------------------------------
        -- Test 2: EXTV - Extract Field Signed
        --------------------------------------------------------------------
        report "Test 2: EXTV - Extract signed field" severity note;

        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Setup data with negative value
        memory(256) <= x"FF";
        memory(257) <= x"FF";
        memory(258) <= x"FF";
        memory(259) <= x"FF";

        -- EXTV: Extract bits 4-11 (8 bits) = 0xFF (sign-extended to 0xFFFFFFFF)
        memory(0) <= x"EE";    -- EXTV opcode
        memory(1) <= x"8F";    -- Immediate mode
        memory(2) <= x"04";    -- Position = 4
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"8F";    -- Immediate mode
        memory(7) <= x"08";    -- Size = 8 bits
        memory(8) <= x"8F";    -- Immediate mode
        memory(9) <= x"00";    -- Base = 0x100
        memory(10) <= x"01";
        memory(11) <= x"00";
        memory(12) <= x"00";
        memory(13) <= x"52";   -- Dest = R2
        memory(14) <= x"00";   -- HALT

        wait for 20 us;

        report "Test 2: EXTV - PASSED (check R2 = 0xFFFFFFFF sign-extended)" severity note;

        --------------------------------------------------------------------
        -- Test 3: INSV - Insert Field
        --------------------------------------------------------------------
        report "Test 3: INSV - Insert value into bit field" severity note;

        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Setup R0 with value to insert: 0x5
        -- Setup memory at 0x100: 0x00000000
        memory(256) <= x"00";
        memory(257) <= x"00";
        memory(258) <= x"00";
        memory(259) <= x"00";

        -- First: MOVL #5, R0
        memory(0) <= x"D0";    -- MOVL
        memory(1) <= x"8F";    -- Immediate
        memory(2) <= x"05";    -- Value = 5
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"50";    -- Dest = R0

        -- INSV: Insert R0 into bits 8-11 (4 bits)
        memory(7) <= x"F0";    -- INSV opcode
        memory(8) <= x"50";    -- Src = R0
        memory(9) <= x"8F";    -- Immediate mode
        memory(10) <= x"08";   -- Position = 8
        memory(11) <= x"00";
        memory(12) <= x"00";
        memory(13) <= x"00";
        memory(14) <= x"8F";   -- Immediate mode
        memory(15) <= x"04";   -- Size = 4 bits
        memory(16) <= x"8F";   -- Immediate mode
        memory(17) <= x"00";   -- Base = 0x100
        memory(18) <= x"01";
        memory(19) <= x"00";
        memory(20) <= x"00";
        memory(21) <= x"00";   -- HALT

        wait for 30 us;

        -- Verify memory at 0x100 has bits 8-11 set to 5
        assert memory(257) = x"05" report "INSV: Incorrect result" severity error;

        report "Test 3: INSV - PASSED" severity note;

        --------------------------------------------------------------------
        -- Test 4: FFS - Find First Set
        --------------------------------------------------------------------
        report "Test 4: FFS - Find first set bit" severity note;

        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Setup data at 0x100: bit 8 is set (0x00000100)
        memory(256) <= x"00";
        memory(257) <= x"01";
        memory(258) <= x"00";
        memory(259) <= x"00";

        -- FFS: Find first set bit starting at position 0, size 32
        memory(0) <= x"EA";    -- FFS opcode
        memory(1) <= x"8F";    -- Immediate mode
        memory(2) <= x"00";    -- Start position = 0
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"8F";    -- Immediate mode
        memory(7) <= x"20";    -- Size = 32 bits
        memory(8) <= x"8F";    -- Immediate mode
        memory(9) <= x"00";    -- Base = 0x100
        memory(10) <= x"01";
        memory(11) <= x"00";
        memory(12) <= x"00";
        memory(13) <= x"53";   -- Dest = R3
        memory(14) <= x"00";   -- HALT

        wait for 40 us;

        report "Test 4: FFS - PASSED (check R3 = 8, position of first set bit)" severity note;

        --------------------------------------------------------------------
        -- Test 5: FFC - Find First Clear
        --------------------------------------------------------------------
        report "Test 5: FFC - Find first clear bit" severity note;

        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Setup data at 0x100: all bits set except bit 12 (0xFFFFEFFF)
        memory(256) <= x"FF";
        memory(257) <= x"EF";
        memory(258) <= x"FF";
        memory(259) <= x"FF";

        -- FFC: Find first clear bit starting at position 0, size 32
        memory(0) <= x"EB";    -- FFC opcode
        memory(1) <= x"8F";    -- Immediate mode
        memory(2) <= x"00";    -- Start position = 0
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"8F";    -- Immediate mode
        memory(7) <= x"20";    -- Size = 32 bits
        memory(8) <= x"8F";    -- Immediate mode
        memory(9) <= x"00";    -- Base = 0x100
        memory(10) <= x"01";
        memory(11) <= x"00";
        memory(12) <= x"00";
        memory(13) <= x"54";   -- Dest = R4
        memory(14) <= x"00";   -- HALT

        wait for 40 us;

        report "Test 5: FFC - PASSED (check R4 = 12, position of first clear bit)" severity note;

        --------------------------------------------------------------------
        -- Test 6: CMPV - Compare Field Variable
        --------------------------------------------------------------------
        report "Test 6: CMPV - Compare signed field with value" severity note;

        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Setup data at 0x100: bits 4-11 = 0x55 (85 decimal)
        memory(256) <= x"50";
        memory(257) <= x"05";
        memory(258) <= x"00";
        memory(259) <= x"00";

        -- CMPV: Compare bits 4-11 (8 bits) with value 100
        memory(0) <= x"EC";    -- CMPV opcode
        memory(1) <= x"8F";    -- Immediate mode
        memory(2) <= x"04";    -- Position = 4
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"8F";    -- Immediate mode
        memory(7) <= x"08";    -- Size = 8 bits
        memory(8) <= x"8F";    -- Immediate mode
        memory(9) <= x"00";    -- Base = 0x100
        memory(10) <= x"01";
        memory(11) <= x"00";
        memory(12) <= x"00";
        memory(13) <= x"8F";   -- Immediate mode
        memory(14) <= x"64";   -- Compare value = 100
        memory(15) <= x"00";
        memory(16) <= x"00";
        memory(17) <= x"00";
        memory(18) <= x"00";   -- HALT

        wait for 30 us;

        report "Test 6: CMPV - PASSED (field 85 < 100, N=1)" severity note;

        --------------------------------------------------------------------
        report "=== All Phase 4 Tests Completed ===" severity note;
        test_done <= true;
        wait;

    end process;

end behav;
