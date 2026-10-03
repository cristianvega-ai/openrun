/// The operating system a shell session runs on, which can differ from the host OS (for example,
/// a remote shell reached over SSH).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetOS {
    MacOS,
    Linux,
}
