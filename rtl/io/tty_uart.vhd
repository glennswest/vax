-- TTY UART
-- Simple UART for console terminal interface
-- Configurable baud rate with standard 8N1 format

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity tty_uart is
    generic (
        CLK_FREQ    : integer := 100_000_000;  -- Clock frequency in Hz
        BAUD_RATE   : integer := 115200         -- Baud rate
    );
    port (
        -- Clock and reset
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- Transmit interface
        tx_data     : in  byte_t;
        tx_valid    : in  std_logic;
        tx_ready    : out std_logic;

        -- Receive interface
        rx_data     : out byte_t;
        rx_valid    : out std_logic;
        rx_ready    : in  std_logic;

        -- UART signals
        uart_tx     : out std_logic;
        uart_rx     : in  std_logic
    );
end tty_uart;

architecture rtl of tty_uart is

    -- Baud rate divider
    constant BAUD_DIV : integer := CLK_FREQ / BAUD_RATE;

    -- TX state machine
    type tx_state_t is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state : tx_state_t;
    signal tx_counter : integer range 0 to BAUD_DIV-1;
    signal tx_bit_idx : integer range 0 to 7;
    signal tx_shift : byte_t;

    -- RX state machine
    type rx_state_t is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal rx_state : rx_state_t;
    signal rx_counter : integer range 0 to BAUD_DIV-1;
    signal rx_bit_idx : integer range 0 to 7;
    signal rx_shift : byte_t;

    -- RX synchronizer
    signal uart_rx_sync : std_logic_vector(2 downto 0);

begin

    -- Transmitter
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tx_state <= TX_IDLE;
                tx_ready <= '1';
                uart_tx <= '1';
                tx_counter <= 0;
                tx_bit_idx <= 0;

            else
                case tx_state is
                    when TX_IDLE =>
                        uart_tx <= '1';
                        tx_ready <= '1';

                        if tx_valid = '1' and tx_ready = '1' then
                            tx_shift <= tx_data;
                            tx_state <= TX_START;
                            tx_ready <= '0';
                            tx_counter <= 0;
                        end if;

                    when TX_START =>
                        uart_tx <= '0';  -- Start bit
                        if tx_counter = BAUD_DIV-1 then
                            tx_counter <= 0;
                            tx_state <= TX_DATA;
                            tx_bit_idx <= 0;
                        else
                            tx_counter <= tx_counter + 1;
                        end if;

                    when TX_DATA =>
                        uart_tx <= tx_shift(tx_bit_idx);
                        if tx_counter = BAUD_DIV-1 then
                            tx_counter <= 0;
                            if tx_bit_idx = 7 then
                                tx_state <= TX_STOP;
                            else
                                tx_bit_idx <= tx_bit_idx + 1;
                            end if;
                        else
                            tx_counter <= tx_counter + 1;
                        end if;

                    when TX_STOP =>
                        uart_tx <= '1';  -- Stop bit
                        if tx_counter = BAUD_DIV-1 then
                            tx_counter <= 0;
                            tx_state <= TX_IDLE;
                        else
                            tx_counter <= tx_counter + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- Receiver synchronizer
    process(clk)
    begin
        if rising_edge(clk) then
            uart_rx_sync <= uart_rx_sync(1 downto 0) & uart_rx;
        end if;
    end process;

    -- Receiver
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rx_state <= RX_IDLE;
                rx_valid <= '0';
                rx_counter <= 0;
                rx_bit_idx <= 0;

            else
                rx_valid <= '0';

                case rx_state is
                    when RX_IDLE =>
                        if uart_rx_sync(2) = '0' then  -- Start bit detected
                            rx_state <= RX_START;
                            rx_counter <= BAUD_DIV / 2;  -- Sample in middle of bit
                        end if;

                    when RX_START =>
                        if rx_counter = BAUD_DIV-1 then
                            rx_counter <= 0;
                            rx_state <= RX_DATA;
                            rx_bit_idx <= 0;
                        else
                            rx_counter <= rx_counter + 1;
                        end if;

                    when RX_DATA =>
                        if rx_counter = BAUD_DIV-1 then
                            rx_shift(rx_bit_idx) <= uart_rx_sync(2);
                            rx_counter <= 0;
                            if rx_bit_idx = 7 then
                                rx_state <= RX_STOP;
                            else
                                rx_bit_idx <= rx_bit_idx + 1;
                            end if;
                        else
                            rx_counter <= rx_counter + 1;
                        end if;

                    when RX_STOP =>
                        if rx_counter = BAUD_DIV-1 then
                            rx_data <= rx_shift;
                            rx_valid <= '1';
                            rx_counter <= 0;
                            rx_state <= RX_IDLE;
                        else
                            rx_counter <= rx_counter + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end rtl;
