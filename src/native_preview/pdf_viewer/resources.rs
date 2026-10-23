// Bundled PDF.js 6.4.299 and local viewer resources. Exact names only.
// Update alongside vendor/pdfjs/manifest.json; no filesystem lookup occurs.
pub fn resource(path: &str) -> Option<(&'static [u8], &'static str)> {
    Some(match path {
        "README.md" => (include_bytes!("README.md"), "text/markdown"),
        "protocol.mjs" => (include_bytes!("protocol.mjs"), "text/javascript; charset=utf-8"),
        "vendor/pdfjs/LICENSE" => {
            (include_bytes!("vendor/pdfjs/LICENSE"), "application/octet-stream")
        }
        "vendor/pdfjs/build/pdf.mjs" => {
            (include_bytes!("vendor/pdfjs/build/pdf.mjs"), "text/javascript; charset=utf-8")
        }
        "vendor/pdfjs/build/pdf.worker.mjs" => {
            (include_bytes!("vendor/pdfjs/build/pdf.worker.mjs"), "text/javascript; charset=utf-8")
        }
        "vendor/pdfjs/cmaps/78-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/78-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/78-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/78-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/78-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/78-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/78-RKSJ-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/78-RKSJ-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/78-RKSJ-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/78-RKSJ-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/78-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/78-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/78ms-RKSJ-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/78ms-RKSJ-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/78ms-RKSJ-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/78ms-RKSJ-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/83pv-RKSJ-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/83pv-RKSJ-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/90ms-RKSJ-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/90ms-RKSJ-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/90ms-RKSJ-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/90ms-RKSJ-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/90msp-RKSJ-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/90msp-RKSJ-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/90msp-RKSJ-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/90msp-RKSJ-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/90pv-RKSJ-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/90pv-RKSJ-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/90pv-RKSJ-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/90pv-RKSJ-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Add-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Add-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Add-RKSJ-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Add-RKSJ-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Add-RKSJ-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Add-RKSJ-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Add-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Add-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-CNS1-0.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-CNS1-0.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-CNS1-1.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-CNS1-1.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-CNS1-2.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-CNS1-2.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-CNS1-3.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-CNS1-3.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-CNS1-4.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-CNS1-4.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-CNS1-5.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-CNS1-5.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-CNS1-6.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-CNS1-6.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-CNS1-UCS2.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-CNS1-UCS2.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-GB1-0.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-GB1-0.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-GB1-1.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-GB1-1.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-GB1-2.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-GB1-2.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-GB1-3.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-GB1-3.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-GB1-4.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-GB1-4.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-GB1-5.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-GB1-5.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-GB1-UCS2.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-GB1-UCS2.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Japan1-0.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Japan1-0.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Japan1-1.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Japan1-1.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Japan1-2.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Japan1-2.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Japan1-3.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Japan1-3.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Japan1-4.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Japan1-4.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Japan1-5.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Japan1-5.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Japan1-6.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Japan1-6.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Japan1-UCS2.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/Adobe-Japan1-UCS2.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/Adobe-Korea1-0.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Korea1-0.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Korea1-1.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Korea1-1.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Korea1-2.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Adobe-Korea1-2.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Adobe-Korea1-UCS2.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/Adobe-Korea1-UCS2.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/B5pc-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/B5pc-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/B5pc-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/B5pc-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/CNS-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/CNS-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/CNS-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/CNS-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/CNS1-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/CNS1-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/CNS1-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/CNS1-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/CNS2-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/CNS2-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/CNS2-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/CNS2-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/ETHK-B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/ETHK-B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/ETHK-B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/ETHK-B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/ETen-B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/ETen-B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/ETen-B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/ETen-B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/ETenms-B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/ETenms-B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/ETenms-B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/ETenms-B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Ext-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Ext-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Ext-RKSJ-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Ext-RKSJ-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Ext-RKSJ-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Ext-RKSJ-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Ext-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Ext-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GB-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GB-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GB-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GB-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GB-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GB-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GB-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GB-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBK-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBK-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBK-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBK-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBK2K-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBK2K-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBK2K-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBK2K-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBKp-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBKp-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBKp-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBKp-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBT-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBT-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBT-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBT-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBT-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBT-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBT-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBT-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBTpc-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBTpc-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBTpc-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBTpc-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBpc-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBpc-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/GBpc-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/GBpc-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKdla-B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKdla-B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKdla-B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKdla-B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKdlb-B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKdlb-B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKdlb-B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKdlb-B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKgccs-B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKgccs-B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKgccs-B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKgccs-B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKm314-B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKm314-B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKm314-B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKm314-B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKm471-B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKm471-B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKm471-B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKm471-B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKscs-B5-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKscs-B5-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/HKscs-B5-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/HKscs-B5-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Hankaku.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Hankaku.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Hiragana.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Hiragana.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSC-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSC-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSC-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSC-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSC-Johab-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSC-Johab-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSC-Johab-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSC-Johab-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSCms-UHC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSCms-UHC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSCms-UHC-HW-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSCms-UHC-HW-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSCms-UHC-HW-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSCms-UHC-HW-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSCms-UHC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSCms-UHC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSCpc-EUC-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSCpc-EUC-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/KSCpc-EUC-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/KSCpc-EUC-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Katakana.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Katakana.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/LICENSE" => {
            (include_bytes!("vendor/pdfjs/cmaps/LICENSE"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/NWP-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/NWP-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/NWP-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/NWP-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/RKSJ-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/RKSJ-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/RKSJ-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/RKSJ-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/Roman.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/Roman.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniCNS-UCS2-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniCNS-UCS2-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniCNS-UCS2-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniCNS-UCS2-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniCNS-UTF16-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniCNS-UTF16-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniCNS-UTF16-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniCNS-UTF16-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniCNS-UTF32-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniCNS-UTF32-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniCNS-UTF32-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniCNS-UTF32-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniCNS-UTF8-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniCNS-UTF8-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniCNS-UTF8-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniCNS-UTF8-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniGB-UCS2-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniGB-UCS2-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniGB-UCS2-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniGB-UCS2-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniGB-UTF16-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniGB-UTF16-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniGB-UTF16-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniGB-UTF16-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniGB-UTF32-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniGB-UTF32-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniGB-UTF32-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniGB-UTF32-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniGB-UTF8-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniGB-UTF8-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniGB-UTF8-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniGB-UTF8-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniJIS-UCS2-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniJIS-UCS2-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniJIS-UCS2-HW-H.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJIS-UCS2-HW-H.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJIS-UCS2-HW-V.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJIS-UCS2-HW-V.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJIS-UCS2-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniJIS-UCS2-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniJIS-UTF16-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniJIS-UTF16-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniJIS-UTF16-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniJIS-UTF16-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniJIS-UTF32-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniJIS-UTF32-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniJIS-UTF32-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniJIS-UTF32-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniJIS-UTF8-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniJIS-UTF8-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniJIS-UTF8-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniJIS-UTF8-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniJIS2004-UTF16-H.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJIS2004-UTF16-H.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJIS2004-UTF16-V.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJIS2004-UTF16-V.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJIS2004-UTF32-H.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJIS2004-UTF32-H.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJIS2004-UTF32-V.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJIS2004-UTF32-V.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJIS2004-UTF8-H.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJIS2004-UTF8-H.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJIS2004-UTF8-V.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJIS2004-UTF8-V.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJISPro-UCS2-HW-V.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJISPro-UCS2-HW-V.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJISPro-UCS2-V.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJISPro-UCS2-V.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJISPro-UTF8-V.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJISPro-UTF8-V.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJISX0213-UTF32-H.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJISX0213-UTF32-H.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJISX0213-UTF32-V.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJISX0213-UTF32-V.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJISX02132004-UTF32-H.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJISX02132004-UTF32-H.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniJISX02132004-UTF32-V.bcmap" => (
            include_bytes!("vendor/pdfjs/cmaps/UniJISX02132004-UTF32-V.bcmap"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/cmaps/UniKS-UCS2-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniKS-UCS2-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniKS-UCS2-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniKS-UCS2-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniKS-UTF16-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniKS-UTF16-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniKS-UTF16-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniKS-UTF16-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniKS-UTF32-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniKS-UTF32-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniKS-UTF32-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniKS-UTF32-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniKS-UTF8-H.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniKS-UTF8-H.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/UniKS-UTF8-V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/UniKS-UTF8-V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/V.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/V.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/cmaps/WP-Symbol.bcmap" => {
            (include_bytes!("vendor/pdfjs/cmaps/WP-Symbol.bcmap"), "application/octet-stream")
        }
        "vendor/pdfjs/manifest.json" => {
            (include_bytes!("vendor/pdfjs/manifest.json"), "application/json")
        }
        "vendor/pdfjs/package.json" => {
            (include_bytes!("vendor/pdfjs/package.json"), "application/json")
        }
        "vendor/pdfjs/standard_fonts/FoxitDingbats.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitDingbats.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/FoxitFixed.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitFixed.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/FoxitFixedBold.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitFixedBold.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/FoxitFixedBoldItalic.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitFixedBoldItalic.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/FoxitFixedItalic.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitFixedItalic.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/FoxitSerif.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitSerif.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/FoxitSerifBold.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitSerifBold.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/FoxitSerifBoldItalic.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitSerifBoldItalic.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/FoxitSerifItalic.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitSerifItalic.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/FoxitSymbol.pfb" => (
            include_bytes!("vendor/pdfjs/standard_fonts/FoxitSymbol.pfb"),
            "application/x-font-type1",
        ),
        "vendor/pdfjs/standard_fonts/LICENSE_FOXIT" => (
            include_bytes!("vendor/pdfjs/standard_fonts/LICENSE_FOXIT"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/standard_fonts/LICENSE_LIBERATION" => (
            include_bytes!("vendor/pdfjs/standard_fonts/LICENSE_LIBERATION"),
            "application/octet-stream",
        ),
        "vendor/pdfjs/standard_fonts/LiberationSans-Bold.ttf" => {
            (include_bytes!("vendor/pdfjs/standard_fonts/LiberationSans-Bold.ttf"), "font/ttf")
        }
        "vendor/pdfjs/standard_fonts/LiberationSans-BoldItalic.ttf" => (
            include_bytes!("vendor/pdfjs/standard_fonts/LiberationSans-BoldItalic.ttf"),
            "font/ttf",
        ),
        "vendor/pdfjs/standard_fonts/LiberationSans-Italic.ttf" => {
            (include_bytes!("vendor/pdfjs/standard_fonts/LiberationSans-Italic.ttf"), "font/ttf")
        }
        "vendor/pdfjs/standard_fonts/LiberationSans-Regular.ttf" => {
            (include_bytes!("vendor/pdfjs/standard_fonts/LiberationSans-Regular.ttf"), "font/ttf")
        }
        "vendor/pdfjs/wasm/LICENSE_JBIG2" => {
            (include_bytes!("vendor/pdfjs/wasm/LICENSE_JBIG2"), "application/octet-stream")
        }
        "vendor/pdfjs/wasm/LICENSE_OPENJPEG" => {
            (include_bytes!("vendor/pdfjs/wasm/LICENSE_OPENJPEG"), "application/octet-stream")
        }
        "vendor/pdfjs/wasm/LICENSE_PDFJS_JBIG2" => {
            (include_bytes!("vendor/pdfjs/wasm/LICENSE_PDFJS_JBIG2"), "application/octet-stream")
        }
        "vendor/pdfjs/wasm/LICENSE_PDFJS_OPENJPEG" => {
            (include_bytes!("vendor/pdfjs/wasm/LICENSE_PDFJS_OPENJPEG"), "application/octet-stream")
        }
        "vendor/pdfjs/wasm/LICENSE_PDFJS_QCMS" => {
            (include_bytes!("vendor/pdfjs/wasm/LICENSE_PDFJS_QCMS"), "application/octet-stream")
        }
        "vendor/pdfjs/wasm/LICENSE_QCMS" => {
            (include_bytes!("vendor/pdfjs/wasm/LICENSE_QCMS"), "application/octet-stream")
        }
        "vendor/pdfjs/wasm/jbig2.wasm" => {
            (include_bytes!("vendor/pdfjs/wasm/jbig2.wasm"), "application/wasm")
        }
        "vendor/pdfjs/wasm/jbig2_nowasm_fallback.js" => {
            (include_bytes!("vendor/pdfjs/wasm/jbig2_nowasm_fallback.js"), "text/javascript")
        }
        "vendor/pdfjs/wasm/openjpeg.wasm" => {
            (include_bytes!("vendor/pdfjs/wasm/openjpeg.wasm"), "application/wasm")
        }
        "vendor/pdfjs/wasm/openjpeg_nowasm_fallback.js" => {
            (include_bytes!("vendor/pdfjs/wasm/openjpeg_nowasm_fallback.js"), "text/javascript")
        }
        "vendor/pdfjs/wasm/qcms_bg.wasm" => {
            (include_bytes!("vendor/pdfjs/wasm/qcms_bg.wasm"), "application/wasm")
        }
        "vendor/pdfjs/wasm/quickjs-eval.js" => {
            (include_bytes!("vendor/pdfjs/wasm/quickjs-eval.js"), "text/javascript")
        }
        "vendor/pdfjs/wasm/quickjs-eval.wasm" => {
            (include_bytes!("vendor/pdfjs/wasm/quickjs-eval.wasm"), "application/wasm")
        }
        "vendor/pdfjs/web/images/altText_add.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/altText_add.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/altText_disclaimer.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/altText_disclaimer.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/altText_done.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/altText_done.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/altText_spinner.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/altText_spinner.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/altText_warning.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/altText_warning.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-check.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-check.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-comment.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-comment.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-help.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-help.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-insert.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-insert.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-key.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-key.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-newparagraph.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-newparagraph.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-noicon.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-noicon.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-note.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-note.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-paperclip.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-paperclip.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-paragraph.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-paragraph.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/annotation-pushpin.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/annotation-pushpin.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/checkmark.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/checkmark.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/comment-actionsButton.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/comment-actionsButton.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/comment-closeButton.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/comment-closeButton.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/comment-editButton.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/comment-editButton.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/comment-popup-editButton.svg" => (
            include_bytes!("vendor/pdfjs/web/images/comment-popup-editButton.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/cursor-editorFreeHighlight.svg" => (
            include_bytes!("vendor/pdfjs/web/images/cursor-editorFreeHighlight.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/cursor-editorFreeText.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/cursor-editorFreeText.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/cursor-editorInk.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/cursor-editorInk.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/cursor-editorTextHighlight.svg" => (
            include_bytes!("vendor/pdfjs/web/images/cursor-editorTextHighlight.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/editor-toolbar-delete.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/editor-toolbar-delete.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/editor-toolbar-edit.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/editor-toolbar-edit.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/findbarButton-next.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/findbarButton-next.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/findbarButton-previous.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/findbarButton-previous.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/gv-toolbarButton-download.svg" => (
            include_bytes!("vendor/pdfjs/web/images/gv-toolbarButton-download.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/loading-icon.gif" => {
            (include_bytes!("vendor/pdfjs/web/images/loading-icon.gif"), "image/gif")
        }
        "vendor/pdfjs/web/images/loading.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/loading.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/messageBar_closingButton.svg" => (
            include_bytes!("vendor/pdfjs/web/images/messageBar_closingButton.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/messageBar_info.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/messageBar_info.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/messageBar_warning.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/messageBar_warning.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/pages_closeButton.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/pages_closeButton.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/pages_selected.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/pages_selected.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/pages_viewArrow.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/pages_viewArrow.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/pages_viewButton.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/pages_viewButton.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/secondaryToolbarButton-documentProperties.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-documentProperties.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-firstPage.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-firstPage.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-handTool.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-handTool.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-lastPage.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-lastPage.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-rotateCcw.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-rotateCcw.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-rotateCw.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-rotateCw.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-scrollHorizontal.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-scrollHorizontal.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-scrollPage.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-scrollPage.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-scrollVertical.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-scrollVertical.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-scrollWrapped.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-scrollWrapped.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-selectTool.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-selectTool.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-spreadEven.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-spreadEven.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-spreadNone.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-spreadNone.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/secondaryToolbarButton-spreadOdd.svg" => (
            include_bytes!("vendor/pdfjs/web/images/secondaryToolbarButton-spreadOdd.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/signature-properties-row-check.svg" => (
            include_bytes!("vendor/pdfjs/web/images/signature-properties-row-check.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-bookmark.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-bookmark.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-currentOutlineItem.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-currentOutlineItem.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-download.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-download.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-editorFreeText.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-editorFreeText.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-editorHighlight.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-editorHighlight.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-editorInk.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-editorInk.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-editorSignature.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-editorSignature.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-editorStamp.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-editorStamp.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-menuArrow.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-menuArrow.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-menuArrowNova.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-menuArrowNova.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-openFile.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-openFile.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-pageDown.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-pageDown.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-pageUp.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-pageUp.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-presentationMode.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-presentationMode.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-print.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-print.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-search.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-search.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-secondaryToolbarToggle.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-secondaryToolbarToggle.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-signaturePropertiesError.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-signaturePropertiesError.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-signaturePropertiesVerified.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-signaturePropertiesVerified.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-viewAttachments.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-viewAttachments.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-viewLayers.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-viewLayers.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-viewOutline.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-viewOutline.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-viewThumbnail.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-viewThumbnail.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-viewsManagerToggle.svg" => (
            include_bytes!("vendor/pdfjs/web/images/toolbarButton-viewsManagerToggle.svg"),
            "image/svg+xml",
        ),
        "vendor/pdfjs/web/images/toolbarButton-zoomIn.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-zoomIn.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/toolbarButton-zoomOut.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/toolbarButton-zoomOut.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/treeitem-collapsed.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/treeitem-collapsed.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/images/treeitem-expanded.svg" => {
            (include_bytes!("vendor/pdfjs/web/images/treeitem-expanded.svg"), "image/svg+xml")
        }
        "vendor/pdfjs/web/pdf_viewer.css" => {
            (include_bytes!("vendor/pdfjs/web/pdf_viewer.css"), "text/css; charset=utf-8")
        }
        "vendor/pdfjs/web/pdf_viewer.mjs" => {
            (include_bytes!("vendor/pdfjs/web/pdf_viewer.mjs"), "text/javascript; charset=utf-8")
        }
        "viewer.css" => (include_bytes!("viewer.css"), "text/css; charset=utf-8"),
        "viewer.html" => (include_bytes!("viewer.html"), "text/html; charset=utf-8"),
        "viewer.mjs" => (include_bytes!("viewer.mjs"), "text/javascript; charset=utf-8"),
        _ => return None,
    })
}
