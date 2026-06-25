//=============================================================================
// Module      : spi_master_top
// Project     : APB-Interfaced SPI Master IP Core
// Block       : Top-Level Integration (Phase 4)
// Standard    : Strict Verilog-2001 (NO SystemVerilog constructs)
//
// Description :
//   Structural top-level that wires all four sub-blocks together.
//   Contains NO logic of its own -- all RTL lives in the sub-blocks.
//   Named port connections used throughout (positional mapping avoided
//   to prevent silent pin-swap bugs during maintenance).
//
// Block Hierarchy:
//   spi_master_top
//     ├── u_apb_slave   : apb_slave_interface  (Block 1)
//     ├── u_baud_gen    : Baud_rate_generator  (Block 2)
//     ├── u_ctrl_sel    : spi_slave_control_select (Block 3)
//     └── u_shift_reg   : shift_reg            (Block 4)
//
// External Port Map (APB + SPI pins only -- everything else internal):
//
//   APB Master side                SPI Slave side
//   ─────────────────              ──────────────
//   PCLK    → all blocks           SCLK  ← Block 2
//   PRESETn → all blocks           MOSI  ← Block 4
//   PADDR   → Block 1              MISO  → Block 4
//   PSEL    → Block 1              SS_N  ← Block 3
//   PENABLE → Block 1
//   PWRITE  → Block 1
//   PWDATA  → Block 1
//   PRDATA  ← Block 1
//   PREADY  ← Block 1
//   PSLVERR ← Block 1
//   IRQ     ← Block 1
//
// Internal Interconnect Summary:
//   Block1 → Block2 : cpol, cpha, spiswai, sppr, spr, spi_mode
//   Block1 → Block3 : mstr, spiswai, spi_mode, send_data
//   Block1 → Block4 : send_data, mosi_data, lsbfe, cpha, cpol
//   Block2 → Block3 : BaudRateDivisor
//   Block2 → Block4 : flag_low, flag_high, flags_low, flags_high
//   Block3 → Block1 : ss, tip, receive_data
//   Block3 → Block2 : ss
//   Block3 → Block4 : ss, receive_data
//   Block4 → Block1 : data_miso (as miso_data)
//=============================================================================

module spi_master_top (
    // ----------------------------------------------------------------
    // System
    // ----------------------------------------------------------------
    input  wire        PCLK,
    input  wire        PRESETn,

    // ----------------------------------------------------------------
    // APB Slave Interface (connect to APB bus / SoC interconnect)
    // ----------------------------------------------------------------
    input  wire [2:0]  PADDR,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PWDATA,
    output wire [7:0]  PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // ----------------------------------------------------------------
    // Interrupt
    // ----------------------------------------------------------------
    output wire        spi_interrupt_request,

    // ----------------------------------------------------------------
    // SPI Physical Interface (connect to external slave device)
    // ----------------------------------------------------------------
    output wire        SCLK,       // SPI serial clock to slave
    output wire        MOSI,       // Master Out Slave In
    input  wire        MISO,       // Master In  Slave Out
    output wire        SS_N        // Slave Select, active-low
);

    // ================================================================
    // Internal Interconnect Wires
    // ================================================================

    // Block 1 → Block 2/3/4 : Configuration
    wire        w_mstr;
    wire        w_cpol;
    wire        w_cpha;
    wire        w_lsbfe;
    wire        w_spiswai;
    wire [2:0]  w_sppr;
    wire [2:0]  w_spr;
    wire [1:0]  w_spi_mode;

    // Block 1 → Block 3/4 : TX trigger + data
    wire        w_send_data;
    wire [7:0]  w_mosi_data;

    // Block 2 → Block 3 : Timing
    wire [11:0] w_BaudRateDivisor;

    // Block 2 → Block 4 : Phase flags
    wire        w_flag_low;
    wire        w_flag_high;
    wire        w_flags_low;
    wire        w_flags_high;

    // Block 3 → Block 1/2/4 : Control
    wire        w_ss;
    wire        w_tip;
    wire        w_receive_data;

    // Block 4 → Block 1 : Received data
    wire [7:0]  w_data_miso;

    // ================================================================
    // Block 1 : APB Slave Interface & Register File
    // ================================================================
    apb_slave_interface u_apb_slave (
        // System
        .PCLK                 (PCLK),
        .PRESETn              (PRESETn),
        // APB
        .PADDR                (PADDR),
        .PWRITE               (PWRITE),
        .PSEL                 (PSEL),
        .PENABLE              (PENABLE),
        .PWDATA               (PWDATA),
        .PRDATA               (PRDATA),
        .PREADY               (PREADY),
        .PSLVERR              (PSLVERR),
        // From Block 3
        .ss                   (w_ss),
        .tip                  (w_tip),
        .receive_data         (w_receive_data),
        // From Block 4
        .miso_data            (w_data_miso),
        // To Block 3/4
        .send_data            (w_send_data),
        .mosi_data            (w_mosi_data),
        // Config outputs to Block 2/3/4
        .mstr                 (w_mstr),
        .cpol                 (w_cpol),
        .cpha                 (w_cpha),
        .lsbfe                (w_lsbfe),
        .spiswai              (w_spiswai),
        .sppr                 (w_sppr),
        .spr                  (w_spr),
        .spi_mode             (w_spi_mode),
        // Interrupt
        .spi_interrupt_request(spi_interrupt_request)
    );

    // ================================================================
    // Block 2 : Baud Rate Generator
    // ================================================================
    Baud_rate_generator u_baud_gen (
        // System
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        // Config from Block 1
        .spi_mode       (w_spi_mode),
        .spiswai        (w_spiswai),
        .sppr           (w_sppr),
        .spr            (w_spr),
        .cpol           (w_cpol),
        .cpha           (w_cpha),
        // From Block 3
        .ss             (w_ss),
        // Outputs
        .sclk           (SCLK),
        .flag_low       (w_flag_low),
        .flag_high      (w_flag_high),
        .flags_low      (w_flags_low),
        .flags_high     (w_flags_high),
        .BaudRateDivisor(w_BaudRateDivisor)
    );

    // ================================================================
    // Block 3 : SPI Slave Select & Transfer Control
    // ================================================================
    spi_slave_control_select u_ctrl_sel (
        // System
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        // Config from Block 1
        .mstr           (w_mstr),
        .spiswai        (w_spiswai),
        .spi_mode       (w_spi_mode),
        // TX trigger from Block 1
        .send_data      (w_send_data),
        // Timing from Block 2
        .BaudRateDivisor(w_BaudRateDivisor),
        // Outputs to Block 1/2/4
        .ss             (w_ss),
        .tip            (w_tip),
        .receive_data   (w_receive_data)
    );

    // ================================================================
    // Block 4 : SPI Shift Register (TX/RX Engine)
    // ================================================================
    shift_reg u_shift_reg (
        // System
        .PCLK         (PCLK),
        .PRESETn      (PRESETn),
        // Control from Block 3
        .ss           (w_ss),
        .receive_data (w_receive_data),
        // TX data from Block 1
        .send_data    (w_send_data),
        .data_mosi    (w_mosi_data),
        // RX data to Block 1
        .data_miso    (w_data_miso),
        // Config from Block 1
        .lsbfe        (w_lsbfe),
        .cpha         (w_cpha),
        .cpol         (w_cpol),
        // Phase flags from Block 2
        .flag_low     (w_flag_low),
        .flag_high    (w_flag_high),
        .flags_low    (w_flags_low),
        .flags_high   (w_flags_high),
        // Physical SPI pins
        .miso         (MISO),
        .mosi         (MOSI)
    );

    // SS_N is driven directly from Block 3's ss output
    assign SS_N = w_ss;

endmodule
