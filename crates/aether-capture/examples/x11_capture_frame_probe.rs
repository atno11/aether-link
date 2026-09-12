#[cfg(target_os = "linux")]
fn main() {
    if let Err(error) = run() {
        eprintln!("X11 single-frame capture probe failed: {error}");
        std::process::exit(1);
    }
}

#[cfg(target_os = "linux")]
fn run() -> Result<(), Box<dyn std::error::Error>> {
    use std::io::{Error as IoError, ErrorKind};

    use aether_capture::{
        X11CaptureSourceKind, capture_x11_window_frame, list_x11_capture_sources,
    };

    let display = std::env::var("DISPLAY").unwrap_or_else(|_| "<not set>".to_owned());

    let requested_window_index = requested_window_index()?;

    println!("Aether X11 single-frame capture probe");
    println!("=====================================");
    println!();
    println!("DISPLAY: {display}");
    println!("Window index: {requested_window_index}");
    println!();

    let source = list_x11_capture_sources()?
        .into_iter()
        .filter(|source| source.kind == X11CaptureSourceKind::Window)
        .nth(requested_window_index - 1)
        .ok_or_else(|| {
            IoError::new(
                ErrorKind::NotFound,
                format!("window source {requested_window_index} was not found"),
            )
        })?;

    let pid = source
        .pid
        .map_or_else(|| "?".to_owned(), |pid| pid.to_string());

    println!("Selected source:");
    println!("  XID:             0x{:08x}", source.id);
    println!("  PID:             {pid}");
    println!("  Title:           {:?}", source.title);
    println!("  Discovered size: {}x{}", source.width, source.height);
    println!();

    println!("Capturing exactly one frame through aether-capture...");

    let frame = capture_x11_window_frame(source.id)?;
    let checksum = fnv1a64(&frame.data);

    println!();
    println!("Capture succeeded:");
    println!("  Size:        {}x{}", frame.width, frame.height);
    println!("  Depth:       {}", frame.depth);
    println!("  Visual:      0x{:08x}", frame.visual);
    println!("  Frame bytes: {}", frame.data.len());
    println!("  FNV-1a:      0x{checksum:016x}");
    println!();

    println!("Copy path:");
    println!("  X11 drawable -> GetImage reply -> process RAM");
    println!();

    println!("The X11 -> RAM copy is part of this reusable GetImage path.");
    println!("aether-capture moves the reply buffer without an extra frame-data clone.");
    println!("GetImage is not intended to be the final zero-copy capture path.");

    Ok(())
}

#[cfg(target_os = "linux")]
fn requested_window_index() -> Result<usize, Box<dyn std::error::Error>> {
    use std::io::{Error as IoError, ErrorKind};

    let Some(value) = std::env::args().nth(1) else {
        return Ok(1);
    };

    let index = value.parse::<usize>().map_err(|error| {
        IoError::new(
            ErrorKind::InvalidInput,
            format!("invalid window index {value:?}: {error}"),
        )
    })?;

    if index == 0 {
        return Err(IoError::new(ErrorKind::InvalidInput, "window index must start at 1").into());
    }

    Ok(index)
}

#[cfg(target_os = "linux")]
fn fnv1a64(bytes: &[u8]) -> u64 {
    const OFFSET_BASIS: u64 = 0xcbf29ce484222325;
    const PRIME: u64 = 0x00000100000001b3;

    let mut hash = OFFSET_BASIS;

    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(PRIME);
    }

    hash
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("This probe is only available on Linux/X11.");
    std::process::exit(1);
}
