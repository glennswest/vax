-- VAX CPU Core
-- Main CPU execution engine with register file, instruction decoder, and execution units

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

    -- Execution state
    signal exec_state   : exec_state_t;
    signal next_state   : exec_state_t;

    -- Instruction fetch
    signal inst_buffer  : std_logic_vector(127 downto 0);  -- Instruction buffer
    signal inst_valid   : integer range 0 to 16;           -- Valid bytes in buffer
    signal inst_ptr     : integer range 0 to 15;           -- Current byte being decoded
    signal opcode       : byte_t;
    signal opcode_valid : std_logic;

    -- Decoded instruction
    signal alu_op       : alu_op_t;
    signal operand_count: integer range 0 to 6;
    signal operands     : array(0 to 5) of longword_t;
    signal dest_reg     : integer range 0 to 15;
    signal use_dest_reg : std_logic;

    -- ALU signals
    signal alu_a        : longword_t;
    signal alu_b        : longword_t;
    signal alu_result   : longword_t;
    signal alu_flags    : std_logic_vector(3 downto 0);  -- N, Z, V, C

    -- Internal signals
    signal pc_next      : virt_addr_t;
    signal halted_i     : std_logic;
    signal exception_i  : exception_t;

    -- Component declaration
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

    -- Main execution state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Reset state
                for i in 0 to 15 loop
                    registers(i) <= (others => '0');
                end loop;
                psl <= (others => '0');
                psl(PSL_CURMOD + 1 downto PSL_CURMOD) <= MODE_KERNEL;
                exec_state <= EXEC_FETCH;
                halted_i <= '0';
                exception_i <= EXC_NONE;
                inst_valid <= 0;
                inst_ptr <= 0;
                opcode_valid <= '0';
                mem_req <= '0';
                interrupt_ack <= '0';

            else
                case exec_state is

                    when EXEC_FETCH =>
                        -- Fetch instruction bytes from memory
                        if inst_valid < 8 then
                            -- Need more instruction bytes
                            mem_addr <= registers(REG_PC);
                            mem_op <= MEM_READ_LONG;
                            mem_req <= '1';

                            if mem_req = '1' and mem_ack = '1' then
                                -- Received data from memory
                                inst_buffer(inst_valid*8 + 31 downto inst_valid*8) <= mem_rdata;
                                inst_valid <= inst_valid + 4;
                                registers(REG_PC) <= std_logic_vector(unsigned(registers(REG_PC)) + 4);
                                mem_req <= '0';
                            end if;
                        else
                            -- Have enough bytes to start decode
                            exec_state <= EXEC_DECODE;
                        end if;

                    when EXEC_DECODE =>
                        -- Decode the opcode
                        if opcode_valid = '0' then
                            opcode <= inst_buffer(7 downto 0);
                            opcode_valid <= '1';
                            inst_ptr <= 1;
                        else
                            -- Simplified decoder for demonstration
                            -- Real VAX decoder is very complex due to variable-length instructions
                            -- and complex addressing modes
                            case opcode is
                                when x"D0" =>  -- MOVL
                                    alu_op <= ALU_MOV;
                                    operand_count <= 2;
                                    exec_state <= EXEC_OPERAND;

                                when x"C0" =>  -- ADDL
                                    alu_op <= ALU_ADD;
                                    operand_count <= 3;
                                    exec_state <= EXEC_OPERAND;

                                when x"C2" =>  -- SUBL
                                    alu_op <= ALU_SUB;
                                    operand_count <= 3;
                                    exec_state <= EXEC_OPERAND;

                                when x"C4" =>  -- MULL
                                    alu_op <= ALU_MUL;
                                    operand_count <= 3;
                                    exec_state <= EXEC_OPERAND;

                                when x"91" =>  -- CMPL
                                    alu_op <= ALU_CMP;
                                    operand_count <= 2;
                                    exec_state <= EXEC_OPERAND;

                                when x"00" =>  -- HALT
                                    halted_i <= '1';
                                    exec_state <= EXEC_FETCH;

                                when others =>
                                    -- Reserved/unimplemented instruction
                                    exception_i <= EXC_RESERVED_INSTRUCTION;
                                    exec_state <= EXEC_EXCEPTION;
                            end case;
                        end if;

                    when EXEC_OPERAND =>
                        -- Fetch operands based on addressing modes
                        -- This is highly simplified; real VAX has 16 addressing modes
                        -- For now, assume operands are in registers
                        -- TODO: Implement full addressing mode parser
                        exec_state <= EXEC_EXECUTE;

                    when EXEC_EXECUTE =>
                        -- Execute the operation using ALU
                        -- ALU operates in this cycle
                        exec_state <= EXEC_WRITEBACK;

                    when EXEC_WRITEBACK =>
                        -- Write results back to registers
                        if use_dest_reg = '1' then
                            registers(dest_reg) <= alu_result;
                        end if;

                        -- Update condition codes
                        psl(PSL_N) <= alu_flags(3);  -- Negative
                        psl(PSL_Z) <= alu_flags(2);  -- Zero
                        psl(PSL_V) <= alu_flags(1);  -- Overflow
                        psl(PSL_C) <= alu_flags(0);  -- Carry

                        -- Clear instruction buffer for next instruction
                        inst_valid <= 0;
                        inst_ptr <= 0;
                        opcode_valid <= '0';

                        exec_state <= EXEC_FETCH;

                    when EXEC_EXCEPTION =>
                        -- Handle exception
                        -- TODO: Implement full exception handling
                        -- For now, just halt
                        halted_i <= '1';
                        exec_state <= EXEC_FETCH;

                end case;

                -- Check for interrupts
                if interrupt_req /= x"0000" and exec_state = EXEC_FETCH then
                    -- Handle interrupt
                    -- TODO: Implement interrupt handling
                    interrupt_ack <= '1';
                else
                    interrupt_ack <= '0';
                end if;

            end if;
        end if;
    end process;

end rtl;
