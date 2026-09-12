//! Screen and window capture functionality for Aether.
//!
//! Native capture backends are introduced only after being validated through
//! isolated probes/examples.

mod platform;

#[cfg(target_os = "linux")]
pub use platform::linux::x11::{
    X11CaptureSource, X11CaptureSourceKind, X11SourceDiscoveryError, list_x11_capture_sources,
};
