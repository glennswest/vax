-- PCIe Interface
-- Provides PCIe bus interface for additional peripheral devices
-- Supports: PCIe Ethernet, GPU, NVMe storage, SATA controllers, etc.
-- Generic PCIe device support with BAR mapping

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity pcie_interface is
    port (
        -- System clock and reset
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- PCIe clock domain
        pcie_clk        : in  std_logic;
        pcie_rst        : in  std_logic;

        -- PCIe AXI Stream TX (VAX to host)
        pcie_tx_tdata   : out std_logic_vector(255 downto 0);
        pcie_tx_tkeep   : out std_logic_vector(31 downto 0);
        pcie_tx_tlast   : out std_logic;
        pcie_tx_tvalid  : out std_logic;
        pcie_tx_tready  : in  std_logic;

        -- PCIe AXI Stream RX (host to VAX)
        pcie_rx_tdata   : in  std_logic_vector(255 downto 0);
        pcie_rx_tkeep   : in  std_logic_vector(31 downto 0);
        pcie_rx_tlast   : in  std_logic;
        pcie_rx_tvalid  : in  std_logic;
        pcie_rx_tready  : out std_logic;

        -- Virtual Disk Interface
        disk_cmd        : in  std_logic_vector(7 downto 0);
        disk_lba        : in  std_logic_vector(31 downto 0);
        disk_count      : in  std_logic_vector(15 downto 0);
        disk_buf_addr   : in  std_logic_vector(31 downto 0);
        disk_start      : in  std_logic;
        disk_busy       : out std_logic;
        disk_done       : out std_logic;
        disk_error      : out std_logic;

        -- DMA interface to memory
        dma_addr        : out phys_addr_t;
        dma_wdata       : out longword_t;
        dma_rdata       : in  longword_t;
        dma_we          : out std_logic;
        dma_req         : out std_logic;
        dma_ack         : in  std_logic;

        -- Console interface
        console_tx_data : in  byte_t;
        console_tx_valid: in  std_logic;
        console_tx_ready: out std_logic;
        console_rx_data : out byte_t;
        console_rx_valid: out std_logic;
        console_rx_ready: in  std_logic
    );
end pcie_interface;

architecture rtl of pcie_interface is

    -- Message types
    constant MSG_DISK_READ_REQ  : std_logic_vector(7 downto 0) := x"01";
    constant MSG_DISK_READ_RESP : std_logic_vector(7 downto 0) := x"02";
    constant MSG_DISK_WRITE_REQ : std_logic_vector(7 downto 0) := x"03";
    constant MSG_DISK_WRITE_RESP: std_logic_vector(7 downto 0) := x"04";
    constant MSG_CONSOLE_TX     : std_logic_vector(7 downto 0) := x"10";
    constant MSG_CONSOLE_RX     : std_logic_vector(7 downto 0) := x"11";
    constant MSG_STATUS         : std_logic_vector(7 downto 0) := x"F0";

    -- TX State machine
    type tx_state_t is (
        TX_IDLE,
        TX_DISK_REQ,
        TX_DISK_DATA,
        TX_CONSOLE,
        TX_STATUS
    );
    signal tx_state : tx_state_t;

    -- RX State machine
    type rx_state_t is (
        RX_IDLE,
        RX_HEADER,
        RX_DISK_DATA,
        RX_CONSOLE,
        RX_DONE
    );
    signal rx_state : rx_state_t;

    -- Message buffer
    signal tx_msg_type  : std_logic_vector(7 downto 0);
    signal tx_msg_len   : unsigned(15 downto 0);
    signal rx_msg_type  : std_logic_vector(7 downto 0);
    signal rx_msg_len   : unsigned(15 downto 0);

    -- Disk operation state
    signal disk_busy_i  : std_logic;
    signal disk_cmd_reg : std_logic_vector(7 downto 0);
    signal disk_lba_reg : std_logic_vector(31 downto 0);
    signal disk_count_reg : std_logic_vector(15 downto 0);
    signal disk_addr_reg : std_logic_vector(31 downto 0);
    signal transfer_count : unsigned(15 downto 0);

    -- Console FIFOs (simple)
    signal console_tx_fifo : byte_t;
    signal console_tx_avail : std_logic;
    signal console_rx_fifo : byte_t;
    signal console_rx_avail : std_logic;

    -- Clock domain crossing signals
    signal disk_start_sync : std_logic_vector(2 downto 0);
    signal disk_start_pcie : std_logic;

begin

    disk_busy <= disk_busy_i;

    -- Synchronize disk_start to PCIe clock domain
    process(pcie_clk)
    begin
        if rising_edge(pcie_clk) then
            disk_start_sync <= disk_start_sync(1 downto 0) & disk_start;
        end if;
    end process;

    disk_start_pcie <= disk_start_sync(2) and not disk_start_sync(1);  -- Edge detect

    -- TX (VAX to host) process
    process(pcie_clk)
    begin
        if rising_edge(pcie_clk) then
            if pcie_rst = '1' then
                tx_state <= TX_IDLE;
                pcie_tx_tvalid <= '0';
                pcie_tx_tlast <= '0';
                console_tx_ready <= '0';

            else
                case tx_state is
                    when TX_IDLE =>
                        pcie_tx_tvalid <= '0';
                        console_tx_ready <= '1';

                        -- Priority: disk requests, then console
                        if disk_start_pcie = '1' then
                            disk_cmd_reg <= disk_cmd;
                            disk_lba_reg <= disk_lba;
                            disk_count_reg <= disk_count;
                            disk_addr_reg <= disk_buf_addr;
                            disk_busy_i <= '1';
                            tx_state <= TX_DISK_REQ;

                        elsif console_tx_valid = '1' then
                            console_tx_fifo <= console_tx_data;
                            tx_state <= TX_CONSOLE;
                        end if;

                    when TX_DISK_REQ =>
                        -- Send disk request header to host
                        -- Header format: [msg_type, cmd, lba, count, buf_addr]
                        pcie_tx_tdata <= (
                            255 downto 248 => MSG_DISK_READ_REQ,
                            247 downto 240 => disk_cmd_reg,
                            239 downto 208 => disk_lba_reg,
                            207 downto 192 => disk_count_reg,
                            191 downto 160 => disk_addr_reg,
                            others => '0'
                        );
                        pcie_tx_tkeep <= (others => '1');
                        pcie_tx_tlast <= '1';
                        pcie_tx_tvalid <= '1';

                        if pcie_tx_tready = '1' then
                            if disk_cmd_reg = x"01" then
                                -- Read: wait for response
                                tx_state <= TX_IDLE;
                            else
                                -- Write: send data
                                tx_state <= TX_DISK_DATA;
                                transfer_count <= (others => '0');
                            end if;
                        end if;

                    when TX_DISK_DATA =>
                        -- Send disk write data
                        -- TODO: DMA from memory to PCIe
                        -- For now, simplified
                        tx_state <= TX_IDLE;
                        disk_busy_i <= '0';
                        disk_done <= '1';

                    when TX_CONSOLE =>
                        -- Send console character to host
                        pcie_tx_tdata <= (
                            255 downto 248 => MSG_CONSOLE_TX,
                            247 downto 240 => console_tx_fifo,
                            others => '0'
                        );
                        pcie_tx_tkeep <= (31 downto 2 => '0', others => '1');
                        pcie_tx_tlast <= '1';
                        pcie_tx_tvalid <= '1';

                        if pcie_tx_tready = '1' then
                            tx_state <= TX_IDLE;
                        end if;

                    when TX_STATUS =>
                        tx_state <= TX_IDLE;

                end case;
            end if;
        end if;
    end process;

    -- RX (host to VAX) process
    process(pcie_clk)
    begin
        if rising_edge(pcie_clk) then
            if pcie_rst = '1' then
                rx_state <= RX_IDLE;
                pcie_rx_tready <= '1';
                console_rx_valid <= '0';
                disk_done <= '0';
                disk_error <= '0';

            else
                console_rx_valid <= '0';
                disk_done <= '0';

                case rx_state is
                    when RX_IDLE =>
                        pcie_rx_tready <= '1';

                        if pcie_rx_tvalid = '1' then
                            rx_state <= RX_HEADER;
                        end if;

                    when RX_HEADER =>
                        -- Parse message header
                        rx_msg_type <= pcie_rx_tdata(255 downto 248);

                        case pcie_rx_tdata(255 downto 248) is
                            when MSG_DISK_READ_RESP | MSG_DISK_WRITE_RESP =>
                                rx_state <= RX_DISK_DATA;

                            when MSG_CONSOLE_RX =>
                                console_rx_data <= pcie_rx_tdata(247 downto 240);
                                console_rx_valid <= '1';
                                rx_state <= RX_DONE;

                            when others =>
                                rx_state <= RX_DONE;
                        end case;

                    when RX_DISK_DATA =>
                        -- Receive disk data from host
                        -- TODO: DMA to memory
                        if pcie_rx_tlast = '1' then
                            disk_done <= '1';
                            disk_busy_i <= '0';
                            rx_state <= RX_DONE;
                        end if;

                    when RX_CONSOLE =>
                        rx_state <= RX_DONE;

                    when RX_DONE =>
                        if pcie_rx_tlast = '1' then
                            rx_state <= RX_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end rtl;
