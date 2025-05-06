onbreak {quit -force}
onerror {quit -force}

asim +access +r +m+ila_debug  -L xpm -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.ila_debug xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure

do {ila_debug.udo}

run 1000ns

endsim

quit -force
