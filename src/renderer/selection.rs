//! Selection stays in rendered-grid coordinates, never source-buffer rows.
use glamour::Contains;

use crate::units::{GridPos, GridRect, GridScale, PixelPos, PixelRect};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NotebookSelectionId {
    pub generation: u64,
    pub region: usize,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct NotebookOutputRegion {
    pub grid_id: u64,
    pub bounds: PixelRect<f32>,
    pub cells: GridRect<u32>,
    pub origin: PixelPos<f32>,
}

impl NotebookOutputRegion {
    pub fn position(&self, point: PixelPos<f32>, scale: GridScale) -> GridPos<u32> {
        let position = ((point - self.origin).to_point() / scale).floor();
        GridPos::new(
            (position.x.max(0.0) as u32).clamp(self.cells.min.x, self.cells.max.x - 1),
            (position.y.max(0.0) as u32).clamp(self.cells.min.y, self.cells.max.y - 1),
        )
    }

    pub fn hit(&self, point: PixelPos<f32>, topmost_grid: u64) -> bool {
        self.grid_id == topmost_grid && self.bounds.contains(&point)
    }
}

pub fn selection_spans(
    start: GridPos<u32>,
    end: GridPos<u32>,
    cells: GridRect<u32>,
) -> Vec<(u32, u32, u32)> {
    if cells.is_empty() {
        return Vec::new();
    }
    let clamp = |point: GridPos<u32>| {
        GridPos::new(
            point.x.clamp(cells.min.x, cells.max.x - 1),
            point.y.clamp(cells.min.y, cells.max.y - 1),
        )
    };
    let (start, end) = (clamp(start), clamp(end));
    let (start, end) =
        if (start.y, start.x) <= (end.y, end.x) { (start, end) } else { (end, start) };
    (start.y..=end.y)
        .map(|row| {
            (
                row,
                if row == start.y { start.x } else { cells.min.x },
                if row == end.y { end.x } else { cells.max.x - 1 },
            )
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::units::PixelSize;

    #[test]
    fn notebook_output_selection_preserves_reverse_columns_clamps_and_respects_floats() {
        let cells = GridRect::from_min_max((4, 2), (12, 5));
        assert_eq!(selection_spans((10, 2).into(), (6, 2).into(), cells), [(2, 6, 10)]);
        assert_eq!(
            selection_spans((7, 4).into(), (10, 2).into(), cells),
            [(2, 10, 11), (3, 4, 11), (4, 4, 7)]
        );
        let region = NotebookOutputRegion {
            grid_id: 2,
            cells,
            bounds: PixelRect::from_origin_and_size(
                (40.0, 40.0).into(),
                PixelSize::new(80.0, 60.0),
            ),
            origin: PixelPos::ZERO,
        };
        let scale = PixelSize::new(10.0, 20.0).into();
        assert_eq!(region.position((-100.0, -100.0).into(), scale), GridPos::new(4, 2));
        assert_eq!(region.position((500.0, 500.0).into(), scale), GridPos::new(11, 4));
        assert!(region.hit((50.0, 50.0).into(), 2));
        assert!(!region.hit((50.0, 50.0).into(), 7), "topmost float retains the click");
        assert!(!region.hit((30.0, 50.0).into(), 2), "gutter is not output");
    }
}
