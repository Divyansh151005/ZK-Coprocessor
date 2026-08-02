fn main() {
    // Compile the RISC-V guest ELF via the succinct toolchain (Milestone A).
    sp1_build::build_program(&format!("{}/../guest", env!("CARGO_MANIFEST_DIR")));
}
