`timescale 1ns / 1ps

module sha256_core (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [511:0] block,
    output reg          done,
    output reg  [255:0] digest,
    output wire         busy
);

    // =============================================
    // Round Constants
    // =============================================
    reg [31:0] K [0:63];
    initial begin
        K[ 0]=32'h428a2f98; K[ 1]=32'h71374491;
        K[ 2]=32'hb5c0fbcf; K[ 3]=32'he9b5dba5;
        K[ 4]=32'h3956c25b; K[ 5]=32'h59f111f1;
        K[ 6]=32'h923f82a4; K[ 7]=32'hab1c5ed5;
        K[ 8]=32'hd807aa98; K[ 9]=32'h12835b01;
        K[10]=32'h243185be; K[11]=32'h550c7dc3;
        K[12]=32'h72be5d74; K[13]=32'h80deb1fe;
        K[14]=32'h9bdc06a7; K[15]=32'hc19bf174;
        K[16]=32'he49b69c1; K[17]=32'hefbe4786;
        K[18]=32'h0fc19dc6; K[19]=32'h240ca1cc;
        K[20]=32'h2de92c6f; K[21]=32'h4a7484aa;
        K[22]=32'h5cb0a9dc; K[23]=32'h76f988da;
        K[24]=32'h983e5152; K[25]=32'ha831c66d;
        K[26]=32'hb00327c8; K[27]=32'hbf597fc7;
        K[28]=32'hc6e00bf3; K[29]=32'hd5a79147;
        K[30]=32'h06ca6351; K[31]=32'h14292967;
        K[32]=32'h27b70a85; K[33]=32'h2e1b2138;
        K[34]=32'h4d2c6dfc; K[35]=32'h53380d13;
        K[36]=32'h650a7354; K[37]=32'h766a0abb;
        K[38]=32'h81c2c92e; K[39]=32'h92722c85;
        K[40]=32'ha2bfe8a1; K[41]=32'ha81a664b;
        K[42]=32'hc24b8b70; K[43]=32'hc76c51a3;
        K[44]=32'hd192e819; K[45]=32'hd6990624;
        K[46]=32'hf40e3585; K[47]=32'h106aa070;
        K[48]=32'h19a4c116; K[49]=32'h1e376c08;
        K[50]=32'h2748774c; K[51]=32'h34b0bcb5;
        K[52]=32'h391c0cb3; K[53]=32'h4ed8aa4a;
        K[54]=32'h5b9cca4f; K[55]=32'h682e6ff3;
        K[56]=32'h748f82ee; K[57]=32'h78a5636f;
        K[58]=32'h84c87814; K[59]=32'h8cc70208;
        K[60]=32'h90befffa; K[61]=32'ha4506ceb;
        K[62]=32'hbef9a3f7; K[63]=32'hc67178f2;
    end

    // =============================================
    // Functions
    // =============================================
    function [31:0] ROTR;
        input [31:0] x;
        input [4:0] n;
        ROTR = (x >> n) | (x << (32-n));
    endfunction

    function [31:0] Ch;
        input [31:0] x,y,z;
        Ch = (x & y) ^ (~x & z);
    endfunction

    function [31:0] Maj;
        input [31:0] x,y,z;
        Maj = (x & y) ^ (x & z) ^ (y & z);
    endfunction

    function [31:0] S0;
        input [31:0] x;
        S0 = ROTR(x,2) ^ ROTR(x,13) ^ ROTR(x,22);
    endfunction

    function [31:0] S1;
        input [31:0] x;
        S1 = ROTR(x,6) ^ ROTR(x,11) ^ ROTR(x,25);
    endfunction

    function [31:0] s0;
        input [31:0] x;
        s0 = ROTR(x,7) ^ ROTR(x,18) ^ (x >> 3);
    endfunction

    function [31:0] s1;
        input [31:0] x;
        s1 = ROTR(x,17) ^ ROTR(x,19) ^ (x >> 10);
    endfunction

    // =============================================
    // Registers
    // =============================================
    reg [31:0] W [0:63];
    reg [31:0] a,b,c,d,e,f,g,h;
    reg [31:0] H0,H1,H2,H3,H4,H5,H6,H7;
    reg [6:0]  round;          // 7-bit: needs to reach 64
    reg busy_reg;

    assign busy = busy_reg;

    integer idx;

    // =============================================
    // Combinational T1 / T2 (FIX: were registered,
    // causing 1-cycle stale-value bug)
    // =============================================
    wire [31:0] W_curr;
    assign W_curr = (round < 16) ? W[round] :
                    (s1(W[round-2]) + W[round-7]
                   + s0(W[round-15]) + W[round-16]);

    wire [31:0] T1_comb = h + S1(e) + Ch(e,f,g) + K[round] + W_curr;
    wire [31:0] T2_comb = S0(a) + Maj(a,b,c);

    // =============================================
    // Main FSM
    // =============================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_reg <= 0;
            done     <= 0;
            round    <= 0;
            digest   <= 256'd0;
        end else begin
            done <= 0;

            if (start && !busy_reg) begin
                busy_reg <= 1;
                round    <= 0;

                // Initial hash values (SHA-256 spec)
                H0<=32'h6a09e667; H1<=32'hbb67ae85;
                H2<=32'h3c6ef372; H3<=32'ha54ff53a;
                H4<=32'h510e527f; H5<=32'h9b05688c;
                H6<=32'h1f83d9ab; H7<=32'h5be0cd19;

                // Load message schedule W[0..15]
                for (idx = 0; idx < 16; idx = idx + 1)
                    W[idx] <= block[511 - 32*idx -: 32];

                // Initialize working variables
                a<=32'h6a09e667; b<=32'hbb67ae85;
                c<=32'h3c6ef372; d<=32'ha54ff53a;
                e<=32'h510e527f; f<=32'h9b05688c;
                g<=32'h1f83d9ab; h<=32'h5be0cd19;

            end else if (busy_reg) begin

                // ---- Round 0..63: compression ----
                if (round <= 63) begin

                    // Extend message schedule for rounds >= 16
                    if (round >= 16)
                        W[round] <= W_curr;

                    // Update working variables (combinational T1/T2)
                    h <= g;
                    g <= f;
                    f <= e;
                    e <= d + T1_comb;
                    d <= c;
                    c <= b;
                    b <= a;
                    a <= T1_comb + T2_comb;

                    round <= round + 1;
                end

                // ---- Round 64: finalize digest ----
                // a-h now hold the results after all 64 rounds
                if (round == 64) begin
                    digest <= {
                        a + H0, b + H1, c + H2, d + H3,
                        e + H4, f + H5, g + H6, h + H7
                    };
                    busy_reg <= 0;
                    done     <= 1;
                end
            end
        end
    end

endmodule