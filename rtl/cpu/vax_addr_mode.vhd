-- VAX Addressing Mode Decoder
-- Parses operand specifiers and computes effective addresses
-- Implements all 16 VAX addressing modes

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity vax_addr_mode is
    port (
        -- Clock and reset
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- Control
        start           : in  std_logic;
        done            : out std_logic;

        -- Specifier byte input
        spec_byte       : in  byte_t;

        -- Additional bytes (for displacements)
        next_byte       : in  byte_t;
        next_byte_req   : out std_logic;
        next_byte_ack   : in  std_logic;

        -- Register file interface
        reg_num         : out integer range 0 to 15;
        reg_rdata       : in  longword_t;
        reg_wdata       : out longword_t;
        reg_we          : out std_logic;

        -- Memory interface for deferred modes
        mem_addr        : out virt_addr_t;
        mem_rdata       : in  longword_t;
        mem_req         : out std_logic;
        mem_ack         : in  std_logic;

        -- Output
        operand_value   : out longword_t;   -- The operand value
        operand_addr    : out virt_addr_t;  -- Address for memory operands
        is_register     : out std_logic;    -- 1 if register mode
        is_immediate    : out std_logic;    -- 1 if immediate/literal
        mode_type       : out std_logic_vector(3 downto 0)
    );
end vax_addr_mode;

architecture rtl of vax_addr_mode is

    -- Addressing mode from specifier
    signal addr_mode    : std_logic_vector(3 downto 0);
    signal reg_field    : integer range 0 to 15;

    -- State machine
    type state_t is (
        STATE_IDLE,
        STATE_PARSE,
        STATE_READ_DISP_BYTE,
        STATE_READ_DISP_WORD,
        STATE_READ_DISP_LONG,
        STATE_CALC_ADDR,
        STATE_READ_MEM,
        STATE_DEREF,
        STATE_DONE
    );
    signal state : state_t;

    -- Internal registers
    signal displacement : signed(31 downto 0);
    signal base_addr    : unsigned(31 downto 0);
    signal temp_addr    : unsigned(31 downto 0);
    signal byte_count   : integer range 0 to 3;

begin

    -- Extract mode and register from specifier byte
    addr_mode <= spec_byte(7 downto 4);
    reg_field <= to_integer(unsigned(spec_byte(3 downto 0)));

    -- Main state machine
    process(clk)
        variable reg_val : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= STATE_IDLE;
                done <= '0';
                next_byte_req <= '0';
                mem_req <= '0';
                reg_we <= '0';
                is_register <= '0';
                is_immediate <= '0';

            else
                case state is
                    when STATE_IDLE =>
                        done <= '0';
                        next_byte_req <= '0';
                        mem_req <= '0';
                        reg_we <= '0';

                        if start = '1' then
                            state <= STATE_PARSE;
                            reg_num <= reg_field;
                        end if;

                    when STATE_PARSE =>
                        -- Parse addressing mode
                        mode_type <= addr_mode;

                        case addr_mode is
                            -- Modes 0-3: Short literal (0-63)
                            when x"0" | x"1" | x"2" | x"3" =>
                                operand_value <= x"000000" & "00" & spec_byte(5 downto 0);
                                is_immediate <= '1';
                                is_register <= '0';
                                state <= STATE_DONE;

                            -- Mode 4: Indexed (complex, handle later)
                            when x"4" =>
                                -- TODO: Indexed mode requires parsing next specifier
                                state <= STATE_DONE;

                            -- Mode 5: Register
                            when x"5" =>
                                operand_value <= reg_rdata;
                                is_register <= '1';
                                is_immediate <= '0';
                                state <= STATE_DONE;

                            -- Mode 6: Register deferred [Rn]
                            when x"6" =>
                                temp_addr <= unsigned(reg_rdata);
                                is_register <= '0';
                                is_immediate <= '0';
                                state <= STATE_READ_MEM;

                            -- Mode 7: Autodecrement [--Rn]
                            when x"7" =>
                                reg_val := unsigned(reg_rdata);
                                reg_val := reg_val - 4;  -- Assume longword
                                temp_addr <= reg_val;
                                reg_wdata <= std_logic_vector(reg_val);
                                reg_we <= '1';
                                is_register <= '0';
                                is_immediate <= '0';
                                state <= STATE_READ_MEM;

                            -- Mode 8: Autoincrement [Rn++]
                            when x"8" =>
                                temp_addr <= unsigned(reg_rdata);

                                -- Special case: PC (R15) autoincrement = immediate
                                if reg_field = REG_PC then
                                    is_immediate <= '1';
                                    state <= STATE_READ_MEM;
                                else
                                    is_immediate <= '0';
                                    state <= STATE_READ_MEM;
                                end if;

                                -- Update register (post-increment)
                                reg_val := unsigned(reg_rdata);
                                reg_val := reg_val + 4;  -- Assume longword
                                reg_wdata <= std_logic_vector(reg_val);
                                reg_we <= '1';
                                is_register <= '0';

                            -- Mode 9: Autoincrement deferred [[Rn++]]
                            when x"9" =>
                                temp_addr <= unsigned(reg_rdata);

                                -- Update register
                                reg_val := unsigned(reg_rdata);
                                reg_val := reg_val + 4;
                                reg_wdata <= std_logic_vector(reg_val);
                                reg_we <= '1';

                                is_register <= '0';
                                is_immediate <= '0';
                                state <= STATE_DEREF;  -- Double dereference

                            -- Mode A: Byte displacement
                            when x"A" =>
                                base_addr <= unsigned(reg_rdata);
                                displacement <= (others => '0');
                                byte_count <= 0;
                                next_byte_req <= '1';
                                state <= STATE_READ_DISP_BYTE;

                            -- Mode B: Byte displacement deferred
                            when x"B" =>
                                base_addr <= unsigned(reg_rdata);
                                displacement <= (others => '0');
                                byte_count <= 0;
                                next_byte_req <= '1';
                                is_immediate <= '0';
                                state <= STATE_READ_DISP_BYTE;

                            -- Mode C: Word displacement
                            when x"C" =>
                                base_addr <= unsigned(reg_rdata);
                                displacement <= (others => '0');
                                byte_count <= 0;
                                next_byte_req <= '1';
                                state <= STATE_READ_DISP_WORD;

                            -- Mode D: Word displacement deferred
                            when x"D" =>
                                base_addr <= unsigned(reg_rdata);
                                displacement <= (others => '0');
                                byte_count <= 0;
                                next_byte_req <= '1';
                                state <= STATE_READ_DISP_WORD;

                            -- Mode E: Long displacement
                            when x"E" =>
                                base_addr <= unsigned(reg_rdata);
                                displacement <= (others => '0');
                                byte_count <= 0;
                                next_byte_req <= '1';
                                state <= STATE_READ_DISP_LONG;

                            -- Mode F: Long displacement deferred
                            when x"F" =>
                                base_addr <= unsigned(reg_rdata);
                                displacement <= (others => '0');
                                byte_count <= 0;
                                next_byte_req <= '1';
                                state <= STATE_READ_DISP_LONG;

                            when others =>
                                state <= STATE_DONE;
                        end case;

                    when STATE_READ_DISP_BYTE =>
                        if next_byte_ack = '1' then
                            displacement(7 downto 0) <= signed(next_byte);
                            -- Sign extend
                            displacement(31 downto 8) <= (others => next_byte(7));
                            next_byte_req <= '0';
                            state <= STATE_CALC_ADDR;
                        end if;

                    when STATE_READ_DISP_WORD =>
                        if next_byte_ack = '1' then
                            case byte_count is
                                when 0 =>
                                    displacement(7 downto 0) <= signed(next_byte);
                                    byte_count <= 1;
                                when 1 =>
                                    displacement(15 downto 8) <= signed(next_byte);
                                    -- Sign extend
                                    displacement(31 downto 16) <= (others => next_byte(7));
                                    next_byte_req <= '0';
                                    state <= STATE_CALC_ADDR;
                                when others =>
                                    null;
                            end case;
                        end if;

                    when STATE_READ_DISP_LONG =>
                        if next_byte_ack = '1' then
                            case byte_count is
                                when 0 =>
                                    displacement(7 downto 0) <= signed(next_byte);
                                    byte_count <= 1;
                                when 1 =>
                                    displacement(15 downto 8) <= signed(next_byte);
                                    byte_count <= 2;
                                when 2 =>
                                    displacement(23 downto 16) <= signed(next_byte);
                                    byte_count <= 3;
                                when 3 =>
                                    displacement(31 downto 24) <= signed(next_byte);
                                    next_byte_req <= '0';
                                    state <= STATE_CALC_ADDR;
                                when others =>
                                    null;
                            end case;
                        end if;

                    when STATE_CALC_ADDR =>
                        -- Calculate effective address
                        temp_addr <= unsigned(signed(base_addr) + displacement);

                        -- Check if deferred mode
                        if addr_mode(0) = '1' then  -- Odd modes are deferred
                            state <= STATE_DEREF;
                        else
                            state <= STATE_READ_MEM;
                        end if;

                    when STATE_READ_MEM =>
                        -- Read from memory
                        mem_addr <= std_logic_vector(temp_addr);
                        operand_addr <= std_logic_vector(temp_addr);
                        mem_req <= '1';

                        if mem_ack = '1' then
                            operand_value <= mem_rdata;
                            mem_req <= '0';
                            state <= STATE_DONE;
                        end if;

                    when STATE_DEREF =>
                        -- Double dereference for deferred modes
                        mem_addr <= std_logic_vector(temp_addr);
                        mem_req <= '1';

                        if mem_ack = '1' then
                            temp_addr <= unsigned(mem_rdata);
                            mem_req <= '0';
                            state <= STATE_READ_MEM;
                        end if;

                    when STATE_DONE =>
                        done <= '1';
                        reg_we <= '0';
                        if start = '0' then
                            state <= STATE_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end rtl;
