#[cfg(unix)]
mod unix {
    use std::collections::HashMap;
    use std::fs::{self, File, OpenOptions};
    use std::io::Write as _;
    use std::os::unix::fs::OpenOptionsExt as _;
    use std::path::Path;
    use std::time::Duration;

    use async_io::Timer;
    use futures_util::future::{AbortHandle, Abortable, Aborted};
    use instant::Instant;
    use nix::sys::signal::kill;
    use nix::sys::stat::Mode;
    use nix::unistd::{Pid, mkfifo};

    use super::super::*;
    use crate::terminal::model::session::command_executor::test_support::session_shell;

    const TIMEOUT: Duration = Duration::from_secs(5);

    fn executor() -> LocalCommandExecutor {
        LocalCommandExecutor::new(Some("/bin/bash".into()), ShellType::Bash)
    }

    fn descendant_command() -> &'static str {
        "/bin/sh -c 'printf %s \"$$\" > \"$READY_FILE\"; \
         IFS= read -r _ < \"$RELEASE_FIFO\"; \
         printf descendant-ran > \"$SIDE_EFFECT_FILE\"' \
         </dev/null >/dev/null 2>&1 & wait"
    }

    fn detached_descendant_command() -> &'static str {
        "/bin/sh -c 'printf %s \"$$\" > \"$READY_FILE\"; \
         IFS= read -r _ < \"$RELEASE_FIFO\"; \
         printf descendant-ran > \"$SIDE_EFFECT_FILE\"' \
         </dev/null >/dev/null 2>&1 &"
    }

    fn command_environment(temp_dir: &Path) -> HashMap<String, String> {
        HashMap::from([
            (
                "READY_FILE".into(),
                temp_dir.join("ready").to_string_lossy().into_owned(),
            ),
            (
                "RELEASE_FIFO".into(),
                temp_dir.join("release-fifo").to_string_lossy().into_owned(),
            ),
            (
                "SIDE_EFFECT_FILE".into(),
                temp_dir.join("side-effect").to_string_lossy().into_owned(),
            ),
        ])
    }

    fn create_release_fifo(temp_dir: &Path) -> File {
        let path = temp_dir.join("release-fifo");
        mkfifo(&path, Mode::S_IRUSR | Mode::S_IWUSR).expect("create release FIFO");
        OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(path)
            .expect("open release FIFO")
    }

    async fn wait_for_file(path: &Path) {
        let deadline = Instant::now() + TIMEOUT;
        while !path.exists() {
            assert!(
                Instant::now() < deadline,
                "timed out waiting for {}",
                path.display()
            );
            Timer::after(Duration::from_millis(10)).await;
        }
    }
    async fn wait_for_process_exit(pid: Pid) {
        let deadline = Instant::now() + TIMEOUT;
        loop {
            match kill(pid, None) {
                Err(nix::errno::Errno::ESRCH) => return,
                Ok(()) | Err(nix::errno::Errno::EPERM) => {}
                Err(error) => panic!("failed to inspect descendant {pid}: {error}"),
            }
            assert!(
                Instant::now() < deadline,
                "timed out waiting for descendant {pid} to exit"
            );
            Timer::after(Duration::from_millis(10)).await;
        }
    }

    async fn wait_for_descendant_pid(path: &Path) -> Pid {
        let deadline = Instant::now() + TIMEOUT;
        loop {
            if let Ok(contents) = fs::read_to_string(path)
                && let Ok(pid) = contents.parse()
            {
                return Pid::from_raw(pid);
            }
            assert!(
                Instant::now() < deadline,
                "timed out waiting for descendant PID in {}",
                path.display()
            );
            Timer::after(Duration::from_millis(10)).await;
        }
    }

    #[test]
    fn dropping_command_future_kills_descendant_process() {
        futures_lite::future::block_on(async {
            let temp_dir = tempfile::tempdir().expect("create temp dir");
            let mut release_fifo = create_release_fifo(temp_dir.path());
            let ready_file = temp_dir.path().join("ready");
            let side_effect_file = temp_dir.path().join("side-effect");
            let executor = executor();
            let (abort_handle, abort_registration) = AbortHandle::new_pair();
            let command = executor.execute_local_command(
                descendant_command(),
                None,
                Some(command_environment(temp_dir.path())),
                ExecuteCommandOptions::default(),
            );
            let command = Abortable::new(command, abort_registration);

            let task_executor = async_executor::LocalExecutor::new();
            task_executor
                .run(async {
                    let command_task = task_executor.spawn(command);
                    let descendant_pid = wait_for_descendant_pid(&ready_file).await;

                    abort_handle.abort();
                    assert!(matches!(command_task.await, Err(Aborted)));

                    writeln!(release_fifo, "continue").expect("release descendant");
                    wait_for_process_exit(descendant_pid).await;
                    assert!(
                        !side_effect_file.exists(),
                        "canceled descendant unexpectedly created {}",
                        side_effect_file.display()
                    );
                })
                .await;
        });
    }

    #[test]
    fn cancel_active_commands_kills_descendant_process() {
        futures_lite::future::block_on(async {
            let temp_dir = tempfile::tempdir().expect("create temp dir");
            let mut release_fifo = create_release_fifo(temp_dir.path());
            let ready_file = temp_dir.path().join("ready");
            let side_effect_file = temp_dir.path().join("side-effect");
            let executor = executor();
            let command = executor.execute_local_command(
                descendant_command(),
                None,
                Some(command_environment(temp_dir.path())),
                ExecuteCommandOptions::default(),
            );

            let task_executor = async_executor::LocalExecutor::new();
            task_executor
                .run(async {
                    let command_task = task_executor.spawn(command);
                    let descendant_pid = wait_for_descendant_pid(&ready_file).await;

                    executor.cancel_active_commands();
                    let _ = command_task.await;

                    writeln!(release_fifo, "continue").expect("release descendant");
                    wait_for_process_exit(descendant_pid).await;
                    assert!(
                        !side_effect_file.exists(),
                        "canceled descendant unexpectedly created {}",
                        side_effect_file.display()
                    );
                })
                .await;
        });
    }

    #[test]
    fn completed_command_is_not_canceled_later() {
        futures_lite::future::block_on(async {
            let temp_dir = tempfile::tempdir().expect("create temp dir");
            let mut release_fifo = create_release_fifo(temp_dir.path());
            let ready_file = temp_dir.path().join("ready");
            let side_effect_file = temp_dir.path().join("side-effect");
            let executor = executor();

            executor
                .execute_local_command(
                    detached_descendant_command(),
                    None,
                    Some(command_environment(temp_dir.path())),
                    ExecuteCommandOptions::default(),
                )
                .await
                .expect("complete wrapper command");
            wait_for_file(&ready_file).await;

            executor.cancel_active_commands();
            writeln!(release_fifo, "continue").expect("release descendant");
            wait_for_file(&side_effect_file).await;
            assert_eq!(
                fs::read_to_string(side_effect_file).expect("read side effect"),
                "descendant-ran"
            );
        });
    }

    /// Runs `command` the way a completion generator of a session of `shell_type` is run: through
    /// the production executor, which starts the session's own shell with `-c` and an empty
    /// `PATH`, not `sh`. Returns the standard output.
    fn run_generator_command(
        shell_path: std::path::PathBuf,
        shell_type: ShellType,
        directory: &Path,
        command: &str,
    ) -> String {
        let executor = LocalCommandExecutor::new(Some(shell_path), shell_type);
        let environment = HashMap::from([
            ("PATH".to_owned(), directory.to_string_lossy().into_owned()),
            ("HOME".to_owned(), directory.to_string_lossy().into_owned()),
        ]);
        let output = futures_lite::future::block_on(executor.execute_local_command(
            command,
            directory.to_str(),
            Some(environment),
            ExecuteCommandOptions::default(),
        ))
        .expect("run the command");
        String::from_utf8_lossy(&output.stdout).into_owned()
    }

    #[test]
    fn a_fish_session_runs_its_generator_commands_in_fish() {
        let Some(fish) = session_shell("fish", "OPENRUN_TEST_FISH") else {
            return;
        };
        let temp_dir = tempfile::tempdir().expect("create temp dir");
        let dir = temp_dir.path();
        let run =
            |command: &str| run_generator_command(fish.clone(), ShellType::Fish, dir, command);

        // The command string is read by fish: `$FISH_VERSION` exists only there, and `sh` would
        // print an empty line.
        let version = run("echo $FISH_VERSION");
        assert!(
            version.trim().starts_with(|c: char| c.is_ascii_digit()),
            "not run by fish: {version:?}"
        );

        // A word quoted the way the completion engine's generators quote it (`'` becomes `'\''`)
        // stays one word in fish, so the rest of it is not run.
        let quoted = format!("it'\\''s; true > {}/safe #", dir.display());
        let output = run(&format!("printf %s '{quoted}'"));
        assert_eq!(output, format!("it's; true > {}/safe #", dir.display()));
        assert!(!dir.join("safe").exists());

        // With a backslash before the quote the same quoting ends early in fish, and what follows
        // runs. This is why the token gate refuses a backslash for a generator that quotes.
        let breakout = format!("x\\'; true > {}/breakout #", dir.display());
        run(&format!("printf %s '{}'", breakout.replace('\'', "'\\''")));
        assert!(
            dir.join("breakout").exists(),
            "fish was expected to run the text after a backslash-quote"
        );
    }

    #[test]
    fn a_powershell_session_runs_its_generator_commands_in_pwsh() {
        let Some(pwsh) = session_shell("pwsh", "OPENRUN_TEST_PWSH") else {
            return;
        };
        let temp_dir = tempfile::tempdir().expect("create temp dir");
        let dir = temp_dir.path();
        let run = |command: &str| {
            run_generator_command(pwsh.clone(), ShellType::PowerShell, dir, command)
        };

        // The command string is read by PowerShell: `$PSVersionTable` exists only there.
        let version = run("Write-Output $PSVersionTable.PSVersion.Major");
        assert_eq!(version.trim(), "7", "not run by PowerShell 7: {version:?}");

        // The POSIX quoting of the generators (`'` becomes `'\''`) does not keep a word inside
        // the quotes in PowerShell, so the text after the quote runs. This is why a generator is
        // given only inert words in a PowerShell session.
        let quoted = format!("x'; Set-Content {}/breakout 1 #", dir.display());
        run(&format!("Write-Output '{}'", quoted.replace('\'', "'\\''")));
        assert!(
            dir.join("breakout").exists(),
            "PowerShell was expected to run the text after a POSIX-quoted quote"
        );
    }
}
