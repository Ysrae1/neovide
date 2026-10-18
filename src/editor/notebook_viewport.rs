//! Notebook text grids may be narrower than their unchanged split layout.
//! This tracks asynchronous requests without querying Neovim or retrying its
//! own resize feedback; win_pos invalidates requests after real layout changes.
use crate::renderer::notebook::NotebookViewport;
use std::collections::HashMap;

#[derive(Default)]
pub(super) struct NotebookViewports {
    wanted: HashMap<u64, (u64, bool)>, // logical host width, active Notebook
    owners: HashMap<u64, u64>,         // grid -> Neovim window
    sizes: HashMap<u64, (u64, u64)>,
    hosts: HashMap<u64, (u64, u64)>,
    top_margins: HashMap<u64, u64>,
    sent: HashMap<u64, (u64, u64)>,
}
impl NotebookViewports {
    pub fn replace(&mut self, viewports: &[NotebookViewport]) {
        for target in self.wanted.values_mut() {
            target.1 = false;
        }
        for viewport in viewports {
            // A delayed Lua snapshot describes the layout it observed. Once
            // win_pos has supplied a newer host width, that UI event wins.
            let width = self
                .owners
                .iter()
                .find_map(|(grid, window)| {
                    (*window == viewport.window)
                        .then(|| self.hosts.get(grid).map(|size| size.0))
                        .flatten()
                })
                .unwrap_or(viewport.width);
            self.wanted.insert(viewport.window, (width, true));
        }
    }
    pub fn associate(&mut self, grid: u64, window: u64) {
        self.owners.insert(grid, window);
        if let (Some(host), Some(target)) = (self.hosts.get(&grid), self.wanted.get_mut(&window)) {
            target.0 = host.0;
        }
    }
    pub fn resize(&mut self, grid: u64, width: u64, height: u64) {
        self.sizes.insert(grid, (width, height));
    }
    pub fn position(&mut self, grid: u64, width: u64, height: u64) {
        // win_pos is the split layout, not a grid_resize acknowledgement.
        let changed = self.hosts.insert(grid, (width, height)) != Some((width, height));
        if let Some(window) = self.owners.get(&grid)
            && let Some(target) = self.wanted.get_mut(window)
        {
            target.0 = width;
        }
        if changed {
            self.sent.remove(&grid);
        }
    }
    pub fn top_margin(&mut self, grid: u64, top: u64) {
        if self.top_margins.insert(grid, top) != Some(top) {
            self.sent.remove(&grid);
        }
    }
    pub fn close(&mut self, grid: u64) {
        if let Some(window) = self.owners.remove(&grid) {
            self.wanted.remove(&window);
        }
        self.sizes.remove(&grid);
        self.sent.remove(&grid);
        self.hosts.remove(&grid);
        self.top_margins.remove(&grid);
    }
    pub fn requests(&mut self) -> Vec<(u64, u64, u64)> {
        let mut result = Vec::new();
        for (&grid, &window) in &self.owners {
            let (Some(&(fallback_host, active)), Some(&(actual, actual_height))) =
                (self.wanted.get(&window), self.sizes.get(&grid))
            else {
                continue;
            };
            let (host, height) =
                self.hosts.get(&grid).copied().unwrap_or((fallback_host, actual_height));
            let width = if active { host.saturating_sub(2).max(1) } else { host };
            if actual == width && actual_height == height {
                // This target has arrived; it is no longer pending. If a stale
                // request later changes the grid again, a correction is needed.
                self.sent.remove(&grid);
            } else if self.sent.get(&grid) != Some(&(width, height)) {
                self.sent.insert(grid, (width, height));
                // The actual normal-window grid includes its winbar. Neovim's
                // resize API accepts only the inner text height and adds that
                // margin back; feeding the full height grows the grid one row.
                let inner_height =
                    height.saturating_sub(self.top_margins.get(&grid).copied().unwrap_or(0)).max(1);
                result.push((grid, width, inner_height));
            }
        }
        // Keep restored owners tracked until close: a queued stale request can
        // still arrive after the first successful full-width restoration.
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn notebook_viewport_waits_for_grid_and_restores_without_resize_feedback_loop() {
        let mut state = NotebookViewports::default();
        state.replace(&[NotebookViewport { window: 1000, width: 80 }]);
        assert!(state.requests().is_empty());
        state.resize(2, 80, 24);
        assert!(state.requests().is_empty());
        state.associate(2, 1000);
        assert_eq!(state.requests(), [(2, 78, 24)]);
        state.resize(2, 78, 24);
        assert!(state.requests().is_empty());
        state.replace(&[NotebookViewport { window: 1000, width: 80 }]);
        assert!(state.requests().is_empty());
        // A clamped request can never create an unbounded feedback retry.
        state.position(2, 60, 24);
        assert_eq!(state.requests(), [(2, 58, 24)]);
        state.resize(2, 30, 24);
        assert!(state.requests().is_empty());
        state.replace(&[NotebookViewport { window: 1000, width: 50 }]);
        assert!(state.requests().is_empty(), "old snapshot cannot override the 60-column host");
        state.replace(&[]);
        assert_eq!(state.requests(), [(2, 60, 24)]);
        state.resize(2, 60, 24);
        assert!(state.requests().is_empty());
        state.resize(2, 60, 30);
        assert_eq!(state.requests(), [(2, 60, 24)], "late feedback still restores the latest host");
        assert!(state.requests().is_empty(), "unchanged mismatch does not retry");
    }
    #[test]
    fn notebook_viewport_old_feedback_cannot_discard_a_newer_queued_target() {
        let mut state = NotebookViewports::default();
        state.resize(2, 80, 24);
        state.position(2, 80, 24);
        state.associate(2, 1000);
        state.replace(&[NotebookViewport { window: 1000, width: 80 }]);
        assert_eq!(state.requests(), [(2, 78, 24)]);
        state.position(2, 90, 24);
        assert_eq!(state.requests(), [(2, 88, 24)]);
        state.resize(2, 78, 24); // older FIFO request's feedback
        assert!(state.requests().is_empty()); // latest 88 is already queued
        state.resize(2, 88, 24);
        assert!(state.requests().is_empty());
        state.replace(&[]);
        assert_eq!(state.requests(), [(2, 90, 24)]);
        state.resize(2, 90, 24);
        assert!(state.requests().is_empty());
        state.close(2);
        assert!(state.requests().is_empty());
    }

    #[test]
    fn notebook_viewport_winbar_requests_inner_height_and_restored_owner_repairs_late_feedback() {
        let mut state = NotebookViewports::default();
        state.resize(2, 81, 37);
        state.position(2, 81, 37);
        state.top_margin(2, 1);
        state.associate(2, 1000);
        state.replace(&[NotebookViewport { window: 1000, width: 81 }]);
        assert_eq!(state.requests(), [(2, 79, 36)]);
        state.resize(2, 79, 37); // Neovim adds the winbar to the requested 36.
        assert!(state.requests().is_empty());
        state.replace(&[]);
        assert_eq!(state.requests(), [(2, 81, 36)]);
        state.resize(2, 81, 37);
        assert!(state.requests().is_empty());
        state.position(2, 106, 33);
        state.top_margin(2, 0); // Ordinary .py buffer, no winbar.
        assert_eq!(state.requests(), [(2, 106, 33)]);
        state.resize(2, 106, 33);
        assert!(state.requests().is_empty());
        state.resize(2, 120, 37); // Old Notebook request lands after restoration.
        assert_eq!(state.requests(), [(2, 106, 33)]);
        assert!(state.requests().is_empty(), "one pending correction, not a feedback loop");
        state.resize(2, 106, 33);
        assert!(state.requests().is_empty());
        state.close(2);
        state.resize(2, 120, 37);
        assert!(state.requests().is_empty(), "closed owners no longer request resizes");
    }
}
