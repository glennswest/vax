-- Testbench for VAX CPU
-- Simple testbench to verify basic CPU operation

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity tb_vax_cpu is
end tb_vax_cpu;

architecture sim of tb_vax_cpu is

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

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
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '1';
    signal mem_addr         : virt_addr_t;
    signal mem_wdata        : longword_t;
    signal mem_rdata        : longword_t;
    signal mem_op           : mem_op_t;
    signal mem_req          : std_logic;
    signal mem_ack          : std_logic;
    signal exception        : exception_t;
    signal interrupt_req    : std_logic_vector(15 downto 0) := (others => '0');
    signal interrupt_vector : std_logic_vector(7 downto 0) := (others => '0');
    signal interrupt_ack    : std_logic;
    signal halted           : std_logic;

    -- Simulation control
    signal sim_done : boolean := false;

    -- Simple memory model (1KB for testing)
    type memory_t is array(0 to 1023) of byte_t;
    signal memory : memory_t := (others => x"00");

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

    -- Simple memory model
    mem_model : process(clk)
        variable addr : integer;
    begin
        if rising_edge(clk) then
            mem_ack <= '0';

            if mem_req = '1' then
                addr := to_integer(unsigned(mem_addr)) mod 1024;

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

    -- Stimulus process
    stimulus : process
    begin
        -- Initialize memory with simple program
        -- MOVL #42, R1
        -- HALT

        wait for CLK_PERIOD * 2;
        rst <= '0';

        report "Starting VAX CPU simulation";

        -- Wait for some execution
        wait for CLK_PERIOD * 100;

        report "CPU execution test completed";

        sim_done <= true;
        wait;
    end process;

end sim;
