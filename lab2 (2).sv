module step #(parameter width = 16)
(
    input clk,
    input reset,
    input [width-1:0] i,
    input start,
    output reg [width-1:0] o,
    output reg valid
);

wire [4:0] frac = (width==32) ? 20 :
                  (width==16) ? 10 :
                  5;
always @(posedge clk or negedge reset)
    if(!reset)
        o <= 0;
    else if(start)
    begin
        if(i[width-1])
            o <= ~0;
        else
            o <= 1 << frac;
    end
    else
        o <= o;

always @(posedge clk or negedge reset)
    if(!reset)
        valid <= 0;
    else
        valid <= start;

endmodule

module sigmoid #(parameter width = 16)
(
    input clk,
    input reset,
    input [width-1:0] i,
    input start,
    output reg [width-1:0] o,
    output reg valid
);

parameter slop = 0.25;
parameter intercept = 0.5;
parameter x_low = -4;
parameter x_high = 4;

always @(posedge clk or negedge reset)
    if(!reset)
        o <= 0;
    else if(start)
    begin
        if(i < x_low)
            o <= 0;
        else if(i > x_high)
            o <= 1;
        else
            o <= i * slop + intercept;
    end
    else
        o <= o;

always @(posedge clk or negedge reset)
    if(!reset)
        valid <= 0;
    else
        valid <= start;

endmodule

module relu #(parameter width = 16)
(
    input clk,
    input reset,
    input [width-1:0] i,
    input start,
    output reg [width-1:0] o,
    output reg valid
);

always @(posedge clk or negedge reset)
    if(!reset)
        o <= 0;
    else if(start)
    begin
        if(i > 0)
            o <= i;
        else
            o <= 0;
    end
    else
        o <= o;

always @(posedge clk or negedge reset)
    if(!reset)
        valid <= 0;
    else
        valid <= start;

endmodule

module lab2 #(
    parameter N = 8,
    parameter K = 1,
    parameter width =8,
    parameter activation = 1  //  0:step   1:sigmoid    2:relu
)
(
    input clk,
    input reset,
    input start,
//    input [N-1: 0] w [width-1:0],
//    input [N-1: 0] x [width-1:0],
    input [width-1:0] w [N-1: 0],
    input [width-1:0] x [N-1: 0],
    input [width-1:0] bias,
    output reg [width-1:0] o,
    output reg out_valid
);

parameter IDLE = 5'b00001;
parameter DATA_PREPROCESS = 5'b00010;
parameter PARA_MAC = 5'b00100;
parameter ADD_TREE = 5'b01000;
parameter ACTIV = 5'b10000;

parameter remainder = N%K;
parameter para_loop_num =  (remainder==0) ? N/K : N/K +1;
parameter LEVELS = $clog2(K+1);

reg [4:0] cur, nxt;

always @(posedge clk or negedge reset)
    if(!reset)
        cur <= IDLE;
    else
        cur <= nxt;

reg data_preprocess_done;
//reg add_done;
reg para_done;
reg add_tree_done;
wire activation_done;
always @(*)
    case(cur)
        IDLE:
            if(start)
                nxt = DATA_PREPROCESS;
            else
                nxt = IDLE;
        DATA_PREPROCESS:
            if(data_preprocess_done)
                nxt = PARA_MAC;
            else
                nxt = DATA_PREPROCESS;
        PARA_MAC:
            if(para_done)
                nxt = ADD_TREE;
            else
                nxt = PARA_MAC;
        ADD_TREE:
            if(add_tree_done)
                nxt = ACTIV;
            else
                nxt = ADD_TREE;
        ACTIV:
            if(activation_done)
                nxt = IDLE;
            else
                nxt = ACTIV;
    endcase

wire cur_idle = cur == IDLE;
wire cur_data_preprocess = cur == DATA_PREPROCESS;
wire cur_para_mac = cur == PARA_MAC;
wire cur_add_tree = cur == ADD_TREE;
wire cur_activ = cur == ACTIV;

wire nxt_data_preprocess = nxt == DATA_PREPROCESS;
wire nxt_para_mac = nxt == PARA_MAC;
wire nxt_add_tree = nxt == ADD_TREE;
wire nxt_activ = nxt == ACTIV;
wire nxt_idle = nxt == IDLE;

wire cur_para_mac_nxt_add_tree = cur_para_mac & nxt_add_tree;
wire cur_add_tree_nxt_activ = cur_add_tree & nxt_activ;

//wire para_muling = cur_para_mul&
//wire mul_start = cur_para_add && nxt_para_mul;
wire activation_start = cur_add_tree && nxt_activ;
wire pre_out_valid = cur_activ && nxt_idle;
wire cnt_flg = cur_para_mac & ~cur_para_mac_nxt_add_tree || cur_add_tree & ~cur_add_tree_nxt_activ;


/******************************* CNT ***********************************/
wire [5:0] loop_num = cur_add_tree ? LEVELS : cur_para_mac & (N == K) ? 0 : para_loop_num -1;
//wire [5:0] loop_num = cur_add_tree ? LEVELS+5 : cur_para_mac & (N == K) ? 0 : para_loop_num -1;
//wire [5:0] loop_num = cur_idle ? 0 :
//                      cur_para_mac ? (N == K) ? 0 : para_loop_num :
//                      K-1;
reg [5:0] cnt;
always @(posedge clk or negedge reset)
    if(!reset)
        cnt <= 0;
    else if(cur_idle)
        cnt <= 0;
    else if(cnt_flg)
    begin
        if(cnt == loop_num)
            cnt <= 0;
        else
            cnt <= cnt + 1'b1;
    end
    else
        cnt <= cnt;

/******************************* PARA_MUL ***********************************/ 
parameter element_num = remainder ? K - remainder : 0;
reg [width-1:0] new_w [N-1 + element_num: 0];
reg [width-1:0] new_x [N-1 + element_num: 0];

integer k; 
always @(posedge clk or negedge reset) begin 
	if(~reset)
	begin
	    for (k = 0; k < N + K -remainder; k = k + 1) 
		begin        
			new_w[k] = 0;       
			new_x[k] = 0; 
		end 
	end
	else if(cur_data_preprocess & ~data_preprocess_done)
	begin
		for (k = 0; k < N; k = k + 1) 
		begin        
			new_w[k] = w[k];       
			new_x[k] = x[k]; 
		end 
			
		for (k = N; k < N + K -remainder; k = k + 1)  
		begin    
			new_w[k] = 0; 
			new_x[k] = 0;
		end 
	end
	else
	begin
		new_w = new_w;
		new_x = new_x;
	end

end
        
always @(posedge clk or negedge reset)
    if(!reset)
        data_preprocess_done <= 0;
    else if(cur_data_preprocess)
    begin
        if(data_preprocess_done)
            data_preprocess_done <= 0;
        else
            data_preprocess_done <= 1;
    end
    else
        data_preprocess_done <= data_preprocess_done;
		
/******************************* MAC ***********************************/
reg [width-1:0] mac_rlt [K-1:0];
generate genvar j;
    for(j=0; j<K; j=j+1) 
    begin: para_mac
        always @(posedge clk or negedge reset)
            if(!reset)
                mac_rlt[j] <= 0;
            else if(cur_para_mac & ~para_done)
                mac_rlt[j] <= mac_rlt[j] + new_x[j + cnt * K] * new_w[j + cnt * K];
            else
                mac_rlt[j] <= mac_rlt[j];
    end
endgenerate

/**************************  parallel done  *********************************/
always @(posedge clk or negedge reset)
    if(!reset)
        para_done <= 0;
    else if(cur_para_mac)
	begin
		if(para_done)
			para_done <= 0;
		else
			para_done <= (cnt == loop_num);
	end
	else
		para_done <= para_done;

/******************************* Final add ***********************************/
//reg [width-1:0] all_add_rlt;

//always @(posedge clk or negedge reset)
//    if(!reset)
//        all_add_rlt <= 0;
//    else if(cur_add_tree & ~add_tree_done)
//        all_add_rlt <= all_add_rlt + mac_rlt[cnt];
//    else
//        all_add_rlt <= all_add_rlt;

//reg [width-1:0] add_rlt [LEVELS-1:0];
   
reg [width-1:0] level_sums[2:1][(K-1):0];

integer m, l;
reg [1:0] current_level;
wire [1:0] next_level;

reg [K:0] num_elements_current_level; // Number of elements at the current level
reg [K:0] num_elements_to_process;    // Number of elements to process

always @(posedge clk or negedge reset)
    if(~reset)
        current_level <= 1;
    else if(cur_add_tree)
        current_level <= next_level;
    else
        ;

assign next_level = current_level == 1 ? 2 : 1;

always @(posedge clk or negedge reset)
    if (!reset)
    begin
        for (m = 1; m <= 2; m = m + 1)
            for (l = 0; l < K; l = l + 1)
                level_sums[m][l] <= 0;
//        next_level <= 2;
        num_elements_current_level <= K; 
        num_elements_to_process <= (num_elements_current_level + 1) >> 1;;// Start with K elements
    end
    else if(cur_para_mac_nxt_add_tree)
    begin
        level_sums[current_level] <= mac_rlt;
//        next_level <= current_level == 1 ? 2 : 1;
    end
    else if(cur_add_tree)
    begin
//        next_level <= current_level == 1 ? 2 : 1;  // Switch between 1 and 2
//        level_sums[2][0] <= 1;
        num_elements_to_process <= (num_elements_current_level + 1) >> 1;
        for (l = 0; l < num_elements_to_process; l = l + 1)
            if ((l<<1) + 1 < num_elements_current_level)
                level_sums[next_level][l] <= level_sums[current_level][l<<1] + level_sums[current_level][(l<<1) + 1];
            else
                level_sums[next_level][l] <= level_sums[current_level][l<<1];

    end
    else
        ;



always @(posedge clk or negedge reset)
    if(!reset)
        add_tree_done <= 0;
    else if(cur_add_tree)
    begin
        if(add_tree_done)
            add_tree_done <= 0;
        else
            add_tree_done <= (cnt == loop_num);
    end
    else
        add_tree_done <= add_tree_done;

wire [width-1:0] all_add_rlt = level_sums[next_level][0];
/******************************* ACTIV ***********************************/
generate
    if(activation == 0)
    begin
        step #(width) u_step(
            .clk(clk),
            .reset(reset),
            .i(all_add_rlt+bias),
            .start(activation_start),
            .o(o),
            .valid(activation_done)
        );
    end
    else if(activation == 1)
    begin
        sigmoid #(width) u_sigmoid(
            .clk(clk),
            .reset(reset),
            .i(all_add_rlt+bias),
            .start(activation_start),
            .o(o),
            .valid(activation_done)
        );
    end
    else
    begin
        relu #(width) u_relu(
            .clk(clk),
            .reset(reset),
            .i(all_add_rlt+bias),
            .start(activation_start),
            .o(o),
            .valid(activation_done)
        );
    end
endgenerate

/**********************************  out_valid *************************************/

always @(posedge clk or negedge reset)
    if(~reset)
        out_valid <= 0;
    else
        out_valid <= pre_out_valid;
        
        
endmodule
