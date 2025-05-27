`timescale 1ns / 1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 868  // 100MHz / 115200 baud
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx_serial,
    output wire       tx_busy,
    output reg        tx_done
);

    localparam IDLE       = 3'b000;
    localparam START_BIT  = 3'b001;
    localparam DATA_BITS  = 3'b010;
    localparam STOP_BIT   = 3'b011;
    localparam CLEANUP    = 3'b100;
    
    reg [2:0] state = IDLE;
    reg [15:0] clk_count = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] tx_data_reg = 0;
    
    assign tx_busy = (state != IDLE);
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            tx_serial <= 1'b1;
            tx_done <= 1'b0;
            clk_count <= 0;
            bit_index <= 0;
        end else begin
            tx_done <= 1'b0;
            
            case (state)
                IDLE: begin
                    tx_serial <= 1'b1;
                    clk_count <= 0;
                    bit_index <= 0;
                    
                    if (tx_start) begin
                        tx_data_reg <= tx_data;
                        state <= START_BIT;
                    end
                end
                
                START_BIT: begin
                    tx_serial <= 1'b0;
                    
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state <= DATA_BITS;
                    end
                end
                
                DATA_BITS: begin
                    tx_serial <= tx_data_reg[bit_index];
                    
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state <= STOP_BIT;
                        end
                    end
                end
                
                STOP_BIT: begin
                    tx_serial <= 1'b1;
                    
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        tx_done <= 1'b1;
                        clk_count <= 0;
                        state <= CLEANUP;
                    end
                end
                
                CLEANUP: begin
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

