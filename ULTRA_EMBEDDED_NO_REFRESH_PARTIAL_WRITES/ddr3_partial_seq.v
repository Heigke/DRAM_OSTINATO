// New module: ddr3_partial_seq.v
// This wraps the existing sequencer and adds partial write control

module ddr3_partial_seq
#(
    parameter DDR_MHZ          = 50,
    parameter DDR_WRITE_LATENCY = 6,
    parameter DDR_READ_LATENCY = 5,
    parameter DDR_BURST_LEN    = 4,
    parameter DDR_COL_W        = 9,
    parameter DDR_BANK_W       = 3,
    parameter DDR_ROW_W        = 15,
    parameter DDR_DATA_W       = 32,
    parameter DDR_DQM_W        = 4
)
(
    // Inputs
    input           clk_i,
    input           rst_i,
    input  [14:0]   address_i,
    input  [2:0]    bank_i,
    input  [3:0]    command_i,
    input           cke_i,
    input  [127:0]  wrdata_i,
    input  [15:0]   wrdata_mask_i,
    input  [31:0]   dfi_rddata_i,
    input           dfi_rddata_valid_i,
    input  [1:0]    dfi_rddata_dnv_i,
    
    // Partial write control
    input           partial_write_en_i,
    input  [2:0]    partial_write_cycles_i,  // 1-8 cycles
    
    // Outputs
    output          accept_o,
    output [127:0]  rddata_o,
    output          rddata_valid_o,
    output [14:0]   dfi_address_o,
    output [2:0]    dfi_bank_o,
    output          dfi_cas_n_o,
    output          dfi_cke_o,
    output          dfi_cs_n_o,
    output          dfi_odt_o,
    output          dfi_ras_n_o,
    output          dfi_reset_n_o,
    output          dfi_we_n_o,
    output [31:0]   dfi_wrdata_o,
    output reg      dfi_wrdata_en_o,
    output [3:0]    dfi_wrdata_mask_o,
    output          dfi_rddata_en_o
);

// Internal signals
wire        seq_wrdata_en_w;
wire [31:0] seq_wrdata_w;
wire [3:0]  seq_wrdata_mask_w;

// Instantiate original sequencer
ddr3_dfi_seq #(
    .DDR_MHZ(DDR_MHZ),
    .DDR_WRITE_LATENCY(DDR_WRITE_LATENCY),
    .DDR_READ_LATENCY(DDR_READ_LATENCY),
    .DDR_BURST_LEN(DDR_BURST_LEN),
    .DDR_COL_W(DDR_COL_W),
    .DDR_BANK_W(DDR_BANK_W),
    .DDR_ROW_W(DDR_ROW_W),
    .DDR_DATA_W(DDR_DATA_W),
    .DDR_DQM_W(DDR_DQM_W)
) u_seq (
    .clk_i(clk_i),
    .rst_i(rst_i),
    .address_i(address_i),
    .bank_i(bank_i),
    .command_i(command_i),
    .cke_i(cke_i),
    .wrdata_i(wrdata_i),
    .wrdata_mask_i(wrdata_mask_i),
    .dfi_rddata_i(dfi_rddata_i),
    .dfi_rddata_valid_i(dfi_rddata_valid_i),
    .dfi_rddata_dnv_i(dfi_rddata_dnv_i),
    .accept_o(accept_o),
    .rddata_o(rddata_o),
    .rddata_valid_o(rddata_valid_o),
    .dfi_address_o(dfi_address_o),
    .dfi_bank_o(dfi_bank_o),
    .dfi_cas_n_o(dfi_cas_n_o),
    .dfi_cke_o(dfi_cke_o),
    .dfi_cs_n_o(dfi_cs_n_o),
    .dfi_odt_o(dfi_odt_o),
    .dfi_ras_n_o(dfi_ras_n_o),
    .dfi_reset_n_o(dfi_reset_n_o),
    .dfi_we_n_o(dfi_we_n_o),
    .dfi_wrdata_o(seq_wrdata_w),
    .dfi_wrdata_en_o(seq_wrdata_en_w),
    .dfi_wrdata_mask_o(seq_wrdata_mask_w),
    .dfi_rddata_en_o(dfi_rddata_en_o)
);

// Partial write control logic
reg [2:0] write_cycle_cnt;
reg       write_active;

always @(posedge clk_i) begin
    if (rst_i) begin
        write_cycle_cnt <= 3'd0;
        write_active <= 1'b0;
        dfi_wrdata_en_o <= 1'b0;
    end else begin
        // Detect start of write
        if (seq_wrdata_en_w && !write_active) begin
            write_active <= 1'b1;
            write_cycle_cnt <= 3'd1;
        end
        
        // Count write cycles
        if (write_active && seq_wrdata_en_w) begin
            write_cycle_cnt <= write_cycle_cnt + 3'd1;
        end
        
        // End write when done
        if (!seq_wrdata_en_w && write_active) begin
            write_active <= 1'b0;
            write_cycle_cnt <= 3'd0;
        end
        
        // Control write enable based on partial write settings
        if (partial_write_en_i && write_active) begin
            // Cut off write after specified cycles
            if (write_cycle_cnt <= partial_write_cycles_i) begin
                dfi_wrdata_en_o <= seq_wrdata_en_w;
            end else begin
                dfi_wrdata_en_o <= 1'b0;  // Truncate write
            end
        end else begin
            // Normal operation
            dfi_wrdata_en_o <= seq_wrdata_en_w;
        end
    end
end

// Pass through data and mask
assign dfi_wrdata_o = seq_wrdata_w;
assign dfi_wrdata_mask_o = seq_wrdata_mask_w;

endmodule
