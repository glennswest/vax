-- Memory Controller
-- Interfaces between VAX CPU and Xilinx MIG for DDR4/DDR5
-- Handles clock domain crossing and data width conversion

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity memory_controller is
    generic (
        DDR_DATA_WIDTH : integer := 512;  -- DDR interface width (512 bits for DDR4/5)
        DDR_ADDR_WIDTH : integer := 30    -- Physical address width
    );
    port (
        -- CPU side (VAX clock domain)
        clk             : in  std_logic;
        rst             : in  std_logic;

        cpu_addr        : in  phys_addr_t;
        cpu_wdata       : in  longword_t;
        cpu_rdata       : out longword_t;
        cpu_we          : in  std_logic;
        cpu_req         : in  std_logic;
        cpu_ack         : out std_logic;

        -- DDR side (MIG clock domain)
        ddr_clk         : in  std_logic;
        ddr_rst         : in  std_logic;
        ddr_ready       : in  std_logic;

        -- DDR command interface
        ddr_cmd_valid   : out std_logic;
        ddr_cmd_ready   : in  std_logic;
        ddr_cmd_addr    : out std_logic_vector(DDR_ADDR_WIDTH-1 downto 0);
        ddr_cmd_we      : out std_logic;
        ddr_cmd_en      : out std_logic;

        -- DDR write data interface
        ddr_wr_data     : out std_logic_vector(DDR_DATA_WIDTH-1 downto 0);
        ddr_wr_mask     : out std_logic_vector(DDR_DATA_WIDTH/8-1 downto 0);
        ddr_wr_valid    : out std_logic;
        ddr_wr_ready    : in  std_logic;

        -- DDR read data interface
        ddr_rd_data     : in  std_logic_vector(DDR_DATA_WIDTH-1 downto 0);
        ddr_rd_valid    : in  std_logic;
        ddr_rd_ready    : out std_logic
    );
end memory_controller;

architecture rtl of memory_controller is

    -- FIFO depths
    constant CMD_FIFO_DEPTH : integer := 16;
    constant DATA_FIFO_DEPTH : integer := 16;

    -- Command FIFO signals
    type cmd_entry_t is record
        addr    : std_logic_vector(31 downto 0);
        we      : std_logic;
        data    : longword_t;
    end record;

    type cmd_fifo_t is array(0 to CMD_FIFO_DEPTH-1) of cmd_entry_t;
    signal cmd_fifo : cmd_fifo_t;
    signal cmd_wr_ptr : unsigned(3 downto 0);
    signal cmd_rd_ptr : unsigned(3 downto 0);
    signal cmd_count : unsigned(4 downto 0);
    signal cmd_full : std_logic;
    signal cmd_empty : std_logic;

    -- Response FIFO for read data
    type resp_fifo_t is array(0 to DATA_FIFO_DEPTH-1) of longword_t;
    signal resp_fifo : resp_fifo_t;
    signal resp_wr_ptr : unsigned(3 downto 0);
    signal resp_rd_ptr : unsigned(3 downto 0);
    signal resp_count : unsigned(4 downto 0);
    signal resp_full : std_logic;
    signal resp_empty : std_logic;

    -- State machines
    type cpu_state_t is (CPU_IDLE, CPU_WAIT_ACK);
    signal cpu_state : cpu_state_t;

    type ddr_state_t is (DDR_IDLE, DDR_CMD, DDR_WRITE, DDR_READ);
    signal ddr_state : ddr_state_t;

    -- Internal signals
    signal cpu_ack_i : std_logic;
    signal current_cmd : cmd_entry_t;

    -- Byte offset within DDR burst
    signal byte_offset : unsigned(5 downto 0);  -- Offset within 512-bit word

begin

    -- FIFO status
    cmd_full <= '1' when cmd_count = CMD_FIFO_DEPTH else '0';
    cmd_empty <= '1' when cmd_count = 0 else '0';
    resp_full <= '1' when resp_count = DATA_FIFO_DEPTH else '0';
    resp_empty <= '1' when resp_count = 0 else '0';

    cpu_ack <= cpu_ack_i;

    -- CPU-side interface (handles requests from CPU)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cpu_state <= CPU_IDLE;
                cpu_ack_i <= '0';
                cmd_wr_ptr <= (others => '0');
                cmd_count <= (others => '0');

            else
                case cpu_state is
                    when CPU_IDLE =>
                        cpu_ack_i <= '0';

                        if cpu_req = '1' and cmd_full = '0' then
                            -- Accept request and add to command FIFO
                            cmd_fifo(to_integer(cmd_wr_ptr)).addr <= cpu_addr;
                            cmd_fifo(to_integer(cmd_wr_ptr)).we <= cpu_we;
                            cmd_fifo(to_integer(cmd_wr_ptr)).data <= cpu_wdata;

                            cmd_wr_ptr <= cmd_wr_ptr + 1;
                            cmd_count <= cmd_count + 1;

                            if cpu_we = '1' then
                                -- Write operation - ack immediately
                                cpu_ack_i <= '1';
                                cpu_state <= CPU_IDLE;
                            else
                                -- Read operation - wait for data
                                cpu_state <= CPU_WAIT_ACK;
                            end if;
                        end if;

                    when CPU_WAIT_ACK =>
                        -- Waiting for read data to arrive in response FIFO
                        if resp_empty = '0' then
                            cpu_rdata <= resp_fifo(to_integer(resp_rd_ptr));
                            resp_rd_ptr <= resp_rd_ptr + 1;
                            resp_count <= resp_count - 1;
                            cpu_ack_i <= '1';
                            cpu_state <= CPU_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- DDR-side interface (handles DDR transactions)
    process(ddr_clk)
        variable word_select : integer range 0 to 15;  -- Which 32-bit word in 512-bit data
    begin
        if rising_edge(ddr_clk) then
            if ddr_rst = '1' then
                ddr_state <= DDR_IDLE;
                cmd_rd_ptr <= (others => '0');
                resp_wr_ptr <= (others => '0');
                resp_count <= (others => '0');
                ddr_cmd_valid <= '0';
                ddr_wr_valid <= '0';
                ddr_rd_ready <= '0';

            else
                case ddr_state is
                    when DDR_IDLE =>
                        ddr_cmd_valid <= '0';
                        ddr_wr_valid <= '0';
                        ddr_rd_ready <= '1';

                        if ddr_ready = '1' and cmd_empty = '0' then
                            -- Get command from FIFO
                            current_cmd <= cmd_fifo(to_integer(cmd_rd_ptr));
                            ddr_state <= DDR_CMD;
                        end if;

                    when DDR_CMD =>
                        -- Issue command to DDR
                        ddr_cmd_addr <= current_cmd.addr(DDR_ADDR_WIDTH-1 downto 0);
                        ddr_cmd_we <= current_cmd.we;
                        ddr_cmd_en <= '1';
                        ddr_cmd_valid <= '1';

                        if ddr_cmd_ready = '1' then
                            ddr_cmd_valid <= '0';
                            cmd_rd_ptr <= cmd_rd_ptr + 1;
                            cmd_count <= cmd_count - 1;

                            if current_cmd.we = '1' then
                                ddr_state <= DDR_WRITE;
                            else
                                ddr_state <= DDR_READ;
                            end if;
                        end if;

                    when DDR_WRITE =>
                        -- Write data to DDR
                        -- Calculate which 32-bit word within the 512-bit DDR word
                        byte_offset <= unsigned(current_cmd.addr(5 downto 0));
                        word_select := to_integer(unsigned(current_cmd.addr(5 downto 2)));

                        -- Prepare write data (place 32-bit word at correct position)
                        ddr_wr_data <= (others => '0');
                        ddr_wr_data(word_select*32+31 downto word_select*32) <= current_cmd.data;

                        -- Set write mask (only write the 4 bytes we want)
                        ddr_wr_mask <= (others => '1');  -- Mask all bytes
                        ddr_wr_mask(word_select*4+3 downto word_select*4) <= (others => '0');  -- Unmask our 4 bytes

                        ddr_wr_valid <= '1';

                        if ddr_wr_ready = '1' then
                            ddr_wr_valid <= '0';
                            ddr_state <= DDR_IDLE;
                        end if;

                    when DDR_READ =>
                        -- Wait for read data from DDR
                        ddr_rd_ready <= '1';

                        if ddr_rd_valid = '1' and resp_full = '0' then
                            -- Extract correct 32-bit word from 512-bit data
                            word_select := to_integer(unsigned(current_cmd.addr(5 downto 2)));
                            resp_fifo(to_integer(resp_wr_ptr)) <=
                                ddr_rd_data(word_select*32+31 downto word_select*32);

                            resp_wr_ptr <= resp_wr_ptr + 1;
                            resp_count <= resp_count + 1;
                            ddr_state <= DDR_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end rtl;
