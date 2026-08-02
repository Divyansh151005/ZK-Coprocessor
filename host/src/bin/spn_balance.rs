//! Print Succinct Prover Network (SPN) escrow balance for the requester in `.env`.
//!
//! Uses `sp1_sdk` blocking `NetworkProver::get_balance()` — does **not** deposit
//! (deposits are on-chain via Explorer / SuccinctVApp). See `NOTES/MILESTONE_AB_SP1.md`.
//!
//! ```bash
//! cargo run -p zk-coprocessor-host --release --bin spn-balance
//! ./target/release/spn-balance --min 1   # exit 1 if below 1 PROVE (CI gate)
//! ```

use std::cmp::Ordering;

use clap::Parser;
use sp1_sdk::{blocking::ProverClient, network::NetworkMode};

/// 18-decimal PROVE token scale.
const PROVE_DECIMALS: usize = 18;

#[derive(Parser, Debug)]
#[command(
    name = "spn-balance",
    about = "Query SPN escrow PROVE balance for NETWORK_PRIVATE_KEY"
)]
struct Args {
    /// Fail with exit code 1 if balance is below this many whole PROVE (integer).
    #[arg(long)]
    min: Option<u64>,
    /// Emit machine-readable JSON on stdout.
    #[arg(long, default_value_t = false)]
    json: bool,
}

fn main() -> eyre::Result<()> {
    let _ = dotenvy::dotenv();
    let args = Args::parse();

    if std::env::var_os("NETWORK_PRIVATE_KEY").is_none() {
        eyre::bail!(
            "NETWORK_PRIVATE_KEY is unset. Copy .env.example → .env and set your requester key."
        );
    }

    let client = ProverClient::builder()
        .network_for(NetworkMode::Mainnet)
        .build();

    let balance = client
        .get_balance()
        .map_err(|e| eyre::eyre!("get_balance failed: {e}"))?;
    let wei = balance.to_string();
    let whole = format_prove(&wei);
    let min_ok = args
        .min
        .map(|m| cmp_dec(&wei, &prove_units(m)) != Ordering::Less);

    if args.json {
        let obj = serde_json::json!({
            "balanceWei": wei,
            "balanceProve": whole,
            "minProve": args.min,
            "minSatisfied": min_ok,
        });
        println!("{}", serde_json::to_string_pretty(&obj)?);
    } else {
        println!("SPN escrow balance: {whole} PROVE ({wei} wei)");
        if let Some(m) = args.min {
            match min_ok {
                Some(true) => println!("min gate: OK (>= {m} PROVE)"),
                Some(false) => println!("min gate: BELOW ({m} PROVE required)"),
                None => {}
            }
        } else {
            println!("Tip: deposit via Explorer Account UI after funding mainnet ETH + PROVE.");
            println!("     Then: PROVE_MODE=sp1 ./scripts/e2e-anvil.sh");
        }
    }

    if matches!(min_ok, Some(false)) {
        std::process::exit(1);
    }
    Ok(())
}

fn prove_units(whole: u64) -> String {
    format!("{whole}{}", "0".repeat(PROVE_DECIMALS))
}

/// Format wei string as PROVE with trimmed fractional digits.
fn format_prove(wei: &str) -> String {
    let digits: String = wei.chars().filter(|c| c.is_ascii_digit()).collect();
    let digits = if digits.is_empty() {
        "0".to_string()
    } else {
        digits
    };
    if digits.len() <= PROVE_DECIMALS {
        let frac = format!("{:0>width$}", digits, width = PROVE_DECIMALS);
        let frac_trim = frac.trim_end_matches('0');
        if frac_trim.is_empty() {
            "0".into()
        } else {
            format!("0.{frac_trim}")
        }
    } else {
        let split = digits.len() - PROVE_DECIMALS;
        let (w, f) = digits.split_at(split);
        let f_trim = f.trim_end_matches('0');
        if f_trim.is_empty() {
            w.to_string()
        } else {
            format!("{w}.{f_trim}")
        }
    }
}

/// Compare two non-negative decimal integer strings.
fn cmp_dec(a: &str, b: &str) -> Ordering {
    let norm = |s: &str| -> String {
        let d: String = s.chars().filter(|c| c.is_ascii_digit()).collect();
        let t = d.trim_start_matches('0');
        if t.is_empty() {
            "0".into()
        } else {
            t.to_string()
        }
    };
    let a = norm(a);
    let b = norm(b);
    match a.len().cmp(&b.len()) {
        Ordering::Equal => a.cmp(&b),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_zero() {
        assert_eq!(format_prove("0"), "0");
    }

    #[test]
    fn format_one_prove() {
        assert_eq!(format_prove(&prove_units(1)), "1");
    }

    #[test]
    fn format_fraction() {
        assert_eq!(format_prove("446700000000000000"), "0.4467");
    }

    #[test]
    fn cmp_min_gate() {
        assert_eq!(cmp_dec("0", &prove_units(1)), Ordering::Less);
        assert_eq!(cmp_dec(&prove_units(1), &prove_units(1)), Ordering::Equal);
        assert_eq!(cmp_dec(&prove_units(2), &prove_units(1)), Ordering::Greater);
    }
}
