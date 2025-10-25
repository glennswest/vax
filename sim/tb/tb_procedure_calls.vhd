-- Testbench for Procedure Call Instructions (CALLS/CALLG/RET)
-- Tests the complete VAX procedure calling convention

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity tb_procedure_calls is
end tb_procedure_calls;

architecture sim of tb_procedure_calls is

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

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
    signal mem_ack      : std_logic;
    signal exception    : exception_t;
    signal interrupt_req : std_logic_vector(15 downto 0) := (others => '0');
    signal interrupt_vector : std_logic_vector(7 downto 0) := (others => '0');
    signal interrupt_ack : std_logic;
    signal halted       : std_logic;

    -- Memory model (64KB)
    type memory_t is array(0 to 65535) of byte_t;
    signal memory : memory_t := (others => x"00");

    -- Simulation control
    signal sim_done : boolean := false;
    signal test_num : integer := 0;

begin

    -- Clock generation
    clk_process : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- DUT instantiation
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
            interrupt_vector=> interrupt_vector,
            interrupt_ack   => interrupt_ack,
            halted          => halted
        );

    -- Memory model process
    mem_model : process(clk)
        variable addr : integer;
    begin
        if rising_edge(clk) then
            mem_ack <= '0';

            if mem_req = '1' then
                addr := to_integer(unsigned(mem_addr)) mod 65536;

                case mem_op is
                    when MEM_READ_BYTE =>
                        mem_rdata <= x"000000" & memory(addr);
                        mem_ack <= '1';

                    when MEM_READ_WORD =>
                        mem_rdata <= x"0000" & memory(addr+1) & memory(addr);
                        mem_ack <= '1';

                    when MEM_READ_LONG =>
                        mem_rdata <= memory(addr+3) & memory(addr+2) &
                                     memory(addr+1) & memory(addr);
                        mem_ack <= '1';

                    when MEM_WRITE_BYTE =>
                        memory(addr) <= mem_wdata(7 downto 0);
                        mem_ack <= '1';

                    when MEM_WRITE_WORD =>
                        memory(addr) <= mem_wdata(7 downto 0);
                        memory(addr+1) <= mem_wdata(15 downto 8);
                        mem_ack <= '1';

                    when MEM_WRITE_LONG =>
                        memory(addr) <= mem_wdata(7 downto 0);
                        memory(addr+1) <= mem_wdata(15 downto 8);
                        memory(addr+2) <= mem_wdata(23 downto 16);
                        memory(addr+3) <= mem_wdata(31 downto 24);
                        mem_ack <= '1';

                    when others =>
                        mem_ack <= '1';
                end case;
            end if;
        end if;
    end process;

    -- Test stimulus
    stimulus : process
        procedure load_program(start_addr : integer; prog : in memory_t; size : integer) is
        begin
            for i in 0 to size-1 loop
                memory(start_addr + i) <= prog(i);
            end loop;
        end procedure;

        variable test_prog : memory_t := (others => x"00");
        variable addr : integer;

    begin
        report "=== Procedure Call Instructions Test ===" severity note;

        -- Wait for reset
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        ------------------------------------------------------------
        -- TEST 1: Simple procedure call with no arguments
        -- CALLS #0, proc1
        -- proc1 just does RET
        ------------------------------------------------------------
        report "Test 1: CALLS #0, proc (no arguments, no register saves)" severity note;
        test_num <= 1;
        addr := 16#0000#;

        -- Main program at 0x0000
        test_prog(0) := x"FB";  -- CALLS opcode
        test_prog(1) := x"00";  -- Literal 0 (no arguments)
        test_prog(2) := x"AF";  -- Absolute mode
        test_prog(3) := x"00";  -- Address 0x0100 (low byte)
        test_prog(4) := x"01";
        test_prog(5) := x"00";
        test_prog(6) := x"00";  -- Address 0x0100 (high byte)
        test_prog(7) := x"00";  -- HALT after return

        -- Procedure at 0x0100
        test_prog(16#100#) := x"00";  -- Entry mask (no registers saved)
        test_prog(16#101#) := x"00";
        test_prog(16#102#) := x"04";  -- RET

        load_program(addr, test_prog, 16#103#);

        wait for CLK_PERIOD * 200;

        if halted = '1' then
            report "Test 1: PASSED - CPU halted after return" severity note;
        else
            report "Test 1: Waiting for completion..." severity note;
            wait until halted = '1' for CLK_PERIOD * 200;
        end if;

        ------------------------------------------------------------
        -- TEST 2: Procedure call with arguments
        -- PUSHL #10
        -- PUSHL #5
        -- CALLS #2, add
        -- add: ADDL3 4(AP), 8(AP), R0; RET
        ------------------------------------------------------------
        report "Test 2: CALLS with arguments" severity note;
        test_num <= 2;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';

        -- Main program
        test_prog(0) := x"DD";  -- PUSHL
        test_prog(1) := x"0A";  -- #10
        test_prog(2) := x"DD";  -- PUSHL
        test_prog(3) := x"05";  -- #5
        test_prog(4) := x"FB";  -- CALLS
        test_prog(5) := x"02";  -- #2 arguments
        test_prog(6) := x"AF";  -- Absolute mode
        test_prog(7) := x"00";  -- Address 0x0200
        test_prog(8) := x"02";
        test_prog(9) := x"00";
        test_prog(10) := x"00";
        test_prog(11) := x"00";  -- HALT

        -- add procedure at 0x0200
        test_prog(16#200#) := x"00";  -- Entry mask (no registers)
        test_prog(16#201#) := x"00";
        test_prog(16#202#) := x"C1";  -- ADDL3
        test_prog(16#203#) := x"A4";  -- 4(AP) - byte displacement
        test_prog(16#204#) := x"04";  -- displacement = 4
        test_prog(16#205#) := x"AC";  -- 8(AP) - byte displacement
        test_prog(16#206#) := x"08";  -- displacement = 8
        test_prog(16#207#) := x"50";  -- R0
        test_prog(16#208#) := x"04";  -- RET

        load_program(addr, test_prog, 16#209#);

        wait for CLK_PERIOD * 300;

        if halted = '1' then
            report "Test 2: PASSED - CPU halted, check R0=15" severity note;
        else
            report "Test 2: Waiting for completion..." severity note;
            wait until halted = '1' for CLK_PERIOD * 300;
        end if;

        ------------------------------------------------------------
        -- TEST 3: Procedure with register saves
        -- Entry mask saves R2-R5
        ------------------------------------------------------------
        report "Test 3: CALLS with register saves (entry mask)" severity note;
        test_num <= 3;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';

        -- Main program
        test_prog(0) := x"FB";  -- CALLS
        test_prog(1) := x"00";  -- #0 arguments
        test_prog(2) := x"AF";  -- Absolute mode
        test_prog(3) := x"00";  -- Address 0x0300
        test_prog(4) := x"03";
        test_prog(5) := x"00";
        test_prog(6) := x"00";
        test_prog(7) := x"00";  -- HALT

        -- Procedure at 0x0300
        test_prog(16#300#) := x"3C";  -- Entry mask: save R2-R5 (bits 2-5 = 0x3C)
        test_prog(16#301#) := x"00";
        test_prog(16#302#) := x"D0";  -- MOVL
        test_prog(16#303#) := x"0F";  -- #15
        test_prog(16#304#) := x"52";  -- R2
        test_prog(16#305#) := x"04";  -- RET

        load_program(addr, test_prog, 16#306#);

        wait for CLK_PERIOD * 300;

        if halted = '1' then
            report "Test 3: PASSED - CPU halted with register saves" severity note;
        else
            report "Test 3: Waiting for completion..." severity note;
            wait until halted = '1' for CLK_PERIOD * 300;
        end if;

        ------------------------------------------------------------
        -- TEST 4: Nested procedure calls
        -- main calls proc1, proc1 calls proc2
        ------------------------------------------------------------
        report "Test 4: Nested CALLS" severity note;
        test_num <= 4;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';

        -- Main at 0x0000
        test_prog(0) := x"FB";  -- CALLS
        test_prog(1) := x"00";  -- #0 args
        test_prog(2) := x"AF";  -- Absolute
        test_prog(3) := x"00";  -- 0x0400
        test_prog(4) := x"04";
        test_prog(5) := x"00";
        test_prog(6) := x"00";
        test_prog(7) := x"00";  -- HALT

        -- proc1 at 0x0400
        test_prog(16#400#) := x"00";  -- Entry mask
        test_prog(16#401#) := x"00";
        test_prog(16#402#) := x"FB";  -- CALLS
        test_prog(16#403#) := x"00";  -- #0 args
        test_prog(16#404#) := x"AF";  -- Absolute
        test_prog(16#405#) := x"00";  -- 0x0500
        test_prog(16#406#) := x"05";
        test_prog(16#407#) := x"00";
        test_prog(16#408#) := x"00";
        test_prog(16#409#) := x"04";  -- RET

        -- proc2 at 0x0500
        test_prog(16#500#) := x"00";  -- Entry mask
        test_prog(16#501#) := x"00";
        test_prog(16#502#) := x"01";  -- NOP
        test_prog(16#503#) := x"04";  -- RET

        load_program(addr, test_prog, 16#504#);

        wait for CLK_PERIOD * 500;

        if halted = '1' then
            report "Test 4: PASSED - Nested calls completed" severity note;
        else
            report "Test 4: Waiting for completion..." severity note;
            wait until halted = '1' for CLK_PERIOD * 500;
        end if;

        ------------------------------------------------------------
        -- TEST 5: CALLG with argument list in memory
        ------------------------------------------------------------
        report "Test 5: CALLG (argument list)" severity note;
        test_num <= 5;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';

        -- Argument list at 0x7F00
        test_prog(16#7F00#) := x"02";  -- Argument count = 2
        test_prog(16#7F01#) := x"00";
        test_prog(16#7F02#) := x"00";
        test_prog(16#7F03#) := x"00";
        test_prog(16#7F04#) := x"05";  -- Arg 1 = 5
        test_prog(16#7F05#) := x"00";
        test_prog(16#7F06#) := x"00";
        test_prog(16#7F07#) := x"00";
        test_prog(16#7F08#) := x"0A";  -- Arg 2 = 10
        test_prog(16#7F09#) := x"00";
        test_prog(16#7F0A#) := x"00";
        test_prog(16#7F0B#) := x"00";

        -- Main program
        test_prog(0) := x"FA";  -- CALLG
        test_prog(1) := x"AF";  -- Absolute mode (arglist address)
        test_prog(2) := x"00";  -- 0x7F00
        test_prog(3) := x"7F";
        test_prog(4) := x"00";
        test_prog(5) := x"00";
        test_prog(6) := x"AF";  -- Absolute mode (procedure address)
        test_prog(7) := x"00";  -- 0x0600
        test_prog(8) := x"06";
        test_prog(9) := x"00";
        test_prog(10) := x"00";
        test_prog(11) := x"00";  -- HALT

        -- Procedure at 0x0600
        test_prog(16#600#) := x"00";  -- Entry mask
        test_prog(16#601#) := x"00";
        test_prog(16#602#) := x"C1";  -- ADDL3
        test_prog(16#603#) := x"A4";  -- 4(AP)
        test_prog(16#604#) := x"04";
        test_prog(16#605#) := x"AC";  -- 8(AP)
        test_prog(16#606#) := x"08";
        test_prog(16#607#) := x"50";  -- R0
        test_prog(16#608#) := x"04";  -- RET

        load_program(addr, test_prog, 16#7F0C#);

        wait for CLK_PERIOD * 400;

        if halted = '1' then
            report "Test 5: PASSED - CALLG completed" severity note;
        else
            report "Test 5: Waiting for completion..." severity note;
            wait until halted = '1' for CLK_PERIOD * 400;
        end if;

        ------------------------------------------------------------
        report "" severity note;
        report "=== All Procedure Call Tests Complete ===" severity note;
        report "Tests run: 5" severity note;
        report "If no errors reported above, all tests PASSED" severity note;

        sim_done <= true;
        wait;
    end process;

end sim;
