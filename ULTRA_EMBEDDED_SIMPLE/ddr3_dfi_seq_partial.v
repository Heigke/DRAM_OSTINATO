module ddr3_dfi_seq
#(
     parameter DDR_MHZ           = 100
    ,parameter DDR_WRITE_LATENCY = 4
    ,parameter DDR_READ_LATENCY  = 4
)
(
     input           clk_i
    ,input           rst_i

    // Command Interface
    ,input  [14:0]   address_i
    ,input  [2:0]    bank_i
    ,input  [3:0]    command_i
    ,input           cke_i
    ,output          accept_o

    // Write Interface
    ,input  [127:0]  wrdata_i
    ,input  [15:0]   wrdata_mask_i
    
    // Partial write control
    ,input           partial_wr_i
    ,input  [15:0]   wr_duration_i

    // Read Interface
    ,output          rddata_valid_o
    ,output [127:0]  rddata_o

    // DFI Interface
    ,output [14:0]   dfi_address_o
    ,output [2:0]    dfi_bank_o
    ,output          dfi_cas_n_o
    ,output          dfi_cke_o
    ,output          dfi_cs_n_o
    ,output          dfi_odt_o
    ,output          dfi_ras_n_o
    ,output          dfi_reset_n_o
    ,output          dfi_we_n_o
    ,output [31:0]   dfi_wrdata_o
    ,output          dfi_wrdata_en_o
    ,output [3:0]    dfi_wrdata_mask_o
    ,output          dfi_rddata_en_o
    ,input  [31:0]   dfi_rddata_i
    ,input           dfi_rddata_valid_i
    ,input  [1:0]    dfi_rddata_dnv_i
);

// Command definitions
localparam CMD_NOP      = 4'b0111;
localparam CMD_ACTIVE   = 4'b0011;
localparam CMD_READ     = 4'b0101;
localparam CMD_WRITE    = 4'b0100;
localparam CMD_PRECHARGE= 4'b0010;
localparam CMD_REFRESH  = 4'b0001;
localparam CMD_LOAD_MODE= 4'b0000;
localparam CMD_ZQCL     = 4'b0110;

// State machine for write data control
reg [15:0] wr_timer_q;
reg        wr_active_q;
reg        partial_mode_q;
reg [15:0] wr_duration_q;

// Capture partial write parameters when write command is issued
always @(posedge clk_i) begin
    if (rst_i) begin
        partial_mode_q <= 1'b0;
        wr_duration_q  <= 16'b0;
    end else if (command_i == CMD_WRITE && accept_o) begin
        partial_mode_q <= partial_wr_i;
        wr_duration_q  <= wr_duration_i;
    end
end

// Write data enable control with partial write support
always @(posedge clk_i) begin
    if (rst_i) begin
        wr_timer_q  <= 16'b0;
        wr_active_q <= 1'b0;
    end else if (command_i == CMD_WRITE && accept_o) begin
        wr_active_q <= 1'b1;
        wr_timer_q  <= 16'b0;
    end else if (wr_active_q) begin
        if (partial_mode_q) begin
            // Partial write mode: stop after duration
            if (wr_timer_q >= wr_duration_q) begin
                wr_active_q <= 1'b0;
            end else begin
                wr_timer_q <= wr_timer_q + 1'b1;
            end
        end else begin
            // Normal write mode: standard burst length
            if (wr_timer_q >= (DDR_WRITE_LATENCY + 7)) begin
                wr_active_q <= 1'b0;
            end else begin
                wr_timer_q <= wr_timer_q + 1'b1;
            end
        end
    end
end

// [Rest of the ddr3_dfi_seq implementation - command pipeline, etc.]
// This is a simplified version - you'll need to integrate with existing logic

// Write data enable output
assign dfi_wrdata_en_o = wr_active_q && (wr_timer_q >= DDR_WRITE_LATENCY) && 
                         (wr_timer_q < (partial_mode_q ? (DDR_WRITE_LATENCY + wr_duration_q) : 
                                                         (DDR_WRITE_LATENCY + 8)));

// [Rest of signal assignments...]

endmodule
