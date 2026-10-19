use super::bundle_declares_application_icon;
use objc2_foundation::{NSBundle, NSString};

#[test]
fn native_and_legacy_application_icons_are_managed_by_the_bundle() {
    let root = std::env::temp_dir().join(format!(
        "neovide-bundle-icon-test-{}-{}",
        std::process::id(),
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()
    ));
    std::fs::create_dir(&root).unwrap();

    for (name, icon_fields, expected) in [
        ("Native.app", "<key>CFBundleIconName</key><string>Neovide</string>", true),
        ("Legacy.app", "<key>CFBundleIconFile</key><string>Neovide.icns</string>", true),
        ("NoIcon.app", "", false),
        ("EmptyIcon.app", "<key>CFBundleIconName</key><string></string>", false),
        ("InvalidIcon.app", "<key>CFBundleIconName</key><false/>", false),
        ("Standalone", "<key>CFBundleIconName</key><string>Neovide</string>", false),
    ] {
        let bundle_path = root.join(name);
        let contents = bundle_path.join("Contents");
        std::fs::create_dir_all(&contents).unwrap();
        std::fs::write(
            contents.join("Info.plist"),
            format!(
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\
                 <plist version=\"1.0\"><dict>\
                 <key>CFBundlePackageType</key><string>APPL</string>\
                 {icon_fields}</dict></plist>"
            ),
        )
        .unwrap();
        let bundle = NSBundle::bundleWithPath(&NSString::from_str(bundle_path.to_str().unwrap()))
            .expect("fixture is a readable bundle");
        assert_eq!(bundle_declares_application_icon(&bundle), expected, "{name}");
    }

    std::fs::remove_dir_all(root).unwrap();
}
