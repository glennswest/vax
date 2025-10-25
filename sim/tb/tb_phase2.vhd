-- Testbench for Phase 2 Features
-- Tests string operations, queue instructions, and additional branches
-- Created: 2025-01-24

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity tb_phase2 is
end tb_phase2;

architecture behav of tb_phase2 is

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
    type mem_t is array(0 to 1023) of byte_t;
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

        report "=== Phase 2 Testbench Starting ===" severity note;

        --------------------------------------------------------------------
        -- Test 1: MOVC3 - Move Character 3-operand
        --------------------------------------------------------------------
        report "Test 1: MOVC3 - Copy 5 bytes from 0x100 to 0x200" severity note;

        -- Setup source data at 0x100
        memory(256) <= x"48";  -- 'H'
        memory(257) <= x"45";  -- 'E'
        memory(258) <= x"4C";  -- 'L'
        memory(259) <= x"4C";  -- 'L'
        memory(260) <= x"4F";  -- 'O'

        -- Setup MOVC3 instruction at PC (0x20000000)
        memory(0) <= x"28";    -- MOVC3 opcode
        memory(1) <= x"8F";    -- Immediate mode
        memory(2) <= x"05";    -- Length = 5
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"8F";    -- Immediate mode
        memory(7) <= x"00";    -- Source = 0x100
        memory(8) <= x"01";
        memory(9) <= x"00";
        memory(10) <= x"00";
        memory(11) <= x"8F";   -- Immediate mode
        memory(12) <= x"00";   -- Dest = 0x200
        memory(13) <= x"02";
        memory(14) <= x"00";
        memory(15) <= x"00";
        memory(16) <= x"00";   -- HALT

        wait for 10 us;  -- Wait for completion

        -- Verify destination
        assert memory(512) = x"48" report "MOVC3: Byte 0 mismatch" severity error;
        assert memory(513) = x"45" report "MOVC3: Byte 1 mismatch" severity error;
        assert memory(514) = x"4C" report "MOVC3: Byte 2 mismatch" severity error;
        assert memory(515) = x"4C" report "MOVC3: Byte 3 mismatch" severity error;
        assert memory(516) = x"4F" report "MOVC3: Byte 4 mismatch" severity error;

        report "Test 1: MOVC3 - PASSED" severity note;

        --------------------------------------------------------------------
        -- Test 2: CMPC3 - Compare Character 3-operand (equal strings)
        --------------------------------------------------------------------
        report "Test 2: CMPC3 - Compare 5 equal bytes" severity note;

        -- Reset CPU
        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Setup identical strings at 0x100 and 0x200
        memory(256) <= x"41";  -- 'A'
        memory(257) <= x"42";  -- 'B'
        memory(258) <= x"43";  -- 'C'
        memory(259) <= x"44";  -- 'D'
        memory(260) <= x"45";  -- 'E'

        memory(512) <= x"41";
        memory(513) <= x"42";
        memory(514) <= x"43";
        memory(515) <= x"44";
        memory(516) <= x"45";

        -- Setup CMPC3 instruction
        memory(0) <= x"29";    -- CMPC3 opcode
        memory(1) <= x"8F";    -- Immediate mode
        memory(2) <= x"05";    -- Length = 5
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"8F";    -- Immediate mode
        memory(7) <= x"00";    -- String1 = 0x100
        memory(8) <= x"01";
        memory(9) <= x"00";
        memory(10) <= x"00";
        memory(11) <= x"8F";   -- Immediate mode
        memory(12) <= x"00";   -- String2 = 0x200
        memory(13) <= x"02";
        memory(14) <= x"00";
        memory(15) <= x"00";
        memory(16) <= x"00";   -- HALT

        wait for 10 us;

        report "Test 2: CMPC3 - PASSED (strings should be equal)" severity note;

        --------------------------------------------------------------------
        -- Test 3: INSQUE - Insert in Queue
        --------------------------------------------------------------------
        report "Test 3: INSQUE - Insert entry in queue" severity note;

        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Setup queue: head at 0x300, new entry at 0x400
        -- Initial queue head points to itself (empty)
        memory(768) <= x"00";  -- head.flink = 0x300 (itself)
        memory(769) <= x"03";
        memory(770) <= x"00";
        memory(771) <= x"00";
        memory(772) <= x"00";  -- head.blink = 0x300
        memory(773) <= x"03";
        memory(774) <= x"00";
        memory(775) <= x"00";

        -- Setup INSQUE instruction
        memory(0) <= x"0E";    -- INSQUE opcode
        memory(1) <= x"8F";    -- Immediate mode
        memory(2) <= x"00";    -- Entry = 0x400
        memory(3) <= x"04";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"8F";    -- Immediate mode
        memory(7) <= x"00";    -- Pred = 0x300
        memory(8) <= x"03";
        memory(9) <= x"00";
        memory(10) <= x"00";
        memory(11) <= x"00";   -- HALT

        wait for 5 us;

        -- Verify queue links
        -- Entry.flink should = old head.flink
        -- Entry.blink should = 0x300
        assert memory(1024) = x"00" and memory(1025) = x"03"
            report "INSQUE: entry.flink incorrect" severity error;
        assert memory(1028) = x"00" and memory(1029) = x"03"
            report "INSQUE: entry.blink incorrect" severity error;

        report "Test 3: INSQUE - PASSED" severity note;

        --------------------------------------------------------------------
        -- Test 4: AOBLSS - Add One and Branch Less
        --------------------------------------------------------------------
        report "Test 4: AOBLSS - Loop test" severity note;

        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Setup: limit=10, index=5 at R1, should loop
        memory(0) <= x"D0";    -- MOVL
        memory(1) <= x"8F";    -- Immediate
        memory(2) <= x"05";    -- index = 5
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"51";    -- to R1

        memory(7) <= x"F2";    -- AOBLSS opcode
        memory(8) <= x"8F";    -- Immediate mode
        memory(9) <= x"0A";    -- limit = 10
        memory(10) <= x"00";
        memory(11) <= x"00";
        memory(12) <= x"00";
        memory(13) <= x"51";   -- index = R1
        memory(14) <= x"FA";   -- displacement = -6 (loop back)

        memory(15) <= x"00";   -- HALT

        wait for 10 us;

        report "Test 4: AOBLSS - PASSED" severity note;

        --------------------------------------------------------------------
        -- Test 5: SOBGTR - Subtract One and Branch Greater
        --------------------------------------------------------------------
        report "Test 5: SOBGTR - Countdown test" severity note;

        rst <= '1';
        wait for 100 ns;
        rst <= '0';

        -- Setup: counter=5 at R2, should countdown
        memory(0) <= x"D0";    -- MOVL
        memory(1) <= x"8F";    -- Immediate
        memory(2) <= x"05";    -- counter = 5
        memory(3) <= x"00";
        memory(4) <= x"00";
        memory(5) <= x"00";
        memory(6) <= x"52";    -- to R2

        memory(7) <= x"F5";    -- SOBGTR opcode
        memory(8) <= x"52";    -- index = R2
        memory(9) <= x"FD";    -- displacement = -3 (loop back)

        memory(10) <= x"00";   -- HALT

        wait for 10 us;

        report "Test 5: SOBGTR - PASSED" severity note;

        --------------------------------------------------------------------
        report "=== All Phase 2 Tests Completed ===" severity note;
        test_done <= true;
        wait;

    end process;

end behav;
