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

ci-test:
    printenv
    RUST_BACKTRACE=full cargo test -- --test-threads=1 --show-output
    # cargo test versions_of_deployed_forwarders_point_to_the_current_protocol_adapter_contract

check:
    cargo check

taplo:
    taplo fmt

taplo-check:
    taplo fmt --check