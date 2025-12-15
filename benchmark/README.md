# Benchmarking

The benchmark test is meant to measure how long it takes to generate proofs on
the GPU cluster.

A single test generated a minting transaction which requires 2 logic proofs and
1 compliance proof. Running with `CONCURRENCY=1` thus means 3 concurrent proofs.

## Run

To run the benchmark, execute the following.

```bash
CONCURRENCY=1 cargo test benchmark_mint -- --show-output --ignored
```

There is a script located at `benchmark/run.sh` that will run the benchmark for
0, 10, .. 100 and write the results into `benchmark/data.csv`. Generate a graph
with `benchmark/gnuplot -p plot.gp`.
