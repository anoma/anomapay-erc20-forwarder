set datafile separator ','
set xlabel '# Concurrent Proofs'
set ylabel 'Total Execution Time (s)'
set title 'Average Execution Time Mint'
set grid
set key top left

plot 'non_aggregate.csv' using 1:2 with points pt 7 ps 2 title 'Non-Aggregate Proofs (non_aggregate.csv)', 'aggregate.csv' using 1:2 with points pt 7 ps 2 title 'Aggregate Proofs (aggregate.csv)', 'data.csv' using 1:2 with points pt 7 ps 2 title 'Proofs (data.csv)'

set terminal push
set terminal pngcairo
set output 'results.png'

replot
set output
set terminal pop