use rmpv::Value;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum MenuLanguage {
    #[default]
    English,
    Chinese,
}

impl MenuLanguage {
    pub fn parse(arguments: &[Value]) -> Result<Self, &'static str> {
        let [Value::Map(fields)] = arguments else {
            return Err("expected one native menu language snapshot");
        };
        let field = |name: &str| {
            fields.iter().find_map(|(key, value)| (key.as_str() == Some(name)).then_some(value))
        };
        if field("version").and_then(Value::as_u64) != Some(1) {
            return Err("unsupported native menu language version");
        }
        match field("language").and_then(Value::as_str) {
            Some("en") => Ok(Self::English),
            Some("zh") => Ok(Self::Chinese),
            _ => Err("native menu language must be en or zh"),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub(super) enum MenuLabel {
    About,
    Services,
    Hide,
    HideOthers,
    Quit,
    Edit,
    Copy,
    Window,
    FullScreen,
    NewWindow,
    Editors,
    Minimize,
    Help,
    IssueReport,
    Documentation,
    Sponsor,
}

impl MenuLabel {
    pub(super) fn title(self, language: MenuLanguage, process: &str, fullscreen: bool) -> String {
        use MenuLabel::*;
        use MenuLanguage::*;
        match (self, language) {
            (About, English) => format!("About {process}"),
            (About, Chinese) => format!("关于 {process}"),
            (Hide, English) => format!("Hide {process}"),
            (Hide, Chinese) => format!("隐藏 {process}"),
            (Quit, English) => format!("Quit {process}"),
            (Quit, Chinese) => format!("退出 {process}"),
            (Services, English) => "Services".into(),
            (Services, Chinese) => "服务".into(),
            (HideOthers, English) => "Hide Others".into(),
            (HideOthers, Chinese) => "隐藏其他应用".into(),
            (Edit, English) => "Edit".into(),
            (Edit, Chinese) => "编辑".into(),
            (Copy, English) => "Copy".into(),
            (Copy, Chinese) => "复制".into(),
            (Window, English) => "Window".into(),
            (Window, Chinese) => "窗口".into(),
            (FullScreen, English) if fullscreen => "Exit Full Screen".into(),
            (FullScreen, English) => "Enter Full Screen".into(),
            (FullScreen, Chinese) if fullscreen => "退出全屏".into(),
            (FullScreen, Chinese) => "进入全屏".into(),
            (NewWindow, English) => "New Window".into(),
            (NewWindow, Chinese) => "新建窗口".into(),
            (Editors, English) => "Editors".into(),
            (Editors, Chinese) => "编辑器".into(),
            (Minimize, English) => "Minimize".into(),
            (Minimize, Chinese) => "最小化".into(),
            (Help, English) => "Help".into(),
            (Help, Chinese) => "帮助".into(),
            (IssueReport, English) => "Create Issue Report".into(),
            (IssueReport, Chinese) => "报告问题".into(),
            (Documentation, English) => "Documentation".into(),
            (Documentation, Chinese) => "使用文档".into(),
            (Sponsor, English) => "Sponsor".into(),
            (Sponsor, Chinese) => "赞助".into(),
        }
    }
}

// These selectors were observed on actual AppKit-generated window operations.
// They are used only as identities, never invoked. Unknown OS actions stay intact.
pub(super) fn system_window_command_title(
    action: &str,
    title: &str,
    language: MenuLanguage,
    fullscreen: bool,
) -> Option<String> {
    if action == "toggleFullScreen:" {
        return Some(MenuLabel::FullScreen.title(language, "", fullscreen));
    }
    if action == "_toggleIPad:" {
        // Display/device names are user content, including their whitespace.
        let name = title.strip_prefix("Move to ").or_else(|| title.strip_prefix("移到 "))?;
        return Some(format!(
            "{}{name}",
            if language == MenuLanguage::Chinese { "移到 " } else { "Move to " }
        ));
    }
    const COMMANDS: &[(&str, &str, &str)] = &[
        ("_zoomFill:", "Fill", "填充"),
        ("_zoomCenter:", "Center", "居中"),
        ("_zoomLeft:", "Left", "左半屏"),
        ("_zoomRight:", "Right", "右半屏"),
        ("_zoomTop:", "Top", "上半屏"),
        ("_zoomBottom:", "Bottom", "下半屏"),
        ("_zoomTopLeft:", "Top Left", "左上"),
        ("_zoomTopRight:", "Top Right", "右上"),
        ("_zoomBottomLeft:", "Bottom Left", "左下"),
        ("_zoomBottomRight:", "Bottom Right", "右下"),
        ("_zoomLeftAndRight:", "Left & Right", "左侧与右侧"),
        ("_zoomLeftThreeUp:", "Left & Quarters", "左侧与四分屏"),
        ("_zoomRightAndLeft:", "Right & Left", "右侧与左侧"),
        ("_zoomRightThreeUp:", "Right & Quarters", "右侧与四分屏"),
        ("_zoomTopAndBottom:", "Top & Bottom", "顶部与底部"),
        ("_zoomTopThreeUp:", "Top & Quarters", "顶部与四分屏"),
        ("_zoomBottomAndTop:", "Bottom & Top", "底部与顶部"),
        ("_zoomBottomThreeUp:", "Bottom & Quarters", "底部与四分屏"),
        ("_zoomQuarters:", "Quarters", "四分屏"),
        ("_zoomUntile:", "Return to Previous Size", "恢复上次大小"),
        ("_tileLeft:", "Left of Screen", "屏幕左侧"),
        ("_tileRight:", "Right of Screen", "屏幕右侧"),
        ("_removeWindowFromStageManagerSet:", "Remove Window from Set", "从窗口组移除"),
        ("miniaturizeAll:", "Minimize All", "最小化所有窗口"),
        ("selectPreviousTab:", "Show Previous Tab", "显示上一个标签页"),
        ("selectNextTab:", "Show Next Tab", "显示下一个标签页"),
        ("moveTabToNewWindow:", "Move Tab to New Window", "将标签页移到新窗口"),
        ("arrangeInFront:", "Bring All to Front", "全部前置"),
    ];
    COMMANDS.iter().find(|(selector, _, _)| *selector == action).map(|(_, en, zh)| {
        if language == MenuLanguage::Chinese { (*zh).into() } else { (*en).into() }
    })
}

pub(super) fn system_window_section_title(
    title: &str,
    language: MenuLanguage,
) -> Option<&'static str> {
    const SECTIONS: &[(&str, &str)] = &[
        ("Move & Resize", "移动与调整大小"),
        ("Full Screen Tile", "全屏拼排"),
        ("Halves", "半屏"),
        ("Quarters", "四分屏"),
        ("Arrange", "排列"),
    ];
    SECTIONS
        .iter()
        .find(|(en, zh)| title == *en || title == *zh)
        .map(|(en, zh)| if language == MenuLanguage::Chinese { *zh } else { *en })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot(version: u64, language: &str) -> Vec<Value> {
        vec![Value::Map(vec![
            ("version".into(), version.into()),
            ("language".into(), language.into()),
        ])]
    }

    #[test]
    fn native_menu_language_validates_snapshot() {
        assert_eq!(MenuLanguage::parse(&snapshot(1, "zh")), Ok(MenuLanguage::Chinese));
        assert_eq!(MenuLanguage::parse(&snapshot(1, "en")), Ok(MenuLanguage::English));
        assert!(MenuLanguage::parse(&snapshot(2, "zh")).is_err());
        assert!(MenuLanguage::parse(&snapshot(1, "fr")).is_err());
        assert!(MenuLanguage::parse(&[]).is_err());
        assert!(MenuLanguage::parse(&[Value::Nil]).is_err());
    }

    #[test]
    fn native_menu_titles_preserve_app_name_and_fullscreen_state() {
        assert_eq!(
            MenuLabel::About.title(MenuLanguage::Chinese, "Neovide Glow", false),
            "关于 Neovide Glow"
        );
        assert_eq!(MenuLabel::Quit.title(MenuLanguage::English, "Neovide", false), "Quit Neovide");
        assert_eq!(MenuLabel::FullScreen.title(MenuLanguage::Chinese, "", true), "退出全屏");
        assert_eq!(MenuLabel::FullScreen.title(MenuLanguage::Chinese, "", false), "进入全屏");
    }

    #[test]
    fn native_menu_system_actions_preserve_dynamic_names_and_unknown_commands() {
        assert_eq!(
            system_window_command_title("_zoomLeft:", "Left", MenuLanguage::Chinese, false)
                .as_deref(),
            Some("左半屏")
        );
        assert_eq!(
            system_window_command_title(
                "miniaturizeAll:",
                "最小化所有窗口",
                MenuLanguage::English,
                false
            )
            .as_deref(),
            Some("Minimize All")
        );
        assert_eq!(
            system_window_command_title(
                "_toggleIPad:",
                "Move to User Display 用户",
                MenuLanguage::Chinese,
                false
            )
            .as_deref(),
            Some("移到 User Display 用户")
        );
        assert_eq!(
            system_window_command_title(
                "makeKeyAndOrderFront:",
                "Left",
                MenuLanguage::Chinese,
                false
            ),
            None
        );
        assert_eq!(
            system_window_command_title("unknown:", "Left", MenuLanguage::Chinese, false),
            None
        );
        assert_eq!(
            system_window_section_title("Move & Resize", MenuLanguage::Chinese),
            Some("移动与调整大小")
        );
    }
}
