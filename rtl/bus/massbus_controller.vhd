-- MASSBUS Controller
-- Emulates a MASSBUS disk controller for VAX-11/780
-- Virtual disk storage is accessed via PCIe interface to host

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity massbus_controller is
    port (
        -- Clock and reset
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- CPU interface (memory-mapped registers)
        reg_addr        : in  std_logic_vector(7 downto 0);  -- Register address
        reg_wdata       : in  longword_t;
        reg_rdata       : out longword_t;
        reg_we          : in  std_logic;
        reg_req         : in  std_logic;
        reg_ack         : out std_logic;

        -- DMA interface to memory
        dma_addr        : out phys_addr_t;
        dma_wdata       : out longword_t;
        dma_rdata       : in  longword_t;
        dma_we          : out std_logic;
        dma_req         : out std_logic;
        dma_ack         : in  std_logic;

        -- Interrupt
        interrupt_req   : out std_logic;
        interrupt_vector: out std_logic_vector(7 downto 0);

        -- Virtual disk interface (to PCIe/host)
        disk_cmd        : out std_logic_vector(7 downto 0);  -- Command (read/write)
        disk_lba        : out std_logic_vector(31 downto 0); -- Logical block address
        disk_count      : out std_logic_vector(15 downto 0); -- Block count
        disk_buf_addr   : out std_logic_vector(31 downto 0); -- Buffer address in memory
        disk_start      : out std_logic;
        disk_busy       : in  std_logic;
        disk_done       : in  std_logic;
        disk_error      : in  std_logic
    );
end massbus_controller;

architecture rtl of massbus_controller is

    -- MASSBUS register addresses (simplified RP06/RP07 disk)
    constant REG_RPCS1  : std_logic_vector(7 downto 0) := x"00";  -- Control/Status 1
    constant REG_RPWC   : std_logic_vector(7 downto 0) := x"04";  -- Word Count
    constant REG_RPBA   : std_logic_vector(7 downto 0) := x"08";  -- Bus Address
    constant REG_RPDA   : std_logic_vector(7 downto 0) := x"0C";  -- Disk Address
    constant REG_RPCS2  : std_logic_vector(7 downto 0) := x"10";  -- Control/Status 2
    constant REG_RPDS   : std_logic_vector(7 downto 0) := x"14";  -- Drive Status
    constant REG_RPER1  : std_logic_vector(7 downto 0) := x"18";  -- Error Register 1
    constant REG_RPAS   : std_logic_vector(7 downto 0) := x"1C";  -- Attention Summary
    constant REG_RPLA   : std_logic_vector(7 downto 0) := x"20";  -- Look Ahead
    constant REG_RPDB   : std_logic_vector(7 downto 0) := x"24";  -- Data Buffer
    constant REG_RPMR   : std_logic_vector(7 downto 0) := x"28";  -- Maintenance Register
    constant REG_RPDT   : std_logic_vector(7 downto 0) := x"2C";  -- Drive Type
    constant REG_RPSN   : std_logic_vector(7 downto 0) := x"30";  -- Serial Number
    constant REG_RPOF   : std_logic_vector(7 downto 0) := x"34";  -- Offset Register

    -- RPCS1 function codes
    constant FUNC_NOP       : std_logic_vector(4 downto 0) := "00000";
    constant FUNC_UNLOAD    : std_logic_vector(4 downto 0) := "00001";
    constant FUNC_SEEK      : std_logic_vector(4 downto 0) := "00010";
    constant FUNC_RECAL     : std_logic_vector(4 downto 0) := "00011";
    constant FUNC_READ      : std_logic_vector(4 downto 0) := "00111";
    constant FUNC_WRITE     : std_logic_vector(4 downto 0) := "01001";
    constant FUNC_WRITE_CHK : std_logic_vector(4 downto 0) := "01011";

    -- Registers
    signal rpcs1        : longword_t;  -- Control/Status 1
    signal rpwc         : longword_t;  -- Word Count (negative, 2's complement)
    signal rpba         : longword_t;  -- Bus Address
    signal rpda         : longword_t;  -- Disk Address (cylinder, track, sector)
    signal rpcs2        : longword_t;  -- Control/Status 2
    signal rpds         : longword_t;  -- Drive Status
    signal rper1        : longword_t;  -- Error Register 1
    signal rpas         : longword_t;  -- Attention Summary
    signal rpdt         : longword_t;  -- Drive Type (RP06 = 022)

    -- Status bits
    signal ready        : std_logic;
    signal busy         : std_logic;
    signal error        : std_logic;

    -- Controller state
    type ctrl_state_t is (
        CTRL_IDLE,
        CTRL_SEEK,
        CTRL_TRANSFER,
        CTRL_DONE,
        CTRL_ERROR
    );
    signal ctrl_state : ctrl_state_t;

    -- Transfer state
    signal transfer_count : unsigned(15 downto 0);
    signal current_addr : unsigned(31 downto 0);

begin

    -- Register interface
    process(clk)
        variable func : std_logic_vector(4 downto 0);
        variable go : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rpcs1 <= (others => '0');
                rpwc <= (others => '0');
                rpba <= (others => '0');
                rpda <= (others => '0');
                rpcs2 <= (others => '0');
                rpds <= x"00000080";  -- Set RDY bit
                rper1 <= (others => '0');
                rpas <= (others => '0');
                rpdt <= x"00000016";  -- RP06 drive type (octal 022)

                ready <= '1';
                busy <= '0';
                error <= '0';
                ctrl_state <= CTRL_IDLE;
                reg_ack <= '0';
                interrupt_req <= '0';
                disk_start <= '0';

            else
                reg_ack <= '0';
                disk_start <= '0';

                -- Register reads
                if reg_req = '1' and reg_we = '0' then
                    case reg_addr is
                        when REG_RPCS1 => reg_rdata <= rpcs1;
                        when REG_RPWC  => reg_rdata <= rpwc;
                        when REG_RPBA  => reg_rdata <= rpba;
                        when REG_RPDA  => reg_rdata <= rpda;
                        when REG_RPCS2 => reg_rdata <= rpcs2;
                        when REG_RPDS  => reg_rdata <= rpds;
                        when REG_RPER1 => reg_rdata <= rper1;
                        when REG_RPAS  => reg_rdata <= rpas;
                        when REG_RPDT  => reg_rdata <= rpdt;
                        when others    => reg_rdata <= (others => '0');
                    end case;
                    reg_ack <= '1';
                end if;

                -- Register writes
                if reg_req = '1' and reg_we = '1' then
                    case reg_addr is
                        when REG_RPCS1 =>
                            rpcs1 <= reg_wdata;
                            func := reg_wdata(4 downto 0);
                            go := reg_wdata(0);

                            -- Check for GO bit and execute command
                            if go = '1' then
                                case func is
                                    when FUNC_READ | FUNC_WRITE =>
                                        if ready = '1' then
                                            busy <= '1';
                                            ready <= '0';
                                            ctrl_state <= CTRL_TRANSFER;

                                            -- Setup disk operation
                                            if func = FUNC_READ then
                                                disk_cmd <= x"01";  -- Read command
                                            else
                                                disk_cmd <= x"02";  -- Write command
                                            end if;

                                            -- Convert disk address to LBA
                                            -- Simplified: just use rpda as LBA for now
                                            disk_lba <= rpda;
                                            disk_count <= std_logic_vector(unsigned(not rpwc(15 downto 0)) + 1);
                                            disk_buf_addr <= rpba;
                                            disk_start <= '1';
                                        end if;

                                    when FUNC_SEEK =>
                                        ctrl_state <= CTRL_SEEK;
                                        busy <= '1';
                                        ready <= '0';

                                    when others =>
                                        -- NOP or unimplemented
                                        null;
                                end case;
                            end if;

                        when REG_RPWC  => rpwc <= reg_wdata;
                        when REG_RPBA  => rpba <= reg_wdata;
                        when REG_RPDA  => rpda <= reg_wdata;
                        when REG_RPCS2 => rpcs2 <= reg_wdata;
                        when others    => null;
                    end case;
                    reg_ack <= '1';
                end if;

                -- Controller state machine
                case ctrl_state is
                    when CTRL_IDLE =>
                        ready <= '1';
                        busy <= '0';
                        interrupt_req <= '0';

                    when CTRL_SEEK =>
                        -- Simulate seek delay (just wait a few cycles)
                        -- In real hardware, this would take milliseconds
                        ctrl_state <= CTRL_DONE;

                    when CTRL_TRANSFER =>
                        -- Wait for disk operation to complete
                        if disk_done = '1' then
                            if disk_error = '1' then
                                ctrl_state <= CTRL_ERROR;
                            else
                                ctrl_state <= CTRL_DONE;
                            end if;
                        end if;

                    when CTRL_DONE =>
                        ready <= '1';
                        busy <= '0';
                        interrupt_req <= '1';
                        interrupt_vector <= x"80";  -- Disk interrupt vector
                        ctrl_state <= CTRL_IDLE;

                    when CTRL_ERROR =>
                        ready <= '1';
                        busy <= '0';
                        error <= '1';
                        rper1 <= x"00000001";  -- Set error bit
                        interrupt_req <= '1';
                        interrupt_vector <= x"80";
                        ctrl_state <= CTRL_IDLE;

                end case;

                -- Update status register
                rpds(7) <= ready;   -- RDY
                rpds(10) <= busy;   -- PIP (Positioning in Progress)
                rpds(15) <= error;  -- ERR

            end if;
        end if;
    end process;

end rtl;
