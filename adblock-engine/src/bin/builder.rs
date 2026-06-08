use std::env;
use std::fs;

use adblock::engine::Engine;
use adblock::lists::{FilterSet, ParseOptions};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: builder <output.dat> <list1.txt> [list2.txt ...]");
        std::process::exit(1);
    }

    let output = &args[1];
    let mut filter_set = FilterSet::new(true);

    for path in &args[2..] {
        let text = fs::read_to_string(path).unwrap_or_else(|e| {
            eprintln!("failed to read {}: {}", path, e);
            std::process::exit(1);
        });
        let fmt = if path.contains("hosts") {
            adblock::lists::FilterFormat::Hosts
        } else {
            adblock::lists::FilterFormat::Standard
        };
        let opts = ParseOptions {
            format: fmt,
            ..ParseOptions::default()
        };
        filter_set.add_filter_list(&text, opts);
    }

    let engine = Engine::from_filter_set(filter_set, true);
    let data = engine.serialize();
    fs::write(output, &data).unwrap_or_else(|e| {
        eprintln!("failed to write {}: {}", output, e);
        std::process::exit(1);
    });

    println!("Wrote {} bytes to {}", data.len(), output);
}
