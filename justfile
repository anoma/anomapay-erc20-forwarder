help:
    @echo Available commands: `just --summary`

clean:
    cargo clean

fmt *CHECK:
    cargo fmt --all {{ if CHECK == "check" { "-- --check" } else { "" } }}

clippy:
    cargo clippy --tests -- -Dwarnings

clippy-fix:
    cargo clippy --fix --allow-dirty --allow-staged

test:
    cargo test --all --workspace

check:
    cargo check

taplo:
    taplo fmt

taplo-check:
    taplo fmt --check