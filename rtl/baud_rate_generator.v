//=============================================================================
// Module      : Baud_rate_generator
// Project     : APB-Interfaced SPI Master IP Core
// Block       : 2 of 4 -- SPI Clock / Baud Rate Generator
// Standard    : Strict Verilog-2001 (NO SystemVerilog constructs)
//
// Description :
//   Generates the SPI serial clock (sclk) from PCLK using the standard
//   Motorola V03.06 divisor formula:
//
//        BaudRateDivisor = (SPPR + 1) * 2^(SPR + 1)
//
//   sclk toggles every (BaudRateDivisor / 2) PCLK cycles, giving a clean
//   50%-duty-cycle output. Divisor is always even (2^(SPR+1) >= 2), so
//   the half-period division is always exact -- no rounding error.
//
//   Power-mode gating (HARD GATE, per project decision):
//     - spi_mode == RUN              : sclk free-runs normally.
//     - spi_mode == WAIT, spiswai=0  : sclk keeps running (legacy SPISWAI
//                                       bit says "don't stop in wait").
//     - spi_mode == WAIT, spiswai=1  : sclk gated off immediately.
//     - spi_mode == STOP / Reserved  : sclk always gated off immediately.
//   When gated (or when ss is deasserted / not selected), sclk is forced
//   to its protocol-correct IDLE level (= cpol), NOT just to 0 -- this
//   matters for CPOL=1 modes where idle clock must sit HIGH.
//
//   Phase Flags (consumed by Block 4 -- Shift Register), derived from the
//   standard SPI leading/trailing edge rule:
//     CPOL == CPHA  -> data SAMPLED on RISING edge, DRIVEN on FALLING edge.
//     CPOL != CPHA  -> data SAMPLED on FALLING edge, DRIVEN on RISING edge.
//
//     flag_low   : 1-cycle pulse on RISING  edge, valid when CPOL==CPHA -> sample MISO
//     flag_high  : 1-cycle pulse on FALLING edge, valid when CPOL!=CPHA -> sample MISO
//     flags_low  : 1-cycle pulse on FALLING edge, valid when CPOL==CPHA -> drive MOSI
//     flags_high : 1-cycle pulse on RISING  edge, valid when CPOL!=CPHA -> drive MOSI
//
//   Edge detection is done by comparing the registered sclk output against
//   a 1-cycle-delayed copy (sclk_d) -- this keeps the flag pulse perfectly
//   aligned to the same PCLK cycle in which sclk actually transitions
//   (no extra pipeline-stage misalignment).
//=============================================================================

module Baud_rate_generator (
    input  wire        PCLK,
    input  wire        PRESETn,

    // From APB Slave Interface (Block 1)
    input  wire [1:0]  spi_mode,    // 00=RUN 01=WAIT 10=STOP 11=Reserved
    input  wire        spiswai,
    input  wire [2:0]  sppr,
    input  wire [2:0]  spr,
    input  wire        cpol,
    input  wire        cpha,

    // From SPI Slave Control Select (Block 3)
    input  wire        ss,          // Active-low slave select

    // Outputs
    output reg          sclk,
    output wire         flag_low,
    output wire         flag_high,
    output wire         flags_low,
    output wire         flags_high,
    output wire [11:0]  BaudRateDivisor
);

    //-------------------------------------------------------------------
    // Mode encoding (must match apb_slave_interface.v)
    //-------------------------------------------------------------------
    localparam MODE_RUN  = 2'b00;
    localparam MODE_WAIT = 2'b01;
    // MODE_STOP (2'b10) and Reserved (2'b11) both fall into the default
    // "disabled" case below -- handled via the case() default branch.

    //-------------------------------------------------------------------
    // Divisor Calculation (combinational, Motorola V03.06 formula)
    //-------------------------------------------------------------------
    // (SPPR+1) max = 8, 2^(SPR+1) max = 256  -> max divisor = 2048 (fits in 12 bits)
    wire [3:0] prescale_val; // 1 to 8
    wire [8:0] rate_val;     // 2 to 256

    assign prescale_val    = sppr + 4'd1;
    assign rate_val        = (9'd1 << (spr + 3'd1));
    assign BaudRateDivisor = prescale_val * rate_val;

    wire [11:0] half_divisor;
    wire [11:0] half_divisor_m1;
    assign half_divisor    = BaudRateDivisor >> 1;        // always exact (divisor always even)
    assign half_divisor_m1 = half_divisor - 12'd1;

    //-------------------------------------------------------------------
    // Clock Enable (Mode + SPISWAI + Slave Select gating decision)
    //-------------------------------------------------------------------
    reg clk_enable;
    always @(*) begin
        case (spi_mode)
            MODE_RUN  : clk_enable = 1'b1;
            MODE_WAIT : clk_enable = ~spiswai;
            default   : clk_enable = 1'b0; // MODE_STOP and Reserved(11)
        endcase
    end

    wire enable_overall;
    assign enable_overall = clk_enable & (~ss); // only toggle while actively selected

    //-------------------------------------------------------------------
    // sclk Generation (registered, hard-gated to idle level = cpol)
    //-------------------------------------------------------------------
    reg [11:0] div_counter;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            sclk        <= 1'b0;
            div_counter <= 12'd0;
        end
        else begin
            if (!enable_overall) begin
                // Hard gate: force to protocol idle level immediately,
                // and re-sync the divider so the next transfer starts clean.
                sclk        <= cpol;
                div_counter <= 12'd0;
            end
            else if (div_counter == half_divisor_m1) begin
                sclk        <= ~sclk;
                div_counter <= 12'd0;
            end
            else begin
                div_counter <= div_counter + 12'd1;
            end
        end
    end

    //-------------------------------------------------------------------
    // Edge Detection on the actual sclk output (1-cycle delayed compare)
    //-------------------------------------------------------------------
    reg sclk_d;
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            sclk_d <= 1'b0;
        else
            sclk_d <= sclk;
    end

    wire rising_edge_sclk;
    wire falling_edge_sclk;
    assign rising_edge_sclk  = sclk  & (~sclk_d);
    assign falling_edge_sclk = (~sclk) & sclk_d;

    //-------------------------------------------------------------------
    // CPOL/CPHA Phase Flags (combinational from registered, glitch-free signals)
    //-------------------------------------------------------------------
    wire cpol_cpha_match; // 1 when CPOL == CPHA (both high or both low)
    assign cpol_cpha_match = (cpol == cpha);

    // Also gated by enable_overall: prevents spurious pulses from being
    // detected on the idle-level transition that happens when sclk is
    // forced back to cpol right as gating kicks in/out (e.g. cpol changes
    // while deselected) -- flags must only ever fire during a real,
    // actively-selected transfer.
    assign flag_low   = rising_edge_sclk  &  cpol_cpha_match  & enable_overall;
    assign flag_high  = falling_edge_sclk & (~cpol_cpha_match) & enable_overall;
    assign flags_low  = falling_edge_sclk &  cpol_cpha_match  & enable_overall;
    assign flags_high = rising_edge_sclk  & (~cpol_cpha_match) & enable_overall;

endmodule
