-- VAX Instruction Decoder
-- Comprehensive opcode decoder with instruction information
-- Returns decoded instruction properties without executing

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity vax_decoder is
    port (
        -- Input
        opcode          : in  byte_t;
        opcode2         : in  byte_t;  -- For two-byte opcodes
        is_two_byte     : in  std_logic;

        -- Decoded output
        alu_operation   : out alu_op_t;
        operand_count   : out integer range 0 to 6;
        inst_class      : out std_logic_vector(3 downto 0);  -- Instruction class
        valid           : out std_logic  -- 1 if valid instruction
    );
end vax_decoder;

architecture rtl of vax_decoder is

    -- Instruction classes
    constant CLASS_MOVE     : std_logic_vector(3 downto 0) := x"0";
    constant CLASS_ARITH    : std_logic_vector(3 downto 0) := x"1";
    constant CLASS_LOGICAL  : std_logic_vector(3 downto 0) := x"2";
    constant CLASS_COMPARE  : std_logic_vector(3 downto 0) := x"3";
    constant CLASS_BRANCH   : std_logic_vector(3 downto 0) := x"4";
    constant CLASS_JUMP     : std_logic_vector(3 downto 0) := x"5";
    constant CLASS_CALL     : std_logic_vector(3 downto 0) := x"6";
    constant CLASS_RETURN   : std_logic_vector(3 downto 0) := x"7";
    constant CLASS_PRIV     : std_logic_vector(3 downto 0) := x"8";
    constant CLASS_CONTROL  : std_logic_vector(3 downto 0) := x"9";
    constant CLASS_STRING   : std_logic_vector(3 downto 0) := x"A";
    constant CLASS_SHIFT    : std_logic_vector(3 downto 0) := x"B";

begin

    -- Decode process (combinational)
    process(opcode, opcode2, is_two_byte)
    begin
        -- Defaults
        alu_operation <= ALU_NOP;
        operand_count <= 0;
        inst_class <= CLASS_CONTROL;
        valid <= '0';

        -- Single-byte opcodes
        if is_two_byte = '0' then
            valid <= '1';

            case opcode is
                ------------------------------------------------
                -- MOVE INSTRUCTIONS (0x90-0xDF range)
                ------------------------------------------------
                when x"90" =>  -- MOVB
                    alu_operation <= ALU_MOV;
                    operand_count <= 2;
                    inst_class <= CLASS_MOVE;

                when x"B0" =>  -- MOVW
                    alu_operation <= ALU_MOV;
                    operand_count <= 2;
                    inst_class <= CLASS_MOVE;

                when x"D0" =>  -- MOVL
                    alu_operation <= ALU_MOV;
                    operand_count <= 2;
                    inst_class <= CLASS_MOVE;

                when x"7D" =>  -- MOVQ
                    alu_operation <= ALU_MOV;
                    operand_count <= 2;
                    inst_class <= CLASS_MOVE;

                when x"DD" =>  -- PUSHL
                    alu_operation <= ALU_MOV;
                    operand_count <= 1;
                    inst_class <= CLASS_MOVE;

                when x"94" | x"B4" | x"D4" | x"7C" =>  -- CLR{B,W,L,Q}
                    alu_operation <= ALU_MOV;
                    operand_count <= 1;
                    inst_class <= CLASS_MOVE;

                ------------------------------------------------
                -- ARITHMETIC (2-operand: 0x80-0x8F, 0xA0-0xAF, 0xC0-0xCF)
                ------------------------------------------------
                when x"80" | x"A0" | x"C0" =>  -- ADD{B,W,L}2
                    alu_operation <= ALU_ADD;
                    operand_count <= 2;
                    inst_class <= CLASS_ARITH;

                when x"82" | x"A2" | x"C2" =>  -- SUB{B,W,L}2
                    alu_operation <= ALU_SUB;
                    operand_count <= 2;
                    inst_class <= CLASS_ARITH;

                when x"84" | x"A4" | x"C4" =>  -- MUL{B,W,L}2
                    alu_operation <= ALU_MUL;
                    operand_count <= 2;
                    inst_class <= CLASS_ARITH;

                when x"86" | x"A6" | x"C6" =>  -- DIV{B,W,L}2
                    alu_operation <= ALU_DIV;
                    operand_count <= 2;
                    inst_class <= CLASS_ARITH;

                ------------------------------------------------
                -- ARITHMETIC (3-operand)
                ------------------------------------------------
                when x"81" | x"A1" | x"C1" =>  -- ADD{B,W,L}3
                    alu_operation <= ALU_ADD;
                    operand_count <= 3;
                    inst_class <= CLASS_ARITH;

                when x"83" | x"A3" | x"C3" =>  -- SUB{B,W,L}3
                    alu_operation <= ALU_SUB;
                    operand_count <= 3;
                    inst_class <= CLASS_ARITH;

                when x"85" | x"A5" | x"C5" =>  -- MUL{B,W,L}3
                    alu_operation <= ALU_MUL;
                    operand_count <= 3;
                    inst_class <= CLASS_ARITH;

                when x"87" | x"A7" | x"C7" =>  -- DIV{B,W,L}3
                    alu_operation <= ALU_DIV;
                    operand_count <= 3;
                    inst_class <= CLASS_ARITH;

                ------------------------------------------------
                -- INCREMENT/DECREMENT
                ------------------------------------------------
                when x"96" | x"B6" | x"D6" =>  -- INC{B,W,L}
                    alu_operation <= ALU_ADD;
                    operand_count <= 1;
                    inst_class <= CLASS_ARITH;

                when x"97" | x"B7" | x"D7" =>  -- DEC{B,W,L}
                    alu_operation <= ALU_SUB;
                    operand_count <= 1;
                    inst_class <= CLASS_ARITH;

                ------------------------------------------------
                -- LOGICAL OPERATIONS
                ------------------------------------------------
                when x"88" | x"A8" | x"C8" =>  -- BIS{B,W,L}2 (OR)
                    alu_operation <= ALU_OR;
                    operand_count <= 2;
                    inst_class <= CLASS_LOGICAL;

                when x"8A" | x"AA" | x"CA" =>  -- BIC{B,W,L}2
                    alu_operation <= ALU_BIC;
                    operand_count <= 2;
                    inst_class <= CLASS_LOGICAL;

                when x"8C" | x"AC" | x"CC" =>  -- XOR{B,W,L}2
                    alu_operation <= ALU_XOR;
                    operand_count <= 2;
                    inst_class <= CLASS_LOGICAL;

                ------------------------------------------------
                -- COMPARE AND TEST
                ------------------------------------------------
                when x"91" | x"B1" | x"D1" =>  -- CMP{B,W,L}
                    alu_operation <= ALU_CMP;
                    operand_count <= 2;
                    inst_class <= CLASS_COMPARE;

                when x"95" | x"B5" | x"D5" =>  -- TST{B,W,L}
                    alu_operation <= ALU_TST;
                    operand_count <= 1;
                    inst_class <= CLASS_COMPARE;

                when x"93" | x"B3" | x"D3" =>  -- BIT{B,W,L}
                    alu_operation <= ALU_AND;
                    operand_count <= 2;
                    inst_class <= CLASS_COMPARE;

                ------------------------------------------------
                -- BRANCH INSTRUCTIONS (0x11-0x1F)
                ------------------------------------------------
                when x"11" | x"31" =>  -- BR{B,W}
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"12" =>  -- BNEQ/BNEQU
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"13" =>  -- BEQL/BEQLU
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"14" =>  -- BGTR
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"15" =>  -- BLEQ
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"18" =>  -- BGEQ
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"19" =>  -- BLSS
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"1A" =>  -- BGTRU
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"1B" =>  -- BLEQU
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"1C" =>  -- BVC
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"1D" =>  -- BVS
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"1E" =>  -- BCC/BGEQU
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                when x"1F" =>  -- BCS/BLSSU
                    operand_count <= 0;
                    inst_class <= CLASS_BRANCH;

                ------------------------------------------------
                -- JUMP AND CALL
                ------------------------------------------------
                when x"16" =>  -- JSB
                    operand_count <= 1;
                    inst_class <= CLASS_JUMP;

                when x"17" =>  -- JMP
                    operand_count <= 1;
                    inst_class <= CLASS_JUMP;

                when x"FB" =>  -- CALLS
                    operand_count <= 2;
                    inst_class <= CLASS_CALL;

                when x"FA" =>  -- CALLG
                    operand_count <= 2;
                    inst_class <= CLASS_CALL;

                when x"04" =>  -- RET
                    operand_count <= 0;
                    inst_class <= CLASS_RETURN;

                when x"05" =>  -- RSB
                    operand_count <= 0;
                    inst_class <= CLASS_RETURN;

                ------------------------------------------------
                -- PRIVILEGED
                ------------------------------------------------
                when x"DA" =>  -- MTPR
                    operand_count <= 2;
                    inst_class <= CLASS_PRIV;

                when x"DB" =>  -- MFPR
                    operand_count <= 2;
                    inst_class <= CLASS_PRIV;

                when x"02" =>  -- REI
                    operand_count <= 0;
                    inst_class <= CLASS_PRIV;

                when x"06" =>  -- LDPCTX
                    operand_count <= 0;
                    inst_class <= CLASS_PRIV;

                when x"07" =>  -- SVPCTX
                    operand_count <= 0;
                    inst_class <= CLASS_PRIV;

                ------------------------------------------------
                -- STRING OPERATIONS
                ------------------------------------------------
                when x"28" =>  -- MOVC3
                    operand_count <= 3;
                    inst_class <= CLASS_STRING;

                when x"2C" =>  -- MOVC5
                    operand_count <= 5;
                    inst_class <= CLASS_STRING;

                when x"29" =>  -- CMPC3
                    operand_count <= 3;
                    inst_class <= CLASS_STRING;

                when x"2D" =>  -- CMPC5
                    operand_count <= 5;
                    inst_class <= CLASS_STRING;

                ------------------------------------------------
                -- SHIFT/ROTATE
                ------------------------------------------------
                when x"78" =>  -- ASHL
                    alu_operation <= ALU_ASH;
                    operand_count <= 3;
                    inst_class <= CLASS_SHIFT;

                when x"9C" =>  -- ROTL
                    alu_operation <= ALU_ROT;
                    operand_count <= 3;
                    inst_class <= CLASS_SHIFT;

                ------------------------------------------------
                -- CONTROL
                ------------------------------------------------
                when x"00" =>  -- HALT
                    operand_count <= 0;
                    inst_class <= CLASS_CONTROL;

                when x"01" =>  -- NOP
                    operand_count <= 0;
                    inst_class <= CLASS_CONTROL;

                when x"03" =>  -- BPT (Breakpoint)
                    operand_count <= 0;
                    inst_class <= CLASS_CONTROL;

                when others =>
                    valid <= '0';

            end case;

        else
            -- Two-byte opcodes (FD, FE, FF prefixes)
            -- TODO: Implement extended opcodes
            valid <= '0';
        end if;

    end process;

end rtl;
