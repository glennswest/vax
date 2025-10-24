-- VAX Memory Management Unit (MMU)
-- Implements virtual-to-physical address translation with TLB and page tables

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity vax_mmu is
    port (
        -- Clock and reset
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- CPU interface
        vaddr           : in  virt_addr_t;
        paddr           : out phys_addr_t;
        translate_req   : in  std_logic;
        translate_ack   : out std_logic;
        exception       : out exception_t;
        mode            : in  std_logic_vector(1 downto 0);  -- Processor mode

        -- Memory interface for page table walks
        mem_addr        : out phys_addr_t;
        mem_wdata       : out longword_t;
        mem_rdata       : in  longword_t;
        mem_we          : out std_logic;
        mem_req         : out std_logic;
        mem_ack         : in  std_logic
    );
end vax_mmu;

architecture rtl of vax_mmu is

    -- TLB (Translation Lookaside Buffer)
    constant TLB_SIZE : integer := 64;

    type tlb_entry_t is record
        valid       : std_logic;
        vpn         : vpn_t;
        pfn         : pfn_t;
        modified    : std_logic;
        protection  : std_logic_vector(3 downto 0);
    end record;

    type tlb_array_t is array(0 to TLB_SIZE-1) of tlb_entry_t;
    signal tlb : tlb_array_t;

    -- TLB lookup signals
    signal tlb_hit      : std_logic;
    signal tlb_hit_idx  : integer range 0 to TLB_SIZE-1;
    signal tlb_vpn      : vpn_t;

    -- Page table base registers (internal processor registers)
    signal p0br         : phys_addr_t;  -- P0 base register
    signal p0lr         : longword_t;   -- P0 length register
    signal p1br         : phys_addr_t;  -- P1 base register
    signal p1lr         : longword_t;   -- P1 length register
    signal sbr          : phys_addr_t;  -- System base register
    signal slr          : longword_t;   -- System length register

    -- Translation state machine
    type trans_state_t is (
        TRANS_IDLE,
        TRANS_TLB_LOOKUP,
        TRANS_PT_READ,
        TRANS_PT_WAIT,
        TRANS_DONE,
        TRANS_ERROR
    );

    signal trans_state  : trans_state_t;
    signal pte          : longword_t;   -- Page table entry
    signal region       : std_logic_vector(1 downto 0);
    signal pt_base      : phys_addr_t;

begin

    -- Extract region from virtual address
    region <= get_region(vaddr);

    -- TLB lookup process (combinational)
    process(tlb, vaddr, translate_req)
        variable vpn_v : vpn_t;
    begin
        vpn_v := get_vpn(vaddr);
        tlb_hit <= '0';
        tlb_hit_idx <= 0;
        tlb_vpn <= vpn_v;

        if translate_req = '1' then
            for i in 0 to TLB_SIZE-1 loop
                if tlb(i).valid = '1' and tlb(i).vpn = vpn_v then
                    tlb_hit <= '1';
                    tlb_hit_idx <= i;
                    exit;
                end if;
            end loop;
        end if;
    end process;

    -- Translation state machine
    process(clk)
        variable page_offset_v : page_offset_t;
        variable vpn_offset : unsigned(22 downto 0);
        variable pt_addr : phys_addr_t;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                trans_state <= TRANS_IDLE;
                translate_ack <= '0';
                exception <= EXC_NONE;
                mem_req <= '0';
                mem_we <= '0';

                -- Initialize page table base registers
                -- These would normally be set by privileged instructions
                p0br <= (others => '0');
                p0lr <= (others => '0');
                p1br <= (others => '0');
                p1lr <= (others => '0');
                sbr <= (others => '0');
                slr <= (others => '0');

                -- Initialize TLB
                for i in 0 to TLB_SIZE-1 loop
                    tlb(i).valid <= '0';
                end loop;

            else
                case trans_state is

                    when TRANS_IDLE =>
                        translate_ack <= '0';
                        exception <= EXC_NONE;

                        if translate_req = '1' then
                            trans_state <= TRANS_TLB_LOOKUP;
                        end if;

                    when TRANS_TLB_LOOKUP =>
                        if tlb_hit = '1' then
                            -- TLB hit - use cached translation
                            page_offset_v := get_page_offset(vaddr);
                            paddr <= build_phys_addr(tlb(tlb_hit_idx).pfn, page_offset_v);
                            trans_state <= TRANS_DONE;
                        else
                            -- TLB miss - need to walk page table
                            -- Determine which page table to use based on region
                            case region is
                                when REGION_P0 =>
                                    pt_base <= p0br;
                                when REGION_P1 =>
                                    pt_base <= p1br;
                                when REGION_S0 | REGION_S1 =>
                                    pt_base <= sbr;
                                when others =>
                                    pt_base <= (others => '0');
                            end case;
                            trans_state <= TRANS_PT_READ;
                        end if;

                    when TRANS_PT_READ =>
                        -- Calculate page table entry address
                        -- PTE address = page_table_base + (VPN * 4)
                        vpn_offset := unsigned(tlb_vpn);
                        pt_addr := std_logic_vector(unsigned(pt_base) + (vpn_offset & "00"));  -- *4

                        -- Read PTE from memory
                        mem_addr <= pt_addr;
                        mem_req <= '1';
                        mem_we <= '0';
                        trans_state <= TRANS_PT_WAIT;

                    when TRANS_PT_WAIT =>
                        if mem_ack = '1' then
                            pte <= mem_rdata;
                            mem_req <= '0';

                            -- Check if page is valid
                            if mem_rdata(PTE_VALID) = '1' then
                                -- Valid page - extract PFN and build physical address
                                page_offset_v := get_page_offset(vaddr);
                                paddr <= build_phys_addr(mem_rdata(25 downto 0), page_offset_v);

                                -- Update TLB with new translation
                                -- Simple replacement: use next available or overwrite entry 0
                                -- Real implementation would use LRU or random replacement
                                for i in 0 to TLB_SIZE-1 loop
                                    if tlb(i).valid = '0' then
                                        tlb(i).valid <= '1';
                                        tlb(i).vpn <= tlb_vpn;
                                        tlb(i).pfn <= mem_rdata(25 downto 0);
                                        tlb(i).modified <= mem_rdata(PTE_MODIFIED);
                                        tlb(i).protection <= mem_rdata(30 downto 27);
                                        exit;
                                    elsif i = TLB_SIZE-1 then
                                        -- TLB full, replace entry 0
                                        tlb(0).valid <= '1';
                                        tlb(0).vpn <= tlb_vpn;
                                        tlb(0).pfn <= mem_rdata(25 downto 0);
                                        tlb(0).modified <= mem_rdata(PTE_MODIFIED);
                                        tlb(0).protection <= mem_rdata(30 downto 27);
                                    end if;
                                end loop;

                                trans_state <= TRANS_DONE;
                            else
                                -- Invalid page
                                exception <= EXC_TRANSLATION_NOT_VALID;
                                trans_state <= TRANS_ERROR;
                            end if;
                        end if;

                    when TRANS_DONE =>
                        translate_ack <= '1';
                        if translate_req = '0' then
                            trans_state <= TRANS_IDLE;
                        end if;

                    when TRANS_ERROR =>
                        translate_ack <= '1';
                        if translate_req = '0' then
                            trans_state <= TRANS_IDLE;
                            exception <= EXC_NONE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end rtl;
