//! This module contains the code path for the [`warp_cli::Command::DumpDebugInfo`] subcommand.
//!
//! This is intended to never be used by a vast majority of users. This is only intended for users
//! who are unable to run Warp and want to provide us, the dev team, with useful debugging
//! information.
use command::blocking::Command;
use warp_core::channel::ChannelState;

pub(crate) fn run() -> anyhow::Result<()> {
    println!("Warp version: {:?}", ChannelState::app_version());

    {
        let uname = collect_output_or_suggest_install("uname -a");
        println!("uname(1) output: {}", uname.trim_end());
    }

    Ok(())
}

fn collect_output_or_suggest_install(full_command: &str) -> String {
    let redirected_command = format!("{full_command} 2>&1");
    let output = Command::new("sh")
        .args(["-c", &redirected_command])
        .output();
    match output {
        Ok(output) => String::from_utf8(output.stdout).unwrap_or_default(),
        Err(err) => err.to_string(),
    }
}
