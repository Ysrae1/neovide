//! Asynchronous RPC commands for route-owned native child views.
//! AppKit objects are created and released only on the existing UI thread.
use crate::{bridge::NeovimWriter, image_preview::ImageView};
use nvim_rs::Neovim;
use rmpv::Value;

#[derive(Clone, Debug, PartialEq)]
pub enum NativeCommand {
    Open { id: u64, kind: String, source: String },
    Show(u64, ImageView),
    Close(u64),
    Action { id: u64, action: String, value: f64 },
    PdfSync { id: u64, page: u64, x: f64, y: f64, width: f64, height: f64 },
}

impl NativeCommand {
    pub fn parse(name: &str, args: &[Value]) -> Result<Self, String> {
        let id = args
            .first()
            .and_then(Value::as_u64)
            .filter(|id| *id > 0)
            .ok_or("Preview needs a positive id")?;
        Ok(match name {
            "neovide.preview.open" => {
                let kind = args
                    .get(1)
                    .and_then(Value::as_str)
                    .filter(|k| ["audio", "video", "web", "pdf"].contains(k))
                    .ok_or("Preview kind must be audio, video, web or pdf")?;
                let source = args
                    .get(2)
                    .and_then(Value::as_str)
                    .filter(|p| !p.is_empty() && !p.contains('\0'))
                    .ok_or("Preview source is missing or invalid")?;
                Self::Open { id, kind: kind.into(), source: source.into() }
            }
            "neovide.preview.show" => {
                Self::Show(id, ImageView::parse(args.get(1).ok_or("Missing viewport")?)?)
            }
            "neovide.preview.close" => Self::Close(id),
            "neovide.preview.pdf_sync" => {
                let fields = args.get(1).and_then(Value::as_map).ok_or("Missing PDF sync point")?;
                let get = |key: &str| {
                    fields
                        .iter()
                        .find(|(name, _)| name.as_str() == Some(key))
                        .map(|(_, value)| value)
                };
                let page = get("page")
                    .and_then(Value::as_u64)
                    .filter(|p| *p > 0 && *p <= 1_000_000)
                    .ok_or("Invalid PDF sync page")?;
                let coordinate = |key: &str, default: Option<f64>| -> Result<f64, String> {
                    let number = get(key)
                        .and_then(Value::as_f64)
                        .or(default)
                        .ok_or_else(|| format!("Missing PDF sync {key}"))?;
                    if !number.is_finite() || !(0.0..=1_000_000.0).contains(&number) {
                        return Err(format!("Invalid PDF sync {key}"));
                    }
                    Ok(number)
                };
                Self::PdfSync {
                    id,
                    page,
                    x: coordinate("x", None)?,
                    y: coordinate("y", None)?,
                    width: coordinate("width", Some(0.0))?,
                    height: coordinate("height", Some(0.0))?,
                }
            }
            "neovide.preview.action" => {
                let action = args
                    .get(1)
                    .and_then(Value::as_str)
                    .filter(|a| {
                        [
                            "play", "pause", "toggle", "seek", "volume", "status", "reload",
                            "zoom", "focus", "blur", "back", "forward", "page", "next", "previous",
                            "fit",
                        ]
                        .contains(a)
                    })
                    .ok_or("Unknown preview action")?;
                let value = match args.get(2) {
                    None | Some(Value::Nil) => 0.0,
                    Some(value) => value
                        .as_f64()
                        .filter(|n| n.is_finite())
                        .ok_or("Preview value must be finite")?,
                };
                Self::Action { id, action: action.into(), value }
            }
            _ => return Err("Unknown native preview command".into()),
        })
    }
}

pub async fn report_status(nvim: Neovim<NeovimWriter>, id: u64, json: String) {
    // Never await this from the notification handler or AppKit event loop.
    let _ = nvim.exec_lua(
        "local a={...}; vim.schedule(function() local ok,m=pcall(require,'config.media.preview'); if ok then m.on_status(unpack(a)) end end)",
        vec![id.into(), json.into()],
    ).await;
}

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::NativePreviews;
#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
pub use windows::NativePreviews;

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn protocol_rejects_bad_sources_actions_and_nonfinite_values() {
        assert!(
            NativeCommand::parse("neovide.preview.open", &[1.into(), "web".into(), "a\0b".into()])
                .is_err()
        );
        assert!(
            NativeCommand::parse("neovide.preview.open", &[0.into(), "video".into(), "x".into()])
                .is_err()
        );
        assert!(
            NativeCommand::parse(
                "neovide.preview.action",
                &[1.into(), "seek".into(), f64::NAN.into()]
            )
            .is_err()
        );
        assert!(
            NativeCommand::parse("neovide.preview.action", &[1.into(), "execute".into()]).is_err()
        );
        assert!(matches!(
            NativeCommand::parse(
                "neovide.preview.open",
                &[1.into(), "audio".into(), "/tmp/a b.wav".into()]
            ),
            Ok(NativeCommand::Open { .. })
        ));
    }
    #[test]
    fn pdf_sync_uses_finite_page_points() {
        let point = |x: f64| {
            Value::Map(vec![
                ("page".into(), 2.into()),
                ("x".into(), x.into()),
                ("y".into(), 72.5.into()),
            ])
        };
        assert!(matches!(
            NativeCommand::parse("neovide.preview.pdf_sync", &[1.into(), point(12.0)]),
            Ok(NativeCommand::PdfSync { page: 2, .. })
        ));
        assert!(
            NativeCommand::parse("neovide.preview.pdf_sync", &[1.into(), point(f64::NAN)]).is_err()
        );
        assert!(
            NativeCommand::parse("neovide.preview.pdf_sync", &[1.into(), point(-1.0)]).is_err()
        );
    }
}
