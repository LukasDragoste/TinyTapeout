`default_nettype none

module vga_generator (
    input wire clk,
    input wire rst,
    input wire [7:0] ui_in,
    output wire [7:0] uo_out
);

    // --- Linter Fix: Mark unused inputs ---
    // This wire is not used in the design, but it "reads" the unused
    // input bits, which prevents the linter from complaining.
    wire _unused = &{1'b0, ui_in[7:1]};

    // --- VGA Timing Parameters for 160x120 @ 60Hz ---
    // Pixel Clock: ~6.4 MHz. We will use the TT `clk` (10MHz) and a divider.
    // Horizontal Timings (in pixel clocks)
    parameter H_DISPLAY = 160;
    parameter H_FRONT   = 16;
    parameter H_SYNC    = 40;
    parameter H_BACK    = 48;
    parameter H_TOTAL   = H_DISPLAY + H_FRONT + H_SYNC + H_BACK; // 264

    // Vertical Timings (in lines)
    parameter V_DISPLAY = 120;
    parameter V_FRONT   = 1;
    parameter V_SYNC    = 3;
    parameter V_BACK    = 9;
    parameter V_TOTAL   = V_DISPLAY + V_FRONT + V_SYNC + V_BACK; // 133

    // --- Clock Divider (approx. 10MHz -> 5MHz) ---
    reg tick;
    always @(posedge clk or posedge rst) begin
        if (rst) tick <= 1'b0;
        else     tick <= ~tick;
    end

    // --- Counters ---
    reg [8:0] h_count; // Max value is 263
    reg [7:0] v_count; // Max value is 132

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            h_count <= 0;
            v_count <= 0;
        end else if (tick) begin // Update counters on our divided clock
            if (h_count == H_TOTAL - 1) begin
                h_count <= 0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 0;
                end else begin
                    v_count <= v_count + 1;
                end
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    // --- Sync Signal Generation ---
    wire hsync = (h_count >= H_DISPLAY + H_FRONT) && (h_count < H_DISPLAY + H_FRONT + H_SYNC);
    wire vsync = (v_count >= V_DISPLAY + V_FRONT) && (v_count < V_DISPLAY + V_FRONT + V_SYNC);

    // --- Video On (Active Display Area) ---
    wire video_on = (h_count < H_DISPLAY) && (v_count < V_DISPLAY);

    // --- Pattern Logic ---
    reg [1:0] r, g, b;
    always @(*) begin
        // Default to black
        r = 2'b00;
        g = 2'b00;
        b = 2'b00;

        if (video_on) begin
            // Use the first input pin to select the pattern
            case (ui_in[0])
                // --- Pattern 0: Vertical Color Bars ---
                1'b0: begin
                    if (h_count < 20)      begin r=2'b11; g=2'b11; b=2'b11; end // White
                    else if (h_count < 40) begin r=2'b11; g=2'b11; b=2'b00; end // Yellow
                    else if (h_count < 60) begin r=2'b00; g=2'b11; b=2'b11; end // Cyan
                    else if (h_count < 80) begin r=2'b00; g=2'b11; b=2'b00; end // Green
                    else if (h_count < 100)begin r=2'b11; g=2'b00; b=2'b11; end // Magenta
                    else if (h_count < 120)begin r=2'b11; g=2'b00; b=2'b00; end // Red
                    else if (h_count < 140)begin r=2'b00; g=2'b00; b=2'b11; end // Blue
                    else                   begin r=2'b01; g=2'b01; b=2'b01; end // Grey
                end

                // --- Pattern 1: 8x8 Checkerboard ---
                1'b1: begin
                    if (h_count[3] ^ v_count[3]) begin
                        // A non-grey color for the checks
                        r = 2'b10;
                        g = 2'b00;
                        b = 2'b11;
                    end else begin
                        r = 2'b00;
                        g = 2'b01;
                        b = 2'b00;
                    end
                end
            endcase
        end
    end
    
    // --- Assign to Output Pins ---
    // This order matches our plan from before.
    assign uo_out[0] = hsync;
    assign uo_out[1] = vsync;
    assign uo_out[2] = r[0];
    assign uo_out[3] = r[1];
    assign uo_out[4] = g[0];
    assign uo_out[5] = g[1];
    assign uo_out[6] = b[0];
    assign uo_out[7] = b[1];

endmodule
