-- Testbench for VAX Instruction Decoder
-- Tests all implemented instructions

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity tb_decoder is
end tb_decoder;

architecture sim of tb_decoder is

    -- Component declaration
    component vax_decoder is
        port (
            opcode          : in  byte_t;
            opcode2         : in  byte_t;
            is_two_byte     : in  std_logic;
            alu_operation   : out alu_op_t;
            operand_count   : out integer range 0 to 6;
            inst_class      : out std_logic_vector(3 downto 0);
            valid           : out std_logic
        );
    end component;

    -- Signals
    signal opcode       : byte_t := x"00";
    signal opcode2      : byte_t := x"00";
    signal is_two_byte  : std_logic := '0';
    signal alu_operation : alu_op_t;
    signal operand_count : integer range 0 to 6;
    signal inst_class   : std_logic_vector(3 downto 0);
    signal valid        : std_logic;

    -- Test counter
    signal test_num : integer := 0;

    -- Simulation control
    signal sim_done : boolean := false;

begin

    -- DUT instantiation
    dut : vax_decoder
        port map (
            opcode        => opcode,
            opcode2       => opcode2,
            is_two_byte   => is_two_byte,
            alu_operation => alu_operation,
            operand_count => operand_count,
            inst_class    => inst_class,
            valid         => valid
        );

    -- Test process
    test_proc : process
        procedure test_instruction(
            constant opc : in byte_t;
            constant name : in string;
            constant expected_valid : in std_logic;
            constant expected_operands : in integer
        ) is
        begin
            opcode <= opc;
            wait for 10 ns;

            report "Test " & integer'image(test_num) & ": " & name &
                   " (0x" & to_hstring(opc) & ")";

            if valid /= expected_valid then
                report "  FAIL: Expected valid=" & std_logic'image(expected_valid) &
                       " got " & std_logic'image(valid)
                    severity error;
            elsif valid = '1' and operand_count /= expected_operands then
                report "  FAIL: Expected " & integer'image(expected_operands) &
                       " operands, got " & integer'image(operand_count)
                    severity error;
            else
                report "  PASS: valid=" & std_logic'image(valid) &
                       " operands=" & integer'image(operand_count) &
                       " class=" & to_hstring(inst_class);
            end if;

            test_num <= test_num + 1;
            wait for 5 ns;
        end procedure;

    begin
        report "Starting VAX Decoder Tests";
        report "===========================";

        -- Move instructions
        report "";
        report "MOVE INSTRUCTIONS";
        test_instruction(x"90", "MOVB", '1', 2);
        test_instruction(x"B0", "MOVW", '1', 2);
        test_instruction(x"D0", "MOVL", '1', 2);
        test_instruction(x"DD", "PUSHL", '1', 1);
        test_instruction(x"D4", "CLRL", '1', 1);

        -- Arithmetic 2-operand
        report "";
        report "ARITHMETIC INSTRUCTIONS (2-operand)";
        test_instruction(x"C0", "ADDL2", '1', 2);
        test_instruction(x"C2", "SUBL2", '1', 2);
        test_instruction(x"C4", "MULL2", '1', 2);
        test_instruction(x"C6", "DIVL2", '1', 2);

        -- Arithmetic 3-operand
        report "";
        report "ARITHMETIC INSTRUCTIONS (3-operand)";
        test_instruction(x"C1", "ADDL3", '1', 3);
        test_instruction(x"C3", "SUBL3", '1', 3);
        test_instruction(x"C5", "MULL3", '1', 3);
        test_instruction(x"C7", "DIVL3", '1', 3);

        -- Increment/Decrement
        report "";
        report "INCREMENT/DECREMENT";
        test_instruction(x"D6", "INCL", '1', 1);
        test_instruction(x"D7", "DECL", '1', 1);

        -- Logical
        report "";
        report "LOGICAL OPERATIONS";
        test_instruction(x"C8", "BISL2", '1', 2);
        test_instruction(x"CA", "BICL2", '1', 2);
        test_instruction(x"CC", "XORL2", '1', 2);

        -- Compare
        report "";
        report "COMPARE AND TEST";
        test_instruction(x"D1", "CMPL", '1', 2);
        test_instruction(x"D5", "TSTL", '1', 1);
        test_instruction(x"D3", "BITL", '1', 2);

        -- Branch
        report "";
        report "BRANCH INSTRUCTIONS";
        test_instruction(x"11", "BRB", '1', 0);
        test_instruction(x"13", "BEQL", '1', 0);
        test_instruction(x"12", "BNEQ", '1', 0);
        test_instruction(x"14", "BGTR", '1', 0);
        test_instruction(x"15", "BLEQ", '1', 0);
        test_instruction(x"18", "BGEQ", '1', 0);
        test_instruction(x"19", "BLSS", '1', 0);

        -- Jump and Call
        report "";
        report "JUMP AND SUBROUTINE";
        test_instruction(x"16", "JSB", '1', 1);
        test_instruction(x"17", "JMP", '1', 1);
        test_instruction(x"05", "RSB", '1', 0);
        test_instruction(x"FB", "CALLS", '1', 2);
        test_instruction(x"04", "RET", '1', 0);

        -- Privileged
        report "";
        report "PRIVILEGED INSTRUCTIONS";
        test_instruction(x"DA", "MTPR", '1', 2);
        test_instruction(x"DB", "MFPR", '1', 2);
        test_instruction(x"02", "REI", '1', 0);

        -- Control
        report "";
        report "CONTROL INSTRUCTIONS";
        test_instruction(x"00", "HALT", '1', 0);
        test_instruction(x"01", "NOP", '1', 0);

        -- Invalid instructions
        report "";
        report "INVALID INSTRUCTIONS";
        test_instruction(x"08", "Invalid 0x08", '0', 0);
        test_instruction(x"0F", "Invalid 0x0F", '0', 0);
        test_instruction(x"FF", "Invalid 0xFF", '0', 0);

        report "";
        report "===========================";
        report "All decoder tests completed!";
        report "Total tests: " & integer'image(test_num);

        sim_done <= true;
        wait;
    end process;

end sim;
