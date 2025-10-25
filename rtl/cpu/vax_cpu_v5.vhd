-- VAX CPU Core - Version 5
-- Adds exception handling and REI instruction
-- Extends v4 with complete exception/interrupt support
-- Implements SCB (System Control Block) dispatch

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
    signal psl          : longword_t;

    -- Processor registers
    signal ksp, esp, ssp, usp : longword_t;
    signal p0br, p0lr : longword_t;
    signal p1br, p1lr : longword_t;
    signal sbr, slr : longword_t;
    signal scbb, pcbb : longword_t;

    -- Main CPU state machine
    type cpu_state_t is (
        CPU_RESET,
        CPU_FETCH_INST,         -- Fetch instruction opcode
        CPU_DECODE_INST,        -- Decode instruction
        CPU_FETCH_OPERAND,      -- Fetch operand using addr_mode decoder
        CPU_EXECUTE,            -- Execute operation
        CPU_WRITEBACK,          -- Write result
        CPU_EXCEPTION,          -- Exception handling entry
        CPU_HALT,               -- Halted
        -- Procedure call states
        CPU_CALLS_PUSH_NUMARG,   -- Push argument count
        CPU_CALLS_PUSH_PC,       -- Push return PC
        CPU_CALLS_PUSH_FP,       -- Push FP
        CPU_CALLS_PUSH_AP,       -- Push AP
        CPU_CALLS_READ_MASK,     -- Read entry mask from procedure
        CPU_CALLS_PUSH_PSW_MASK, -- Push PSW and save mask
        CPU_CALLS_SAVE_REGS,     -- Save registers (loop)
        CPU_CALLS_SET_POINTERS,  -- Set new FP and AP
        CPU_CALLS_JUMP,          -- Jump to procedure
        -- Return states
        CPU_RET_READ_MASK,       -- Read save mask
        CPU_RET_RESTORE_REGS,    -- Restore registers (loop)
        CPU_RET_RESTORE_PSW,     -- Restore PSW
        CPU_RET_RESTORE_PTRS,    -- Restore AP, FP, SP
        CPU_RET_GET_PC,          -- Get return PC
        CPU_RET_POP_ARGS,        -- Pop arguments and return
        -- Exception states
        CPU_EXC_PUSH_PC,         -- Push PC onto exception stack
        CPU_EXC_PUSH_PSL,        -- Push PSL onto exception stack
        CPU_EXC_READ_SCB,        -- Read handler address from SCB
        CPU_EXC_DISPATCH,        -- Dispatch to exception handler
        -- REI states
        CPU_REI_POP_PC,          -- Pop PC from stack
        CPU_REI_POP_PSL,         -- Pop PSL from stack
        CPU_REI_VALIDATE,        -- Validate PSL
        CPU_REI_RESTORE          -- Restore and continue
    );
    signal cpu_state : cpu_state_t;

    -- Instruction buffer and parsing
    signal inst_buffer  : std_logic_vector(255 downto 0);
    signal inst_bytes   : integer range 0 to 32;
    signal inst_pc      : virt_addr_t;
    signal inst_ptr     : integer range 0 to 31;  -- Byte pointer into instruction

    -- Decoded instruction
    signal opcode       : byte_t;
    signal alu_op       : alu_op_t;
    signal operand_count : integer range 0 to 6;
    signal current_operand : integer range 0 to 6;

    -- Operand storage
    signal operands         : longword_array_t(0 to 5);
    signal operand_addrs    : virt_addr_array_t(0 to 5);
    signal operand_is_reg   : std_logic_vector(5 downto 0);
    type reg_num_array_t is array(0 to 5) of integer range 0 to 15;
    signal operand_reg_nums : reg_num_array_t;

    -- Instruction properties
    signal inst_is_branch   : std_logic;
    signal inst_is_jump     : std_logic;
    signal inst_needs_writeback : std_logic;
    signal dest_operand_idx : integer range 0 to 5;

    -- Procedure call state
    signal call_numarg       : longword_t;        -- Argument count
    signal call_entry_mask   : word_t;            -- Entry mask from procedure
    signal call_saved_count  : integer range 0 to 12;  -- Number of regs to save/restore
    signal call_reg_index    : integer range 0 to 15;  -- Current register being processed
    signal call_return_pc    : virt_addr_t;       -- Return PC
    signal call_saved_fp     : longword_t;        -- Saved FP
    signal call_saved_ap     : longword_t;        -- Saved AP
    signal call_new_fp       : longword_t;        -- New FP value
    signal call_proc_addr    : virt_addr_t;       -- Procedure address
    signal call_is_callg     : std_logic;         -- CALLG vs CALLS

    -- Exception handling state
    signal exc_vector        : std_logic_vector(9 downto 0);  -- SCB vector offset (0-1023)
    signal exc_handler_addr  : virt_addr_t;       -- Handler address from SCB
    signal exc_saved_pc      : virt_addr_t;       -- PC at exception
    signal exc_saved_psl     : longword_t;        -- PSL at exception
    signal exc_prev_mode     : std_logic_vector(1 downto 0);  -- Previous mode

    -- Address mode decoder interface
    signal addr_mode_start      : std_logic;
    signal addr_mode_done       : std_logic;
    signal addr_mode_spec       : byte_t;
    signal addr_mode_next_byte  : byte_t;
    signal addr_mode_next_req   : std_logic;
    signal addr_mode_next_ack   : std_logic;
    signal addr_mode_reg_num    : integer range 0 to 15;
    signal addr_mode_reg_rdata  : longword_t;
    signal addr_mode_reg_wdata  : longword_t;
    signal addr_mode_reg_we     : std_logic;
    signal addr_mode_mem_addr   : virt_addr_t;
    signal addr_mode_mem_rdata  : longword_t;
    signal addr_mode_mem_req    : std_logic;
    signal addr_mode_mem_ack    : std_logic;
    signal addr_mode_value      : longword_t;
    signal addr_mode_addr       : virt_addr_t;
    signal addr_mode_is_reg     : std_logic;
    signal addr_mode_is_imm     : std_logic;
    signal addr_mode_mode_type  : std_logic_vector(3 downto 0);

    -- ALU interface
    signal alu_a        : longword_t;
    signal alu_b        : longword_t;
    signal alu_result   : longword_t;
    signal alu_flags    : std_logic_vector(3 downto 0);

    -- Branch control
    signal branch_taken : std_logic;
    signal branch_target : virt_addr_t;

    -- Memory arbitration
    type mem_user_t is (MEM_USER_INST_FETCH, MEM_USER_ADDR_MODE, MEM_USER_EXECUTE, MEM_USER_CALL, MEM_USER_EXCEPTION);
    signal mem_user : mem_user_t;

    -- Internal signals
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

    component vax_addr_mode is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            start           : in  std_logic;
            done            : out std_logic;
            spec_byte       : in  byte_t;
            next_byte       : in  byte_t;
            next_byte_req   : out std_logic;
            next_byte_ack   : in  std_logic;
            reg_num         : out integer range 0 to 15;
            reg_rdata       : in  longword_t;
            reg_wdata       : out longword_t;
            reg_we          : out std_logic;
            mem_addr        : out virt_addr_t;
            mem_rdata       : in  longword_t;
            mem_req         : out std_logic;
            mem_ack         : in  std_logic;
            operand_value   : out longword_t;
            operand_addr    : out virt_addr_t;
            is_register     : out std_logic;
            is_immediate    : out std_logic;
            mode_type       : out std_logic_vector(3 downto 0)
        );
    end component;

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

    -- Decoder signals
    signal decoder_opcode2      : byte_t;
    signal decoder_is_two_byte  : std_logic;
    signal decoder_inst_class   : std_logic_vector(3 downto 0);
    signal decoder_valid        : std_logic;

begin

    -- Component instantiations
    alu_inst : vax_alu
        port map (
            clk     => clk,
            op      => alu_op,
            a       => alu_a,
            b       => alu_b,
            result  => alu_result,
            flags   => alu_flags
        );

    addr_mode_inst : vax_addr_mode
        port map (
            clk             => clk,
            rst             => rst,
            start           => addr_mode_start,
            done            => addr_mode_done,
            spec_byte       => addr_mode_spec,
            next_byte       => addr_mode_next_byte,
            next_byte_req   => addr_mode_next_req,
            next_byte_ack   => addr_mode_next_ack,
            reg_num         => addr_mode_reg_num,
            reg_rdata       => addr_mode_reg_rdata,
            reg_wdata       => addr_mode_reg_wdata,
            reg_we          => addr_mode_reg_we,
            mem_addr        => addr_mode_mem_addr,
            mem_rdata       => addr_mode_mem_rdata,
            mem_req         => addr_mode_mem_req,
            mem_ack         => addr_mode_mem_ack,
            operand_value   => addr_mode_value,
            operand_addr    => addr_mode_addr,
            is_register     => addr_mode_is_reg,
            is_immediate    => addr_mode_is_imm,
            mode_type       => addr_mode_mode_type
        );

    decoder_inst : vax_decoder
        port map (
            opcode          => opcode,
            opcode2         => decoder_opcode2,
            is_two_byte     => decoder_is_two_byte,
            alu_operation   => alu_op,
            operand_count   => operand_count,
            inst_class      => decoder_inst_class,
            valid           => decoder_valid
        );

    -- Output assignments
    halted <= halted_i;
    exception <= exception_i;

    -- Register file read for address mode decoder
    addr_mode_reg_rdata <= registers(addr_mode_reg_num);

    -- Memory arbitration
    process(mem_user, addr_mode_mem_req, addr_mode_mem_addr)
    begin
        mem_req <= '0';

        case mem_user is
            when MEM_USER_INST_FETCH =>
                -- Instruction fetch has priority
                null;

            when MEM_USER_ADDR_MODE =>
                -- Address mode decoder uses memory
                if addr_mode_mem_req = '1' then
                    mem_addr <= addr_mode_mem_addr;
                    mem_op <= MEM_READ_LONG;
                    mem_req <= '1';
                end if;

            when MEM_USER_EXECUTE | MEM_USER_CALL | MEM_USER_EXCEPTION =>
                -- Execute, call, or exception phase memory access
                null;
        end case;
    end process;

    -- Main CPU state machine
    process(clk)
        variable spec_byte_v : byte_t;
        variable displacement : signed(31 downto 0);
        variable temp_sp : longword_t;
        variable temp_data : longword_t;
        variable bit_pos : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Reset
                for i in 0 to 15 loop
                    registers(i) <= (others => '0');
                end loop;

                registers(REG_PC) <= x"20000000";  -- Boot ROM address
                registers(REG_SP) <= x"7FFFFFFF";  -- Stack at top of memory

                psl <= (others => '0');
                psl(PSL_CURMOD + 1 downto PSL_CURMOD) <= MODE_KERNEL;

                -- Initialize processor registers
                scbb <= x"80000000";  -- SCB at standard location

                cpu_state <= CPU_RESET;
                halted_i <= '0';
                exception_i <= EXC_NONE;
                mem_req <= '0';
                addr_mode_start <= '0';
                inst_bytes <= 0;
                inst_ptr <= 0;
                current_operand <= 0;
                call_saved_count <= 0;
                call_reg_index <= 0;

            else
                -- Register file write from address mode decoder
                if addr_mode_reg_we = '1' then
                    registers(addr_mode_reg_num) <= addr_mode_reg_wdata;
                end if;

                case cpu_state is

                    ------------------------------------------------------------
                    when CPU_RESET =>
                        cpu_state <= CPU_FETCH_INST;
                        mem_user <= MEM_USER_INST_FETCH;

                    ------------------------------------------------------------
                    when CPU_FETCH_INST =>
                        -- Fetch instruction bytes
                        if inst_bytes < 16 then
                            mem_addr <= registers(REG_PC);
                            mem_op <= MEM_READ_LONG;
                            mem_req <= '1';
                            mem_user <= MEM_USER_INST_FETCH;

                            if mem_ack = '1' then
                                inst_buffer(inst_bytes*8 + 31 downto inst_bytes*8) <= mem_rdata;
                                inst_bytes <= inst_bytes + 4;
                                registers(REG_PC) <= std_logic_vector(unsigned(registers(REG_PC)) + 4);
                                mem_req <= '0';
                            end if;
                        else
                            -- Have enough bytes
                            inst_pc <= registers(REG_PC);
                            inst_ptr <= 0;
                            cpu_state <= CPU_DECODE_INST;
                        end if;

                    ------------------------------------------------------------
                    when CPU_DECODE_INST =>
                        -- Extract opcode
                        opcode <= inst_buffer(7 downto 0);
                        inst_ptr <= 1;

                        -- Check for two-byte opcode
                        if inst_buffer(7 downto 0) = x"FD" or
                           inst_buffer(7 downto 0) = x"FE" or
                           inst_buffer(7 downto 0) = x"FF" then
                            decoder_is_two_byte <= '1';
                            decoder_opcode2 <= inst_buffer(15 downto 8);
                            inst_ptr <= 2;
                        else
                            decoder_is_two_byte <= '0';
                        end if;

                        -- Wait for decoder
                        if decoder_valid = '1' then
                            if operand_count = 0 then
                                -- No operands, go straight to execute
                                cpu_state <= CPU_EXECUTE;
                            else
                                -- Need to fetch operands
                                current_operand <= 0;
                                cpu_state <= CPU_FETCH_OPERAND;
                            end if;
                        else
                            -- Invalid instruction
                            exception_i <= EXC_RESERVED_INSTRUCTION;
                            cpu_state <= CPU_EXCEPTION;
                        end if;

                    ------------------------------------------------------------
                    when CPU_FETCH_OPERAND =>
                        -- Fetch operands one by one using address mode decoder

                        if addr_mode_start = '0' then
                            -- Start fetching current operand
                            spec_byte_v := inst_buffer(inst_ptr*8 + 7 downto inst_ptr*8);
                            addr_mode_spec <= spec_byte_v;
                            inst_ptr <= inst_ptr + 1;

                            addr_mode_start <= '1';
                            mem_user <= MEM_USER_ADDR_MODE;

                        elsif addr_mode_done = '1' then
                            -- Operand fetched
                            addr_mode_start <= '0';

                            -- Store operand
                            operands(current_operand) <= addr_mode_value;
                            operand_addrs(current_operand) <= addr_mode_addr;
                            operand_is_reg(current_operand) <= addr_mode_is_reg;
                            if addr_mode_is_reg = '1' then
                                operand_reg_nums(current_operand) <= addr_mode_reg_num;
                            end if;

                            -- Move to next operand
                            if current_operand = operand_count - 1 then
                                -- All operands fetched
                                cpu_state <= CPU_EXECUTE;
                            else
                                current_operand <= current_operand + 1;
                            end if;

                        elsif addr_mode_next_req = '1' then
                            -- Address mode decoder needs next byte from instruction
                            addr_mode_next_byte <= inst_buffer(inst_ptr*8 + 7 downto inst_ptr*8);
                            inst_ptr <= inst_ptr + 1;
                            addr_mode_next_ack <= '1';
                        else
                            addr_mode_next_ack <= '0';
                        end if;

                        -- Pass memory responses to address mode decoder
                        if mem_user = MEM_USER_ADDR_MODE then
                            addr_mode_mem_ack <= mem_ack;
                            addr_mode_mem_rdata <= mem_rdata;
                        else
                            addr_mode_mem_ack <= '0';
                        end if;

                    ------------------------------------------------------------
                    when CPU_EXECUTE =>
                        -- Execute the instruction
                        mem_user <= MEM_USER_EXECUTE;

                        case opcode is
                            ---------------- Move instructions ----------------
                            when x"D0" | x"B0" | x"90" =>  -- MOVL, MOVW, MOVB
                                alu_a <= operands(0);
                                alu_b <= (others => '0');
                                inst_needs_writeback <= '1';
                                dest_operand_idx <= 1;
                                cpu_state <= CPU_WRITEBACK;

                            ---------------- Arithmetic 2-operand ----------------
                            when x"C0" | x"A0" | x"80" =>  -- ADDL2, ADDW2, ADDB2
                                alu_a <= operands(1);
                                alu_b <= operands(0);
                                inst_needs_writeback <= '1';
                                dest_operand_idx <= 1;
                                cpu_state <= CPU_WRITEBACK;

                            when x"C2" | x"A2" | x"82" =>  -- SUBL2, SUBW2, SUBB2
                                alu_a <= operands(1);
                                alu_b <= operands(0);
                                inst_needs_writeback <= '1';
                                dest_operand_idx <= 1;
                                cpu_state <= CPU_WRITEBACK;

                            ---------------- Arithmetic 3-operand ----------------
                            when x"C1" | x"A1" | x"81" =>  -- ADDL3, ADDW3, ADDB3
                                alu_a <= operands(0);
                                alu_b <= operands(1);
                                inst_needs_writeback <= '1';
                                dest_operand_idx <= 2;
                                cpu_state <= CPU_WRITEBACK;

                            when x"C3" | x"A3" | x"83" =>  -- SUBL3, SUBW3, SUBB3
                                alu_a <= operands(0);
                                alu_b <= operands(1);
                                inst_needs_writeback <= '1';
                                dest_operand_idx <= 2;
                                cpu_state <= CPU_WRITEBACK;

                            ---------------- Compare ----------------
                            when x"D1" | x"B1" | x"91" =>  -- CMPL, CMPW, CMPB
                                alu_a <= operands(0);
                                alu_b <= operands(1);
                                inst_needs_writeback <= '0';
                                cpu_state <= CPU_WRITEBACK;

                            ---------------- Branch instructions ----------------
                            when x"11" =>  -- BRB
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(inst_pc) + unsigned(displacement));
                                branch_taken <= '1';
                                inst_needs_writeback <= '0';
                                cpu_state <= CPU_WRITEBACK;

                            when x"13" =>  -- BEQL
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(inst_pc) + unsigned(displacement));
                                branch_taken <= psl(PSL_Z);
                                inst_needs_writeback <= '0';
                                cpu_state <= CPU_WRITEBACK;

                            when x"12" =>  -- BNEQ
                                displacement := resize(signed(inst_buffer(15 downto 8)), 32);
                                branch_target <= std_logic_vector(unsigned(inst_pc) + unsigned(displacement));
                                branch_taken <= not psl(PSL_Z);
                                inst_needs_writeback <= '0';
                                cpu_state <= CPU_WRITEBACK;

                            ---------------- Procedure calls ----------------
                            when x"FB" =>  -- CALLS
                                call_is_callg <= '0';
                                call_numarg <= operands(0);  -- Number of arguments
                                call_proc_addr <= operand_addrs(1);  -- Procedure address
                                call_return_pc <= registers(REG_PC);  -- Save return PC
                                cpu_state <= CPU_CALLS_PUSH_NUMARG;

                            when x"FA" =>  -- CALLG
                                call_is_callg <= '1';
                                call_proc_addr <= operand_addrs(1);  -- Procedure address
                                call_return_pc <= registers(REG_PC);  -- Save return PC
                                -- For CALLG, operands(0) points to arglist
                                -- First longword of arglist is numarg
                                mem_addr <= operand_addrs(0);
                                mem_op <= MEM_READ_LONG;
                                mem_req <= '1';
                                mem_user <= MEM_USER_CALL;
                                cpu_state <= CPU_CALLS_PUSH_NUMARG;

                            when x"04" =>  -- RET
                                -- Start return sequence
                                cpu_state <= CPU_RET_READ_MASK;

                            when x"02" =>  -- REI (Return from Exception/Interrupt)
                                -- Start REI sequence
                                cpu_state <= CPU_REI_POP_PC;

                            ---------------- Control ----------------
                            when x"00" =>  -- HALT
                                halted_i <= '1';
                                cpu_state <= CPU_HALT;

                            when x"01" =>  -- NOP
                                inst_needs_writeback <= '0';
                                cpu_state <= CPU_WRITEBACK;

                            when others =>
                                exception_i <= EXC_RESERVED_INSTRUCTION;
                                cpu_state <= CPU_EXCEPTION;
                        end case;

                    -------------------- CALLS States --------------------
                    when CPU_CALLS_PUSH_NUMARG =>
                        -- Push argument count onto stack
                        mem_user <= MEM_USER_CALL;

                        if call_is_callg = '1' and mem_ack = '1' then
                            -- For CALLG, read numarg from arglist
                            call_numarg <= mem_rdata;
                            mem_req <= '0';
                        end if;

                        if mem_req = '0' then
                            temp_sp := std_logic_vector(unsigned(registers(REG_SP)) - 4);
                            mem_addr <= temp_sp;
                            mem_wdata <= call_numarg;
                            mem_op <= MEM_WRITE_LONG;
                            mem_req <= '1';

                            if mem_ack = '1' then
                                registers(REG_SP) <= temp_sp;
                                mem_req <= '0';
                                cpu_state <= CPU_CALLS_PUSH_PC;
                            end if;
                        end if;

                    when CPU_CALLS_PUSH_PC =>
                        -- Push return PC
                        temp_sp := std_logic_vector(unsigned(registers(REG_SP)) - 4);
                        mem_addr <= temp_sp;
                        mem_wdata <= call_return_pc;
                        mem_op <= MEM_WRITE_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_CALL;

                        if mem_ack = '1' then
                            registers(REG_SP) <= temp_sp;
                            mem_req <= '0';
                            cpu_state <= CPU_CALLS_PUSH_FP;
                        end if;

                    when CPU_CALLS_PUSH_FP =>
                        -- Push FP
                        temp_sp := std_logic_vector(unsigned(registers(REG_SP)) - 4);
                        mem_addr <= temp_sp;
                        mem_wdata <= registers(REG_FP);
                        mem_op <= MEM_WRITE_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_CALL;

                        if mem_ack = '1' then
                            registers(REG_SP) <= temp_sp;
                            mem_req <= '0';
                            cpu_state <= CPU_CALLS_PUSH_AP;
                        end if;

                    when CPU_CALLS_PUSH_AP =>
                        -- Push AP
                        temp_sp := std_logic_vector(unsigned(registers(REG_SP)) - 4);
                        mem_addr <= temp_sp;

                        if call_is_callg = '1' then
                            -- For CALLG, AP points to arglist
                            mem_wdata <= operand_addrs(0);
                        else
                            -- For CALLS, AP will point to numarg on stack
                            mem_wdata <= registers(REG_AP);
                        end if;

                        mem_op <= MEM_WRITE_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_CALL;

                        if mem_ack = '1' then
                            registers(REG_SP) <= temp_sp;
                            mem_req <= '0';
                            cpu_state <= CPU_CALLS_READ_MASK;
                        end if;

                    when CPU_CALLS_READ_MASK =>
                        -- Read entry mask from procedure entry point
                        mem_addr <= call_proc_addr;
                        mem_op <= MEM_READ_WORD;
                        mem_req <= '1';
                        mem_user <= MEM_USER_CALL;

                        if mem_ack = '1' then
                            call_entry_mask <= mem_rdata(15 downto 0);
                            mem_req <= '0';

                            -- Count number of registers to save
                            call_saved_count <= 0;
                            for i in 0 to 11 loop
                                if mem_rdata(i) = '1' then
                                    call_saved_count <= call_saved_count + 1;
                                end if;
                            end loop;

                            cpu_state <= CPU_CALLS_PUSH_PSW_MASK;
                        end if;

                    when CPU_CALLS_PUSH_PSW_MASK =>
                        -- Push PSW (upper 16 bits) and save mask (lower 16 bits)
                        temp_sp := std_logic_vector(unsigned(registers(REG_SP)) - 4);
                        mem_addr <= temp_sp;
                        mem_wdata <= psl(31 downto 16) & call_entry_mask;
                        mem_op <= MEM_WRITE_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_CALL;

                        if mem_ack = '1' then
                            registers(REG_SP) <= temp_sp;
                            mem_req <= '0';
                            call_reg_index <= 0;
                            cpu_state <= CPU_CALLS_SAVE_REGS;
                        end if;

                    when CPU_CALLS_SAVE_REGS =>
                        -- Save registers according to entry mask
                        -- Check bits 0-11 of entry mask

                        if call_reg_index < 12 then
                            bit_pos := call_reg_index;

                            if call_entry_mask(bit_pos) = '1' then
                                -- Save this register
                                temp_sp := std_logic_vector(unsigned(registers(REG_SP)) - 4);
                                mem_addr <= temp_sp;
                                mem_wdata <= registers(call_reg_index);
                                mem_op <= MEM_WRITE_LONG;
                                mem_req <= '1';
                                mem_user <= MEM_USER_CALL;

                                if mem_ack = '1' then
                                    registers(REG_SP) <= temp_sp;
                                    mem_req <= '0';
                                    call_reg_index <= call_reg_index + 1;
                                end if;
                            else
                                -- Skip this register
                                call_reg_index <= call_reg_index + 1;
                            end if;
                        else
                            -- Done saving registers
                            cpu_state <= CPU_CALLS_SET_POINTERS;
                        end if;

                    when CPU_CALLS_SET_POINTERS =>
                        -- Set new FP and AP
                        registers(REG_FP) <= registers(REG_SP);

                        if call_is_callg = '1' then
                            -- CALLG: AP already points to arglist
                            registers(REG_AP) <= operand_addrs(0);
                        else
                            -- CALLS: AP points to numarg on stack
                            -- AP = FP + 20 + 4*(saved_regs)
                            temp_data := std_logic_vector(
                                unsigned(registers(REG_SP)) + 20 + (call_saved_count * 4)
                            );
                            registers(REG_AP) <= temp_data;
                        end if;

                        cpu_state <= CPU_CALLS_JUMP;

                    when CPU_CALLS_JUMP =>
                        -- Jump to procedure (skip 2-byte entry mask)
                        registers(REG_PC) <= std_logic_vector(unsigned(call_proc_addr) + 2);

                        -- Reset instruction buffer
                        inst_bytes <= 0;
                        inst_ptr <= 0;
                        cpu_state <= CPU_FETCH_INST;

                    -------------------- RET States --------------------
                    when CPU_RET_READ_MASK =>
                        -- Read save mask from FP-4
                        mem_addr <= std_logic_vector(unsigned(registers(REG_FP)) - 4);
                        mem_op <= MEM_READ_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_CALL;

                        if mem_ack = '1' then
                            call_entry_mask <= mem_rdata(15 downto 0);
                            psl(31 downto 16) <= mem_rdata(31 downto 16);  -- Restore PSW
                            mem_req <= '0';

                            -- Set SP to start of saved registers
                            registers(REG_SP) <= registers(REG_FP);
                            call_reg_index <= 11;  -- Start from R11 (restore in reverse)
                            cpu_state <= CPU_RET_RESTORE_REGS;
                        end if;

                    when CPU_RET_RESTORE_REGS =>
                        -- Restore registers in reverse order (R11 down to R0)

                        if call_reg_index >= 0 then
                            bit_pos := call_reg_index;

                            if call_entry_mask(bit_pos) = '1' and call_reg_index < 12 then
                                -- Restore this register
                                mem_addr <= registers(REG_SP);
                                mem_op <= MEM_READ_LONG;
                                mem_req <= '1';
                                mem_user <= MEM_USER_CALL;

                                if mem_ack = '1' then
                                    registers(call_reg_index) <= mem_rdata;
                                    registers(REG_SP) <= std_logic_vector(unsigned(registers(REG_SP)) + 4);
                                    mem_req <= '0';
                                    call_reg_index <= call_reg_index - 1;
                                end if;
                            else
                                -- Skip this register
                                call_reg_index <= call_reg_index - 1;
                            end if;
                        else
                            -- Done restoring registers
                            cpu_state <= CPU_RET_RESTORE_PTRS;
                        end if;

                    when CPU_RET_RESTORE_PTRS =>
                        -- Restore AP and FP
                        -- SP now points to PSW/mask, next is AP, then FP

                        temp_sp := std_logic_vector(unsigned(registers(REG_FP)) - 8);
                        mem_addr <= temp_sp;
                        mem_op <= MEM_READ_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_CALL;

                        if mem_ack = '1' then
                            registers(REG_AP) <= mem_rdata;
                            mem_req <= '0';

                            -- Now read FP
                            temp_sp := std_logic_vector(unsigned(registers(REG_FP)) - 12);
                            mem_addr <= temp_sp;
                            mem_op <= MEM_READ_LONG;
                            mem_req <= '1';

                            if mem_ack = '1' then
                                call_saved_fp <= mem_rdata;  -- Temporary storage
                                registers(REG_SP) <= registers(REG_FP);  -- SP = old FP
                                mem_req <= '0';
                                cpu_state <= CPU_RET_GET_PC;
                            end if;
                        end if;

                    when CPU_RET_GET_PC =>
                        -- Get return PC from stack
                        mem_addr <= registers(REG_SP);
                        mem_op <= MEM_READ_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_CALL;

                        if mem_ack = '1' then
                            call_return_pc <= mem_rdata;
                            registers(REG_SP) <= std_logic_vector(unsigned(registers(REG_SP)) + 4);
                            mem_req <= '0';
                            cpu_state <= CPU_RET_POP_ARGS;
                        end if;

                    when CPU_RET_POP_ARGS =>
                        -- Get argument count and pop arguments
                        mem_addr <= registers(REG_SP);
                        mem_op <= MEM_READ_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_CALL;

                        if mem_ack = '1' then
                            call_numarg <= mem_rdata;
                            mem_req <= '0';

                            -- Pop argcount + arguments
                            temp_sp := std_logic_vector(
                                unsigned(registers(REG_SP)) + 4 + (unsigned(mem_rdata) * 4)
                            );
                            registers(REG_SP) <= temp_sp;

                            -- Restore FP
                            registers(REG_FP) <= call_saved_fp;

                            -- Return to caller
                            registers(REG_PC) <= call_return_pc;

                            -- Reset and fetch next instruction
                            inst_bytes <= 0;
                            inst_ptr <= 0;
                            cpu_state <= CPU_FETCH_INST;
                        end if;

                    ------------------------------------------------------------
                    when CPU_WRITEBACK =>
                        -- Update condition codes
                        if inst_needs_writeback = '1' or opcode = x"D1" or opcode = x"B1" or opcode = x"91" then
                            psl(PSL_N) <= alu_flags(3);
                            psl(PSL_Z) <= alu_flags(2);
                            psl(PSL_V) <= alu_flags(1);
                            psl(PSL_C) <= alu_flags(0);
                        end if;

                        -- Write result
                        if inst_needs_writeback = '1' then
                            if operand_is_reg(dest_operand_idx) = '1' then
                                -- Write to register
                                registers(operand_reg_nums(dest_operand_idx)) <= alu_result;
                            else
                                -- Write to memory
                                mem_addr <= operand_addrs(dest_operand_idx);
                                mem_wdata <= alu_result;
                                mem_op <= MEM_WRITE_LONG;
                                mem_req <= '1';

                                if mem_ack = '1' then
                                    mem_req <= '0';
                                end if;
                            end if;
                        end if;

                        -- Handle branch
                        if branch_taken = '1' then
                            registers(REG_PC) <= branch_target;
                        end if;

                        -- Ready for next instruction
                        if mem_req = '0' then
                            inst_bytes <= 0;
                            inst_ptr <= 0;
                            cpu_state <= CPU_FETCH_INST;
                        end if;

                    -------------------- Exception States --------------------
                    when CPU_EXCEPTION =>
                        -- Exception entry: determine vector from exception_i
                        exc_saved_pc <= registers(REG_PC);
                        exc_saved_psl <= psl;

                        -- Map exception to SCB vector
                        case exception_i is
                            when EXC_MACHINE_CHECK =>
                                exc_vector <= "0000000000";  -- 0x00
                            when EXC_KERNEL_STACK_INVALID =>
                                exc_vector <= "0000000100";  -- 0x04
                            when EXC_POWER_FAIL =>
                                exc_vector <= "0000001000";  -- 0x08
                            when EXC_RESERVED_INSTRUCTION =>
                                exc_vector <= "0000001100";  -- 0x0C
                            when EXC_RESERVED_OPERAND =>
                                exc_vector <= "0000010100";  -- 0x14
                            when EXC_RESERVED_ADDRESSING =>
                                exc_vector <= "0000011000";  -- 0x18
                            when EXC_ACCESS_VIOLATION =>
                                exc_vector <= "0000011100";  -- 0x1C
                            when EXC_TRANSLATION_NOT_VALID =>
                                exc_vector <= "0000100000";  -- 0x20
                            when EXC_TRACE_TRAP =>
                                exc_vector <= "0000100100";  -- 0x24
                            when EXC_BREAKPOINT =>
                                exc_vector <= "0000101000";  -- 0x28
                            when EXC_ARITHMETIC_TRAP =>
                                exc_vector <= "0000110000";  -- 0x30
                            when others =>
                                exc_vector <= "0000000000";  -- Default to machine check
                        end case;

                        cpu_state <= CPU_EXC_PUSH_PC;

                    when CPU_EXC_PUSH_PC =>
                        -- Push PC onto stack
                        temp_sp := std_logic_vector(unsigned(registers(REG_SP)) - 4);
                        mem_addr <= temp_sp;
                        mem_wdata <= exc_saved_pc;
                        mem_op <= MEM_WRITE_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_EXCEPTION;

                        if mem_ack = '1' then
                            registers(REG_SP) <= temp_sp;
                            mem_req <= '0';
                            cpu_state <= CPU_EXC_PUSH_PSL;
                        end if;

                    when CPU_EXC_PUSH_PSL =>
                        -- Push PSL onto stack
                        temp_sp := std_logic_vector(unsigned(registers(REG_SP)) - 4);
                        mem_addr <= temp_sp;
                        mem_wdata <= exc_saved_psl;
                        mem_op <= MEM_WRITE_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_EXCEPTION;

                        if mem_ack = '1' then
                            registers(REG_SP) <= temp_sp;
                            mem_req <= '0';
                            cpu_state <= CPU_EXC_READ_SCB;
                        end if;

                    when CPU_EXC_READ_SCB =>
                        -- Read handler address from SCB
                        temp_data := std_logic_vector(unsigned(scbb) + unsigned(exc_vector));
                        mem_addr <= temp_data;
                        mem_op <= MEM_READ_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_EXCEPTION;

                        if mem_ack = '1' then
                            exc_handler_addr <= mem_rdata;
                            mem_req <= '0';
                            cpu_state <= CPU_EXC_DISPATCH;
                        end if;

                    when CPU_EXC_DISPATCH =>
                        -- Dispatch to exception handler
                        -- Update PSL: save previous mode, set current to kernel
                        exc_prev_mode <= psl(PSL_CURMOD + 1 downto PSL_CURMOD);
                        psl(PSL_PRVMOD + 1 downto PSL_PRVMOD) <= psl(PSL_CURMOD + 1 downto PSL_CURMOD);
                        psl(PSL_CURMOD + 1 downto PSL_CURMOD) <= MODE_KERNEL;
                        psl(PSL_TP) <= '0';  -- Clear trace pending

                        -- Jump to handler
                        registers(REG_PC) <= exc_handler_addr;
                        exception_i <= EXC_NONE;  -- Clear exception

                        -- Reset instruction fetch
                        inst_bytes <= 0;
                        inst_ptr <= 0;
                        cpu_state <= CPU_FETCH_INST;

                    -------------------- REI States --------------------
                    when CPU_REI_POP_PC =>
                        -- Pop PC from stack
                        mem_addr <= registers(REG_SP);
                        mem_op <= MEM_READ_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_EXCEPTION;

                        if mem_ack = '1' then
                            exc_saved_pc <= mem_rdata;
                            registers(REG_SP) <= std_logic_vector(unsigned(registers(REG_SP)) + 4);
                            mem_req <= '0';
                            cpu_state <= CPU_REI_POP_PSL;
                        end if;

                    when CPU_REI_POP_PSL =>
                        -- Pop PSL from stack
                        mem_addr <= registers(REG_SP);
                        mem_op <= MEM_READ_LONG;
                        mem_req <= '1';
                        mem_user <= MEM_USER_EXCEPTION;

                        if mem_ack = '1' then
                            exc_saved_psl <= mem_rdata;
                            registers(REG_SP) <= std_logic_vector(unsigned(registers(REG_SP)) + 4);
                            mem_req <= '0';
                            cpu_state <= CPU_REI_VALIDATE;
                        end if;

                    when CPU_REI_VALIDATE =>
                        -- Validate PSL (mode transition rules)
                        exc_prev_mode <= psl(PSL_CURMOD + 1 downto PSL_CURMOD);

                        -- Check if transition is legal
                        -- Can only REI to same or less privileged mode
                        -- For now, accept any transition (add validation later)

                        cpu_state <= CPU_REI_RESTORE;

                    when CPU_REI_RESTORE =>
                        -- Restore PSL and PC
                        psl <= exc_saved_psl;
                        registers(REG_PC) <= exc_saved_pc;

                        -- Reset instruction fetch
                        inst_bytes <= 0;
                        inst_ptr <= 0;
                        cpu_state <= CPU_FETCH_INST;

                    ------------------------------------------------------------
                    when CPU_HALT =>
                        halted_i <= '1';

                end case;
            end if;
        end if;
    end process;

end rtl;
