`timescale 1ns/1ps

module PMAU_tb;

    parameter DATA_WIDTH = 16;

    reg                        CLK;
    reg                        RST;
    reg                        First_Row;
    reg                        A_valid;
    reg                        X_valid;
    reg                        Last_Row;

    reg  [DATA_WIDTH-1:0]      A [7:0];
    reg  [DATA_WIDTH-1:0]      X [7:0];

    wire [DATA_WIDTH-1:0]      Y_out;
    wire                       Y_valid;

    // Instantiate DUT
    PMAU #(.DATA_WIDTH(DATA_WIDTH)) uut (
        .CLK(CLK),
        .RST(RST),
        .First_Row(First_Row),
        .A_valid(A_valid),
        .X_valid(X_valid),
        .Last_Row(Last_Row),
        .A0_in(A[0]), .A1_in(A[1]), .A2_in(A[2]), .A3_in(A[3]),
        .A4_in(A[4]), .A5_in(A[5]), .A6_in(A[6]), .A7_in(A[7]),
        .X0_in(X[0]), .X1_in(X[1]), .X2_in(X[2]), .X3_in(X[3]),
        .X4_in(X[4]), .X5_in(X[5]), .X6_in(X[6]), .X7_in(X[7]),
        .Y_out(Y_out),
        .Y_valid(Y_valid)
    );

    // Clock generation
    initial CLK = 0;
    always #5 CLK = ~CLK;

    // Test patterns
    integer pat_a [0:7][0:7];
    integer pat_x [0:7][0:7];

    integer acc, row_sum;
    integer i, j;

    initial begin
        // Generate patterns: values from {-1, 0, 1}
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                pat_a[i][j] = ($unsigned($random) % 3) - 1;
                pat_x[i][j] = ($unsigned($random) % 3) - 1;
				// pat_a[i][j] = 1;
                // pat_x[i][j] = 1;
            end

        // Initialization
        RST = 0;
        A_valid = 0; X_valid = 0; First_Row = 0; Last_Row = 0;
        acc = 0;
		for (j = 0; j < 8; j = j + 1) begin
          A[j] = 0;
          X[j] = 0;
        end
        #35 RST = 1;

        // Loop through 8 patterns
        for (i = 0; i < 8; i = i + 1) begin
            // Prepare data
			row_sum = 0;
			#10;
            for (j = 0; j < 8; j = j + 1) begin
                A[j] = pat_a[i][j];
                X[j] = pat_x[i][j];
				row_sum = row_sum + pat_a[i][j] * pat_x[i][j];
            end
            // Activate valid + First_Row on first cycle only
            A_valid = 1;
            X_valid = 1;
            First_Row = (i == 0);
            Last_Row = (i == 7);

            // Compute expected result
            acc = (i == 0) ? row_sum : acc + row_sum;
        end
            #10;
			for (j = 0; j < 8; j = j + 1) begin
                A[j] = 0;
                X[j] = 0;
            end
            A_valid = 0;
            X_valid = 0;
            First_Row = 0;
            Last_Row = 0;
			wait (Y_valid == 1);
			
			// Result
			$display("--------------------------------------------------");
			$display("Expected Accumulated Y_out = %0d", acc);
			$display("Output from DUT Y_out      = %0d", Y_out);
			$display("Y_valid                    = %b", Y_valid);
			$display("--------------------------------------------------");


        if (Y_out === acc && Y_valid)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");

        $finish;
    end

endmodule
