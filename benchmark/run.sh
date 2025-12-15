#!/bin/bash

# exit if something fails
set -e

# cd to dir of the script to store the dat
cd "$(dirname "$0")" || (echo "cant cd to script dir" ; exit 0)

for i in $(seq 0 10 100); do
  # 5 runs for each concurrency parameter
  for _ in {1..5}; do
    echo "Running with CONCURRENCY=$i"
    # run the benchmark with `i` concurrent mint requests
    # extract the runtime for a single test from the output.
    PROOFS=$(echo "$i * 3" | bc)
    CONCURRENCY=$i cargo test benchmark_mint -- --ignored 2>&1 | \
    grep 'test result: ok. 1 passed' | \
    awk -v vals="${PROOFS}" '{print vals "," $NF}' | tr -d 's' >> data.csv;
  done;
done;

echo "done";

# show the plot
gnuplot -p plot.gp