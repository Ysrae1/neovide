// Native Windows .NET Framework 4.8 regression for launcher profile IO.
// csc /nologo /target:exe /platform:x64 /main:WindowsLauncherPaths
//   /r:System.Windows.Forms.dll /r:System.Runtime.Serialization.dll
//   /out:WindowsLauncherPaths.exe portable/windows/launcher/GlowLauncher.cs tests/windows_launcher_paths.cs
// WindowsLauncherPaths.exe [fresh-test-parent]
// No registry changes, real profile access, downloads, GUI or external shares.
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

internal static class WindowsLauncherPaths
{
    private static int passed;
    private static string root;
    private static readonly Type Launcher = typeof(GlowLauncher);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.U1)]
    private static extern bool CreateSymbolicLinkW(string link, string target, int flags);

    private static object Call(string name, params object[] args)
    {
        try { return Launcher.GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, args); }
        catch (TargetInvocationException error) { throw error.InnerException; }
    }
    private static string FS(string path) { return (string)Call("FileSystemPath", path); }
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
    private static void Pass(string name) { passed++; Console.WriteLine("PASS " + name); }
    private static void Write(string path, string content)
    {
        Directory.CreateDirectory(FS(Path.GetDirectoryName(path)));
        File.WriteAllText(FS(path), content);
    }
    private static string Deep(string parent)
    {
        while (parent.Length < 310) parent = Path.Combine(parent, "directory-" + new string('d', 40));
        return parent;
    }
    private static void Prepare(string package, string profile)
    {
        Call("PrepareProfile", package, profile, "glow-path-regression");
    }
    private static string Package(string name)
    {
        string package = Path.Combine(root, name);
        Write(Path.Combine(package, "profile", "config", "nvim", "init.lua"), "-- static config");
        Write(Path.Combine(package, "profile", "data", "nvim", "lazy", "fixture", "payload.txt"), "immutable payload");
        return package;
    }
    private static void Rejected(string package, string profile, string expected)
    {
        bool rejected = false;
        try { Prepare(package, profile); }
        catch (InvalidDataException error)
        {
            rejected = error.Message.Contains(expected);
            Check(!error.Message.Contains(@"\\?\"), "Guard diagnostic leaked an IO-only prefix");
        }
        Check(rejected, "Expected guarded package rejection: " + expected);
        Check(!Directory.Exists(FS(profile)), "Rejected copy exposed a partial final profile");
        string parent = Path.GetDirectoryName(profile);
        if (Directory.Exists(FS(parent)))
            Check(Directory.GetDirectories(FS(parent), Path.GetFileName(profile) + ".preparing-*").Length == 0,
                "Rejected copy left its long atomic staging directory");
    }
    private static void TestLinks(string parent)
    {
        foreach (bool directory in new bool[] { false, true })
        {
            string name = directory ? "directory-link" : "file-link";
            string package = Package(name);
            string target = Path.Combine(root, name + "-target");
            string link = Path.Combine(package, "profile", "data", "nvim", name);
            if (directory) Directory.CreateDirectory(FS(target)); else Write(target, "owned link target");
            int flags = directory ? 1 : 0;
            bool created = CreateSymbolicLinkW(FS(link), FS(target), flags | 2);
            if (!created) created = CreateSymbolicLinkW(FS(link), FS(target), flags);
            if (!created) { Console.WriteLine("SKIP " + name + " creation unavailable; Win32=" + Marshal.GetLastWin32Error()); continue; }
            Rejected(package, Path.Combine(parent, name), "Links are not permitted");
            Check(directory ? Directory.Exists(FS(target)) : File.ReadAllText(FS(target)) == "owned link target",
                "Reparse rejection changed its target");
            Pass(name + " rejected without following target");
        }
    }
    private static int Main(string[] args)
    {
        try
        {
            // Match the launcher's entry point: set its application-local IO
            // switches before this test makes its own first System.IO call.
            System.Runtime.CompilerServices.RuntimeHelpers.RunClassConstructor(Launcher.TypeHandle);
            Check(Environment.OSVersion.Platform == PlatformID.Win32NT, "Run on native Windows or a Windows API compatibility test environment");
            string parent = args.Length == 0 ? Path.GetTempPath() : Path.GetFullPath(args[0]);
            root = Path.Combine(parent, "glow-launcher-paths-" + Guid.NewGuid().ToString("N"));
            Check(!Directory.Exists(FS(root)), "Test root must not already exist");
            Directory.CreateDirectory(FS(root));
            Check(FS(@"C:\Glow 中文\a") == @"\\?\C:\Glow 中文\a", "Drive path conversion failed");
            Check(FS(@"\\server\share\Glow 中文\a") == @"\\?\UNC\server\share\Glow 中文\a", "UNC conversion failed");
            Check(FS(@"\\?\C:\Glow\a") == @"\\?\C:\Glow\a", "Extended path idempotence failed");
            Check((string)Call("LogicalPath", @"\\?\UNC\server\share\a") == @"\\server\share\a", "Logical UNC restoration failed");
            Check((string)Call("LogicalPath", @"\\?\C:\Glow\a") == @"C:\Glow\a", "Logical drive restoration failed");
            bool escaped = false;
            try { Call("ChildPath", root, "../outside"); } catch (InvalidDataException) { escaped = true; }
            Check(escaped, "Dot traversal bypassed the package boundary guard");
            Pass("drive/UNC prefixes remain IO-only; traversal rejected");

            string package = Package("good");
            string codex = Path.Combine("codex-acp", "node_modules", "@openai", "codex-win32-x64", "vendor",
                "x86_64-pc-windows-msvc", "codex-resources", "codex-windows-sandbox-setup.exe");
            Write(Path.Combine(package, "profile", "data", "nvim", codex), "owned executable-name fixture, never executed");
            string sourceFile = Path.Combine(package, "profile", "data", "nvim", "lazy", "fixture", "payload.txt");
            File.SetAttributes(FS(sourceFile), FileAttributes.ReadOnly);
            string longParent = Deep(Path.Combine(root, "profiles"));
            string profile = Path.Combine(longParent, "glow-path-regression");
            Check(profile.Length > 260 && (profile + ".preparing-" + new string('a', 32)).Length > 300, "Fixture is not long enough");
            Prepare(package, profile);
            File.SetAttributes(FS(sourceFile), FileAttributes.Normal);
            string targetFile = Path.Combine(profile, "data", "nvim-data", "lazy", "fixture", "payload.txt");
            Check(File.ReadAllText(FS(targetFile)) == "immutable payload", "Long copy changed bytes");
            Check((File.GetAttributes(FS(targetFile)) & FileAttributes.ReadOnly) == 0, "Copied data stayed read-only");
            Check(File.Exists(FS(Path.Combine(profile, "data", "nvim-data", codex))), "Deep Codex resource was not copied");
            string marker = Path.Combine(profile, ".glow-profile.json");
            Check(!File.ReadAllText(FS(marker)).Contains(@"\\?\"), "Marker contains an IO-only path prefix");
            Write(Path.Combine(profile, "config", "nvim", "init.lua"), "user edit must survive");
            Prepare(package, profile);
            Check(File.ReadAllText(FS(Path.Combine(profile, "config", "nvim", "init.lua"))) == "user edit must survive", "Existing valid profile was overwritten");
            Type metadataType = Launcher.GetNestedType("BundleMetadata", BindingFlags.NonPublic);
            object metadata = Activator.CreateInstance(metadataType, true);
            metadataType.GetProperty("ToolPaths").SetValue(metadata, new string[0], null);
            Check(!((string)Call("ToolPath", package, metadata, profile)).Contains(@"\\?\"), "Child PATH contains an IO-only prefix");
            Pass("final/staging paths exceed 260; copy/rename/marker/writable/reuse/PATH passed");

            foreach (string forbidden in new string[] { "AUTH.JSON", "credentials.json", ".env" })
            {
                string bad = Package("bad-file-" + passed);
                Write(Path.Combine(bad, "profile", "data", "nvim", "lazy", "fixture", forbidden), "public test fixture only");
                Rejected(bad, Path.Combine(longParent, "reject-" + passed), "Credential-like files");
                Pass("credential guard and long staging rollback: " + forbidden);
            }
            foreach (string forbidden in new string[] { ".git", ".codex" })
            {
                string bad = Package("bad-directory-" + passed);
                Directory.CreateDirectory(FS(Path.Combine(bad, "profile", "data", "nvim", forbidden)));
                Rejected(bad, Path.Combine(longParent, "reject-" + passed), "Private or source-control state");
                Pass("private directory guard and rollback: " + forbidden);
            }
            string existing = Path.Combine(longParent, "unrecognized");
            Write(Path.Combine(existing, "keep.txt"), "untouched");
            bool preserved = false;
            try { Prepare(package, existing); } catch (InvalidOperationException) { preserved = true; }
            Check(preserved && File.ReadAllText(FS(Path.Combine(existing, "keep.txt"))) == "untouched", "Unknown profile was not preserved");
            string mismatched = Path.Combine(longParent, "mismatched");
            Write(Path.Combine(mismatched, ".glow-profile.json"), "{\"schema_version\":1,\"stack_id\":\"another-release\"}");
            preserved = false;
            try { Prepare(package, mismatched); } catch (InvalidDataException) { preserved = true; }
            Check(preserved && File.ReadAllText(FS(Path.Combine(mismatched, ".glow-profile.json"))).Contains("another-release"), "Mismatched profile changed");
            Pass("unknown and mismatched existing profiles preserved");

            string collisionSource = Path.Combine(root, "copy-source");
            string collisionTarget = Path.Combine(longParent, "copy-target");
            Write(Path.Combine(collisionSource, "same.txt"), "source");
            Write(Path.Combine(collisionTarget, "same.txt"), "existing destination");
            bool collision = false;
            try { Call("CopyTree", collisionSource, collisionTarget, root); } catch (IOException) { collision = true; }
            Check(collision && File.ReadAllText(FS(Path.Combine(collisionTarget, "same.txt"))) == "existing destination", "Copy overwrote an existing file");
            Pass("copy refuses overwrite");
            TestLinks(longParent);
            Console.WriteLine("Launcher path regression passed: " + passed + " cases; no global settings changed");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error.ToString()); return 1; }
        finally
        {
            if (root != null && Directory.Exists(FS(root)))
            {
                foreach (string file in Directory.GetFiles(FS(root), "*", SearchOption.AllDirectories))
                    File.SetAttributes(file, File.GetAttributes(file) & ~FileAttributes.ReadOnly);
                Directory.Delete(FS(root), true);
            }
        }
    }
}
