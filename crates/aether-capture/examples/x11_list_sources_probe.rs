#[cfg(target_os = "linux")]
mod linux {
    use std::error::Error;
    use std::io;

    use x11rb::connection::Connection;
    use x11rb::protocol::xproto::{Atom, AtomEnum, ConnectionExt as _, Window};
    use x11rb::rust_connection::RustConnection;

    const MAX_CLIENT_WINDOWS: u32 = 4096;
    const MAX_TEXT_LENGTH: u32 = 1024;

    struct Atoms {
        net_client_list: Atom,
        net_wm_name: Atom,
        net_wm_pid: Atom,
        utf8_string: Atom,
    }

    impl Atoms {
        fn load(connection: &RustConnection) -> Result<Self, Box<dyn Error>> {
            Ok(Self {
                net_client_list: intern_atom(connection, b"_NET_CLIENT_LIST")?,
                net_wm_name: intern_atom(connection, b"_NET_WM_NAME")?,
                net_wm_pid: intern_atom(connection, b"_NET_WM_PID")?,
                utf8_string: intern_atom(connection, b"UTF8_STRING")?,
            })
        }
    }

    struct WindowSource {
        id: Window,
        pid: Option<u32>,
        width: u16,
        height: u16,
        title: String,
    }

    pub fn run() -> Result<(), Box<dyn Error>> {
        let display = std::env::var("DISPLAY").unwrap_or_else(|_| "<not set>".to_owned());

        let (connection, screen_index) = x11rb::connect(None)?;
        let screen = connection
            .setup()
            .roots
            .get(screen_index)
            .ok_or_else(|| io::Error::other("X11 screen index is invalid"))?;

        let root = screen.root;
        let atoms = Atoms::load(&connection)?;

        println!("Aether X11 source discovery probe");
        println!("=================================");
        println!();
        println!("DISPLAY:      {display}");
        println!("screen index: {screen_index}");
        println!("root window:  0x{root:08x}");
        println!();

        println!(
            "[desktop] id=0x{:08x} size={}x{}",
            root, screen.width_in_pixels, screen.height_in_pixels
        );

        println!();

        let windows = client_windows(&connection, root, &atoms)?;

        println!(
            "Window manager reported {} client window(s).",
            windows.len()
        );
        println!();

        let mut listed = 0usize;

        for window in windows {
            match describe_window(&connection, window, &atoms) {
                Ok(source) => {
                    listed += 1;

                    let pid = source
                        .pid
                        .map_or_else(|| "?".to_owned(), |pid| pid.to_string());

                    println!(
                        "[window {listed}] id=0x{:08x} pid={} size={}x{} title={:?}",
                        source.id, pid, source.width, source.height, source.title
                    );
                }
                Err(error) => {
                    eprintln!("[skip] id=0x{window:08x}: {error}");
                }
            }
        }

        println!();
        println!("Listed window sources: {listed}");

        Ok(())
    }

    fn intern_atom(connection: &RustConnection, name: &[u8]) -> Result<Atom, Box<dyn Error>> {
        Ok(connection.intern_atom(false, name)?.reply()?.atom)
    }

    fn client_windows(
        connection: &RustConnection,
        root: Window,
        atoms: &Atoms,
    ) -> Result<Vec<Window>, Box<dyn Error>> {
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
            .ok_or_else(|| io::Error::other("_NET_CLIENT_LIST is not a 32-bit WINDOW property"))?;

        Ok(windows.collect())
    }

    fn describe_window(
        connection: &RustConnection,
        window: Window,
        atoms: &Atoms,
    ) -> Result<WindowSource, Box<dyn Error>> {
        let geometry = connection.get_geometry(window)?.reply()?;

        Ok(WindowSource {
            id: window,
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
    ) -> Result<Option<u32>, Box<dyn Error>> {
        let reply = connection
            .get_property(false, window, atoms.net_wm_pid, AtomEnum::CARDINAL, 0, 1)?
            .reply()?;

        Ok(reply.value32().and_then(|mut values| values.next()))
    }

    fn window_title(
        connection: &RustConnection,
        window: Window,
        atoms: &Atoms,
    ) -> Result<String, Box<dyn Error>> {
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
}

#[cfg(target_os = "linux")]
fn main() {
    if let Err(error) = linux::run() {
        eprintln!("X11 source discovery probe failed: {error}");
        std::process::exit(1);
    }
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("This probe is only available on Linux/X11.");
    std::process::exit(1);
}
