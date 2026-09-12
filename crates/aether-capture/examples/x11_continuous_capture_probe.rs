#[cfg(target_os = "linux")]
fn main() {
    if let Err(error) = run() {
        eprintln!("X11 continuous capture probe failed: {error}");
        std::process::exit(1);
    }
}

#[cfg(target_os = "linux")]
fn run() -> Result<(), Box<dyn std::error::Error>> {
    use std::io::{Error as IoError, ErrorKind};
    use std::thread;
    use std::time::{Duration, Instant};

    use aether_capture::{
        X11CaptureSourceKind, X11FrameCaptureError, capture_x11_window_frame,
        list_x11_capture_sources,
    };

    const DEFAULT_TARGET_FPS: u32 = 60;
    const MAX_TARGET_FPS: u32 = 1000;
    const METRICS_INTERVAL: Duration = Duration::from_secs(1);

    let (requested_window_index, target_fps) =
        requested_arguments(DEFAULT_TARGET_FPS, MAX_TARGET_FPS)?;
    let display = std::env::var("DISPLAY").unwrap_or_else(|_| "<not set>".to_owned());

    println!("Aether X11 continuous capture probe");
    println!("===================================");
    println!();
    println!("DISPLAY: {display}");
    println!("Window index: {requested_window_index}");
    println!("Target FPS: {target_fps}");
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
    println!("Validation:");
    println!("  - resize the selected window and watch for a size-change event");
    println!("  - hide/unmap it so X11 reports it as not viewable, then restore it");
    println!("  - close it to verify clean termination on an unavailable XID");
    println!();
    println!("Copy path: X11 drawable -> GetImage reply -> process RAM");
    println!("This probe intentionally reuses the validated single-frame API.");
    println!("That API currently opens an X11 connection for each capture attempt.");
    println!();

    let frame_interval = Duration::from_secs_f64(1.0 / f64::from(target_fps));
    let started_at = Instant::now();
    let mut last_metrics_at = started_at;
    let mut next_capture_at = started_at;
    let mut frames_at_last_report = 0u64;

    let mut metrics = ProbeMetrics {
        captured_frames: 0,
        capture_errors: 0,
        not_viewable_errors: 0,
        invalid_geometry_errors: 0,
        resize_events: 0,
        last_size: (source.width, source.height),
    };

    let mut is_not_viewable = false;
    let mut has_invalid_geometry = false;

    loop {
        match capture_x11_window_frame(source.id) {
            Ok(frame) => {
                metrics.captured_frames += 1;

                if is_not_viewable {
                    println!("[state] window is viewable again; capture resumed");
                    is_not_viewable = false;
                }

                if has_invalid_geometry {
                    println!("[state] window geometry is valid again; capture resumed");
                    has_invalid_geometry = false;
                }

                let size = (frame.width, frame.height);

                if metrics.last_size != size {
                    metrics.resize_events += 1;
                    println!(
                        "[resize] {}x{} -> {}x{}",
                        metrics.last_size.0, metrics.last_size.1, frame.width, frame.height
                    );
                    metrics.last_size = size;
                }
            }
            Err(X11FrameCaptureError::WindowNotViewable(_)) => {
                metrics.capture_errors += 1;
                metrics.not_viewable_errors += 1;

                if !is_not_viewable {
                    println!("[state] window is not viewable; waiting for it to return");
                    is_not_viewable = true;
                }
            }
            Err(X11FrameCaptureError::WindowUnavailable(_)) => {
                metrics.capture_errors += 1;
                println!("[state] window is unavailable; assuming it was closed");
                print_final_metrics(started_at, &metrics);
                break;
            }
            Err(error @ X11FrameCaptureError::InvalidGeometry { .. }) => {
                metrics.capture_errors += 1;
                metrics.invalid_geometry_errors += 1;

                if !has_invalid_geometry {
                    eprintln!("[capture error] {error}; waiting for valid geometry");
                    has_invalid_geometry = true;
                }
            }
            Err(error) => {
                metrics.capture_errors += 1;
                print_final_metrics(started_at, &metrics);
                return Err(error.into());
            }
        }

        let now = Instant::now();
        let metrics_elapsed = now.duration_since(last_metrics_at);

        if metrics_elapsed >= METRICS_INTERVAL {
            let interval_frames = metrics.captured_frames - frames_at_last_report;
            print_periodic_metrics(started_at, metrics_elapsed, interval_frames, &metrics);

            last_metrics_at = now;
            frames_at_last_report = metrics.captured_frames;
        }

        next_capture_at += frame_interval;
        let now = Instant::now();

        if next_capture_at > now {
            thread::sleep(next_capture_at - now);
        } else {
            next_capture_at = now;
        }
    }

    Ok(())
}

#[cfg(target_os = "linux")]
struct ProbeMetrics {
    captured_frames: u64,
    capture_errors: u64,
    not_viewable_errors: u64,
    invalid_geometry_errors: u64,
    resize_events: u64,
    last_size: (u16, u16),
}

#[cfg(target_os = "linux")]
fn requested_arguments(
    default_target_fps: u32,
    max_target_fps: u32,
) -> Result<(usize, u32), Box<dyn std::error::Error>> {
    use std::io::{Error as IoError, ErrorKind};

    let mut arguments = std::env::args().skip(1);

    let Some(window_index_value) = arguments.next() else {
        return Err(IoError::new(
            ErrorKind::InvalidInput,
            "usage: x11_continuous_capture_probe <window-index> [target-fps]",
        )
        .into());
    };

    let window_index = window_index_value.parse::<usize>().map_err(|error| {
        IoError::new(
            ErrorKind::InvalidInput,
            format!("invalid window index {window_index_value:?}: {error}"),
        )
    })?;

    if window_index == 0 {
        return Err(IoError::new(ErrorKind::InvalidInput, "window index must start at 1").into());
    }

    let target_fps = match arguments.next() {
        Some(value) => value.parse::<u32>().map_err(|error| {
            IoError::new(
                ErrorKind::InvalidInput,
                format!("invalid target FPS {value:?}: {error}"),
            )
        })?,
        None => default_target_fps,
    };

    if !(1..=max_target_fps).contains(&target_fps) {
        return Err(IoError::new(
            ErrorKind::InvalidInput,
            format!("target FPS must be between 1 and {max_target_fps}"),
        )
        .into());
    }

    if let Some(unexpected) = arguments.next() {
        return Err(IoError::new(
            ErrorKind::InvalidInput,
            format!("unexpected argument {unexpected:?}"),
        )
        .into());
    }

    Ok((window_index, target_fps))
}

#[cfg(target_os = "linux")]
fn print_periodic_metrics(
    started_at: std::time::Instant,
    interval_elapsed: std::time::Duration,
    interval_frames: u64,
    metrics: &ProbeMetrics,
) {
    let total_elapsed = started_at.elapsed();
    let current_fps = interval_frames as f64 / interval_elapsed.as_secs_f64();
    let average_fps = metrics.captured_frames as f64 / total_elapsed.as_secs_f64();

    println!(
        "[metrics] frames={} fps={current_fps:.1} avg_fps={average_fps:.1} errors={} not_viewable={} invalid_geometry={} resizes={} size={}x{}",
        metrics.captured_frames,
        metrics.capture_errors,
        metrics.not_viewable_errors,
        metrics.invalid_geometry_errors,
        metrics.resize_events,
        metrics.last_size.0,
        metrics.last_size.1
    );
}

#[cfg(target_os = "linux")]
fn print_final_metrics(started_at: std::time::Instant, metrics: &ProbeMetrics) {
    let elapsed = started_at.elapsed();
    let average_fps = metrics.captured_frames as f64 / elapsed.as_secs_f64();

    println!();
    println!("Final metrics:");
    println!("  Elapsed:          {:.2}s", elapsed.as_secs_f64());
    println!("  Frames captured:  {}", metrics.captured_frames);
    println!("  Average FPS:      {average_fps:.1}");
    println!("  Capture errors:   {}", metrics.capture_errors);
    println!("  Not viewable:     {}", metrics.not_viewable_errors);
    println!("  Invalid geometry: {}", metrics.invalid_geometry_errors);
    println!("  Resize events:    {}", metrics.resize_events);
    println!(
        "  Last size:        {}x{}",
        metrics.last_size.0, metrics.last_size.1
    );
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("This probe is only available on Linux/X11.");
    std::process::exit(1);
}
