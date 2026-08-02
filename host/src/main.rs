//! Thin entrypoint documenting Phase 0 host roles.
//! Prefer `prove-mock` + `scripts/e2e-anvil.sh` for the vertical slice.

fn main() {
    eprintln!(
        "zk-coprocessor host: use `cargo run -p zk-coprocessor-host --bin prove-mock -- --a N --b M --vkey 0x...`\n\
         and scripts/e2e-anvil.sh for the Anvil lifecycle."
    );
}
