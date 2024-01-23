module datapath #(
    parameter WORD_SIZE = 8,
    parameter N = 2,
    parameter ACTIVATION = 2
) (
    input  logic clk, n_rst, write_en, start, neuron_rst,
    input  logic ctrl, 
    input  logic [WORD_SIZE-1:0] inputs  [N-1:0], weights [(N+1)*N-1:0],
    output logic out_valid,
    output logic [WORD_SIZE-1:0] outputs [N-1:0]
);

logic [WORD_SIZE-1:0] data[N-1:0], prev_result[N-1:0], bias;
assign bias = 1;

logic[N-1:0] neuron_valid;
assign out_valid = &neuron_valid;

assign outputs = prev_result;

logic [WORD_SIZE-1:0] inputNeuron [N:0];

genvar i;

always_comb begin
    for (int j = 0; j < N; j++) begin
        inputNeuron[j] = data[j];
    end

    inputNeuron[N] = bias;
end

generate;
    for (i = 0; i < N; i++) begin
        lab2 #(.N(N+1), .K(N+1), .width(WORD_SIZE), .activation(ACTIVATION)) neuron (
            .clk(clk),
            .reset(n_rst & neuron_rst),
            .start(start),
            .w(weights[(N+1)*(i+1)-1:N*i+i]),
            .x(inputNeuron),
            .o(prev_result[i]),
            .out_valid(neuron_valid[i])
        );
    end
endgenerate

always_ff @(posedge clk or negedge n_rst) begin
    if (!n_rst) begin
        data <= '{default: '0};
    end else begin
        if (write_en) begin       // Write enable true to input values
            data <= inputs;
        end else if (ctrl) begin  // ctrl true if values comming from previous layers
            data <= prev_result;
        end
    end
end

endmodule

module FSM #(
    parameter M = 2
) (
    input  logic clk, n_rst, init, out_valid, 
    output logic ctrl, start, write_en, ready, neuron_rst,
    output logic [$clog2(M):0] counter
);

    typedef enum logic [3:0] {IDLE, FETCH, OP, COMPLETE} statetype;
    statetype state, nextstate;

    // State register
    always_ff @(posedge clk or negedge n_rst) begin
        if(!n_rst) state <= IDLE;
        else state <= nextstate;
    end

    parameter START_DEL = 2;
    logic next_start[START_DEL:0];

    always_ff @(posedge clk or negedge n_rst) begin
        if(!n_rst) begin
            next_start <= '{default: '0};
        end
        else begin
            next_start[0] <= out_valid;
            for (int i = 1; i <= START_DEL; i++) begin
                next_start[i] <= next_start[i-1]; 
            end 
        end
        if(next_start[0]) 
            neuron_rst <= 0;
        else begin
            neuron_rst <= 1;    
        end
    end

    // Next state logic
    always_comb begin
        case(state) 
            IDLE: nextstate = init ? FETCH : IDLE;
            FETCH: nextstate = OP;
            OP: nextstate = (counter == M) ? COMPLETE : OP;
            COMPLETE: nextstate = IDLE;
            default: nextstate = IDLE;
        endcase
    end

    // Counter logic
    always_ff @(posedge clk or negedge n_rst) begin
        if (~n_rst) begin
            counter = 0;
        end
        else if (state == OP && out_valid) begin
            counter = counter + 1;
        end
    end

    // Output logic
    always_comb begin
        case (state)
            IDLE: begin
                ctrl = 1'b0;
                start = 1'b0;
                write_en = 1'b0;
                ready = 1'b0;
            end
            FETCH: begin
                ctrl = 1'b0;
                start = 1'b1;
                write_en = 1'b1;
                ready = 1'b0;
            end
            OP: begin
                ctrl = out_valid;
                start = next_start[START_DEL];
                write_en = 1'b0;
                ready = 1'b0;
            end
            COMPLETE: begin
                ctrl = 1'b0;
                start = 1'b0;
                write_en = 1'b0;
                ready = 1'b1;
            end
        endcase
    end
   
endmodule

module weights_mem #(
    parameter WORD_SIZE = 8,
    parameter N = 2,
    parameter M = 2,
    parameter WEIGHTS_FILE = "filename.txt"
) (
    input  logic clk,
    input  logic[$clog2(M):0] addr,
    output logic[WORD_SIZE-1:0] weights[(N+1)*N-1:0]
);

logic [WORD_SIZE-1:0] weights_reg[M-1:0][(N+1)*N-1:0];

initial begin
    $readmemh(WEIGHTS_FILE, weights_reg);
end

always_ff @(posedge clk) begin
    weights <= weights_reg[addr];
end
    
endmodule

module top #(
    parameter WORD_SIZE = 8,
    parameter N = 2,
    parameter M = 2,
    parameter ACTIVATION = 2,
    parameter WEIGHTS_FILE = "weights.dat"
) (
    input  logic clk, n_rst, init,
    input  logic [WORD_SIZE-1:0] inputs [N-1:0],
    output logic ready,
    output logic [WORD_SIZE-1:0] outputs[N-1:0]
);

logic write_en, start, ctrl, out_valid, neuron_rst;
logic[$clog2(M):0]counter;
logic[WORD_SIZE-1:0] weights[(N+1)*N-1:0];

datapath #(
    .WORD_SIZE(WORD_SIZE),
    .N(N),
    .ACTIVATION(ACTIVATION)
) MLP_DP (
    .clk(clk), 
    .n_rst(n_rst), 
    .write_en(write_en), 
    .start(start),
    .ctrl(ctrl), 
    .inputs(inputs),
    .weights(weights),
    .out_valid(out_valid),
    .outputs(outputs),
    .neuron_rst(neuron_rst)
);

FSM #(
    .M(M)
) MLP_FSM (
    .clk(clk), 
    .n_rst(n_rst), 
    .init(init), 
    .out_valid(out_valid), 
    .ctrl(ctrl), 
    .start(start), 
    .write_en(write_en),
    .ready(ready),
    .counter(counter),
    .neuron_rst(neuron_rst)
);

weights_mem #(
    .WORD_SIZE(WORD_SIZE),
    .N(N),
    .M(M),
    .WEIGHTS_FILE(WEIGHTS_FILE)
) MLP_WM (
    .clk(clk),
    .addr(counter),
    .weights(weights)
);

endmodule