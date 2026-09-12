use std::error::Error;
use std::fmt;

use x11rb::connection::Connection;
use x11rb::errors::{ConnectError, ConnectionError, ReplyError};
use x11rb::protocol::xproto::{Atom, AtomEnum, ConnectionExt as _, Window};
use x11rb::rust_connection::RustConnection;

const MAX_CLIENT_WINDOWS: u32 = 4096;
const MAX_TEXT_LENGTH: u32 = 1024;

/// Kind of source exposed by the X11 discovery backend.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum X11CaptureSourceKind {
    Desktop,
    Window,
}

/// Capture source discovered from the active X11 display.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct X11CaptureSource {
    pub id: u32,
    pub kind: X11CaptureSourceKind,
    pub pid: Option<u32>,
    pub width: u16,
    pub height: u16,
    pub title: String,
}

/// Error returned when X11 source discovery cannot be completed.
#[derive(Debug)]
pub enum X11SourceDiscoveryError {
    Connect(ConnectError),
    Connection(ConnectionError),
    Reply(ReplyError),
    InvalidScreenIndex(usize),
    InvalidClientListProperty,
}

impl fmt::Display for X11SourceDiscoveryError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Connect(error) => write!(formatter, "failed to connect to X11: {error}"),
            Self::Connection(error) => write!(formatter, "X11 connection error: {error}"),
            Self::Reply(error) => write!(formatter, "X11 reply error: {error}"),
            Self::InvalidScreenIndex(index) => {
                write!(formatter, "X11 screen index {index} is invalid")
            }
            Self::InvalidClientListProperty => {
                write!(
                    formatter,
                    "_NET_CLIENT_LIST is not a 32-bit WINDOW property"
                )
            }
        }
    }
}

impl Error for X11SourceDiscoveryError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Connect(error) => Some(error),
            Self::Connection(error) => Some(error),
            Self::Reply(error) => Some(error),
            Self::InvalidScreenIndex(_) | Self::InvalidClientListProperty => None,
        }
    }
}

impl From<ConnectError> for X11SourceDiscoveryError {
    fn from(error: ConnectError) -> Self {
        Self::Connect(error)
    }
}

impl From<ConnectionError> for X11SourceDiscoveryError {
    fn from(error: ConnectionError) -> Self {
        Self::Connection(error)
    }
}

impl From<ReplyError> for X11SourceDiscoveryError {
    fn from(error: ReplyError) -> Self {
        Self::Reply(error)
    }
}

/// Lists the desktop root and currently discoverable X11 client windows.
///
/// A client window that disappears or becomes unreadable after `_NET_CLIENT_LIST`
/// is read is skipped so that a transient window does not invalidate the whole list.
pub fn list_x11_capture_sources() -> Result<Vec<X11CaptureSource>, X11SourceDiscoveryError> {
    let (connection, screen_index) = x11rb::connect(None)?;

    let screen = connection
        .setup()
        .roots
        .get(screen_index)
        .ok_or(X11SourceDiscoveryError::InvalidScreenIndex(screen_index))?;

    let root = screen.root;
    let atoms = Atoms::load(&connection)?;

    let mut sources = vec![X11CaptureSource {
        id: root,
        kind: X11CaptureSourceKind::Desktop,
        pid: None,
        width: screen.width_in_pixels,
        height: screen.height_in_pixels,
        title: "Desktop".to_owned(),
    }];

    for window in client_windows(&connection, root, &atoms)? {
        if let Ok(source) = describe_window(&connection, window, &atoms) {
            sources.push(source);
        }
    }

    Ok(sources)
}

struct Atoms {
    net_client_list: Atom,
    net_wm_name: Atom,
    net_wm_pid: Atom,
    utf8_string: Atom,
}

impl Atoms {
    fn load(connection: &RustConnection) -> Result<Self, X11SourceDiscoveryError> {
        Ok(Self {
            net_client_list: intern_atom(connection, b"_NET_CLIENT_LIST")?,
            net_wm_name: intern_atom(connection, b"_NET_WM_NAME")?,
            net_wm_pid: intern_atom(connection, b"_NET_WM_PID")?,
            utf8_string: intern_atom(connection, b"UTF8_STRING")?,
        })
    }
}

fn intern_atom(connection: &RustConnection, name: &[u8]) -> Result<Atom, X11SourceDiscoveryError> {
    Ok(connection.intern_atom(false, name)?.reply()?.atom)
}

fn client_windows(
    connection: &RustConnection,
    root: Window,
    atoms: &Atoms,
) -> Result<Vec<Window>, X11SourceDiscoveryError> {
    let reply = connection
        .get_property(
            false,
            root,
            atoms.net_client_list,
            AtomEnum::WINDOW,
            0,
            MAX_CLIENT_WINDOWS,
        )?
        .reply()?;

    let windows = reply
        .value32()
        .ok_or(X11SourceDiscoveryError::InvalidClientListProperty)?;

    Ok(windows.collect())
}

fn describe_window(
    connection: &RustConnection,
    window: Window,
    atoms: &Atoms,
) -> Result<X11CaptureSource, X11SourceDiscoveryError> {
    let geometry = connection.get_geometry(window)?.reply()?;

    Ok(X11CaptureSource {
        id: window,
        kind: X11CaptureSourceKind::Window,
        pid: window_pid(connection, window, atoms)?,
        width: geometry.width,
        height: geometry.height,
        title: window_title(connection, window, atoms)?,
    })
}

fn window_pid(
    connection: &RustConnection,
    window: Window,
    atoms: &Atoms,
) -> Result<Option<u32>, X11SourceDiscoveryError> {
    let reply = connection
        .get_property(false, window, atoms.net_wm_pid, AtomEnum::CARDINAL, 0, 1)?
        .reply()?;

    Ok(reply.value32().and_then(|mut values| values.next()))
}

fn window_title(
    connection: &RustConnection,
    window: Window,
    atoms: &Atoms,
) -> Result<String, X11SourceDiscoveryError> {
    let net_wm_name = connection
        .get_property(
            false,
            window,
            atoms.net_wm_name,
            atoms.utf8_string,
            0,
            MAX_TEXT_LENGTH,
        )?
        .reply()?;

    if !net_wm_name.value.is_empty() {
        return Ok(String::from_utf8_lossy(&net_wm_name.value).into_owned());
    }

    let wm_name = connection
        .get_property(
            false,
            window,
            AtomEnum::WM_NAME,
            AtomEnum::STRING,
            0,
            MAX_TEXT_LENGTH,
        )?
        .reply()?;

    if wm_name.value.is_empty() {
        return Ok("<untitled>".to_owned());
    }

    Ok(String::from_utf8_lossy(&wm_name.value).into_owned())
}
