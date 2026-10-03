use std::fs::File;
use std::os::fd::{AsRawFd, FromRawFd};

use mio::unix::SourceFd;
use nix::pty::openpty;
use nix::sys::termios::{self, LocalFlags, SetArg};

use super::*;
use crate::SizeInfo;
use crate::local_tty::unix::pty_echo_enabled;
use crate::local_tty::{ChildEvent, EventedPty, EventedReadWrite, mio_channel};
use crate::model::blockgrid::BlockGrid;
use crate::model::secrets::ObfuscateSecrets;

impl ActiveTerminal for BlockGrid {
    fn exit(&mut self, _: ExitReason) {}

    fn input_reporting_block(&self) -> Option<BlockId> {
        (!self.started()).then(|| "prompt".to_owned().into())
    }
}

struct TestPty(File);

impl EventedReadWrite for TestPty {
    type Reader = File;
    type Writer = File;

    fn register(&mut self, poll: &mio::Poll, interest: Interest) -> io::Result<()> {
        poll.registry()
            .register(&mut SourceFd(&self.0.as_raw_fd()), PTY_TOKEN, interest)
    }
    fn reregister(&mut self, poll: &mio::Poll, interest: Interest) -> io::Result<()> {
        poll.registry()
            .reregister(&mut SourceFd(&self.0.as_raw_fd()), PTY_TOKEN, interest)
    }
    fn deregister(&mut self, poll: &mio::Poll) -> io::Result<()> {
        poll.registry()
            .deregister(&mut SourceFd(&self.0.as_raw_fd()))
    }
    fn reader(&mut self) -> &mut File {
        &mut self.0
    }
    fn writer(&mut self) -> &mut File {
        &mut self.0
    }
    fn read_token(&self) -> mio::Token {
        PTY_TOKEN
    }
    fn write_token(&self) -> mio::Token {
        PTY_TOKEN
    }
}

impl EventedPty for TestPty {
    fn echo_enabled(&self) -> io::Result<bool> {
        pty_echo_enabled(&self.0)
    }
    fn child_event_token(&self) -> mio::Token {
        SIGNALS_TOKEN
    }
    fn next_child_event(&mut self) -> Option<ChildEvent> {
        None
    }
    fn on_resize(&mut self, _: &SizeInfo) {}
    fn kill(self) -> anyhow::Result<()> {
        Ok(())
    }
}

fn fixture() -> (
    EventLoop<TestPty, BlockGrid>,
    mio_channel::Sender<Message>,
    File,
) {
    let ends = openpty(None, None).unwrap();
    let master = unsafe { File::from_raw_fd(ends.master) };
    let slave = unsafe { File::from_raw_fd(ends.slave) };
    for file in [&master, &slave] {
        assert_eq!(
            unsafe { libc::fcntl(file.as_raw_fd(), libc::F_SETFL, libc::O_NONBLOCK) },
            0
        );
    }
    let mut attrs = termios::tcgetattr(slave.as_raw_fd()).unwrap();
    termios::cfmakeraw(&mut attrs);
    attrs.local_flags.insert(LocalFlags::ECHO);
    termios::tcsetattr(slave.as_raw_fd(), SetArg::TCSANOW, &attrs).unwrap();
    let grid = BlockGrid::new(
        SizeInfo::new_without_font_metrics(80, 24),
        100,
        ChannelEventListener::new_for_test(),
        ObfuscateSecrets::No,
    );
    let (tx, rx) = mio_channel::channel();
    (
        EventLoop::new(
            Arc::new(FairMutex::new(grid)),
            ChannelEventListener::new_for_test(),
            TestPty(master),
            rx,
        ),
        tx,
        slave,
    )
}

fn disable_echo(slave: &File) {
    let mut attrs = termios::tcgetattr(slave.as_raw_fd()).unwrap();
    attrs.local_flags.remove(LocalFlags::ECHO);
    termios::tcsetattr(slave.as_raw_fd(), SetArg::TCSANOW, &attrs).unwrap();
}

fn read_available(slave: &mut File) -> Vec<u8> {
    let mut bytes = Vec::new();
    let mut buf = [0; 64];
    loop {
        match slave.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => bytes.extend_from_slice(&buf[..n]),
            Err(e) if e.kind() == ErrorKind::WouldBlock => break,
            Err(e) => panic!("{e}"),
        }
    }
    bytes
}

fn reporting() -> Writing {
    Writing::reporting(
        *b"\x1bi",
        "prompt".to_owned().into(),
        async_channel::bounded(1).0,
    )
}

#[test]
fn reporting_waits_for_real_termios_without_consuming_output() {
    let (mut event_loop, _, mut slave) = fixture();
    assert!(event_loop.pty.echo_enabled().unwrap());
    let mut state = State::default();
    state.write_list.push_back(reporting());
    let mut can_write = true;
    event_loop.pty_write(&mut state, &mut can_write).unwrap();
    assert!(!can_write);
    assert!(state.reporting_retry_at.is_some());
    assert!(read_available(&mut slave).is_empty());
    slave.write_all(b"prefix ^[i literal\n").unwrap();
    let mut can_read = true;
    event_loop
        .pty_read(&mut state, &mut [0; READ_BUFFER_SIZE], &mut can_read)
        .unwrap();
    disable_echo(&slave);
    assert!(!event_loop.pty.echo_enabled().unwrap());
    event_loop.pty_write(&mut state, &mut can_write).unwrap();
    assert_eq!(read_available(&mut slave), b"\x1bi");
    assert!(!state.needs_write());
}

#[test]
fn idle_poll_retries_and_discards_expired_reporting_without_losing_following_input() {
    for turn_echo_off in [true, false] {
        let (event_loop, tx, mut slave) = fixture();
        let thread = event_loop.spawn();
        tx.send(Message::InputReportingKey {
            key: *b"\x1bi",
            block: "prompt".to_owned().into(),
            done: async_channel::bounded(1).0,
        })
        .unwrap();
        tx.send(Message::Input(b"following".to_vec().into()))
            .unwrap();
        thread::sleep(Duration::from_millis(50));
        assert!(read_available(&mut slave).is_empty());
        if turn_echo_off {
            disable_echo(&slave);
        }
        let start = Instant::now();
        let mut bytes = Vec::new();
        while bytes.len() < 9 && start.elapsed() < REPORTING_TIMEOUT + Duration::from_secs(1) {
            bytes.extend(read_available(&mut slave));
            thread::sleep(Duration::from_millis(5));
        }
        tx.send(Message::Shutdown).unwrap();
        thread.join().unwrap();
        assert_eq!(
            bytes,
            if turn_echo_off {
                b"\x1bifollowing".as_slice()
            } else {
                b"following".as_slice()
            }
        );
    }
}

#[test]
fn stale_prompt_cancels_only_unwritten_reporting_and_partial_keys_finish() {
    let (mut event_loop, _, mut slave) = fixture();
    disable_echo(&slave);
    event_loop.terminal.lock().start();
    let mut state = State::default();
    state.write_list.push_back(reporting());
    state
        .write_list
        .push_back(Writing::new(b"following".to_vec().into()));
    event_loop.pty_write(&mut state, &mut true).unwrap();
    assert_eq!(read_available(&mut slave), b"following");

    let mut partial = reporting();
    partial.advance(1);
    assert_eq!(
        partial.reporting_action(None, Ok(true), Instant::now() + REPORTING_TIMEOUT),
        ReportingAction::Write
    );
    let pending = reporting();
    assert_eq!(
        pending.reporting_action(
            Some("different-prompt".to_owned().into()),
            Ok(false),
            Instant::now()
        ),
        ReportingAction::Discard
    );
    assert_eq!(
        pending.reporting_action(
            Some("prompt".to_owned().into()),
            Err(io::Error::other("termios failed")),
            Instant::now()
        ),
        ReportingAction::Wait
    );
}

struct BusyReader(Arc<std::sync::atomic::AtomicBool>);
impl Read for BusyReader {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        if !self.0.load(std::sync::atomic::Ordering::Relaxed) {
            return Err(ErrorKind::WouldBlock.into());
        }
        bytes.fill(b'x');
        Ok(bytes.len())
    }
}
struct BusyPty {
    pty: TestPty,
    reader: BusyReader,
}
impl EventedReadWrite for BusyPty {
    type Reader = BusyReader;
    type Writer = File;
    fn register(&mut self, poll: &mio::Poll, interest: Interest) -> io::Result<()> {
        self.pty.register(poll, interest)
    }
    fn reregister(&mut self, poll: &mio::Poll, interest: Interest) -> io::Result<()> {
        self.pty.reregister(poll, interest)
    }
    fn deregister(&mut self, poll: &mio::Poll) -> io::Result<()> {
        self.pty.deregister(poll)
    }
    fn reader(&mut self) -> &mut BusyReader {
        &mut self.reader
    }
    fn writer(&mut self) -> &mut File {
        self.pty.writer()
    }
    fn read_token(&self) -> mio::Token {
        PTY_TOKEN
    }
    fn write_token(&self) -> mio::Token {
        PTY_TOKEN
    }
}
impl EventedPty for BusyPty {
    fn echo_enabled(&self) -> io::Result<bool> {
        self.pty.echo_enabled()
    }
    fn child_event_token(&self) -> mio::Token {
        SIGNALS_TOKEN
    }
    fn next_child_event(&mut self) -> Option<ChildEvent> {
        None
    }
    fn on_resize(&mut self, _: &SizeInfo) {}
    fn kill(self) -> anyhow::Result<()> {
        Ok(())
    }
}

#[test]
fn an_always_readable_pty_cannot_starve_the_reporting_deadline() {
    let (event_loop, tx, mut slave) = fixture();
    let running = Arc::new(std::sync::atomic::AtomicBool::new(true));
    let busy_pty = BusyPty {
        pty: event_loop.pty,
        reader: BusyReader(running.clone()),
    };
    let busy_loop = EventLoop::new(
        event_loop.terminal,
        event_loop.event_listener,
        busy_pty,
        event_loop.rx,
    );
    let (done, received) = async_channel::bounded(1);
    tx.send(Message::InputReportingKey {
        key: *b"\x1bi",
        block: "prompt".to_owned().into(),
        done,
    })
    .unwrap();
    let thread = busy_loop.spawn();
    // Let the first writable event gate the request before making reads permanently ready.
    thread::sleep(Duration::from_millis(30));
    slave.write_all(b"x").unwrap();
    let deadline = Instant::now() + REPORTING_TIMEOUT + Duration::from_secs(2);
    let mut outcome = None;
    while Instant::now() < deadline {
        if let Ok(value) = received.try_recv() {
            outcome = Some(value);
            break;
        }
        thread::sleep(Duration::from_millis(5));
    }
    running.store(false, std::sync::atomic::Ordering::Relaxed);
    tx.send(Message::Shutdown).unwrap();
    thread.join().unwrap();
    assert_eq!(
        outcome,
        Some(false),
        "the timeout must fire while every read returns more output"
    );
    assert!(read_available(&mut slave).is_empty());
}
