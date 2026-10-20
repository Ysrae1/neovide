use crate::editor::DrawCommand;

pub struct DrawCommandBatcher {
    batch: Vec<DrawCommand>,
    enabled: bool,
    queued: Vec<Vec<DrawCommand>>,
}

impl DrawCommandBatcher {
    pub fn new() -> DrawCommandBatcher {
        Self { batch: Vec::new(), enabled: true, queued: Vec::new() }
    }

    pub fn queue(&mut self, draw_command: DrawCommand) {
        self.batch.push(draw_command);
    }

    #[cfg(test)]
    pub fn take_commands(&mut self) -> Vec<DrawCommand> {
        std::mem::take(&mut self.batch)
    }

    pub fn set_enabled(&mut self, enabled: bool) -> Vec<Vec<DrawCommand>> {
        log::info!("Set redraw {enabled}");
        let queued =
            if enabled && !self.enabled { std::mem::take(&mut self.queued) } else { Vec::new() };
        self.enabled = enabled;
        queued
    }

    /// Finishes one redraw, keeping its commands together while display is paused.
    pub fn finish_batch(&mut self) -> Option<Vec<DrawCommand>> {
        let batch = std::mem::take(&mut self.batch);
        if self.enabled {
            Some(batch)
        } else {
            self.queued.push(batch);
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paused_redraws_replay_in_order_without_merging_batch_boundaries() {
        let mut batcher = DrawCommandBatcher::new();
        assert!(batcher.set_enabled(false).is_empty());

        let first = vec![DrawCommand::FontChanged("first".into()), DrawCommand::UIReady];
        for command in &first {
            batcher.queue(command.clone());
        }
        assert!(batcher.finish_batch().is_none());

        let second = vec![DrawCommand::FontChanged("second".into())];
        batcher.queue(second[0].clone());
        assert!(batcher.finish_batch().is_none());
        assert!(batcher.set_enabled(false).is_empty());

        assert_eq!(batcher.set_enabled(true), vec![first, second]);
        assert!(batcher.set_enabled(true).is_empty());
        batcher.queue(DrawCommand::UIReady);
        assert_eq!(batcher.finish_batch(), Some(vec![DrawCommand::UIReady]));
    }
}
