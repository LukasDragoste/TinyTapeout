`default_nettype none
`timescale 1ns/1ps

module testbench;

    // --- Testbench Inputs & Outputs ---
    reg clk;
    reg rst_n;
    reg [7:0] ui_in;
    wire [7:0] uo_out;

    // --- Unused DUT I/O ---
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg ena;

    // --- Moved Variable Declarations for Verilog-2005 Compliance ---
    integer file;
    integer scaled_r, scaled_g, scaled_b;
    integer x, y; // Loop variables

    // --- Instantiate the DUT (Design Under Test) ---
    tt_um_vga_patterns dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    // --- Signal Aliases for Clarity ---
    wire hsync, vsync;
    wire [1:0] r, g, b;

    assign hsync = uo_out[0];
    assign vsync = uo_out[1];
    assign r = {uo_out[3], uo_out[2]};
    assign g = {uo_out[5], uo_out[4]};
    assign b = {uo_out[7], uo_out[6]};

    // --- Clock Generation (100 MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 5ns high, 5ns low -> 10ns period -> 100MHz
    end

    // --- Main Simulation Block ---
    initial begin
        $display("Starting Verilog-2005 compatible simulation...");

        // --- Run for Pattern 0: Color Bars ---
        $display("Testing Pattern 0: Color Bars");
        rst_n = 1'b0; // Assert reset
        ui_in = 8'h00;
        ena = 1'b1;
        uio_in = 8'b0;
        #20;
        rst_n = 1'b1; // De-assert reset
        #20;

        file = $fopen("pattern_0.ppm", "w");
        $fdisplay(file, "P3");
        $fdisplay(file, "160 120"); // Image width and height
        $fdisplay(file, "255");   // Max color value

        @(negedge vsync); // Wait for the beginning of a frame

        for (y = 0; y < 120; y = y + 1) begin
            @(posedge hsync); @(negedge hsync); #1;
            for (x = 0; x < 160; x = x + 1) begin
                @(posedge clk); @(posedge clk);
                scaled_r = r * 85; scaled_g = g * 85; scaled_b = b * 85;
                $fdisplay(file, "%3d %3d %3d", scaled_r, scaled_g, scaled_b);
            end
        end
        $fclose(file);
        $display("Frame captured to pattern_0.ppm");

        // --- Run for Pattern 1: Checkerboard ---
        $display("Testing Pattern 1: Checkerboard");
        rst_n = 1'b0; // Re-assert reset for a clean state
        ui_in = 8'h01; // Change input for the next pattern
        #20;
        rst_n = 1'b1; // De-assert reset
        #20;

        file = $fopen("pattern_1.ppm", "w");
        $fdisplay(file, "P3");
        $fdisplay(file, "160 120");
        $fdisplay(file, "255");

        @(negedge vsync); // Wait for the beginning of a new frame

        for (y = 0; y < 120; y = y + 1) begin
            @(posedge hsync); @(negedge hsync); #1;
            for (x = 0; x < 160; x = x + 1) begin
                @(posedge clk); @(posedge clk);
                scaled_r = r * 85; scaled_g = g * 85; scaled_b = b * 85;
                $fdisplay(file, "%3d %3d %3d", scaled_r, scaled_g, scaled_b);
            end
        end
        $fclose(file);
        $display("Frame captured to pattern_1.ppm");

        $display("Simulation finished.");
        $finish;
    end

endmodule