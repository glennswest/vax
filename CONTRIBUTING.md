# Contributing to VAX-11/780 FPGA Implementation

Thank you for your interest in contributing to this project! This document provides guidelines for contributing.

## How to Contribute

### 1. Fork and Clone

```bash
# Fork the repository on GitHub, then:
git clone git@github.com:YOUR_USERNAME/vax.git
cd vax
git remote add upstream git@github.com:glennswest/vax.git
```

### 2. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/bug-description
```

### 3. Make Your Changes

- Write clean, commented VHDL code
- Follow the existing code style
- Add tests for new functionality
- Update documentation as needed

### 4. Test Your Changes

```bash
# Run simulation
cd scripts
./simulate.sh

# Check for synthesis errors (if you have Vivado)
vivado -source build_vivado.tcl
```

### 5. Commit Your Changes

Use descriptive commit messages:

```bash
git add <files>
git commit -m "Add feature: brief description

Longer description if needed:
- Detail 1
- Detail 2
"
```

### 6. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

## Areas for Contribution

### High Priority

1. **Operand Fetching Integration**
   - Connect `vax_addr_mode.vhd` to CPU
   - Parse operand specifiers
   - Handle all addressing modes in execution

2. **CALLS/CALLG/RET Completion**
   - Complete procedure call implementation
   - Stack frame handling
   - Argument list processing

3. **Exception Handling**
   - SCB (System Control Block) lookup
   - Exception dispatch
   - REI instruction

4. **Boot ROM**
   - Simple boot code
   - Console initialization
   - Disk boot loader

### Medium Priority

5. **String Operations**
   - MOVC3, MOVC5 execution
   - CMPC3, CMPC5 execution

6. **Queue Instructions**
   - INSQUE, REMQUE

7. **Bit Field Instructions**
   - EXTV, EXTZV, INSV, etc.

8. **Additional Testing**
   - More comprehensive testbenches
   - Instruction-level tests
   - Integration tests

### Lower Priority

9. **Floating Point**
   - F_floating, D_floating support

10. **Performance Optimization**
    - Pipeline optimization
    - TLB improvements

11. **Documentation**
    - More examples
    - Tutorial content
    - Video demonstrations

## Code Style Guidelines

### VHDL Code

- **Indentation:** 4 spaces (no tabs)
- **Case:** `lower_case_with_underscores` for signals, variables
- **Case:** `UPPER_CASE` for constants
- **Comments:** Use `--` for inline comments
- **Line Length:** Max 100 characters
- **Signals:** Descriptive names, avoid abbreviations

Example:
```vhdl
signal instruction_valid : std_logic;  -- Good
signal inst_vld : std_logic;           -- Avoid
```

### File Organization

- One entity per file
- Filename matches entity name
- Group related files in directories

### Documentation

- Update README.md for user-facing changes
- Update relevant docs in `doc/` directory
- Add comments for complex logic
- Include examples where helpful

## Testing Requirements

### For New Features

- Add testbench in `sim/tb/`
- Test all edge cases
- Verify against VAX specification
- Document test coverage

### For Bug Fixes

- Add test that reproduces the bug
- Verify fix resolves the issue
- Ensure no regressions

## Commit Message Guidelines

Format:
```
<type>: <subject>

<body>

<footer>
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `test`: Adding tests
- `refactor`: Code refactoring
- `perf`: Performance improvement
- `style`: Formatting changes
- `build`: Build system changes

Example:
```
feat: Add MOVC3 instruction execution

Implement MOVC3 (Move Character 3-operand) instruction:
- Parse length, source, and destination operands
- Handle multi-cycle execution
- Update R0-R5 as per VAX spec
- Add testbench validation

Closes #42
```

## Pull Request Process

1. **Ensure CI passes** (when set up)
2. **Update documentation** as needed
3. **Add tests** for new functionality
4. **Keep PRs focused** - one feature/fix per PR
5. **Respond to feedback** in a timely manner
6. **Squash commits** if requested

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement

## Testing
- [ ] Simulation tests pass
- [ ] Manual testing completed
- [ ] Added new tests

## Checklist
- [ ] Code follows project style
- [ ] Self-review completed
- [ ] Comments added where needed
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
```

## Questions or Issues?

- Open an issue on GitHub
- Tag with appropriate labels
- Provide detailed description
- Include steps to reproduce (for bugs)

## Code of Conduct

### Our Pledge

We pledge to make participation in this project a harassment-free experience for everyone.

### Our Standards

**Positive behavior:**
- Using welcoming and inclusive language
- Being respectful of differing viewpoints
- Gracefully accepting constructive criticism
- Focusing on what is best for the community

**Unacceptable behavior:**
- Trolling, insulting/derogatory comments
- Public or private harassment
- Publishing others' private information
- Other conduct which could reasonably be considered inappropriate

### Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported by opening an issue or contacting the project maintainer.

## Attribution

Contributors will be acknowledged in:
- Commit history
- AUTHORS file (if created)
- Project documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to the VAX-11/780 FPGA Implementation project!
