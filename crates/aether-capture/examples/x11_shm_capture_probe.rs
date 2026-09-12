#[cfg(target_os = "linux")]
fn main() {
    if let Err(error) = run() {
        eprintln!("X11 MIT-SHM capture probe failed: {error}");
        std::process::exit(1);
    }
}

#[cfg(target_os = "linux")]
fn run() -> Result<(), Box<dyn std::error::Error>> {
    use std::io::{Error as IoError, ErrorKind};
    use std::time::Instant;

    use aether_capture::{X11CaptureSourceKind, list_x11_capture_sources};
    use x11rb::connection::RequestConnection;
    use x11rb::protocol::shm::{self, ConnectionExt as _};
    use x11rb::protocol::xproto::{ConnectionExt as _, ImageFormat, MapState};

    let display = std::env::var("DISPLAY").unwrap_or_else(|_| "<not set>".to_owned());
    let requested_window_index = requested_window_index()?;

    println!("Aether X11 MIT-SHM capture probe");
    println!("================================");
    println!();
    println!("DISPLAY:      {display}");
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

    if connection
        .extension_information(shm::X11_EXTENSION_NAME)?
        .is_none()
    {
        return Err(IoError::new(
            ErrorKind::Unsupported,
            "the X11 server does not expose the MIT-SHM extension",
        )
        .into());
    }

    let shm_version = connection.shm_query_version()?.reply()?;

    println!(
        "MIT-SHM version: {}.{}",
        shm_version.major_version, shm_version.minor_version
    );

    if shm_version.major_version < 1
        || (shm_version.major_version == 1 && shm_version.minor_version < 2)
    {
        return Err(IoError::new(
            ErrorKind::Unsupported,
            format!(
                "MIT-SHM {}.{} is available, but 1.2 is required for server-created FD segments",
                shm_version.major_version, shm_version.minor_version
            ),
        )
        .into());
    }

    let attributes = connection.get_window_attributes(source.id)?.reply()?;

    if attributes.map_state != MapState::VIEWABLE {
        return Err(IoError::new(
            ErrorKind::InvalidInput,
            format!(
                "selected X11 window 0x{:08x} is not currently viewable",
                source.id
            ),
        )
        .into());
    }

    let geometry = connection.get_geometry(source.id)?.reply()?;

    if geometry.width == 0 || geometry.height == 0 {
        return Err(IoError::new(
            ErrorKind::InvalidData,
            format!(
                "selected X11 window 0x{:08x} has invalid geometry {}x{}",
                source.id, geometry.width, geometry.height
            ),
        )
        .into());
    }

    let layout = frame_layout(&connection, geometry.depth, geometry.width, geometry.height)?;

    let segment_size = u32::try_from(layout.buffer_len).map_err(|_| {
        IoError::new(
            ErrorKind::InvalidData,
            format!(
                "required MIT-SHM segment is too large: {} bytes",
                layout.buffer_len
            ),
        )
    })?;

    println!();
    println!("Capture layout:");
    println!("  Current size:    {}x{}", geometry.width, geometry.height);
    println!("  Depth:           {}", geometry.depth);
    println!("  Bits per pixel:  {}", layout.bits_per_pixel);
    println!("  Scanline pad:    {} bits", layout.scanline_pad);
    println!("  Stride:          {} bytes", layout.stride_bytes);
    println!("  Segment bytes:   {segment_size}");
    println!();

    let segment = MappedShmSegment::create(&connection, segment_size)?;

    println!("Capturing twice into the same mapped MIT-SHM segment...");

    for capture_number in 1..=2 {
        let started = Instant::now();

        let reply = connection
            .shm_get_image(
                source.id,
                0,
                0,
                geometry.width,
                geometry.height,
                u32::MAX,
                ImageFormat::Z_PIXMAP.into(),
                segment.id(),
                0,
            )?
            .reply()?;

        let elapsed = started.elapsed();

        if reply.size == 0 {
            return Err(IoError::new(
                ErrorKind::UnexpectedEof,
                "MIT-SHM GetImage reported zero copied bytes",
            )
            .into());
        }

        let copied_len = usize::try_from(reply.size).map_err(|_| {
            IoError::new(
                ErrorKind::InvalidData,
                format!("MIT-SHM GetImage returned an invalid size: {}", reply.size),
            )
        })?;

        if copied_len > segment.byte_len() {
            return Err(IoError::new(
                ErrorKind::InvalidData,
                format!(
                    "MIT-SHM GetImage copied {copied_len} bytes into a {}-byte segment",
                    segment.byte_len()
                ),
            )
            .into());
        }

        let checksum = fnv1a64(&segment.as_slice()[..copied_len]);

        println!();
        println!("Capture {capture_number} succeeded:");
        println!("  Depth:        {}", reply.depth);
        println!("  Visual:       0x{:08x}", reply.visual);
        println!("  Copied bytes: {}", reply.size);
        println!("  Latency:      {:.3} ms", elapsed.as_secs_f64() * 1_000.0);
        println!("  FNV-1a:       0x{checksum:016x}");
    }

    println!();
    println!("Validated path:");
    println!("  X11 drawable -> MIT-SHM -> one persistent mapped process-RAM buffer");
    println!();
    println!("The same frame-sized mapping was reused for both captures.");
    println!("shm_get_image returns only metadata; frame bytes are not returned in a new Vec.");
    println!("This removes the frame-sized GetImage reply allocation/copy from the client path.");
    println!("The X server still copies the drawable into CPU-visible shared memory.");
    println!("MIT-SHM is therefore an intermediate low-overhead path, not GPU zero-copy.");

    Ok(())
}

#[cfg(target_os = "linux")]
struct FrameLayout {
    bits_per_pixel: u8,
    scanline_pad: u8,
    stride_bytes: usize,
    buffer_len: usize,
}

#[cfg(target_os = "linux")]
fn frame_layout(
    connection: &x11rb::rust_connection::RustConnection,
    depth: u8,
    width: u16,
    height: u16,
) -> Result<FrameLayout, Box<dyn std::error::Error>> {
    use std::io::{Error as IoError, ErrorKind};

    use x11rb::connection::Connection;

    let format = connection
        .setup()
        .pixmap_formats
        .iter()
        .find(|format| format.depth == depth)
        .ok_or_else(|| {
            IoError::new(
                ErrorKind::Unsupported,
                format!("X11 server did not advertise a pixmap format for depth {depth}"),
            )
        })?;

    if format.bits_per_pixel == 0
        || format.scanline_pad == 0
        || !format.scanline_pad.is_multiple_of(8)
    {
        return Err(IoError::new(
            ErrorKind::InvalidData,
            format!(
                "unsupported X11 pixmap layout: depth={depth}, bits_per_pixel={}, scanline_pad={}",
                format.bits_per_pixel, format.scanline_pad
            ),
        )
        .into());
    }

    let bits_per_line = u64::from(width)
        .checked_mul(u64::from(format.bits_per_pixel))
        .ok_or_else(|| IoError::new(ErrorKind::InvalidData, "X11 scanline size overflow"))?;

    let alignment_bits = u64::from(format.scanline_pad);

    let aligned_bits = bits_per_line
        .div_ceil(alignment_bits)
        .checked_mul(alignment_bits)
        .ok_or_else(|| IoError::new(ErrorKind::InvalidData, "X11 scanline alignment overflow"))?;

    let stride_bytes_u64 = aligned_bits / 8;

    let buffer_len_u64 = stride_bytes_u64
        .checked_mul(u64::from(height))
        .ok_or_else(|| IoError::new(ErrorKind::InvalidData, "X11 frame size overflow"))?;

    let stride_bytes = usize::try_from(stride_bytes_u64)
        .map_err(|_| IoError::new(ErrorKind::InvalidData, "X11 stride does not fit usize"))?;

    let buffer_len = usize::try_from(buffer_len_u64)
        .map_err(|_| IoError::new(ErrorKind::InvalidData, "X11 frame size does not fit usize"))?;

    if buffer_len == 0 {
        return Err(
            IoError::new(ErrorKind::InvalidData, "calculated X11 frame size is zero").into(),
        );
    }

    Ok(FrameLayout {
        bits_per_pixel: format.bits_per_pixel,
        scanline_pad: format.scanline_pad,
        stride_bytes,
        buffer_len,
    })
}

#[cfg(target_os = "linux")]
struct MappedShmSegment<'connection> {
    connection: &'connection x11rb::rust_connection::RustConnection,
    id: x11rb::protocol::shm::Seg,
    address: std::ptr::NonNull<u8>,
    len: usize,
}

#[cfg(target_os = "linux")]
impl<'connection> MappedShmSegment<'connection> {
    fn create(
        connection: &'connection x11rb::rust_connection::RustConnection,
        segment_size: u32,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        use std::io::{Error as IoError, ErrorKind};
        use std::os::fd::AsRawFd;
        use std::ptr::null_mut;

        use libc::{MAP_FAILED, MAP_SHARED, PROT_READ, PROT_WRITE, mmap};
        use x11rb::connection::Connection;
        use x11rb::protocol::shm::{self, ConnectionExt as _};

        let len = usize::try_from(segment_size).map_err(|_| {
            IoError::new(
                ErrorKind::InvalidInput,
                "MIT-SHM segment size does not fit usize",
            )
        })?;

        let id = connection.generate_id()?;

        let reply = connection
            .shm_create_segment(id, segment_size, false)?
            .reply()?;

        let shm::CreateSegmentReply { shm_fd, .. } = reply;

        // SAFETY: `shm_fd` is a valid file descriptor returned by the X server
        // for a segment of `segment_size` bytes. The mapping is kept alive until
        // Drop, and all slices created from it are bounded by `len`.
        let mapped = unsafe {
            mmap(
                null_mut(),
                len,
                PROT_READ | PROT_WRITE,
                MAP_SHARED,
                shm_fd.as_raw_fd(),
                0,
            )
        };

        if mapped == MAP_FAILED {
            let mmap_error = IoError::last_os_error();

            if let Ok(cookie) = connection.shm_detach(id) {
                cookie.ignore_error();
            }

            return Err(mmap_error.into());
        }

        let Some(address) = std::ptr::NonNull::new(mapped.cast::<u8>()) else {
            // SAFETY: `mapped` is the successful mapping returned immediately
            // above, so these are the same pointer and length passed to mmap.
            unsafe {
                let _ = libc::munmap(mapped, len);
            }

            if let Ok(cookie) = connection.shm_detach(id) {
                cookie.ignore_error();
            }

            return Err(IoError::new(
                ErrorKind::OutOfMemory,
                "mmap returned a null MIT-SHM mapping",
            )
            .into());
        };

        Ok(Self {
            connection,
            id,
            address,
            len,
        })
    }

    fn id(&self) -> x11rb::protocol::shm::Seg {
        self.id
    }

    fn byte_len(&self) -> usize {
        self.len
    }

    fn as_slice(&self) -> &[u8] {
        // SAFETY: `address` points to the live `len`-byte mapping owned by this
        // value. The returned slice cannot outlive `self`.
        unsafe { std::slice::from_raw_parts(self.address.as_ptr(), self.len) }
    }
}

#[cfg(target_os = "linux")]
impl Drop for MappedShmSegment<'_> {
    fn drop(&mut self) {
        use libc::munmap;
        use x11rb::protocol::shm::ConnectionExt as _;

        if let Ok(cookie) = self.connection.shm_detach(self.id) {
            cookie.ignore_error();
        }

        // SAFETY: `address` and `len` are exactly the mapping created by mmap in
        // `MappedShmSegment::create`, and Drop runs at most once for this owner.
        unsafe {
            let _ = munmap(self.address.as_ptr().cast(), self.len);
        }
    }
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
