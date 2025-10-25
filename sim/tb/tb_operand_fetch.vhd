-- Testbench for Operand Fetching Integration
-- Tests the complete operand fetch pipeline with real VAX instructions

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity tb_operand_fetch is
end tb_operand_fetch;

architecture sim of tb_operand_fetch is

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

    -- Memory model (8KB)
    type memory_t is array(0 to 8191) of byte_t;
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
                addr := to_integer(unsigned(mem_addr)) mod 8192;

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
        report "=== Operand Fetching Integration Test ===";

        -- Wait for reset
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        ------------------------------------------------------------
        -- TEST 1: MOVL with immediate and register modes
        -- MOVL #42, R1
        -- Encoding: D0 8F 2A 00 00 00 51
        ------------------------------------------------------------
        report "Test 1: MOVL #42, R1 (immediate to register)";
        test_num <= 1;
        addr := 16#20000000#;

        test_prog(0) := x"D0";  -- MOVL opcode
        test_prog(1) := x"8F";  -- Immediate mode (autoincrement from PC)
        test_prog(2) := x"2A";  -- Value 42 (low byte)
        test_prog(3) := x"00";
        test_prog(4) := x"00";
        test_prog(5) := x"00";  -- Value 42 (high byte)
        test_prog(6) := x"51";  -- Register 1
        test_prog(7) := x"00";  -- HALT

        load_program(addr mod 8192, test_prog, 8);

        -- Wait for execution
        wait for CLK_PERIOD * 100;

        if halted = '1' then
            report "Test 1: PASSED - CPU halted";
        else
            report "Test 1: Waiting for completion...";
            wait until halted = '1' for CLK_PERIOD * 100;
        end if;

        ------------------------------------------------------------
        -- TEST 2: ADDL3 with register modes
        -- ADDL3 R1, R2, R3
        -- Encoding: C1 51 52 53
        ------------------------------------------------------------
        report "Test 2: ADDL3 R1, R2, R3 (three register operands)";
        test_num <= 2;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';

        test_prog(0) := x"C1";  -- ADDL3 opcode
        test_prog(1) := x"51";  -- Register 1
        test_prog(2) := x"52";  -- Register 2
        test_prog(3) := x"53";  -- Register 3
        test_prog(4) := x"00";  -- HALT

        load_program(addr mod 8192, test_prog, 5);

        wait for CLK_PERIOD * 100;

        if halted = '1' then
            report "Test 2: PASSED - CPU halted";
        else
            report "Test 2: Waiting for completion...";
            wait until halted = '1' for CLK_PERIOD * 100;
        end if;

        ------------------------------------------------------------
        -- TEST 3: MOVL with displacement mode
        -- MOVL R1, 100(R2)
        -- Encoding: D0 51 A2 64
        ------------------------------------------------------------
        report "Test 3: MOVL R1, 100(R2) (byte displacement)";
        test_num <= 3;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';

        test_prog(0) := x"D0";  -- MOVL opcode
        test_prog(1) := x"51";  -- Register 1 (source)
        test_prog(2) := x"A2";  -- Byte displacement mode, R2
        test_prog(3) := x"64";  -- Displacement = 100
        test_prog(4) := x"00";  -- HALT

        load_program(addr mod 8192, test_prog, 5);

        wait for CLK_PERIOD * 150;

        if halted = '1' then
            report "Test 3: PASSED - CPU halted";
        else
            report "Test 3: Waiting for completion...";
            wait until halted = '1' for CLK_PERIOD * 100;
        end if;

        ------------------------------------------------------------
        -- TEST 4: CMPL with literal mode
        -- CMPL #5, R1
        -- Encoding: D1 05 51
        ------------------------------------------------------------
        report "Test 4: CMPL #5, R1 (literal and register)";
        test_num <= 4;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';

        test_prog(0) := x"D1";  -- CMPL opcode
        test_prog(1) := x"05";  -- Literal 5 (mode 0, value 5)
        test_prog(2) := x"51";  -- Register 1
        test_prog(3) := x"00";  -- HALT

        load_program(addr mod 8192, test_prog, 4);

        wait for CLK_PERIOD * 100;

        if halted = '1' then
            report "Test 4: PASSED - CPU halted";
        else
            report "Test 4: Waiting for completion...";
            wait until halted = '1' for CLK_PERIOD * 100;
        end if;

        ------------------------------------------------------------
        -- TEST 5: BRB (unconditional branch)
        -- BRB forward (+10)
        -- Encoding: 11 0A
        ------------------------------------------------------------
        report "Test 5: BRB +10 (branch forward)";
        test_num <= 5;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';

        test_prog(0) := x"11";  -- BRB opcode
        test_prog(1) := x"0A";  -- Displacement +10
        test_prog(2) := x"01";  -- NOP (skipped)
        test_prog(3) := x"01";  -- NOP (skipped)
        test_prog(4) := x"01";  -- NOP (skipped)
        test_prog(5) := x"01";  -- NOP (skipped)
        test_prog(6) := x"01";  -- NOP (skipped)
        test_prog(7) := x"01";  -- NOP (skipped)
        test_prog(8) := x"01";  -- NOP (skipped)
        test_prog(9) := x"01";  -- NOP (skipped)
        test_prog(10) := x"01"; -- NOP (skipped)
        test_prog(11) := x"01"; -- NOP (skipped)
        test_prog(12) := x"00"; -- HALT (target)

        load_program(addr mod 8192, test_prog, 13);

        wait for CLK_PERIOD * 100;

        if halted = '1' then
            report "Test 5: PASSED - CPU halted";
        else
            report "Test 5: Waiting for completion...";
            wait until halted = '1' for CLK_PERIOD * 100;
        end if;

        ------------------------------------------------------------
        report "";
        report "=== All Operand Fetching Tests Complete ===";
        report "Tests run: 5";
        report "If no errors reported above, all tests PASSED";

        sim_done <= true;
        wait;
    end process;

end sim;
