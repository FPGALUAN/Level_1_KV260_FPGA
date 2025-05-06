/*-----------------------------------------------------------------------------
 * File          : PMAU.v
 * Author        : PHAM HOAI LUAN
 * Created       : 05.05.2025
 * Last modified : 05.05.2025
 *-----------------------------------------------------------------------------
 * Description   : Parallel Multiply-Add Unit (PMAU) for 8-lane matrix-vector
 *                 multiplication. Designed for integration with external BRAMs
 *                 holding matrix A, vector X, and result vector Y.
 *                 Accumulator supports clear signal First_Row.
 *                 All inputs are fixed-point 16-bit: 1 sign bit, 15 integer bits.
 *-----------------------------------------------------------------------------
 */

module PMAU #(parameter DATA_WIDTH = 16) (
    input  wire                        CLK,
    input  wire                        RST,
    input  wire                        First_Row,
    input  wire                        A_valid,
    input  wire                        X_valid,
    input  wire                        Last_Row,

    input  wire [DATA_WIDTH-1:0]      A0_in,
    input  wire [DATA_WIDTH-1:0]      A1_in,
    input  wire [DATA_WIDTH-1:0]      A2_in,
    input  wire [DATA_WIDTH-1:0]      A3_in,
    input  wire [DATA_WIDTH-1:0]      A4_in,
    input  wire [DATA_WIDTH-1:0]      A5_in,
    input  wire [DATA_WIDTH-1:0]      A6_in,
    input  wire [DATA_WIDTH-1:0]      A7_in,

    input  wire [DATA_WIDTH-1:0]      X0_in,
    input  wire [DATA_WIDTH-1:0]      X1_in,
    input  wire [DATA_WIDTH-1:0]      X2_in,
    input  wire [DATA_WIDTH-1:0]      X3_in,
    input  wire [DATA_WIDTH-1:0]      X4_in,
    input  wire [DATA_WIDTH-1:0]      X5_in,
    input  wire [DATA_WIDTH-1:0]      X6_in,
    input  wire [DATA_WIDTH-1:0]      X7_in,

    output wire [DATA_WIDTH-1:0]      Y_out,
    output wire                       Y_valid
);

    //-------------------------------------//
    //            Reg Signals              //
    //-------------------------------------//

    reg  [31:0] mult_r [7:0];
    reg  [15:0] accumulator_r;

    reg         A_valid_r, X_valid_r, Last_Row_r;
    reg         acc_first_r;

    //-------------------------------------//
    //           Wire Signals              //
    //-------------------------------------//

    wire [15:0] mult_trunc_w [7:0];
    wire [15:0] sum_lvl1_w [3:0];
    wire [15:0] sum_lvl2_w [1:0];
    wire [15:0] sum_final_w;

    //-------------------------------------//
    //        Input Delay Registers        //
    //-------------------------------------//

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            A_valid_r    <= 0;
            X_valid_r    <= 0;
            Last_Row_r   <= 0;
            acc_first_r  <= 0;
        end else begin
            A_valid_r    <= A_valid;
            X_valid_r    <= X_valid;
            Last_Row_r   <= Last_Row;
            acc_first_r  <= (A_valid && X_valid && First_Row); // latch once at the first row
        end
    end

    //-------------------------------------//
    //        Stage 1: Multiply            //
    //-------------------------------------//

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            mult_r[0] <= 0; mult_r[1] <= 0; mult_r[2] <= 0; mult_r[3] <= 0;
            mult_r[4] <= 0; mult_r[5] <= 0; mult_r[6] <= 0; mult_r[7] <= 0;
        end else if (A_valid && X_valid) begin
            mult_r[0] <= $signed(A0_in) * $signed(X0_in);
            mult_r[1] <= $signed(A1_in) * $signed(X1_in);
            mult_r[2] <= $signed(A2_in) * $signed(X2_in);
            mult_r[3] <= $signed(A3_in) * $signed(X3_in);
            mult_r[4] <= $signed(A4_in) * $signed(X4_in);
            mult_r[5] <= $signed(A5_in) * $signed(X5_in);
            mult_r[6] <= $signed(A6_in) * $signed(X6_in);
            mult_r[7] <= $signed(A7_in) * $signed(X7_in);
        end
    end

    //-------------------------------------//
    //        Stage 2: Add Tree            //
    //-------------------------------------//

    assign mult_trunc_w[0] = mult_r[0][15:0];
    assign mult_trunc_w[1] = mult_r[1][15:0];
    assign mult_trunc_w[2] = mult_r[2][15:0];
    assign mult_trunc_w[3] = mult_r[3][15:0];
    assign mult_trunc_w[4] = mult_r[4][15:0];
    assign mult_trunc_w[5] = mult_r[5][15:0];
    assign mult_trunc_w[6] = mult_r[6][15:0];
    assign mult_trunc_w[7] = mult_r[7][15:0];

    assign sum_lvl1_w[0] = mult_trunc_w[0] + mult_trunc_w[1];
    assign sum_lvl1_w[1] = mult_trunc_w[2] + mult_trunc_w[3];
    assign sum_lvl1_w[2] = mult_trunc_w[4] + mult_trunc_w[5];
    assign sum_lvl1_w[3] = mult_trunc_w[6] + mult_trunc_w[7];

    assign sum_lvl2_w[0] = sum_lvl1_w[0] + sum_lvl1_w[1];
    assign sum_lvl2_w[1] = sum_lvl1_w[2] + sum_lvl1_w[3];

    assign sum_final_w = sum_lvl2_w[0] + sum_lvl2_w[1];

    //-------------------------------------//
    //             Accumulator             //
    //-------------------------------------//

    always @(posedge CLK or negedge RST) begin
        if (!RST)
            accumulator_r <= 0;
        else begin
			if (A_valid_r && X_valid_r) begin
				if (acc_first_r)
					accumulator_r <= {{16{sum_final_w[15]}}, sum_final_w };
				else
					accumulator_r <= accumulator_r + { {16{sum_final_w[15]}}, sum_final_w};
			end
			else begin
				accumulator_r <= 0;
			end
		end
    end
    //-------------------------------------//
    //           	 Output    		       //
    //-------------------------------------//
    assign Y_out 	= (Y_valid && !acc_first_r) ? $signed(accumulator_r + { {16{sum_final_w[15]}}, sum_final_w}) :(Y_valid && acc_first_r) ? {{16{sum_final_w[15]}}, sum_final_w }: 16'sd0;
	assign Y_valid  = (A_valid_r && X_valid_r && Last_Row_r);

endmodule
