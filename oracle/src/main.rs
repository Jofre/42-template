//! Reference implementations for live differential testing (grader-side).
//!
//! Usage:  oracle <fn> <seed> <count>   — emit `<hex-inputs>\t<reference>` per case
//!         oracle <fn> <seed> <count> <length> — the perf layer's length series:
//!                                        <count> inputs of <length> elements (length.rs)
//!         oracle check                 — run every module's self-checks
//!         oracle bench <fn>            — the perf/cost layers' reference baseline,
//!                                        timed against the student (dispatch_bench)
//!         oracle shell01_groups <user> — a shell check's reference (see shell01.rs)
//!         oracle shell01_multigroup [<except>] — ditto, a user in two groups or more
//!         oracle shell01_hwaddr [--loopback] — ditto, a verdict on stdin (exit code)
//!         oracle shell01_hwaddr --machine — ditto, whether there is a hardware address
//!         oracle shell01_rdwssap ...   — ditto, a verdict on stdin (words)
//!         oracle shell01_rdwssap orders|reaches <n>|shows — ditto, about the passwd
//!                                        file alone (exit code)
//!         oracle shell01_chelou [cases <seed>] — ditto, from the environment
//!         oracle shell00_diff_apply <old> <diff> — ditto (see shell00.rs)
//!         oracle rush01_validate       — which rule a rush01 grid breaks, one
//!                                        request per stdin line (rush01_validate.rs)
//!         oracle c10_run [--prog NAME] <tool> ARG... — c-10's four programs run
//!                                        on real paths: the tool's stdout, stderr
//!                                        and exit status (c10.rs, THE MODEL)
//!         oracle c06_run print|rev|sort ARG... — c-06's three argument programs
//!                                        (c06.rs, run_cmd)
//!         oracle run <program> <arg>... — a program's reference, run as the
//!                                        student's is (program(), below)
//!         oracle run --has <program>   — whether there is one (exit code)
//!
//! Std-only, zero dependencies. Each module (cNN.rs) owns its functions'
//! references, generators, a `gen(name, seed, count) -> bool` dispatcher, and a
//! `check() -> usize` self-check. A new module gets a `mod` line below and a term
//! in `check_all`; it also joins `dispatch` if it has a `gen` arm,
//! `dispatch_bench` if it has a bench arm, and `program` if it ships a reference
//! program.

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
mod length;
mod rush00;
mod rush01;
mod rush01_bonus;
mod rush01_validate;
mod rush02;
mod shell00;
mod shell01;

use std::env;
use std::ffi::OsString;
use std::process::exit;

/// `oracle bench <fn>` — read a corpus on stdin and compute the reference
/// answers, generating nothing. The corpus-replay arms print nothing; the
/// zero-input arms do print (see c05::bench). This is the baseline the perf
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

/// Every `gen` dispatcher, tried in order until one claims the function name.
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
        + rush01_validate::check()
        + bsq::check()
        + shell01::check()
        + shell00::check()
        + length::check()
        + check_args()
}

/// The entry point's own arguments. A table or a case can hand a program an
/// argument that is not UTF-8, and `env::args()` panics on one (exit 101), which
/// a runner reads as the reference crashing. So this binary runs itself on such
/// an argument: once for each program `oracle run` knows, for c-06's and
/// c-10's, for `run --has` and a name `run` does not know, and once where the
/// commands that take words read one. Each run is held to a status of its
/// own: the program's answer, its "no answer", or a refusal, never a panic.
fn check_args() -> usize {
    use std::ffi::OsStr;
    use std::os::unix::ffi::OsStrExt;
    use std::process::{Command, Stdio};
    let Ok(me) = env::current_exe() else {
        eprintln!("main: cannot find this binary to run it on its own arguments");
        return 1;
    };
    let bad = OsStr::from_bytes(b"1\xff");
    let runs: [(&[&OsStr], &[i32]); 9] = [
        (&[OsStr::new("run"), OsStr::new("do-op"), bad, OsStr::new("+"), OsStr::new("1")], &[0, 2]),
        (&[OsStr::new("run"), OsStr::new("rush-02"), bad], &[0]),
        (&[OsStr::new("run"), OsStr::new("rush01"), bad], &[0]),
        (&[OsStr::new("run"), OsStr::new("bsq"), bad], &[0]),
        (&[OsStr::new("run"), OsStr::new("--has"), bad], &[1]),
        (&[OsStr::new("run"), bad], &[2]),
        (&[OsStr::new("c10_run"), OsStr::new("cat"), bad], &[2]),
        (&[OsStr::new("c06_run"), OsStr::new("print"), bad], &[0]),
        (&[bad, OsStr::new("1"), OsStr::new("1")], &[2]),
    ];
    let mut fails = 0;
    for (args, want) in runs {
        let shown: Vec<String> = args.iter().map(|a| format!("{:?}", a)).collect();
        let got = Command::new(&me)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output();
        match got {
            Ok(o) if o.status.code().is_some_and(|c| want.contains(&c)) => {}
            Ok(o) => {
                eprintln!(
                    "main: `oracle {}` ended with {} (want a status in {:?}): {}",
                    shown.join(" "),
                    o.status,
                    want,
                    String::from_utf8_lossy(&o.stderr).lines().find(|l| !l.is_empty()).unwrap_or("")
                );
                fails += 1;
            }
            Err(e) => {
                eprintln!("main: `oracle {}` could not start: {}", shown.join(" "), e);
                fails += 1;
            }
        }
    }
    fails
}

/// The reference PROGRAMS, by the subject's executable name: `oracle run
/// <name> <arg>...` prints what `./<name> <arg>...` must, from the folder it
/// runs in, and returns 0. Where it has no answer -- a run the subject leaves
/// open -- it says why on standard error and returns another status, and
/// reference_cases.sh fails any case but a survive case that makes that run
/// (printing nothing is an answer, which the differ alone would pass).
/// c_program's `reference = True` runs every named case through it, with the
/// case's own argv, argument file and run folder (tools/reference_cases.sh),
/// so a case whose run and expected file drifted apart fails on any tree, the
/// template's stubs included.
///
/// Each one is handed its arguments as the OS gave them, bytes that need not
/// be UTF-8, as a C program's argv is.
fn program(name: &str) -> Option<fn(&[OsString]) -> i32> {
    match name {
        "rush-02" => Some(rush02::run),
        "rush01" => Some(rush01::run),
        "bsq" => Some(bsq::run),
        "do-op" => Some(c11::do_op_run),
        _ => None,
    }
}

fn main() {
    // The commands that run a program read its arguments as the OS gave them:
    // an argument a table or a case hands the program need not be UTF-8, and
    // env::args() panics on one (check_args). Every other command takes words,
    // and a word that is not UTF-8 is a usage error there, never a panic.
    let raw: Vec<OsString> = env::args_os().collect();
    if raw.len() >= 3 && raw[1] == "c06_run" {
        c06::run_cmd(&raw[2..]);
    }
    if raw.len() >= 3 && raw[1] == "c10_run" {
        c10::run_cmd(&raw[2..]);
    }
    if raw.len() >= 3 && raw[1] == "run" {
        let name = raw[2].to_str();
        if name == Some("--has") {
            exit(if raw.len() == 4 && raw[3].to_str().and_then(program).is_some() { 0 } else { 1 });
        }
        match name.and_then(program) {
            Some(run) => exit(run(&raw[3..])),
            None => {
                eprintln!("oracle run: no reference program named {}", raw[2].to_string_lossy());
                exit(2);
            }
        }
    }
    let args: Vec<String> = match raw.iter().map(|a| a.clone().into_string()).collect() {
        Ok(v) => v,
        Err(word) => {
            eprintln!("oracle: an argument is not UTF-8: {:?}", word);
            exit(2);
        }
    };
    if args.len() >= 3 && args[1] == "bench" {
        if dispatch_bench(&args[2]) {
            exit(0);
        }
        eprintln!("oracle bench: no baseline for {}", args[2]);
        exit(2);
    }
    if args.len() == 3 && args[1] == "shell01_groups" {
        shell01::groups(&args[2]);
    }
    if (args.len() == 2 || args.len() == 3) && args[1] == "shell01_multigroup" {
        shell01::multigroup_cmd(args.get(2).map(String::as_str));
    }
    if args.len() == 2 && args[1] == "shell01_hwaddr" {
        shell01::hwaddr_cmd(false);
    }
    if args.len() == 3 && args[1] == "shell01_hwaddr" && args[2] == "--loopback" {
        shell01::hwaddr_cmd(true);
    }
    if args.len() == 3 && args[1] == "shell01_hwaddr" && args[2] == "--machine" {
        shell01::hwaddr_machine_cmd();
    }
    if args.len() >= 3 && args[1] == "shell01_rdwssap" {
        shell01::rdwssap_cmd(&args[2..]);
    }
    if args.len() == 2 && args[1] == "shell01_chelou" {
        shell01::chelou_cmd();
    }
    if args.len() == 4 && args[1] == "shell01_chelou" && args[2] == "cases" {
        shell01::chelou_cases_cmd(&args[3]);
    }
    if args.len() == 4 && args[1] == "shell00_diff_apply" {
        shell00::diff_apply_cmd(&args[2], &args[3]);
    }
    if args.len() == 2 && args[1] == "rush01_validate" {
        rush01_validate::run();
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
    if args.len() == 5 {
        let seed: u64 = args[2].parse().unwrap_or(0);
        let count: usize = args[3].parse().unwrap_or(0);
        let len: usize = args[4].parse().unwrap_or(0);
        if !length::gen(&args[1], seed, count, len) {
            eprintln!("unknown length arm: {}", args[1]);
            exit(2);
        }
        exit(0);
    }
    if args.len() != 4 {
        eprintln!("usage: oracle <fn> <seed> <count> [<length>]   |   oracle check");
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
