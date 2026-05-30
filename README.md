# Dual Clock Asynchronous FIFO — UVM 1.2 Verification

## 1. Overview

This project implements and verifies a **Dual Clock Asynchronous FIFO** using the **Universal Verification Methodology (UVM) 1.2** framework. The RTL design is written in **Verilog** and the verification environment is built in **SystemVerilog**. The FIFO safely transfers data between two independent, asynchronous clock domains using **Gray-coded pointer synchronization** to mitigate metastability at clock domain crossing (CDC) boundaries.

---

## 2. Design Architecture

## 3 Module Summary

| Module Name | File | Description |
|---|---|---|
| `async_fifo` | `async_fifo.v` | **Top-level wrapper.** Instantiates all sub-modules and exposes the primary interface: `wclk`, `rclk`, `rst_n`, `winc`, `rinc`, `wdata`, `rdata`, `wfull`, `rempty`. Parameters: `DSIZE` (data width), `ASIZE` (address width; depth = 2^ASIZE). |
| `fifomem` | `fifomem.v` | **Dual-port SRAM / register file.** Implements the actual storage array of depth 2^ASIZE and width DSIZE bits. Write port is clocked by `wclk`; read port is combinational (or clocked by `rclk`). Addressed via binary `waddr` and `raddr` from the control modules. |
| `wptr_full` | `wptr_full.v` | **Write pointer & full flag logic.** Operates entirely in the `wclk` domain. Maintains an (ASIZE+1)-bit binary write pointer; converts it to Gray code (`wptr`) for safe CDC. Compares `wptr` against the synchronized read pointer (`wq2_rptr`) to assert `wfull` when the FIFO cannot accept more data. The MSB of the Gray-coded pointers is used to detect full vs. empty conditions. |
| `rptr_empty` | `rptr_empty.v` | **Read pointer & empty flag logic.** Operates entirely in the `rclk` domain. Maintains an (ASIZE+1)-bit binary read pointer; converts it to Gray code (`rptr`) for safe CDC. Compares `rptr` against the synchronized write pointer (`rq2_wptr`) to assert `rempty` when no valid data is available for reading. |
| `sync_w2r` | `sync_w2r.v` | **Write-to-read pointer synchronizer.** A 2-stage flip-flop synchronizer (double-flop) clocked by `rclk`. Safely transfers the Gray-coded write pointer (`wptr`) from the `wclk` domain into the `rclk` domain (`rq2_wptr`), mitigating metastability at the clock domain crossing boundary. |
| `sync_r2w` | `sync_r2w.v` | **Read-to-write pointer synchronizer.** A 2-stage flip-flop synchronizer (double-flop) clocked by `wclk`. Safely transfers the Gray-coded read pointer (`rptr`) from the `rclk` domain into the `wclk` domain (`wq2_rptr`), mitigating metastability at the clock domain crossing boundary. |

### 3.1 Top-Level Interface Signals

| Signal | Direction | Clock Domain | Description |
|---|---|---|---|
| `wclk` | Input | Write | Write-side clock |
| `rclk` | Input | Read | Read-side clock |
| `rst_n` | Input | Both | Active-low asynchronous reset |
| `winc` | Input | Write | Write enable (push); ignored when `wfull` is asserted |
| `rinc` | Input | Read | Read enable (pop); ignored when `rempty` is asserted |
| `wdata` | Input | Write | Data input bus `[DSIZE-1:0]` |
| `rdata` | Output | Read | Data output bus `[DSIZE-1:0]` |
| `wfull` | Output | Write | FIFO full flag; asserted in `wclk` domain |
| `rempty` | Output | Read | FIFO empty flag; asserted in `rclk` domain |

---

## 4. UVM Testbench Architecture

The verification environment follows the standard layered UVM architecture. All testbench files are located under the `/Testbench` directory.

### 4.1 UVM Component Roles

| Component | Role |
|---|---|
| **Sequence Item** | Encapsulates a single FIFO transaction (write/read operation with associated data and control signals) |
| **Sequencer** | Arbitrates and schedules sequences; feeds items to the driver |
| **Driver** | Translates UVM sequence items into pin-level stimulus on the DUT interface, respecting clock and protocol timing |
| **Monitor** | Passively observes DUT interface signals; broadcasts transactions to the scoreboard and coverage via TLM analysis ports |
| **Scoreboard** | Compares DUT output transactions against a reference model (golden model) to flag functional mismatches |
| **Coverage** | Collects functional coverage using SystemVerilog covergroups to track exercised scenarios |
| **Environment** | Instantiates and connects all agents, scoreboard, and coverage components using TLM connections |
| **Test** | Top-level UVM test class; configures the environment and starts sequences targeting specific scenarios |

### 4.2 Test Scenarios

| Test Scenario | Description |
|---|---|
| Normal R/W | Write and read at matched clock rates; verify data integrity |
| Write Burst to Full | Write until `wfull` asserts; verify no data is overwritten |
| Read Drain to Empty | Read until `rempty` asserts; verify no spurious reads |
| Concurrent R/W | Simultaneous read and write operations at different clock rates |
| Reset Behavior | Assert `rst_n` mid-operation; verify pointer and flag reset |
| Overflow / Underflow | Attempt write when full / read when empty; verify flag protection |
| Clock Ratio Variation | Vary `wclk`:`rclk` frequency ratios; verify CDC robustness |

---

## 5. Repository Structure

```
Dual_Clock_Asynchronous_FIFO_UVM/
│
├── Design/                      # RTL design source files (Verilog)
│   ├── async_fifo.v             # Top-level FIFO module
│   ├── fifomem.v                # Dual-port SRAM storage array
│   ├── wptr_full.v              # Write pointer and wfull flag logic
│   ├── rptr_empty.v             # Read pointer and rempty flag logic
│   ├── sync_w2r.v               # 2-FF synchronizer: wclk → rclk
│   └── sync_r2w.v               # 2-FF synchronizer: rclk → wclk
│
├── Testbench/                   # UVM 1.2 verification environment (SystemVerilog)
│   ├── fifo_if.sv               # SystemVerilog interface (DUT connections)
│   ├── fifo_seq_item.sv         # UVM sequence item (transaction class)
│   ├── fifo_sequence.sv         # UVM sequences (test stimulus generators)
│   ├── fifo_driver.sv           # UVM driver (pin-level stimulus)
│   ├── fifo_monitor.sv          # UVM monitor (passive observer)
│   ├── fifo_scoreboard.sv       # UVM scoreboard (checker / reference model)
│   ├── fifo_coverage.sv         # Functional coverage collector
│   ├── fifo_agent.sv            # UVM agent (bundles driver + monitor + sequencer)
│   ├── fifo_env.sv              # UVM environment (top-level TB container)
│   ├── fifo_test.sv             # UVM test class(es)
│   └── fifo_tb_top.sv           # Top-level simulation module (DUT + TB bind)
│
├── Output/                      # Simulation output artifacts
│   ├── *.log                    # Simulator log files
│   ├── *.vcd / *.fsdb           # Waveform dump files (GTKWave / Verdi)
│   └── coverage_report/         # Functional and code coverage reports
│
├── References/                  # Supporting documentation
│   ├── Cummings_SNUG2002.pdf    # Clifford Cummings async FIFO paper
│   │
├── LICENSE                    
└── README.md                    
```
## 6. References

1. Clifford E. Cummings, *"Simulation and Synthesis Techniques for Asynchronous FIFO Design,"* SNUG 2002, San Jose, CA. Available at: [www.sunburst-design.com/papers](http://www.sunburst-design.com/papers)

*This project was developed as part of the FFVDD Elective Mini Project at PES University.*

 




