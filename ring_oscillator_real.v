module ring_oscillator_real #(
    parameter LENGTH = 3
)(
    input  wire enable,
    output wire ro_out
);

    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *)
    wire [LENGTH-1:0] chain;

    // AND-gate feedback: harder for synthesis to optimize away than ?:
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *)
    assign chain[0] = enable & ~chain[LENGTH-1];

    genvar i;
    generate
        for (i = 1; i < LENGTH; i = i + 1) begin : INV_CHAIN
            (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *)
            assign chain[i] = ~chain[i-1];
        end
    endgenerate

    assign ro_out = chain[LENGTH-1];

endmodule