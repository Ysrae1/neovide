use skia_safe::Color4f;

#[derive(Debug, Clone, PartialEq)]
pub struct Colors {
    /// Foreground color.
    pub foreground: Option<Color4f>,
    /// Background color.
    pub background: Option<Color4f>,
    /// Color to use for various underlines, when present.
    pub special: Option<Color4f>,
}

impl Colors {
    pub fn new(
        foreground: Option<Color4f>,
        background: Option<Color4f>,
        special: Option<Color4f>,
    ) -> Self {
        Self { foreground, background, special }
    }
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum UnderlineStyle {
    Underline,
    UnderDouble,
    UnderDash,
    UnderDot,
    UnderCurl,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotebookTitleGroup {
    Kernel,
    Actions,
}

/// Rendering behavior declared by Lua, independent of theme group names.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HighlightRole {
    EnlargedIcon,
    NotebookKernel,
    NotebookActions,
    SolidTitleCap,
    ReferenceOutline,
    CenteredCaption,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Style {
    pub colors: Colors,
    /// Reverse video, i.e. switch foreground and background colors.
    pub reverse: bool,
    /// Italic text.
    pub italic: bool,
    /// Bold text.
    pub bold: bool,
    /// Struck through text.
    pub strikethrough: bool,
    /// Blend level (0-100).
    pub blend: u8,
    pub underline: Option<UnderlineStyle>,
    /// Scale only the foreground of Notebook type-icon capsules.
    pub enlarged_icon: bool,
    pub notebook_title: Option<NotebookTitleGroup>,
    /// Avante's solid title endcap over its independently blended panel base.
    pub avante_solid_cap: bool,
    /// Draw one thin box around each contiguous highlighted reference.
    pub reference_outline: bool,
    /// Center only caption ink inside its existing colored grid cells.
    pub centered_caption: bool,
}

impl Style {
    pub fn new(colors: Colors) -> Self {
        Self {
            colors,
            reverse: false,
            italic: false,
            bold: false,
            strikethrough: false,
            blend: 0,
            underline: None,
            enlarged_icon: false,
            notebook_title: None,
            avante_solid_cap: false,
            reference_outline: false,
            centered_caption: false,
        }
    }

    pub fn with_roles(mut self, roles: impl IntoIterator<Item = HighlightRole>) -> Self {
        self.enlarged_icon = false;
        self.notebook_title = None;
        self.avante_solid_cap = false;
        self.reference_outline = false;
        self.centered_caption = false;
        for role in roles {
            match role {
                HighlightRole::EnlargedIcon => self.enlarged_icon = true,
                HighlightRole::NotebookKernel => {
                    self.notebook_title = Some(NotebookTitleGroup::Kernel)
                }
                HighlightRole::NotebookActions => {
                    self.notebook_title = Some(NotebookTitleGroup::Actions)
                }
                HighlightRole::SolidTitleCap => self.avante_solid_cap = true,
                HighlightRole::ReferenceOutline => self.reference_outline = true,
                HighlightRole::CenteredCaption => self.centered_caption = true,
            }
        }
        self
    }

    pub fn foreground(&self, default_colors: &Colors) -> Color4f {
        if self.reverse {
            self.colors.background.unwrap_or_else(|| default_colors.background.unwrap())
        } else {
            self.colors.foreground.unwrap_or_else(|| default_colors.foreground.unwrap())
        }
    }

    pub fn background(&self, default_colors: &Colors) -> Color4f {
        if self.reverse {
            self.colors.foreground.unwrap_or_else(|| default_colors.foreground.unwrap())
        } else {
            self.colors.background.unwrap_or_else(|| default_colors.background.unwrap())
        }
    }

    pub fn special(&self, default_colors: &Colors) -> Color4f {
        self.colors.special.unwrap_or_else(|| self.foreground(default_colors))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const COLORS: Colors = Colors {
        foreground: Some(Color4f::new(0.1, 0.1, 0.1, 0.1)),
        background: Some(Color4f::new(0.2, 0.1, 0.1, 0.1)),
        special: Some(Color4f::new(0.3, 0.1, 0.1, 0.1)),
    };

    const DEFAULT_COLORS: Colors = Colors {
        foreground: Some(Color4f::new(0.1, 0.2, 0.1, 0.1)),
        background: Some(Color4f::new(0.2, 0.2, 0.1, 0.1)),
        special: Some(Color4f::new(0.3, 0.2, 0.1, 0.1)),
    };

    #[test]
    fn roles_change_only_rendering_behavior_and_can_be_cleared() {
        let original = Style::new(COLORS);
        let marked = original.clone().with_roles([
            HighlightRole::EnlargedIcon,
            HighlightRole::NotebookKernel,
            HighlightRole::SolidTitleCap,
            HighlightRole::ReferenceOutline,
            HighlightRole::CenteredCaption,
        ]);
        assert!(marked.enlarged_icon && marked.avante_solid_cap && marked.reference_outline);
        assert!(marked.centered_caption);
        assert_eq!(marked.notebook_title, Some(NotebookTitleGroup::Kernel));
        assert_eq!(marked.colors, original.colors);
        assert_eq!(marked.with_roles([]), original);
        assert_eq!(
            original.with_roles([HighlightRole::NotebookActions]).notebook_title,
            Some(NotebookTitleGroup::Actions)
        );
    }

    #[test]
    fn test_foreground() {
        let mut style = Style::new(COLORS);

        assert_eq!(style.foreground(&DEFAULT_COLORS), COLORS.foreground.unwrap());
        style.colors.foreground = None;
        assert_eq!(style.foreground(&DEFAULT_COLORS), DEFAULT_COLORS.foreground.unwrap());
    }

    #[test]
    fn test_foreground_reverse() {
        let mut style = Style::new(COLORS);
        style.reverse = true;

        assert_eq!(style.foreground(&DEFAULT_COLORS), COLORS.background.unwrap());
        style.colors.background = None;
        assert_eq!(style.foreground(&DEFAULT_COLORS), DEFAULT_COLORS.background.unwrap());
    }

    #[test]
    fn test_background() {
        let mut style = Style::new(COLORS);

        assert_eq!(style.background(&DEFAULT_COLORS), COLORS.background.unwrap());
        style.colors.background = None;
        assert_eq!(style.background(&DEFAULT_COLORS), DEFAULT_COLORS.background.unwrap());
    }

    #[test]
    fn test_background_reverse() {
        let mut style = Style::new(COLORS);
        style.reverse = true;

        assert_eq!(style.background(&DEFAULT_COLORS), COLORS.foreground.unwrap());
        style.colors.foreground = None;
        assert_eq!(style.background(&DEFAULT_COLORS), DEFAULT_COLORS.foreground.unwrap());
    }

    #[test]
    fn test_special() {
        let mut style = Style::new(COLORS);

        assert_eq!(style.special(&DEFAULT_COLORS), COLORS.special.unwrap());
        style.colors.special = None;
        assert_eq!(style.special(&DEFAULT_COLORS), style.foreground(&DEFAULT_COLORS),);
    }
}
