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
use tokio::sync::Semaphore;
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
// Shared by all editor routes, including hidden native macOS tabs.
static DECODERS: OnceLock<Semaphore> = OnceLock::new();

struct Requests {
    active: Mutex<HashMap<u64, Arc<AtomicBool>>>,
    proxy: Mutex<EventLoopProxy<EventPayload>>,
    route: RouteId,
}

impl Requests {
    fn send(&self, command: ImageCommand) {
        let payload = UserEvent::DrawCommandBatch(vec![DrawCommand::ImagePreview(command)]);
        let _ = self.proxy.lock().unwrap().send_event(EventPayload::for_route(payload, self.route));
    }
}

impl Drop for Requests {
    fn drop(&mut self) {
        for live in self.active.get_mut().unwrap().values() {
            live.store(false, Ordering::Release);
        }
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
                self.load(id, path.to_owned(), nvim);
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
                if let Some(live) = active.remove(&id) {
                    live.store(false, Ordering::Release);
                }
                self.0.send(ImageCommand::Close(id));
            }
            _ => log::warn!("Unknown native image command: {name}"),
        }
    }

    fn load(&self, id: u64, path: String, nvim: Neovim<NeovimWriter>) {
        let live = Arc::new(AtomicBool::new(true));
        {
            let mut active = self.0.active.lock().unwrap();
            if active.len() >= MAX_PREVIEWS && !active.contains_key(&id) {
                report_status(nvim, id, Err("Too many image previews (maximum 8)".into()));
                return;
            }
            if let Some(previous) = active.insert(id, live.clone()) {
                previous.store(false, Ordering::Release);
            }
            self.0.send(ImageCommand::Begin(id));
        }
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
                    || !active.get(&id).is_some_and(|current| Arc::ptr_eq(current, &live))
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
        let _ = nvim.exec_lua(
            "local args={...}; vim.schedule(function() local ok,m=pcall(require,'config.media.image'); if ok then m.on_status(unpack(args)) end end)",
            vec![id.into(), width.into(), height.into(), error],
        ).await;
    });
}
