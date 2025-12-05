set datafile separator ','
set xlabel '# Concurrent Proofs'
set ylabel 'Total Execution Time (s)'
set title 'Average Execution Time Mint'
set grid
set key top left

plot 'data.csv' using 1:2 with points pt 7 ps 2 title 'Values'

set terminal push
set terminal pngcairo
set output 'results.png'

replot
set output
set terminal pop