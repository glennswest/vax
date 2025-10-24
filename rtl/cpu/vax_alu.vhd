-- VAX ALU (Arithmetic Logic Unit)
-- Performs arithmetic and logical operations with condition code generation

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity vax_alu is
    port (
        clk         : in  std_logic;
        op          : in  alu_op_t;
        a           : in  longword_t;
        b           : in  longword_t;
        result      : out longword_t;
        flags       : out std_logic_vector(3 downto 0)  -- N, Z, V, C
    );
end vax_alu;

architecture rtl of vax_alu is

    signal result_i     : longword_t;
    signal flags_i      : std_logic_vector(3 downto 0);

    -- Extended results for overflow detection
    signal add_result   : std_logic_vector(32 downto 0);
    signal sub_result   : std_logic_vector(32 downto 0);
    signal mul_result   : signed(63 downto 0);

begin

    -- Combinational ALU operation
    process(op, a, b)
        variable a_signed   : signed(31 downto 0);
        variable b_signed   : signed(31 downto 0);
        variable a_unsigned : unsigned(31 downto 0);
        variable b_unsigned : unsigned(31 downto 0);
        variable temp_result: longword_t;
        variable temp_flags : std_logic_vector(3 downto 0);
        variable overflow   : std_logic;
    begin
        a_signed := signed(a);
        b_signed := signed(b);
        a_unsigned := unsigned(a);
        b_unsigned := unsigned(b);

        temp_result := (others => '0');
        temp_flags := (others => '0');
        overflow := '0';

        case op is
            when ALU_ADD =>
                -- Addition
                add_result <= std_logic_vector(resize(unsigned(a), 33) + resize(unsigned(b), 33));
                temp_result := add_result(31 downto 0);

                -- Carry flag
                temp_flags(0) := add_result(32);

                -- Overflow: operands same sign but result different
                if (a(31) = b(31)) and (a(31) /= temp_result(31)) then
                    temp_flags(1) := '1';  -- Overflow
                end if;

            when ALU_SUB =>
                -- Subtraction
                sub_result <= std_logic_vector(resize(unsigned(a), 33) - resize(unsigned(b), 33));
                temp_result := sub_result(31 downto 0);

                -- Carry flag (borrow)
                temp_flags(0) := sub_result(32);

                -- Overflow: operands different sign and result has sign of b
                if (a(31) /= b(31)) and (temp_result(31) = b(31)) then
                    temp_flags(1) := '1';  -- Overflow
                end if;

            when ALU_MUL =>
                -- Multiplication (signed)
                mul_result <= a_signed * b_signed;
                temp_result := std_logic_vector(mul_result(31 downto 0));

                -- Check for overflow (result doesn't fit in 32 bits)
                if mul_result(63 downto 31) /= (32 downto 0 => mul_result(31)) then
                    temp_flags(1) := '1';  -- Overflow
                end if;

            when ALU_DIV =>
                -- Division (signed)
                if b_signed /= 0 then
                    temp_result := std_logic_vector(a_signed / b_signed);
                else
                    -- Division by zero - set overflow
                    temp_flags(1) := '1';
                    temp_result := (others => '0');
                end if;

            when ALU_AND =>
                -- Logical AND
                temp_result := a and b;

            when ALU_OR =>
                -- Logical OR (BIS - Bit Set)
                temp_result := a or b;

            when ALU_XOR =>
                -- Logical XOR
                temp_result := a xor b;

            when ALU_BIC =>
                -- Bit Clear
                temp_result := a and (not b);

            when ALU_ASH =>
                -- Arithmetic shift
                -- b contains shift count (positive = left, negative = right)
                if b_signed >= 0 then
                    -- Shift left
                    if to_integer(b_signed) < 32 then
                        temp_result := std_logic_vector(shift_left(a_unsigned, to_integer(b_signed)));
                    else
                        temp_result := (others => '0');
                    end if;
                else
                    -- Shift right (arithmetic)
                    if to_integer(abs(b_signed)) < 32 then
                        temp_result := std_logic_vector(shift_right(a_signed, to_integer(abs(b_signed))));
                    else
                        temp_result := (31 downto 0 => a(31));  -- Sign extend
                    end if;
                end if;

            when ALU_ROT =>
                -- Rotate
                -- Simplified rotate left
                if to_integer(b_signed) < 32 and to_integer(b_signed) >= 0 then
                    temp_result := std_logic_vector(rotate_left(a_unsigned, to_integer(b_signed)));
                end if;

            when ALU_CMP =>
                -- Compare (subtract but don't store result)
                sub_result <= std_logic_vector(resize(unsigned(a), 33) - resize(unsigned(b), 33));
                temp_result := sub_result(31 downto 0);
                temp_flags(0) := sub_result(32);
                if (a(31) /= b(31)) and (temp_result(31) = b(31)) then
                    temp_flags(1) := '1';
                end if;

            when ALU_TST =>
                -- Test (AND but don't store result)
                temp_result := a;  -- Pass through for flag computation

            when ALU_MOV =>
                -- Move (pass through)
                temp_result := a;

            when ALU_NOP =>
                -- No operation
                temp_result := (others => '0');

        end case;

        -- Set Zero flag
        if temp_result = x"00000000" then
            temp_flags(2) := '1';
        end if;

        -- Set Negative flag
        temp_flags(3) := temp_result(31);

        result_i <= temp_result;
        flags_i <= temp_flags;

    end process;

    -- Register outputs
    process(clk)
    begin
        if rising_edge(clk) then
            result <= result_i;
            flags <= flags_i;
        end if;
    end process;

end rtl;
