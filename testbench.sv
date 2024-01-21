module testbench ();

parameter WORD_SIZE = 8;
parameter N = 1;
parameter M = 1;
parameter ACTIVATION = 2;
parameter WEIGHTS_FILE = "weights_1_1.txt";

logic clk, n_rst, init, ready;
logic [WORD_SIZE-1:0] inputs [N-1:0], outputs [N-1:0];

initial begin
    clk = 0;
    n_rst = 0;
    init = 0;
    for (int i = 0; i < N; i++) begin
        inputs[i] = i+1;
    end
    #7;
    n_rst = 1;
    init = 1;
    #100;
    //init = 0;
end

always begin
    clk = !clk;
    #5;
end

top #(
    .WORD_SIZE(WORD_SIZE),
    .N(N),
    .M(M),
    .ACTIVATION(ACTIVATION),
    .WEIGHTS_FILE(WEIGHTS_FILE)
) DUT (
    .clk(clk), 
    .n_rst(n_rst), 
    .init(init),
    .inputs(inputs),
    .ready(ready),
    .outputs(outputs)
);
    
endmodule