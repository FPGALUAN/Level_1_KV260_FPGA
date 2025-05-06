#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#define MAX_N 14

// Generate random value -1, 0, or 1
int16_t random_val() {
    int r = rand() % 3;
    return (r == 0) ? -1 : (r == 1) ? 0 : 1;
}

// Create file if it does not exist
void create_data_if_needed(const char* filename, int size, int is_matrix, int n) {
    FILE* f = fopen(filename, "r");
    if (f) {
        fclose(f);
        printf("File %s exists. KEEPING existing data.\n", filename);
        return;
    }

    f = fopen(filename, "w");
    if (!f) {
        perror("Failed to open file for writing");
        exit(1);
    }

    printf("Creating new file: %s ...\n", filename);
    for (int i = 0; i < size; i++) {
        for (int j = 0; j < (is_matrix ? size : 1); j++) {
			if(size != 1)
				fprintf(f, "%d ", random_val());
			else 
				fprintf(f, "%d ", n);
        }
        fprintf(f, "\n");
    }

    fclose(f);
}

// Read matrix A from file
void read_matrix_file(const char* filename, int16_t** A, int size) {
    FILE* f = fopen(filename, "r");
    if (!f) {
        perror("Failed to open matrix file");
        exit(1);
    }

    for (int i = 0; i < size; i++)
        for (int j = 0; j < size; j++)
            fscanf(f, "%hd", &A[i][j]);

    fclose(f);
}

// Read vector X from file
void read_vector_file(const char* filename, int16_t* X, int size) {
    FILE* f = fopen(filename, "r");
    if (!f) {
        perror("Failed to open vector file");
        exit(1);
    }

    for (int i = 0; i < size; i++)
        fscanf(f, "%hd", &X[i]);

    fclose(f);
}

// Write result vector Y to file
void write_result_file(const char* filename, int16_t* Y, int size) {
    FILE* f = fopen(filename, "w");
    if (!f) {
        perror("Failed to write result file");
        exit(1);
    }

    for (int i = 0; i < size; i++)
        fprintf(f, "%hd\n", Y[i]);

    fclose(f);
}

int main() {
    int n;
    printf("Enter n (max %d): ", MAX_N);
    scanf("%d", &n);

    if (n < 1 || n > MAX_N) {
        printf("Invalid n.\n");
        return 1;
    }

    int size = 1 << n;

    // Allocate memory
    int16_t** A = malloc(size * sizeof(int16_t*));
    for (int i = 0; i < size; i++)
        A[i] = malloc(size * sizeof(int16_t));

    int16_t* X = malloc(size * sizeof(int16_t));
    int16_t* Y = malloc(size * sizeof(int16_t));
    if (!A || !X || !Y) {
        perror("Memory allocation failed");
        exit(1);
    }

    srand(time(NULL));

    create_data_if_needed("Matrix_A.txt", size, 1,n);
    create_data_if_needed("Vector_X.txt", size, 0,n);
	create_data_if_needed("n.txt", 1, 0,n);
	
    read_matrix_file("Matrix_A.txt", A, size);
    read_vector_file("Vector_X.txt", X, size);

    // Compute Y = A × X
    for (int i = 0; i < size; i++) {
        int32_t sum = 0;
        for (int j = 0; j < size; j++) {
            sum += A[i][j] * X[j];
        }
        Y[i] = (int16_t)sum;
    }

    write_result_file("Vector_Y_Result.txt", Y, size);
    printf("Computation completed. Result written to result.txt\n");

    // Free memory
    for (int i = 0; i < size; i++) free(A[i]);
    free(A);
    free(X);
    free(Y);

    return 0;
}
