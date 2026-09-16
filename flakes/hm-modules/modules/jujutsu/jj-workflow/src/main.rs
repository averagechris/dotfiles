fn main() {
    if let Err(err) = jj_workflow::run_cli() {
        eprintln!("Error: {err:#}");
        std::process::exit(1);
    }
}
