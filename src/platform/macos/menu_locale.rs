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
}
