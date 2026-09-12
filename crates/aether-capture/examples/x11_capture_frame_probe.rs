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

    use aether_capture::{X11CaptureSourceKind, list_x11_capture_sources};
    use x11rb::protocol::xproto::{ConnectionExt as _, ImageFormat, MapState};

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

    let (connection, _) = x11rb::connect(None)?;

    let attributes = connection.get_window_attributes(source.id)?.reply()?;

    if attributes.map_state != MapState::VIEWABLE {
        return Err(IoError::other(format!(
            "selected X11 window 0x{:08x} is not currently viewable",
            source.id
        ))
        .into());
    }

    let geometry = connection.get_geometry(source.id)?.reply()?;

    if geometry.width == 0 || geometry.height == 0 {
        return Err(IoError::other(format!(
            "selected X11 window has invalid geometry {}x{}",
            geometry.width, geometry.height
        ))
        .into());
    }

    println!("Current size:    {}x{}", geometry.width, geometry.height);
    println!();
    println!("Capturing exactly one frame with X11 GetImage...");

    let frame = connection
        .get_image(
            ImageFormat::Z_PIXMAP,
            source.id,
            0,
            0,
            geometry.width,
            geometry.height,
            u32::MAX,
        )?
        .reply()?;

    if frame.data.is_empty() {
        return Err(IoError::other("X11 GetImage returned an empty frame").into());
    }

    let checksum = fnv1a64(&frame.data);

    println!();
    println!("Capture succeeded:");
    println!("  Size:       {}x{}", geometry.width, geometry.height);
    println!("  Depth:      {}", frame.depth);
    println!("  Visual:     0x{:08x}", frame.visual);
    println!("  Frame bytes: {}", frame.data.len());
    println!("  FNV-1a:     0x{checksum:016x}");
    println!();
    println!("Copy path:");
    println!("  X11 drawable -> GetImage reply -> process RAM");
    println!();
    println!("This CPU-visible copy is intentional for this probe.");
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
