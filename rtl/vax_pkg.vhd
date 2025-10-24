-- VAX Package: Common types and constants
-- Defines the fundamental data types and constants used throughout the VAX implementation

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package vax_pkg is

    -- Basic data types
    subtype byte_t is std_logic_vector(7 downto 0);
    subtype word_t is std_logic_vector(15 downto 0);
    subtype longword_t is std_logic_vector(31 downto 0);
    subtype quadword_t is std_logic_vector(63 downto 0);

    -- Physical and virtual addresses
    subtype virt_addr_t is std_logic_vector(31 downto 0);
    subtype phys_addr_t is std_logic_vector(31 downto 0);
    subtype vpn_t is std_logic_vector(22 downto 0);  -- Virtual page number
    subtype pfn_t is std_logic_vector(25 downto 0);  -- Physical frame number
    subtype page_offset_t is std_logic_vector(8 downto 0);  -- 512-byte pages

    -- Register file
    type register_file_t is array(0 to 15) of longword_t;

    -- Array types for operands
    type longword_array_t is array(integer range <>) of longword_t;
    type virt_addr_array_t is array(integer range <>) of virt_addr_t;

    -- Register names
    constant REG_R0  : integer := 0;
    constant REG_R1  : integer := 1;
    constant REG_R2  : integer := 2;
    constant REG_R3  : integer := 3;
    constant REG_R4  : integer := 4;
    constant REG_R5  : integer := 5;
    constant REG_R6  : integer := 6;
    constant REG_R7  : integer := 7;
    constant REG_R8  : integer := 8;
    constant REG_R9  : integer := 9;
    constant REG_R10 : integer := 10;
    constant REG_R11 : integer := 11;
    constant REG_AP  : integer := 12;  -- Argument Pointer
    constant REG_FP  : integer := 13;  -- Frame Pointer
    constant REG_SP  : integer := 14;  -- Stack Pointer
    constant REG_PC  : integer := 15;  -- Program Counter

    -- PSL (Processor Status Longword) bit positions
    constant PSL_C   : integer := 0;   -- Carry
    constant PSL_V   : integer := 1;   -- Overflow
    constant PSL_Z   : integer := 2;   -- Zero
    constant PSL_N   : integer := 3;   -- Negative
    constant PSL_T   : integer := 4;   -- Trace trap enable
    constant PSL_IV  : integer := 5;   -- Integer overflow trap enable
    constant PSL_FU  : integer := 6;   -- Floating underflow trap enable
    constant PSL_DV  : integer := 7;   -- Decimal overflow trap enable
    constant PSL_IPL : integer := 16;  -- Interrupt Priority Level (bits 20:16)
    constant PSL_PRVMOD : integer := 22; -- Previous mode (bits 23:22)
    constant PSL_CURMOD : integer := 24; -- Current mode (bits 25:24)
    constant PSL_IS  : integer := 26;  -- Interrupt stack
    constant PSL_FPD : integer := 27;  -- First part done
    constant PSL_TP  : integer := 30;  -- Trace pending
    constant PSL_CM  : integer := 31;  -- Compatibility mode

    -- Processor modes
    constant MODE_KERNEL    : std_logic_vector(1 downto 0) := "00";
    constant MODE_EXECUTIVE : std_logic_vector(1 downto 0) := "01";
    constant MODE_SUPERVISOR: std_logic_vector(1 downto 0) := "10";
    constant MODE_USER      : std_logic_vector(1 downto 0) := "11";

    -- Memory regions
    constant REGION_P0 : std_logic_vector(1 downto 0) := "00";
    constant REGION_P1 : std_logic_vector(1 downto 0) := "01";
    constant REGION_S0 : std_logic_vector(1 downto 0) := "10";
    constant REGION_S1 : std_logic_vector(1 downto 0) := "11";

    -- Page table entry bits
    constant PTE_VALID    : integer := 31;
    constant PTE_MODIFIED : integer := 26;

    -- ALU operations
    type alu_op_t is (
        ALU_ADD,   -- Addition
        ALU_SUB,   -- Subtraction
        ALU_MUL,   -- Multiplication
        ALU_DIV,   -- Division
        ALU_AND,   -- Logical AND
        ALU_OR,    -- Logical OR (BIS)
        ALU_XOR,   -- Logical XOR
        ALU_BIC,   -- Bit clear
        ALU_ASH,   -- Arithmetic shift
        ALU_ROT,   -- Rotate
        ALU_CMP,   -- Compare
        ALU_TST,   -- Test
        ALU_MOV,   -- Move (pass through)
        ALU_NOP    -- No operation
    );

    -- Instruction execution state
    type exec_state_t is (
        EXEC_FETCH,        -- Fetch instruction bytes
        EXEC_DECODE,       -- Decode opcode and specifiers
        EXEC_OPERAND,      -- Fetch operands
        EXEC_EXECUTE,      -- Execute operation
        EXEC_WRITEBACK,    -- Write results
        EXEC_EXCEPTION     -- Handle exception
    );

    -- Memory operation types
    type mem_op_t is (
        MEM_NOP,
        MEM_READ_BYTE,
        MEM_READ_WORD,
        MEM_READ_LONG,
        MEM_WRITE_BYTE,
        MEM_WRITE_WORD,
        MEM_WRITE_LONG
    );

    -- Exception types
    type exception_t is (
        EXC_NONE,
        EXC_RESET,
        EXC_MACHINE_CHECK,
        EXC_KERNEL_STACK_INVALID,
        EXC_POWER_FAIL,
        EXC_RESERVED_INSTRUCTION,
        EXC_PRIVILEGED_INSTRUCTION,
        EXC_RESERVED_OPERAND,
        EXC_RESERVED_ADDRESSING,
        EXC_ACCESS_VIOLATION,
        EXC_TRANSLATION_NOT_VALID,
        EXC_TRACE_TRAP,
        EXC_BREAKPOINT,
        EXC_COMPATIBILITY,
        EXC_ARITHMETIC_TRAP,
        EXC_SOFTWARE_INTERRUPT
    );

    -- Function to extract region from virtual address
    function get_region(vaddr : virt_addr_t) return std_logic_vector;

    -- Function to extract VPN from virtual address
    function get_vpn(vaddr : virt_addr_t) return vpn_t;

    -- Function to extract page offset
    function get_page_offset(vaddr : virt_addr_t) return page_offset_t;

    -- Function to build physical address from PFN and offset
    function build_phys_addr(pfn : pfn_t; offset : page_offset_t) return phys_addr_t;

    -- Sign extension functions
    function sign_extend_byte(b : byte_t) return longword_t;
    function sign_extend_word(w : word_t) return longword_t;

end package vax_pkg;

package body vax_pkg is

    function get_region(vaddr : virt_addr_t) return std_logic_vector is
    begin
        return vaddr(31 downto 30);
    end function;

    function get_vpn(vaddr : virt_addr_t) return vpn_t is
    begin
        return vaddr(31 downto 9);
    end function;

    function get_page_offset(vaddr : virt_addr_t) return page_offset_t is
    begin
        return vaddr(8 downto 0);
    end function;

    function build_phys_addr(pfn : pfn_t; offset : page_offset_t) return phys_addr_t is
        variable paddr : phys_addr_t;
    begin
        paddr := pfn & offset(8 downto 3);  -- Assuming we align to 8-byte boundaries
        return paddr;
    end function;

    function sign_extend_byte(b : byte_t) return longword_t is
        variable result : longword_t;
    begin
        result := (31 downto 8 => b(7)) & b;
        return result;
    end function;

    function sign_extend_word(w : word_t) return longword_t is
        variable result : longword_t;
    begin
        result := (31 downto 16 => w(15)) & w;
        return result;
    end function;

end package body vax_pkg;
