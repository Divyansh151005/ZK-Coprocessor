//! Milestone C guest: verify Ethereum account + storage MPT proofs in-circuit.
//!
//! Stdin (host order):
//! 1. `state_root: [u8; 32]`
//! 2. `address: [u8; 20]`
//! 3. `storage_slot: [u8; 32]`      (raw slot; hashed in-circuit)
//! 4. `account_rlp: Vec<u8>`        (leaf account value from eth_getProof)
//! 5. `account_proof: Vec<Vec<u8>>`  (RLP nodes)
//! 6. `storage_proof: Vec<Vec<u8>>`  (RLP nodes)
//! 7. `storage_value: [u8; 32]`     (32-byte big-endian slot value)
//!
//! Commits [`StorageProofPublicValues`] on success; panics on bad proofs.

#![no_main]
sp1_zkvm::entrypoint!(main);

use alloy_primitives::{keccak256, Address, Bytes, B256, U256};
use alloy_rlp::{Decodable, Header};
use alloy_sol_types::SolType;
use alloy_trie::{proof::verify_proof, Nibbles};
use zk_coprocessor_lib::StorageProofPublicValues;

#[derive(Debug)]
struct EthAccount {
    storage_root: B256,
}

impl Decodable for EthAccount {
    fn decode(buf: &mut &[u8]) -> alloy_rlp::Result<Self> {
        let mut payload = Header::decode_bytes(buf, true)?;
        let _nonce = U256::decode(&mut payload)?;
        let _balance = U256::decode(&mut payload)?;
        let storage_root = B256::decode(&mut payload)?;
        let _code_hash = B256::decode(&mut payload)?;
        Ok(Self { storage_root })
    }
}

fn nodes_as_bytes(nodes: &[Vec<u8>]) -> Vec<Bytes> {
    nodes.iter().map(|n| Bytes::copy_from_slice(n)).collect()
}

/// RLP-encode a 32-byte storage value the same way geth leaves do (minimal bytes).
fn encode_storage_leaf_value(value: B256) -> Vec<u8> {
    let u = U256::from_be_bytes(value.into());
    alloy_rlp::encode(u)
}

pub fn main() {
    let state_root = B256::from(sp1_zkvm::io::read::<[u8; 32]>());
    let address = Address::from(sp1_zkvm::io::read::<[u8; 20]>());
    let storage_slot = B256::from(sp1_zkvm::io::read::<[u8; 32]>());
    let account_rlp = sp1_zkvm::io::read::<Vec<u8>>();
    let account_proof = sp1_zkvm::io::read::<Vec<Vec<u8>>>();
    let storage_proof = sp1_zkvm::io::read::<Vec<Vec<u8>>>();
    let storage_value = B256::from(sp1_zkvm::io::read::<[u8; 32]>());

    // 1) Account inclusion under state root
    let acct_key = Nibbles::unpack(keccak256(address));
    let acct_nodes = nodes_as_bytes(&account_proof);
    verify_proof(
        state_root,
        acct_key,
        Some(account_rlp.clone()),
        acct_nodes.iter(),
    )
    .expect("account MPT proof invalid");

    let mut acct_buf: &[u8] = &account_rlp;
    let account = EthAccount::decode(&mut acct_buf).expect("account RLP decode failed");

    // 2) Storage inclusion under account storage root
    let slot_key = Nibbles::unpack(keccak256(storage_slot));
    let stor_nodes = nodes_as_bytes(&storage_proof);
    let expected_leaf = encode_storage_leaf_value(storage_value);
    // Empty storage may be exclusion (None) or empty RLP string — handle zero specially.
    let expected = if storage_value == B256::ZERO {
        // Zero can be missing key (exclusion) or explicit zero; try inclusion of empty/0 first.
        Some(expected_leaf.clone())
    } else {
        Some(expected_leaf)
    };

    if let Err(_) = verify_proof(
        account.storage_root,
        slot_key.clone(),
        expected.clone(),
        stor_nodes.iter(),
    ) {
        // Fallback: exclusion proof for zero value
        assert_eq!(
            storage_value,
            B256::ZERO,
            "storage MPT proof invalid for non-zero value"
        );
        verify_proof(account.storage_root, slot_key, None, stor_nodes.iter())
            .expect("storage exclusion proof invalid");
    }

    let journal = StorageProofPublicValues {
        stateRoot: state_root.0.into(),
        account: address.0.into(),
        slot: storage_slot.0.into(),
        value: storage_value.0.into(),
    };
    let bytes = StorageProofPublicValues::abi_encode(&journal);
    sp1_zkvm::io::commit_slice(&bytes);
}
