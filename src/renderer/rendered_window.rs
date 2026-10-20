use std::{cell::RefCell, ops::Range, rc::Rc};

use skia_safe::{
    BlendMode, Canvas, ClipOp, Color, Color4f, Matrix, Paint, Path, PathBuilder, Picture,
    PictureRecorder, Rect,
};

use crate::{
    bridge::WindowAnchor,
    cmd_line::CmdLineSettings,
    editor::{AnchorInfo, Line, LineFragment, SortOrder, WindowType},
    profiling::{tracy_plot, tracy_zone},
    renderer::{GridRenderer, RendererSettings, animation_utils::*},
    settings::Settings,
    units::{GridPos, GridRect, GridScale, GridSize, PixelPos, PixelRect, PixelVec, to_skia_rect},
    utils::RingBuffer,
};

pub const BASE_GRID_ID: u64 = 1;
pub const NO_MULTIGRID_GRID_ID: u64 = 0;

// Extend the rightmost host through its horizontal pixel remainder. The strip
// below the last complete row retains the window's default background. Cap the
// fractional extension to one cell so a grid lagging a resize is not stretched.
const MAX_EDGE_FILL_CELLS: f32 = 1.0;

#[derive(Clone, Copy, Debug)]
struct NotebookTitleLayout {
    kernel: (f32, f32),
    actions: (f32, f32),
    host_width: f32,
}

impl NotebookTitleLayout {
    fn draw(
        &self,
        canvas: &Canvas,
        picture: &Picture,
        matrix: &Matrix,
        scale: GridScale,
        origin_x: f32,
    ) {
        let rect = |span: (f32, f32)| {
            Rect::from_xywh(
                origin_x + span.0 * scale.width(),
                0.0,
                (span.1 - span.0) * scale.width(),
                scale.height(),
            )
        };
        canvas.save();
        canvas.concat(matrix);
        canvas.clip_rect(rect(self.kernel), ClipOp::Difference, false);
        canvas.clip_rect(rect(self.actions), ClipOp::Difference, false);
        canvas.draw_picture(picture, None, None);
        canvas.restore();
        // Lua places Kernel at round(textoff-.8). Its remaining .2-cell
        // fraction and the right frame edge are resolved in pixel coordinates.
        for (span, offset) in
            [(self.kernel, 0.2), (self.actions, self.host_width - 1.12 - self.actions.1)]
        {
            canvas.save();
            canvas.concat(matrix);
            canvas.translate((offset * scale.width(), 0.0));
            canvas.clip_rect(rect(span), None, false);
            canvas.draw_picture(picture, None, None);
            canvas.restore();
        }
    }
}

#[derive(Debug)]
pub struct ViewportMargins {
    pub top: u64,
    pub bottom: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum WindowDrawCommand {
    HostSize {
        width: u64,
        height: u64,
    },
    Position {
        grid_position: (f64, f64),
        grid_size: (u64, u64),
        anchor_info: Option<AnchorInfo>,
        window_type: WindowType,
    },
    DrawLine {
        row: usize,
        line: Line,
    },
    Scroll {
        top: u64,
        bottom: u64,
        left: u64,
        right: u64,
        rows: i64,
        cols: i64,
    },
    Clear,
    Show,
    Hide,
    Close,
    Viewport {
        window_id: u64,
        scroll_delta: f64,
    },
    ViewportMargins {
        top: u64,
        bottom: u64,
        #[allow(unused)]
        left: u64,
        #[allow(unused)]
        right: u64,
    },
    SortOrder(SortOrder),
}

struct RenderedLine {
    line: Line,
    background_picture: Option<Picture>,
    foreground_picture: Option<Picture>,
    boxchar_picture: Option<(Picture, PixelPos<f32>)>,
    trailing_background: Option<Color4f>,
    has_transparency: bool,
    is_valid: bool,
}

pub struct RenderedWindow {
    pub id: u64,
    valid: bool,
    pub hidden: bool,
    pub anchor_info: Option<AnchorInfo>,
    pub window_type: WindowType,

    pub grid_size: GridSize<u32>,

    scrollback_lines: RingBuffer<Option<Rc<RefCell<RenderedLine>>>>,
    actual_lines: RingBuffer<Option<Rc<RefCell<RenderedLine>>>>,
    scroll_delta: isize,
    pub viewport_margins: ViewportMargins,

    grid_start_position: GridPos<f32>,
    pub grid_current_position: GridPos<f32>,
    grid_destination: GridPos<f32>,
    position_t: f32,

    pub scroll_animation: CriticallyDampedSpringAnimation,
    pub scroll_animation_delta: f32,
    pub window_id: Option<u64>,
    pub viewport_scroll: f64,
    pub host_grid_size: Option<GridSize<u32>>,
}
#[derive(Clone, Debug)]
pub struct WindowDrawDetails {
    pub id: u64,
    pub region: PixelRect<f32>,
    pub grid_size: GridSize<u32>,
    pub window_type: WindowType,
}

impl WindowDrawDetails {
    pub fn event_grid_id(&self, settings: &Settings) -> u64 {
        if settings.get::<CmdLineSettings>().no_multi_grid { NO_MULTIGRID_GRID_ID } else { self.id }
    }
}

impl RenderedWindow {
    pub fn new(id: u64) -> RenderedWindow {
        let grid_size = GridSize::ZERO;
        let grid_position = GridPos::ZERO;
        RenderedWindow {
            id,
            valid: false,
            hidden: false,
            anchor_info: None,
            window_type: WindowType::Editor,

            grid_size,

            actual_lines: RingBuffer::new(grid_size.height as usize, None),
            scrollback_lines: RingBuffer::new(2 * grid_size.height as usize, None),
            scroll_delta: 0,
            viewport_margins: ViewportMargins { top: 0, bottom: 0 },

            grid_start_position: grid_position,
            grid_current_position: grid_position,
            grid_destination: grid_position,
            position_t: 2.0, // 2.0 is out of the 0.0 to 1.0 range and stops animation.

            scroll_animation: CriticallyDampedSpringAnimation::new(),
            scroll_animation_delta: 0.0,
            window_id: None,
            viewport_scroll: 0.0,
            host_grid_size: None,
        }
    }

    pub fn pixel_region(&self, grid_scale: GridScale) -> PixelRect<f32> {
        // Round to the same fraction as the desination to avoid glitches when rendering box
        // characters.
        let fract = (self.grid_destination * grid_scale).fract();
        let pos = (self.grid_current_position * grid_scale - fract).round() + fract.to_vector();
        PixelRect::<f32>::from_origin_and_size(pos.into(), self.grid_size() * grid_scale)
    }

    /// A normal split can reserve columns outside its narrower text grid.
    /// Those columns still belong to the split's background, unlike floats.
    pub fn background_region(&self, grid_scale: GridScale) -> PixelRect<f32> {
        let mut region = self.pixel_region(grid_scale);
        if self.anchor_info.is_none()
            && matches!(self.window_type, WindowType::Editor)
            && let Some(host_size) = self.host_grid_size
        {
            region.max.x = region.min.x + host_size.width as f32 * grid_scale.width();
            region.max.y = region.min.y + host_size.height as f32 * grid_scale.height();
        }
        region
    }

    fn grid_size(&self) -> GridSize<u32> {
        let mut size = self.grid_size;
        if matches!(self.window_type, WindowType::Message { .. }) {
            // Neovim reports message grids with the full default-grid height even
            // when they are anchored near the bottom. Only the rows from the
            // message start row down to the bottom edge are actually visible.
            size.height = size.height.saturating_sub(self.grid_destination.y.max(0.0) as u32);
        }
        size
    }

    fn full_window_vertical_scroll_rows(
        &self,
        top: u64,
        bottom: u64,
        left: u64,
        right: u64,
        rows: i64,
        cols: i64,
    ) -> Option<i64> {
        (top == 0
            && bottom == u64::from(self.grid_size.height)
            && left == 0
            && right == u64::from(self.grid_size.width)
            && cols == 0)
            .then_some(rows)
    }

    fn get_target_position(&self, grid_rect: &GridRect<f32>) -> GridPos<f32> {
        let destination = self.grid_destination + grid_rect.min.to_vector();

        match self.anchor_info {
            None => destination,
            Some(AnchorInfo { anchor_type: WindowAnchor::Absolute, .. }) => destination,
            _ => {
                let grid_size: GridSize<f32> = self.grid_size().try_cast().unwrap();
                // If a floating window is partially outside the grid, then move it in from the right, but
                // ensure that the left edge is always visible.
                let x = destination.x.min(grid_rect.max.x - grid_size.width).max(grid_rect.min.x);

                // For messages the last line is most important, (it shows press enter), so let the position go negative
                // Otherwise ensure that the window start row is within the screen
                let mut y = destination.y.min(grid_rect.max.y - grid_size.height);
                if !matches!(self.window_type, WindowType::Message { .. }) {
                    y = y.max(grid_rect.min.y)
                }
                GridPos::<f32>::new(x, y)
            }
        }
    }

    /// Returns `true` if the window has been animated in this step.
    pub fn animate(
        &mut self,
        settings: &RendererSettings,
        grid_rect: &GridRect<f32>,
        dt: f32,
    ) -> bool {
        let mut animating = false;

        if self.position_t > 1.0 - f32::EPSILON {
            // We are at destination, move t out of 0-1 range to stop the animation.
            self.position_t = 2.0;
        } else {
            animating = true;
            self.position_t = (self.position_t + dt / settings.position_animation_length).min(1.0);
        }

        let prev_position = self.grid_current_position;
        self.grid_current_position = ease_point(
            ease_out_expo,
            self.grid_start_position,
            self.get_target_position(grid_rect),
            self.position_t,
        );
        animating |= self.grid_current_position != prev_position;

        let scroll_before = self.scroll_animation.position;
        let scrolling = self.scroll_animation.update(dt, settings.scroll_animation_length);
        self.scroll_animation_delta = self.scroll_animation.position - scroll_before;

        animating |= scrolling;

        if scrolling {
            tracy_plot!("Scroll position {}", self.scroll_animation.position.into());
        }

        animating
    }

    fn notebook_title_layout(&self, line: &RenderedLine) -> Option<NotebookTitleLayout> {
        use crate::editor::NotebookTitleGroup;
        let host_width = self.host_grid_size?.width;
        if self.anchor_info.is_some()
            || self.viewport_margins.top == 0
            || host_width <= self.grid_size.width
        {
            return None;
        }
        let (mut kernel, mut actions) = (None::<(f32, f32)>, None::<(f32, f32)>);
        for fragment in line.line.fragments() {
            let target = match fragment.style.as_ref().and_then(|style| style.notebook_title) {
                Some(NotebookTitleGroup::Kernel) => &mut kernel,
                Some(NotebookTitleGroup::Actions) => &mut actions,
                None => continue,
            };
            let span = (fragment.cells.start as f32, fragment.cells.end as f32);
            *target = Some(target.map_or(span, |old| (old.0.min(span.0), old.1.max(span.1))));
        }
        Some(NotebookTitleLayout {
            kernel: kernel?,
            actions: actions?,
            host_width: host_width as f32,
        })
    }

    fn draw_border_picture(
        &self,
        canvas: &Canvas,
        picture: &Picture,
        matrix: &Matrix,
        line: &RenderedLine,
        grid_scale: GridScale,
        origin_x: f32,
    ) {
        if let Some(layout) = self.notebook_title_layout(line) {
            layout.draw(canvas, picture, matrix, grid_scale, origin_x);
        } else {
            canvas.draw_picture(picture, Some(matrix), None);
        }
    }

    pub fn draw_background_surface(
        &mut self,
        canvas: &Canvas,
        pixel_region: PixelRect<f32>,
        grid_scale: GridScale,
    ) {
        let inner_region = self.inner_region(pixel_region, grid_scale);

        canvas.save();
        canvas.clip_rect(to_skia_rect(&pixel_region), None, false);
        for (matrix, line) in self.iter_border_lines_with_transform(pixel_region, grid_scale) {
            let line = line.borrow();
            if let Some(background_picture) = &line.background_picture {
                self.draw_border_picture(
                    canvas,
                    background_picture,
                    &matrix,
                    &line,
                    grid_scale,
                    0.0,
                );
            }
        }
        canvas.restore();

        canvas.save();
        canvas.clip_rect(inner_region, None, false);
        let mut pics = 0;
        for (matrix, line) in self.iter_scrollable_lines_with_transform(pixel_region, grid_scale) {
            let line = line.borrow();
            if let Some(background_picture) = &line.background_picture {
                canvas.draw_picture(background_picture, Some(&matrix), None);
                pics += 1;
            }
        }

        log::trace!("region: {pixel_region:?}, inner: {inner_region:?}, pics: {pics}");
        canvas.restore();
    }

    pub fn draw_foreground_surface(
        &mut self,
        canvas: &Canvas,
        pixel_region: PixelRect<f32>,
        grid_scale: GridScale,
    ) {
        for (matrix, line) in self.iter_border_lines_with_transform(pixel_region, grid_scale) {
            let line = line.borrow();
            if let Some(foreground_picture) = &line.foreground_picture {
                self.draw_border_picture(
                    canvas,
                    foreground_picture,
                    &matrix,
                    &line,
                    grid_scale,
                    0.0,
                );
            }
        }
        canvas.save();
        canvas.clip_rect(self.inner_region(pixel_region, grid_scale), None, false);
        for (matrix, line) in self.iter_scrollable_lines_with_transform(pixel_region, grid_scale) {
            let line = line.borrow();
            if let Some(foreground_picture) = &line.foreground_picture {
                canvas.draw_picture(foreground_picture, Some(&matrix), None);
            }
        }
        canvas.restore();

        for (mut matrix, line) in self.iter_border_lines_with_transform(pixel_region, grid_scale) {
            let line = line.borrow();
            if let Some((boxchar_picture, position)) = &line.boxchar_picture {
                let deltax = pixel_region.min.x - position.x;
                matrix.set_translate_x(deltax);
                self.draw_border_picture(
                    canvas,
                    boxchar_picture,
                    &matrix,
                    &line,
                    grid_scale,
                    position.x,
                );
            }
        }
        canvas.save();
        canvas.clip_rect(self.inner_region(pixel_region, grid_scale), None, false);
        for (mut matrix, line) in
            self.iter_scrollable_lines_with_transform(pixel_region, grid_scale)
        {
            let line = line.borrow();
            if let Some((boxchar_picture, position)) = &line.boxchar_picture {
                let deltax = pixel_region.min.x - position.x;
                matrix.set_translate_x(deltax);
                canvas.draw_picture(boxchar_picture, Some(&matrix), None);
            }
        }
        canvas.restore();
    }

    pub fn has_transparency(&self) -> bool {
        let scroll_offset_lines = self.scroll_animation.position.floor() as isize;
        if self.scrollback_lines.is_empty() {
            return false;
        }
        self.scrollback_lines
            .iter_range(
                scroll_offset_lines..scroll_offset_lines + self.grid_size.height as isize + 1,
            )
            .flatten()
            .any(|line| line.borrow().has_transparency)
    }

    pub fn draw(
        &mut self,
        root_canvas: &Canvas,
        default_background: Color,
        grid_scale: GridScale,
        content_region: Option<PixelRect<f32>>,
        rightmost_window: bool,
    ) -> WindowDrawDetails {
        let pixel_region_box = self.pixel_region(grid_scale);
        let draw_region_box = self.expanded_pixel_region(
            pixel_region_box,
            content_region,
            grid_scale,
            rightmost_window,
        );
        let pixel_region = to_skia_rect(&draw_region_box);

        if !self.valid {
            return WindowDrawDetails {
                id: self.id,
                region: pixel_region_box,
                grid_size: self.grid_size,
                window_type: self.window_type,
            };
        }

        root_canvas.save();
        root_canvas.clip_rect(pixel_region, None, Some(false));
        root_canvas.clear(default_background);

        self.draw_background_surface(root_canvas, draw_region_box, grid_scale);
        self.draw_foreground_surface(root_canvas, draw_region_box, grid_scale);

        root_canvas.restore();

        self.draw_edge_background_surface(root_canvas, draw_region_box, grid_scale);

        WindowDrawDetails {
            id: self.id,
            region: draw_region_box,
            grid_size: self.grid_size,
            window_type: self.window_type,
        }
    }

    pub fn expanded_pixel_region(
        &self,
        pixel_region: PixelRect<f32>,
        content_region: Option<PixelRect<f32>>,
        grid_scale: GridScale,
        rightmost_window: bool,
    ) -> PixelRect<f32> {
        let mut region = pixel_region;
        region.max = self.background_region(grid_scale).max;
        if let Some(content_region) = content_region
            && rightmost_window
            && sub_cell_edge_gap(content_region.max.x, region.max.x, grid_scale.width()).is_some()
        {
            region.max.x = content_region.max.x;
        }

        region
    }

    pub fn draw_edge_background_surface(
        &self,
        canvas: &Canvas,
        pixel_region: PixelRect<f32>,
        grid_scale: GridScale,
    ) {
        self.trailing_background_fills(pixel_region, grid_scale).draw(canvas, pixel_region);
    }

    pub fn edge_background_path_and_bounds(
        &self,
        pixel_region: PixelRect<f32>,
        grid_scale: GridScale,
    ) -> Option<(Path, Rect)> {
        self.trailing_background_fills(pixel_region, grid_scale).path_and_bounds()
    }

    fn trailing_background_fills(
        &self,
        expanded_region: PixelRect<f32>,
        grid_scale: GridScale,
    ) -> BackgroundFills {
        let base_region = self.pixel_region(grid_scale);
        let inner_region = self.inner_region(expanded_region, grid_scale);
        let host_region = self.background_region(grid_scale);
        let extra_width = expanded_region.max.x - base_region.max.x;
        // Reserved Notebook columns are outside the text grid, so they keep
        // the window clear. CursorLine/Visual must end with the actual text.
        // Only an ordinary fractional remainder extends the last cell style.
        if host_region.max.x > base_region.max.x
            || extra_width <= 0.0
            || expanded_region.max.x > host_region.max.x + grid_scale.width() + f32::EPSILON
        {
            return BackgroundFills::default();
        }

        let mut fills = BackgroundFills::default();
        // The trailing fill follows the same clipping model as the normal
        // background pass. Fixed rows like border and margin rows can paint
        // across the full window region, but scrollable rows must stay inside
        // the inner viewport. Since edge fills are drawn through one shared
        // path now, we bake those separate bounds into the generated rects so
        // buffered scroll rows cannot leak into fixed UI rows.
        for (i, line) in self.iter_border_lines() {
            let line = line.borrow();
            let Some(color) = line.trailing_background else {
                continue;
            };

            fills.push(
                Rect::from_xywh(
                    base_region.max.x,
                    expanded_region.min.y + i as f32 * grid_scale.height(),
                    extra_width,
                    grid_scale.height(),
                ),
                color,
            );
        }

        // this fill is part of the rendered grid background, not a separate
        // overlay. when the window is mid-scroll, the scrollable rows can
        // sit at a fractional cell offset, so this fill has to use that
        // same pixel offset too.
        //
        // See https://github.com/neovide/neovide/pull/3387
        let scroll_offset_pixels = self.scroll_offset_pixels(grid_scale.height());
        for (i, line) in self.iter_scrollable_lines() {
            let line = line.borrow();
            let Some(color) = line.trailing_background else {
                continue;
            };

            let y = expanded_region.min.y
                + scroll_offset_pixels
                + (i + self.viewport_margins.top as isize) as f32 * grid_scale.height();
            let top = y.max(inner_region.top);
            let bottom = (y + grid_scale.height()).min(inner_region.bottom);
            if bottom <= top {
                continue;
            }

            fills.push(Rect::from_xywh(base_region.max.x, top, extra_width, bottom - top), color);
        }

        fills
    }

    fn scroll_offset_pixels(&self, line_height: f32) -> f32 {
        let scroll_offset_lines = self.scroll_animation.position.floor();
        let scroll_offset = scroll_offset_lines - self.scroll_animation.position;
        (scroll_offset * line_height).round()
    }
    fn line_for_row(&self, row: u32) -> Option<Rc<RefCell<RenderedLine>>> {
        if self.actual_lines.is_empty() {
            return None;
        }

        let row = row as isize;
        let height = self.grid_size.height as isize;
        if row < 0 || row >= height {
            return None;
        }

        let top_margin = self.viewport_margins.top as isize;
        let bottom_margin = self.viewport_margins.bottom as isize;
        let bottom_start = height.saturating_sub(bottom_margin);

        if row < top_margin || row >= bottom_start {
            return self.actual_lines[row].as_ref().cloned();
        }

        let inner_row = row - top_margin;
        let scroll_offset = self.scroll_animation.position.floor() as isize;
        self.scrollback_lines[scroll_offset + inner_row].as_ref().cloned()
    }

    pub fn line_text_range(&self, row: u32, start_col: u32, end_col: u32) -> Option<String> {
        let line = self.line_for_row(row)?;
        let line = line.borrow();
        let cells = line.line.rendered_cells();
        if cells.is_empty() {
            return Some(String::new());
        }

        let max_col = cells.len().saturating_sub(1) as u32;
        let start = start_col.min(max_col);
        let end = end_col.min(max_col);
        let (mut start, end) = if start <= end { (start, end) } else { (end, start) };
        while start > 0 && cells[start as usize].is_empty() {
            start -= 1; // A click on a wide glyph's continuation selects its glyph.
        }

        let mut text = String::new();
        for col in start..=end {
            text.push_str(&cells[col as usize]);
        }

        let trimmed_len = text.trim_end_matches(' ').len();
        text.truncate(trimmed_len);

        Some(text)
    }

    pub fn notebook_output_region(
        &self,
        mut bounds: Rect,
        scale: GridScale,
    ) -> Option<super::selection::NotebookOutputRegion> {
        let pixel_region = self.pixel_region(scale);
        if !bounds.intersect(self.inner_region(pixel_region, scale)) {
            return None;
        }
        let hit_bounds =
            PixelRect::from_min_max((bounds.left, bounds.top), (bounds.right, bounds.bottom));
        let first_col = (((bounds.left - pixel_region.min.x) / scale.width()).ceil().max(0.0)
            as u32)
            .min(self.grid_size.width);
        let end_col = (((bounds.right - pixel_region.min.x) / scale.width()).floor().max(0.0)
            as u32)
            .min(self.grid_size.width);
        if first_col >= end_col {
            return None;
        }
        let rows = (self.viewport_margins.top as u32
            ..self.grid_size.height.saturating_sub(self.viewport_margins.bottom as u32))
            .filter_map(|row| {
                let rect = self.grid_row_rect(row, first_col, end_col - 1, scale)?;
                // The output's top seam is centered in an independent blank
                // row. Its center lies on the border, so do not select that row.
                (rect.center_y() > bounds.top + 0.01 && rect.center_y() < bounds.bottom)
                    .then_some((row, rect))
            })
            .collect::<Vec<_>>();
        let (first_row, first_rect) = rows.first()?;
        let (last_row, last_rect) = rows.last()?;
        Some(super::selection::NotebookOutputRegion {
            grid_id: self.id,
            hit_bounds,
            cells: GridRect::from_min_max((first_col, *first_row), (end_col, last_row + 1)),
            bounds: PixelRect::from_min_max(
                (first_rect.left.max(bounds.left), first_rect.top.max(bounds.top)),
                (last_rect.right.min(bounds.right), last_rect.bottom.min(bounds.bottom)),
            ),
            origin: PixelPos::new(
                pixel_region.min.x,
                first_rect.top - *first_row as f32 * scale.height(),
            ),
        })
    }

    pub fn grid_row_rect(
        &self,
        row: u32,
        col_start: u32,
        col_end: u32,
        grid_scale: GridScale,
    ) -> Option<Rect> {
        let height = self.grid_size.height;
        let width = self.grid_size.width;
        if height == 0 || width == 0 {
            return None;
        }

        let max_row = height - 1;
        let max_col = width - 1;
        let row = row.min(max_row);
        let start_col = col_start.min(max_col);
        let end_col = col_end.min(max_col);
        let (start_col, end_col) =
            if start_col <= end_col { (start_col, end_col) } else { (end_col, start_col) };

        let pixel_region = self.pixel_region(grid_scale);
        let line_height = grid_scale.height();
        let col_width = grid_scale.width();
        let base_x = pixel_region.min.x;
        let base_y = pixel_region.min.y;

        let scroll_offset_pixels = ((self.scroll_animation.position.floor()
            - self.scroll_animation.position)
            * line_height)
            .round();
        let top_margin = self.viewport_margins.top as u32;
        let bottom_margin = self.viewport_margins.bottom as u32;
        let bottom_start = height.saturating_sub(bottom_margin);

        let y = if row < top_margin || row >= bottom_start {
            base_y + row as f32 * line_height
        } else {
            base_y + scroll_offset_pixels + row as f32 * line_height
        };
        let x = base_x + start_col as f32 * col_width;
        let w = (end_col - start_col + 1) as f32 * col_width;

        Some(Rect::from_xywh(x, y, w, line_height))
    }

    pub fn changes_selection(&self, command: &WindowDrawCommand) -> bool {
        match command {
            WindowDrawCommand::HostSize { width, height } => {
                self.host_grid_size != Some(GridSize::new(*width as u32, *height as u32))
            }
            WindowDrawCommand::Position { grid_position, grid_size, anchor_info, window_type } => {
                !self.valid
                    || self.grid_destination
                        != GridPos::new(grid_position.0 as f32, grid_position.1 as f32)
                    || self.grid_size != GridSize::new(grid_size.0 as u32, grid_size.1 as u32)
                    || self.anchor_info != *anchor_info
                    || self.window_type != *window_type
            }
            WindowDrawCommand::DrawLine { row, line } => {
                *row < self.actual_lines.len()
                    && self.actual_lines[*row].as_ref().is_none_or(|old| old.borrow().line != *line)
            }
            WindowDrawCommand::Scroll { top, bottom, left, right, rows, cols } => {
                top < bottom && left < right && (*rows != 0 || *cols != 0)
            }
            WindowDrawCommand::Clear => {
                self.actual_lines.iter().any(Option::is_some)
                    || self.scrollback_lines.iter().any(Option::is_some)
            }
            WindowDrawCommand::Show => self.hidden,
            WindowDrawCommand::Hide => !self.hidden,
            WindowDrawCommand::Close => true,
            WindowDrawCommand::Viewport { window_id, scroll_delta } => {
                self.window_id != Some(*window_id) || scroll_delta.round() != 0.0
            }
            WindowDrawCommand::ViewportMargins { top, bottom, .. } => {
                self.viewport_margins.top != *top || self.viewport_margins.bottom != *bottom
            }
            WindowDrawCommand::SortOrder(sort_order) => {
                self.anchor_info.as_ref().is_some_and(|anchor| anchor.sort_order != *sort_order)
            }
        }
    }

    pub fn handle_window_draw_command(&mut self, draw_command: WindowDrawCommand) {
        match draw_command {
            WindowDrawCommand::HostSize { width, height } => {
                self.host_grid_size = Some(GridSize::new(width as u32, height as u32));
            }
            WindowDrawCommand::Position { grid_position, grid_size, anchor_info, window_type } => {
                tracy_zone!("position_cmd", 0);

                self.valid = true;

                let new_grid_size: GridSize<u32> =
                    GridSize::<u64>::from(grid_size).try_cast().unwrap();
                let grid_position: GridPos<f32> =
                    GridPos::<f64>::from(grid_position).try_cast().unwrap();

                if self.grid_destination != grid_position {
                    if self.grid_start_position.x.abs() > f32::EPSILON
                        || self.grid_start_position.y.abs() > f32::EPSILON
                    {
                        self.position_t = 0.0; // Reset animation as we have a new destination.
                        self.grid_start_position = self.grid_current_position;
                    } else {
                        // We don't want to animate since the window is animating out of the start location,
                        // so we set t to 2.0 to stop animations.
                        self.position_t = 2.0;
                        self.grid_start_position = grid_position;
                    }
                    self.grid_destination = grid_position;
                }

                let height = new_grid_size.height as usize;
                self.actual_lines.resize(height, None);
                self.grid_size = new_grid_size;

                self.scrollback_lines.resize(2 * height, None);
                self.scrollback_lines.clone_from_iter(&self.actual_lines);
                self.scroll_delta = 0;

                if height != self.actual_lines.len() {
                    self.scroll_animation.reset();
                }

                self.anchor_info = anchor_info;
                self.window_type = window_type;
            }
            WindowDrawCommand::DrawLine { row, line } => {
                tracy_zone!("draw_line_cmd", 0);

                if self.actual_lines.is_empty() || !self.valid {
                    log::warn!(
                        "Ignoring DrawLine for grid {} row {} because the window is not ready yet",
                        self.id,
                        row
                    );
                    return;
                }

                let line = RenderedLine {
                    line,
                    background_picture: None,
                    foreground_picture: None,
                    boxchar_picture: None,
                    trailing_background: None,
                    has_transparency: false,
                    is_valid: false,
                };

                self.actual_lines[row] = Some(Rc::new(RefCell::new(line)));
            }
            WindowDrawCommand::Scroll { top, bottom, left, right, rows, cols } => {
                tracy_zone!("scroll_cmd", 0);
                if let Some(rows) =
                    self.full_window_vertical_scroll_rows(top, bottom, left, right, rows, cols)
                {
                    self.actual_lines.rotate(rows as isize);
                }
            }
            WindowDrawCommand::Clear => {
                tracy_zone!("clear_cmd", 0);
                self.scroll_delta = 0;
                // A later flush copies actual_lines back into the visible cache.
                self.actual_lines.iter_mut().for_each(|line| *line = None);
                self.scrollback_lines.iter_mut().for_each(|line| *line = None);
                self.scroll_animation.reset();
            }
            WindowDrawCommand::Show if self.hidden => {
                tracy_zone!("show_cmd", 0);
                self.hidden = false;
                self.position_t = 2.0; // We don't want to animate since the window is becoming visible,
                // so we set t to 2.0 to stop animations.
                self.grid_start_position = self.grid_destination;
                self.scroll_animation.reset();
            }
            WindowDrawCommand::Show => {
                tracy_zone!("show_cmd", 0);
            }
            WindowDrawCommand::Hide => {
                tracy_zone!("hide_cmd", 0);
                self.hidden = true;
            }
            WindowDrawCommand::Viewport { window_id, scroll_delta } => {
                log::trace!("Handling Viewport {}", self.id);
                self.window_id = Some(window_id);
                self.viewport_scroll += scroll_delta.round();
                self.scroll_delta = scroll_delta.round() as isize;
            }
            WindowDrawCommand::ViewportMargins { top, bottom, .. } => {
                self.viewport_margins = ViewportMargins { top, bottom }
            }
            WindowDrawCommand::SortOrder(sort_order) => {
                if let Some(anchor_info) = self.anchor_info.as_mut() {
                    anchor_info.sort_order = sort_order;
                }
            }
            _ => {}
        };
    }

    pub fn flush(&mut self, renderer_settings: &RendererSettings) {
        if !self.valid {
            return;
        }
        // If the borders are changed, reset the scrollback to only fit the inner view
        let inner_range = self.viewport_margins.top as isize
            ..(self.actual_lines.len() - self.viewport_margins.bottom as usize) as isize;
        let inner_size = inner_range.len();
        let inner_view = self.actual_lines.iter_range(inner_range);
        if inner_size != self.scrollback_lines.len() / 2 {
            self.scrollback_lines.resize(2 * inner_size, None);
            self.scrollback_lines.clone_from_iter(inner_view);
            self.scroll_delta = 0;
            self.scroll_animation.reset();
            return;
        }

        let scroll_delta = self.scroll_delta;
        self.scrollback_lines.rotate(scroll_delta);

        self.scrollback_lines.clone_from_iter(inner_view);

        if scroll_delta != 0 {
            let mut scroll_offset = self.scroll_animation.position;

            let max_delta =
                self.scrollback_lines.len().saturating_sub(self.grid_size.height as usize);
            log::trace!(
                "Scroll offset {scroll_offset}, delta {scroll_delta}, max_delta {max_delta}"
            );
            // Do a limited scroll with empty lines when scrolling far
            if scroll_delta.unsigned_abs() > max_delta {
                let far_lines = renderer_settings
                    .scroll_animation_far_lines
                    .min(self.actual_lines.len() as u32) as isize;

                scroll_offset = -(far_lines * scroll_delta.signum()) as f32;
                let empty_lines = if scroll_delta > 0 {
                    -far_lines..0
                } else {
                    self.actual_lines.len() as isize..self.actual_lines.len() as isize + far_lines
                };
                for i in empty_lines {
                    self.scrollback_lines[i] = None;
                }
            // And even when scrolling in steps, we can't let it drift too far, since the
            // buffer size is limited
            } else {
                scroll_offset -= scroll_delta as f32;
                scroll_offset = scroll_offset.clamp(-(max_delta as f32), max_delta as f32);
            }
            self.scroll_animation.position = scroll_offset;
            log::trace!("Current scroll {scroll_offset}");
        }
        self.scroll_delta = 0;
    }

    fn iter_border_lines(&self) -> impl Iterator<Item = (isize, &Rc<RefCell<RenderedLine>>)> {
        let top_border_indices = 0..self.viewport_margins.top as isize;
        let actual_line_count = self.actual_lines.len() as isize;
        let bottom_border_indices =
            actual_line_count - self.viewport_margins.bottom as isize..actual_line_count;

        top_border_indices
            .chain(bottom_border_indices)
            .filter_map(move |i| self.actual_lines[i].as_ref().map(|line| (i, line)))
    }

    // Iterates over the scrollable lines (excluding the viewport margins). Includes the index for
    // the given line being scrolled
    fn iter_scrollable_lines(&self) -> impl Iterator<Item = (isize, &Rc<RefCell<RenderedLine>>)> {
        let scroll_offset_lines = self.scroll_animation.position.floor();
        let scroll_offset_lines = scroll_offset_lines as isize;
        let inner_size = self.actual_lines.len() as isize
            - self.viewport_margins.top as isize
            - self.viewport_margins.bottom as isize;

        let line_indices = if inner_size > 0 { 0..inner_size + 1 } else { 0..0 };

        line_indices.filter_map(move |i| {
            self.scrollback_lines[scroll_offset_lines + i].as_ref().map(|line| (i, line))
        })
    }

    fn iter_scrollable_lines_with_transform(
        &self,
        pixel_region: PixelRect<f32>,
        grid_scale: GridScale,
    ) -> impl Iterator<Item = (Matrix, &Rc<RefCell<RenderedLine>>)> {
        let scroll_offset_pixels = self.scroll_offset_pixels(grid_scale.height());

        self.iter_scrollable_lines().map(move |(i, line)| {
            let mut matrix = Matrix::new_identity();
            matrix.set_translate((
                pixel_region.min.x,
                pixel_region.min.y
                    + (scroll_offset_pixels
                        + ((i + self.viewport_margins.top as isize) as f32 * grid_scale.height())),
            ));
            (matrix, line)
        })
    }

    fn iter_border_lines_with_transform(
        &self,
        pixel_region: PixelRect<f32>,
        grid_scale: GridScale,
    ) -> impl Iterator<Item = (Matrix, &Rc<RefCell<RenderedLine>>)> {
        self.iter_border_lines().map(move |(i, line)| {
            let mut matrix = Matrix::new_identity();
            matrix.set_translate((
                pixel_region.min.x,
                pixel_region.min.y + (i as f32 * grid_scale.height()),
            ));
            (matrix, line)
        })
    }

    /// Returns the rect containing the region of the window that does not have borders above and
    /// below it. Note: This does not take into account the borders on the left and the right of
    /// the window.
    pub fn inner_region(&self, pixel_region: PixelRect<f32>, grid_scale: GridScale) -> Rect {
        let line_height = grid_scale.height();

        let adjusted_region = PixelRect::new(
            pixel_region.min + PixelVec::new(0., self.viewport_margins.top as f32 * line_height),
            pixel_region.max - PixelVec::new(0., self.viewport_margins.bottom as f32 * line_height),
        );

        to_skia_rect(&adjusted_region)
    }

    pub fn prepare_lines(&mut self, grid_renderer: &mut GridRenderer, opacity: f32, force: bool) {
        let scroll_offset_lines = self.scroll_animation.position.floor() as isize;
        let height = self.grid_size.height as isize;
        if height == 0 {
            return;
        }
        let grid_scale = grid_renderer.grid_scale;

        let mut prepare_line = |line: &Rc<RefCell<RenderedLine>>| {
            let mut line = line.borrow_mut();
            let position = self.grid_destination * grid_renderer.grid_scale;
            let boxchar_moved = match line.boxchar_picture {
                None => false,
                Some((_, p)) if p == position => false,
                _ => true,
            };
            // This can be optimized, only the boxchars need to be redrawn when the window moves
            if line.is_valid && !force && !boxchar_moved {
                return;
            }

            let mut recorder = PictureRecorder::new();

            let line_size = GridSize::new(self.grid_size.width, 1) * grid_scale;
            let grid_rect = Rect::from_wh(line_size.width, line_size.height);
            let canvas = recorder.begin_recording(grid_rect, false);

            let mut has_transparency = false;
            let mut custom_background = false;

            for line_fragment in line.line.fragments() {
                let LineFragment { cells, style, .. } = line_fragment;
                let background_info = grid_renderer.draw_background(canvas, cells, style, opacity);
                custom_background |= background_info.custom_color;
                has_transparency |= background_info.transparent;
            }
            let background_picture =
                custom_background.then_some(recorder.finish_recording_as_picture(None).unwrap());

            let text_canvas = recorder.begin_recording(grid_rect, false);
            let mut boxchar_recorder = PictureRecorder::new();
            let boxchar_canvas =
                boxchar_recorder.begin_recording(grid_rect.with_offset((position.x, 0.0)), false);
            let (text_drawn, boxchar_drawn) = draw_line_foreground(
                grid_renderer,
                text_canvas,
                boxchar_canvas,
                line.line.fragments(),
                position,
                opacity,
            );
            let foreground_picture =
                text_drawn.then_some(recorder.finish_recording_as_picture(None).unwrap());
            let boxchar_picture = boxchar_drawn
                .then_some((boxchar_recorder.finish_recording_as_picture(None).unwrap(), position));

            let trailing_background = line
                .line
                .fragments()
                .filter(|fragment| fragment.cells.end == self.grid_size.width)
                .last()
                .and_then(|fragment| {
                    // Unstyled cells use the window clear, including its exact
                    // alpha quantization. Leave that same clear in the margin.
                    fragment
                        .style
                        .as_ref()
                        .map(|_| grid_renderer.background_paint_color(fragment.style, opacity))
                });

            line.background_picture = background_picture;
            line.foreground_picture = foreground_picture;
            line.boxchar_picture = boxchar_picture;
            line.trailing_background = trailing_background;
            line.has_transparency = has_transparency;
            line.is_valid = true;
        };

        if !self.scrollback_lines.is_empty() {
            for line in self
                .scrollback_lines
                .iter_range_mut(scroll_offset_lines..scroll_offset_lines + height + 1)
                .flatten()
            {
                prepare_line(line)
            }
        }

        for line in
            self.actual_lines.iter_range_mut(0..self.viewport_margins.top as isize).flatten()
        {
            prepare_line(line)
        }
        let actual_line_count = self.actual_lines.len() as isize;
        for line in self
            .actual_lines
            .iter_range_mut(
                actual_line_count - self.viewport_margins.bottom as isize..actual_line_count,
            )
            .flatten()
        {
            prepare_line(line)
        }
    }
}

fn draw_line_foreground<'a>(
    renderer: &mut GridRenderer,
    text_canvas: &Canvas,
    boxchar_canvas: &Canvas,
    fragments: impl Iterator<Item = LineFragment<'a>>,
    position: PixelPos<f32>,
    opacity: f32,
) -> (bool, bool) {
    let (mut text_drawn, mut boxchar_drawn) = (false, false);
    let mut icons = Vec::new();
    let mut caps = Vec::new();
    let mut foreground = Vec::new();
    let mut reference_outlines: Vec<(Range<u32>, Color4f)> = Vec::new();
    for fragment in fragments {
        let style = fragment.style.as_ref().unwrap_or(&renderer.default_style);
        if style.reference_outline && !fragment.cells.is_empty() {
            let color = style.special(&renderer.default_style.colors);
            if let Some((cells, previous_color)) = reference_outlines.last_mut()
                && cells.end == fragment.cells.start
                && *previous_color == color
            {
                // Syntax and CursorLine can split one reference into several
                // fragments. Merge by the outline color, not the text style.
                cells.end = fragment.cells.end;
            } else {
                reference_outlines.push((fragment.cells.clone(), color));
            }
        }
        if style.avante_solid_cap && crate::renderer::box_drawing::is_box_char(fragment.text) {
            caps.push(fragment);
        } else {
            foreground.push(fragment);
        }
    }
    if let Some(last) = caps.last() {
        let bounds = Rect::from_wh(
            last.cells.end as f32 * renderer.grid_scale.width(),
            renderer.grid_scale.height(),
        );
        let mut recorder = PictureRecorder::new();
        let cap_canvas = recorder.begin_recording(bounds.with_offset((position.x, 0.0)), false);
        let mut caps_drawn = false;
        for cap in caps {
            let (text, boxes) =
                renderer.draw_foreground(text_canvas, cap_canvas, &cap, position, opacity);
            text_drawn |= text;
            caps_drawn |= boxes;
        }
        if caps_drawn {
            let caps = recorder.finish_recording_as_picture(None).unwrap();
            let mut matrix = Matrix::new_identity();
            matrix.set_translate((-position.x, 0.0));
            // Filled title caps are background shapes: place them below all
            // glyphs, including ordinary statusline logos that overhang a cell.
            // Keep other box-drawing characters in their existing upper layer.
            text_canvas.draw_picture(&caps, Some(&matrix), None);
            text_drawn = true;
            // Preserve the world-X cache dependency even when caps are the
            // only native shapes; moving the window must realign their pixels.
            boxchar_drawn = true;
        }
    }
    for fragment in foreground {
        let style = fragment.style.as_ref().unwrap_or(&renderer.default_style);
        if style.enlarged_icon && !crate::renderer::box_drawing::is_box_char(fragment.text) {
            icons.push(fragment);
            continue;
        }
        let (text, boxes) =
            renderer.draw_foreground(text_canvas, boxchar_canvas, &fragment, position, opacity);
        text_drawn |= text;
        boxchar_drawn |= boxes;
    }
    // Box pictures record world X for native pixel alignment. Glyphs are local
    // to the line, so translate once before recording their final overlay. The
    // existing box-picture replay removes this X again when the window moves.
    boxchar_canvas.save();
    boxchar_canvas.translate((position.x, 0.0));
    for icon in icons {
        let (text, boxes) =
            renderer.draw_foreground(boxchar_canvas, boxchar_canvas, &icon, position, opacity);
        boxchar_drawn |= text || boxes;
    }
    boxchar_canvas.restore();
    for (cells, color) in reference_outlines {
        text_drawn |= renderer.draw_reference_outline(text_canvas, &cells, color);
    }
    (text_drawn, boxchar_drawn)
}

struct BackgroundFillRect {
    rect: Rect,
    color: Color4f,
}

/// Background rects drawn outside the grid-owned cell area.
#[derive(Default)]
struct BackgroundFills {
    rects: Vec<BackgroundFillRect>,
}

impl BackgroundFills {
    fn push(&mut self, rect: Rect, color: Color4f) {
        if rect.is_empty() {
            return;
        }

        self.rects.push(BackgroundFillRect { rect, color });
    }

    fn draw(&self, canvas: &Canvas, clip_region: PixelRect<f32>) {
        if self.rects.is_empty() {
            return;
        }

        let mut paint = Paint::default();
        paint.set_anti_alias(false);
        // Extend the cell background without accumulating alpha over the canvas background.
        paint.set_blend_mode(BlendMode::Src);

        canvas.save();
        canvas.clip_rect(to_skia_rect(&clip_region), None, false);

        for fill in &self.rects {
            paint.set_color4f(fill.color, None);
            canvas.draw_rect(fill.rect, &paint);
        }

        canvas.restore();
    }

    fn path_and_bounds(&self) -> Option<(Path, Rect)> {
        let mut builder = PathBuilder::new();
        let mut bounds = None;

        for fill in &self.rects {
            push_fill_rect_path(&mut builder, &mut bounds, fill.rect);
        }

        bounds.map(|bounds| (builder.detach(), bounds))
    }
}

fn sub_cell_edge_gap(expanded_edge: f32, base_edge: f32, cell_extent: f32) -> Option<f32> {
    let extra_extent = expanded_edge - base_edge;
    if extra_extent > 0.0 && extra_extent <= cell_extent * MAX_EDGE_FILL_CELLS + f32::EPSILON {
        Some(extra_extent)
    } else {
        None
    }
}

fn push_fill_rect_path(builder: &mut PathBuilder, bounds: &mut Option<Rect>, rect: Rect) {
    if rect.is_empty() {
        return;
    }

    builder
        .move_to((rect.left, rect.top))
        .line_to((rect.right, rect.top))
        .line_to((rect.right, rect.bottom))
        .line_to((rect.left, rect.bottom))
        .close();

    *bounds = Some(match *bounds {
        Some(current) => Rect::join2(current, rect),
        None => rect,
    });
}

#[cfg(test)]
#[path = "rendered_window_enlarged_icon_tests.rs"]
mod enlarged_icon_tests;

#[cfg(test)]
mod tests {
    use crate::units::PixelSize;

    use super::*;

    fn grid_scale() -> GridScale {
        GridScale::new(PixelSize::new(8.0, 16.0))
    }

    #[test]
    fn notebook_output_hit_bounds_keep_complete_frame_and_owner_clip_without_copying_seam() {
        let scale = grid_scale();
        let mut window = RenderedWindow::new(2);
        window.handle_window_draw_command(WindowDrawCommand::Position {
            grid_position: (3.0, 2.0),
            grid_size: (20, 10),
            anchor_info: None,
            window_type: WindowType::Editor,
        });
        window.grid_current_position = GridPos::new(3.0, 2.0);
        window.viewport_margins = ViewportMargins { top: 1, bottom: 1 };

        // No text lines are installed: image and blank output must still hit.
        let region =
            window.notebook_output_region(Rect::new(26.4, 56.0, 200.0, 190.0), scale).unwrap();
        assert_eq!(region.hit_bounds, PixelRect::from_min_max((26.4, 56.0), (184.0, 176.0)));
        assert_eq!(region.bounds, PixelRect::from_min_max((32.0, 64.0), (184.0, 176.0)));
        assert_eq!(region.cells, GridRect::from_min_max((1, 2), (20, 9)));
        assert!(
            region.hit(PixelPos::new(27.0, 56.5), 2),
            "side and seam padding remains clickable"
        );
        assert!(region.hit(PixelPos::new(100.0, 100.0), 2), "blank or image interior is clickable");
        assert!(!region.hit(PixelPos::new(27.0, 56.5), 7), "a covering float retains the click");
        assert_eq!(region.position(PixelPos::new(27.0, 56.5), scale), GridPos::new(1, 2));

        let clipped =
            window.notebook_output_region(Rect::new(20.0, 40.0, 200.0, 190.0), scale).unwrap();
        assert_eq!(clipped.hit_bounds, PixelRect::from_min_max((24.0, 48.0), (184.0, 176.0)));
        for point in [(23.0, 80.0), (30.0, 47.0), (185.0, 80.0), (30.0, 177.0)] {
            assert!(!clipped.hit(point.into(), 2), "outside the owner clip: {point:?}");
        }
    }

    #[test]
    fn notebook_title_alignment_replays_whole_groups_at_exact_frame_edges() {
        use skia_safe::surfaces;
        let scale = GridScale::new(PixelSize::new(10.0, 20.0));
        let layout =
            NotebookTitleLayout { kernel: (7.0, 12.0), actions: (80.0, 98.0), host_width: 100.0 };
        for origin_x in [0.0, 83.5] {
            let mut recorder = PictureRecorder::new();
            let canvas =
                recorder.begin_recording(Rect::from_xywh(origin_x, 0.0, 980.0, 20.0), false);
            canvas.translate((origin_x, 0.0));
            let blocks = [
                (70.0, 50.0, Color::RED),
                (90.0, 10.0, Color::YELLOW),
                (400.0, 20.0, Color::GREEN),
                (800.0, 180.0, Color::BLUE),
                (970.0, 10.0, Color::WHITE),
            ];
            for (x, width, color) in blocks {
                canvas.draw_rect(
                    Rect::from_xywh(x, 0.0, width, 20.0),
                    &Paint::new(Color4f::from(color), None),
                );
            }
            let picture = recorder.finish_recording_as_picture(None).unwrap();
            let mut actual = surfaces::raster_n32_premul((1100, 40)).unwrap();
            actual.canvas().clear(Color::TRANSPARENT);
            let mut matrix = Matrix::new_identity();
            matrix.set_translate((50.0 - origin_x, 10.0));
            layout.draw(actual.canvas(), &picture, &matrix, scale, origin_x);
            let mut expected = surfaces::raster_n32_premul((1100, 40)).unwrap();
            expected.canvas().clear(Color::TRANSPARENT);
            for (x, width, color) in blocks {
                let shift = if x < 120.0 {
                    2.0
                } else if x >= 800.0 {
                    8.8
                } else {
                    0.0
                };
                expected.canvas().draw_rect(
                    Rect::from_xywh(50.0 + x + shift, 10.0, width, 20.0),
                    &Paint::new(Color4f::from(color), None),
                );
            }
            let actual = actual.peek_pixels().unwrap();
            let expected = expected.peek_pixels().unwrap();
            for y in 0..40 {
                for x in 0..1100 {
                    assert_eq!(
                        actual.get_color((x, y)),
                        expected.get_color((x, y)),
                        "header layer/ordinary content mismatch at {x},{y}; origin {origin_x}"
                    );
                }
            }
        }
    }

    #[test]
    fn clear_does_not_resurrect_old_statusline_after_partial_redraw() {
        let mut window = RenderedWindow::new(BASE_GRID_ID);
        window.handle_window_draw_command(WindowDrawCommand::Position {
            grid_position: (0.0, 0.0),
            grid_size: (20, 5),
            anchor_info: None,
            window_type: WindowType::Editor,
        });
        window.handle_window_draw_command(WindowDrawCommand::DrawLine {
            row: 3,
            line: Line::empty(),
        });
        window.flush(&RendererSettings::default());
        assert!(window.actual_lines[3].is_some());
        assert!(window.scrollback_lines[3].is_some());

        window.handle_window_draw_command(WindowDrawCommand::Clear);
        window.handle_window_draw_command(WindowDrawCommand::DrawLine {
            row: 4,
            line: Line::empty(),
        });
        window.flush(&RendererSettings::default());

        assert!(window.actual_lines[3].is_none());
        assert!(window.scrollback_lines[3].is_none());
        assert!(window.actual_lines[4].is_some());
        assert!(window.scrollback_lines[4].is_some());
    }

    #[test]
    fn sub_cell_edge_gap_accepts_only_positive_sub_cell_gaps() {
        assert_eq!(sub_cell_edge_gap(17.0, 10.0, 16.0), Some(7.0));
        assert_eq!(sub_cell_edge_gap(26.0, 10.0, 16.0), Some(16.0));
        assert_eq!(sub_cell_edge_gap(10.0, 10.0, 16.0), None);
        assert_eq!(sub_cell_edge_gap(27.0, 10.0, 16.0), None);
    }

    #[test]
    fn notebook_viewport_stale_wide_grid_is_clipped_to_latest_host_without_resizing_it() {
        use skia_safe::surfaces;

        let scale = grid_scale();
        let mut window = RenderedWindow::new(2);
        window.handle_window_draw_command(WindowDrawCommand::Position {
            grid_position: (0.0, 0.0),
            grid_size: (106, 24),
            anchor_info: None,
            window_type: WindowType::Editor,
        });
        window.handle_window_draw_command(WindowDrawCommand::HostSize { width: 81, height: 31 });
        let mut surface = surfaces::raster_n32_premul((900, 500)).unwrap();
        surface.canvas().clear(Color::RED);
        let host = window.draw(surface.canvas(), Color::BLUE, scale, None, false).region;
        assert_eq!(
            window.grid_size,
            GridSize::new(106, 24),
            "actual grid remains independently allocated"
        );
        assert_eq!(host.max.x, 81.0 * scale.width());
        let pixels = surface.peek_pixels().unwrap();
        assert_eq!(pixels.get_color((647, 8)), Color::BLUE);
        assert_eq!(
            pixels.get_color((648, 8)),
            Color::RED,
            "stale grid cannot paint the neighboring split"
        );
    }

    #[test]
    fn notebook_viewport_late_oversize_grid_cannot_cover_global_statusline() {
        use skia_safe::surfaces;
        let scale = grid_scale();
        let mut window = RenderedWindow::new(2);
        // The ordinary .py window from the observed late Notebook request:
        // root 134x35, host starts at (28,1), host 106x33, stale grid 120x37.
        window.handle_window_draw_command(WindowDrawCommand::Position {
            grid_position: (28.0, 1.0),
            grid_size: (120, 37),
            anchor_info: None,
            window_type: WindowType::Editor,
        });
        window.handle_window_draw_command(WindowDrawCommand::HostSize { width: 106, height: 33 });
        window.grid_current_position = GridPos::new(28.0, 1.0);
        let mut surface = surfaces::raster_n32_premul((134 * 8, 35 * 16)).unwrap();
        surface.canvas().clear(Color::RED); // Global statusline already drawn by grid 1.
        let region = window.draw(surface.canvas(), Color::BLUE, scale, None, true).region;
        assert_eq!(window.grid_size, GridSize::new(120, 37), "actual allocation remains separate");
        assert_eq!(region.max.y, 34.0 * 16.0);
        let pixels = surface.peek_pixels().unwrap();
        assert_eq!(pixels.get_color((600, 543)), Color::BLUE);
        for x in [8, 600, 1060] {
            for y in 544..560 {
                assert_eq!(pixels.get_color((x, y)), Color::RED, "global statusline at ({x},{y})");
            }
        }
    }

    #[test]
    fn fractional_bottom_gap_keeps_default_background_in_root_and_floating_windows() {
        use crate::renderer::rendered_layer::FloatingLayer;
        use skia_safe::surfaces;

        let grid_scale = grid_scale();
        let background = Color::from_rgb(11, 14, 20);
        let left_color = Color::from_rgb(240, 70, 100);
        let right_color = Color::from_rgb(0, 190, 240);
        let content_region = PixelRect::new(PixelPos::new(0.0, 0.0), PixelPos::new(35.0, 39.0));

        for floating in [false, true] {
            let mut window = RenderedWindow::new(BASE_GRID_ID);
            window.handle_window_draw_command(WindowDrawCommand::Position {
                grid_position: (0.0, 0.0),
                grid_size: (4, 2),
                anchor_info: None,
                window_type: WindowType::Editor,
            });
            window.viewport_margins = ViewportMargins { top: 0, bottom: 1 };
            let mut recorder = PictureRecorder::new();
            let canvas = recorder.begin_recording(Rect::from_wh(32.0, 16.0), false);
            let mut paint = Paint::default();
            paint.set_color(left_color);
            canvas.draw_rect(Rect::from_xywh(0.0, 0.0, 16.0, 16.0), &paint);
            paint.set_color(right_color);
            canvas.draw_rect(Rect::from_xywh(16.0, 0.0, 16.0, 16.0), &paint);
            window.actual_lines[1] = Some(Rc::new(RefCell::new(RenderedLine {
                line: Line::empty(),
                background_picture: recorder.finish_recording_as_picture(None),
                foreground_picture: None,
                boxchar_picture: None,
                trailing_background: Some(right_color.into()),
                has_transparency: false,
                is_valid: true,
            })));

            let mut surface = surfaces::raster_n32_premul((35, 39)).unwrap();
            surface.canvas().clear(background);
            let region = if floating {
                let settings = RendererSettings {
                    floating_shadow: false,
                    floating_blur: false,
                    floating_corner_radius: 0.0,
                    ..RendererSettings::default()
                };
                FloatingLayer { windows: vec![&mut window] }
                    .draw(
                        surface.canvas(),
                        &settings,
                        background,
                        grid_scale,
                        Some(content_region),
                        &Default::default(),
                    )
                    .remove(0)
                    .region
            } else {
                window
                    .draw(surface.canvas(), background, grid_scale, Some(content_region), true)
                    .region
            };
            assert_eq!(region.max, PixelPos::new(35.0, 32.0));

            let pixels = surface.peek_pixels().unwrap();
            assert_eq!(pixels.get_color((4, 31)), left_color);
            assert_eq!(pixels.get_color((24, 31)), right_color);
            // Keep the right-hand fractional fill within the complete status line.
            assert_eq!(pixels.get_color((34, 31)), right_color);
            for y in 32..39 {
                for x in 0..35 {
                    assert_eq!(
                        pixels.get_color((x, y)),
                        background,
                        "bottom remainder at ({x}, {y}), floating={floating}"
                    );
                }
            }
        }
    }

    #[test]
    fn fractional_right_remainder_inherits_cell_while_notebook_margin_keeps_normal() {
        use std::sync::Arc;

        use crate::{
            editor::{Colors, Style},
            window::WindowSettings,
        };
        use skia_safe::surfaces;

        let settings = Arc::new(Settings::new());
        settings.set(&RendererSettings::default());
        let mut renderer = GridRenderer::new(1.0, settings.clone());
        let normal = Color::from_rgb(250, 250, 250);
        renderer.default_style = Arc::new(Style::new(Colors::new(None, Some(normal.into()), None)));

        for cell_width in [7.5, 8.0, 11.25] {
            let scale = GridScale::new(PixelSize::new(cell_width, 16.0));
            renderer.grid_scale = scale;
            for reserved_columns in [0, 2] {
                for (name, normal_opacity, background, blend, expected_alpha) in [
                    ("Normal", 0.78, None, 0, 198),
                    ("NeoTreeNormal", 0.78, Some(Color::from_rgb(243, 243, 243)), 40, 153),
                    ("NeoTreeCursorLine", 0.78, Some(normal), 40, 153),
                    ("CursorLine", 0.78, Some(Color::from_rgb(239, 239, 239)), 40, 153),
                    ("Visual", 0.78, Some(Color::from_rgb(220, 230, 240)), 0, 255),
                    ("Opaque", 1.0, None, 0, 255),
                ] {
                    settings.set(&WindowSettings { normal_opacity, ..WindowSettings::default() });
                    let base = renderer.get_default_background(normal_opacity);
                    let style = background.map(|color| {
                        Arc::new(Style {
                            blend,
                            ..Style::new(Colors::new(None, Some(color.into()), None))
                        })
                    });
                    let mut window = RenderedWindow::new(2);
                    window.handle_window_draw_command(WindowDrawCommand::Position {
                        grid_position: (0.0, 0.0),
                        grid_size: (4, 2),
                        anchor_info: None,
                        window_type: WindowType::Editor,
                    });
                    window.handle_window_draw_command(WindowDrawCommand::HostSize {
                        width: 4 + reserved_columns,
                        height: 2,
                    });
                    window.viewport_margins = ViewportMargins { top: 0, bottom: 1 };
                    let mut recorder = PictureRecorder::new();
                    renderer.draw_background(
                        recorder.begin_recording(Rect::from_wh(4.0 * cell_width, 16.0), false),
                        &(0..4),
                        &style,
                        1.0,
                    );
                    window.actual_lines[1] = Some(Rc::new(RefCell::new(RenderedLine {
                        line: Line::empty(),
                        background_picture: recorder.finish_recording_as_picture(None),
                        foreground_picture: None,
                        boxchar_picture: None,
                        trailing_background: style
                            .as_ref()
                            .map(|_| renderer.background_paint_color(&style, 1.0)),
                        has_transparency: normal_opacity < 1.0,
                        is_valid: true,
                    })));
                    let host_width = (4 + reserved_columns) as f32 * cell_width;
                    let content_width = host_width.ceil() as i32 + 3;
                    let content = PixelRect::from_origin_and_size(
                        PixelPos::ZERO,
                        PixelSize::new(content_width as f32, 39.0),
                    );
                    let mut surface = surfaces::raster_n32_premul((content_width, 39)).unwrap();
                    surface.canvas().clear(base);
                    let details = window.draw(surface.canvas(), base, scale, Some(content), true);
                    assert_eq!(details.region.max.x, content_width as f32);
                    assert_eq!(window.grid_size.width, 4, "background fill must not resize text");
                    let pixels = surface.peek_pixels().unwrap();
                    let adjacent = pixels.get_color(((4.0 * cell_width) as i32 - 2, 24));
                    assert_eq!(adjacent.a(), expected_alpha, "{name} adjacent alpha");
                    let expected_margin = if reserved_columns > 0 { base } else { adjacent };
                    for x in (4.0 * cell_width).ceil() as i32..content_width {
                        assert_eq!(
                            pixels.get_color((x, 24)),
                            expected_margin,
                            "{name}: cell_width={cell_width}, reserved={reserved_columns}, x={x}"
                        );
                    }
                    assert_eq!(
                        pixels.get_color((content_width - 1, 35)),
                        base,
                        "fractional bottom padding keeps its independent default background"
                    );
                }
            }
        }
    }
}
