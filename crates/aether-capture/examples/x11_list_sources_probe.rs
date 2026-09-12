#[cfg(target_os = "linux")]
fn main() {
    if let Err(error) = run() {
        eprintln!("X11 source discovery probe failed: {error}");
        std::process::exit(1);
    }
}

#[cfg(target_os = "linux")]
fn run() -> Result<(), aether_capture::X11SourceDiscoveryError> {
    use aether_capture::{X11CaptureSourceKind, list_x11_capture_sources};

    let display = std::env::var("DISPLAY").unwrap_or_else(|_| "<not set>".to_owned());

    println!("Aether X11 source discovery probe");
    println!("=================================");
    println!();
    println!("DISPLAY: {display}");
    println!();

    let sources = list_x11_capture_sources()?;

    let mut window_index = 0usize;

    for source in sources {
        match source.kind {
            X11CaptureSourceKind::Desktop => {
                println!(
                    "[desktop] id=0x{:08x} size={}x{}",
                    source.id, source.width, source.height
                );
            }

            X11CaptureSourceKind::Window => {
                window_index += 1;

                let pid = source
                    .pid
                    .map_or_else(|| "?".to_owned(), |pid| pid.to_string());

                println!(
                    "[window {window_index}] id=0x{:08x} pid={} size={}x{} title={:?}",
                    source.id, pid, source.width, source.height, source.title
                );
            }
        }
    }

    println!();
    println!("Discovered window sources: {window_index}");

    Ok(())
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("This probe is only available on Linux/X11.");
    std::process::exit(1);
}
