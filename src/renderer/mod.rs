pub mod animation_utils;
mod bloom;
#[cfg(test)]
mod bloom_tests;
#[cfg(test)]
mod bottom_margin_tests;
pub mod box_drawing;
pub mod cursor_renderer;
pub mod fonts;
pub mod grid_renderer;
pub(crate) mod image_preview;
pub(crate) mod notebook;
pub mod opengl;
pub mod profiler;
pub mod progress_bar;
mod rendered_layer;
pub mod rendered_window;
mod selection;
mod vsync;

use selection::selection_spans;
pub use selection::{NotebookOutputRegion, NotebookSelectionId};

#[cfg(target_os = "windows")]
pub mod d3d;

#[cfg(target_os = "macos")]
mod metal;

use std::{
    cmp::Ordering,
    collections::{HashMap, HashSet, hash_map::Entry},
    rc::Rc,
    sync::Arc,
};

use itertools::Itertools;
use progress_bar::{ProgressBar, ProgressBarSettings};
use skia_safe::{Canvas, Color4f, Paint};

use winit::{
    event::WindowEvent,
    event_loop::{ActiveEventLoop, EventLoopProxy},
    window::{Window, WindowAttributes},
};

use crate::{
    WindowSettings,
    bridge::{EditorMode, StartupMessage},
    cmd_line::CmdLineSettings,
    editor::{Cursor, Style, WindowType},
    profiling::{tracy_create_gpu_context, tracy_named_frame, tracy_zone},
    renderer::{
        fonts::font_options::PixelGeometry,
        rendered_layer::{FloatingLayer, group_windows},
    },
    settings::*,
    units::{GridPos, GridRect, GridScale, GridSize, PixelPos, PixelRect, to_skia_rect},
    window::{EventPayload, ShouldRender},
};

#[cfg(target_os = "macos")]
use crate::editor::ScrollbarSnapshot;

#[cfg(feature = "profiling")]
use crate::profiling::tracy_plot;
#[cfg(feature = "profiling")]
use skia_safe::graphics::{
    font_cache_count_limit, font_cache_count_used, font_cache_limit, font_cache_used,
    resource_cache_single_allocation_byte_limit, resource_cache_total_bytes_limit,
    resource_cache_total_bytes_used,
};

#[cfg(feature = "gpu_profiling")]
use crate::profiling::GpuCtx;

use cursor_renderer::CursorRenderer;
pub use fonts::caching_shaper::CachingShaper;
pub use grid_renderer::GridRenderer;
pub use rendered_window::{RenderedWindow, WindowDrawCommand, WindowDrawDetails};

pub use vsync::VSync;

use self::fonts::font_options::FontOptions;

const MESSAGE_SELECTION_ALPHA: f32 = 0.35;
const STARTUP_MESSAGE_LIMIT: usize = 4;

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct MessageSelection {
    pub grid_id: u64,
    pub start: GridPos<u32>,
    pub end: GridPos<u32>,
    pub notebook: Option<NotebookSelectionId>,
}

#[cfg(feature = "profiling")]
fn plot_skia_cache() {
    tracy_plot!("font_cache_limit", font_cache_limit() as f64);
    tracy_plot!("font_cache_used", font_cache_used() as f64);
    tracy_plot!("font_cache_count_used", font_cache_count_used() as f64);
    tracy_plot!("font_cache_count_limit", font_cache_count_limit() as f64);
    tracy_plot!("resource_cache_total_bytes_used", resource_cache_total_bytes_used() as f64);
    tracy_plot!("resource_cache_total_bytes_limit", resource_cache_total_bytes_limit() as f64);
    tracy_plot!(
        "resource_cache_single_allocation_byte_limit",
        resource_cache_single_allocation_byte_limit().unwrap_or_default() as f64
    );
}

#[derive(SettingGroup, Clone)]
pub struct RendererSettings {
    bloom: bool,
    bloom_strength: f32,
    bloom_radius: f32,
    bloom_brightness: f32,
    bloom_saturation: f32,
    position_animation_length: f32,
    scroll_animation_length: f32,
    scroll_animation_far_lines: u32,
    floating_blur: bool,
    floating_blur_amount_x: f32,
    floating_blur_amount_y: f32,
    floating_shadow: bool,
    floating_z_height: f32,
    floating_corner_radius: f32,
    light_angle_degrees: f32,
    light_radius: f32,
    debug_renderer: bool,
    profiler: bool,
    underline_stroke_scale: f32,
    text_gamma: f32,
    text_contrast: f32,
    experimental_layer_grouping: bool,
    pixel_geometry: PixelGeometry,
}

impl Default for RendererSettings {
    fn default() -> Self {
        Self {
            // Enable bloom by default in this experimental glow-preview branch.
            bloom: true,
            bloom_strength: 0.2,
            bloom_radius: 8.0,
            bloom_brightness: 1.1,
            bloom_saturation: 0.15,
            position_animation_length: 0.15,
            scroll_animation_length: 0.3,
            scroll_animation_far_lines: 1,
            floating_blur: true,
            floating_blur_amount_x: 2.0,
            floating_blur_amount_y: 2.0,
            floating_shadow: true,
            floating_z_height: 10.,
            floating_corner_radius: 0.0,
            light_angle_degrees: 45.,
            light_radius: 5.,
            debug_renderer: false,
            profiler: false,
            underline_stroke_scale: 1.,
            text_gamma: 0.0,
            text_contrast: 0.5,
            experimental_layer_grouping: false,
            pixel_geometry: PixelGeometry::default(),
        }
    }
}

// Draw commands retain Neovim's order within each completed redraw batch.
#[derive(Debug, Clone, PartialEq)]
pub enum DrawCommand {
    UpdateCursor(Cursor),
    FontChanged(String),
    LineSpaceChanged(f32),
    DefaultStyleChanged(Style),
    ModeChanged(EditorMode),
    StartupMessage {
        message: StartupMessage,
        replace_last: bool,
        append: bool,
    },
    ClearStartupMessages,
    StartupPrompt,
    ReplayStartupMessages,
    UIReady,
    ImagePreview(image_preview::ImageCommand),
    NotebookFrames(notebook::FrameSnapshot),
    FloatShadowExclusions(Vec<u64>),
    #[cfg(target_os = "macos")]
    ScrollbarSnapshot(ScrollbarSnapshot),
    Window {
        grid_id: u64,
        command: WindowDrawCommand,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StartupMessageFlush {
    RestoreMessageUi,
    Replay,
}

pub struct Renderer {
    images: image_preview::ImageRenderer,
    notebooks: notebook::NotebookRenderer,
    bloom_renderer: bloom::BloomRenderer,
    cursor_renderer: CursorRenderer,
    pub grid_renderer: GridRenderer,
    current_mode: EditorMode,

    pub progress_bar: ProgressBar,

    pub rendered_windows: HashMap<u64, RenderedWindow>,
    pub window_regions: Vec<WindowDrawDetails>,
    pub notebook_output_regions: Vec<NotebookOutputRegion>,
    pub notebook_selection_generation: u64,
    /// committed with this route grids, including before its OS window exists.
    #[cfg(target_os = "macos")]
    pub scrollbar_snapshot: Option<ScrollbarSnapshot>,

    profiler: profiler::Profiler,
    pub os_scale_factor: f64,
    pub user_scale_factor: f64,

    settings: Arc<Settings>,
    message_selection: Option<MessageSelection>,
    float_shadow_exclusions: HashSet<u64>,
    startup_messages: Vec<StartupMessage>,
    startup_message_ui_restored: bool,
}

/// Results of processing the draw commands from the command channel.
pub struct DrawCommandResult {
    #[cfg(target_os = "macos")]
    pub scrollbar_changed: bool,
    pub font_changed: bool,
    pub should_show: bool,
    pub startup_message_flush: Option<StartupMessageFlush>,
    pub startup_messages: Vec<StartupMessage>,
}

impl Renderer {
    pub fn new(os_scale_factor: f64, init_config: Config, settings: Arc<Settings>) -> Self {
        let window_settings = settings.get::<WindowSettings>();

        let user_scale_factor = window_settings.scale_factor.into();
        let scale_factor = user_scale_factor * os_scale_factor;
        let cursor_renderer = CursorRenderer::new(settings.clone());
        let mut grid_renderer = GridRenderer::new(scale_factor, settings.clone());
        let mut font_config_state = settings.get::<FontConfigState>();
        font_config_state.has_font = init_config.font.is_some();
        settings.set(&font_config_state);
        grid_renderer.update_font_options(init_config.font.map(|x| x.into()).unwrap_or_default());
        grid_renderer.handle_box_drawing_update(init_config.box_drawing.unwrap_or_default());
        let current_mode = EditorMode::Unknown(String::from(""));

        let rendered_windows = HashMap::new();
        let window_regions = Vec::new();

        let profiler = profiler::Profiler::new(12.0, settings.clone());

        let progress_bar = ProgressBar::new();

        Renderer {
            images: image_preview::ImageRenderer::default(),
            notebooks: notebook::NotebookRenderer::default(),
            bloom_renderer: bloom::BloomRenderer::default(),
            rendered_windows,
            #[cfg(target_os = "macos")]
            scrollbar_snapshot: None,
            cursor_renderer,
            grid_renderer,
            current_mode,
            window_regions,
            notebook_output_regions: Vec::new(),
            notebook_selection_generation: 0,
            profiler,
            progress_bar,
            os_scale_factor,
            user_scale_factor,
            settings,
            message_selection: None,
            float_shadow_exclusions: HashSet::new(),
            startup_messages: Vec::new(),
            startup_message_ui_restored: false,
        }
    }

    pub fn handle_event(&mut self, event: &WindowEvent) {
        self.cursor_renderer.handle_event(event);
    }

    pub fn font_names(&self) -> Vec<String> {
        self.grid_renderer.font_names()
    }

    pub fn set_message_selection(&mut self, selection: Option<MessageSelection>) {
        self.message_selection = selection;
    }

    pub fn active_notebook_selection(&self) -> Option<MessageSelection> {
        let selection = self.message_selection?;
        selection.notebook?;
        self.selection_bounds(&selection)?;
        Some(selection)
    }

    fn invalidate_notebook_selection(&mut self) {
        self.notebook_selection_generation = self.notebook_selection_generation.wrapping_add(1);
        self.notebook_output_regions.clear();
        if self.message_selection.is_some_and(|selection| selection.notebook.is_some()) {
            self.message_selection = None;
        }
    }

    fn refresh_notebook_output_regions(
        &mut self,
        scale: GridScale,
        windows: &[notebook::NotebookWindow],
    ) {
        let regions = self
            .notebooks
            .output_bounds(scale, windows)
            .into_iter()
            .filter_map(|(grid, bounds)| {
                self.rendered_windows.get(&grid)?.notebook_output_region(bounds, scale)
            })
            .collect::<Vec<_>>();
        if regions != self.notebook_output_regions {
            self.notebook_selection_generation = self.notebook_selection_generation.wrapping_add(1);
            self.notebook_output_regions = regions;
        }
    }

    fn selection_bounds(&self, selection: &MessageSelection) -> Option<GridRect<u32>> {
        let window = self.rendered_windows.get(&selection.grid_id)?;
        if let Some(id) = selection.notebook {
            if id.generation != self.notebook_selection_generation {
                return None;
            }
            let region = self.notebook_output_regions.get(id.region)?;
            (region.grid_id == selection.grid_id).then_some(region.cells)
        } else {
            matches!(window.window_type, WindowType::Message { .. }).then_some(
                GridRect::from_min_max((0, 0), (window.grid_size.width, window.grid_size.height)),
            )
        }
    }

    pub fn selection_text(&self, selection: MessageSelection) -> Option<String> {
        let bounds = self.selection_bounds(&selection)?;
        let window = self.rendered_windows.get(&selection.grid_id)?;
        let lines = selection_spans(selection.start, selection.end, bounds)
            .into_iter()
            .map(|(row, start, end)| window.line_text_range(row, start, end))
            .collect::<Option<Vec<_>>>()?;
        lines.iter().any(|line| !line.is_empty()).then(|| lines.join("\n"))
    }

    pub fn prepare_frame(&mut self) -> ShouldRender {
        self.cursor_renderer.prepare_frame()
    }

    pub fn draw_frame(&mut self, root_canvas: &Canvas, content_region: &PixelRect<f32>, dt: f32) {
        tracy_zone!("renderer_draw_frame");
        let window_settings = self.settings.get::<WindowSettings>();
        let opacity = if window_settings.normal_opacity < 1.0 {
            window_settings.normal_opacity
        } else {
            window_settings.opacity
        };
        let default_background = self.grid_renderer.get_default_background(opacity);
        let grid_scale = self.grid_renderer.grid_scale;
        let notebook_windows = self
            .rendered_windows
            .values()
            .filter_map(|window| notebook::NotebookWindow::from_window(window, grid_scale))
            .collect_vec();

        let layer_grouping = self.settings.get::<RendererSettings>().experimental_layer_grouping;
        root_canvas.clear(default_background);
        root_canvas.save();
        root_canvas.reset_matrix();
        self.draw_bottom_margin_background(root_canvas, Some(content_region), &window_settings);
        root_canvas.clip_rect(to_skia_rect(content_region), None, Some(false));

        let (root_windows, floating_layers) = {
            let (mut root_windows, mut floating_windows): (
                Vec<&mut RenderedWindow>,
                Vec<&mut RenderedWindow>,
            ) = self
                .rendered_windows
                .values_mut()
                .filter(|window| !window.hidden)
                .partition(|window| window.anchor_info.is_none());

            root_windows
                .sort_by(|window_a, window_b| window_a.id.partial_cmp(&window_b.id).unwrap());
            floating_windows.sort_by(floating_sort);

            let mut floating_layers = vec![];

            let mut base_zindex = 0;
            let mut last_zindex = 0;
            let mut current_windows = vec![];

            let mut prev_is_message = false;
            for window in floating_windows {
                let zindex = window.anchor_info.as_ref().unwrap().sort_order.z_index;
                log::debug!("zindex: {zindex}, base: {base_zindex}");
                let is_message = matches!(window.window_type, WindowType::Message { .. });
                // NOTE: The message window is always on it's own layer
                if !current_windows.is_empty() && zindex != last_zindex
                    || is_message
                    || prev_is_message
                {
                    // Group floating windows by consecutive z indices if layer_grouping is enabled,
                    // Otherwise group all windows inside a single layer

                    if !layer_grouping || zindex - last_zindex > 1 {
                        for windows in group_windows(current_windows, grid_scale) {
                            floating_layers.push(FloatingLayer { windows });
                        }
                        current_windows = vec![];
                    }
                }
                prev_is_message = is_message;

                if current_windows.is_empty() {
                    base_zindex = zindex;
                }
                current_windows.push(window);
                last_zindex = zindex;
            }

            if !current_windows.is_empty() {
                for windows in group_windows(current_windows, grid_scale) {
                    floating_layers.push(FloatingLayer { windows });
                }
            }

            for layer in &mut floating_layers {
                layer.windows.sort_by(floating_sort);
                log::debug!(
                    "layer: {:?}",
                    layer
                        .windows
                        .iter()
                        .map(|w| (w.id, w.anchor_info.as_ref().unwrap().sort_order.clone()))
                        .collect_vec()
                );
            }

            (root_windows, floating_layers)
        };

        let settings = self.settings.get::<RendererSettings>();
        let max_root_x = max_window_max_x(&root_windows, grid_scale);
        let root_window_regions = root_windows
            .into_iter()
            .map(|window| {
                let region = window.background_region(grid_scale);
                let rightmost_root_window = is_rightmost_window_edge(region.max.x, max_root_x);
                window.draw(
                    root_canvas,
                    default_background,
                    grid_scale,
                    Some(*content_region),
                    rightmost_root_window,
                )
            })
            .collect_vec();

        // Native previews belong to ordinary editor splits. Draw them before floating
        // windows so menus and error messages retain their normal stacking order.
        let image_floating_regions = floating_layers
            .iter()
            .flat_map(|layer| {
                let max_x = max_window_max_x(&layer.windows, grid_scale);
                layer.windows.iter().map(move |window| {
                    let region = window.pixel_region(grid_scale);
                    window.expanded_pixel_region(
                        region,
                        Some(*content_region),
                        grid_scale,
                        is_rightmost_window_edge(region.max.x, max_x),
                    )
                })
            })
            .collect_vec();
        self.images.prepare_anchored_views(
            grid_scale,
            &mut self.notebooks,
            &notebook_windows,
            &image_floating_regions,
        );
        self.images.draw(root_canvas, grid_scale);
        self.notebooks.draw(root_canvas, grid_scale, false, &[], &notebook_windows);

        let floating_window_regions = floating_layers
            .into_iter()
            .flat_map(|mut layer| {
                layer.draw(
                    root_canvas,
                    &settings,
                    default_background,
                    grid_scale,
                    Some(*content_region),
                    &self.float_shadow_exclusions,
                )
            })
            .collect_vec();

        // The adapter confines these to their owner output float and suspends
        // them whenever another popup overlaps; ordinary split images stay below floats.
        self.images.draw_overlay(root_canvas, grid_scale);
        self.notebooks.draw(
            root_canvas,
            grid_scale,
            true,
            &floating_window_regions,
            &notebook_windows,
        );
        let image_bloom_exclusion =
            self.images.bloom_exclusion(grid_scale, &floating_window_regions);
        self.window_regions =
            root_window_regions.into_iter().chain(floating_window_regions).collect();
        self.refresh_notebook_output_regions(grid_scale, &notebook_windows);
        self.draw_message_selection(root_canvas, grid_scale);
        self.cursor_renderer.draw(&mut self.grid_renderer, root_canvas);

        root_canvas.save();
        if let Some(mask) = image_bloom_exclusion {
            root_canvas.clip_path(&mask, skia_safe::ClipOp::Difference, false);
        }
        self.bloom_renderer.draw(root_canvas, &settings, default_background);
        root_canvas.restore();

        self.profiler.draw(root_canvas, dt);

        let grid_size = self.get_grid_size();

        root_canvas.restore();

        let progress_bar_settings = self.settings.get::<ProgressBarSettings>();
        self.progress_bar.draw(&progress_bar_settings, root_canvas, &self.grid_renderer, grid_size);

        #[cfg(feature = "profiling")]
        plot_skia_cache();
    }

    fn draw_bottom_margin_background(
        &self,
        canvas: &Canvas,
        content_region: Option<&PixelRect<f32>>,
        settings: &WindowSettings,
    ) {
        let Some(opacity) = settings.bottom_margin_opacity.0.filter(|value| value.is_finite())
        else {
            return;
        };
        if !settings.opacity.is_finite() {
            return;
        }
        // Only grid 1 owns the global status line. Split and floating grids
        // must never extend their final row into the window's bottom margin.
        let Some(root) = self.rendered_windows.get(&1).filter(|window| !window.hidden) else {
            return;
        };
        let Some(rect) = bottom_margin_rect(
            canvas,
            root.pixel_region(self.grid_renderer.grid_scale),
            content_region,
            self.grid_renderer.grid_scale.height(),
        ) else {
            return;
        };
        let mut paint = Paint::default();
        paint.set_anti_alias(false);
        paint.set_blend_mode(skia_safe::BlendMode::Src);
        paint.set_color(self.grid_renderer.get_default_background_color());
        // Match explicit highlight blend: global opacity applies, while the
        // ordinary editing area's normal_opacity remains independent.
        paint.set_alpha_f(opacity.clamp(0.0, 1.0) * settings.opacity.clamp(0.0, 1.0));
        canvas.draw_rect(rect, &paint);
    }

    fn message_selection_window(&self) -> Option<(&MessageSelection, &RenderedWindow)> {
        let selection = self.message_selection.as_ref()?;
        let window = self.rendered_windows.get(&selection.grid_id)?;
        self.selection_bounds(selection)?;
        Some((selection, window))
    }

    fn draw_message_selection(&mut self, root_canvas: &Canvas, grid_scale: GridScale) {
        let Some((selection, window)) = self.message_selection_window() else {
            return;
        };

        let Some(bounds) = self.selection_bounds(selection) else {
            return;
        };
        let spans = selection_spans(selection.start, selection.end, bounds);
        let pixel_region = window.pixel_region(grid_scale);
        root_canvas.save();
        root_canvas.clip_rect(to_skia_rect(&pixel_region), None, Some(false));

        let selection_color = self
            .grid_renderer
            .default_style
            .colors
            .foreground
            .or(self.grid_renderer.default_style.colors.background)
            .unwrap_or_else(|| Color4f::from(self.grid_renderer.get_default_background(1.0)));

        let mut paint = Paint::new(selection_color, None);
        paint.set_anti_alias(false);
        paint.set_alpha_f(MESSAGE_SELECTION_ALPHA);

        if let Some(id) = selection.notebook {
            root_canvas.clip_rect(
                to_skia_rect(&self.notebook_output_regions[id.region].bounds),
                None,
                false,
            );
            for details in &self.window_regions {
                if self
                    .rendered_windows
                    .get(&details.id)
                    .is_some_and(|window| window.anchor_info.is_some())
                {
                    root_canvas.clip_rect(
                        to_skia_rect(&details.region),
                        skia_safe::ClipOp::Difference,
                        false,
                    );
                }
            }
        }
        for (row, start, end) in spans {
            if let Some(rect) = window.grid_row_rect(row, start, end, grid_scale) {
                root_canvas.draw_rect(rect, &paint);
            }
        }

        root_canvas.restore();
    }

    pub fn animate_frame(&mut self, grid_rect: &GridRect<f32>, dt: f32) -> bool {
        let windows = {
            let (mut root_windows, mut floating_windows): (
                Vec<&mut RenderedWindow>,
                Vec<&mut RenderedWindow>,
            ) = self
                .rendered_windows
                .values_mut()
                .filter(|window| !window.hidden)
                .partition(|window| window.anchor_info.is_none());

            root_windows
                .sort_by(|window_a, window_b| window_a.id.partial_cmp(&window_b.id).unwrap());

            floating_windows.sort_by(floating_sort);

            root_windows.into_iter().chain(floating_windows)
        };

        let settings = self.settings.get::<RendererSettings>();
        // Clippy recommends short-circuiting with any which is not what we want
        #[allow(clippy::unnecessary_fold)]
        let mut animating =
            windows.fold(false, |acc, window| acc | window.animate(&settings, grid_rect, dt));

        let windows = &self.rendered_windows;
        let grid_scale = self.grid_renderer.grid_scale;
        self.cursor_renderer.update_cursor_destination(grid_scale, windows);

        animating |= self.cursor_renderer.animate(&self.current_mode, &self.grid_renderer, dt);

        let progress_bar_settings = self.settings.get::<ProgressBarSettings>();
        self.progress_bar.animate(&progress_bar_settings, dt);
        animating |= self.progress_bar.is_active();

        animating
    }

    pub fn handle_config_changed(&mut self, config: RendererHotReloadConfigs) {
        match config {
            RendererHotReloadConfigs::Font(font) => {
                let font = *font;
                let mut font_config_state = self.settings.get::<FontConfigState>();
                font_config_state.has_font = font.is_some();
                self.settings.set(&font_config_state);
                match font {
                    Some(font) => {
                        self.grid_renderer.update_font_options(font.into());
                    }
                    None => {
                        self.grid_renderer.update_font_options(FontOptions::default());
                    }
                }
            }
            RendererHotReloadConfigs::BoxDrawing(settings) => {
                self.grid_renderer.handle_box_drawing_update(settings.unwrap_or_default())
            }
        }
    }

    pub fn handle_draw_commands(&mut self, batch: Vec<DrawCommand>) -> DrawCommandResult {
        let settings = self.settings.get::<RendererSettings>();
        let mut result = DrawCommandResult {
            #[cfg(target_os = "macos")]
            scrollbar_changed: false,
            font_changed: false,
            should_show: false,
            startup_message_flush: None,
            startup_messages: vec![],
        };

        for draw_command in batch {
            self.handle_draw_command(draw_command, &mut result);
            tracy_named_frame!("neovim draw batch processed");
        }

        if self.should_auto_replay_startup_messages(&result) {
            result.startup_message_flush = Some(StartupMessageFlush::Replay);
        }

        if result.startup_message_flush.is_some() {
            result.startup_messages = self.take_startup_messages();
        }

        self.flush(&settings);

        result
    }

    pub fn sync_scale_factor(&mut self) {
        let user_scale_factor = self.settings.get::<WindowSettings>().scale_factor.into();
        self.handle_user_scale_factor_change(user_scale_factor);
    }

    pub fn handle_user_scale_factor_change(&mut self, user_scale_factor: f64) {
        self.user_scale_factor = user_scale_factor;
        self.update_scale_factor();
    }

    pub fn handle_os_scale_factor_change(&mut self, os_scale_factor: f64) {
        self.os_scale_factor = os_scale_factor;
        self.update_scale_factor();
    }

    fn update_scale_factor(&mut self) {
        self.grid_renderer
            .handle_scale_factor_update(self.os_scale_factor * self.user_scale_factor);
    }

    pub fn prepare_lines(&mut self, force: bool) {
        let opacity = self.settings.get::<WindowSettings>().opacity;
        self.rendered_windows
            .iter_mut()
            .for_each(|(_, w)| w.prepare_lines(&mut self.grid_renderer, opacity, force));
    }

    fn window_command_changes_notebook_selection(
        &self,
        grid_id: u64,
        command: &WindowDrawCommand,
    ) -> bool {
        let Some(window) = self.rendered_windows.get(&grid_id) else {
            return !self.notebook_output_regions.is_empty()
                && matches!(command, WindowDrawCommand::Position { anchor_info: Some(_), .. });
        };
        if !window.changes_selection(command) {
            return false;
        }
        if let WindowDrawCommand::DrawLine { row, .. } = command {
            return self.notebook_output_regions.iter().any(|region| {
                region.grid_id == grid_id
                    && *row >= region.cells.min.y as usize
                    && *row < region.cells.max.y as usize
            });
        }
        self.notebook_output_regions.iter().any(|region| region.grid_id == grid_id)
            || (!self.notebook_output_regions.is_empty() && window.anchor_info.is_some())
    }

    fn handle_draw_command(&mut self, draw_command: DrawCommand, result: &mut DrawCommandResult) {
        if let DrawCommand::Window { grid_id, command } = &draw_command
            && self.window_command_changes_notebook_selection(*grid_id, command)
        {
            self.invalidate_notebook_selection();
        }
        match draw_command {
            DrawCommand::FloatShadowExclusions(windows) => {
                self.float_shadow_exclusions = windows.into_iter().collect();
            }
            DrawCommand::ImagePreview(command) => self.images.handle(command),
            DrawCommand::NotebookFrames(snapshot) => {
                self.notebooks.replace(snapshot);
                let scale = self.grid_renderer.grid_scale;
                let windows = self
                    .rendered_windows
                    .values()
                    .filter_map(|window| notebook::NotebookWindow::from_window(window, scale))
                    .collect_vec();
                self.refresh_notebook_output_regions(scale, &windows);
            }
            DrawCommand::Window { grid_id, command: WindowDrawCommand::Close } => {
                self.rendered_windows.remove(&grid_id);
            }
            DrawCommand::Window { grid_id, command } => {
                match self.rendered_windows.entry(grid_id) {
                    Entry::Occupied(mut occupied_entry) => {
                        let rendered_window = occupied_entry.get_mut();
                        rendered_window.handle_window_draw_command(command);
                    }
                    Entry::Vacant(vacant_entry) => match command {
                        WindowDrawCommand::Position { .. }
                        | WindowDrawCommand::ViewportMargins { .. } => {
                            let mut new_window = RenderedWindow::new(grid_id);
                            new_window.handle_window_draw_command(command);
                            vacant_entry.insert(new_window);
                        }
                        _ => {
                            let settings = self.settings.get::<CmdLineSettings>();
                            // Neovim can emit draw commands before a window is positioned when using multigrid.
                            if !settings.no_multi_grid {
                                log::warn!(
                                    "Ignoring {command:?} sent for uninitialized grid {grid_id}"
                                );
                            }
                        }
                    },
                }
            }
            DrawCommand::UpdateCursor(new_cursor) => {
                self.cursor_renderer.update_cursor(new_cursor);
            }
            #[cfg(target_os = "macos")]
            DrawCommand::ScrollbarSnapshot(snapshot) => {
                self.scrollbar_snapshot = Some(snapshot);
                result.scrollbar_changed = true;
            }
            DrawCommand::FontChanged(new_font) => {
                self.grid_renderer.update_font(&new_font);
                result.font_changed = true;
            }
            DrawCommand::LineSpaceChanged(new_linespace) => {
                self.grid_renderer.update_linespace(new_linespace);
                result.font_changed = true;
            }
            DrawCommand::DefaultStyleChanged(new_style) => {
                self.grid_renderer.default_style = Arc::new(new_style);
            }
            DrawCommand::ModeChanged(new_mode) => {
                self.current_mode = new_mode;
            }
            DrawCommand::StartupMessage { message, replace_last, append } => {
                self.push_startup_message(message, replace_last, append);
            }
            DrawCommand::ClearStartupMessages => {
                self.startup_messages.pop();
            }
            DrawCommand::StartupPrompt => {
                result.should_show = true;
                result.startup_message_flush = Some(StartupMessageFlush::RestoreMessageUi);
            }
            DrawCommand::ReplayStartupMessages => {
                self.startup_message_ui_restored = true;
                result.startup_message_flush = Some(StartupMessageFlush::Replay);
            }
            DrawCommand::UIReady => {
                result.should_show = true;
                result.startup_message_flush = Some(StartupMessageFlush::RestoreMessageUi);
            }
        }
    }

    fn should_auto_replay_startup_messages(&self, result: &DrawCommandResult) -> bool {
        self.startup_message_ui_restored
            && result.startup_message_flush.is_none()
            && !self.startup_messages.is_empty()
    }

    fn push_startup_message(&mut self, message: StartupMessage, replace_last: bool, append: bool) {
        match (append, replace_last, self.startup_messages.last_mut()) {
            (true, _, Some(last_message)) => last_message.content.push_str(&message.content),
            (_, true, Some(last_message)) => *last_message = message,
            _ => {
                self.startup_messages.push(message);
                self.trim_startup_messages();
            }
        }
    }

    fn trim_startup_messages(&mut self) {
        let overflow = self.startup_messages.len().saturating_sub(STARTUP_MESSAGE_LIMIT);
        if overflow > 0 {
            self.startup_messages.drain(..overflow);
        }
    }

    fn take_startup_messages(&mut self) -> Vec<StartupMessage> {
        std::mem::take(&mut self.startup_messages)
            .into_iter()
            .flat_map(|message| {
                let kind = message.kind;
                message
                    .content
                    .lines()
                    .map(str::trim_end)
                    .filter(|line| !line.is_empty())
                    .map(move |line| StartupMessage { kind, content: line.to_string() })
                    .collect_vec()
            })
            .collect()
    }

    pub fn flush(&mut self, renderer_settings: &RendererSettings) {
        self.rendered_windows.iter_mut().for_each(|(_, w)| w.flush(renderer_settings));
    }

    pub fn clear(&mut self) {
        self.float_shadow_exclusions.clear();
        self.invalidate_notebook_selection();
        self.images.clear();
        self.notebooks.clear();
        self.rendered_windows.clear();
        #[cfg(target_os = "macos")]
        {
            self.scrollbar_snapshot = None;
        }
        self.window_regions.clear();
        self.cursor_renderer = CursorRenderer::new(self.settings.clone());
        self.progress_bar = ProgressBar::new();
        self.current_mode = EditorMode::Unknown(String::new());
        self.message_selection = None;
        self.startup_messages.clear();
        self.startup_message_ui_restored = false;
    }

    pub fn get_cursor_destination(&self) -> PixelPos<f32> {
        self.cursor_renderer.get_destination()
    }

    pub fn get_grid_size(&self) -> GridSize<u32> {
        if let Some(main_grid) = self.rendered_windows.get(&1) {
            main_grid.grid_size
        } else {
            DEFAULT_GRID_SIZE
        }
    }
}

fn bottom_margin_rect(
    canvas: &Canvas,
    root_region: PixelRect<f32>,
    content_region: Option<&PixelRect<f32>>,
    cell_height: f32,
) -> Option<skia_safe::Rect> {
    let size = canvas.base_layer_size();
    let canvas_region =
        PixelRect::from_min_max((0.0, 0.0), (size.width as f32, size.height as f32));
    let content = content_region.unwrap_or(&canvas_region);
    let top = root_region.max.y;
    let bottom = content.max.y.min(canvas_region.max.y);
    let gap = bottom - top;
    let left = content.min.x.max(0.0);
    let right = content.max.x.min(canvas_region.max.x);
    if [top, bottom, gap, left, right, cell_height].into_iter().all(f32::is_finite)
        && cell_height > 0.0
        && gap > 0.0
        && gap < cell_height
        && top >= content.min.y
        && right > left
        && root_region.max.x > root_region.min.x
        && root_region.max.y > root_region.min.y
    {
        Some(skia_safe::Rect::new(left, top, right, bottom))
    } else {
        // A whole missing row means the grid is stale during resize. Do not
        // stretch the requested material across that unrendered editor area.
        None
    }
}

pub fn is_rightmost_window_edge(region_max_x: f32, max_x: f32) -> bool {
    max_x.is_finite() && (region_max_x - max_x).abs() <= f32::EPSILON
}

pub fn max_window_max_x(windows: &[&mut RenderedWindow], grid_scale: GridScale) -> f32 {
    windows.iter().fold(f32::NEG_INFINITY, |max_x, window| {
        let region = window.background_region(grid_scale);
        max_x.max(region.max.x)
    })
}

/// Defines how floating windows are sorted.
fn floating_sort(window_a: &&mut RenderedWindow, window_b: &&mut RenderedWindow) -> Ordering {
    let orda = &window_a.anchor_info.as_ref().unwrap().sort_order;
    let ordb = &window_b.anchor_info.as_ref().unwrap().sort_order;
    orda.cmp(ordb)
}

#[derive(Clone)]
pub enum WindowConfigType {
    OpenGL(glutin::config::Config),
    #[cfg(target_os = "windows")]
    Direct3D,
    #[cfg(target_os = "macos")]
    Metal,
}

#[derive(Clone)]
pub struct WindowConfig {
    pub window: Rc<Window>,
    pub config: WindowConfigType,
}

#[cfg(target_os = "macos")]
pub fn build_window_config(
    window_attributes: WindowAttributes,
    event_loop: &ActiveEventLoop,
    settings: &Settings,
) -> WindowConfig {
    let cmd_line_settings = settings.get::<CmdLineSettings>();
    if cmd_line_settings.opengl {
        opengl::build_window(window_attributes, event_loop)
    } else {
        let window = event_loop.create_window(window_attributes).unwrap();
        let config = WindowConfigType::Metal;
        WindowConfig { window: window.into(), config }
    }
}

#[cfg(target_os = "windows")]
pub fn build_window_config(
    window_attributes: WindowAttributes,
    event_loop: &ActiveEventLoop,
    settings: &Settings,
) -> WindowConfig {
    let cmd_line_settings = settings.get::<CmdLineSettings>();
    if cmd_line_settings.opengl {
        opengl::build_window(window_attributes, event_loop)
    } else {
        let window = event_loop.create_window(window_attributes).unwrap();
        let config = WindowConfigType::Direct3D;
        WindowConfig { window: window.into(), config }
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
pub fn build_window_config(
    window_attributes: WindowAttributes,
    event_loop: &ActiveEventLoop,
    _settings: &Settings,
) -> WindowConfig {
    opengl::build_window(window_attributes, event_loop)
}

pub trait SkiaRenderer {
    fn window(&self) -> Rc<Window>;
    fn flush(&mut self);
    fn swap_buffers(&mut self);
    fn canvas(&mut self) -> &Canvas;
    fn resize(&mut self);
    fn create_vsync(&self, proxy: EventLoopProxy<EventPayload>) -> VSync;
    #[cfg(feature = "gpu_profiling")]
    fn tracy_create_gpu_context(&self, name: &str) -> Box<dyn GpuCtx>;
}

pub fn create_skia_renderer(
    window: &WindowConfig,
    srgb: bool,
    vsync: bool,
    settings: Arc<Settings>,
) -> Box<dyn SkiaRenderer> {
    let renderer: Box<dyn SkiaRenderer> = match &window.config {
        WindowConfigType::OpenGL(..) => {
            Box::new(opengl::OpenGLSkiaRenderer::new(window.clone(), srgb, vsync, settings.clone()))
        }
        #[cfg(target_os = "windows")]
        WindowConfigType::Direct3D => {
            Box::new(d3d::D3DSkiaRenderer::new(window.window.clone(), settings.clone()))
        }
        #[cfg(target_os = "macos")]
        WindowConfigType::Metal => Box::new(metal::MetalSkiaRenderer::new(
            window.window.clone(),
            srgb,
            vsync,
            settings.clone(),
        )),
    };
    tracy_create_gpu_context("main_render_context", renderer.as_ref());
    renderer
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::bridge::MessageKind;

    fn create_renderer() -> Renderer {
        let settings = Arc::new(Settings::new());
        settings.register::<WindowSettings>();
        settings.register::<RendererSettings>();
        Renderer::new(2.0, Config::default(), settings)
    }

    #[test]
    fn picker_shadow_scope_snapshot_replaces_and_clears_owner_ids() {
        let mut renderer = create_renderer();
        renderer.handle_draw_commands(vec![DrawCommand::FloatShadowExclusions(vec![
            1001, 1002, 1003, 1004,
        ])]);
        assert_eq!(renderer.float_shadow_exclusions.len(), 4);
        renderer.handle_draw_commands(vec![DrawCommand::FloatShadowExclusions(vec![])]);
        assert!(renderer.float_shadow_exclusions.is_empty());
        renderer.handle_draw_commands(vec![DrawCommand::FloatShadowExclusions(vec![1001])]);
        renderer.clear();
        assert!(renderer.float_shadow_exclusions.is_empty());
    }

    #[test]
    fn notebook_output_selection_copies_rendered_text_and_cancels_changed_frames_content_and_scroll()
     {
        use crate::{editor::Line, units::PixelSize};
        use rmpv::Value;
        let mut renderer = create_renderer();
        let scale = GridScale::new(PixelSize::new(10.0, 20.0));
        renderer.grid_renderer.grid_scale = scale;
        let command = |command| DrawCommand::Window { grid_id: 2, command };
        renderer.handle_draw_commands(vec![
            command(WindowDrawCommand::Position {
                grid_position: (0.0, 0.0),
                grid_size: (14, 8),
                anchor_info: None,
                window_type: WindowType::Editor,
            }),
            command(WindowDrawCommand::HostSize { width: 16, height: 8 }),
            command(WindowDrawCommand::Viewport { window_id: 1000, scroll_delta: 0.0 }),
            command(WindowDrawCommand::DrawLine {
                row: 3,
                line: Line::from_test_cells(&[
                    "1", "2", "3", "4", "A", "中", "", "e\u{301}", "B", " ", " ", " ", " ", " ",
                ]),
            }),
            command(WindowDrawCommand::DrawLine {
                row: 4,
                line: Line::from_test_cells(&[
                    "1", "2", "3", "4", "C", "D", " ", " ", " ", " ", " ", " ", " ", " ",
                ]),
            }),
            command(WindowDrawCommand::DrawLine {
                row: 5,
                line: Line::from_test_cells(&[
                    "1", "2", "3", "4", "Z", " ", " ", " ", " ", " ", " ", " ", " ", " ",
                ]),
            }),
        ]);
        let rect = |row: f64, col: f64, width: f64, height: f64| {
            Value::Map(vec![
                ("row".into(), row.into()),
                ("col".into(), col.into()),
                ("width".into(), width.into()),
                ("height".into(), height.into()),
            ])
        };
        let packet = notebook::FrameSnapshot::parse(&[Value::Array(vec![Value::Map(vec![
            ("kind".into(), "output".into()),
            ("rect".into(), rect(2.5, 3.2, 11.6, 3.7)),
            ("clip".into(), rect(0.0, 0.0, 16.0, 8.0)),
            (
                "anchor".into(),
                Value::Map(vec![
                    ("window".into(), 1000.into()),
                    ("epoch".into(), 1.into()),
                    ("scroll".into(), true.into()),
                ]),
            ),
        ])])])
        .unwrap();
        renderer.handle_draw_commands(vec![DrawCommand::NotebookFrames(packet.clone())]);
        let refresh = |renderer: &mut Renderer| {
            let windows = renderer
                .rendered_windows
                .values()
                .filter_map(|window| notebook::NotebookWindow::from_window(window, scale))
                .collect_vec();
            renderer.refresh_notebook_output_regions(scale, &windows);
        };
        refresh(&mut renderer);
        let region = renderer.notebook_output_regions[0];
        assert_eq!(
            region.cells,
            GridRect::from_min_max((4, 3), (14, 6)),
            "no line numbers, seam row, or outside margin"
        );
        let select = |renderer: &Renderer, start, end| MessageSelection {
            grid_id: 2,
            start,
            end,
            notebook: Some(NotebookSelectionId {
                generation: renderer.notebook_selection_generation,
                region: 0,
            }),
        };
        assert_eq!(
            renderer.selection_text(select(&renderer, (4, 3).into(), (8, 3).into())).as_deref(),
            Some("A中e\u{301}B")
        );
        assert_eq!(
            renderer.selection_text(select(&renderer, (8, 3).into(), (4, 3).into())).as_deref(),
            Some("A中e\u{301}B")
        );
        assert_eq!(
            renderer.selection_text(select(&renderer, (6, 3).into(), (6, 3).into())).as_deref(),
            Some("中"),
            "wide continuation keeps the full glyph"
        );
        assert_eq!(
            renderer.selection_text(select(&renderer, (7, 5).into(), (8, 3).into())).as_deref(),
            Some("B\nCD\nZ"),
            "reverse row/column association survives"
        );
        let held = select(&renderer, (5, 3).into(), (7, 3).into());
        renderer.set_message_selection(Some(held));
        let held_generation = renderer.notebook_selection_generation;
        for _ in 0..3 {
            // Hold across the Notebook UI's 150 ms heartbeat. Repeated layout
            // and text notifications must not cancel a partial-field drag.
            std::thread::sleep(std::time::Duration::from_millis(160));
            renderer.handle_draw_commands(vec![
                command(WindowDrawCommand::Viewport { window_id: 1000, scroll_delta: 0.0 }),
                command(WindowDrawCommand::HostSize { width: 16, height: 8 }),
                command(WindowDrawCommand::Position {
                    grid_position: (0.0, 0.0),
                    grid_size: (14, 8),
                    anchor_info: None,
                    window_type: WindowType::Editor,
                }),
                command(WindowDrawCommand::DrawLine {
                    row: 3,
                    line: Line::from_test_cells(&[
                        "1", "2", "3", "4", "A", "中", "", "e\u{301}", "B", " ", " ", " ", " ", " ",
                    ]),
                }),
                DrawCommand::NotebookFrames(packet.clone()),
            ]);
            refresh(&mut renderer);
            assert_eq!(renderer.notebook_selection_generation, held_generation, "idle heartbeat");
            assert_eq!(renderer.active_notebook_selection(), Some(held));
            assert_eq!(renderer.selection_text(held).as_deref(), Some("中e\u{301}"));
        }
        let old = select(&renderer, (4, 3).into(), (8, 3).into());
        renderer.set_message_selection(Some(old));
        assert_eq!(renderer.active_notebook_selection(), Some(old));
        assert_eq!(
            renderer.selection_text(renderer.active_notebook_selection().unwrap()).as_deref(),
            Some("A中e\u{301}B"),
            "retained selection supplies the same text to Copy"
        );
        renderer.handle_draw_commands(vec![DrawCommand::NotebookFrames(notebook::FrameSnapshot {
            frames: Vec::new(),
            viewports: Vec::new(),
        })]);
        assert!(renderer.selection_text(old).is_none(), "frame update cancels before a repaint");
        assert!(renderer.active_notebook_selection().is_none());
        renderer.handle_draw_commands(vec![DrawCommand::NotebookFrames(packet)]);
        refresh(&mut renderer);
        let old = select(&renderer, (4, 3).into(), (8, 3).into());
        renderer.set_message_selection(Some(old));
        renderer.handle_draw_commands(vec![command(WindowDrawCommand::DrawLine {
            row: 4,
            line: Line::from_test_cells(&["changed"]),
        })]);
        assert!(renderer.selection_text(old).is_none(), "content update cannot copy stale text");
        assert!(renderer.active_notebook_selection().is_none());
        refresh(&mut renderer);
        let old = select(&renderer, (4, 3).into(), (8, 3).into());
        renderer.set_message_selection(Some(old));
        renderer.handle_draw_commands(vec![command(WindowDrawCommand::Viewport {
            window_id: 1000,
            scroll_delta: 1.0,
        })]);
        assert!(renderer.selection_text(old).is_none(), "scroll update cancels");
        assert!(renderer.active_notebook_selection().is_none());
        refresh(&mut renderer);
        let old = select(&renderer, (4, 2).into(), (8, 2).into());
        renderer.rendered_windows.get_mut(&2).unwrap().scroll_animation.position = 0.25;
        refresh(&mut renderer);
        assert!(renderer.selection_text(old).is_none(), "animation geometry changes cancel");
    }

    fn startup_message(content: &str) -> StartupMessage {
        StartupMessage { kind: MessageKind::Error, content: content.to_string() }
    }

    #[test]
    fn user_scale_updates_apply_immediately() {
        let mut renderer = create_renderer();
        let initial_size = renderer.grid_renderer.shaper.current_size();

        renderer.handle_user_scale_factor_change(1.5);

        assert_eq!(renderer.user_scale_factor, 1.5);
        assert_eq!(renderer.grid_renderer.shaper.current_size(), initial_size * 1.5);
    }

    #[test]
    fn scale_can_be_resynced_from_settings_after_renderer_creation() {
        let settings = Arc::new(Settings::new());
        settings.register::<WindowSettings>();

        let mut renderer = Renderer::new(1.0, Config::default(), settings.clone());
        let initial_size = renderer.grid_renderer.shaper.current_size();

        let mut window_settings = settings.get::<WindowSettings>();
        window_settings.scale_factor = 1.5;
        settings.set(&window_settings);

        renderer.sync_scale_factor();

        assert_eq!(renderer.user_scale_factor, 1.5);
        assert_eq!(renderer.grid_renderer.shaper.current_size(), initial_size * 1.5);
    }

    #[test]
    fn startup_messages_are_kept_until_ui_ready() {
        let mut renderer = create_renderer();

        let result = renderer.handle_draw_commands(vec![DrawCommand::StartupMessage {
            message: startup_message("boom"),
            replace_last: false,
            append: false,
        }]);

        assert!(!result.should_show);
        assert_eq!(result.startup_message_flush, None);
        assert!(result.startup_messages.is_empty());

        let result = renderer.handle_draw_commands(vec![DrawCommand::UIReady]);

        assert!(result.should_show);
        assert_eq!(result.startup_message_flush, Some(StartupMessageFlush::RestoreMessageUi));
        assert_eq!(result.startup_messages, vec![startup_message("boom")]);
    }

    #[test]
    fn startup_messages_after_ui_ready_in_same_batch_are_included() {
        let mut renderer = create_renderer();

        let result = renderer.handle_draw_commands(vec![
            DrawCommand::UIReady,
            DrawCommand::StartupMessage {
                message: startup_message("boom"),
                replace_last: false,
                append: false,
            },
        ]);

        assert!(result.should_show);
        assert_eq!(result.startup_message_flush, Some(StartupMessageFlush::RestoreMessageUi));
        assert_eq!(result.startup_messages, vec![startup_message("boom")]);
    }

    #[test]
    fn startup_prompt_flushes_startup_messages() {
        let mut renderer = create_renderer();

        let result = renderer.handle_draw_commands(vec![
            DrawCommand::StartupMessage {
                message: startup_message("boom"),
                replace_last: false,
                append: false,
            },
            DrawCommand::StartupPrompt,
        ]);

        assert!(result.should_show);
        assert_eq!(result.startup_message_flush, Some(StartupMessageFlush::RestoreMessageUi));
        assert_eq!(result.startup_messages, vec![startup_message("boom")]);
    }

    #[test]
    fn startup_message_clear_drops_only_latest_message() {
        let mut renderer = create_renderer();

        let result = renderer.handle_draw_commands(vec![
            DrawCommand::StartupMessage {
                message: startup_message("boom"),
                replace_last: false,
                append: false,
            },
            DrawCommand::StartupMessage {
                message: startup_message("progress"),
                replace_last: false,
                append: false,
            },
            DrawCommand::ClearStartupMessages,
            DrawCommand::UIReady,
        ]);

        assert!(result.should_show);
        assert_eq!(result.startup_message_flush, Some(StartupMessageFlush::RestoreMessageUi));
        assert_eq!(result.startup_messages, vec![startup_message("boom")]);
    }

    #[test]
    fn startup_messages_can_replay_after_message_ui_restore() {
        let mut renderer = create_renderer();

        let result = renderer.handle_draw_commands(vec![
            DrawCommand::StartupMessage {
                message: startup_message("boom"),
                replace_last: false,
                append: false,
            },
            DrawCommand::ReplayStartupMessages,
        ]);

        assert!(!result.should_show);
        assert_eq!(result.startup_message_flush, Some(StartupMessageFlush::Replay));
        assert_eq!(result.startup_messages, vec![startup_message("boom")]);
    }

    #[test]
    fn startup_messages_auto_replay_after_message_ui_restore() {
        let mut renderer = create_renderer();

        renderer.handle_draw_commands(vec![DrawCommand::ReplayStartupMessages]);
        let result = renderer.handle_draw_commands(vec![DrawCommand::StartupMessage {
            message: startup_message("boom"),
            replace_last: false,
            append: false,
        }]);

        assert!(!result.should_show);
        assert_eq!(result.startup_message_flush, Some(StartupMessageFlush::Replay));
        assert_eq!(result.startup_messages, vec![startup_message("boom")]);
    }

    #[test]
    fn startup_message_replay_state_is_reset_on_clear() {
        let mut renderer = create_renderer();

        renderer.handle_draw_commands(vec![DrawCommand::ReplayStartupMessages]);
        renderer.clear();
        let result = renderer.handle_draw_commands(vec![DrawCommand::StartupMessage {
            message: startup_message("boom"),
            replace_last: false,
            append: false,
        }]);

        assert!(!result.should_show);
        assert_eq!(result.startup_message_flush, None);
        assert!(result.startup_messages.is_empty());
    }

    #[test]
    fn startup_messages_can_replace_last_message() {
        let mut renderer = create_renderer();

        let result = renderer.handle_draw_commands(vec![
            DrawCommand::StartupMessage {
                message: startup_message("old"),
                replace_last: false,
                append: false,
            },
            DrawCommand::StartupMessage {
                message: startup_message("new"),
                replace_last: true,
                append: false,
            },
            DrawCommand::UIReady,
        ]);

        assert!(result.should_show);
        assert_eq!(result.startup_message_flush, Some(StartupMessageFlush::RestoreMessageUi));
        assert_eq!(result.startup_messages, vec![startup_message("new")]);
    }

    #[test]
    fn startup_messages_can_append_to_previous_message() {
        let mut renderer = create_renderer();

        let result = renderer.handle_draw_commands(vec![
            DrawCommand::StartupMessage {
                message: startup_message("hello"),
                replace_last: false,
                append: false,
            },
            DrawCommand::StartupMessage {
                message: startup_message(" world"),
                replace_last: false,
                append: true,
            },
            DrawCommand::UIReady,
        ]);

        assert!(result.should_show);
        assert_eq!(result.startup_message_flush, Some(StartupMessageFlush::RestoreMessageUi));
        assert_eq!(result.startup_messages, vec![startup_message("hello world")]);
    }

    #[test]
    fn startup_messages_keep_only_recent_entries() {
        let mut renderer = create_renderer();
        let mut commands = (0..(STARTUP_MESSAGE_LIMIT + 2))
            .map(|i| DrawCommand::StartupMessage {
                message: startup_message(&format!("message {i}")),
                replace_last: false,
                append: false,
            })
            .collect_vec();
        commands.push(DrawCommand::UIReady);

        let result = renderer.handle_draw_commands(commands);

        assert!(result.should_show);
        assert_eq!(result.startup_message_flush, Some(StartupMessageFlush::RestoreMessageUi));
        assert_eq!(
            result.startup_messages,
            vec![
                startup_message("message 2"),
                startup_message("message 3"),
                startup_message("message 4"),
                startup_message("message 5")
            ]
        );
    }
}
