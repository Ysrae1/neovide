// csc /nologo /target:exe /platform:x64 /main:WindowsLauncherCore
// /r:System.Windows.Forms.dll /r:System.Runtime.Serialization.dll
// /out:WindowsLauncherCore.exe portable/windows/launcher/GlowLauncher.cs tests/windows_launcher_core.cs
// Synthetic package validation only; no launch, user profile, registry or downloads.
using System;
using System.IO;
using System.Reflection;

internal static class WindowsLauncherCore
{
    private static void Write(string root, string relative, string value)
    {
        string path = Path.Combine(root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllText(path, value);
    }
    private static void Validate(string root)
    {
        object[] arguments = new object[] { root, null };
        try { typeof(GlowLauncher).GetMethod("ValidateBundle", BindingFlags.NonPublic | BindingFlags.Static).Invoke(null, arguments); }
        catch (TargetInvocationException error) { throw error.InnerException; }
    }
    private static string Metadata(string distribution)
    {
        return "{\"schema_version\":1,\"stack_id\":\"core-test\",\"native_required\":[\"native.dll\"],\"distribution\":\"" + distribution + "\",\"tool_paths\":[]}";
    }
    private static int Main()
    {
        // Match the GUI entry point before the first fixture filesystem call:
        // .NET caches its path handling switches on first IO initialization.
        System.Runtime.CompilerServices.RuntimeHelpers.RunClassConstructor(typeof(GlowLauncher).TypeHandle);
        string root = Path.Combine(Path.GetTempPath(), "glow-core-test-" + Guid.NewGuid().ToString("N"));
        try
        {
            foreach (string path in new string[] { "bin/neovide.exe", "bin/nvim.exe", "share/nvim/runtime/filetype.lua", "config/neovide.toml",
                "runtime/lua/WindowsInit.lua", "profile/config/nvim/init.lua", "profile/config/nvim/lazy-lock.json",
                "profile/data/nvim/lazy/plugin/plugin.lua", "native.dll", "dependencies/Setup-Wizard.ps1", "dependencies/Setup-Locale.ps1", "dependencies/Setup-Dependencies.ps1",
                "dependencies/WebView2.ps1", "dependencies/dependencies.json", "dependencies/Dependency-Helpers.ps1", "dependencies/system-assets.lock.json", "dependencies/Setup-LaTeX.ps1" }) Write(root, path, "fixture");
            Write(root, "bundle.json", Metadata("core"));
            Validate(root);
            Console.WriteLine("PASS core accepts missing optional Python, Node, Java and tool runtimes");
            Write(root, "bundle.json", Metadata("offline"));
            bool rejected = false;
            try { Validate(root); } catch (FileNotFoundException) { rejected = true; }
            if (!rejected) throw new Exception("Offline validation incorrectly relaxed");
            Console.WriteLine("PASS offline still requires packaged runtimes");
            Write(root, "bundle.json", Metadata("unknown"));
            rejected = false;
            try { Validate(root); } catch (InvalidDataException) { rejected = true; }
            if (!rejected) throw new Exception("Unknown distribution accepted");
            Console.WriteLine("PASS unsupported distribution rejected");
            Write(root, "bundle.json", Metadata("core"));
            File.Delete(Path.Combine(root, "dependencies", "Setup-Wizard.ps1"));
            rejected = false;
            try { Validate(root); } catch (FileNotFoundException error) { rejected = error.Message.Contains("Setup-Wizard.ps1"); }
            if (!rejected) throw new Exception("Core validation accepted a missing setup GUI");
            Console.WriteLine("PASS core requires its setup GUI before launcher-check succeeds");
            Write(root, "dependencies/Setup-Wizard.ps1", "fixture");
            File.Delete(Path.Combine(root, "native.dll"));
            rejected = false;
            try { Validate(root); } catch (FileNotFoundException) { rejected = true; }
            if (!rejected) throw new Exception("Missing native component accepted");
            Console.WriteLine("PASS core retains native component completeness checks");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}
