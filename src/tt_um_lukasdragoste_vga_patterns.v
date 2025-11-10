// SPDX-License-Identifier: MIT
// TinyTapeout user project: VGA-Pattern-Generator (Sky130)
// Author: Lukas Dragoste (angepasst)
// Top-Level: tt_um_lukasdragoste_vga_patterns
//
// Beschreibung:
// - Erzeugt 640x480@60Hz (VGA) mit 6-Bit-Farbe (R,G,B je 2 Bit).
// - Verschiedene Muster (Checker/XOR, Tiles, Plasma-ähnlich, Moiré, LFSR-Noise, Diagonalen).
// - ui_in[2:0] = Mode (0..5), ui_in[7:3] = einfache Paletten/Scroll-Variation.
// - uo_out[7:0] = {HSYNC_n, B0, G0, R0, VSYNC_n, B1, G1, R1} (siehe Mapping unten).
// - Wenn ena=0 oder rst_n=0: RGB=schwarz, HS/VS=High (inaktiv).
//
// Pin-Mapping (OUT → TinyVGA):
//   uo_out[0] = R1
//   uo_out[1] = G1
//   uo_out[2] = B1
//   uo_out[3] = VSYNC (low-aktiv)
//   uo_out[4] = R0
//   uo_out[5] = G0
//   uo_out[6] = B0
//   uo_out[7] = HSYNC (low-aktiv)
//
// Hinweise:
// - Empfohlene Pixelclock: ~25.175/25.179 MHz.
// - Die Logik ist bewusst leichtgewichtig (keine RAMs, nur einfache Bit-Operationen).
// - Kompatibel mit TinyTapeout-Top-Signatur.
//
// --------------------------------------------------------------------------

`default_nettype none

module tt_um_lukasdragoste_vga_patterns (
    input  wire        clk,     // ~25.175/25.179 MHz
    input  wire        rst_n,   // async active-low reset
    input  wire        ena,     // high = project active (Ausgänge gültig)
    input  wire [7:0]  ui_in,   // [2:0]=Mode, [7:3]=Palette/Scroll
    output wire [7:0]  uo_out,  // VGA-Outputs (siehe Mapping)
    input  wire [7:0]  uio_in,  // ungenutzt
    output wire [7:0]  uio_out, // ungenutzt
    output wire [7:0]  uio_oe   // ungenutzt
);
    // Bidirectional-IOs deaktivieren
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    // "active" wenn Projekt eingeschaltet und Reset frei
    wire active = ena & rst_n;

    // ---------------------------
    // VGA-Timing 640x480@60 Hz
    // Total: 800 x 525, HSYNC low 96, VSYNC low 2
    // ---------------------------
    localparam integer H_VISIBLE = 640;
    localparam integer H_FRONT   = 16;
    localparam integer H_SYNC    = 96;
    localparam integer H_BACK    = 48;
    localparam integer H_TOTAL   = 800;

    localparam integer V_VISIBLE = 480;
    localparam integer V_FRONT   = 10;
    localparam integer V_SYNC    = 2;
    localparam integer V_BACK    = 33;
    localparam integer V_TOTAL   = 525;

    reg [9:0] h_cnt;  // 0..799
    reg [9:0] v_cnt;  // 0..524

    // Zähler
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if (!ena) begin
            // wenn Projekt nicht aktiv, nicht "herumzappeln":
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == H_TOTAL-1) begin
                h_cnt <= 10'd0;
                v_cnt <= (v_cnt == V_TOTAL-1) ? 10'd0 : (v_cnt + 10'd1);
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    // Sichtbar / Syncs (low-aktiv)
    wire vis = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);
    wire hsync_n_timing =
        ~((h_cnt >= H_VISIBLE + H_FRONT) && (h_cnt < H_VISIBLE + H_FRONT + H_SYNC));
    wire vsync_n_timing =
        ~((v_cnt >= V_VISIBLE + V_FRONT) && (v_cnt < V_VISIBLE + V_FRONT + V_SYNC));

    // ---------------------------
    // LFSR (8 Bit), pro Zeile neu "gesalzen"
    // ---------------------------
    reg  [7:0] lfsr;
    wire       lfsr_fb = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]; // x^8+x^6+x^5+x^4+1

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 8'h1;
        end else if (!ena) begin
            lfsr <= 8'h1;
        end else begin
            if (h_cnt == 10'd0) begin
                // pro Zeile neu initialisieren
                lfsr <= (v_cnt[7:0]) ^ 8'h5A;
            end else begin
                lfsr <= {lfsr[6:0], lfsr_fb};
            end
        end
    end

    // ---------------------------
    // Muster-Generator
    // ---------------------------
    wire [2:0] mode = ui_in[2:0];
    wire [4:0] pal  = ui_in[7:3];

    // etwas "runterskalierte" Koordinaten (8 Bit)
    wire [7:0] x = h_cnt[9:2];
    wire [7:0] y = v_cnt[9:2];

    reg  [7:0] pix;

    // Helfer: Multiplikationen als Shifts (kleiner in Sky130)
    wire [8:0] x3 = {x,1'b0} + x;                  // x*2 + x = x*3
    wire [9:0] y5 = {y,2'b00} + y;                 // y*4 + y = y*5

    always @* begin
        case (mode)
            3'd0: pix = {8{ (x[5] ^ y[5]) }} ^ {y[2:0], x[4:0]};     // Checker + XOR
            3'd1: pix = {x[7:4], y[7:4]};                            // Kacheln
            3'd2: pix = (x ^ {3'b000, y[7:3]}) + {y[6:0], 1'b0};     // Plasma-ähnlich
            3'd3: pix = ((x & y) ^ ( {1'b0,x3[7:0]} + {2'b00,y5[7:0]} )); // Moiré/Bitmix
            3'd4: pix = lfsr;                                        // LFSR-Noise
            3'd5: pix = {8{ (x[4]^x[3]^y[4]^y[3]) }} ^ {x[2:0],y[4:0]};// Diagonale Wellen
            default: pix = {x[7:5], y[7:5], x[4:3], y[2:1]};         // Fallback
        endcase
    end

    // Simple "Palette": XOR mit pal
    wire [7:0] p = pix ^ {3'b000, pal};

    // 6-Bit-Farbe (2 Bit je Kanal)
    wire [1:0] r = {p[7], p[4]};
    wire [1:0] g = {p[6], p[3]};
    wire [1:0] b = {p[5], p[2]};

    // Außerhalb des sichtbaren Bereichs → schwarz
    wire [1:0] r_vis = (active && vis) ? r : 2'b00;
    wire [1:0] g_vis = (active && vis) ? g : 2'b00;
    wire [1:0] b_vis = (active && vis) ? b : 2'b00;

    // Syncs: wenn inaktiv, auf High (nicht toggeln)
    wire hsync_n = active ? hsync_n_timing : 1'b1;
    wire vsync_n = active ? vsync_n_timing : 1'b1;

    // ---------------------------
    // Ausgänge nach TinyVGA-Pinout
    // ---------------------------
    assign uo_out[0] = r_vis[1]; // R1
    assign uo_out[1] = g_vis[1]; // G1
    assign uo_out[2] = b_vis[1]; // B1
    assign uo_out[3] = vsync_n;  // VSYNC (low-aktiv)
    assign uo_out[4] = r_vis[0]; // R0
    assign uo_out[5] = g_vis[0]; // G0
    assign uo_out[6] = b_vis[0]; // B0
    assign uo_out[7] = hsync_n;  // HSYNC (low-aktiv)

endmodule

`default_nettype wire
