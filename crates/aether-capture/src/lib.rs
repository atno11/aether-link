//! Screen and window capture functionality for Aether.
//!
//! Native capture backends are introduced only after being validated through
//! isolated probes/examples.

mod platform;

#[cfg(target_os = "linux")]
pub use platform::linux::x11::{
    X11CaptureFrame, X11CaptureSource, X11CaptureSourceKind, X11FrameCaptureError,
    X11SourceDiscoveryError, capture_x11_window_frame, list_x11_capture_sources,
};
