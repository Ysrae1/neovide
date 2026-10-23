use anyhow::{Context, Result};
use nvim_rs::{Neovim, call_args, rpc::IntoVal};
use rmpv::Value;

use super::{
    api_info::{ApiInformation, parse_api_info},
    nvim_dict, nvim_exec_output,
};
use crate::{
    bridge::NeovimWriter,
    settings::{SettingLocation, Settings, config::config_path},
    version::BUILD_VERSION,
};

const INIT_LUA: &str = include_str!("../../lua/init.lua");

pub async fn get_api_information(nvim: &Neovim<NeovimWriter>) -> Result<ApiInformation> {
    // Retrieve the channel number for communicating with neovide.
    let api_info = nvim.get_api_info().await.context("Error getting API info")?;

    let version = nvim_exec_output(nvim, "version").await?;
    log::info!("Neovim version: {version:#?}");
    let version_str = version.lines().next().unwrap_or_default();
    parse_api_info(&api_info, version_str).context("Failed to parse Neovim api information")
}

pub async fn setup_neovide_specific_state(
    nvim: &Neovim<NeovimWriter>,
    remote: bool,
    api_information: &ApiInformation,
    settings: &Settings,
) -> Result<()> {
    // Set variable indicating to user config that neovide is being used.
    nvim.set_var("neovide", Value::from(true))
        .await
        .context("Could not communicate with neovim process")?;
    nvim.exec_lua(
        "local supported, version = ...; \
         vim.g.neovide_window_drag_supported = supported; \
         vim.g.neovide_window_drag_version = version; \
         vim.api.nvim_exec_autocmds('User', { pattern = 'NeovideWindowDragReady', modeline = false })",
        call_args![
            cfg!(target_os = "windows")
                && settings.get::<crate::CmdLineSettings>().frame == crate::frame::Frame::None,
            if cfg!(target_os = "windows")
                && settings.get::<crate::CmdLineSettings>().frame == crate::frame::Frame::None
                && api_information.version.has_version(0, 12, 0, Some(1264))
            { 2 } else { 1 }
        ],
    )
    .await
    .context("Could not advertise frameless tabline dragging")?;
    nvim.set_var("neovide_native_glass", Value::from(cfg!(target_os = "macos")))
        .await
        .context("Could not advertise native macOS glass material")?;
    nvim.set_var("neovide_native_notebook", Value::from(true))
        .await
        .context("Could not advertise native Notebook frames")?;
    nvim.set_var("neovide_native_notebook_viewport", Value::from(true))
        .await
        .context("Could not advertise Notebook text viewport support")?;
    nvim.set_var("neovide_native_notebook_footer", Value::from(true))
        .await
        .context("Could not advertise Notebook footer border gaps")?;
    nvim.set_var("neovide_native_image", Value::from(true))
        .await
        .context("Could not advertise native image preview")?;
    nvim.set_var("neovide_native_image_anchor", Value::from(true))
        .await
        .context("Could not advertise owner-anchored native images")?;

    // Linux dependencies and display backend are runtime capabilities. Probe on
    // a worker so importing system GI typelibs never blocks the bridge/UI loop.
    #[cfg(target_os = "linux")]
    let linux_preview_kinds =
        tokio::task::spawn_blocking(|| crate::native_preview::linux_available_kinds().to_vec())
            .await
            .unwrap_or_default();
    #[cfg(not(target_os = "linux"))]
    let linux_preview_kinds: Vec<String> = Vec::new();
    nvim.set_var(
        "neovide_native_preview",
        Value::from(
            cfg!(any(target_os = "macos", target_os = "windows"))
                || !linux_preview_kinds.is_empty(),
        ),
    )
    .await
    .context("Could not advertise native media/web preview")?;
    // Capabilities are per kind: Windows embeds PDF, Linux reports the installed
    // WebKitGTK/Poppler kinds only on a compatible X11 session.
    nvim.set_var(
        "neovide_native_preview_kinds",
        Value::Array(
            ["audio", "video", "web", "pdf"]
                .into_iter()
                .filter(|kind| {
                    cfg!(target_os = "macos")
                        || (cfg!(target_os = "windows") && *kind == "pdf")
                        || linux_preview_kinds.iter().any(|supported| supported == kind)
                })
                .map(Value::from)
                .collect(),
        ),
    )
    .await
    .context("Could not advertise native preview kinds")?;
    nvim.set_var(
        "neovide_native_pdf_synctex",
        Value::from(
            cfg!(any(target_os = "macos", target_os = "windows"))
                || linux_preview_kinds.iter().any(|kind| kind == "pdf"),
        ),
    )
    .await
    .context("Could not advertise PDF coordinate synchronization")?;

    nvim.exec2("runtime! ginit.vim", nvim_dict!())
        .await
        .context("Error encountered in ginit.vim ")?;

    // Set details about the neovide version.
    nvim.set_client_info(
        "neovide",
        nvim_dict! {
            "major" =>env!("CARGO_PKG_VERSION_MAJOR"),
            "minor" =>env!("CARGO_PKG_VERSION_MINOR"),
            "patch" =>env!("CARGO_PKG_VERSION_PATCH")
        },
        "ui",
        nvim_dict! {},
        nvim_dict! {},
    )
    .await
    .context("Error setting client info")?;

    let register_clipboard = remote;
    let register_right_click = cfg!(target_os = "windows");

    let setting_locations = settings.setting_locations();
    let global_variable_settings = setting_locations
        .iter()
        .filter_map(|s| match s {
            SettingLocation::NeovideGlobal(setting) => Some(Value::from(setting.to_owned())),
            _ => None,
        })
        .collect::<Vec<_>>();
    let option_settings = setting_locations
        .iter()
        .filter_map(|s| match s {
            SettingLocation::NeovimOption(setting) => Some(Value::from(setting.to_owned())),
            _ => None,
        })
        .collect::<Vec<_>>();

    nvim.exec_lua(
        INIT_LUA,
        call_args![nvim_dict! {
            "neovide_channel_id" => api_information.channel,
            "neovide_version" => BUILD_VERSION,
            "config_path" => config_path().to_string_lossy().into_owned(),
            "register_clipboard" => register_clipboard,
            "register_right_click" => register_right_click,
            "remote" => remote,
            "global_variable_settings" => global_variable_settings,
            "option_settings" => option_settings,
        }],
    )
    .await
    .context("Error when running Neovide init.lua")?;

    nvim.exec_lua(include_str!("../../lua/highlight_roles.lua"), call_args![])
        .await
        .context("Error when declaring highlight rendering roles")?;

    nvim.exec_lua(include_str!("../../lua/float_shadow.lua"), call_args![])
        .await
        .context("Error when configuring composed floating-window shadows")?;

    #[cfg(target_os = "macos")]
    nvim.exec_lua(include_str!("../../lua/native_menu.lua"), call_args![])
        .await
        .context("Error when configuring native menu language")?;

    Ok(())
}
