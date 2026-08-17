`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================================
// FIFO Interface
// ============================================================================
interface fifo_if;
  // Write domain signals
  logic wclk;
  logic wrst_n;
  logic [7:0] wdata;
  logic winc;
  logic wfull;
  logic [4:0] wr_count;
  
  // Read domain signals
  logic rclk;
  logic rrst_n;
  logic [7:0] rdata;
  logic rinc;
  logic rempty;
  logic [4:0] rd_count;
  
  // Reset generation tasks
  task generate_wrst(bit async = 1);
    wrst_n <= 0;
    if (async) begin
      @(posedge wclk);
    end
    repeat (5) @(posedge wclk);
    wrst_n <= 1;
  endtask
  
  task generate_rrst(bit async = 1);
    rrst_n <= 0;
    if (async) begin
      @(posedge rclk);
    end
    repeat (5) @(posedge rclk);
    rrst_n <= 1;
  endtask
  
endinterface

// ============================================================================
// Configuration Classes
// ============================================================================
class write_agent_config extends uvm_object;
  `uvm_object_utils(write_agent_config)
  
  uvm_active_passive_enum active = UVM_ACTIVE;
  bit has_coverage = 0;
  int unsigned wclk_freq_mhz = 100;
  int unsigned DSIZE = 8;
  int unsigned ASIZE = 4;
  
  function new(string name = "write_agent_config");
    super.new(name);
  endfunction
endclass

class read_agent_config extends uvm_object;
  `uvm_object_utils(read_agent_config)
  
  uvm_active_passive_enum active = UVM_ACTIVE;
  bit has_coverage = 0;
  int unsigned rclk_freq_mhz = 75;
  int unsigned DSIZE = 8;
  int unsigned ASIZE = 4;
  
  function new(string name = "read_agent_config");
    super.new(name);
  endfunction
endclass

class fifo_uvm_env_config extends uvm_object;
  `uvm_object_utils(fifo_uvm_env_config)
  
  write_agent_config w_agent_cfg;
  read_agent_config r_agent_cfg;
  bit has_scoreboard = 1;
  bit has_coverage = 1;
  int unsigned num_transactions = 100;
  int unsigned DSIZE = 8;
  int unsigned ASIZE = 4;
  
  function new(string name = "fifo_uvm_env_config");
    super.new(name);
  endfunction
  
  function bit is_valid();
    if (w_agent_cfg == null || r_agent_cfg == null) begin
      `uvm_error("ENV_CONFIG", "Agent configurations are not set")
      return 0;
    end
    return 1;
  endfunction
endclass

// ============================================================================
// Transaction Classes
// ============================================================================
class fifo_write_transaction extends uvm_sequence_item;
  `uvm_object_utils(fifo_write_transaction)
  
  rand bit [7:0] wdata;
  rand bit winc;
  bit wfull;
  bit [4:0] wr_count;
  time write_time;
  
  constraint data_c {
    wdata dist {8'h00 := 10, 8'hFF := 10, [8'h01:8'hFE] := 80};
  }
  
  constraint enable_c {
    winc dist {1 := 70, 0 := 30};
  }
  
  function new(string name = "fifo_write_transaction");
    super.new(name);
  endfunction
  
  function string convert2string();
    return $sformatf("wdata=0x%2h, winc=%b, wfull=%b, time=%0t", wdata, winc, wfull, write_time);
  endfunction
endclass

class fifo_read_transaction extends uvm_sequence_item;
  `uvm_object_utils(fifo_read_transaction)
  
  rand bit rinc;
  bit [7:0] rdata;
  bit rempty;
  bit [4:0] rd_count;
  time read_time;
  int transaction_id;
  
  constraint enable_c {
    rinc dist {1 := 70, 0 := 30};
  }
  
  function new(string name = "fifo_read_transaction");
    super.new(name);
  endfunction
  
  function string convert2string();
    return $sformatf("rinc=%b, rdata=0x%2h, rempty=%b, time=%0t", rinc, rdata, rempty, read_time);
  endfunction
endclass

class fifo_combined_transaction extends uvm_sequence_item;
  `uvm_object_utils(fifo_combined_transaction)
  
  fifo_write_transaction write_tx;
  fifo_read_transaction read_tx;
  bit [7:0] data;
  bit valid_write;
  bit valid_read;
  int latency_cycles;
  
  function new(string name = "fifo_combined_transaction");
    super.new(name);
  endfunction
  
  function string convert2string();
    return $sformatf("data=0x%2h, valid_write=%b, valid_read=%b", data, valid_write, valid_read);
  endfunction
endclass

// ============================================================================
// Sequences (Defined early to avoid forward reference issues)
// ============================================================================
class fifo_write_sequence extends uvm_sequence#(fifo_write_transaction);
  `uvm_object_utils(fifo_write_sequence)
  
  int num_transactions = 20;
  
  function new(string name = "fifo_write_sequence");
    super.new(name);
  endfunction
  
  virtual task body();
    fifo_write_transaction tx;

    // Directed boundary writes: guarantee wdata_cp zero/max_val bins are hit
    // on every run instead of relying on 10% dist weight over random draws
    // (root cause of 77.78% coverage: 32-sample random run can legally miss
    // 0x00 and/or 0xFF entirely -- P(miss both) ~ (0.9^32)^2 ~= 0.1%, and it
    // did on the seed used to log 77.78%/77.38%).
    tx = fifo_write_transaction::type_id::create("tx");
    start_item(tx);
    assert(tx.randomize() with { wdata == 8'h00; winc == 1; });
    finish_item(tx);
    #10ns;

    tx = fifo_write_transaction::type_id::create("tx");
    start_item(tx);
    assert(tx.randomize() with { wdata == 8'hFF; winc == 1; });
    finish_item(tx);
    #10ns;

    repeat (num_transactions) begin
      tx = fifo_write_transaction::type_id::create("tx");
      start_item(tx);
      assert(tx.randomize());
      finish_item(tx);
      #10ns;
    end
  endtask
endclass

class fifo_read_sequence extends uvm_sequence#(fifo_read_transaction);
  `uvm_object_utils(fifo_read_sequence)
  
  int num_transactions = 20;
  
  function new(string name = "fifo_read_sequence");
    super.new(name);
  endfunction
  
  virtual task body();
    fifo_read_transaction tx;
    #50ns; // Delay to let data accumulate
    repeat (num_transactions) begin
      tx = fifo_read_transaction::type_id::create("tx");
      start_item(tx);
      assert(tx.randomize());
      finish_item(tx);
      #10ns;
    end
  endtask
endclass

// ============================================================================
// Write Agent Components
// ============================================================================
class write_sequencer extends uvm_sequencer#(fifo_write_transaction);
  `uvm_component_utils(write_sequencer)
  
  virtual fifo_if vif;
  write_agent_config cfg;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("WRITE_SEQR", "Could not get virtual interface")
    end
  endfunction
endclass

class write_driver extends uvm_driver#(fifo_write_transaction);
  `uvm_component_utils(write_driver)
  
  virtual fifo_if vif;
  write_agent_config cfg;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("WRITE_DRIVER", "Could not get virtual interface")
    end
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    wait (vif.wrst_n == 1);
    
    forever begin
      seq_item_port.get_next_item(req);
      drive_transaction(req);
      req.write_time = $time;
      seq_item_port.item_done();
    end
  endtask
  
  virtual task drive_transaction(fifo_write_transaction trans);
    @(posedge vif.wclk);
    vif.wdata <= trans.wdata;
    vif.winc <= trans.winc;
    trans.wfull = vif.wfull;
    trans.wr_count = vif.wr_count;
  endtask
endclass

class write_monitor extends uvm_monitor;
  `uvm_component_utils(write_monitor)
  
  virtual fifo_if vif;
  uvm_analysis_port#(fifo_write_transaction) ap;
  write_agent_config cfg;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("write_ap", this);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("WRITE_MONITOR", "Could not get virtual interface")
    end
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    fifo_write_transaction wr_trans;
    super.run_phase(phase);
    wait (vif.wrst_n == 1);
    
    forever begin
      @(posedge vif.wclk);
      wr_trans = fifo_write_transaction::type_id::create("write_tr");
      wr_trans.wdata = vif.wdata;
      wr_trans.winc = vif.winc;
      wr_trans.wfull = vif.wfull;
      wr_trans.wr_count = vif.wr_count;
      wr_trans.write_time = $time;
      
      if (vif.winc && !vif.wfull) begin
        ap.write(wr_trans);
      end
    end
  endtask
endclass

class write_agent extends uvm_agent;
  `uvm_component_utils(write_agent)
  
  write_sequencer sequencer;
  write_driver driver;
  write_monitor monitor;
  write_agent_config cfg;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if (!uvm_config_db#(write_agent_config)::get(this, "", "config", cfg)) begin
      `uvm_fatal("WRITE_AGENT", "Could not get agent configuration")
    end
    
    if (cfg.active == UVM_ACTIVE) begin
      sequencer = write_sequencer::type_id::create("sequencer", this);
      driver = write_driver::type_id::create("driver", this);
    end
    monitor = write_monitor::type_id::create("monitor", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction
endclass

// ============================================================================
// Read Agent Components
// ============================================================================
class read_sequencer extends uvm_sequencer#(fifo_read_transaction);
  `uvm_component_utils(read_sequencer)
  
  virtual fifo_if vif;
  read_agent_config cfg;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("READ_SEQR", "Could not get virtual interface")
    end
  endfunction
endclass

class read_driver extends uvm_driver#(fifo_read_transaction);
  `uvm_component_utils(read_driver)
  
  virtual fifo_if vif;
  read_agent_config cfg;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("READ_DRIVER", "Could not get virtual interface")
    end
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    wait (vif.rrst_n == 1);
    
    forever begin
      seq_item_port.get_next_item(req);
      drive_transaction(req);
      req.read_time = $time;
      seq_item_port.item_done();
    end
  endtask
  
  virtual task drive_transaction(fifo_read_transaction trans);
    @(posedge vif.rclk);
    vif.rinc <= trans.rinc;
    trans.rdata = vif.rdata;
    trans.rempty = vif.rempty;
    trans.rd_count = vif.rd_count;
  endtask
endclass

class read_monitor extends uvm_monitor;
  `uvm_component_utils(read_monitor)
  
  virtual fifo_if vif;
  uvm_analysis_port#(fifo_read_transaction) ap;
  read_agent_config cfg;
  int read_transaction_id = 0;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("read_ap", this);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("READ_MONITOR", "Could not get virtual interface")
    end
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    fifo_read_transaction mon_tr;
    super.run_phase(phase);
    wait (vif.rrst_n == 1);
    
    forever begin
      @(posedge vif.rclk);
      mon_tr = fifo_read_transaction::type_id::create("read_tr");
      mon_tr.rinc = vif.rinc;
      mon_tr.rdata = vif.rdata;
      mon_tr.rempty = vif.rempty;
      mon_tr.rd_count = vif.rd_count;
      mon_tr.read_time = $time;
      mon_tr.transaction_id = read_transaction_id;
      read_transaction_id = read_transaction_id + 1;
      
      if (vif.rinc && !vif.rempty) begin
        ap.write(mon_tr);
      end
    end
  endtask
endclass

class read_agent extends uvm_agent;
  `uvm_component_utils(read_agent)
  
  read_sequencer sequencer;
  read_driver driver;
  read_monitor monitor;
  read_agent_config cfg;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if (!uvm_config_db#(read_agent_config)::get(this, "", "config", cfg)) begin
      `uvm_fatal("READ_AGENT", "Could not get agent configuration")
    end
    
    if (cfg.active == UVM_ACTIVE) begin
      sequencer = read_sequencer::type_id::create("sequencer", this);
      driver = read_driver::type_id::create("driver", this);
    end
    monitor = read_monitor::type_id::create("monitor", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction
endclass

// ============================================================================
// Scoreboard
// ============================================================================
class fifo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fifo_scoreboard)
  
  bit [7:0] expected_data[$];
  uvm_analysis_export#(fifo_write_transaction) w_ap;
  uvm_analysis_export#(fifo_read_transaction) r_ap;
  uvm_tlm_analysis_fifo#(fifo_write_transaction) w_fifo;
  uvm_tlm_analysis_fifo#(fifo_read_transaction) r_fifo;
  fifo_uvm_env_config cfg;
  
  bit test_done = 0;
  int total_writes = 0;
  int total_reads = 0;
  int mismatches = 0;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    w_ap = new("write_ap", this);
    r_ap = new("read_ap", this);
    w_fifo = new("w_fifo", this);
    r_fifo = new("r_fifo", this);
    
    if (!uvm_config_db#(fifo_uvm_env_config)::get(this, "", "config", cfg)) begin
      `uvm_warning("SCOREBOARD", "Could not get environment configuration")
    end
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    w_ap.connect(w_fifo.analysis_export);
    r_ap.connect(r_fifo.analysis_export);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    fork
      process_write_transactions();
      process_read_transactions();
    join_none
  endtask
  
  virtual task process_write_transactions();
    fifo_write_transaction w_tr;
    forever begin
      w_fifo.get(w_tr);
      if (w_tr.winc && !w_tr.wfull) begin
        expected_data.push_back(w_tr.wdata);
        total_writes = total_writes + 1;
        `uvm_info("SCOREBOARD", $sformatf("Write: 0x%2h, Queue size: %0d", w_tr.wdata, expected_data.size()), UVM_HIGH)
      end
    end
  endtask
  
  virtual task process_read_transactions();
    fifo_read_transaction r_tr;
    bit [7:0] expected_data_item;
    
    forever begin
      r_fifo.get(r_tr);
      if (r_tr.rinc && !r_tr.rempty) begin
        if (expected_data.size() > 0) begin
          expected_data_item = expected_data.pop_front();
          total_reads = total_reads + 1;
          
          if (r_tr.rdata !== expected_data_item) begin
            mismatches = mismatches + 1;
            `uvm_error("SCOREBOARD", $sformatf("Data mismatch: Expected 0x%2h, Got 0x%2h", expected_data_item, r_tr.rdata))
          end else begin
            `uvm_info("SCOREBOARD", $sformatf("Read: 0x%2h matches", r_tr.rdata), UVM_HIGH)
          end
        end
      end
    end
  endtask
  
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCOREBOARD_REPORT", "=== FIFO Scoreboard Results ===", UVM_LOW)
    `uvm_info("SCOREBOARD_REPORT", $sformatf("Total writes: %0d", total_writes), UVM_LOW)
    `uvm_info("SCOREBOARD_REPORT", $sformatf("Total reads: %0d", total_reads), UVM_LOW)
    `uvm_info("SCOREBOARD_REPORT", $sformatf("Data mismatches: %0d", mismatches), UVM_LOW)
    
    if (mismatches == 0) begin
      `uvm_info("SCOREBOARD_REPORT", "*** TEST PASSED ***", UVM_LOW)
    end else begin
      `uvm_error("SCOREBOARD_REPORT", "*** TEST FAILED ***")
    end
  endfunction
endclass

// ============================================================================
// Coverage - Simplified
// ============================================================================
class fifo_coverage extends uvm_subscriber#(fifo_combined_transaction);
  `uvm_component_utils(fifo_coverage)
  
  fifo_uvm_env_config cfg;
  fifo_combined_transaction tx;
  
  covergroup fifo_cg;
    wdata_cp: coverpoint tx.data {
      bins zero = {0};
      bins max_val = {8'hFF};
      bins others = {[8'h01:8'hFE]};
    }
    
    write_cp: coverpoint tx.valid_write {
      bins write_bin = {1};
      bins no_write = {0};
    }
    
    read_cp: coverpoint tx.valid_read {
      bins read_bin = {1};
      bins no_read = {0};
    }
  endgroup
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
    fifo_cg = new();
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(fifo_uvm_env_config)::get(this, "", "config", cfg)) begin
      `uvm_warning("COVERAGE", "Could not get environment configuration")
    end
  endfunction
  
  virtual function void write(fifo_combined_transaction t);
    tx = t;
    fifo_cg.sample();
  endfunction
  
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COVERAGE", $sformatf("Overall coverage: %0.2f%%", fifo_cg.get_coverage()), UVM_LOW)
  endfunction
endclass

// ============================================================================
// Cross-domain Analyzer
// ============================================================================
class cross_domain_analyzer extends uvm_component;
  `uvm_component_utils(cross_domain_analyzer)
  
  uvm_analysis_export#(fifo_write_transaction) w_ap;
  uvm_analysis_export#(fifo_read_transaction) r_ap;
  uvm_analysis_port#(fifo_combined_transaction) ap;
  uvm_tlm_analysis_fifo#(fifo_write_transaction) w_fifo;
  uvm_tlm_analysis_fifo#(fifo_read_transaction) r_fifo;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    w_ap = new("w_ap", this);
    r_ap = new("r_ap", this);
    ap = new("ap", this);
    w_fifo = new("w_fifo", this);
    r_fifo = new("r_fifo", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    w_ap.connect(w_fifo.analysis_export);
    r_ap.connect(r_fifo.analysis_export);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    fork
      process_combined_transactions();
    join_none
  endtask
  
  virtual task process_combined_transactions();
    fifo_write_transaction w_tr;
    fifo_read_transaction r_tr;
    fifo_combined_transaction comb_tr;
    
    forever begin
      if (w_fifo.try_get(w_tr)) begin
        comb_tr = fifo_combined_transaction::type_id::create("comb_tr");
        comb_tr.write_tx = w_tr;
        comb_tr.data = w_tr.wdata;
        comb_tr.valid_write = w_tr.winc && !w_tr.wfull;
        comb_tr.valid_read = 0;
        ap.write(comb_tr);
      end
      
      if (r_fifo.try_get(r_tr)) begin
        comb_tr = fifo_combined_transaction::type_id::create("comb_tr");
        comb_tr.read_tx = r_tr;
        comb_tr.data = r_tr.rdata;
        comb_tr.valid_write = 0;
        comb_tr.valid_read = r_tr.rinc && !r_tr.rempty;
        ap.write(comb_tr);
      end
      
      #1ns;
    end
  endtask
endclass

// ============================================================================
// Environment
// ============================================================================
class fifo_uvm_env extends uvm_env;
  `uvm_component_utils(fifo_uvm_env)
  
  fifo_uvm_env_config cfg;
  write_agent w_agent;
  read_agent r_agent;
  fifo_scoreboard scoreboard;
  fifo_coverage coverage;
  cross_domain_analyzer cross_analyzer;
  
  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if (!uvm_config_db#(fifo_uvm_env_config)::get(this, "", "config", cfg)) begin
      `uvm_fatal("ENV", "Could not get environment configuration")
    end
    
    w_agent = write_agent::type_id::create("w_agent", this);
    r_agent = read_agent::type_id::create("r_agent", this);
    
    uvm_config_db#(write_agent_config)::set(this, "w_agent", "config", cfg.w_agent_cfg);
    uvm_config_db#(read_agent_config)::set(this, "r_agent", "config", cfg.r_agent_cfg);
    
    if (cfg.has_scoreboard) begin
      scoreboard = fifo_scoreboard::type_id::create("scoreboard", this);
      uvm_config_db#(fifo_uvm_env_config)::set(this, "scoreboard", "config", cfg);
    end
    
    if (cfg.has_coverage) begin
      coverage = fifo_coverage::type_id::create("coverage", this);
      uvm_config_db#(fifo_uvm_env_config)::set(this, "coverage", "config", cfg);
    end
    
    cross_analyzer = cross_domain_analyzer::type_id::create("cross_analyzer", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    if (cfg.has_scoreboard && scoreboard != null) begin
      w_agent.monitor.ap.connect(scoreboard.w_ap);
      r_agent.monitor.ap.connect(scoreboard.r_ap);
    end
    
    w_agent.monitor.ap.connect(cross_analyzer.w_ap);
    r_agent.monitor.ap.connect(cross_analyzer.r_ap);
    
    if (cfg.has_coverage && coverage != null) begin
      cross_analyzer.ap.connect(coverage.analysis_export);
    end
  endfunction
endclass

// ============================================================================
// Base Test
// ============================================================================
class fifo_uvm_base_test extends uvm_test;
  `uvm_component_utils(fifo_uvm_base_test)
  
  fifo_uvm_env env;
  fifo_uvm_env_config env_cfg;
  int num_transactions = 50;
  
  function new(string name = "fifo_uvm_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    env_cfg = fifo_uvm_env_config::type_id::create("env_cfg");
    env_cfg.w_agent_cfg = write_agent_config::type_id::create("w_agent_cfg");
    env_cfg.r_agent_cfg = read_agent_config::type_id::create("r_agent_cfg");
    env_cfg.has_scoreboard = 1;
    env_cfg.has_coverage = 1;
    env_cfg.num_transactions = num_transactions;
    
    uvm_config_db#(fifo_uvm_env_config)::set(this, "env", "config", env_cfg);
    env = fifo_uvm_env::type_id::create("env", this);
  endfunction
  
  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("BASE_TEST", "Starting base test", UVM_LOW)
    #1us;
    `uvm_info("BASE_TEST", "Base test completed", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass

// ============================================================================
// Normal Test
// ============================================================================
class fifo_normal_test extends fifo_uvm_base_test;
  `uvm_component_utils(fifo_normal_test)
  
  fifo_write_sequence write_seq;
  fifo_read_sequence read_seq;
  
  function new(string name = "fifo_normal_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    num_transactions = 32;
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    
    `uvm_info("NORMAL_TEST", "Starting normal operation test", UVM_LOW)
    
    fork
      begin
        write_seq = fifo_write_sequence::type_id::create("write_seq");
        write_seq.num_transactions = 32;
        write_seq.start(env.w_agent.sequencer);
      end
      begin
        read_seq = fifo_read_sequence::type_id::create("read_seq");
        read_seq.num_transactions = 32;
        read_seq.start(env.r_agent.sequencer);
      end
    join
    
    #500ns;
    `uvm_info("NORMAL_TEST", "Normal test completed", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass

// ============================================================================
// Testbench Top Module
// ============================================================================
module fifo_uvm_tb_top;
  
  import uvm_pkg::*;
  
  // Clock signals
  bit wclk;
  bit rclk;
  
  // Interface instance
  fifo_if vif();
  
  // Connect clocks to interface
  assign vif.wclk = wclk;
  assign vif.rclk = rclk;
  
  // DUT instance with count signals set to 0 (simplified)
  fifo1 #(
    .DSIZE(8),
    .ASIZE(4)
  ) dut (
    .wdata(vif.wdata),
    .wfull(vif.wfull),
    .winc(vif.winc),
    .wclk(vif.wclk),
    .wrst_n(vif.wrst_n),
    .rdata(vif.rdata),
    .rempty(vif.rempty),
    .rinc(vif.rinc),
    .rclk(vif.rclk),
    .rrst_n(vif.rrst_n)
  );
  
  // Set count signals to 0 (not available in DUT)
  assign vif.wr_count = 5'h0;
  assign vif.rd_count = 5'h0;
  
  // Write clock generation (100 MHz)
  initial begin
    wclk = 0;
    forever #5ns wclk = ~wclk;
  end
  
  // Read clock generation (75 MHz)
  initial begin
    rclk = 0;
    forever #6.67ns rclk = ~rclk;
  end
  
  // Reset generation
  initial begin
    vif.wrst_n = 0;
    vif.rrst_n = 0;
    vif.winc = 0;
    vif.rinc = 0;
    vif.wdata = 0;
    
    #20ns;
    vif.wrst_n = 1;
    vif.rrst_n = 1;
  end
  
  // UVM configuration and test execution
  initial begin
    // Set virtual interface in config DB
    uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", vif);
    
    // Dump waveforms
    $dumpfile("fifo_uvm_simulation.vcd");
    $dumpvars(0, fifo_uvm_tb_top);
    
    // Run test
    run_test("fifo_normal_test");
  end
  
  // Timeout watchdog
  initial begin
    #10us;
    `uvm_fatal("TIMEOUT", "Simulation timeout reached")
  end
  

endmodule