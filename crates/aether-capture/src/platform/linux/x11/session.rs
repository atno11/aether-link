use x11rb::rust_connection::RustConnection;

use super::frame::{
    X11CaptureFrame, X11FrameCaptureError, capture_x11_window_frame_with_connection,
};

/// Reusable pull-based capture session for one X11 window.
///
/// The session keeps a single X11 connection open across capture attempts. It
/// does not create a worker thread, queue frames, schedule captures, or copy
/// frame bytes beyond the X11 `GetImage` -> process RAM copy performed by the
/// validated frame capture path.
///
/// Resize is handled naturally because every capture reads the current window
/// geometry before issuing `GetImage`. Hidden/unmapped and closed windows keep
/// the same explicit [`X11FrameCaptureError`] behavior as single-frame capture.
pub struct X11CaptureSession {
    connection: RustConnection,
    window: u32,
}

impl X11CaptureSession {
    /// Opens a reusable capture session for one X11 window ID.
    pub fn open(window: u32) -> Result<Self, X11FrameCaptureError> {
        let (connection, _) = x11rb::connect(None)?;

        Ok(Self { connection, window })
    }

    /// Captures the next frame on demand.
    ///
    /// No background work occurs between calls. Dropping the session closes its
    /// X11 connection and stops capture.
    pub fn capture_next_frame(&self) -> Result<X11CaptureFrame, X11FrameCaptureError> {
        capture_x11_window_frame_with_connection(&self.connection, self.window)
    }
}
