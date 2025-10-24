-- UNIBUS Controller
-- Implements simplified UNIBUS for peripheral devices

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity unibus_controller is
    port (
        -- Clock and reset
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- CPU interface
        addr            : in  std_logic_vector(17 downto 0);  -- UNIBUS address (18-bit)
        wdata           : in  word_t;                          -- 16-bit data
        rdata           : out word_t;
        we              : in  std_logic;
        req             : in  std_logic;
        ack             : out std_logic;

        -- Device interfaces
        -- TTY (Console)
        tty_tx_data     : out byte_t;
        tty_tx_valid    : out std_logic;
        tty_tx_ready    : in  std_logic;
        tty_rx_data     : in  byte_t;
        tty_rx_valid    : in  std_logic;
        tty_rx_ready    : out std_logic;
        tty_interrupt   : out std_logic
    );
end unibus_controller;

architecture rtl of unibus_controller is

    -- UNIBUS I/O page (high addresses)
    -- TTY (DL11) registers - typical at 177560
    constant TTY_BASE   : std_logic_vector(17 downto 0) := "111" & "111" & "111" & "101" & "110" & "000";  -- 177560 octal
    constant TTY_RCSR   : std_logic_vector(2 downto 0) := "000";  -- Receiver Status
    constant TTY_RBUF   : std_logic_vector(2 downto 0) := "010";  -- Receiver Buffer
    constant TTY_XCSR   : std_logic_vector(2 downto 0) := "100";  -- Transmitter Status
    constant TTY_XBUF   : std_logic_vector(2 downto 0) := "110";  -- Transmitter Buffer

    -- TTY registers
    signal tty_rcsr     : word_t;  -- Receiver Control/Status
    signal tty_rbuf     : word_t;  -- Receiver Buffer
    signal tty_xcsr     : word_t;  -- Transmitter Control/Status
    signal tty_xbuf     : word_t;  -- Transmitter Buffer

    -- TTY status bits
    signal rx_done      : std_logic;  -- Character received
    signal rx_ie        : std_logic;  -- Receiver interrupt enable
    signal tx_ready     : std_logic;  -- Transmitter ready
    signal tx_ie        : std_logic;  -- Transmitter interrupt enable

    -- Determine if address is in TTY range
    signal tty_select   : std_logic;
    signal reg_offset   : std_logic_vector(2 downto 0);

begin

    -- Decode addresses
    tty_select <= '1' when addr(17 downto 3) = TTY_BASE(17 downto 3) else '0';
    reg_offset <= addr(2 downto 0);

    -- UNIBUS access process
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tty_rcsr <= (others => '0');
                tty_rbuf <= (others => '0');
                tty_xcsr <= x"0080";  -- TX Ready set
                tty_xbuf <= (others => '0');

                rx_done <= '0';
                rx_ie <= '0';
                tx_ready <= '1';
                tx_ie <= '0';

                ack <= '0';
                tty_tx_valid <= '0';
                tty_rx_ready <= '1';
                tty_interrupt <= '0';

            else
                ack <= '0';
                tty_tx_valid <= '0';

                -- Handle TTY device access
                if req = '1' and tty_select = '1' then
                    if we = '0' then
                        -- Read operation
                        case reg_offset is
                            when TTY_RCSR =>
                                rdata <= tty_rcsr;
                            when TTY_RBUF =>
                                rdata <= tty_rbuf;
                                rx_done <= '0';  -- Clear done bit on read
                            when TTY_XCSR =>
                                rdata <= tty_xcsr;
                            when TTY_XBUF =>
                                rdata <= tty_xbuf;
                            when others =>
                                rdata <= (others => '0');
                        end case;
                        ack <= '1';

                    else
                        -- Write operation
                        case reg_offset is
                            when TTY_RCSR =>
                                rx_ie <= wdata(6);  -- Interrupt enable bit
                            when TTY_XCSR =>
                                tx_ie <= wdata(6);  -- Interrupt enable bit
                            when TTY_XBUF =>
                                if tx_ready = '1' then
                                    tty_xbuf <= wdata;
                                    tty_tx_data <= wdata(7 downto 0);
                                    tty_tx_valid <= '1';
                                    tx_ready <= '0';  -- Clear ready until transmission done
                                end if;
                            when others =>
                                null;
                        end case;
                        ack <= '1';
                    end if;
                end if;

                -- Handle TTY receiver
                if tty_rx_valid = '1' and rx_done = '0' then
                    tty_rbuf <= x"00" & tty_rx_data;
                    rx_done <= '1';
                end if;

                -- Handle TTY transmitter completion
                if tty_tx_valid = '1' and tty_tx_ready = '1' then
                    tx_ready <= '1';  -- Set ready after transmission
                end if;

                -- Update status registers
                tty_rcsr <= (15 => '0',
                            7 => rx_done,
                            6 => rx_ie,
                            others => '0');

                tty_xcsr <= (15 => '0',
                            7 => tx_ready,
                            6 => tx_ie,
                            others => '0');

                -- Generate interrupts
                if (rx_done = '1' and rx_ie = '1') or (tx_ready = '1' and tx_ie = '1') then
                    tty_interrupt <= '1';
                else
                    tty_interrupt <= '0';
                end if;

            end if;
        end if;
    end process;

end rtl;
