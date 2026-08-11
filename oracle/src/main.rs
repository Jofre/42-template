//! Reference implementations for live differential testing (grader-side).
//!
//! Usage:  oracle <fn> <seed> <count>   — emit `<hex-inputs>\t<reference>` per case
//!         oracle check                 — run every module's self-checks
//!
//! Std-only, zero dependencies. Each module (cNN.rs) owns its functions'
//! references, generators, a `gen(name, seed, count) -> bool` dispatcher, and a
//! `check() -> usize` self-check. Register new modules in the two lists below.

mod common;

mod bsq;
mod c00;
mod c01;
mod c02;
mod c03;
mod c04;
mod c05;
mod c06;
mod c07;
mod c08;
mod c09;
mod c10;
mod c11;
mod c12;
mod c13;
mod rush00;
mod rush01;
mod rush01_bonus;
mod rush02;

use std::env;
use std::process::exit;

/// Every module's dispatcher, tried in order until one claims the function name.
/// `oracle bench <fn>` — read a corpus on stdin and compute the reference
/// answers, generating and printing nothing. This is the baseline the perf
/// layer times the student against; see c05::bench for why it cannot be `gen`.
/// Returns false for a function with no bench arm yet, so perf falls back to
/// scaling-only rather than reporting a meaningless ratio.
fn dispatch_bench(name: &str) -> bool {
    c00::bench(name)
        || c01::bench(name)
        || c02::bench(name)
        || c03::bench(name)
        || c04::bench(name)
        || c05::bench(name)
        || c07::bench(name)
        || c09::bench(name)
        || c11::bench(name)
        || c12::bench(name)
        || c13::bench(name)
        || rush01::bench(name)
}

fn dispatch(name: &str, seed: u64, count: usize) -> bool {
    c00::gen(name, seed, count)
        || c01::gen(name, seed, count)
        || c02::gen(name, seed, count)
        || c03::gen(name, seed, count)
        || c04::gen(name, seed, count)
        || c05::gen(name, seed, count)
        || c06::gen(name, seed, count)
        || c07::gen(name, seed, count)
        || c08::gen(name, seed, count)
        || c09::gen(name, seed, count)
        || c10::gen(name, seed, count)
        || c11::gen(name, seed, count)
        || c12::gen(name, seed, count)
        || c13::gen(name, seed, count)
        || rush00::gen(name, seed, count)
        || rush02::gen(name, seed, count)
        || rush01::gen(name, seed, count)
        || rush01_bonus::gen(name, seed, count)
        || bsq::gen(name, seed, count)
}

/// Sum of every module's self-check failures.
fn check_all() -> usize {
    c00::check()
        + c01::check()
        + c02::check()
        + c03::check()
        + c04::check()
        + c05::check()
        + c06::check()
        + c07::check()
        + c08::check()
        + c09::check()
        + c10::check()
        + c11::check()
        + c12::check()
        + c13::check()
        + rush00::check()
        + rush01::check()
        + rush02::check()
        + rush01_bonus::check()
        + rush01_bonus::check_rect()
        + bsq::check()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() >= 3 && args[1] == "bench" {
        if dispatch_bench(&args[2]) {
            exit(0);
        }
        eprintln!("oracle bench: no baseline for {}", args[2]);
        exit(2);
    }
    if args.len() >= 2 && args[1] == "check" {
        let fails = check_all();
        if fails == 0 {
            println!("oracle self-check: OK");
            exit(0);
        }
        eprintln!("oracle self-check: {} FAILURES", fails);
        exit(1);
    }
    if args.len() != 4 {
        eprintln!("usage: oracle <fn> <seed> <count>   |   oracle check");
        exit(2);
    }
    let func = args[1].as_str();
    let seed: u64 = args[2].parse().unwrap_or(0);
    let count: usize = args[3].parse().unwrap_or(0);
    if !dispatch(func, seed, count) {
        eprintln!("unknown fn: {}", func);
        exit(2);
    }
}
