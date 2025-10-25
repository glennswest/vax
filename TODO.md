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

### 2. CALLS/CALLG/RET Completion
**Priority:** High
**Effort:** 1-2 weeks
**Status:** Partially implemented

- [ ] Complete CALLS instruction
  - [ ] Stack frame creation
  - [ ] Argument list processing
  - [ ] Save registers (R2-R11, AP, FP)
  - [ ] Condition handler setup
- [ ] Complete CALLG instruction
  - [ ] Argument list pointer handling
- [ ] Complete RET instruction
  - [ ] Restore registers
  - [ ] Unwind stack frame
  - [ ] Return to caller
- [ ] Test nested procedure calls

### 3. Exception Handling
**Priority:** High
**Effort:** 1-2 weeks
**Status:** Framework only

- [ ] Implement SCB (System Control Block) lookup
- [ ] Exception vector dispatch
- [ ] PSL state saving
- [ ] Stack switching (kernel, exec, supervisor, user)
- [ ] REI (Return from Exception/Interrupt) instruction
- [ ] Test with common exceptions

### 4. Boot ROM Implementation
**Priority:** High
**Effort:** 3-5 days
**Status:** Design only

- [ ] Write simple boot code in VAX assembly
- [ ] Assemble to machine code
- [ ] Create VHDL ROM initialization
- [ ] Integrate ROM into memory controller
- [ ] Test boot sequence
- [ ] Add console output for debugging

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

**Phase 1: Core Functionality (3-6 weeks)**
- ✅ Item 1: Operand fetching integration (COMPLETED)
- Items 2-4: Critical path to boot (remaining)

**Phase 2: Extended Features (4-6 weeks)**
- Items 5-7: String, queue, branches

**Phase 3: PCIe Redesign (1-2 weeks)**
- Item 8: Proper PCIe peripheral support

**Phase 4: Additional Instructions (2-4 weeks)**
- Items 9-10: Bit field, floating point

**Phase 5: Testing and Optimization (4-8 weeks)**
- Items 11-14: Performance, hardware, VMS

**Total to VMS Boot:** 10-20 weeks (2.5-5 months)
**Progress:** ~30% complete (operand fetching milestone achieved)

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
