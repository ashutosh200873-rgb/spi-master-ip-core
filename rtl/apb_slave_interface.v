//=============================================================================
// Module      : apb_slave_interface
// Project     : APB-Interfaced SPI Master IP Core
// Block       : 1 of 4 -- APB Slave Interface & Register File
// Standard    : Strict Verilog-2001 (NO SystemVerilog constructs)
// Description : Implements the AMBA APB slave protocol and the Motorola
//               SPI V03.06-style register map (SPICR1, SPICR2, SPIBR,
//               SPISR, SPIDR). Also implements the custom Run/Wait/Stop
//               power-mode control field (project-specific extension,
//               not part of the original Motorola spec -- packed into
//               reserved bits[7:6] of SPICR2).
//
// Address Map (PADDR[2:0], byte-addressed registers):
//   3'b000  : SPICR1  (R/W) - SPI Control Register 1
//   3'b001  : SPICR2  (R/W) - SPI Control Register 2 (+ custom MODE field)
//   3'b010  : SPIBR   (R/W) - SPI Baud Rate Register
//   3'b011  : SPISR   (R)   - SPI Status Register (writes ignored)
//   3'b100  : SPIDR   (R/W) - SPI Data Register (TX on write, RX on read)
//   3'b101-111 : RESERVED -- access asserts PSLVERR
//
// SPICR1[7:0] = { SPIE, SPE, SPTIE, MSTR, CPOL, CPHA, SSOE, LSBFE }
// SPICR2[7:0] = { MODE[1:0], 1'b0, MODFEN, BIDIROE, 1'b0, SPISWAI, SPC0 }
//               MODE: 00=RUN  01=WAIT  10=STOP  11=Reserved(treated as STOP)
// SPIBR [7:0] = { 1'b0, SPPR[2:0], 1'b0, SPR[2:0] }
// SPISR [7:0] = { SPIF, 1'b0, SPTEF, MODF, 4'b0000 }
//=============================================================================

module apb_slave_interface (
    // System
    input  wire        PCLK,
    input  wire        PRESETn,

    // APB Bus
    input  wire [2:0]  PADDR,
    input  wire        PWRITE,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire [7:0]  PWDATA,
    output reg  [7:0]  PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // From SPI Slave Control Select (Block 3)
    input  wire        ss,             // Active-low slave select (mode-fault check)
    input  wire        tip,            // Transfer In Progress

    // From Shift Register (Block 4)
    input  wire [7:0]  miso_data,      // Received byte from shifter
    input  wire        receive_data,   // Pulse: new RX byte valid on miso_data

    // To Shift Register (Block 4) / SPI Slave Control Select (Block 3)
    output wire         send_data,      // Pulse: new TX byte valid on mosi_data
    output wire [7:0]   mosi_data,      // Byte to be shifted out

    // To Baud Rate Generator (Block 2) / Control Select (Block 3)
    output wire         mstr,
    output wire         cpol,
    output wire         cpha,
    output wire         lsbfe,
    output wire         spiswai,
    output wire [2:0]   sppr,
    output wire [2:0]   spr,
    output wire [1:0]   spi_mode,       // 00=RUN 01=WAIT 10=STOP

    // Interrupt
    output wire         spi_interrupt_request
);

    //-------------------------------------------------------------------
    // Local Address Parameters
    //-------------------------------------------------------------------
    localparam ADDR_SPICR1 = 3'b000;
    localparam ADDR_SPICR2 = 3'b001;
    localparam ADDR_SPIBR  = 3'b010;
    localparam ADDR_SPISR  = 3'b011;
    localparam ADDR_SPIDR  = 3'b100;

    //-------------------------------------------------------------------
    // Internal Registers
    //-------------------------------------------------------------------
    reg [7:0] spicr1_reg;
    reg [7:0] spicr2_reg;
    reg [7:0] spibr_reg;
    reg [7:0] tx_data_reg;
    reg [7:0] rx_data_reg;

    reg spif_flag;             // SPI Transfer complete interrupt flag
    reg sptef_flag;            // SPI Transmit buffer empty flag
    reg modf_flag;             // Mode fault flag

    reg send_data_reg;         // 1-cycle pulse register
    reg tip_d;                 // delayed 'tip' for falling-edge detect
    reg spisr_read_pending;    // tracks classic 2-step SPIF clear sequence

    //-------------------------------------------------------------------
    // Combinational helpers
    //-------------------------------------------------------------------
    wire addr_valid;
    wire apb_write_access;
    wire apb_read_access;

    assign addr_valid       = (PADDR <= ADDR_SPIDR);
    assign apb_write_access = PSEL & PENABLE & PWRITE;
    assign apb_read_access  = PSEL & PENABLE & (~PWRITE);

    // Zero-wait-state slave: always ready in the same access cycle
    assign PREADY  = 1'b1;
    // Protocol error flagged for any access (read or write) to reserved space
    assign PSLVERR = PSEL & PENABLE & (~addr_valid);

    //-------------------------------------------------------------------
    // Register File + Mode Control + Flag Management (Sequential)
    //-------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            spicr1_reg          <= 8'h00;
            spicr2_reg          <= 8'b10_0_0_0_0_0_0; // MODE=STOP on reset (safe power-up)
            spibr_reg           <= 8'h00;
            tx_data_reg         <= 8'h00;
            rx_data_reg         <= 8'h00;
            spif_flag           <= 1'b0;
            sptef_flag          <= 1'b1;              // buffer empty, ready for 1st write
            modf_flag           <= 1'b0;
            send_data_reg       <= 1'b0;
            tip_d               <= 1'b0;
            spisr_read_pending  <= 1'b0;
        end
        else begin
            // Default: send_data is a single-cycle pulse, deassert unless re-asserted below
            send_data_reg <= 1'b0;

            // ---- SPTEF refill: buffer becomes free again once an in-flight
            //      transfer (tip) finishes (falling-edge detect) ----
            tip_d <= tip;
            if (tip_d && !tip) begin
                sptef_flag <= 1'b1;
            end

            // ---- Mode Fault detection (standard Motorola behavior):
            //      if we are MSTR and MODFEN=1, an externally-asserted SS
            //      (active-low conflict) forces a mode fault and demotes
            //      us to slave mode automatically ----
            if (spicr1_reg[4] && spicr2_reg[4] && !ss) begin
                modf_flag     <= 1'b1;
                spicr1_reg[4] <= 1'b0; // auto clear MSTR on fault
            end

            // ---- RX path: latch incoming byte from shifter ----
            if (receive_data) begin
                rx_data_reg <= miso_data;
                spif_flag   <= 1'b1;
            end

            // ---- APB Write Access ----
            if (apb_write_access) begin
                case (PADDR)
                    ADDR_SPICR1: spicr1_reg <= PWDATA;
                    ADDR_SPICR2: spicr2_reg <= PWDATA;
                    ADDR_SPIBR : spibr_reg  <= PWDATA;
                    ADDR_SPISR : ; // status reg is read-only, write = no-op
                    ADDR_SPIDR : begin
                        if (!tip) begin // software must respect SPTEF / !tip, like real silicon
                            tx_data_reg   <= PWDATA;
                            sptef_flag    <= 1'b0;
                            send_data_reg <= 1'b1;
                        end
                    end
                    default    : ; // reserved address, no register effect (PSLVERR already flags it)
                endcase
            end

            // ---- APB Read Access: classic 2-step SPIF clear sequence
            //      (read SPISR while SPIF=1, then access SPIDR) ----
            if (apb_read_access) begin
                if (PADDR == ADDR_SPISR && spif_flag) begin
                    spisr_read_pending <= 1'b1;
                end
                else if (PADDR == ADDR_SPIDR && spisr_read_pending) begin
                    spif_flag          <= 1'b0;
                    spisr_read_pending <= 1'b0;
                end
            end
        end
    end

    //-------------------------------------------------------------------
    // PRDATA Mux (Combinational read path)
    //-------------------------------------------------------------------
    always @(*) begin
        case (PADDR)
            ADDR_SPICR1: PRDATA = spicr1_reg;
            ADDR_SPICR2: PRDATA = spicr2_reg;
            ADDR_SPIBR : PRDATA = spibr_reg;
            ADDR_SPISR : PRDATA = {spif_flag, 1'b0, sptef_flag, modf_flag, 4'b0000};
            ADDR_SPIDR : PRDATA = rx_data_reg;
            default    : PRDATA = 8'h00;
        endcase
    end

    //-------------------------------------------------------------------
    // Output Assignments (field extraction from registers)
    //-------------------------------------------------------------------
    assign mstr     = spicr1_reg[4];
    assign cpol     = spicr1_reg[3];
    assign cpha     = spicr1_reg[2];
    assign lsbfe    = spicr1_reg[0];

    assign spiswai  = spicr2_reg[1];
    assign spi_mode = spicr2_reg[7:6];

    assign sppr     = spibr_reg[6:4];
    assign spr      = spibr_reg[2:0];

    assign mosi_data = tx_data_reg;
    assign send_data = send_data_reg;

    assign spi_interrupt_request = (spicr1_reg[7] & spif_flag)  |  // SPIE & SPIF
                                    (spicr1_reg[5] & sptef_flag) |  // SPTIE & SPTEF
                                    (spicr2_reg[4] & modf_flag);    // MODFEN & MODF

endmodule
