// SPDX-License-Identifier: MIT
// TinyTapeout user project: VGA-Pattern-Generator (Sky130)
// Top-Level: tt_um_lukasdragoste_vga_patterns

`default_nettype none

/* verilator lint_off UNUSEDSIGNAL */ // uio_in is required by the TT harness but unused here.
/* verilator lint_off UNUSEDPARAM */  // H_BACK/V_BACK are unused but useful for context.
module tt_um_lukasdragoste_vga_patterns (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,
    input  wire [7:0]  ui_in,
    output wire [7:0]  uo_out,
    input  wire [7:0]  uio_in,
    output wire [7:0]  uio_out,
    output wire [7:0]  uio_oe
);
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire active = ena & rst_n;

    // ------------ VGA timing 640x480@60 (800x525 total) ------------
    localparam [9:0] H_VISIBLE = 640;
    localparam [9:0] H_FRONT   = 16;
    localparam [9:0] H_SYNC    = 96;
    localparam [9:0] H_BACK    = 48; // Unused, but kept for documentation
    localparam [9:0] H_TOTAL   = 800;

    localparam [9:0] V_VISIBLE = 480;
    localparam [9:0] V_FRONT   = 10;
    localparam [9:0] V_SYNC    = 2;
    localparam [9:0] V_BACK    = 33; // Unused, but kept for documentation
    localparam [9:0] V_TOTAL   = 525;

    reg [9:0] h_cnt, v_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin h_cnt<=0; v_cnt<=0; end
        else if (!ena) begin h_cnt<=0; v_cnt<=0; end
        else begin
            if (h_cnt == H_TOTAL-1) begin
                h_cnt <= 0;
                v_cnt <= (v_cnt == V_TOTAL-1) ? 0 : v_cnt + 1;
            end else begin
                h_cnt <= h_cnt + 1;
            end
        end
    end

    wire vis      = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);
    wire hsync_n  = active ? ~((h_cnt >= (H_VISIBLE+H_FRONT)) && (h_cnt < (H_VISIBLE+H_FRONT+H_SYNC))) : 1'b1;
    wire vsync_n  = active ? ~((v_cnt >= (V_VISIBLE+V_FRONT)) && (v_cnt < (V_VISIBLE+V_FRONT+V_SYNC))) : 1'b1;

    // ------------ Tiny timebase for motion (cheap!) ------------
    reg [15:0] t;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) t <= 0;
        else if (!ena) t <= 0;
        else if (h_cnt==H_TOTAL-1 && v_cnt==V_TOTAL-1) begin
            t <= t + 1;
        end
    end

    // Speed & animate controls
    wire animate      = ui_in[7];
    wire [1:0] speed  = ui_in[6:5];
    wire [1:0] palctl = ui_in[4:3];
    wire [2:0] mode   = ui_in[2:0];

    wire [7:0] t_scroll = animate ? { (speed==2'b00)? t[7]  :
                                      (speed==2'b01)? t[8]  :
                                      (speed==2'b10)? t[9]  : t[10],
                                      t[6:0] } : 8'h00;

    wire [7:0] x = h_cnt[9:2];
    wire [7:0] y = v_cnt[9:2];

    wire [7:0] x2 = x + (animate ? {5'b0, t[2:0]} : 8'h00);
    wire [7:0] y2 = y + (animate ? {5'b0, t[4:2]} : 8'h00);

    // ------------ LFSR (for noise and dithery looks) ------------
    reg [7:0] lfsr;
    wire lfsr_fb = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lfsr <= 8'h1;
        else if (!ena)   lfsr <= 8'h1;
        else if (h_cnt==0) lfsr <= (v_cnt[7:0]) ^ 8'h5A ^ {7'b0, animate};
        else lfsr <= {lfsr[6:0], lfsr_fb};
    end

    // ------------ Patterns (prettier + optionally animated) ------------
    wire [8:0] x3 = {x2,1'b0} + x2;
    wire [9:0] y5 = {y2,2'b00} + {2'b0, y2};
    wire [7:0] swirl = (x2 ^ {3'b000,y2[7:3]}) + ({y2[6:0],1'b0} ^ {2'b00,x2[7:2]});

    reg [7:0] pix;
    always @* begin
        case (mode)
            3'd0: pix = {8{ (x2[5]^y2[5]) }} ^ {y2[2:0], x2[4:0]};
            3'd1: pix = {x2[7:4] + t_scroll[7:4], y2[7:4]};
            3'd2: pix = swirl;
            3'd3: pix = ( (x2 & y2) ^ (x3[7:0] + y5[7:0]) );
            3'd4: pix = lfsr ^ {x2[3:0], y2[3:0]};
            3'd5: pix = {8{ (x2[4]^x2[3]^y2[4]^y2[3]) }} ^ {x2[2:0],y2[4:0]};
            3'd6: pix = (x2 + y2) ^ {t_scroll[6:0],1'b0};
            default: pix = {x2[7:6], y2[7:6], x2[5:4], y2[5:4]};
        endcase
    end

    // ------------ Nicer palette mapping (still 6-bit RGB) ------------
    wire [7:0] p = (pix ^ {5'b0, palctl, 1'b0}) ^ {pix[6:0], pix[7]};

    wire [1:0] r = { p[7] | p[5], p[4] ^ p[1] };
    wire [1:0] g = { p[6] | p[3], p[2] ^ p[0] };
    wire [1:0] b = { p[5] | p[2], p[3] ^ p[1] };

    wire [1:0] r_vis = (active && vis) ? r : 2'b00;
    wire [1:0] g_vis = (active && vis) ? g : 2'b00;
    wire [1:0] b_vis = (active && vis) ? b : 2'b00;

    // ------------ Output mapping (unchanged) ------------
    assign uo_out[0] = r_vis[1]; // R1
    assign uo_out[1] = g_vis[1]; // G1
    assign uo_out[2] = b_vis[1]; // B1
    assign uo_out[3] = vsync_n;
    assign uo_out[4] = r_vis[0]; // R0
    assign uo_out[5] = g_vis[0]; // G0
    assign uo_out[6] = b_vis[0]; // B0
    assign uo_out[7] = hsync_n;

endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on UNUSEDPARAM */

`default_nettype wire
