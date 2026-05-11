`timescale 1ns/1ps

module async_fifo_TB;
    parameter DATA_WIDTH = 8;
    parameter PTR_WIDTH = 3;

    wire [DATA_WIDTH-1:0] dataout;
    wire full, empty;
    wire [PTR_WIDTH:0] w_count, r_count;
    reg [DATA_WIDTH-1:0] datain;
    reg w_en, wrclk, wrst, r_en, rclk, rrst;

    asynchronous_fifo #(8, 8, 3) dut (
        .wclk(wrclk), .wrst_n(wrst), .rclk(rclk), .rrst_n(rrst),
        .w_en(w_en), .r_en(r_en), .data_in(datain), .data_out(dataout),
        .full(full), .empty(empty), .w_count(w_count), .r_count(r_count)
    );

    // Clocks
    initial begin wrclk = 0; rclk = 0; end
    always #5  wrclk = ~wrclk; // 100MHz
    always #15 rclk  = ~rclk;  // 33MHz

    initial begin
        // Reset
        wrst = 0; rrst = 0; w_en = 0; r_en = 0; datain = 0;
        #100 wrst = 1; rrst = 1;
        #50;

        $display("--- Starting Advanced FIFO Test ---");

        // 1. FWFT Check: Write D1
        @(posedge wrclk);
        w_en <= 1; datain <= 8'hD1;
        @(posedge wrclk);
        w_en <= 0;

        wait(empty == 0);
        #1;
        $display("Time %0t: FWFT Check -> Data: %h (Expected D1)", $time, dataout);

        // 2. Fill more
        @(posedge wrclk);
        w_en <= 1; datain <= 8'hD2;
        @(posedge wrclk);
        w_en <= 1; datain <= 8'hD3;
        @(posedge wrclk);
        w_en <= 0;

        repeat(5) @(posedge rclk);
        $display("Time %0t: Count Check -> w_count: %0d, r_count: %0d", $time, w_count, r_count);

        // 3. THE FIX: Precise Single-Word Read
        // Asserting for exactly one clock cycle using non-blocking assignments
        @(posedge rclk);
        r_en <= 1;
        @(posedge rclk);
        r_en <= 0;
        
        #5; // Allow for pointer increment and FWFT fall-through
        $display("Time %0t: After 1 Read -> Data Out: %h (Expected D2)", $time, dataout);
        $display("Time %0t: Current w_count: %0d", $time, w_count);

        #500;
        $display("--- Test Completed ---");
        $finish;
    end
endmodule