gcc main.c -I. -o main
./main
# Define file paths
file1="Vector_Y_Result.txt"
file2="Vector_Y_Result_FPGA.txt"

# Check if both files exist
if [ ! -e "$file1" ] || [ ! -e "$file2" ]; then
    echo "One or both files do not exist."
    exit 1
fi

# Count the number of differences
diff_count=$(diff -U 0 $file1 $file2 | grep -v "^@" | wc -l)

# Check if files are the same
if [ $diff_count -eq 0 ]; then
    echo "Two files are the same, the accuracy is 100%"
else
    echo "There are $diff_count differences."
fi
rm -f main
