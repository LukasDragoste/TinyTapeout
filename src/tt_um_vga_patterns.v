`default_nettype none

module tt_um_vga_patterns (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // Bidirectional I/O (unused)
    output wire [7:0] uio_out,  // Bidirectional I/O (unused)
    output wire [7:0] uio_oe,   // Bidirectional I/O (unused)
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // --- Unused Bidirectional I/O ---
    // Tie all uio outputs to 0 and set them as inputs
    assign uio_out = 8'b0;
    assign uio_oe = 8'b0;

    // --- Instantiate our VGA Generator ---
    // The core of our design
    vga_generator vga_gen (
        .clk(clk),
        .rst(~rst_n), // Project uses active-high reset
        .ui_in(ui_in),
        .uo_out(uo_out)
    );

endmodule