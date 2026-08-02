//! Print the SP1 program verification key (bytes32) for on-chain registration.

use sp1_sdk::{
    blocking::{Prover, ProverClient},
    include_elf, Elf, HashableKey, ProvingKey,
};

const ELF: Elf = include_elf!("add-guest");

fn main() {
    sp1_sdk::utils::setup_logger();
    let client = ProverClient::from_env();
    let pk = client.setup(ELF).expect("setup");
    println!("{}", pk.verifying_key().bytes32());
}
