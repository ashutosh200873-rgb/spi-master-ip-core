//=============================================================================
// Module      : spi_slave_control_select
// Project     : APB-Interfaced SPI Master IP Core
// Block       : 3 of 4 -- SPI Slave Select & Transfer Control
// Standard    : Strict Verilog-2001 (NO SystemVerilog constructs)
//
// Description :
//   This block acts as the "traffic controller" for the SPI Master.
//   It watches for a send_data trigger from Block 1 (APB Interface),
//   asserts the active-low Slave Select (ss), manages a 3-state FSM
//   to time the 8-bit transfer window using BaudRateDivisor, and then
//   fires a 1-cycle receive_data pulse to tell Block 1 to latch the
//   incoming byte from Block 4 (Shift Register).
//
// FSM States:
//   S_IDLE     (2'b00) : Idle. Waiting for send_data trigger.
//                        ss=1 (deasserted), tip=0.
//   S_TRANSFER (2'b01) : Transfer active. ss=0, tip=1.
//                        Counts 8 full SPI bit-periods in PCLK cycles.
//                        Each bit-period = BaudRateDivisor PCLK cycles.
//                        If STOP/WAIT(+spiswai) asserted mid-transfer:
//                        aborts immediately back to S_IDLE (no receive_data
//                        pulse -- data is invalid, discarded).
//   S_DONE     (2'b10) : 1-cycle completion state.
//                        ss=1, tip=0, receive_data=1 (one pulse to Block 1).
//                        Unconditional next-cycle return to S_IDLE.
//
// Mode Gating:
//   Same run_enable logic as Block 2 (must stay consistent):
//   RUN  (00)          : Normal operation.
//   WAIT (01)+spiswai=0: Transfer continues (SPISWAI not set).
//   WAIT (01)+spiswai=1: Transfer aborted immediately -> S_IDLE.
//   STOP (10/11)       : Transfer aborted immediately -> S_IDLE.
//=============================================================================

module spi_slave_control_select (
    input  wire        PCLK,
    input  wire        PRESETn,

    // From APB Slave Interface (Block 1)
    input  wire        mstr,           // 1 = SPI configured as Master
    input  wire        spiswai,        // SPI Stop-in-Wait Mode enable
    input  wire [1:0]  spi_mode,       // 00=RUN 01=WAIT 10=STOP 11=Reserved
    input  wire        send_data,      // 1-cycle pulse: new TX byte loaded into shift reg

    // From Baud Rate Generator (Block 2)
    input  wire [11:0] BaudRateDivisor,// PCLK cycles per one SPI bit period

    // Outputs
    output reg         ss,             // Active-low Slave Select to SPI slave device
    output reg         tip,            // Transfer In Progress flag (to Block 1 SPTEF logic)
    output reg         receive_data    // 1-cycle pulse: RX byte valid, latch into Block 1
);

    //-------------------------------------------------------------------
    // Mode Encoding (must match Block 1 and Block 2)
    //-------------------------------------------------------------------
    localparam MODE_RUN  = 2'b00;
    localparam MODE_WAIT = 2'b01;
    // 2'b10 and 2'b11 = STOP/Reserved, handled via default

    //-------------------------------------------------------------------
    // FSM State Encoding
    //-------------------------------------------------------------------
    localparam S_IDLE     = 2'b00;
    localparam S_TRANSFER = 2'b01;
    localparam S_DONE     = 2'b10;

    reg [1:0] state;
    reg [1:0] next_state;

    //-------------------------------------------------------------------
    // Internal Counters
    //-------------------------------------------------------------------
    reg [11:0] div_counter;   // Counts PCLK cycles within one SPI bit period
    reg [3:0]  bit_counter;   // Counts SPI bits (0 to 7, then transfer complete)

    //-------------------------------------------------------------------
    // Run Enable (same logic as Block 2, kept in sync)
    //-------------------------------------------------------------------
    wire run_enable;
    assign run_enable = (spi_mode == MODE_RUN) |
                        ((spi_mode == MODE_WAIT) & (~spiswai));

    //-------------------------------------------------------------------
    // End-of-bit-period detection
    //-------------------------------------------------------------------
    wire bit_period_done;
    assign bit_period_done = (div_counter == (BaudRateDivisor - 12'd1));

    //-------------------------------------------------------------------
    // FSM -- Sequential State Register
    //-------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    //-------------------------------------------------------------------
    // FSM -- Next-State Logic (Combinational)
    //-------------------------------------------------------------------
    always @(*) begin
        case (state)
            S_IDLE : begin
                // Only start if: master mode + run_enable + send_data triggered
                if (mstr && run_enable && send_data)
                    next_state = S_TRANSFER;
                else
                    next_state = S_IDLE;
            end

            S_TRANSFER : begin
                // Abort path: STOP or WAIT+spiswai asserted mid-transfer
                if (!run_enable) begin
                    next_state = S_IDLE;
                end
                // Normal completion: 8 full bit-periods have elapsed
                else if (bit_period_done && (bit_counter == 4'd7)) begin
                    next_state = S_DONE;
                end
                else begin
                    next_state = S_TRANSFER;
                end
            end

            S_DONE : begin
                // 1-cycle pulse state, always return to IDLE
                next_state = S_IDLE;
            end

            default : next_state = S_IDLE; // Defensive catch-all
        endcase
    end

    //-------------------------------------------------------------------
    // FSM -- Output Logic + Counter Control (Sequential)
    //-------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ss           <= 1'b1;   // Deasserted (slave not selected)
            tip          <= 1'b0;
            receive_data <= 1'b0;
            div_counter  <= 12'd0;
            bit_counter  <= 4'd0;
        end
        else begin
            // Default: deassert single-cycle signals
            receive_data <= 1'b0;

            case (state)
                S_IDLE : begin
                    ss          <= 1'b1;
                    tip         <= 1'b0;
                    div_counter <= 12'd0;
                    bit_counter <= 4'd0;

                    // Pre-assert ss one cycle before first SCLK edge for
                    // setup time (ss valid before transfer begins)
                    if (mstr && run_enable && send_data) begin
                        ss  <= 1'b0;
                        tip <= 1'b1;
                    end
                end

                S_TRANSFER : begin
                    ss  <= 1'b0;
                    tip <= 1'b1;

                    if (!run_enable) begin
                        // Abort: deassert ss and clear counters immediately
                        ss          <= 1'b1;
                        tip         <= 1'b0;
                        div_counter <= 12'd0;
                        bit_counter <= 4'd0;
                    end
                    else begin
                        // Count PCLK cycles within the current bit-period
                        if (bit_period_done) begin
                            div_counter <= 12'd0;
                            if (bit_counter == 4'd7)
                                bit_counter <= 4'd0;   // Reset for next transfer
                            else
                                bit_counter <= bit_counter + 4'd1;
                        end
                        else begin
                            div_counter <= div_counter + 12'd1;
                        end
                    end
                end

                S_DONE : begin
                    ss           <= 1'b1;   // Deassert slave select
                    tip          <= 1'b0;
                    receive_data <= 1'b1;   // 1-cycle pulse to Block 1
                    div_counter  <= 12'd0;
                    bit_counter  <= 4'd0;
                end

                default : begin
                    ss           <= 1'b1;
                    tip          <= 1'b0;
                    receive_data <= 1'b0;
                    div_counter  <= 12'd0;
                    bit_counter  <= 4'd0;
                end
            endcase
        end
    end

endmodule
