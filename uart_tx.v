module uart_tx (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy
);

    localparam CLKS_PER_BIT = 100_000_000 / 115200;

    reg [13:0] clk_cnt;
    reg [3:0]  bit_idx;
    reg [9:0]  shift_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx      <= 1'b1;
            busy    <= 0;
            clk_cnt <= 0;
            bit_idx <= 0;
        end else begin
            if (start && !busy) begin
                busy      <= 1;
                shift_reg <= {1'b1, data, 1'b0};  // stop + data + start
                clk_cnt   <= 0;
                bit_idx   <= 0;
            end else if (busy) begin
                if (clk_cnt < CLKS_PER_BIT - 1)
                    clk_cnt <= clk_cnt + 1;
                else begin
                    clk_cnt   <= 0;
                    tx        <= shift_reg[0];
                    shift_reg <= {1'b1, shift_reg[9:1]};
                    bit_idx   <= bit_idx + 1;
                    if (bit_idx == 9)
                        busy <= 0;
                end
            end
        end
    end

endmodule