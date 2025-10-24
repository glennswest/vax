-- VAX-11/780 Top Level Entity
-- This is the top-level module that instantiates the CPU, MMU, memory controller,
-- and I/O subsystems

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.vax_pkg.all;

entity vax_top is
    generic (
        -- Memory configuration
        DDR_DATA_WIDTH : integer := 512;  -- DDR interface width
        DDR_ADDR_WIDTH : integer := 30    -- Physical address width
    );
    port (
        -- Clock and reset
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- DDR4/DDR5 Memory Interface (connects to Xilinx MIG)
        ddr_clk         : in  std_logic;
        ddr_rst         : in  std_logic;
        ddr_ready       : in  std_logic;

        ddr_cmd_valid   : out std_logic;
        ddr_cmd_ready   : in  std_logic;
        ddr_cmd_addr    : out std_logic_vector(DDR_ADDR_WIDTH-1 downto 0);
        ddr_cmd_we      : out std_logic;
        ddr_cmd_en      : out std_logic;

        ddr_wr_data     : out std_logic_vector(DDR_DATA_WIDTH-1 downto 0);
        ddr_wr_mask     : out std_logic_vector(DDR_DATA_WIDTH/8-1 downto 0);
        ddr_wr_valid    : out std_logic;
        ddr_wr_ready    : in  std_logic;

        ddr_rd_data     : in  std_logic_vector(DDR_DATA_WIDTH-1 downto 0);
        ddr_rd_valid    : in  std_logic;
        ddr_rd_ready    : out std_logic;

        -- PCIe Interface (connects to Xilinx PCIe IP)
        pcie_clk        : in  std_logic;
        pcie_rst        : in  std_logic;

        -- PCIe AXI Stream TX (data from VAX to host)
        pcie_tx_tdata   : out std_logic_vector(255 downto 0);
        pcie_tx_tkeep   : out std_logic_vector(31 downto 0);
        pcie_tx_tlast   : out std_logic;
        pcie_tx_tvalid  : out std_logic;
        pcie_tx_tready  : in  std_logic;

        -- PCIe AXI Stream RX (data from host to VAX)
        pcie_rx_tdata   : in  std_logic_vector(255 downto 0);
        pcie_rx_tkeep   : in  std_logic_vector(31 downto 0);
        pcie_rx_tlast   : in  std_logic;
        pcie_rx_tvalid  : in  std_logic;
        pcie_rx_tready  : out std_logic;

        -- Console/Debug UART (optional simple debug interface)
        uart_tx         : out std_logic;
        uart_rx         : in  std_logic;

        -- Status LEDs
        led_heartbeat   : out std_logic;
        led_running     : out std_logic;
        led_error       : out std_logic
    );
end vax_top;

architecture rtl of vax_top is

    -- CPU Interface signals
    signal cpu_mem_addr     : virt_addr_t;
    signal cpu_mem_wdata    : longword_t;
    signal cpu_mem_rdata    : longword_t;
    signal cpu_mem_op       : mem_op_t;
    signal cpu_mem_req      : std_logic;
    signal cpu_mem_ack      : std_logic;
    signal cpu_exception    : exception_t;
    signal cpu_halted       : std_logic;

    -- MMU Interface signals
    signal mmu_vaddr        : virt_addr_t;
    signal mmu_paddr        : phys_addr_t;
    signal mmu_translate_req: std_logic;
    signal mmu_translate_ack: std_logic;
    signal mmu_exception    : exception_t;
    signal mmu_mode         : std_logic_vector(1 downto 0);

    -- Memory Controller Interface
    signal mem_addr         : phys_addr_t;
    signal mem_wdata        : longword_t;
    signal mem_rdata        : longword_t;
    signal mem_we           : std_logic;
    signal mem_req          : std_logic;
    signal mem_ack          : std_logic;

    -- I/O Bus signals
    signal io_addr          : std_logic_vector(15 downto 0);
    signal io_wdata         : longword_t;
    signal io_rdata         : longword_t;
    signal io_we            : std_logic;
    signal io_req           : std_logic;
    signal io_ack           : std_logic;

    -- Interrupt signals
    signal interrupt_req    : std_logic_vector(15 downto 0);
    signal interrupt_vector : std_logic_vector(7 downto 0);
    signal interrupt_ack    : std_logic;

    -- Heartbeat counter for LED
    signal heartbeat_counter : unsigned(27 downto 0);

    -- Component declarations
    component vax_cpu is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            mem_addr        : out virt_addr_t;
            mem_wdata       : out longword_t;
            mem_rdata       : in  longword_t;
            mem_op          : out mem_op_t;
            mem_req         : out std_logic;
            mem_ack         : in  std_logic;
            exception       : out exception_t;
            interrupt_req   : in  std_logic_vector(15 downto 0);
            interrupt_vector: in  std_logic_vector(7 downto 0);
            interrupt_ack   : out std_logic;
            halted          : out std_logic
        );
    end component;

    component vax_mmu is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            vaddr           : in  virt_addr_t;
            paddr           : out phys_addr_t;
            translate_req   : in  std_logic;
            translate_ack   : out std_logic;
            exception       : out exception_t;
            mode            : in  std_logic_vector(1 downto 0);
            mem_addr        : out phys_addr_t;
            mem_wdata       : out longword_t;
            mem_rdata       : in  longword_t;
            mem_we          : out std_logic;
            mem_req         : out std_logic;
            mem_ack         : in  std_logic
        );
    end component;

    component memory_controller is
        generic (
            DDR_DATA_WIDTH : integer;
            DDR_ADDR_WIDTH : integer
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            cpu_addr        : in  phys_addr_t;
            cpu_wdata       : in  longword_t;
            cpu_rdata       : out longword_t;
            cpu_we          : in  std_logic;
            cpu_req         : in  std_logic;
            cpu_ack         : out std_logic;
            ddr_clk         : in  std_logic;
            ddr_rst         : in  std_logic;
            ddr_ready       : in  std_logic;
            ddr_cmd_valid   : out std_logic;
            ddr_cmd_ready   : in  std_logic;
            ddr_cmd_addr    : out std_logic_vector(DDR_ADDR_WIDTH-1 downto 0);
            ddr_cmd_we      : out std_logic;
            ddr_cmd_en      : out std_logic;
            ddr_wr_data     : out std_logic_vector(DDR_DATA_WIDTH-1 downto 0);
            ddr_wr_mask     : out std_logic_vector(DDR_DATA_WIDTH/8-1 downto 0);
            ddr_wr_valid    : out std_logic;
            ddr_wr_ready    : in  std_logic;
            ddr_rd_data     : in  std_logic_vector(DDR_DATA_WIDTH-1 downto 0);
            ddr_rd_valid    : in  std_logic;
            ddr_rd_ready    : out std_logic
        );
    end component;

begin

    -- CPU Core instantiation
    cpu_inst : vax_cpu
        port map (
            clk             => clk,
            rst             => rst,
            mem_addr        => cpu_mem_addr,
            mem_wdata       => cpu_mem_wdata,
            mem_rdata       => cpu_mem_rdata,
            mem_op          => cpu_mem_op,
            mem_req         => cpu_mem_req,
            mem_ack         => cpu_mem_ack,
            exception       => cpu_exception,
            interrupt_req   => interrupt_req,
            interrupt_vector=> interrupt_vector,
            interrupt_ack   => interrupt_ack,
            halted          => cpu_halted
        );

    -- Memory Management Unit instantiation
    mmu_inst : vax_mmu
        port map (
            clk             => clk,
            rst             => rst,
            vaddr           => mmu_vaddr,
            paddr           => mmu_paddr,
            translate_req   => mmu_translate_req,
            translate_ack   => mmu_translate_ack,
            exception       => mmu_exception,
            mode            => mmu_mode,
            mem_addr        => mem_addr,
            mem_wdata       => mem_wdata,
            mem_rdata       => mem_rdata,
            mem_we          => mem_we,
            mem_req         => mem_req,
            mem_ack         => mem_ack
        );

    -- Memory Controller instantiation
    mem_ctrl_inst : memory_controller
        generic map (
            DDR_DATA_WIDTH => DDR_DATA_WIDTH,
            DDR_ADDR_WIDTH => DDR_ADDR_WIDTH
        )
        port map (
            clk             => clk,
            rst             => rst,
            cpu_addr        => mem_addr,
            cpu_wdata       => mem_wdata,
            cpu_rdata       => mem_rdata,
            cpu_we          => mem_we,
            cpu_req         => mem_req,
            cpu_ack         => mem_ack,
            ddr_clk         => ddr_clk,
            ddr_rst         => ddr_rst,
            ddr_ready       => ddr_ready,
            ddr_cmd_valid   => ddr_cmd_valid,
            ddr_cmd_ready   => ddr_cmd_ready,
            ddr_cmd_addr    => ddr_cmd_addr,
            ddr_cmd_we      => ddr_cmd_we,
            ddr_cmd_en      => ddr_cmd_en,
            ddr_wr_data     => ddr_wr_data,
            ddr_wr_mask     => ddr_wr_mask,
            ddr_wr_valid    => ddr_wr_valid,
            ddr_wr_ready    => ddr_wr_ready,
            ddr_rd_data     => ddr_rd_data,
            ddr_rd_valid    => ddr_rd_valid,
            ddr_rd_ready    => ddr_rd_ready
        );

    -- Heartbeat LED (blinks to show the FPGA is alive)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                heartbeat_counter <= (others => '0');
            else
                heartbeat_counter <= heartbeat_counter + 1;
            end if;
        end if;
    end process;

    led_heartbeat <= heartbeat_counter(heartbeat_counter'high);
    led_running <= not cpu_halted;
    led_error <= '1' when (cpu_exception /= EXC_NONE or mmu_exception /= EXC_NONE) else '0';

    -- TODO: Add I/O subsystem instantiations
    -- - MASSBUS controller
    -- - UNIBUS controller
    -- - PCIe interface
    -- - Console UART

end rtl;
