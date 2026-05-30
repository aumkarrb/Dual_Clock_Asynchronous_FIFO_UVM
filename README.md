# Dual Clock Asynchronous FIFO UVM Verification
--------------------------------------------------------------------------------
## 1. OVERVIEW
--------------------------------------------------------------------------------

This project implements and verifies a Dual Clock Asynchronous FIFO using the
Universal Verification Methodology (UVM) 1.2 framework. The design is written
in Verilog and the verification environment is built in SystemVerilog. The
FIFO safely transfers data between two independent, asynchronous clock domains
using Gray-coded pointer synchronization to mitigate metastability.

--------------------------------------------------------------------------------
## 2 . DESIGN ARCHITECTURE
--------------------------------------------------------------------------------

The design follows the modular architecture described in the seminal paper by
Clifford E. Cummings, "Simulation and Synthesis Techniques for Asynchronous
FIFO Design" (SNUG 2002). It is composed of five hierarchically connected
Verilog modules instantiated under a single top-level wrapper.

--------------------------------------------------------------------------------
## 3. VERILOG DESIGN MODULE DESCRIPTIONS
--------------------------------------------------------------------------------

All design files are located under the /Design directory.

+------------------+-------------------+----------------------------------------+
| Module Name      | File              | Description                            |
+------------------+-------------------+----------------------------------------+
| async_fifo       | async_fifo.v      | TOP-LEVEL WRAPPER. Instantiates all    |
|                  |                   | sub-modules and exposes the primary     |
|                  |                   | interface: wclk, rclk, rst_n, winc,    |
|                  |                   | rinc, wdata, rdata, wfull, rempty.     |
|                  |                   | Parameters: DSIZE (data width),        |
|                  |                   | ASIZE (address width, depth = 2^ASIZE) |
+------------------+-------------------+----------------------------------------+
| fifomem          | fifomem.v         | DUAL-PORT SRAM / REGISTER FILE.        |
|                  |                   | Implements the actual storage array    |
|                  |                   | of depth 2^ASIZE and width DSIZE bits. |
|                  |                   | Write port is clocked by wclk;         |
|                  |                   | read port is combinational (or clocked |
|                  |                   | by rclk). Addressed via binary waddr   |
|                  |                   | and raddr from the control modules.    |
+------------------+-------------------+----------------------------------------+
| wptr_full        | wptr_full.v       | WRITE POINTER & FULL FLAG LOGIC.       |
|                  |                   | Operates entirely in the wclk domain.  |
|                  |                   | Maintains a (ASIZE+1)-bit binary write |
|                  |                   | pointer; converts it to Gray code      |
|                  |                   | (wptr) for safe CDC. Compares wptr     |
|                  |                   | against the synchronized read pointer  |
|                  |                   | (wq2_rptr) to assert wfull when the    |
|                  |                   | FIFO cannot accept more data. The MSB  |
|                  |                   | of the Gray-coded pointers is used to  |
|                  |                   | detect full vs. empty conditions.      |
+------------------+-------------------+----------------------------------------+
| rptr_empty       | rptr_empty.v      | READ POINTER & EMPTY FLAG LOGIC.       |
|                  |                   | Operates entirely in the rclk domain.  |
|                  |                   | Maintains a (ASIZE+1)-bit binary read  |
|                  |                   | pointer; converts it to Gray code      |
|                  |                   | (rptr) for safe CDC. Compares rptr     |
|                  |                   | against the synchronized write pointer |
|                  |                   | (rq2_wptr) to assert rempty when no    |
|                  |                   | valid data is available for reading.   |
+------------------+-------------------+----------------------------------------+
| sync_w2r         | sync_w2r.v        | WRITE-TO-READ POINTER SYNCHRONIZER.    |
|                  |                   | A 2-stage flip-flop synchronizer       |
|                  |                   | (double-flop) clocked by rclk.         |
|                  |                   | Safely transfers the Gray-coded write  |
|                  |                   | pointer (wptr) from the wclk domain    |
|                  |                   | into the rclk domain (rq2_wptr),       |
|                  |                   | mitigating metastability at the        |
|                  |                   | clock domain crossing boundary.        |
+------------------+-------------------+----------------------------------------+
| sync_r2w         | sync_r2w.v        | READ-TO-WRITE POINTER SYNCHRONIZER.    |
|                  |                   | A 2-stage flip-flop synchronizer       |
|                  |                   | (double-flop) clocked by wclk.         |
|                  |                   | Safely transfers the Gray-coded read   |
|                  |                   | pointer (rptr) from the rclk domain    |
|                  |                   | into the wclk domain (wq2_rptr),       |
|                  |                   | mitigating metastability at the        |
|                  |                   | clock domain crossing boundary.        |
+------------------+-------------------+----------------------------------------+

KEY PARAMETERS (configurable at instantiation):
  DSIZE  — Data bus width in bits        (default: 8)
  ASIZE  — Address bus width in bits     (default: 4, gives depth of 2^4 = 16)

KEY INTERFACE SIGNALS:
  +----------+-----+--------+----------------------------------------------------+
  | Signal   | Dir | Domain | Description                                        |
  +----------+-----+--------+----------------------------------------------------+
  | wclk     | IN  | Write  | Write-side clock                                   |
  | rclk     | IN  | Read   | Read-side clock                                    |
  | rst_n    | IN  | Both   | Active-low asynchronous reset                      |
  | winc     | IN  | Write  | Write enable (push); ignored when wfull is high    |
  | rinc     | IN  | Read   | Read enable (pop); ignored when rempty is high     |
  | wdata    | IN  | Write  | Data input bus [DSIZE-1:0]                         |
  | rdata    | OUT | Read   | Data output bus [DSIZE-1:0]                        |
  | wfull    | OUT | Write  | FIFO full flag; asserted in wclk domain            |
  | rempty   | OUT | Read   | FIFO empty flag; asserted in rclk domain           |
  +----------+-----+--------+----------------------------------------------------+

--------------------------------------------------------------------------------
## 3. REPOSITORY STRUCTURE
--------------------------------------------------------------------------------

Dual_Clock_Asynchronous_FIFO_UVM/
|
+-- Design/                      # RTL design source files (Verilog)
|   +-- async_fifo.v             # Top-level FIFO module
|   +-- fifomem.v                # Dual-port SRAM storage array
|   +-- wptr_full.v              # Write pointer and wfull flag logic
|   +-- rptr_empty.v             # Read pointer and rempty flag logic
|   +-- sync_w2r.v               # 2-FF synchronizer: wclk -> rclk
|   +-- sync_r2w.v               # 2-FF synchronizer: rclk -> wclk
|
+-- Testbench/                   # UVM 1.2 verification environment (SystemVerilog)
|   +-- fifo_if.sv               # SystemVerilog interface (DUT connections)
|   +-- fifo_seq_item.sv         # UVM sequence item (transaction class)
|   +-- fifo_sequence.sv         # UVM sequences (test stimulus generators)
|   +-- fifo_driver.sv           # UVM driver (pin-level stimulus)
|   +-- fifo_monitor.sv          # UVM monitor (passive observer)
|   +-- fifo_scoreboard.sv       # UVM scoreboard (checker / reference model)
|   +-- fifo_coverage.sv         # Functional coverage collector
|   +-- fifo_agent.sv            # UVM agent (bundles driver + monitor + sequencer)
|   +-- fifo_env.sv              # UVM environment (top-level TB container)
|   +-- fifo_test.sv             # UVM test class(es)
|   +-- fifo_tb_top.sv           # Top-level simulation module (DUT + TB bind)
|
+-- Output/                      # Simulation output artifacts
|   +-- *.log                    # Simulator log files
|   +-- *.vcd / *.fsdb           # Waveform dump files (for GTKWave / Verdi)
|   +-- coverage_report/         # Functional and code coverage reports
|
+-- References/                  
|   +-- Cummings_SNUG2002.pdf    
|   +-- uvm_12_ref_guide.pdf     
|
+-- LICENSE                      
+-- README.md                    



--------------------------------------------------------------------------------
## 4. REFERENCES
--------------------------------------------------------------------------------

  [1] Clifford E. Cummings, "Simulation and Synthesis Techniques for
      Asynchronous FIFO Design," SNUG 2002 (Synopsys Users Group Conference),
      San Jose, CA. Available at: www.sunburst-design.com/papers/

 




