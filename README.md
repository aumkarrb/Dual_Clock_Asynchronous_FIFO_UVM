# Dual Clock Asynchronous FIFO — UVM Verification

> **FFVDD Elective Mini Project** · UVM 1.2 Functional Verification of a Dual-Clock Asynchronous FIFO in SystemVerilog

![Language](https://img.shields.io/badge/Language-SystemVerilog%20%7C%20Verilog-blue)
![Methodology](https://img.shields.io/badge/Methodology-UVM%201.2-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

---

## Overview

This project implements a complete **Universal Verification Methodology (UVM 1.2)** testbench for a dual-clock asynchronous FIFO design. The FIFO uses separate, independent write and read clock domains and employs **Gray-code pointer synchronization** via two-flop synchronizers to safely cross clock domain boundaries — a classical technique described in Clifford Cummings' seminal paper on FIFO design.

The verification environment features a layered UVM architecture with independent write and read agents, a self-checking scoreboard, functional coverage collection, and a cross-domain transaction analyzer.

---

## Repository Structure

```
Dual_Clock_Asynchronous_FIFO_UVM/
├── Design/
│   └── dual_clock_async_fifo_design.v       # RTL design (Verilog)
├── Output/
│   ├── Output.txt                            # Simulation log / transcript
│   └── Waveform.png                          # GTKWave / simulator waveform screenshot
├── References/
│   ├── Simulation_and_Synthesis_Tech...      # Reference textbook/paper excerpt
│   ├── Template_FFVDD_Team_1.pptx            # Project presentation slides
│   └── cummings1_final.pdf                   # Clifford Cummings FIFO paper (SNUG 2002)
├── Testbench/
│   └── dual_clock_async_fifo_testbench...    # Full UVM testbench (SystemVerilog)
├── LICENSE                                   # MIT License
└── README.md                                 # This file
```

### File Summary

| File | Location | Type | Description |
|------|----------|------|-------------|
| `dual_clock_async_fifo_design.v` | `Design/` | Verilog RTL | Top-level FIFO (`fifo1`) and all five sub-modules: `fifomem`, `rptr_empty`, `wptr_full`, `sync_r2w`, `sync_w2r` |
| `dual_clock_async_fifo_testbench...` | `Testbench/` | SystemVerilog (UVM) | Complete UVM 1.2 environment: interface, config objects, transactions, sequences, agents, scoreboard, coverage, and testbench top |
| `Output.txt` | `Output/` | Text | Full simulation transcript including UVM phase log, scoreboard results, and pass/fail status |
| `Waveform.png` | `Output/` | Image | Waveform screenshot showing write/read clock domains, pointer synchronization, `wfull`, and `rempty` signals |
| `cummings1_final.pdf` | `References/` | PDF | Clifford Cummings, *Simulation and Synthesis Techniques for Asynchronous FIFO Design* (SNUG 2002) — primary design reference |
| `Simulation_and_Synthesis_Tech...` | `References/` | Document | Supporting simulation and synthesis reference material |
| `Template_FFVDD_Team_1.pptx` | `References/` | PowerPoint | Project presentation template (FFVDD course) |
| `LICENSE` | Root | Text | MIT License |

---

## Design Architecture

The RTL (`dual_clock_async_fifo_design.v`) is structured as five cooperating modules:

```
fifo1 (top)
├── fifomem          — Dual-port synchronous-write / asynchronous-read memory array
├── wptr_full        — Write pointer (binary + Gray), full flag generation
├── rptr_empty       — Read pointer (binary + Gray), empty flag generation
├── sync_r2w         — 2-FF synchronizer: read Gray pointer → write clock domain
└── sync_w2r         — 2-FF synchronizer: write Gray pointer → read clock domain
```

| Parameter | Value | Description |
|-----------|-------|-------------|
| `DSIZE` | 8 bits | Data word width |
| `ASIZE` | 4 bits | Address width |
| Depth | 16 entries | `2^ASIZE` |
| Write clock | 100 MHz | Configurable |
| Read clock | 75 MHz | Configurable (intentionally asynchronous) |
| Pointer encoding | Gray code | CDC-safe; only one bit changes per increment |
| Full detection | MSB comparison | `wgnext == {~wrptr2[MSBs], wrptr2[LSBs]}` |
| Empty detection | Equality check | `rgnext == rwptr2` |

---

## Verification Environment

The UVM testbench (`Testbench/`) implements the following class hierarchy:

```
fifo_uvm_base_test
└── fifo_normal_test
    └── fifo_uvm_env
        ├── write_agent  (UVM_ACTIVE)
        │   ├── write_sequencer
        │   ├── write_driver
        │   └── write_monitor  ──► analysis port
        ├── read_agent  (UVM_ACTIVE)
        │   ├── read_sequencer
        │   ├── read_driver
        │   └── read_monitor   ──► analysis port
        ├── fifo_scoreboard    ◄── write_monitor + read_monitor
        ├── fifo_coverage      ◄── cross_domain_analyzer
        └── cross_domain_analyzer ◄── write_monitor + read_monitor
```

### Key UVM Components

| Component | Class | Role |
|-----------|-------|------|
| Interface | `fifo_if` | Bundles all DUT signals; provides `generate_wrst` / `generate_rrst` tasks |
| Write transaction | `fifo_write_transaction` | Randomized `wdata` (boundary-weighted), `winc` (70% active) |
| Read transaction | `fifo_read_transaction` | Randomized `rinc` (70% active), captures `rdata` |
| Combined transaction | `fifo_combined_transaction` | Cross-domain tuple used by coverage |
| Write sequence | `fifo_write_sequence` | Drives N write transactions with inter-transaction delays |
| Read sequence | `fifo_read_sequence` | Drives N read transactions after a 50 ns head-start delay |
| Scoreboard | `fifo_scoreboard` | Shadow queue checks every read against the expected write order; reports mismatches |
| Coverage | `fifo_coverage` | Covergroup sampling data boundary values (0x00, 0xFF, mid-range), valid write/read events |
| Cross-domain analyzer | `cross_domain_analyzer` | Pairs write and read monitor transactions into combined events for coverage |
| Config objects | `write_agent_config`, `read_agent_config`, `fifo_uvm_env_config` | Parameterized via `uvm_config_db` |

### Randomization Constraints

| Field | Distribution |
|-------|-------------|
| `wdata` | 0x00 → 10%, 0xFF → 10%, 0x01–0xFE → 80% |
| `winc` | Assert → 70%, De-assert → 30% |
| `rinc` | Assert → 70%, De-assert → 30% |

---

## Scoreboard Operation

The scoreboard maintains a shadow FIFO (`expected_data[$]`) in the write clock domain and checks reads in order:

1. **Write monitor** pushes `wdata` into `expected_data` when `winc && !wfull`.
2. **Read monitor** pops the front of `expected_data` and compares it to `rdata` when `rinc && !rempty`.
3. Any mismatch raises a UVM_ERROR; a clean run prints `*** TEST PASSED ***`.

---

## Test Scenarios

| Test | Class | Description |
|------|-------|-------------|
| Normal Operation | `fifo_normal_test` | Concurrent 32-write / 32-read sequences; fork–join; 75 MHz vs. 100 MHz clocks |
| Base (template) | `fifo_uvm_base_test` | 1 µs idle run; used as base class for derived tests |



## References

| Reference | Description |
|-----------|-------------|
| `cummings1_final.pdf` | C. Cummings, *Simulation and Synthesis Techniques for Asynchronous FIFO Design*, SNUG San Jose 2002 — the canonical reference for Gray-code CDC FIFO architecture |
| `Simulation_and_Synthesis_Tech...` | Supporting simulation and synthesis methodology document |
| `Template_FFVDD_Team_1.pptx` | Course presentation slides for the FFVDD Elective Mini Project |

---

## License

This project is licensed under the **MIT License** — see [`LICENSE`](LICENSE) for details.

---


