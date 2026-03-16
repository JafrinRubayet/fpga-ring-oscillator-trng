module trng_top (
    input  wire       clk,
    input  wire       rst,
    output wire [3:0] led,
    output wire       uart_tx_out
);

    parameter NUM_RO = 16;
    localparam HALF_PERIOD = 100_000_000 / (390_000 * 2);  // ~128 cycles

    // ==================================================
    // 27-BIT VISIBILITY DIVIDER  (~0.5 s LED refresh)
    // ==================================================
    reg [26:0] vis_cnt;
    reg vis_tick;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vis_cnt  <= 0;
            vis_tick <= 0;
        end else begin
            if (vis_cnt == 27'd50_000_000) begin
                vis_cnt  <= 0;
                vis_tick <= 1;
            end else begin
                vis_cnt  <= vis_cnt + 1;
                vis_tick <= 0;
            end
        end
    end

    // ==================================================
    // RO START / STOP CLOCK  (390 kHz toggle)
    // ==================================================
    reg [$clog2(HALF_PERIOD)-1:0] ss_counter;
    reg ro_enable, ro_enable_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ss_counter  <= 0;
            ro_enable   <= 0;
            ro_enable_d <= 0;
        end else begin
            ro_enable_d <= ro_enable;
            if (ss_counter == HALF_PERIOD - 1) begin
                ss_counter <= 0;
                ro_enable  <= ~ro_enable;
            end else
                ss_counter <= ss_counter + 1;
        end
    end

    wire ro_enable_fall = ro_enable_d & ~ro_enable;

    // ==================================================
    // RING OSCILLATORS  (varying lengths for decorrelation)
    // ==================================================
    wire [NUM_RO-1:0] ro_raw;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_RO; gi = gi + 1) begin : RO_BLOCK
            ring_oscillator_real #(
                .LENGTH(3 + (gi % 4) * 2)   // 3, 5, 7, 9, …
            ) ro_inst (
                .enable(ro_enable),
                .ro_out(ro_raw[gi])
            );
        end
    endgenerate

    // ==================================================
    // 2-STAGE SYNCHRONIZER  (metastability guard)
    // ==================================================
    reg [NUM_RO-1:0] ro_sync1, ro_sync2, ro_prev;

    always @(posedge clk) begin
        ro_sync1 <= ro_raw;
        ro_sync2 <= ro_sync1;
        ro_prev  <= ro_sync2;
    end

    // ==================================================
    // EDGE COUNTING  (per-RO, 6-bit with saturation)
    // ==================================================
    reg [5:0] edge_count     [0:NUM_RO-1];
    reg [5:0] captured_count [0:NUM_RO-1];
    reg capture_valid;
    integer j;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            capture_valid <= 0;
            for (j = 0; j < NUM_RO; j = j + 1) begin
                edge_count[j]     <= 0;
                captured_count[j] <= 0;
            end
        end else begin
            capture_valid <= 0;

            if (ro_enable) begin
                for (j = 0; j < NUM_RO; j = j + 1)
                    if (ro_sync2[j] != ro_prev[j])
                        // FIX: saturate at 63 to prevent overflow bias
                        if (edge_count[j] != 6'h3F)
                            edge_count[j] <= edge_count[j] + 1;
            end

            if (ro_enable_fall) begin
                for (j = 0; j < NUM_RO; j = j + 1) begin
                    captured_count[j] <= edge_count[j];
                    edge_count[j]     <= 0;
                end
                capture_valid <= 1;
            end
        end
    end

    // ==================================================
    // LSB-ONLY ENTROPY MIX
    //   XOR the least-significant bit of each RO's count.
    //   The LSB carries the most jitter entropy; higher
    //   bits are correlated across oscillators and across
    //   samples. Produces 1 clean bit per capture cycle.
    // ==================================================
    reg entropy_bit;
    integer k;

    always @(*) begin
        entropy_bit = 1'b0;
        for (k = 0; k < NUM_RO; k = k + 1)
            entropy_bit = entropy_bit ^ captured_count[k][0];
    end

    // ==================================================
    // STARTUP DISCARD  (ignore first 512 samples)
    // ==================================================
    reg [9:0] startup_cnt;
    wire startup_done = (startup_cnt >= 10'd512);

    always @(posedge clk or posedge rst) begin
        if (rst)
            startup_cnt <= 0;
        else if (capture_valid && !startup_done)
            startup_cnt <= startup_cnt + 1;
    end

    // ==================================================
    // REPETITION COUNT TEST  (RCT)
    //   Flags if the same bit repeats >= 16 times
    // ==================================================
    reg        last_bit;
    reg [4:0]  repeat_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            last_bit   <= 0;
            repeat_cnt <= 0;
        end else if (capture_valid && startup_done) begin
            if (entropy_bit == last_bit)
                repeat_cnt <= repeat_cnt + 1;
            else
                repeat_cnt <= 0;
            last_bit <= entropy_bit;
        end
    end

    wire rct_fail = (repeat_cnt >= 16);

    // ==================================================
    // ADAPTIVE PROPORTION TEST  (sliding 64-bit window)
    //   Flags if popcount < 6 or > 58  (~3 sigma)
    // ==================================================
    reg [63:0] apt_window;
    reg [6:0]  apt_count;
    reg [6:0]  apt_fill_cnt;

    wire apt_ready = (apt_fill_cnt >= 64);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            apt_window   <= 0;
            apt_count    <= 0;
            apt_fill_cnt <= 0;
        end else if (capture_valid && startup_done) begin
            apt_window <= {apt_window[62:0], entropy_bit};
            apt_count  <= apt_count
                        + (entropy_bit      ? 7'd1 : 7'd0)
                        - (apt_window[63]   ? 7'd1 : 7'd0);

            if (!apt_ready)
                apt_fill_cnt <= apt_fill_cnt + 1;
        end
    end

    wire apt_fail = apt_ready &&
                    ((apt_count > 58) || (apt_count < 6));

    wire health_pass = startup_done & ~rct_fail & ~apt_fail;

    // ==================================================
    // 512-BIT ENTROPY BUFFER → SHA-256
    //   Fills 1 bit per capture cycle (512 cycles to fill)
    // ==================================================
    reg [511:0] entropy_buf;
    reg [511:0] sha_block_reg;
    reg [9:0]   bit_cnt;
    reg sha_start;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            entropy_buf   <= 0;
            sha_block_reg <= 0;
            bit_cnt       <= 0;
            sha_start     <= 0;
        end else begin
            sha_start <= 0;

            if (capture_valid && health_pass) begin
                entropy_buf <= {entropy_buf[510:0], entropy_bit};

                if (bit_cnt == 10'd511 && !sha_busy) begin
                    // Freeze the buffer with the final bit included
                    sha_block_reg <= {entropy_buf[510:0], entropy_bit};
                    bit_cnt       <= 0;
                    sha_start     <= 1;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end
        end
    end

    // ==================================================
    // SHA-256 WHITENING
    // ==================================================
    wire [255:0] sha_digest;
    wire sha_done;
    wire sha_busy;

    sha256_core sha_inst (
        .clk    (clk),
        .rst    (rst),
        .start  (sha_start),
        .block  (sha_block_reg),
        .done   (sha_done),
        .digest (sha_digest),
        .busy   (sha_busy)
    );

    // ==================================================
    // UART TX  (32 bytes per digest, MSB-first)
    // ==================================================
    reg [255:0] digest_reg;
    reg [4:0]   byte_index;
    reg sending;
    reg uart_start;
    reg [7:0] uart_data;
    wire uart_busy;

    uart_tx uart_inst (
        .clk   (clk),
        .rst   (rst),
        .start (uart_start),
        .data  (uart_data),
        .tx    (uart_tx_out),
        .busy  (uart_busy)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            byte_index <= 0;
            sending    <= 0;
            uart_start <= 0;
            uart_data  <= 0;
        end else begin
            uart_start <= 0;

            // Only latch new digest when not already sending
            if (sha_done && !sending) begin
                digest_reg <= sha_digest;
                byte_index <= 0;
                sending    <= 1;
            end

            // FIX: removed unnecessary !uart_start guard
            if (sending && !uart_busy) begin
                uart_data  <= digest_reg[255 - byte_index*8 -: 8];
                uart_start <= 1;

                if (byte_index == 5'd31)
                    sending <= 0;
                else
                    byte_index <= byte_index + 1;
            end
        end
    end

    // ==================================================
    // LED STATUS
    //   LED[0] = health_pass
    //   LED[1] = apt_fail
    //   LED[2] = rct_fail
    //   LED[3] = entropy_bit  (visible randomness)
    // ==================================================
    reg [3:0] led_reg;

    always @(posedge clk or posedge rst) begin
        if (rst)
            led_reg <= 0;
        else if (vis_tick)
            led_reg <= {entropy_bit, rct_fail, apt_fail, health_pass};
    end

    assign led = led_reg;

endmodule