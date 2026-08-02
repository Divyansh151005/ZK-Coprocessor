fn main() {
    let manifest = env!("CARGO_MANIFEST_DIR");
    // Phase 0 add guest (SPN / local Groth16 E2E)
    sp1_build::build_program(&format!("{manifest}/../guest"));
    // Milestone C MPT guest
    sp1_build::build_program(&format!("{manifest}/../guest-mpt"));
}
