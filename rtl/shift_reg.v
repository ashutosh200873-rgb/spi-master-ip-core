//=============================================================================
// Module      : shift_reg
// Project     : APB-Interfaced SPI Master IP Core
// Block       : 4 of 4 -- SPI Shift Register (TX/RX Engine)
// Standard    : Strict Verilog-2001 (NO SystemVerilog constructs)
// Revision    : R2 -- data_miso changed from registered to combinational wire.
//               Root cause of fix: Both Block1 and Block4 were sampling on
//               the same posedge PCLK when receive_data fired, causing Block1
//               to latch the OLD (pre-update) value of data_miso. Making
//               data_miso = rx_shift (combinational) means Block1 always
//               reads the fully-assembled current byte on receive_data.
//=============================================================================

module shift_reg (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        ss,
    input  wire        receive_data,
    input  wire        send_data,
    input  wire [7:0]  data_mosi,
    output wire [7:0]  data_miso,    // R2: wire, not reg; combinational from rx_shift
    input  wire        lsbfe,
    input  wire        cpha,
    input  wire        cpol,
    input  wire        flag_low,
    input  wire        flag_high,
    input  wire        flags_low,
    input  wire        flags_high,
    input  wire        miso,
    output reg         mosi
);

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;

    // data_miso is now purely combinational -- Block1 reads rx_shift directly
    // on the same clock edge receive_data fires, getting the correct final byte.
    assign data_miso = rx_shift;

    wire drive_mosi;
    wire sample_miso;
    assign drive_mosi  = flags_low | flags_high;
    assign sample_miso = flag_low  | flag_high;

    // TX Shift Register + MOSI Driver
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_shift <= 8'h00;
            mosi     <= 1'b0;
        end
        else begin
            if (send_data) begin
                if (!cpha) begin
                    // CPHA=0: pre-drive first bit, pre-shift register
                    if (!lsbfe) begin
                        mosi     <= data_mosi[7];
                        tx_shift <= {data_mosi[6:0], 1'b0};
                    end else begin
                        mosi     <= data_mosi[0];
                        tx_shift <= {1'b0, data_mosi[7:1]};
                    end
                end else begin
                    // CPHA=1: no pre-drive, load as-is
                    tx_shift <= data_mosi;
                end
            end
            else if (drive_mosi) begin
                if (!lsbfe) begin
                    mosi     <= tx_shift[7];
                    tx_shift <= {tx_shift[6:0], 1'b0};
                end else begin
                    mosi     <= tx_shift[0];
                    tx_shift <= {1'b0, tx_shift[7:1]};
                end
            end
            else if (ss) begin
                mosi <= 1'b0;
            end
        end
    end

    // RX Shift Register
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_shift <= 8'h00;
        end
        else begin
            if (sample_miso) begin
                if (!lsbfe)
                    rx_shift <= {rx_shift[6:0], miso};
                else
                    rx_shift <= {miso, rx_shift[7:1]};
            end
        end
    end

    // synthesis translate_off
    wire unused_cpol     = cpol;
    wire unused_rcv_data = receive_data;
    // synthesis translate_on

endmodule
