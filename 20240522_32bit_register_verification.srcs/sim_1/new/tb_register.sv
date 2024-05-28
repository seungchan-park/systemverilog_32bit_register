`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/22 09:56:37
// Design Name: 
// Module Name: tb_register
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

interface reg_interface;
    logic        clk;
    logic        reset;
    logic [31:0] d;
    logic [31:0] q;
endinterface  //reg_interface

class transaction;
    rand logic [31:0] data;
    logic      [31:0] out;

    task display(string name);
        $display("[%s] data: %x, out: %x", name, data, out);
    endtask
endclass  //transaction

class generator;
    transaction trans;
    mailbox #(transaction) gen2drv_mbox; // #(transaction) 안해줘도 알아서 판단함
    event gen_next_event;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.gen_next_event = gen_next_event;
    endfunction  //new()

    task run(int count);
        repeat (count) begin
            trans = new();
            assert (trans.randomize())
            else $error("[GEN] trans.randomize() error!");
            gen2drv_mbox.put(trans);
            trans.display("[GEN]");
            @(gen_next_event);
        end
    endtask
endclass  //generator

class driver;
    virtual reg_interface reg_if;
    transaction trans;
    mailbox #(transaction) gen2drv_mbox;

    function new(virtual reg_interface reg_if,
                 mailbox#(transaction) gen2drv_mbox);
        this.reg_if = reg_if;
        this.gen2drv_mbox = gen2drv_mbox;
    endfunction  //new()

    task reset();
        reg_if.reset <= 1'b1;
        reg_if.d <= 0;
        repeat (5) @(posedge reg_if.clk);
        reg_if.reset <= 1'b0;
    endtask

    task run();
        forever begin
            //@(posedge reg_if.clk);
            gen2drv_mbox.get(
                trans);  // mailbox reference memory는 지워진다
            reg_if.d <= trans.data;  // input
            trans.display("[DRV]");
            @(posedge reg_if.clk);
            // output
        end
    endtask
endclass  //driver

class monitor;
    transaction trans;
    virtual reg_interface reg_if;
    mailbox #(transaction) mon2scb_mbox;

    function new(virtual reg_interface reg_if,
                 mailbox#(transaction) mon2scb_mbox);
        this.reg_if = reg_if;
        this.mon2scb_mbox = mon2scb_mbox;
    endfunction  //new()

    task run();
        forever begin
            trans = new();
            //@(posedge reg_if.clk);
            trans.data = reg_if.d;
            @(posedge reg_if.clk);
            trans.out = reg_if.q;
            mon2scb_mbox.put(trans);
            trans.display("[MON]");
        end
    endtask
endclass  //monitor

class scoreboard;
    transaction trans;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_event;

    int total_cnt, pass_cnt, fail_cnt;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_event);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_event = gen_next_event;
        total_cnt = 0;
        pass_cnt = 0;
        fail_cnt = 0;
    endfunction  //new()

    task run();
        forever begin
            mon2scb_mbox.get(trans);
            trans.display("[SCB]");
            if (trans.data == trans.out) begin
                $display(" --> PASS! %d == %d", trans.data, trans.out);
                pass_cnt++;
            end else begin
                $display(" --> FAIL! %d != %d", trans.data, trans.out);
                fail_cnt++;
            end
            total_cnt++;
            ->gen_next_event;
        end
    endtask
endclass  //scoreboard

class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    event gen_next_event;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    function new(virtual reg_interface reg_if);
        gen2drv_mbox = new();
        mon2scb_mbox = new();

        gen = new(gen2drv_mbox, gen_next_event);
        drv = new(reg_if, gen2drv_mbox);
        mon = new(reg_if, mon2scb_mbox);
        scb = new(mon2scb_mbox, gen_next_event);
    endfunction  //new()

    task report();
        $display("==================================");
        $display("==         Final Report         ==");
        $display("==================================");
        $display("Total Test : %d", scb.total_cnt);
        $display("Pass Test : %d", scb.pass_cnt);
        $display("Fail Test : %d", scb.fail_cnt);
        $display("==================================");
        $display("==    testbench is finished!    ==");
        $display("==================================");
    endtask

    task pre_run();
        drv.reset();
    endtask

    task run();
        fork
            gen.run(10);
            drv.run();
            mon.run();
            scb.run();
        join_any
        report();
        #10 $finish;
    endtask

    task run_test();
        pre_run();
        run();
    endtask
endclass  //environment

module tb_register ();
    reg_interface reg_if ();
    environment env;

    register dut (
        .clk(reg_if.clk),
        .reset(reg_if.reset),
        .d(reg_if.d),
        .q(reg_if.q)
    );

    always #5 reg_if.clk = ~reg_if.clk;

    initial begin
        reg_if.clk = 1'b0;
    end

    initial begin
        env = new(reg_if);
        env.run_test();
    end
endmodule
