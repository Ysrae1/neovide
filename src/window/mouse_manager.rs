use std::{
    cmp::Ordering,
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};

use winit::{
    event::WindowEvent,
    event::{DeviceId, ElementState, MouseButton, MouseScrollDelta, Touch, TouchPhase},
    window::Window,
};

use glamour::{Contains, Point2};

use crate::{
    bridge::{NeovimHandler, SerialCommand, send_ui},
    editor::WindowType,
    renderer::{
        MessageSelection, NotebookOutputRegion, NotebookSelectionId, Renderer, WindowDrawDetails,
    },
    settings::Settings,
    units::{GridPos, GridScale, GridSize, GridVec, PixelPos, PixelRect, PixelSize, PixelVec},
    window::{WindowSettings, keyboard_manager::KeyboardManager},
};

fn mouse_button_to_button_text(mouse_button: MouseButton) -> Option<String> {
    match mouse_button {
        MouseButton::Left => Some("left".to_owned()),
        MouseButton::Right => Some("right".to_owned()),
        MouseButton::Middle => Some("middle".to_owned()),
        MouseButton::Back => Some("x1".to_owned()),
        MouseButton::Forward => Some("x2".to_owned()),
        _ => None,
    }
}

fn scroll_direction_and_count(
    previous: i32,
    new: i32,
    forward: &'static str,
    backward: &'static str,
) -> Option<(&'static str, u32)> {
    match new.cmp(&previous) {
        Ordering::Greater => Some((forward, new.abs_diff(previous))),
        Ordering::Less => Some((backward, new.abs_diff(previous))),
        Ordering::Equal => None,
    }
}

struct DragDetails {
    draw_details: WindowDrawDetails,
    button: MouseButton,
}

#[derive(Clone, Debug)]
struct MessageSelectionState {
    draw_details: WindowDrawDetails,
    start: GridPos<u32>,
    end: GridPos<u32>,
    notebook: Option<(NotebookSelectionId, NotebookOutputRegion)>,
}

impl MessageSelectionState {
    fn valid(&self, state: &EditorState) -> bool {
        self.notebook.is_none_or(|(id, region)| {
            id.generation == state.notebook_selection_generation
                && state.notebook_output_regions.get(id.region) == Some(&region)
        })
    }
    fn position(&self, point: PixelPos<f32>, state: &EditorState) -> GridPos<u32> {
        self.notebook.map(|(_, region)| region.position(point, *state.grid_scale)).unwrap_or_else(
            || MouseManager::get_relative_position_at(point, &self.draw_details, state),
        )
    }
    fn selection(&self, end: GridPos<u32>) -> MessageSelection {
        MessageSelection {
            grid_id: self.draw_details.id,
            start: self.start,
            end,
            notebook: self.notebook.map(|(id, _)| id),
        }
    }
}

#[derive(Clone, Debug)]
pub enum MessageSelectionEvent {
    Outside,
    Update(MessageSelection),
    Finish(MessageSelection),
    Clear,
    Cancel,
}

impl MessageSelectionEvent {
    fn consumes_input(&self) -> bool {
        matches!(self, Self::Update(_) | Self::Finish(_) | Self::Cancel)
    }
}

#[derive(Clone, Debug, Default)]
pub enum OverlayEvent {
    #[default]
    Unchanged,
    MessageSelection(MessageSelectionEvent),
}

pub struct PointerTransitionResult {
    pub overlay_event: OverlayEvent,
}

pub struct MouseEventResult {
    pub overlay_event: OverlayEvent,
}

pub struct EditorState<'a> {
    pub grid_scale: &'a GridScale,
    pub window_regions: &'a Vec<WindowDrawDetails>,
    pub notebook_output_regions: &'a [NotebookOutputRegion],
    pub notebook_selection_generation: u64,
    pub full_region: WindowDrawDetails,
    pub window: &'a Window,
    pub keyboard_manager: &'a KeyboardManager,
}

#[derive(Debug)]
struct TouchTrace {
    start_time: Instant,
    start: PixelPos<f32>,
    last: PixelPos<f32>,
    left_deadzone_once: bool,
}

pub struct MouseManager {
    drag_details: Option<DragDetails>,
    grid_position: GridPos<u32>,

    has_moved: bool,
    pub window_position: PixelPos<f32>,

    scroll_position: GridPos<f32>,

    // the tuple allows to keep track of different fingers per device
    touch_position: HashMap<(DeviceId, u64), TouchTrace>,

    mouse_hidden: bool,
    // tracks whether we need to force a cursor visibility resync once focus returns.
    // on macos, alt-tabbing while hidden keeps appkit in a cursor hidden mode that ignores
    // redundant show requests https://github.com/rust-windowing/winit/issues/1295 so we
    // remember to toggle visibility once we regain focus.
    cursor_resync_needed: bool,
    pub enabled: bool,

    settings: Arc<Settings>,
    message_selection: Option<MessageSelectionState>,
    selection_release_pending: bool,
}

impl MouseManager {
    pub fn new(settings: Arc<Settings>) -> MouseManager {
        MouseManager {
            drag_details: None,
            has_moved: false,
            window_position: PixelPos::default(),
            grid_position: GridPos::default(),
            scroll_position: GridPos::default(),
            touch_position: HashMap::new(),
            mouse_hidden: false,
            cursor_resync_needed: false,
            enabled: true,
            settings,
            message_selection: None,
            selection_release_pending: false,
        }
    }

    fn request_cursor_visible(&mut self, window: &Window) {
        window.set_cursor_visible(true);
        self.mouse_hidden = false;
        // remember to reapply on focus regain if we changed visibility while unfocused.
        self.cursor_resync_needed = !window.has_focus();
    }

    fn force_cursor_visible(&mut self, window: &Window) {
        #[cfg(target_os = "macos")]
        {
            // winit short-circuits duplicate visibility requests and AppKit won't repaint when the
            // window is unfocused https://github.com/rust-windowing/winit/issues/1295 so flip to
            // false first to ensure the following true call is seen.
            // TODO: move this workaround into winit so visibility resyncs automatically.
            window.set_cursor_visible(false);
        }
        window.set_cursor_visible(true);
        self.mouse_hidden = false;
        self.cursor_resync_needed = false;
    }

    fn hide_cursor(&mut self, window: &Window) {
        window.set_cursor_visible(false);
        self.mouse_hidden = true;
        self.cursor_resync_needed = false;
    }

    fn handle_focus_gain(&mut self, window: &Window) {
        if self.cursor_resync_needed {
            self.force_cursor_visible(window);
        }
    }

    fn handle_focus_loss(&mut self, window: &Window) {
        if self.mouse_hidden {
            self.request_cursor_visible(window);
            self.cursor_resync_needed = true;
        }
    }

    fn handle_focus_change(&mut self, window: &Window, focused: bool) {
        if focused {
            self.handle_focus_gain(window);
        } else {
            self.handle_focus_loss(window);
        }
    }

    pub fn get_window_details_under_mouse<'b>(
        &self,
        editor_state: &'b EditorState<'b>,
    ) -> Option<&'b WindowDrawDetails> {
        let position = self.window_position;
        if self.settings.get::<WindowSettings>().has_mouse_grid_detection {
            Some(&editor_state.full_region)
        } else {
            // the rendered window regions are sorted by draw order, so the earlier windows in the
            // list are drawn under the later ones
            editor_state.window_regions.iter().rfind(|details| details.region.contains(&position))
        }
    }

    fn get_window_details_under_mouse_raw<'b>(
        &self,
        editor_state: &'b EditorState<'b>,
    ) -> Option<&'b WindowDrawDetails> {
        let position = self.window_position;
        editor_state.window_regions.iter().rfind(|details| details.region.contains(&position))
    }

    fn get_relative_position_at(
        window_position: PixelPos<f32>,
        window_details: &WindowDrawDetails,
        editor_state: &EditorState,
    ) -> GridPos<u32> {
        let relative_position = (window_position - window_details.region.min).to_point();
        (relative_position / *editor_state.grid_scale)
            .floor()
            .max((0.0, 0.0).into())
            .try_cast()
            .unwrap()
            .min(Point2::new(
                window_details.grid_size.width.max(1) - 1,
                window_details.grid_size.height.max(1) - 1,
            ))
    }

    pub fn get_relative_position(
        &self,
        window_details: &WindowDrawDetails,
        editor_state: &EditorState,
    ) -> GridPos<u32> {
        Self::get_relative_position_at(self.window_position, window_details, editor_state)
    }

    pub fn clear_message_selection(&mut self) -> bool {
        let had_selection = self.message_selection.take().is_some();
        if had_selection {
            self.drag_details = None;
            self.has_moved = false;
        }

        had_selection
    }

    pub fn clear_notebook_selection(&mut self) -> bool {
        self.message_selection.as_ref().is_some_and(|selection| selection.notebook.is_some())
            && self.clear_message_selection()
    }

    fn update_drag_selection_end(&mut self, end: GridPos<u32>) -> Option<MessageSelection> {
        if !self.selection_release_pending {
            return None;
        }
        let selection = self.message_selection.as_mut()?;
        selection.end = end;
        Some(selection.selection(end))
    }

    fn finish_message_selection(&mut self, end: GridPos<u32>) -> Option<MessageSelection> {
        self.selection_release_pending = false;
        self.drag_details = None;
        self.has_moved = false;
        let mut selection = self.message_selection.take()?;
        selection.end = end;
        let result = selection.selection(end);
        if selection.notebook.is_some() {
            self.message_selection = Some(selection);
        }
        Some(result)
    }

    fn message_area_drag_selection_enabled(&self) -> bool {
        self.settings.get::<WindowSettings>().message_area_drag_selection
    }

    fn handle_pointer_motion(
        &mut self,
        position: PixelPos<f32>,
        editor_state: &EditorState,
        neovim_handler: &NeovimHandler,
    ) -> MessageSelectionEvent {
        let window_size = editor_state.window.inner_size();
        let window_size = PixelSize::new(window_size.width as f32, window_size.height as f32);
        let relative_window_rect = PixelRect::from_size(window_size);

        self.window_position = position;

        let message_selection_enabled = self.message_area_drag_selection_enabled();
        if !message_selection_enabled
            && self.message_selection.as_ref().is_some_and(|s| s.notebook.is_none())
            && self.clear_message_selection()
        {
            return MessageSelectionEvent::Clear;
        }

        if self.message_selection.as_ref().is_some_and(|s| !s.valid(editor_state)) {
            self.clear_message_selection();
            return MessageSelectionEvent::Cancel;
        }
        if self.selection_release_pending
            && let Some(selection) = &self.message_selection
        {
            let window_position = self.window_position;
            let end = selection.position(window_position, editor_state);
            self.grid_position = end;
            if let Some(selection) = self.update_drag_selection_end(end) {
                return MessageSelectionEvent::Update(selection);
            }
        }
        if self.message_selection.as_ref().is_some_and(|selection| selection.notebook.is_some()) {
            // A completed selection is fixed until the next click/scroll/key.
            return MessageSelectionEvent::Outside;
        }

        // If dragging, the relevant window (the one which we send all commands to) is the one
        // which the mouse drag started on. Otherwise its the top rendered window
        let window_details = if let Some(drag_details) = &self.drag_details {
            if self.settings.get::<WindowSettings>().has_mouse_grid_detection {
                Some(&editor_state.full_region)
            } else {
                editor_state
                    .window_regions
                    .iter()
                    .find(|details| details.id == drag_details.draw_details.id)
            }
        } else {
            if !relative_window_rect.contains(&position) {
                return MessageSelectionEvent::Outside;
            }

            self.get_window_details_under_mouse(editor_state)
        };

        if let Some(window_details) = window_details {
            let relative_position = self.get_relative_position(window_details, editor_state);
            let previous_position = self.grid_position;
            self.grid_position = relative_position;

            let has_moved = self.grid_position != previous_position;

            if has_moved {
                if let Some(drag_details) = &self.drag_details {
                    send_ui(
                        SerialCommand::Drag {
                            button: mouse_button_to_button_text(drag_details.button).unwrap(),
                            grid_id: window_details.event_grid_id(&self.settings),
                            position: self.grid_position.to_tuple(),
                            modifier_string: editor_state
                                .keyboard_manager
                                .format_modifier_string("", true),
                        },
                        neovim_handler,
                    );
                } else if self.settings.get::<WindowSettings>().mouse_move_event {
                    // Send a mouse move command
                    send_ui(
                        SerialCommand::MouseButton {
                            button: "move".into(),
                            action: "".into(), // this is ignored by nvim
                            grid_id: window_details.event_grid_id(&self.settings),
                            position: relative_position.to_tuple(),
                            modifier_string: editor_state
                                .keyboard_manager
                                .format_modifier_string("", true),
                        },
                        neovim_handler,
                    );
                }
            }

            self.has_moved = self.drag_details.is_some() && (self.has_moved || has_moved);
        }

        MessageSelectionEvent::Outside
    }

    fn update_message_selection_on_button(
        &mut self,
        mouse_button: MouseButton,
        down: bool,
        editor_state: &EditorState,
    ) -> Option<MessageSelectionEvent> {
        if self.consume_cancelled_selection_release(mouse_button, down) {
            return Some(MessageSelectionEvent::Cancel);
        }
        if !down && mouse_button == MouseButton::Left && self.selection_release_pending {
            let Some(selection) = self.message_selection.as_ref() else {
                return Some(MessageSelectionEvent::Cancel);
            };
            if !selection.valid(editor_state) {
                self.clear_message_selection();
                self.selection_release_pending = false;
                return Some(MessageSelectionEvent::Cancel);
            }
            let end = selection.position(self.window_position, editor_state);
            return self.finish_message_selection(end).map(MessageSelectionEvent::Finish);
        }
        if !self.message_area_drag_selection_enabled()
            && self.message_selection.as_ref().is_some_and(|s| s.notebook.is_none())
        {
            return self.clear_message_selection().then_some(MessageSelectionEvent::Clear);
        }

        // Native selections consume both halves of the click; ordinary editor
        // clicks continue through Neovim's normal input path.
        if down && mouse_button == MouseButton::Left {
            let details = self.get_window_details_under_mouse_raw(editor_state);
            let notebook = details.and_then(|details| {
                editor_state.notebook_output_regions.iter().enumerate().find_map(
                    |(index, region)| {
                        region.hit(self.window_position, details.id).then_some((
                            NotebookSelectionId {
                                generation: editor_state.notebook_selection_generation,
                                region: index,
                            },
                            *region,
                        ))
                    },
                )
            });
            let allow_selection = details
                .map(|details| {
                    notebook.is_some()
                        || (self.message_area_drag_selection_enabled()
                            && matches!(details.window_type, WindowType::Message { .. }))
                })
                .unwrap_or(false);

            if !allow_selection && self.message_selection.is_some() {
                self.message_selection = None;
                return Some(MessageSelectionEvent::Clear);
            }

            if let Some(details) = details
                && allow_selection
            {
                let position = notebook
                    .map(|(_, region)| {
                        region.position(self.window_position, *editor_state.grid_scale)
                    })
                    .unwrap_or_else(|| self.get_relative_position(details, editor_state));
                self.message_selection = Some(MessageSelectionState {
                    draw_details: details.clone(),
                    start: position,
                    end: position,
                    notebook,
                });
                self.selection_release_pending = true;
                self.drag_details = None;
                self.has_moved = false;
                return Some(MessageSelectionEvent::Update(MessageSelection {
                    grid_id: details.id,
                    start: position,
                    end: position,
                    notebook: notebook.map(|(id, _)| id),
                }));
            }
        }

        None
    }

    fn consume_cancelled_selection_release(&mut self, button: MouseButton, down: bool) -> bool {
        if !down
            && button == MouseButton::Left
            && self.selection_release_pending
            && self.message_selection.is_none()
        {
            self.selection_release_pending = false;
            self.drag_details = None;
            self.has_moved = false;
            true
        } else {
            false
        }
    }

    fn send_nvim_mouse_button(
        &mut self,
        mouse_button: MouseButton,
        down: bool,
        editor_state: &EditorState,
        neovim_handler: &NeovimHandler,
    ) {
        // For some reason pointer down is handled differently from pointer up and drag.
        // Floating windows: relative coordinates are great.
        // Non floating windows: rather than global coordinates, relative are needed
        if !self.enabled {
            return;
        }

        if let Some(button_text) = mouse_button_to_button_text(mouse_button) {
            if let &Some(details) = &self.get_window_details_under_mouse(editor_state) {
                let action = if down { "press".to_owned() } else { "release".to_owned() };

                let position = if !down && self.has_moved {
                    self.grid_position
                } else {
                    self.get_relative_position(details, editor_state)
                };

                send_ui(
                    SerialCommand::MouseButton {
                        button: button_text.clone(),
                        action,
                        grid_id: details.event_grid_id(&self.settings),
                        position: position.to_tuple(),
                        modifier_string: editor_state
                            .keyboard_manager
                            .format_modifier_string("", true),
                    },
                    neovim_handler,
                );

                if down {
                    self.drag_details =
                        Some(DragDetails { button: mouse_button, draw_details: details.clone() });
                } else {
                    self.drag_details = None;
                }
            } else {
                self.drag_details = None;
            }

            if self.drag_details.is_none() {
                self.has_moved = false;
            }
        }
    }

    fn handle_pointer_transition(
        &mut self,
        mouse_button: MouseButton,
        down: bool,
        editor_state: &EditorState,
        neovim_handler: &NeovimHandler,
    ) -> PointerTransitionResult {
        let message_selection_event =
            self.update_message_selection_on_button(mouse_button, down, editor_state);
        let consume_mouse_input =
            message_selection_event.as_ref().is_some_and(MessageSelectionEvent::consumes_input);

        if !consume_mouse_input {
            self.send_nvim_mouse_button(mouse_button, down, editor_state, neovim_handler);
        }

        PointerTransitionResult {
            overlay_event: message_selection_event
                .map(OverlayEvent::MessageSelection)
                .unwrap_or_default(),
        }
    }

    fn send_nvim_scroll(
        &self,
        direction: &str,
        count: u32,
        grid_id: u64,
        editor_state: &EditorState,
        neovim_handler: &NeovimHandler,
    ) {
        send_ui(
            SerialCommand::scroll(
                direction,
                grid_id,
                self.grid_position.to_tuple(),
                count,
                editor_state.keyboard_manager.format_modifier_string("", true),
            ),
            neovim_handler,
        );
    }

    fn handle_line_scroll(
        &mut self,
        amount: GridVec<f32>,
        editor_state: &EditorState,
        neovim_handler: &NeovimHandler,
    ) {
        if !self.enabled {
            return;
        }

        let draw_details = self.get_window_details_under_mouse(editor_state);
        let grid_id =
            draw_details.map(|details| details.event_grid_id(&self.settings)).unwrap_or(0);

        let previous: GridPos<i32> = self.scroll_position.floor().try_cast().unwrap();
        self.scroll_position += amount;
        let new: GridPos<i32> = self.scroll_position.floor().try_cast().unwrap();

        if let Some((direction, count)) =
            scroll_direction_and_count(previous.y, new.y, "up", "down")
        {
            self.send_nvim_scroll(direction, count, grid_id, editor_state, neovim_handler);
        }

        if let Some((direction, count)) =
            scroll_direction_and_count(previous.x, new.x, "left", "right")
        {
            self.send_nvim_scroll(direction, count, grid_id, editor_state, neovim_handler);
        }
    }

    fn handle_pixel_scroll(
        &mut self,
        amount: PixelVec<f32>,
        editor_state: &EditorState,
        neovim_handler: &NeovimHandler,
    ) {
        let amount = amount / *editor_state.grid_scale;
        self.handle_line_scroll(amount, editor_state, neovim_handler);
    }

    fn handle_touch(
        &mut self,
        finger_id: (DeviceId, u64),
        location: PixelPos<f32>,
        phase: &TouchPhase,
        editor_state: &EditorState,
        neovim_handler: &NeovimHandler,
    ) {
        match phase {
            TouchPhase::Started => {
                let settings = self.settings.get::<WindowSettings>();
                let enable_deadzone = settings.touch_deadzone >= 0.0;

                self.touch_position.insert(
                    finger_id,
                    TouchTrace {
                        start_time: Instant::now(),
                        start: location,
                        last: location,
                        left_deadzone_once: !enable_deadzone,
                    },
                );
            }
            TouchPhase::Moved => {
                let mut dragging_just_now = false;

                if let Some(trace) = self.touch_position.get_mut(&finger_id) {
                    if !trace.left_deadzone_once {
                        let distance_to_start = ((trace.start.x - location.x).powi(2)
                            + (trace.start.y - location.y).powi(2))
                        .sqrt();

                        let settings = self.settings.get::<WindowSettings>();
                        if distance_to_start >= settings.touch_deadzone {
                            trace.left_deadzone_once = true;
                        }

                        let timeout_setting = Duration::from_micros(
                            (settings.touch_drag_timeout * 1_000_000.) as u64,
                        );
                        if self.drag_details.is_none()
                            && trace.start_time.elapsed() >= timeout_setting
                        {
                            dragging_just_now = true;
                        }
                    }

                    if self.drag_details.is_some() || dragging_just_now {
                        self.handle_pointer_motion(
                            (location.x, location.y).into(),
                            editor_state,
                            neovim_handler,
                        );
                    }
                    // the double check might seem useless, but the if branch above might set
                    // trace.left_deadzone_once - which urges to check again
                    else if trace.left_deadzone_once {
                        let delta = (trace.last.x - location.x, location.y - trace.last.y).into();

                        // not updating the position would cause the movement to "escalate" from the
                        // starting point
                        trace.last = location;

                        self.handle_pixel_scroll(delta, editor_state, neovim_handler);
                    }
                }

                if dragging_just_now {
                    self.handle_pointer_motion(
                        (location.x, location.y).into(),
                        editor_state,
                        neovim_handler,
                    );
                    self.handle_pointer_transition(
                        MouseButton::Left,
                        true,
                        editor_state,
                        neovim_handler,
                    );
                }
            }
            TouchPhase::Ended | TouchPhase::Cancelled => {
                if let Some(trace) = self.touch_position.remove(&finger_id) {
                    if self.drag_details.is_some() {
                        self.handle_pointer_transition(
                            MouseButton::Left,
                            false,
                            editor_state,
                            neovim_handler,
                        );
                    }
                    if !trace.left_deadzone_once {
                        self.handle_pointer_motion(
                            (trace.start.x, trace.start.y).into(),
                            editor_state,
                            neovim_handler,
                        );
                        self.handle_pointer_transition(
                            MouseButton::Left,
                            true,
                            editor_state,
                            neovim_handler,
                        );
                        self.handle_pointer_transition(
                            MouseButton::Left,
                            false,
                            editor_state,
                            neovim_handler,
                        );
                    }
                }
            }
        }
    }

    pub fn handle_event(
        &mut self,
        event: &WindowEvent,
        keyboard_manager: &KeyboardManager,
        renderer: &Renderer,
        window: &Window,
        neovim_handler: &NeovimHandler,
    ) -> MouseEventResult {
        let full_region = WindowDrawDetails {
            id: 0,
            region: renderer.window_regions.first().map_or(PixelRect::ZERO, |v| v.region),
            grid_size: renderer.window_regions.first().map_or(GridSize::ZERO, |v| v.grid_size),
            window_type: crate::editor::WindowType::Editor,
        };
        let editor_state = EditorState {
            grid_scale: &renderer.grid_renderer.grid_scale,
            window_regions: &renderer.window_regions,
            notebook_output_regions: &renderer.notebook_output_regions,
            notebook_selection_generation: renderer.notebook_selection_generation,
            full_region,
            window,
            keyboard_manager,
        };
        let hide_mouse_when_typing = self.settings.get::<WindowSettings>().hide_mouse_when_typing;
        let mut overlay_event = OverlayEvent::default();
        if matches!(event, WindowEvent::MouseWheel { .. }) && self.clear_notebook_selection() {
            overlay_event = OverlayEvent::MessageSelection(MessageSelectionEvent::Clear);
        }
        match event {
            WindowEvent::CursorMoved { position, .. } => {
                let message_selection_event = self.handle_pointer_motion(
                    (position.x as f32, position.y as f32).into(),
                    &editor_state,
                    neovim_handler,
                );
                overlay_event = match message_selection_event {
                    MessageSelectionEvent::Outside => OverlayEvent::default(),
                    event => OverlayEvent::MessageSelection(event),
                };
                if self.mouse_hidden && window.has_focus() {
                    self.request_cursor_visible(window);
                } else if self.cursor_resync_needed && window.has_focus() {
                    self.force_cursor_visible(window);
                }
            }
            WindowEvent::CursorEntered { .. } => {
                if self.mouse_hidden {
                    self.request_cursor_visible(window);
                } else if self.cursor_resync_needed && window.has_focus() {
                    self.force_cursor_visible(window);
                }
            }
            WindowEvent::MouseWheel { delta: MouseScrollDelta::LineDelta(x, y), .. } => {
                self.handle_line_scroll((*x, *y).into(), &editor_state, neovim_handler)
            }
            WindowEvent::MouseWheel { delta: MouseScrollDelta::PixelDelta(delta), .. } => self
                .handle_pixel_scroll(
                    (delta.x as f32, delta.y as f32).into(),
                    &editor_state,
                    neovim_handler,
                ),
            WindowEvent::Touch(Touch { device_id, id, location, phase, .. }) => self.handle_touch(
                (*device_id, *id),
                PixelPos::new(location.x as f32, location.y as f32),
                phase,
                &editor_state,
                neovim_handler,
            ),
            WindowEvent::MouseInput { button, state, .. } => {
                overlay_event = self
                    .handle_pointer_transition(
                        *button,
                        state == &ElementState::Pressed,
                        &editor_state,
                        neovim_handler,
                    )
                    .overlay_event;
            }

            WindowEvent::KeyboardInput { event: key_event, .. }
                if hide_mouse_when_typing
                    && key_event.state == ElementState::Pressed
                    && !self.mouse_hidden
                    && window.has_focus() =>
            {
                self.hide_cursor(window);
            }
            WindowEvent::Focused(focused_event) if hide_mouse_when_typing => {
                self.handle_focus_change(window, *focused_event);
            }
            _ => {}
        }

        MouseEventResult { overlay_event }
    }
}

#[cfg(test)]
mod selection_tests {
    use super::*;

    fn selection_state(notebook: bool) -> MessageSelectionState {
        let region = NotebookOutputRegion {
            grid_id: 2,
            bounds: PixelRect::from_origin_and_size(PixelPos::ZERO, PixelSize::new(80.0, 40.0)),
            cells: crate::units::GridRect::from_min_max((0, 0), (8, 2)),
            origin: PixelPos::ZERO,
        };
        MessageSelectionState {
            draw_details: WindowDrawDetails {
                id: 2,
                region: region.bounds,
                grid_size: GridSize::new(8, 2),
                window_type: WindowType::Editor,
            },
            start: GridPos::new(6, 1),
            end: GridPos::new(6, 1),
            notebook: notebook
                .then_some((NotebookSelectionId { generation: 1, region: 0 }, region)),
        }
    }

    #[test]
    fn notebook_output_selection_persists_release_ignores_hover_and_clears() {
        let mut mouse = MouseManager::new(Arc::new(Settings::new()));
        mouse.message_selection = Some(selection_state(true));
        mouse.selection_release_pending = true;
        let end = GridPos::new(2, 0);
        let completed = mouse.finish_message_selection(end).unwrap();
        assert_eq!(completed.start, GridPos::new(6, 1));
        assert_eq!(completed.end, end, "reverse selection keeps its endpoints");
        assert!(!mouse.selection_release_pending);
        assert!(mouse.message_selection.is_some(), "release preserves Notebook selection");
        assert!(mouse.update_drag_selection_end(GridPos::new(7, 1)).is_none());
        assert_eq!(mouse.message_selection.as_ref().unwrap().end, end, "hover cannot extend it");
        assert!(mouse.clear_notebook_selection(), "Escape, scroll, and outside click may clear it");
        assert!(mouse.message_selection.is_none());

        mouse.message_selection = Some(selection_state(false));
        assert!(!mouse.clear_notebook_selection(), "Notebook cancellation does not alter messages");
        mouse.selection_release_pending = true;
        assert!(mouse.finish_message_selection(end).is_some());
        assert!(
            mouse.message_selection.is_none(),
            "ordinary message release keeps its old behavior"
        );
    }

    #[test]
    fn notebook_output_selection_consumes_press_finish_and_cancelled_release() {
        let selection = MessageSelection {
            grid_id: 2,
            start: GridPos::new(4, 3),
            end: GridPos::new(8, 3),
            notebook: Some(NotebookSelectionId { generation: 1, region: 0 }),
        };
        assert!(MessageSelectionEvent::Update(selection).consumes_input());
        assert!(MessageSelectionEvent::Finish(selection).consumes_input());
        assert!(MessageSelectionEvent::Cancel.consumes_input());
        assert!(
            !MessageSelectionEvent::Outside.consumes_input(),
            "source clicks retain Neovim's normal input"
        );
        let mut mouse = MouseManager::new(Arc::new(Settings::new()));
        mouse.selection_release_pending = true;
        // Frame/scroll cancellation already removed the drag state. Its later
        // release must still be swallowed rather than sent alone to Neovim.
        assert!(mouse.consume_cancelled_selection_release(MouseButton::Left, false));
        assert!(!mouse.consume_cancelled_selection_release(MouseButton::Left, false));
        assert!(!mouse.consume_cancelled_selection_release(MouseButton::Left, true));
    }
}
