//! Nonblocking, route-local native image RPC. Never read files on the UI/RPC task.
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, Ordering},
    },
};

use nvim_rs::Neovim;
use rmpv::Value;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};
use winit::event_loop::EventLoopProxy;

use crate::{
    bridge::NeovimWriter,
    image_preview::{ImageView, decode_image},
    renderer::{
        DrawCommand,
        image_preview::{ImageCommand, PreparedImage},
    },
    window::{EventPayload, RouteId, UserEvent},
};

const MAX_PREVIEWS: usize = 8;
const MAX_NOTEBOOK_PREVIEWS: usize = 6;
// Shared by all editor routes, including hidden native macOS tabs.
static DECODERS: OnceLock<Semaphore> = OnceLock::new();
static PREVIEWS: OnceLock<PreviewQuota> = OnceLock::new();

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PreviewOwner {
    Image,
    Molten,
    Yazi,
}

impl PreviewOwner {
    fn parse(value: Option<&Value>, id: u64) -> Result<Self, String> {
        match value {
            Some(Value::Nil) | None => Ok(if id > 2_000_000 {
                Self::Yazi
            } else if id > 1_000_000 {
                Self::Molten
            } else {
                Self::Image
            }),
            Some(value) => match value.as_str() {
                Some("image") => Ok(Self::Image),
                Some("molten") => Ok(Self::Molten),
                Some("yazi") => Ok(Self::Yazi),
                _ => Err("Unknown native image owner".into()),
            },
        }
    }
}

struct PreviewQuota {
    total: Arc<Semaphore>,
    notebook: Arc<Semaphore>,
}

impl PreviewQuota {
    fn new() -> Self {
        Self {
            total: Arc::new(Semaphore::new(MAX_PREVIEWS)),
            notebook: Arc::new(Semaphore::new(MAX_NOTEBOOK_PREVIEWS)),
        }
    }
}

fn capacity_error() -> String {
    "Image preview capacity reached (application maximum 8; Notebook maximum 6, with 2 shared interactive slots)".into()
}

struct PreviewRequest {
    live: Arc<AtomicBool>,
    owner: PreviewOwner,
    _permit: OwnedSemaphorePermit,
    _notebook_permit: Option<OwnedSemaphorePermit>,
}

impl Drop for PreviewRequest {
    fn drop(&mut self) {
        self.live.store(false, Ordering::Release);
    }
}

fn begin_request(
    active: &mut HashMap<u64, PreviewRequest>,
    quota: &PreviewQuota,
    id: u64,
    owner: PreviewOwner,
) -> Result<Arc<AtomicBool>, String> {
    let live = Arc::new(AtomicBool::new(true));
    if let Some(previous) = active.get_mut(&id) {
        if previous.owner != owner {
            return Err("Close an image preview before changing its owner".into());
        }
        // Reloading replaces the request, but still owns the same preview slot.
        previous.live.store(false, Ordering::Release);
        previous.live = live.clone();
    } else {
        // Notebook pixels may occupy six slots; ordinary images and Yazi share
        // the other two, while all owners still obey the application-wide cap.
        let notebook_permit = if owner == PreviewOwner::Molten {
            Some(quota.notebook.clone().try_acquire_owned().map_err(|_| capacity_error())?)
        } else {
            None
        };
        let permit = quota.total.clone().try_acquire_owned().map_err(|_| capacity_error())?;
        active.insert(
            id,
            PreviewRequest {
                live: live.clone(),
                owner,
                _permit: permit,
                _notebook_permit: notebook_permit,
            },
        );
    }
    Ok(live)
}

struct Requests {
    active: Mutex<HashMap<u64, PreviewRequest>>,
    proxy: Mutex<EventLoopProxy<EventPayload>>,
    route: RouteId,
}

impl Requests {
    fn send(&self, command: ImageCommand) {
        let payload = UserEvent::DrawCommandBatch(vec![DrawCommand::ImagePreview(command)]);
        let _ = self.proxy.lock().unwrap().send_event(EventPayload::for_route(payload, self.route));
    }
}

#[derive(Clone)]
pub(super) struct ImageRequests(Arc<Requests>);

impl ImageRequests {
    pub fn new(proxy: EventLoopProxy<EventPayload>, route: RouteId) -> Self {
        Self(Arc::new(Requests {
            active: Mutex::new(HashMap::new()),
            proxy: Mutex::new(proxy),
            route,
        }))
    }

    pub fn handle(&self, name: &str, args: &[Value], nvim: Neovim<NeovimWriter>) {
        let Some(id) = args.first().and_then(Value::as_u64) else {
            log::warn!("Native image command needs a positive image id");
            return;
        };
        match name {
            "neovide.image.load" => {
                let Some(path) = args.get(1).and_then(Value::as_str).filter(|p| !p.is_empty())
                else {
                    report_status(nvim, id, Err("Image path is missing".into()));
                    return;
                };
                let owner = match PreviewOwner::parse(args.get(2), id) {
                    Ok(owner) => owner,
                    Err(error) => {
                        report_status(nvim, id, Err(error));
                        return;
                    }
                };
                self.load(id, path.to_owned(), owner, nvim);
            }
            "neovide.image.show" => match args
                .get(1)
                .ok_or("Image view is missing".to_owned())
                .and_then(ImageView::parse)
            {
                Ok(view) => self.0.send(ImageCommand::Show(id, view)),
                Err(error) => report_status(nvim, id, Err(error)),
            },
            "neovide.image.hide" => self.0.send(ImageCommand::Hide(id)),
            "neovide.image.close" => {
                let mut active = self.0.active.lock().unwrap();
                active.remove(&id);
                self.0.send(ImageCommand::Close(id));
            }
            _ => log::warn!("Unknown native image command: {name}"),
        }
    }

    fn load(&self, id: u64, path: String, owner: PreviewOwner, nvim: Neovim<NeovimWriter>) {
        let live = {
            let mut active = self.0.active.lock().unwrap();
            let quota = PREVIEWS.get_or_init(PreviewQuota::new);
            let live = match begin_request(&mut active, quota, id, owner) {
                Ok(live) => live,
                Err(error) => {
                    report_status(nvim, id, Err(error));
                    return;
                }
            };
            self.0.send(ImageCommand::Begin(id));
            live
        };
        let requests = Arc::downgrade(&self.0);
        tokio::spawn(async move {
            let Ok(permit) = DECODERS.get_or_init(|| Semaphore::new(2)).acquire().await else {
                return;
            };
            if !live.load(Ordering::Acquire) {
                return;
            }
            let worker_live = live.clone();
            let decoded = tokio::task::spawn_blocking(move || {
                let decoded = decode_image(&path)?;
                if !worker_live.load(Ordering::Acquire) {
                    return Err("Preview closed".into());
                }
                PreparedImage::new(decoded, worker_live)
            })
            .await
            .unwrap_or_else(|error| Err(format!("Image worker failed: {error}")));
            drop(permit);
            let Some(requests) = requests.upgrade() else { return };
            let status;
            {
                let mut active = requests.active.lock().unwrap();
                if !live.load(Ordering::Acquire)
                    || !active.get(&id).is_some_and(|current| Arc::ptr_eq(&current.live, &live))
                {
                    return;
                }
                status = match decoded {
                    Ok(image) => {
                        let size = (image.image.width(), image.image.height());
                        requests.send(ImageCommand::Ready(id, image));
                        Ok(size)
                    }
                    Err(error) => {
                        active.remove(&id);
                        requests.send(ImageCommand::Close(id));
                        Err(error)
                    }
                };
            }
            report_status(nvim, id, status);
        });
    }
}

fn report_status(nvim: Neovim<NeovimWriter>, id: u64, status: Result<(i32, i32), String>) {
    tokio::spawn(async move {
        let (width, height, error) = match status {
            Ok((width, height)) => (width, height, Value::Nil),
            Err(error) => (0, 0, Value::from(error)),
        };
        // The companion configuration ignores ids that were closed while loading.
        let _ = nvim
            .exec_lua(
                include_str!("../../lua/image_status.lua"),
                vec![id.into(), width.into(), height.into(), error],
            )
            .await;
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preview_quota_is_shared_across_routes_and_reused_by_reload() {
        let quota = PreviewQuota::new();
        let mut first = HashMap::new();
        let mut second = HashMap::new();
        let original = begin_request(&mut first, &quota, 1, PreviewOwner::Image).unwrap();
        for id in 2..=MAX_PREVIEWS as u64 {
            // Identical route-local ids still consume separate global slots.
            begin_request(&mut second, &quota, id - 1, PreviewOwner::Image).unwrap();
        }
        assert_eq!(quota.total.available_permits(), 0);
        assert!(begin_request(&mut second, &quota, 100, PreviewOwner::Image).is_err());
        assert!(!second.contains_key(&100));
        let replacement = begin_request(&mut first, &quota, 1, PreviewOwner::Image).unwrap();
        assert!(!original.load(Ordering::Acquire));
        assert!(replacement.load(Ordering::Acquire));
        assert_eq!(quota.total.available_permits(), 0);

        // Both explicit close and failed decode remove the active request.
        first.remove(&1);
        assert!(!replacement.load(Ordering::Acquire));
        assert_eq!(quota.total.available_permits(), 1);
        let recovered = begin_request(&mut second, &quota, 100, PreviewOwner::Image).unwrap();
        assert_eq!(quota.total.available_permits(), 0);
        drop(second);
        assert!(!recovered.load(Ordering::Acquire));
        assert_eq!(quota.total.available_permits(), MAX_PREVIEWS);
    }
    #[test]
    fn notebook_quota_reserves_two_shared_interactive_slots_across_routes() {
        let quota = PreviewQuota::new();
        let mut first = HashMap::new();
        let mut second = HashMap::new();
        for id in 1..=MAX_NOTEBOOK_PREVIEWS as u64 {
            begin_request(&mut first, &quota, id, PreviewOwner::Molten).unwrap();
        }
        assert!(begin_request(&mut second, &quota, 77, PreviewOwner::Molten).is_err());
        assert_eq!(quota.total.available_permits(), 2);
        let image = begin_request(&mut second, &quota, 78, PreviewOwner::Image).unwrap();
        let yazi = begin_request(&mut second, &quota, 79, PreviewOwner::Yazi).unwrap();
        assert_eq!(quota.total.available_permits(), 0);
        assert!(begin_request(&mut second, &quota, 80, PreviewOwner::Image).is_err());
        // A rejected owner change keeps the original request and both permits.
        let original = first.get(&1).unwrap().live.clone();
        assert!(begin_request(&mut first, &quota, 1, PreviewOwner::Image).is_err());
        assert!(original.load(Ordering::Acquire));
        let replacement = begin_request(&mut first, &quota, 1, PreviewOwner::Molten).unwrap();
        assert!(!original.load(Ordering::Acquire));
        assert_eq!(quota.notebook.available_permits(), 0);
        // Close / failed decode and route destruction return both reservations.
        first.remove(&1);
        assert!(!replacement.load(Ordering::Acquire));
        begin_request(&mut second, &quota, 80, PreviewOwner::Molten).unwrap();
        drop(first);
        drop(second);
        assert!(!image.load(Ordering::Acquire) && !yazi.load(Ordering::Acquire));
        assert_eq!(quota.total.available_permits(), MAX_PREVIEWS);
        assert_eq!(quota.notebook.available_permits(), MAX_NOTEBOOK_PREVIEWS);
    }

    #[test]
    fn notebook_reservation_is_returned_when_total_quota_is_full() {
        let quota = PreviewQuota::new();
        let mut active = HashMap::new();
        for id in 1..=MAX_PREVIEWS as u64 {
            begin_request(&mut active, &quota, id, PreviewOwner::Image).unwrap();
        }
        assert!(begin_request(&mut active, &quota, 99, PreviewOwner::Molten).is_err());
        assert_eq!(quota.notebook.available_permits(), MAX_NOTEBOOK_PREVIEWS);
    }

    #[test]
    fn image_owner_is_explicit_with_legacy_id_fallback() {
        assert_eq!(PreviewOwner::parse(None, 5).unwrap(), PreviewOwner::Image);
        assert_eq!(PreviewOwner::parse(None, 1_000_001).unwrap(), PreviewOwner::Molten);
        assert_eq!(PreviewOwner::parse(None, 2_000_001).unwrap(), PreviewOwner::Yazi);
        assert_eq!(
            PreviewOwner::parse(Some(&Value::from("molten")), 5).unwrap(),
            PreviewOwner::Molten
        );
        assert!(PreviewOwner::parse(Some(&Value::from("unknown")), 5).is_err());
    }
}
