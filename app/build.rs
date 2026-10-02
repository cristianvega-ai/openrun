// We can use `std::process:Command` here because this is invoked within a build script,
// not within the app binary.
#![allow(clippy::disallowed_types)]

use std::path::{Path, PathBuf};
use std::process::Command;
use std::{env, fs};

use anyhow::Result;
use cfg_aliases::cfg_aliases;
use walkdir::WalkDir;
use warp_util::path::app_target_dir;

fn main() -> Result<()> {
    cfg_aliases! {
        enable_crash_recovery: { target_os = "linux" },
    }

    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=CARGO_CFG_TARGET_OS");
    println!("cargo:rerun-if-env-changed=CARGO_CFG_TARGET_FAMILY");

    let target_os = env::var("CARGO_CFG_TARGET_OS")?;
    let target_family = env::var("CARGO_CFG_TARGET_FAMILY")?;

    add_features(&target_family);

    if target_os == "macos" && target_family != "wasm" {
        println!("cargo:rustc-link-lib=framework=MetalKit");
        println!("cargo:rustc-link-lib=framework=UserNotifications");

        println!("cargo:rerun-if-changed=src/platform/mac/objc/services.h");
        println!("cargo:rerun-if-changed=src/platform/mac/objc/services.m");

        cc::Build::new()
            .file("src/platform/mac/objc/services.m")
            .compile("warp_objc");

        // Build the dock tile plugin
        println!("cargo:rerun-if-changed=DockTilePlugin/WarpDockTilePlugin.m");
        println!("cargo:rerun-if-changed=DockTilePlugin/WarpDockTilePlugin.h");
        println!("cargo:rerun-if-changed=DockTilePlugin/Info.plist");
        println!("cargo:rerun-if-changed=DockTilePlugin/Makefile");

        let min_macos_version = env::var("MACOSX_DEPLOYMENT_TARGET")
            .expect("MACOSX_DEPLOYMENT_TARGET must be set for macos builds");
        let status = Command::new("make")
            .current_dir("DockTilePlugin")
            .env("MACOSX_DEPLOYMENT_TARGET", min_macos_version)
            .status()
            .expect("Failed to build dock tile plugin");
        if !status.success() {
            panic!("Dock tile plugin build failed");
        }

        // Copy the dock tile plugin to the output directory
        let profile = get_build_profile_name();
        let target_dir = app_target_dir(&profile).expect("Failed to get app target directory");
        let plugin_src = Path::new("DockTilePlugin/WarpDockTilePlugin.docktileplugin");
        let plugin_dst = target_dir.join("WarpDockTilePlugin.docktileplugin");

        if !status.success() {
            fs::remove_dir_all(plugin_src).expect("Failed to clean up plugin directory");
            panic!("Dock tile plugin build failed");
        }

        if plugin_src.exists() {
            fs::remove_dir_all(&plugin_dst).ok(); // Remove existing if any
            fs::create_dir_all(&plugin_dst).expect("Failed to create plugin directory");

            // Copy the plugin directory recursively
            for entry in WalkDir::new(plugin_src) {
                let entry = entry.expect("Failed to read plugin directory");
                let path = entry.path();
                let relative = path
                    .strip_prefix(plugin_src)
                    .expect("Failed to strip path prefix");
                let target = plugin_dst.join(relative);

                if path.is_dir() {
                    fs::create_dir_all(target).expect("Failed to create plugin subdirectory");
                } else {
                    fs::copy(path, target).expect("Failed to copy plugin file");
                }
            }

            // Clean up the source plugin directory after copying
            fs::remove_dir_all(plugin_src).expect("Failed to clean up plugin directory");
        }
    }

    Ok(())
}

fn get_build_profile_name() -> String {
    // The profile name is always the 3rd last part of the path (with 1 based indexing).
    // e.g. /code/core/target/cli/build/my-build-info-9f91ba6f99d7a061/out
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR must be set"));
    out_dir
        .ancestors()
        .nth(3)
        .and_then(Path::file_name)
        .expect("could not get profile name")
        .to_string_lossy()
        .into_owned()
}

fn add_features(target_family: &str) {
    if target_family != "wasm" {
        println!("cargo:rustc-cfg=feature=\"local_fs\"");
        println!("cargo:rustc-cfg=feature=\"local_tty\"");
    }
}
