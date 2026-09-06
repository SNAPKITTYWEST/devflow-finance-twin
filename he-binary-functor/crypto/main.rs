use malleability::{map_digest, ZeroOrbit};

fn parse_hex(s: &str) -> Vec<u8> {
    let s = s.trim().trim_start_matches("0x");
    (0..s.len())
        .step_by(2)
        .filter_map(|i| u8::from_str_radix(&s[i..i + 2.min(s.len() - i)], 16).ok())
        .collect()
}

fn print_orbit(o: &ZeroOrbit) {
    println!("n = {}", o.n);
    println!("t_n = {:.12}", o.t);
    println!("rho = 1/2 + i*{:.12}", o.rho.t);
    println!("rho_bar = 1/2 - i*{:.12}", o.rho_bar.t);
    println!("orbit ({} points):", o.orbit.len());
    for (i, p) in o.orbit.iter().enumerate() {
        let sign = if p.upper { '+' } else { '-' };
        println!(" [{}] 1/2 {} i*{:.12}", i, sign, p.t);
    }
    println!("seal = {:#018x}", o.seal);
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let digest = if args.len() > 1 {
        parse_hex(&args[1])
    } else {
        parse_hex("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
    };
    if digest.is_empty() {
        eprintln!("usage: malleability <hex-digest>");
        std::process::exit(1);
    }
    let orbit = map_digest(&digest);
    print_orbit(&orbit);
}
