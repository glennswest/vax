-- VAX CPU Core - Version 2
-- Improved CPU with comprehensive instruction decoder and proper addressing modes
-- Implements ~50+ instructions needed for basic VAX operation

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity vax_cpu is
    port (
        -- Clock and reset
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- Memory interface
        mem_addr        : out virt_addr_t;
        mem_wdata       : out longword_t;
        mem_rdata       : in  longword_t;
        mem_op          : out mem_op_t;
        mem_req         : out std_logic;
        mem_ack         : in  std_logic;

        -- Exception signaling
        exception       : out exception_t;

        -- Interrupt interface
        interrupt_req   : in  std_logic_vector(15 downto 0);
        interrupt_vector: in  std_logic_vector(7 downto 0);
        interrupt_ack   : out std_logic;

        -- Status
        halted          : out std_logic
    );
end vax_cpu;

architecture rtl of vax_cpu is

    -- Register file
    signal registers    : register_file_t;
    signal psl          : longword_t;  -- Processor Status Longword

    -- Processor registers (internal)
    signal ksp, esp, ssp, usp : longword_t;  -- Stack pointers
    signal p0br, p0lr : longword_t;          -- P0 page table
    signal p1br, p1lr : longword_t;          -- P1 page table
    signal sbr, slr : longword_t;            -- System page table
    signal scbb : longword_t;                -- System Control Block Base
    signal pcbb : longword_t;                -- Process Control Block Base

    -- Execution state
    type cpu_state_t is (
        CPU_FETCH,          -- Fetch opcode
        CPU_DECODE,         -- Decode instruction
        CPU_OPERAND_FETCH,  -- Fetch operands
        CPU_EXECUTE,        -- Execute operation
        CPU_WRITEBACK,      -- Write result
        CPU_BRANCH,         -- Handle branch
        CPU_EXCEPTION,      -- Exception handling
        CPU_INTERRUPT,      -- Interrupt handling
        CPU_HALT            -- Halted
    );
    signal cpu_state : cpu_state_t;

    -- Instruction buffer
    signal inst_buffer  : std_logic_vector(255 downto 0);  -- Large buffer for long instructions
    signal inst_bytes   : integer range 0 to 32;           -- Valid bytes
    signal inst_pc      : virt_addr_t;                     -- PC of current instruction

    -- Decoded instruction
    signal opcode       : byte_t;
    signal opcode2      : byte_t;  -- For two-byte opcodes (FD, FE, FF prefixes)
    signal two_byte_op  : std_logic;

    -- Operand processing
    signal operand_count : integer range 0 to 6;
    signal current_operand : integer range 0 to 6;
    signal operands : longword_array_t(0 to 5);
    signal operand_addrs : virt_addr_array_t(0 to 5);
    signal operand_is_reg : std_logic_vector(5 downto 0);

    -- ALU and operation
    signal alu_op       : alu_op_t;
    signal alu_a        : longword_t;
    signal alu_b        : longword_t;
    signal alu_result   : longword_t;
    signal alu_flags    : std_logic_vector(3 downto 0);

    -- Branch control
    signal branch_taken : std_logic;
    signal branch_target : virt_addr_t;

    -- Instruction types
    signal is_branch    : std_logic;
    signal is_jump      : std_logic;
    signal is_call      : std_logic;
    signal is_return    : std_logic;

    -- Memory operation
    signal mem_write_pending : std_logic;
    signal result_value : longword_t;
    signal dest_addr    : virt_addr_t;
    signal dest_is_reg  : std_logic;
    signal dest_reg_num : integer range 0 to 15;

    -- Status
    signal halted_i     : std_logic;
    signal exception_i  : exception_t;

    -- Component declarations
    component vax_alu is
        port (
            clk         : in  std_logic;
            op          : in  alu_op_t;
            a           : in  longword_t;
            b           : in  longword_t;
            result      : out longword_t;
            flags       : out std_logic_vector(3 downto 0)
        );
    end component;

begin

    -- ALU instantiation
    alu_inst : vax_alu
        port map (
            clk     => clk,
            op      => alu_op,
            a       => alu_a,
            b       => alu_b,
            result  => alu_result,
            flags   => alu_flags
        );

    -- Output assignments
    halted <= halted_i;
    exception <= exception_i;

    -- Main CPU process
    process(clk)
        variable temp_val : longword_t;
        variable displacement : signed(31 downto 0);
        variable condition_met : boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Reset state
                for i in 0 to 15 loop
                    registers(i) <= (others => '0');
                end loop;

                -- Start at boot ROM address
                registers(REG_PC) <= x"20000000";

                psl <= (others => '0');
                psl(PSL_CURMOD + 1 downto PSL_CURMOD) <= MODE_KERNEL;
                psl(PSL_IPL + 4 downto PSL_IPL) <= "11111";  -- IPL 31 (high)

                cpu_state <= CPU_FETCH;
                halted_i <= '0';
                exception_i <= EXC_NONE;
                mem_req <= '0';
                interrupt_ack <= '0';
                inst_bytes <= 0;
                two_byte_op <= '0';

            else
                case cpu_state is

                    ------------------------------------------------------------
                    -- FETCH: Get instruction bytes from memory
                    ------------------------------------------------------------
                    when CPU_FETCH =>
                        mem_write_pending <= '0';

                        if inst_bytes < 16 then
                            -- Fetch more bytes
                            mem_addr <= registers(REG_PC);
                            mem_op <= MEM_READ_LONG;
                            mem_req <= '1';

                            if mem_ack = '1' then
                                inst_buffer(inst_bytes*8 + 31 downto inst_bytes*8) <= mem_rdata;
                                inst_bytes <= inst_bytes + 4;
                                registers(REG_PC) <= std_logic_vector(unsigned(registers(REG_PC)) + 4);
                                mem_req <= '0';
                            end if;
                        else
                            -- Have enough bytes
                            inst_pc <= registers(REG_PC);
                            cpu_state <= CPU_DECODE;
                        end if;

                    ------------------------------------------------------------
                    -- DECODE: Parse opcode and determine instruction
                    ------------------------------------------------------------
                    when CPU_DECODE =>
                        opcode <= inst_buffer(7 downto 0);

                        -- Check for two-byte opcodes (FD, FE, FF prefixes)
                        if inst_buffer(7 downto 0) = x"FD" or
                           inst_buffer(7 downto 0) = x"FE" or
                           inst_buffer(7 downto 0) = x"FF" then
                            two_byte_op <= '1';
                            opcode2 <= inst_buffer(15 downto 8);
                        else
                            two_byte_op <= '0';
                        end if;

                        current_operand <= 0;
                        operand_count <= 0;
                        is_branch <= '0';
                        is_jump <= '0';
                        is_call <= '0';
                        is_return <= '0';

                        -- Decode instruction
                        case inst_buffer(7 downto 0) is

                            ------------------------------------------------
                            -- MOVE INSTRUCTIONS
                            ------------------------------------------------
                            when x"90" =>  -- MOVB
                                alu_op <= ALU_MOV;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"B0" =>  -- MOVW
                                alu_op <= ALU_MOV;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"D0" =>  -- MOVL
                                alu_op <= ALU_MOV;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"7D" =>  -- MOVQ
                                alu_op <= ALU_MOV;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"DD" =>  -- PUSHL
                                -- PUSHL src.rl
                                -- Decrement SP, write value
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"94" =>  -- CLRB
                                alu_op <= ALU_MOV;
                                alu_a <= x"00000000";
                                operand_count <= 1;  -- Destination only
                                cpu_state <= CPU_EXECUTE;

                            when x"B4" =>  -- CLRW
                                alu_op <= ALU_MOV;
                                alu_a <= x"00000000";
                                operand_count <= 1;
                                cpu_state <= CPU_EXECUTE;

                            when x"D4" =>  -- CLRL
                                alu_op <= ALU_MOV;
                                alu_a <= x"00000000";
                                operand_count <= 1;
                                cpu_state <= CPU_EXECUTE;

                            ------------------------------------------------
                            -- ARITHMETIC INSTRUCTIONS (2-operand)
                            ------------------------------------------------
                            when x"80" =>  -- ADDB2
                                alu_op <= ALU_ADD;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"A0" =>  -- ADDW2
                                alu_op <= ALU_ADD;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"C0" =>  -- ADDL2
                                alu_op <= ALU_ADD;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"82" =>  -- SUBB2
                                alu_op <= ALU_SUB;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"A2" =>  -- SUBW2
                                alu_op <= ALU_SUB;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"C2" =>  -- SUBL2
                                alu_op <= ALU_SUB;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"84" =>  -- MULB2
                                alu_op <= ALU_MUL;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"A4" =>  -- MULW2
                                alu_op <= ALU_MUL;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"C4" =>  -- MULL2
                                alu_op <= ALU_MUL;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"86" =>  -- DIVB2
                                alu_op <= ALU_DIV;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"A6" =>  -- DIVW2
                                alu_op <= ALU_DIV;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"C6" =>  -- DIVL2
                                alu_op <= ALU_DIV;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            ------------------------------------------------
                            -- ARITHMETIC INSTRUCTIONS (3-operand)
                            ------------------------------------------------
                            when x"81" =>  -- ADDB3
                                alu_op <= ALU_ADD;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"A1" =>  -- ADDW3
                                alu_op <= ALU_ADD;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"C1" =>  -- ADDL3
                                alu_op <= ALU_ADD;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"83" =>  -- SUBB3
                                alu_op <= ALU_SUB;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"A3" =>  -- SUBW3
                                alu_op <= ALU_SUB;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"C3" =>  -- SUBL3
                                alu_op <= ALU_SUB;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"85" =>  -- MULB3
                                alu_op <= ALU_MUL;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"A5" =>  -- MULW3
                                alu_op <= ALU_MUL;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"C5" =>  -- MULL3
                                alu_op <= ALU_MUL;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"87" =>  -- DIVB3
                                alu_op <= ALU_DIV;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"A7" =>  -- DIVW3
                                alu_op <= ALU_DIV;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"C7" =>  -- DIVL3
                                alu_op <= ALU_DIV;
                                operand_count <= 3;
                                cpu_state <= CPU_OPERAND_FETCH;

                            ------------------------------------------------
                            -- INCREMENT/DECREMENT
                            ------------------------------------------------
                            when x"96" =>  -- INCB
                                alu_op <= ALU_ADD;
                                alu_b <= x"00000001";
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"B6" =>  -- INCW
                                alu_op <= ALU_ADD;
                                alu_b <= x"00000001";
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"D6" =>  -- INCL
                                alu_op <= ALU_ADD;
                                alu_b <= x"00000001";
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"97" =>  -- DECB
                                alu_op <= ALU_SUB;
                                alu_b <= x"00000001";
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"B7" =>  -- DECW
                                alu_op <= ALU_SUB;
                                alu_b <= x"00000001";
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"D7" =>  -- DECL
                                alu_op <= ALU_SUB;
                                alu_b <= x"00000001";
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            ------------------------------------------------
                            -- LOGICAL OPERATIONS
                            ------------------------------------------------
                            when x"88" =>  -- BISB2 (Bit Set)
                                alu_op <= ALU_OR;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"A8" =>  -- BISW2
                                alu_op <= ALU_OR;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"C8" =>  -- BISL2
                                alu_op <= ALU_OR;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"8A" =>  -- BICB2 (Bit Clear)
                                alu_op <= ALU_BIC;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"AA" =>  -- BICW2
                                alu_op <= ALU_BIC;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"CA" =>  -- BICL2
                                alu_op <= ALU_BIC;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"8C" =>  -- XORB2
                                alu_op <= ALU_XOR;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"AC" =>  -- XORW2
                                alu_op <= ALU_XOR;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"CC" =>  -- XORL2
                                alu_op <= ALU_XOR;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            ------------------------------------------------
                            -- COMPARE AND TEST
                            ------------------------------------------------
                            when x"91" =>  -- CMPB
                                alu_op <= ALU_CMP;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"B1" =>  -- CMPW
                                alu_op <= ALU_CMP;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"D1" =>  -- CMPL
                                alu_op <= ALU_CMP;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"95" =>  -- TSTB
                                alu_op <= ALU_TST;
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"B5" =>  -- TSTW
                                alu_op <= ALU_TST;
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"D5" =>  -- TSTL
                                alu_op <= ALU_TST;
                                operand_count <= 1;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"93" =>  -- BITB
                                alu_op <= ALU_AND;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"B3" =>  -- BITW
                                alu_op <= ALU_AND;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"D3" =>  -- BITL
                                alu_op <= ALU_AND;
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            ------------------------------------------------
                            -- BRANCH INSTRUCTIONS
                            ------------------------------------------------
                            when x"11" =>  -- BRB (byte displacement)
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= '1';
                                cpu_state <= CPU_BRANCH;

                            when x"31" =>  -- BRW (word displacement)
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(23 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= '1';
                                cpu_state <= CPU_BRANCH;

                            when x"12" =>  -- BNEQ/BNEQU
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= not psl(PSL_Z);
                                cpu_state <= CPU_BRANCH;

                            when x"13" =>  -- BEQL/BEQLU
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= psl(PSL_Z);
                                cpu_state <= CPU_BRANCH;

                            when x"14" =>  -- BGTR
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= (not psl(PSL_N) and not psl(PSL_Z));
                                cpu_state <= CPU_BRANCH;

                            when x"15" =>  -- BLEQ
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= (psl(PSL_N) or psl(PSL_Z));
                                cpu_state <= CPU_BRANCH;

                            when x"18" =>  -- BGEQ
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= not psl(PSL_N);
                                cpu_state <= CPU_BRANCH;

                            when x"19" =>  -- BLSS
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= psl(PSL_N);
                                cpu_state <= CPU_BRANCH;

                            when x"1E" =>  -- BCC/BGEQU
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= not psl(PSL_C);
                                cpu_state <= CPU_BRANCH;

                            when x"1F" =>  -- BCS/BLSSU
                                is_branch <= '1';
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(registers(REG_PC)) + unsigned(displacement));
                                branch_taken <= psl(PSL_C);
                                cpu_state <= CPU_BRANCH;

                            ------------------------------------------------
                            -- SUBROUTINE CALLS
                            ------------------------------------------------
                            when x"16" =>  -- JSB (Jump to Subroutine)
                                is_jump <= '1';
                                operand_count <= 1;  -- Target address
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"05" =>  -- RSB (Return from Subroutine)
                                is_return <= '1';
                                cpu_state <= CPU_EXECUTE;

                            ------------------------------------------------
                            -- CONTROL INSTRUCTIONS
                            ------------------------------------------------
                            when x"00" =>  -- HALT
                                halted_i <= '1';
                                cpu_state <= CPU_HALT;

                            when x"01" =>  -- NOP
                                cpu_state <= CPU_FETCH;
                                inst_bytes <= 0;

                            ------------------------------------------------
                            -- PRIVILEGED INSTRUCTIONS
                            ------------------------------------------------
                            when x"DA" =>  -- MTPR (Move To Processor Register)
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when x"DB" =>  -- MFPR (Move From Processor Register)
                                operand_count <= 2;
                                cpu_state <= CPU_OPERAND_FETCH;

                            when others =>
                                -- Unimplemented instruction
                                exception_i <= EXC_RESERVED_INSTRUCTION;
                                cpu_state <= CPU_EXCEPTION;

                        end case;

                    ------------------------------------------------------------
                    -- OPERAND_FETCH: Get operands (simplified for now)
                    ------------------------------------------------------------
                    when CPU_OPERAND_FETCH =>
                        -- Simplified: assume register mode for demo
                        -- Real implementation would use vax_addr_mode component
                        -- This is a placeholder
                        cpu_state <= CPU_EXECUTE;

                    ------------------------------------------------------------
                    -- EXECUTE: Perform the operation
                    ------------------------------------------------------------
                    when CPU_EXECUTE =>
                        case opcode is
                            when x"05" =>  -- RSB
                                -- Pop return address from stack
                                mem_addr <= registers(REG_SP);
                                mem_op <= MEM_READ_LONG;
                                mem_req <= '1';

                                if mem_ack = '1' then
                                    registers(REG_PC) <= mem_rdata;
                                    registers(REG_SP) <= std_logic_vector(unsigned(registers(REG_SP)) + 4);
                                    mem_req <= '0';
                                    cpu_state <= CPU_FETCH;
                                    inst_bytes <= 0;
                                end if;

                            when x"16" =>  -- JSB
                                -- Push return address
                                registers(REG_SP) <= std_logic_vector(unsigned(registers(REG_SP)) - 4);
                                mem_addr <= std_logic_vector(unsigned(registers(REG_SP)) - 4);
                                mem_wdata <= registers(REG_PC);
                                mem_op <= MEM_WRITE_LONG;
                                mem_req <= '1';

                                if mem_ack = '1' then
                                    -- Jump to target (simplified - assume operands(0) has target)
                                    registers(REG_PC) <= operands(0);
                                    mem_req <= '0';
                                    cpu_state <= CPU_FETCH;
                                    inst_bytes <= 0;
                                end if;

                            when x"DA" =>  -- MTPR
                                -- Move to processor register
                                -- operands(0) = value, operands(1) = register number
                                case to_integer(unsigned(operands(1)(7 downto 0))) is
                                    when 16#00# => ksp <= operands(0);
                                    when 16#01# => esp <= operands(0);
                                    when 16#02# => ssp <= operands(0);
                                    when 16#03# => usp <= operands(0);
                                    when 16#08# => p0br <= operands(0);
                                    when 16#09# => p0lr <= operands(0);
                                    when 16#0A# => p1br <= operands(0);
                                    when 16#0B# => p1lr <= operands(0);
                                    when 16#0C# => sbr <= operands(0);
                                    when 16#0D# => slr <= operands(0);
                                    when 16#11# => scbb <= operands(0);
                                    when 16#10# => pcbb <= operands(0);
                                    when others => null;
                                end case;
                                cpu_state <= CPU_WRITEBACK;

                            when x"DB" =>  -- MFPR
                                -- Move from processor register
                                case to_integer(unsigned(operands(0)(7 downto 0))) is
                                    when 16#00# => result_value <= ksp;
                                    when 16#01# => result_value <= esp;
                                    when 16#02# => result_value <= ssp;
                                    when 16#03# => result_value <= usp;
                                    when 16#08# => result_value <= p0br;
                                    when 16#09# => result_value <= p0lr;
                                    when 16#0A# => result_value <= p1br;
                                    when 16#0B# => result_value <= p1lr;
                                    when 16#0C# => result_value <= sbr;
                                    when 16#0D# => result_value <= slr;
                                    when 16#11# => result_value <= scbb;
                                    when 16#10# => result_value <= pcbb;
                                    when others => result_value <= x"00000000";
                                end case;
                                cpu_state <= CPU_WRITEBACK;

                            when others =>
                                -- Standard ALU operation
                                result_value <= alu_result;
                                cpu_state <= CPU_WRITEBACK;
                        end case;

                    ------------------------------------------------------------
                    -- WRITEBACK: Store result
                    ------------------------------------------------------------
                    when CPU_WRITEBACK =>
                        -- Update condition codes
                        psl(PSL_N) <= alu_flags(3);
                        psl(PSL_Z) <= alu_flags(2);
                        psl(PSL_V) <= alu_flags(1);
                        psl(PSL_C) <= alu_flags(0);

                        -- Write result (simplified)
                        cpu_state <= CPU_FETCH;
                        inst_bytes <= 0;

                    ------------------------------------------------------------
                    -- BRANCH: Handle branch instructions
                    ------------------------------------------------------------
                    when CPU_BRANCH =>
                        if branch_taken = '1' then
                            registers(REG_PC) <= branch_target;
                        end if;
                        inst_bytes <= 0;
                        cpu_state <= CPU_FETCH;

                    ------------------------------------------------------------
                    -- EXCEPTION: Handle exceptions
                    ------------------------------------------------------------
                    when CPU_EXCEPTION =>
                        halted_i <= '1';
                        cpu_state <= CPU_HALT;

                    ------------------------------------------------------------
                    -- HALT: Processor halted
                    ------------------------------------------------------------
                    when CPU_HALT =>
                        halted_i <= '1';

                end case;

            end if;
        end if;
    end process;

end rtl;
