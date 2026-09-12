use std::error::Error;
use std::fmt;

use x11rb::errors::{ConnectError, ConnectionError, ReplyError};
use x11rb::protocol::ErrorKind;
use x11rb::protocol::xproto::{ConnectionExt as _, ImageFormat, MapState};

/// One CPU-visible frame captured from an X11 window with `GetImage`.
///
/// `data` contains the raw X11 `ZPixmap` reply bytes. The bytes are not
/// normalized to RGBA or another application pixel format.
///
/// This path performs an X11 -> process RAM copy by design. The reply buffer is
/// moved into this type without an additional clone, but `GetImage` itself is a
/// CPU-visible copy and is not the final zero-copy capture path for Aether.
#[derive(Debug)]
pub struct X11CaptureFrame {
    pub width: u16,
    pub height: u16,
    pub depth: u8,
    pub visual: u32,
    pub data: Vec<u8>,
}

/// Error returned when a single X11 window frame cannot be captured.
#[derive(Debug)]
pub enum X11FrameCaptureError {
    Connect(ConnectError),
    Connection(ConnectionError),
    Reply(ReplyError),
    WindowUnavailable(u32),
    WindowNotViewable(u32),
    InvalidGeometry {
        window: u32,
        width: u16,
        height: u16,
    },
    EmptyFrame(u32),
}

impl fmt::Display for X11FrameCaptureError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Connect(error) => {
                write!(formatter, "failed to connect to X11: {error}")
            }
            Self::Connection(error) => {
                write!(formatter, "X11 connection error: {error}")
            }
            Self::Reply(error) => {
                write!(formatter, "X11 reply error: {error}")
            }
            Self::WindowUnavailable(window) => {
                write!(
                    formatter,
                    "X11 window 0x{window:08x} is no longer available"
                )
            }
            Self::WindowNotViewable(window) => {
                write!(
                    formatter,
                    "X11 window 0x{window:08x} is not currently viewable"
                )
            }
            Self::InvalidGeometry {
                window,
                width,
                height,
            } => {
                write!(
                    formatter,
                    "X11 window 0x{window:08x} has invalid geometry {width}x{height}"
                )
            }
            Self::EmptyFrame(window) => {
                write!(
                    formatter,
                    "X11 GetImage returned an empty frame for window 0x{window:08x}"
                )
            }
        }
    }
}

impl Error for X11FrameCaptureError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Connect(error) => Some(error),
            Self::Connection(error) => Some(error),
            Self::Reply(error) => Some(error),
            Self::WindowUnavailable(_)
            | Self::WindowNotViewable(_)
            | Self::InvalidGeometry { .. }
            | Self::EmptyFrame(_) => None,
        }
    }
}

impl From<ConnectError> for X11FrameCaptureError {
    fn from(error: ConnectError) -> Self {
        Self::Connect(error)
    }
}

impl From<ConnectionError> for X11FrameCaptureError {
    fn from(error: ConnectionError) -> Self {
        Self::Connection(error)
    }
}

/// Captures exactly one CPU-visible frame from an X11 window.
///
/// The window must exist and be viewable at capture time. A window that has
/// been closed is reported as [`X11FrameCaptureError::WindowUnavailable`], and
/// an unmapped/hidden window is reported as
/// [`X11FrameCaptureError::WindowNotViewable`].
///
/// This function intentionally uses X11 `GetImage`. That request copies the
/// drawable into process RAM. Aether keeps this copy explicit so this validated
/// single-frame path is not mistaken for the future zero-copy capture path.
pub fn capture_x11_window_frame(window: u32) -> Result<X11CaptureFrame, X11FrameCaptureError> {
    let (connection, _) = x11rb::connect(None)?;

    let attributes = connection
        .get_window_attributes(window)?
        .reply()
        .map_err(|error| map_window_reply_error(window, error))?;

    if attributes.map_state != MapState::VIEWABLE {
        return Err(X11FrameCaptureError::WindowNotViewable(window));
    }

    let geometry = connection
        .get_geometry(window)?
        .reply()
        .map_err(|error| map_window_reply_error(window, error))?;

    if geometry.width == 0 || geometry.height == 0 {
        return Err(X11FrameCaptureError::InvalidGeometry {
            window,
            width: geometry.width,
            height: geometry.height,
        });
    }

    let reply = connection
        .get_image(
            ImageFormat::Z_PIXMAP,
            window,
            0,
            0,
            geometry.width,
            geometry.height,
            u32::MAX,
        )?
        .reply()
        .map_err(|error| map_window_reply_error(window, error))?;

    if reply.data.is_empty() {
        return Err(X11FrameCaptureError::EmptyFrame(window));
    }

    Ok(X11CaptureFrame {
        width: geometry.width,
        height: geometry.height,
        depth: reply.depth,
        visual: reply.visual,
        data: reply.data,
    })
}

fn map_window_reply_error(window: u32, error: ReplyError) -> X11FrameCaptureError {
    match &error {
        ReplyError::X11Error(x11_error)
            if matches!(
                x11_error.error_kind,
                ErrorKind::Window | ErrorKind::Drawable
            ) =>
        {
            X11FrameCaptureError::WindowUnavailable(window)
        }
        _ => X11FrameCaptureError::Reply(error),
    }
}
