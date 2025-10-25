# VAX-11/780 FPGA Implementation - TODO List

## Critical Path Items (Required for Boot)

### 1. Operand Fetching Integration ✅ COMPLETED
**Priority:** Highest
**Effort:** 2-3 weeks
**Status:** ✅ COMPLETE

- [x] Integrate `vax_addr_mode.vhd` into CPU execution pipeline
- [x] Parse operand specifiers from instruction stream
- [x] Handle all 16 addressing modes in operand fetch
- [x] Test with simple register-mode instructions first
- [x] Expand to complex displacement modes
- [x] Validate with comprehensive testbench

**Completed:** This critical blocker has been removed! Full instruction execution now possible.

**Deliverables:**
- `rtl/cpu/vax_cpu_v3.vhd` - Complete CPU with operand fetching
- `sim/tb/tb_operand_fetch.vhd` - Comprehensive testbench
- `doc/operand_fetching.md` - Full documentation

### 2. CALLS/CALLG/RET Completion ✅ COMPLETED
**Priority:** High
**Effort:** 1-2 weeks
**Status:** ✅ COMPLETE

- [x] Complete CALLS instruction
  - [x] Stack frame creation
  - [x] Argument list processing
  - [x] Save registers (R0-R11) according to entry mask
  - [x] PSW preservation
  - [ ] Condition handler setup (deferred to exception handling)
- [x] Complete CALLG instruction
  - [x] Argument list pointer handling
- [x] Complete RET instruction
  - [x] Restore registers
  - [x] Unwind stack frame
  - [x] Return to caller
- [x] Test nested procedure calls

**Completed:** Full VAX procedure calling convention implemented!

**Deliverables:**
- `rtl/cpu/vax_cpu_v4.vhd` - Complete CPU with CALLS/CALLG/RET
- `sim/tb/tb_procedure_calls.vhd` - Comprehensive testbench
- `doc/procedure_calls.md` - Full documentation

### 3. Exception Handling ✅ COMPLETED
**Priority:** High
**Effort:** 1-2 weeks
**Status:** ✅ COMPLETE

- [x] Implement SCB (System Control Block) lookup
- [x] Exception vector dispatch
- [x] PSL state saving
- [x] Mode switching to kernel on exception
- [x] REI (Return from Exception/Interrupt) instruction
- [x] Test with common exceptions

**Completed:** Full VAX exception/interrupt mechanism implemented!

**Deliverables:**
- `rtl/cpu/vax_cpu_v5.vhd` - CPU with exception handling
- `sim/tb/tb_exceptions.vhd` - Exception testbench
- `doc/exception_handling.md` - Full documentation

### 4. Boot ROM Implementation ✅ COMPLETED
**Priority:** High
**Effort:** 3-5 days
**Status:** ✅ COMPLETE

- [x] Write test programs in VAX machine code
- [x] Create VHDL ROM component with initialized data
- [x] Implement 5 comprehensive test programs
- [x] Document all test programs and expected results
- [x] Ready for memory controller integration

**Completed:** Boot ROM with comprehensive test suite!

**Deliverables:**
- `rtl/memory/boot_rom.vhd` - Boot ROM component
- `doc/boot_rom_design.md` - Updated with implementation
- 5 test programs for CPU validation

## Medium Priority Items

### 5. String Operations
**Effort:** 1 week

- [ ] MOVC3 execution (move character 3-operand)
- [ ] MOVC5 execution (move character 5-operand)
- [ ] CMPC3 execution (compare character 3-operand)
- [ ] CMPC5 execution (compare character 5-operand)
- [ ] Multi-cycle operation handling
- [ ] Register state updates (R0-R5)

### 6. Queue Instructions
**Effort:** 1 week

- [ ] INSQUE (Insert into queue)
- [ ] REMQUE (Remove from queue)
- [ ] Interlocked operation
- [ ] Test queue manipulation

### 7. Additional Branch Instructions
**Effort:** 3-5 days

- [ ] AOBxxx (Add One and Branch)
- [ ] SOBxxx (Subtract One and Branch)
- [ ] Case branch instructions

## PCIe Clarification and Updates ⚠️ NEW

### 8. PCIe Interface Redesign
**Priority:** Medium
**Effort:** 1-2 weeks
**Status:** Current design needs revision

**Current Issue:** PCIe interface currently described as "host communication"

**Correct Usage:** PCIe should support additional peripheral devices:
- [ ] PCIe Ethernet controllers
- [ ] PCIe GPU devices
- [ ] PCIe NVMe storage
- [ ] PCIe SATA controllers
- [ ] Other PCIe expansion cards

**Tasks:**
- [ ] Update `pcie_interface.vhd` documentation
- [ ] Redesign for generic PCIe device support
- [ ] Implement PCIe BAR (Base Address Register) mapping
- [ ] Add PCIe configuration space
- [ ] Support multiple PCIe devices
- [ ] Update all documentation referencing PCIe
- [ ] Remove "host communication" references

**Files to Update:**
- [ ] `rtl/io/pcie_interface.vhd` - Implementation and comments
- [ ] `doc/architecture.md` - Architecture description
- [ ] `doc/implementation_guide.md` - Implementation details
- [ ] `doc/SUMMARY.md` - Project summary
- [ ] `README.md` - Overview
- [ ] `PROJECT_COMPLETE.md` - Completion report

## Lower Priority Items

### 9. Bit Field Instructions
**Effort:** 1 week

- [ ] EXTV (Extract field variable)
- [ ] EXTZV (Extract field zero-extended)
- [ ] FFS (Find first set)
- [ ] FFC (Find first clear)
- [ ] INSV (Insert field)
- [ ] CMPV/CMPZV (Compare field)

### 10. Floating Point Support
**Effort:** 2-3 weeks

- [ ] F_floating (32-bit)
- [ ] D_floating (64-bit)
- [ ] G_floating (64-bit)
- [ ] H_floating (128-bit)
- [ ] Floating point ALU
- [ ] Conversion instructions
- [ ] Test with floating point programs

**Note:** May not be needed for initial VMS boot

### 11. Performance Optimization
**Effort:** Ongoing

- [ ] Pipeline optimization
- [ ] TLB hit rate improvement
- [ ] Instruction prefetch
- [ ] Branch prediction
- [ ] Cache implementation (L1 I-cache, D-cache)

### 12. Hardware Testing
**Effort:** 2-4 weeks

- [ ] Select target FPGA board
- [ ] Port to specific Xilinx part
- [ ] Integrate Xilinx MIG IP
- [ ] Integrate Xilinx PCIe IP
- [ ] Pin constraints
- [ ] Timing closure
- [ ] Hardware bring-up
- [ ] On-board debugging

## Testing and Validation

### 13. Comprehensive Testing
**Effort:** Ongoing

- [ ] Unit tests for each instruction
- [ ] Addressing mode tests
- [ ] Memory management tests
- [ ] I/O device tests
- [ ] Integration tests
- [ ] Regression test suite
- [ ] Performance benchmarks

### 14. VMS Boot Testing
**Effort:** 2-4 weeks (after critical items complete)

- [ ] Boot ROM to console prompt
- [ ] Load VMS bootstrap
- [ ] VMS kernel initialization
- [ ] Single-user mode
- [ ] Multi-user mode
- [ ] Full VMS compatibility testing

## Documentation

### 15. Additional Documentation
**Effort:** Ongoing

- [ ] Video tutorials
- [ ] Step-by-step guides
- [ ] Example programs
- [ ] Debugging guide
- [ ] Performance tuning guide
- [ ] Hardware deployment guide

## Future Enhancements

### 16. Advanced Features

- [ ] Multiprocessor support (VAX-11/782)
- [ ] Vector processor (optional)
- [ ] Additional I/O controllers
- [ ] Network boot support
- [ ] Debugging interface (JTAG, logic analyzer)

## Timeline Estimate

**Phase 1: Core Functionality ✅ COMPLETE**
- ✅ Item 1: Operand fetching integration (COMPLETED)
- ✅ Item 2: CALLS/CALLG/RET completion (COMPLETED)
- ✅ Item 3: Exception handling and REI (COMPLETED)
- ✅ Item 4: Boot ROM implementation (COMPLETED)

**Phase 2: Extended Features (4-6 weeks)**
- Items 5-7: String, queue, branches

**Phase 3: PCIe Redesign (1-2 weeks)**
- Item 8: Proper PCIe peripheral support

**Phase 4: Additional Instructions (2-4 weeks)**
- Items 9-10: Bit field, floating point

**Phase 5: Testing and Optimization (4-8 weeks)**
- Items 11-14: Performance, hardware, VMS

**Total to VMS Boot:** 6-16 weeks (1.5-4 months)
**Progress:** ~55% complete (ALL Phase 1 critical items achieved!) ⭐⭐⭐

## How to Use This TODO

1. **Pick an item** from the high-priority section
2. **Create a branch:** `git checkout -b feature/item-name`
3. **Implement** the feature
4. **Test** thoroughly
5. **Update** this TODO file
6. **Commit** and push
7. **Create Pull Request**

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines on how to contribute to these items.

---

**Last Updated:** 2025-01-24
**Next Review:** Weekly during active development
