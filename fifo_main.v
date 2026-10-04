`timescale 1ns / 1ps

// --- 2-Stage Synchronizer ---
module tfsync #(parameter WIDTH=3)(
    input [WIDTH:0] din,
    input clk, rst,
    output reg [WIDTH:0] dout
);
    reg [WIDTH:0] dmeta;
    always @(posedge clk or negedge rst) begin
        if(!rst) begin dmeta <= 0; dout <= 0; end
        else      begin dmeta <= din; dout <= dmeta; end
    end
endmodule

// --- Gray to Binary Converter (Required for Counts) ---
module g2b_convert #(parameter PTR_WIDTH=3) (
    input [PTR_WIDTH:0] gray_input,
    output reg [PTR_WIDTH:0] binary_output
);
    integer i;
    always @(*) begin
        binary_output[PTR_WIDTH] = gray_input[PTR_WIDTH];
        for (i = PTR_WIDTH-1; i >= 0; i = i - 1) begin                         //g to b
            binary_output[i] = binary_output[i+1] ^ gray_input[i];          //for(i=0;iN-1;i++)begin
        end                                                                  //  assign binary_num[i]=^(graycode_num>>i);
    end                                                                       //  assign binary_num[N-1]=graycode_num[N-1];
endmodule

// --- Write Pointer Handler ---
module wptr_handler #(parameter WIDTH=3) (
    input wclk, wrst, w_en,
    input [WIDTH:0] g_rptr_sync,
    output reg [WIDTH:0] b_wptr,
    output reg [WIDTH:0] g_wptr,
    output reg full
);
    wire [WIDTH:0] b_wptr_nxt, g_wptr_nxt;
    assign b_wptr_nxt = b_wptr + (w_en & !full);
    assign g_wptr_nxt = b_wptr_nxt ^ (b_wptr_nxt >> 1);

    always @(posedge wclk or negedge wrst) begin
        if(!wrst) begin b_wptr <= 0; g_wptr <= 0; end
        else      begin b_wptr <= b_wptr_nxt; g_wptr <= g_wptr_nxt; end
    end

    always @(posedge wclk or negedge wrst) begin
        if(!wrst) full <= 0;
        else      full <= (g_wptr_nxt == {~(g_rptr_sync[WIDTH:WIDTH-1]), g_rptr_sync[WIDTH-2:0]});
    end
endmodule

// --- Read Pointer Handler (FWFT Optimized) ---
module rptr_handler #(parameter WIDTH=3) (
    input rclk, rrst, r_en,
    input [WIDTH:0] g_wptr_sync,
    output reg [WIDTH:0] b_rptr,
    output reg [WIDTH:0] g_rptr,
    output reg empty
);
    wire [WIDTH:0] b_rptr_nxt, g_rptr_nxt;
    // FWFT: Increment when user acknowledges current data and FIFO isn't empty
    assign b_rptr_nxt = b_rptr + (r_en & !empty);
    assign g_rptr_nxt = b_rptr_nxt ^ (b_rptr_nxt >> 1);

    always @(posedge rclk or negedge rrst) begin
        if(!rrst) begin b_rptr <= 0; g_rptr <= 0; end
        else      begin b_rptr <= b_rptr_nxt; g_rptr <= g_rptr_nxt; end
    end

    always @(posedge rclk or negedge rrst) begin
        if(!rrst) empty <= 1;
        else      empty <= (g_wptr_sync == g_rptr_nxt);
    end
endmodule

// --- FIFO Memory (FWFT: Combinational Read) ---
module fifo #(parameter DEPTH=8, DATA_WIDTH=8, PTR_WIDTH=3) (
    input w_clk, w_en, full,
    input [PTR_WIDTH:0] b_wptr, b_rptr,
    input [DATA_WIDTH-1:0] data_in,
    output [DATA_WIDTH-1:0] data_out
);
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    always @(posedge w_clk) if(w_en & !full) mem[b_wptr[PTR_WIDTH-1:0]] <= data_in;
    // Fall-through data
    assign data_out = mem[b_rptr[PTR_WIDTH-1:0]];
endmodule

// --- Top Level Asynchronous FIFO ---
module asynchronous_fifo #(parameter DEPTH=8, DATA_WIDTH=8, PTR_WIDTH=3) (
  input wclk, wrst_n,
  input rclk, rrst_n,
  input w_en, r_en,
  input [DATA_WIDTH-1:0] data_in,
  output [DATA_WIDTH-1:0] data_out,
  output full, empty,
  output [PTR_WIDTH:0] w_count, // Filling status in Write Domain
  output [PTR_WIDTH:0] r_count  // Availability status in Read Domain
);
    wire [PTR_WIDTH:0] g_wptr_sync, g_rptr_sync;
    wire [PTR_WIDTH:0] b_wptr, b_rptr;
    wire [PTR_WIDTH:0] g_wptr, g_rptr;
    wire [PTR_WIDTH:0] b_wptr_sync, b_rptr_sync;

    // Domain Synchronizers
    tfsync #(PTR_WIDTH) sync_r2w (g_rptr, wclk, wrst_n, g_rptr_sync);
    tfsync #(PTR_WIDTH) sync_w2r (g_wptr, rclk, rrst_n, g_wptr_sync);

    // Handlers
    wptr_handler #(PTR_WIDTH) w_h (wclk, wrst_n, w_en, g_rptr_sync, b_wptr, g_wptr, full);
    rptr_handler #(PTR_WIDTH) r_h (rclk, rrst_n, r_en, g_wptr_sync, b_rptr, g_rptr, empty);

    // Memory
    fifo #(DEPTH, DATA_WIDTH, PTR_WIDTH) mem_m (wclk, w_en, full, b_wptr, b_rptr, data_in, data_out);

    // --- Data Count Generation ---
    g2b_convert #(PTR_WIDTH) g2b_r_inst (g_rptr_sync, b_rptr_sync);
    g2b_convert #(PTR_WIDTH) g2b_w_inst (g_wptr_sync, b_wptr_sync);

    assign w_count = b_wptr - b_rptr_sync;
    assign r_count = b_wptr_sync - b_rptr;

endmodule
