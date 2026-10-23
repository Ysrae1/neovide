//! Bounded, versioned messages from the bundled PDF viewer. No file paths or
//! executable expressions can cross this bridge.
use serde_json::Value;

pub const MAX_MESSAGE: usize = 64 * 1024;

pub fn resource_key<'a>(uri: &'a str, prefix: &str) -> Option<&'a str> {
    let key = uri.strip_prefix(prefix)?;
    if key.is_empty()
        || key.contains(['?', '#', '%', '\\'])
        || key.split('/').any(|part| part.is_empty() || part == "." || part == "..")
    {
        return None;
    }
    Some(key)
}

pub fn viewer_navigation(uri: &str, prefix: &str) -> bool {
    let document = format!("{prefix}viewer.html");
    uri == document || uri.strip_prefix(&document).is_some_and(|tail| tail.starts_with('#'))
}

#[derive(Debug, PartialEq)]
pub enum ViewerEvent {
    Ready { page: u64, pages: u64, zoom: f64 },
    Status { page: u64, pages: u64, zoom: f64 },
    Inverse { page: u64, x: f64, y: f64, seq: u64 },
    Error(String),
}

pub fn event(json: &str, revision: u64) -> Option<ViewerEvent> {
    if json.len() > MAX_MESSAGE {
        return None;
    }
    let value: Value = serde_json::from_str(json).ok()?;
    if value.get("version")?.as_u64()? != 1 || value.get("revision")?.as_u64()? != revision {
        return None;
    }
    let page = || value.get("page")?.as_u64().filter(|n| (1..=1_000_000).contains(n));
    match value.get("type")?.as_str()? {
        "error" => Some(ViewerEvent::Error(
            value
                .get("error")
                .or_else(|| value.get("message"))?
                .as_str()?
                .chars()
                .take(1024)
                .collect(),
        )),
        "ready" | "status" => {
            let page = page()?;
            let pages =
                value.get("page_count")?.as_u64().filter(|n| (page..=1_000_000).contains(n))?;
            let zoom = value
                .get("zoom")?
                .as_f64()
                .filter(|n| n.is_finite() && (0.001..=100.0).contains(n))?;
            if value["type"] == "ready" {
                Some(ViewerEvent::Ready { page, pages, zoom })
            } else {
                Some(ViewerEvent::Status { page, pages, zoom })
            }
        }
        "inverse" => {
            let coordinate = |key| {
                value
                    .get(key)?
                    .as_f64()
                    .filter(|n| n.is_finite() && (0.0..=1_000_000.0).contains(n))
            };
            Some(ViewerEvent::Inverse {
                page: page()?,
                x: coordinate("x")?,
                y: coordinate("y")?,
                seq: value.get("seq")?.as_u64().filter(|n| *n > 0)?,
            })
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pdf_bridge_limits_resource_access_to_exact_view() {
        let prefix = "https://glow-pdf.invalid/abc/";
        assert_eq!(
            resource_key("https://glow-pdf.invalid/abc/document.pdf", prefix),
            Some("document.pdf")
        );
        for uri in [
            "file:///C:/secret",
            "https://example.com/document.pdf",
            "https://glow-pdf.invalid/other/document.pdf",
            "https://glow-pdf.invalid/abc/../secret",
            "https://glow-pdf.invalid/abc/%2e%2e/secret",
            "https://glow-pdf.invalid/abc/document.pdf?file=secret",
        ] {
            assert_eq!(resource_key(uri, prefix), None, "{uri}");
        }
        assert!(viewer_navigation("https://glow-pdf.invalid/abc/viewer.html#page=2", prefix));
        assert!(!viewer_navigation("https://glow-pdf.invalid/abc/viewer.html.evil", prefix));
    }

    #[test]
    fn pdf_bridge_rejects_stale_or_invalid_coordinates_and_status() {
        let inverse =
            r#"{"version":1,"type":"inverse","revision":3,"page":2,"x":45.5,"y":99,"seq":1}"#;
        assert_eq!(
            event(inverse, 3),
            Some(ViewerEvent::Inverse { page: 2, x: 45.5, y: 99.0, seq: 1 })
        );
        assert_eq!(event(inverse, 4), None);
        assert_eq!(event(&inverse.replace("45.5", "-1"), 3), None);
        assert_eq!(event(&inverse.replace("99", "1e100"), 3), None);
        assert_eq!(
            event(
                r#"{"version":1,"type":"status","revision":3,"page":3,"page_count":2,"zoom":1}"#,
                3
            ),
            None
        );
        assert_eq!(event(&"x".repeat(MAX_MESSAGE + 1), 3), None);
        assert_eq!(
            event(
                r#"{"version":1,"type":"ready","revision":3,"page":1,"page_count":2,"zoom":1}"#,
                3
            ),
            Some(ViewerEvent::Ready { page: 1, pages: 2, zoom: 1.0 })
        );
        assert!(matches!(
            event(
                r#"{"version":1,"type":"ready","revision":3,"page":1,"page_count":2,"zoom":0.05}"#,
                3
            ),
            Some(ViewerEvent::Ready { zoom: 0.05, .. })
        ));
    }
}
