
/*-----------------------------------------------------------------------------
 * File          : Matrix_Vector_Multiplication.v
 * Author        : PHAM HOAI LUAN
 * Created       : 05.05.2025
 * Last modified : 05.05.2025
 *-----------------------------------------------------------------------------
 * Description   : Top-level accelerator module for matrix-vector multiplication.
 *                 Integrates control FSM, multiple dual-port BRAM blocks for
 *                 storing matrix A, vector X, and result vector Y, and a parallel
 *                 multiply-accumulate unit (PMAU).
 *
 *                 The system reads matrix A row-by-row and vector X in parallel,
 *                 performs 8-lane parallel MAC operations, and stores the final
 *                 output in Y. Supports streaming-style control signals (Start,
 *                 Continue, Done) and memory-mapped data and address inputs.
 *
 *                 All data inputs/outputs are 16-bit fixed-point: 1 sign bit,
 *                 15 integer bits.
 *-----------------------------------------------------------------------------
 */

`timescale 1ns/1ps

module Matrix_Vector_Multiplication #(
    parameter DATA_WIDTH = 16,
    parameter W_ADDR_WIDTH = 12,
    parameter R_ADDR_WIDTH = 11
)(
    //-------------------------------------//
    //           Input Signals             //
    //-------------------------------------//
    input  wire                         CLK,
    input  wire                         RST,
    input  wire [W_ADDR_WIDTH-1:0]      W_Addr_in,
    input  wire                         W_Valid_in,
    input  wire [DATA_WIDTH*8-1:0]      W_Data_in,
    input  wire [R_ADDR_WIDTH-1:0]      R_Addr_in,
    input  wire                         R_Valid_in,
    input  wire [3:0]      				n_in,
	input  wire                         Load_in,
    input  wire                         Start_in,

    //-------------------------------------//
    //          Output Signals             //
    //-------------------------------------//
    output reg                          Done_out,
    output wire  [DATA_WIDTH*8-1:0]     R_Data_out
);

    //-------------------------------------//
    //       Parameter Declarations        //
    //-------------------------------------//
	
	// For FSM
	
    localparam IDLE        				= 2'd0;
    localparam LOAD        				= 2'd1;
    localparam EXECUTE     				= 2'd2;
    localparam DONE  					= 2'd3;
					
	// For BRAM				
	localparam MATRIX_A	   				= 1'b0;
	localparam VECTOR_X	   				= 1'b1;
	
    //-------------------------------------//
    //           Wire Signals              //
    //-------------------------------------//
    wire [DATA_WIDTH-1:0] 				A_w [0:7];
    wire [DATA_WIDTH-1:0] 				X_w [0:7];
    wire [DATA_WIDTH-1:0] 				Y_out_w;
    wire 								Y_valid_w;

    wire 								A_BRAM_ena_w, X_BRAM_ena_w, Y_BRAM_ena_w;
	wire 								A_BRAM_enb_w, X_BRAM_enb_w;
	wire								Y_BRAM_enb_w[0:7];
	
	wire 								A_BRAM_wea_w, X_BRAM_wea_w, Y_BRAM_wea_w;
	wire 								A_BRAM_web_w, X_BRAM_web_w;
	wire								Y_BRAM_web_w[0:7];
	
	wire [DATA_WIDTH-1:0]				Y_BRAM_dinb_w[0:7];
	
	wire [13:0] 						Col_Idx_w;
	
	wire								Complete_flag_w, Done_flag_w;
	
    //-------------------------------------//
    //            Reg Signals              //
    //-------------------------------------//
	
	
	reg [W_ADDR_WIDTH-2:0]				A_BRAM_addrb_r, X_BRAM_addrb_r, Y_BRAM_addrb_r;

	reg	[2:0]							Y_dinb_count_r;
	
    reg [13:0] 							Col_Idx_r;
	reg [13:0] 							Row_Idx_r;

    reg [13:0] 							Max_Col_Idx_r;
	reg [13:0] 							Max_Row_Idx_r;
	
    reg 								A_valid_r;
    reg 								X_valid_r;
    reg 								First_Row_r;
    reg 								Last_Row_r;
		
    reg [1:0] 							state_r, next_state_r;
	
    //-------------------------------------//
    //        Instantiate PMAU Core        //
    //-------------------------------------//
    PMAU #(.DATA_WIDTH(DATA_WIDTH)) pmau_inst (
        .CLK(CLK),
        .RST(RST),
        .First_Row(First_Row_r),
        .A_valid(A_valid_r),
        .X_valid(X_valid_r),
        .Last_Row(Last_Row_r),
        .A0_in(A_w[0]), .A1_in(A_w[1]), .A2_in(A_w[2]), .A3_in(A_w[3]),
        .A4_in(A_w[4]), .A5_in(A_w[5]), .A6_in(A_w[6]), .A7_in(A_w[7]),
        .X0_in(X_w[0]), .X1_in(X_w[1]), .X2_in(X_w[2]), .X3_in(X_w[3]),
        .X4_in(X_w[4]), .X5_in(X_w[5]), .X6_in(X_w[6]), .X7_in(X_w[7]),
        .Y_out(Y_out_w),
        .Y_valid(Y_valid_w)
    );

    //-------------------------------------//
    //         Instantiate BRAMs           //
    //-------------------------------------//
    genvar i;
	
	assign A_BRAM_ena_w		= (W_Valid_in && (W_Addr_in[W_ADDR_WIDTH-1:W_ADDR_WIDTH-1] == MATRIX_A)) ? W_Valid_in: 0;
	assign X_BRAM_ena_w		= (W_Valid_in && (W_Addr_in[W_ADDR_WIDTH-1:W_ADDR_WIDTH-1] == VECTOR_X)) ? W_Valid_in: 0;	
	assign Y_BRAM_ena_w		= R_Valid_in;

	assign A_BRAM_wea_w		= (W_Valid_in && (W_Addr_in[W_ADDR_WIDTH-1:W_ADDR_WIDTH-1] == MATRIX_A)) ? W_Valid_in: 0;
	assign X_BRAM_wea_w		= (W_Valid_in && (W_Addr_in[W_ADDR_WIDTH-1:W_ADDR_WIDTH-1] == VECTOR_X)) ? W_Valid_in: 0;	
	assign Y_BRAM_wea_w		= 0;	
	
	assign A_BRAM_enb_w		= (state_r == EXECUTE) ? 1: 0;
	assign X_BRAM_enb_w		= (state_r == EXECUTE) ? 1: 0;
	
	assign Y_BRAM_enb_w[0]	= (state_r == EXECUTE && Y_dinb_count_r == 0) ? Y_valid_w: 0;
	assign Y_BRAM_enb_w[1]	= (state_r == EXECUTE && Y_dinb_count_r == 1) ? Y_valid_w: 0;
	assign Y_BRAM_enb_w[2]	= (state_r == EXECUTE && Y_dinb_count_r == 2) ? Y_valid_w: 0;
	assign Y_BRAM_enb_w[3]	= (state_r == EXECUTE && Y_dinb_count_r == 3) ? Y_valid_w: 0;
	assign Y_BRAM_enb_w[4]	= (state_r == EXECUTE && Y_dinb_count_r == 4) ? Y_valid_w: 0;
	assign Y_BRAM_enb_w[5]	= (state_r == EXECUTE && Y_dinb_count_r == 5) ? Y_valid_w: 0;
	assign Y_BRAM_enb_w[6]	= (state_r == EXECUTE && Y_dinb_count_r == 6) ? Y_valid_w: 0;
	assign Y_BRAM_enb_w[7]	= (state_r == EXECUTE && Y_dinb_count_r == 7) ? Y_valid_w: 0;
	
	assign A_BRAM_web_w		= 0;
	assign X_BRAM_web_w		= 0;
	
	assign Y_BRAM_web_w[0]  = Y_BRAM_enb_w[0];
	assign Y_BRAM_web_w[1]  = Y_BRAM_enb_w[1];
	assign Y_BRAM_web_w[2]  = Y_BRAM_enb_w[2];
	assign Y_BRAM_web_w[3]  = Y_BRAM_enb_w[3];
	assign Y_BRAM_web_w[4]  = Y_BRAM_enb_w[4];
	assign Y_BRAM_web_w[5]  = Y_BRAM_enb_w[5];
	assign Y_BRAM_web_w[6]  = Y_BRAM_enb_w[6];
	assign Y_BRAM_web_w[7]  = Y_BRAM_enb_w[7];

	assign Y_BRAM_dinb_w[0]  = (Y_BRAM_enb_w[0]) ? Y_out_w: 0;
	assign Y_BRAM_dinb_w[1]  = (Y_BRAM_enb_w[1]) ? Y_out_w: 0;
	assign Y_BRAM_dinb_w[2]  = (Y_BRAM_enb_w[2]) ? Y_out_w: 0;
	assign Y_BRAM_dinb_w[3]  = (Y_BRAM_enb_w[3]) ? Y_out_w: 0;
	assign Y_BRAM_dinb_w[4]  = (Y_BRAM_enb_w[4]) ? Y_out_w: 0;
	assign Y_BRAM_dinb_w[5]  = (Y_BRAM_enb_w[5]) ? Y_out_w: 0;
	assign Y_BRAM_dinb_w[6]  = (Y_BRAM_enb_w[6]) ? Y_out_w: 0;
	assign Y_BRAM_dinb_w[7]  = (Y_BRAM_enb_w[7]) ? Y_out_w: 0;
	
    generate
        for (i = 0; i < 8; i = i + 1) begin : BRAM_BANK

            Dual_Port_BRAM #(.AWIDTH(R_ADDR_WIDTH), .DWIDTH(DATA_WIDTH)) A_BRAM (
                .clka(CLK),
                .ena(A_BRAM_ena_w),
                .wea(A_BRAM_wea_w),
                .addra(W_Addr_in[W_ADDR_WIDTH-2:0]),
                .dina(W_Data_in[DATA_WIDTH*(8-i)-1:DATA_WIDTH*(7-i)]),
                .douta(),
                .clkb(CLK),
                .enb(A_BRAM_enb_w),
                .web(A_BRAM_web_w),
                .addrb(A_BRAM_addrb_r),
                .dinb(0),
                .doutb(A_w[i])
            );

            Dual_Port_BRAM #(.AWIDTH(R_ADDR_WIDTH), .DWIDTH(DATA_WIDTH)) X_BRAM (
                .clka(CLK),
                .ena(X_BRAM_ena_w),
                .wea(X_BRAM_wea_w),
                .addra(W_Addr_in[W_ADDR_WIDTH-2:0]),
                .dina(W_Data_in[DATA_WIDTH*(8-i)-1:DATA_WIDTH*(7-i)]),
                .douta(),
                .clkb(CLK),
                .enb(X_BRAM_enb_w),
                .web(X_BRAM_web_w),
                .addrb(X_BRAM_addrb_r),
                .dinb(0),
                .doutb(X_w[i])
            );
			
			Dual_Port_BRAM #(.AWIDTH(R_ADDR_WIDTH), .DWIDTH(DATA_WIDTH)) Y_BRAM (
                .clka(CLK),
                .ena(Y_BRAM_ena_w),
                .wea(Y_BRAM_wea_w),
                .addra(R_Addr_in),
                .dina(),
                .douta(R_Data_out[DATA_WIDTH*(8-i)-1:DATA_WIDTH*(7-i)]),
                .clkb(CLK),
                .enb(Y_BRAM_enb_w[i]),
                .web(Y_BRAM_web_w[i]),
                .addrb(Y_BRAM_addrb_r),
                .dinb(Y_BRAM_dinb_w[i]),
                .doutb()
            );
        end
    endgenerate

    //-------------------------------------//
    //       Finite State Machine          //
    //-------------------------------------//
    always @(posedge CLK or negedge RST)
        if (!RST) state_r <= IDLE;
        else      state_r <= next_state_r;

    always @(*) begin
        case (state_r)
            IDLE:        next_state_r = Load_in ? LOAD : IDLE;
            LOAD:        next_state_r = Start_in? EXECUTE: LOAD;
            EXECUTE:     next_state_r = (Done_flag_w) ? DONE : EXECUTE;
            DONE:  		 next_state_r = (Complete_flag_w) ? IDLE : LOAD;
            default:     next_state_r = IDLE;
        endcase
    end
	
    //-------------------------------------//
    //          Control Logic              //
    //-------------------------------------//
	
	assign Col_Idx_w		= (A_valid_r) ? Col_Idx_r + 8: 8;

	assign Complete_flag_w	= ((state_r == DONE) && (Row_Idx_r > Max_Row_Idx_r)) ? 1 : 0;
	assign Done_flag_w		= ((state_r == EXECUTE) && ((A_BRAM_addrb_r == 11'h7FF) || ((Row_Idx_r > Max_Row_Idx_r) && Y_valid_w && Y_dinb_count_r == 7))) ? Y_valid_w : 0;
	
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            A_BRAM_addrb_r	<= 0;
			X_BRAM_addrb_r	<= 0;
			Y_BRAM_addrb_r	<= 0;
			
			Y_dinb_count_r	<= 0;
			
			Col_Idx_r		<= 0;
			Row_Idx_r		<= 0;

			Max_Col_Idx_r	<= 0;
			Max_Row_Idx_r	<= 0;
			
            A_valid_r     	<= 0;
            X_valid_r     	<= 0;
            First_Row_r   	<= 0;
            Last_Row_r    	<= 0;
						
            Done_out      	<= 0;
        end 
		else begin
            case (state_r)
                IDLE: begin
					A_BRAM_addrb_r	<= 0;
					X_BRAM_addrb_r	<= 0;
					Y_BRAM_addrb_r	<= 0;

					Y_dinb_count_r	<= 0;
					
					Col_Idx_r		<= 0;
					Row_Idx_r		<= 0;

					Max_Col_Idx_r	<= 0;
					Max_Row_Idx_r	<= 0;
					
					A_valid_r     	<= 0;
					X_valid_r     	<= 0;
					First_Row_r   	<= 0;
					Last_Row_r    	<= 0;
					
					Done_out      	<= Done_out;
                end
                LOAD: begin
					A_BRAM_addrb_r	<= 0;
					X_BRAM_addrb_r	<= 0;
					Y_BRAM_addrb_r	<= Y_BRAM_addrb_r;

					Y_dinb_count_r	<= 0;
					
					Col_Idx_r		<= 0;
					Row_Idx_r		<= Row_Idx_r;
					
					if(n_in == 14) begin
						Max_Col_Idx_r	<= 14'h3FFF;
						Max_Row_Idx_r	<= 14'h3FFF;
					end
					else begin
						Max_Col_Idx_r	<= (1 << n_in) - 1;
						Max_Row_Idx_r	<= (1 << n_in) - 1;
					end
					
					A_valid_r     	<= 0;
					X_valid_r     	<= 0;
					First_Row_r   	<= 0;
					Last_Row_r    	<= 0;
					
					Done_out      	<= Done_out;
                end
                EXECUTE: begin				
					A_valid_r     	<= A_BRAM_enb_w;
					X_valid_r     	<= X_BRAM_enb_w;
					
					if(A_BRAM_addrb_r == 11'h7FF)	
						A_BRAM_addrb_r	<= A_BRAM_addrb_r;
					else
						A_BRAM_addrb_r	<= A_BRAM_addrb_r + A_BRAM_enb_w;
						
					if(Col_Idx_w > Max_Col_Idx_r)
						X_BRAM_addrb_r	<= 0;
					else
						X_BRAM_addrb_r	<= X_BRAM_addrb_r + X_BRAM_enb_w;
						
					Y_BRAM_addrb_r	<= Y_BRAM_addrb_r + Y_BRAM_enb_w[7];
					
						
					Y_dinb_count_r	<= Y_dinb_count_r + Y_valid_w;
					
					if(Col_Idx_w > Max_Col_Idx_r)
						Col_Idx_r	<= 0;
					else 
						Col_Idx_r	<= Col_Idx_w;
					
					if(Col_Idx_w >= Max_Col_Idx_r)					
						Row_Idx_r	<= Row_Idx_r + 1;
					else 
						Row_Idx_r	<= Row_Idx_r;
						
					Max_Col_Idx_r	<= Max_Col_Idx_r;
					Max_Row_Idx_r	<= Max_Row_Idx_r;
					
					A_valid_r     	<= 1;
					X_valid_r     	<= 1;
					
					if(Col_Idx_r == 0)
						First_Row_r   	<= 1;
					else 
						First_Row_r   	<= 0;
					
					if(Col_Idx_w > Max_Col_Idx_r)					
						Last_Row_r    	<= 1;
					else 
						Last_Row_r    	<= 0;
						
					Done_out      	<= 0;
                end
                DONE: begin

					A_BRAM_addrb_r	<= 0;
					X_BRAM_addrb_r	<= 0;
					Y_BRAM_addrb_r	<= Y_BRAM_addrb_r;

					Y_dinb_count_r	<= 0;
									
					Col_Idx_r		<= 0;
					Row_Idx_r		<= Row_Idx_r;

					Max_Col_Idx_r	<= Max_Col_Idx_r;
					Max_Row_Idx_r	<= Max_Row_Idx_r;
					
					A_valid_r     	<= 0;
					X_valid_r     	<= 0;
					First_Row_r   	<= 0;
					Last_Row_r    	<= 0;
					
					Done_out      	<= 1;
                end
            endcase
        end
    end

endmodule
