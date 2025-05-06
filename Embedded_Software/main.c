// Created by: PHAM HOAI LUAN
// Created on: 2025-05-06
// Description: This file is used to test the FPGA driver by sending data to the FPGA and receiving the result back from the FPGA.


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>


#include <fcntl.h>
#include <stdint.h>
#include <math.h>

#include "./FPGA_Driver.c" // call fpga driver


#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

/// Address in Write Channel
#define LOAD_BASE_PHYS		 		(0x00000000 >> 2)					
#define START_BASE_PHYS		 		(0x00000010 >> 2)
#define N_BASE_PHYS	 		 		(0x00000020 >> 2)

#define MATRIX_A_BASE_PHYS	 		(0x01000000)  
#define VECTOR_X_BASE_PHYS	 		(0x02000000) 	
					
/// Address in Read Channel                
#define DONE_BASE_PHYS	 		 	(0x00000000 >> 2)
#define VECTOR_Y_BASE_PHYS	 		(0x03000000)  


#define MATRIX_A_PATH         		"Matrix_A.txt"
#define VECTOR_X_PATH         		"Vector_X.txt"
#define N_PATH                		"n.txt"
#define VECTOR_Y_OUTPUT_PATH  		"Vector_Y_Result_FPGA.txt"

typedef uint16_t U16;

int main() {
    unsigned char* membase;
    if (fpga_open() == 0) {
        perror("Failed to open FPGA");
        return 1;
    }

    fpga.dma_ctrl = MY_IP_info.dma_mmap;
    membase = (unsigned char*)MY_IP_info.ddr_mmap;

    U16* A = (U16*)(membase + MATRIX_A_BASE_PHYS);
    U16* X = (U16*)(membase + VECTOR_X_BASE_PHYS);
    U16* Y = (U16*)(membase + VECTOR_Y_BASE_PHYS);

    // Read n
    int n, size, WS1, WS2;
    FILE* f_n = fopen(N_PATH, "r");
    if (!f_n) {
        perror("Failed to open n.txt");
        return 1;
    }
    fscanf(f_n, "%d", &n);
    fclose(f_n);

    size = 1 << n;
    if (n <= 7) {
        WS1 = 1;
        WS2 = size;
    } else {
        WS1 = 1 << ((n + n) - 14);
        WS2 = 1 << (14 - n);
    }
    // Send LOAD signal
    *(MY_IP_info.pio_32_mmap + LOAD_BASE_PHYS) = 1;
	// Set N
    *(MY_IP_info.pio_32_mmap + N_BASE_PHYS) = n;

    // Read vector X
    FILE* f_vector = fopen(VECTOR_X_PATH, "r");
    if (!f_vector) {
        perror("Failed to open Vector_X.txt");
        return 1;
    }
    for (int i = 0; i < size; i++) {
        fscanf(f_vector, "%hu", &X[i]);
    }
    fclose(f_vector);

    // Send vector X via DMA
    printf("Writing Vector X to DDR via DMA...\n");
    dma_write(VECTOR_X_BASE_PHYS, size);




    // Read matrix A in batches and compute each batch
    FILE* f_matrix = fopen(MATRIX_A_PATH, "r");
    if (!f_matrix) {
        perror("Failed to open Matrix_A.txt");
        return 1;
    }

    U16* A_buf = (U16*)malloc(sizeof(U16) * WS2 * size);
    if (!A_buf) {
        perror("Memory allocation failed for A_buf");
        fclose(f_matrix);
        return 1;
    }

    for (int h = 0; h < WS1; h++) {
        printf("Batch %d/%d: Loading Matrix A to DDR...\n", h + 1, WS1);
        for (int i = 0; i < WS2 * size; i++) {
            fscanf(f_matrix, "%hu", &A_buf[i]);
            A[i] = A_buf[i];  // store to mapped DDR memory
        }

        dma_write(MATRIX_A_BASE_PHYS, WS2 * size);

        // Start computation
        *(MY_IP_info.pio_32_mmap + START_BASE_PHYS) = 1;

        // Wait for done flag
        while (1){
			if(*(MY_IP_info.pio_32_mmap + DONE_BASE_PHYS) == 1){
				printf("Batch %d done.\n", h + 1);
				break;
			}
		}

        
    }
	
	dma_read(VECTOR_Y_BASE_PHYS, size);
	
    fclose(f_matrix);
    free(A_buf);

    // Save result vector Y
    FILE* f_output = fopen(VECTOR_Y_OUTPUT_PATH, "w");
    if (!f_output) {
        perror("Failed to open Vector_Y_Result.txt");
        return 1;
    }

    for (int i = 0; i < size; i++) {
        fprintf(f_output, "%hd\n", Y[i]);
    }
    fclose(f_output);

    printf("Computation completed! Results written to %s\n", VECTOR_Y_OUTPUT_PATH);
    return 0;
}