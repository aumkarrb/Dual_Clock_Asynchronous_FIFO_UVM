# Dual Clock Asynchronous FIFO — UVM Verification
 
> UVM 1.2 Functional Verification of a Dual-Clock Asynchronous FIFO in SystemVerilog
 
![Language](https://img.shields.io/badge/Language-SystemVerilog%20%7C%20Verilog-blue)
![Methodology](https://img.shields.io/badge/Methodology-UVM%201.2-green)
![Coverage](https://img.shields.io/badge/Functional%20Coverage-100%25-brightgreen)
![License](https://img.shields.io/badge/License-MIT-yellow)
 
---
 
## Overview
 
This project implements a **UVM 1.2** testbench for a dual-clock asynchronous FIFO. The FIFO uses independent write and read clock domains and **Gray-code pointer synchronization** via two-flop synchronizers to safely cross the clock domain boundary — the technique described in Clifford Cummings' SNUG 2002 FIFO paper (included under `References/`).
 
The verification environment is a single-file UVM testbench with independent write/read agents, a self-checking scoreboard, a cross-domain transaction analyzer, and a functional covergroup — closed at **100% coverage** with zero scoreboard mismatches.
 
---
 
## Repository Structure
 
```
Dual_Clock_Asynchronous_FIFO_UVM/
├── Design/
│   └── dual_clock_async_fifo_design.v          # RTL design (Verilog)
├── Output/
│   ├── Output.txt                               # Latest Xcelium simulation log
│   └── fifo_uvm_simulation.vcd                  # Waveform dump (view in EPWave/GTKWave)
├── References/
│   ├── Simulation_and_Synthesis_Techniques_...  # Supporting methodology paper
│   └── cummings1_final.pdf                      # Cummings, SNUG San Jose 2002
├── Testbench/
│   └── dual_clock_asynchronous_fifo_testbench.sv # Full UVM testbench (SystemVerilog)
├── LICENSE                                       # MIT License
└── README.md
```
 
---
 
## Design Architecture
 
`dual_clock_async_fifo_design.v` is structured as five cooperating modules:
 
```
fifo1 (top)
├── fifomem          — Dual-port synchronous-write / asynchronous-read memory array
├── wptr_full        — Write pointer (binary + Gray), full-flag generation
├── rptr_empty       — Read pointer (binary + Gray), empty-flag generation
├── sync_r2w         — 2-FF synchronizer: read Gray pointer  → write clock domain
└── sync_w2r         — 2-FF synchronizer: write Gray pointer → read clock domain
```
 
| Parameter | Value | Description |
|-----------|-------|-------------|
| `DSIZE` | 8 bits | Data word width |
| `ASIZE` | 4 bits | Address width |
| Depth | 16 entries | `2^ASIZE` |
| Write clock | 100 MHz | `#5ns` half-period, generated in tb top |
| Read clock | 75 MHz | `#6.67ns` half-period, intentionally asynchronous to wclk |
| Pointer encoding | Gray code | CDC-safe; only one bit changes per increment |
| Full detection | MSB comparison | `wgnext == {~wrptr2[MSBs], wrptr2[LSBs]}` |
| Empty detection | Equality check | `rgnext == rwptr2` |
 
---
 
## Verification Environment
 
```
fifo_uvm_base_test
└── fifo_normal_test
    └── fifo_uvm_env
        ├── write_agent  (UVM_ACTIVE)
        │   ├── write_sequencer
        │   ├── write_driver
        │   └── write_monitor  ──► analysis port (forwards only winc && !wfull)
        ├── read_agent  (UVM_ACTIVE)
        │   ├── read_sequencer
        │   ├── read_driver
        │   └── read_monitor   ──► analysis port (forwards only rinc && !rempty)
        ├── fifo_scoreboard    ◄── write_monitor + read_monitor
        ├── fifo_coverage      ◄── cross_domain_analyzer
        └── cross_domain_analyzer ◄── write_monitor + read_monitor
```
 
### Key UVM Components
 
| Component | Class | Role |
|-----------|-------|------|
| Interface | `fifo_if` | Bundles all DUT signals; `generate_wrst`/`generate_rrst` reset tasks (defined, not currently called — tb top drives reset directly) |
| Write transaction | `fifo_write_transaction` | Randomized `wdata` (boundary-weighted), `winc` (70% active) |
| Read transaction | `fifo_read_transaction` | Randomized `rinc` (70% active), captures `rdata` |
| Combined transaction | `fifo_combined_transaction` | Cross-domain tuple consumed by the coverage subscriber |
| Write sequence | `fifo_write_sequence` | 2 directed boundary writes (`wdata=0x00`, `wdata=0xFF`) followed by `num_transactions` randomized writes |
| Read sequence | `fifo_read_sequence` | `num_transactions` randomized reads, after a 50 ns head start |
| Scoreboard | `fifo_scoreboard` | Shadow queue (`expected_data[$]`); checks every read against write order, tallies mismatches |
| Coverage | `fifo_coverage` | `fifo_cg` covergroup: `wdata_cp` (zero/max/others), `write_cp`, `read_cp` |
| Cross-domain analyzer | `cross_domain_analyzer` | Merges write- and read-monitor transactions into `fifo_combined_transaction` events for coverage sampling |
| Config objects | `write_agent_config`, `read_agent_config`, `fifo_uvm_env_config` | Distributed via `uvm_config_db` |
 
 
| Metric | Result |
|--------|--------|
| Overall functional coverage | **100.00%** |
| Total writes | 34 (2 directed + 32 randomized) |
| Total reads | 18 |
| Data mismatches | 0 |
| Result | `*** TEST PASSED ***` |
 

 
## References
 
| Reference | Description |
|-----------|-------------|
| `cummings1_final.pdf` | C. Cummings, *Simulation and Synthesis Techniques for Asynchronous FIFO Design*, SNUG San Jose 2002 — canonical reference for Gray-code CDC FIFO architecture |
| `Simulation_and_Synthesis_Techniques_...pdf` | Supporting simulation and synthesis methodology document |
 
---
 
## License
 
MIT License — see [`LICENSE`](LICENSE).
