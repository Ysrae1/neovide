// Built on the Windows release worker, never compiled on an end user's machine.
// csc /target:winexe /platform:x64 /r:System.Windows.Forms.dll
//     /r:System.Runtime.Serialization.dll /out:Glow.exe GlowLauncher.cs
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class GlowLauncher
{
    private static string uiLanguage = "en";

    private static string Ui(string english, string chinese)
    {
        return uiLanguage == "zh-CN" ? chinese : english;
    }

    // This optional installer choice affects launcher/setup text only. Reading
    // it never changes the user's editor configuration or Windows preferences.
    private static string ReadUiLanguage(string root, CultureInfo culture)
    {
        try
        {
            string path = FileSystemPath(Path.Combine(root, "glow-ui-language.txt"));
            if (File.Exists(path))
            {
                string selected = File.ReadAllText(path, Encoding.UTF8).Trim().TrimStart('\uFEFF').Trim();
                if (String.Equals(selected, "en", StringComparison.OrdinalIgnoreCase)) return "en";
                if (String.Equals(selected, "zh-CN", StringComparison.OrdinalIgnoreCase)) return "zh-CN";
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return culture != null && culture.TwoLetterISOLanguageName == "zh" ? "zh-CN" : "en";
    }

    static GlowLauncher()
    {
        // Application-local .NET 4.8 behavior, never a machine-wide setting.
        AppContext.SetSwitch("Switch.System.IO.UseLegacyPathHandling", false);
        AppContext.SetSwitch("Switch.System.IO.BlockLongPaths", false);
    }

    // Only filesystem calls receive device paths. Explicit Unicode Win32 device
    // paths do not depend on the user's global LongPathsEnabled registry setting.
    private static string FileSystemPath(string path)
    {
        if (path.StartsWith(@"\\?\", StringComparison.Ordinal)) return path;
        if (path.StartsWith(@"\\.\", StringComparison.Ordinal))
            throw new InvalidDataException("Device namespace paths are not permitted.");
        if (!path.StartsWith(@"\\", StringComparison.Ordinal) &&
            (path.Length < 3 || !Char.IsLetter(path[0]) || path[1] != ':' || path[2] != '\\'))
            path = Path.GetFullPath(path);
        if (path.StartsWith(@"\\", StringComparison.Ordinal)) return @"\\?\UNC\" + path.Substring(2);
        return @"\\?\" + path;
    }

    private static string LogicalPath(string path)
    {
        if (path.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) return @"\\" + path.Substring(8);
        if (path.StartsWith(@"\\?\", StringComparison.Ordinal)) return path.Substring(4);
        return path;
    }

    private static string FullLogicalPath(string path)
    {
        // Normalize before adding a device prefix: extended paths deliberately
        // bypass dot-segment normalization, which ChildPath's escape guard needs.
        return Path.GetFullPath(LogicalPath(path));
    }

    [DataContract]
    private sealed class BundleMetadata
    {
        [DataMember(Name = "schema_version")] public int SchemaVersion { get; set; }
        [DataMember(Name = "stack_id")] public string StackId { get; set; }
        [DataMember(Name = "native_required")] public string[] NativeRequired { get; set; }
        [DataMember(Name = "tool_paths")] public string[] ToolPaths { get; set; }
        // Omitted by existing frozen offline bundles.
        [DataMember(Name = "distribution")] public string Distribution { get; set; }
    }

    [DataContract]
    private sealed class SystemDependencies
    {
        [DataMember(Name = "schema_version")] public int SchemaVersion { get; set; }
        [DataMember(Name = "python")] public string Python { get; set; }
        [DataMember(Name = "jupytext")] public string Jupytext { get; set; }
        [DataMember(Name = "latex2text")] public string Latex2text { get; set; }
        [DataMember(Name = "tool_paths")] public string[] ToolPaths { get; set; }
    }

    [DataContract]
    private sealed class ProfileMetadata
    {
        [DataMember(Name = "schema_version")] public int SchemaVersion { get; set; }
        [DataMember(Name = "stack_id")] public string StackId { get; set; }
    }

    [DataContract]
    private sealed class ConfigurationSelection
    {
        [DataMember(Name = "schema_version")] public int SchemaVersion { get; set; }
        [DataMember(Name = "stack_id")] public string StackId { get; set; }
        [DataMember(Name = "mode")] public string Mode { get; set; }
        [DataMember(Name = "external_config", EmitDefaultValue = false)] public string ExternalConfig { get; set; }
    }

    // Windows argv quoting: backslashes before quotes and at the end need doubling.
    internal static string Quote(string value)
    {
        StringBuilder output = new StringBuilder("\"");
        int slashes = 0;
        foreach (char character in value)
        {
            if (character == '\\') { slashes++; continue; }
            output.Append('\\', slashes * (character == '"' ? 2 : 1) + (character == '"' ? 1 : 0));
            output.Append(character);
            slashes = 0;
        }
        output.Append('\\', slashes * 2);
        return output.Append('"').ToString();
    }

    private static string ChildPath(string root, string relative)
    {
        if (String.IsNullOrWhiteSpace(relative) || Path.IsPathRooted(relative) || relative.IndexOf(':') >= 0)
            throw new InvalidDataException("The bundle contains an invalid relative path.");
        string full = FullLogicalPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        string prefix = FullLogicalPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("The bundle contains a path outside its installation directory.");
        return full;
    }

    private static T ReadObject<T>(string path) where T : class
    {
        using (FileStream stream = File.OpenRead(FileSystemPath(path)))
        {
            T result = new DataContractJsonSerializer(typeof(T)).ReadObject(stream) as T;
            if (result == null) throw new InvalidDataException("Invalid bundle metadata: " + Path.GetFileName(path));
            return result;
        }
    }

    private static void RequireFile(string path)
    {
        if (!File.Exists(FileSystemPath(path)))
            throw new FileNotFoundException(Ui("This installation is incomplete. Please reinstall the complete Neovide Glow package. Missing file: ",
                "安装文件不完整。请重新安装完整的 Neovide Glow 安装包。缺少文件：") + path);
    }

    private static string ValidateBundle(string root, out BundleMetadata bundle)
    {
        string metadata = ChildPath(root, "bundle.json");
        RequireFile(metadata);
        bundle = ReadObject<BundleMetadata>(metadata);
        if (bundle.SchemaVersion != 1 || String.IsNullOrEmpty(bundle.StackId) ||
            !Regex.IsMatch(bundle.StackId, @"\A[A-Za-z0-9][A-Za-z0-9._-]{0,100}\z"))
            throw new InvalidDataException("The bundle schema or stack identifier is invalid.");
        if (!String.IsNullOrEmpty(bundle.Distribution) && bundle.Distribution != "core" && bundle.Distribution != "offline")
            throw new InvalidDataException("The bundle distribution is unsupported.");
        string[] basic = {
            "bin/neovide.exe", "bin/nvim.exe", "share/nvim/runtime/filetype.lua", "config/neovide.toml",
            "runtime/lua/WindowsInit.lua",
            "profile/config/nvim/init.lua", "profile/config/nvim/lazy-lock.json"
        };
        foreach (string relative in basic) RequireFile(ChildPath(root, relative));
        if (!Directory.Exists(FileSystemPath(ChildPath(root, "profile/data/nvim/lazy"))))
            throw new InvalidDataException("This installation is missing its packaged plugins.");
        if (bundle.Distribution == "core")
        {
            foreach (string relative in new string[] { "dependencies/Setup-Wizard.ps1", "dependencies/Setup-Locale.ps1", "dependencies/Setup-Dependencies.ps1", "dependencies/WebView2.ps1", "dependencies/dependencies.json", "dependencies/Dependency-Helpers.ps1", "dependencies/system-assets.lock.json", "dependencies/Setup-LaTeX.ps1" })
                RequireFile(ChildPath(root, relative));
        }
        else
        {
            RequireFile(ChildPath(root, "runtime/python/python.exe"));
            RequireFile(ChildPath(root, "runtime/node/node.exe"));
            if (!Directory.Exists(FileSystemPath(ChildPath(root, "runtime/python/Lib/site-packages"))))
                throw new InvalidDataException("This offline installation is missing its packaged Python dependencies.");
        }
        if (bundle.NativeRequired == null || bundle.NativeRequired.Length == 0)
            throw new InvalidDataException("The bundle does not declare its prebuilt native components.");
        foreach (string entry in bundle.NativeRequired)
        {
            RequireFile(ChildPath(root, entry));
        }
        return bundle.StackId;
    }

    private static string DependencyReceipt()
    {
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "NeovideGlow", "dependencies", "selected.json");
    }

    private static bool ExistingExecutable(string path)
    {
        try
        {
            return !String.IsNullOrWhiteSpace(path) && Path.IsPathRooted(path) &&
                String.Equals(Path.GetFullPath(path), path, StringComparison.OrdinalIgnoreCase) &&
                String.Equals(Path.GetExtension(path), ".exe", StringComparison.OrdinalIgnoreCase) &&
                File.Exists(FileSystemPath(path));
        }
        catch (ArgumentException) { return false; }
        catch (NotSupportedException) { return false; }
        catch (PathTooLongException) { return false; }
    }

    private static void ApplyRuntime(ProcessStartInfo child, string root, BundleMetadata bundle)
    {
        if (bundle.Distribution != "core")
        {
            child.EnvironmentVariables["NEOVIDE_GLOW_DISTRIBUTION"] = "offline";
            child.EnvironmentVariables["GLOW_PYTHON"] = ChildPath(root, "runtime/python/python.exe");
            child.EnvironmentVariables["JAVA_HOME"] = ChildPath(root, "runtime/java");
            return;
        }
        child.EnvironmentVariables["NEOVIDE_GLOW_DISTRIBUTION"] = "core";
        child.EnvironmentVariables["NEOVIDE_GLOW_DEPENDENCY_SETUP"] = ChildPath(root, "dependencies/Setup-Dependencies.ps1");
        foreach (string variable in new string[] { "GLOW_PYTHON", "NEOVIDE_GLOW_PYTHON", "GLOW_JUPYTEXT", "GLOW_LATEX2TEXT" })
            child.EnvironmentVariables.Remove(variable);
        string receipt = DependencyReceipt();
        if (!File.Exists(FileSystemPath(receipt))) return;
        SystemDependencies selected;
        try { selected = ReadObject<SystemDependencies>(receipt); }
        catch (IOException) { return; }
        catch (UnauthorizedAccessException) { return; }
        catch (SerializationException) { return; }
        catch (InvalidDataException) { return; }
        if (selected.SchemaVersion != 1) return;
        // A stale/removed environment disables Notebook, not the editor itself.
        // Setup probes imports before registering; launch never installs packages.
        if (!ExistingExecutable(selected.Python) || !ExistingExecutable(selected.Jupytext)) return;
        child.EnvironmentVariables["GLOW_PYTHON"] = selected.Python;
        child.EnvironmentVariables["GLOW_JUPYTEXT"] = selected.Jupytext;
        if (ExistingExecutable(selected.Latex2text)) child.EnvironmentVariables["GLOW_LATEX2TEXT"] = selected.Latex2text;
    }

    private static string DependencySetupArguments(string script, string[] args)
    {
        bool notebook = false, latex = false;
        for (int i = 1; i < args.Length; i++)
        {
            if (args[i] == "--notebook" && !notebook) notebook = true;
            else if (args[i] == "--latex" && !latex) latex = true;
            else throw new ArgumentException(Ui("Unknown or repeated setup option: ", "未知或重复的设置选项：") + args[i] +
                Ui(". Use --setup [--notebook] [--latex].", "。请使用 --setup [--notebook] [--latex]。"));
        }
        return "-STA -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(script) +
            " -Language " + Quote(uiLanguage) +
            (notebook ? " -InstallNotebook" : "") + (latex ? " -InstallLatex" : "");
    }

    private static int RunDependencySetup(string root, BundleMetadata bundle, string[] args)
    {
        if (bundle.Distribution != "core")
            throw new InvalidOperationException(Ui("Dependency setup is available in the Core package. This offline package retains its bundled runtimes.",
                "依赖设置适用于 Core 安装包；当前离线安装包继续使用其自带的运行环境。"));
        string script = ChildPath(root, "dependencies/Setup-Wizard.ps1");
        string arguments = DependencySetupArguments(script, args);
        RequireFile(script);
        ProcessStartInfo start = new ProcessStartInfo();
        start.FileName = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        start.Arguments = arguments;
        start.WorkingDirectory = root;
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.RedirectStandardOutput = true;
        start.RedirectStandardError = true;
        // Read while the wizard runs, with a bounded diagnostic buffer. A GUI
        // setup entry never creates a transient console or waits on a full pipe.
        StringBuilder output = new StringBuilder();
        object outputLock = new object();
        DataReceivedEventHandler collect = delegate(object sender, DataReceivedEventArgs data) {
            if (data.Data == null) return;
            lock (outputLock)
            {
                int room = 8192 - output.Length;
                if (room > 0) output.Append((data.Data + Environment.NewLine).Substring(0, Math.Min(room, data.Data.Length + Environment.NewLine.Length)));
            }
        };
        using (Process process = new Process())
        {
            process.StartInfo = start;
            process.OutputDataReceived += collect;
            process.ErrorDataReceived += collect;
            if (!process.Start()) throw new InvalidOperationException(Ui("The dependency setup window could not be started. Run Glow.exe --setup again to retry.",
                "无法打开依赖设置窗口。请重新运行 Glow.exe --setup。"));
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            bool exited = process.WaitForExit(2 * 60 * 60 * 1000);
            if (!exited)
            {
                try { process.Kill(); } catch (InvalidOperationException) { }
                process.WaitForExit(5000);
            }
            // Do not wait indefinitely for inherited handles in a descendant.
            process.CancelOutputRead();
            process.CancelErrorRead();
            if (!exited) throw new InvalidOperationException(Ui("Dependency setup exceeded its two-hour limit. Existing environments and partial downloads were preserved. Run Glow.exe --setup again to continue.",
                "依赖设置超过两小时上限。已有环境和未完成的下载已保留，请重新运行 Glow.exe --setup 继续。"));
            if (process.ExitCode == 0 || process.ExitCode == 2) return process.ExitCode;
            string details;
            lock (outputLock) details = output.ToString().Trim();
            throw new InvalidOperationException(Ui("Dependency setup did not finish. Existing environments and partial downloads were preserved. Run Glow.exe --setup again to continue.",
                "依赖设置未完成。已有环境和未完成的下载已保留，请重新运行 Glow.exe --setup 继续。") +
                (details.Length == 0 ? "" : "\n\n" + details));
        }
    }

    private static string PackagedSourcePath(string root, string path)
    {
        string prefix = FullLogicalPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        string full = FullLogicalPath(path);
        return full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
            ? full.Substring(prefix.Length).Replace('\\', '/') : "<outside packaged profile>";
    }

    private static void CopyTree(string source, string destination, string packageRoot)
    {
        DirectoryInfo directory = new DirectoryInfo(FileSystemPath(source));
        if ((directory.Attributes & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException("Links are not permitted in the packaged profile: " + directory.Name);
        Directory.CreateDirectory(FileSystemPath(destination));
        foreach (FileInfo file in directory.GetFiles())
        {
            if ((file.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Links are not permitted in the packaged profile: " + file.Name);
            if (file.Name.Equals("auth.json", StringComparison.OrdinalIgnoreCase) ||
                file.Name.Equals("credentials.json", StringComparison.OrdinalIgnoreCase) ||
                file.Name.Equals(".env", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Credential-like files must not be present in the packaged profile: "
                    + PackagedSourcePath(packageRoot, Path.Combine(source, file.Name)));
            string target = Path.Combine(destination, file.Name);
            file.CopyTo(FileSystemPath(target), false);
            string targetFile = FileSystemPath(target);
            File.SetAttributes(targetFile, File.GetAttributes(targetFile) & ~FileAttributes.ReadOnly);
        }
        foreach (DirectoryInfo child in directory.GetDirectories())
        {
            if (child.Name.Equals(".git", StringComparison.OrdinalIgnoreCase) ||
                child.Name.Equals(".codex", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Private or source-control state must not be present in the packaged profile.");
            CopyTree(Path.Combine(source, child.Name), Path.Combine(destination, child.Name), packageRoot);
        }
    }

    private static string ProfileRoot(string installRoot, string stack)
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (String.IsNullOrWhiteSpace(local)) throw new InvalidOperationException(Ui("The Windows user data directory is unavailable.", "无法访问 Windows 用户数据目录。"));
        string root = FullLogicalPath(Path.Combine(local, "NeovideGlow", "profiles", stack));
        string installation = FullLogicalPath(installRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if ((root + Path.DirectorySeparatorChar).StartsWith(installation, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(Ui("The writable profile cannot be inside the application installation.", "可写的用户配置目录不能位于应用安装目录内。"));
        return root;
    }

    private static void PrepareProfile(string installRoot, string profile, string stack)
    {
        string mutexName;
        using (SHA256 hash = SHA256.Create())
            mutexName = "Local\\NeovideGlow-" + BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(profile.ToUpperInvariant()))).Replace("-", "");
        using (Mutex mutex = new Mutex(false, mutexName))
        {
            bool acquired = false;
            string staging = null;
            try
            {
                try { acquired = mutex.WaitOne(TimeSpan.FromSeconds(30)); }
                catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new InvalidOperationException(Ui("Another Neovide Glow window is preparing this profile. Please try again shortly.",
                    "另一个 Neovide Glow 窗口正在准备此配置，请稍后重试。"));
                string marker = Path.Combine(profile, ".glow-profile.json");
                if (Directory.Exists(FileSystemPath(profile)))
                {
                    if (!File.Exists(FileSystemPath(marker)))
                        throw new InvalidOperationException(Ui("An existing unrecognized profile was preserved: ", "已保留无法识别的现有配置目录：") + profile);
                    ProfileMetadata current = ReadObject<ProfileMetadata>(marker);
                    if (current.SchemaVersion != 1 || !String.Equals(current.StackId, stack, StringComparison.Ordinal))
                        throw new InvalidDataException(Ui("The existing profile belongs to a different release and was preserved.", "现有配置目录属于其他发行版本，已保留原样。"));
                    return;
                }
                string parent = LogicalPath(Path.GetDirectoryName(FileSystemPath(profile)));
                Directory.CreateDirectory(FileSystemPath(parent));
                staging = profile + ".preparing-" + Guid.NewGuid().ToString("N");
                Directory.CreateDirectory(FileSystemPath(staging));
                CopyTree(ChildPath(installRoot, "profile/config"), Path.Combine(staging, "config"), installRoot);
                CopyTree(ChildPath(installRoot, "profile/data"), Path.Combine(staging, "data"), installRoot);
                // Native Windows Nvim uses the nvim-data suffix for data/state/cache.
                // The shipped snapshot keeps the shared portable data/nvim layout.
                Directory.Move(FileSystemPath(Path.Combine(staging, "data", "nvim")), FileSystemPath(Path.Combine(staging, "data", "nvim-data")));
                Directory.CreateDirectory(FileSystemPath(Path.Combine(staging, "state")));
                Directory.CreateDirectory(FileSystemPath(Path.Combine(staging, "cache")));
                ProfileMetadata record = new ProfileMetadata();
                record.SchemaVersion = 1;
                record.StackId = stack;
                using (FileStream stream = File.Create(FileSystemPath(Path.Combine(staging, ".glow-profile.json"))))
                    new DataContractJsonSerializer(typeof(ProfileMetadata)).WriteObject(stream, record);
                Directory.Move(FileSystemPath(staging), FileSystemPath(profile));
                staging = null;
            }
            finally
            {
                if (staging != null && Directory.Exists(FileSystemPath(staging))) Directory.Delete(FileSystemPath(staging), true);
                if (acquired) mutex.ReleaseMutex();
            }
        }
    }

    // Reusing a configuration is explicit and read-only. A recognizable early
    // hook is required: starting arbitrary init.lua without it would omit the
    // selected runtime/provider setup. Do not rewrite the user's init.lua.
    private static bool CompatibleExternalConfiguration(string directory, out string reason)
    {
        reason = Ui("init.lua must begin with the Neovide Glow runtime hook.", "init.lua 需要先加载 Neovide Glow 运行时入口。");
        try
        {
            if (String.IsNullOrWhiteSpace(directory) || !Path.IsPathRooted(directory) ||
                !String.Equals(FullLogicalPath(directory), directory, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(Path.GetFileName(directory), "nvim", StringComparison.OrdinalIgnoreCase))
                return false;
            string init = Path.Combine(directory, "init.lua");
            if (!File.Exists(FileSystemPath(init))) { reason = Ui("init.lua is missing.", "缺少 init.lua。"); return false; }
            if (new FileInfo(FileSystemPath(init)).Length > 1024 * 1024) return false;
            using (StreamReader reader = new StreamReader(FileSystemPath(init), Encoding.UTF8, true))
            {
                string line;
                while ((line = reader.ReadLine()) != null)
                {
                    line = line.Trim();
                    if (line.Length == 0) continue;
                    // Long Lua comments need a parser. Conservatively decline
                    // them rather than mistaking a commented hook for code.
                    if (Regex.IsMatch(line, @"\A--\[=*\[")) return false;
                    if (line.StartsWith("--", StringComparison.Ordinal)) continue;
                    bool compatible = Regex.IsMatch(line,
                        @"\Aif\s+vim\.env\.NEOVIDE_GLOW_INIT\s+then\s+dofile\s*\(\s*vim\.env\.NEOVIDE_GLOW_INIT\s*\)\s*;?\s*end\s*;?\s*(?:--.*)?\z");
                    if (compatible) reason = null;
                    return compatible;
                }
            }
        }
        catch (IOException) { reason = Ui("init.lua could not be read.", "无法读取 init.lua。"); }
        catch (UnauthorizedAccessException) { reason = Ui("init.lua could not be read.", "无法读取 init.lua。"); }
        catch (ArgumentException) { reason = Ui("The configuration path is invalid.", "配置路径无效。"); }
        catch (NotSupportedException) { reason = Ui("The configuration path is unsupported.", "不支持此配置路径。"); }
        return false;
    }

    private static string ResolveConfiguration(string profile, string stack, string candidate,
        Func<string, DialogResult> chooseExisting, Action<string> announceDefault, string nextSteps)
    {
        string selectionPath = Path.Combine(profile, ".glow-config.json");
        string mutexName;
        using (SHA256 hash = SHA256.Create())
            mutexName = "Local\\NeovideGlow-Config-" + BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(profile.ToUpperInvariant()))).Replace("-", "");
        using (Mutex mutex = new Mutex(false, mutexName))
        {
            bool acquired = false;
            string staging = null;
            try
            {
                try { acquired = mutex.WaitOne(TimeSpan.FromSeconds(30)); }
                catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new InvalidOperationException(Ui("Another Glow window is choosing this profile's configuration. Please try again shortly.",
                    "另一个 Glow 窗口正在选择此版本的配置，请稍后重试。"));
                ConfigurationSelection selection;
                if (File.Exists(FileSystemPath(selectionPath)))
                    selection = ReadObject<ConfigurationSelection>(selectionPath);
                else
                {
                    string reason;
                    bool compatible = CompatibleExternalConfiguration(candidate, out reason);
                    DialogResult choice = compatible ? chooseExisting(candidate) : DialogResult.No;
                    if (choice == DialogResult.Cancel) throw new OperationCanceledException(Ui("Configuration selection was cancelled. Launch Glow again when ready; existing files were preserved.",
                        "已取消配置选择，现有文件已保留。准备好后请重新启动 Glow。"));
                    if (choice != DialogResult.Yes && choice != DialogResult.No)
                        throw new InvalidOperationException(Ui("No configuration was selected. Existing files were preserved.", "尚未选择配置，现有文件已保留。"));
                    selection = new ConfigurationSelection();
                    selection.SchemaVersion = 1;
                    selection.StackId = stack;
                    selection.Mode = choice == DialogResult.Yes ? "external" : "profile";
                    if (selection.Mode == "external") selection.ExternalConfig = candidate;
                    if (selection.Mode == "profile")
                        announceDefault(Ui("Glow will use its separate configuration:\n", "Glow 将使用独立配置：\n") + Path.Combine(profile, "config", "nvim") +
                            Ui("\n\nYour existing Windows configuration is preserved.", "\n\n现有 Windows 配置已保留。") +
                            (File.Exists(FileSystemPath(Path.Combine(candidate, "init.lua"))) && !compatible
                                ? Ui("\nThe existing init.lua could not be safely reused: ", "\n无法安全沿用现有 init.lua：") + reason : "") +
                            "\n\n" + nextSteps +
                            Ui("\nThis choice is saved for this release; it will not ask again.", "\n此选择已为本发行版本保存，之后启动不再询问。"));
                    staging = selectionPath + ".preparing-" + Guid.NewGuid().ToString("N");
                    using (FileStream stream = File.Create(FileSystemPath(staging)))
                        new DataContractJsonSerializer(typeof(ConfigurationSelection)).WriteObject(stream, selection);
                    File.Move(FileSystemPath(staging), FileSystemPath(selectionPath));
                    staging = null;
                }
                if (selection.SchemaVersion != 1 || !String.Equals(selection.StackId, stack, StringComparison.Ordinal) ||
                    (selection.Mode != "profile" && selection.Mode != "external") ||
                    (selection.Mode == "profile" && !String.IsNullOrEmpty(selection.ExternalConfig)))
                    throw new InvalidDataException(Ui("The saved Glow configuration selection is invalid and was preserved: ", "已保存的 Glow 配置选择无效，原记录已保留：") + selectionPath);
                if (selection.Mode == "profile") return Path.Combine(profile, "config", "nvim");
                string failure;
                if (!CompatibleExternalConfiguration(selection.ExternalConfig, out failure))
                    throw new InvalidOperationException(Ui("The selected Windows configuration cannot be used: ", "无法使用选定的 Windows 配置：") + selection.ExternalConfig +
                        "\n" + failure + Ui("\nRestore that configuration, or rename ", "\n请恢复该配置，或重命名 ") + selectionPath +
                        Ui(" to choose again. No configuration files were changed.", " 后重新选择。未修改任何配置文件。"));
                return selection.ExternalConfig;
            }
            finally
            {
                if (staging != null && File.Exists(FileSystemPath(staging))) File.Delete(FileSystemPath(staging));
                if (acquired) mutex.ReleaseMutex();
            }
        }
    }

    private static string ToolPath(string root, BundleMetadata bundle, string profile)
    {
        List<string> paths = new List<string>();
        paths.Add(ChildPath(root, "bin"));
        paths.Add(ChildPath(root, "runtime/node"));
        paths.Add(ChildPath(root, "runtime/python"));
        paths.Add(ChildPath(root, "runtime/python/Scripts"));
        paths.Add(Path.Combine(profile, "data", "nvim-data", "mason", "bin"));
        if (bundle.ToolPaths != null)
        {
            foreach (string entry in bundle.ToolPaths)
            {
                string selectedPath = ChildPath(root, entry);
                if (!Directory.Exists(FileSystemPath(selectedPath))) throw new DirectoryNotFoundException("A packaged tool directory is missing: " + selectedPath);
                paths.Add(selectedPath);
            }
        }
        else
        {
            string tools = ChildPath(root, "tools");
            if (Directory.Exists(FileSystemPath(tools)))
            {
                paths.Add(tools);
                string[] directories = Directory.GetDirectories(FileSystemPath(tools));
                Array.Sort(directories, StringComparer.OrdinalIgnoreCase);
                foreach (string directoryPath in directories)
                {
                    string directory = LogicalPath(directoryPath);
                    paths.Add(directory);
                    if (Directory.Exists(FileSystemPath(Path.Combine(directory, "bin")))) paths.Add(Path.Combine(directory, "bin"));
                }
            }
        }
        if (bundle.Distribution == "core" && File.Exists(FileSystemPath(DependencyReceipt())))
        {
            try
            {
                SystemDependencies selection = ReadObject<SystemDependencies>(DependencyReceipt());
                if (selection.SchemaVersion == 1 && selection.ToolPaths != null)
                    foreach (string path in selection.ToolPaths)
                        if (!String.IsNullOrWhiteSpace(path) && path.IndexOf(Path.PathSeparator) < 0 &&
                            Path.IsPathRooted(path) && String.Equals(Path.GetFullPath(path), path, StringComparison.OrdinalIgnoreCase) &&
                            Directory.Exists(FileSystemPath(path))) paths.Add(path);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            catch (SerializationException) { }
            catch (InvalidDataException) { }
            catch (ArgumentException) { }
            catch (NotSupportedException) { }
        }
        string inherited = Environment.GetEnvironmentVariable("PATH");
        if (bundle.Distribution == "core" && !String.IsNullOrEmpty(inherited))
        {
            // Git's regular Windows PATH exposes cmd/, not usr/bin/file.exe.
            // Resolve its MIME helper for this child only, retaining the ASCII
            // YAZI_FILE_ONE value required by Yazi's ANSI Lua environment API.
            foreach (string directory in inherited.Split(Path.PathSeparator))
            {
                try
                {
                    string gitDirectory = directory.Trim().Trim('"');
                    if (!Path.IsPathRooted(gitDirectory) || !File.Exists(Path.Combine(gitDirectory, "git.exe"))) continue;
                    string helper = Path.GetFullPath(Path.Combine(gitDirectory, "..", "usr", "bin"));
                    if (File.Exists(Path.Combine(helper, "file.exe"))) { paths.Add(helper); break; }
                }
                catch (ArgumentException) { }
                catch (NotSupportedException) { }
            }
        }
        if (!String.IsNullOrEmpty(inherited)) paths.Add(inherited);
        return String.Join(Path.PathSeparator.ToString(), paths.ToArray());
    }

    private static string[] ReadSystemBios()
    {
        using (RegistryKey machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
        using (RegistryKey bios = machine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\BIOS", false))
        {
            if (bios == null) return null;
            return new string[] {
                bios.GetValue("SystemManufacturer", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string,
                bios.GetValue("SystemProductName", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string
            };
        }
    }

    // Only this child's default changes. Existing values, including false or an
    // empty value, remain authoritative; neither arguments nor parent env change.
    // Supplying the BIOS reader keeps the real selection path directly testable
    // without accessing hardware, starting a process or modifying the registry.
    internal static void ApplyGraphicsDefault(ProcessStartInfo child, Func<string[]> readBios)
    {
        if (child.EnvironmentVariables.ContainsKey("NEOVIDE_OPENGL")) return;
        try
        {
            string[] identity = readBios();
            if (identity == null || identity.Length != 2) return;
            foreach (string field in identity)
            {
                if (String.IsNullOrWhiteSpace(field) || !Regex.IsMatch(field, @"\bParallels\b",
                    RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) return;
            }
            child.EnvironmentVariables["NEOVIDE_OPENGL"] = "1";
        }
        catch (Exception)
        {
            // Unavailable or unreadable BIOS information keeps the normal default.
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        bool headless = args.Length == 1 && (args[0] == "--launcher-check" || args[0] == "--initialize-profile");
        try
        {
            string root = FullLogicalPath(AppDomain.CurrentDomain.BaseDirectory);
            uiLanguage = ReadUiLanguage(root, CultureInfo.CurrentUICulture);
            BundleMetadata bundle;
            string stack = ValidateBundle(root, out bundle);
            if (args.Length == 1 && args[0] == "--launcher-check") return 0;
            if (args.Length > 0 && args[0] == "--setup") return RunDependencySetup(root, bundle, args);
            string profile = ProfileRoot(root, stack);
            PrepareProfile(root, profile, stack);
            if (args.Length == 1 && args[0] == "--initialize-profile") return 0;
            string candidate = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config", "nvim");
            string configuration = ResolveConfiguration(profile, stack, candidate,
                delegate(string existing) {
                    return MessageBox.Show(Ui("An existing Windows Glow configuration is available:\n", "发现现有 Windows Glow 配置：\n") + existing +
                        Ui("\n\nYes: use it, preserving its files, themes and settings.", "\n\n是：沿用此配置，保留其中的文件、主题和设置。") +
                        Ui("\nNo: use this release's separate default configuration.", "\n否：使用本发行版本的独立默认配置。") +
                        Ui("\nCancel: choose later.", "\n取消：稍后再选择。") +
                        Ui("\n\nPlugins, runtime data and caches stay in this release's separate profile. This choice is saved for future launches.",
                            "\n\n插件、运行数据和缓存存放于本发行版本的独立目录。此选择将为以后启动保存。"),
                        Ui("Neovide Glow — choose configuration", "Neovide Glow — 选择配置"), MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
                },
                delegate(string message) { MessageBox.Show(message, Ui("Neovide Glow — first start", "Neovide Glow — 首次启动"), MessageBoxButtons.OK, MessageBoxIcon.Information); },
                bundle.Distribution == "core"
                    ? Ui("Next: open a file to begin. Open the Glow Setup shortcut to review optional features.",
                        "下一步：打开文件即可开始使用。可通过 Glow Setup 快捷方式查看和设置可选功能。")
                    : Ui("Next: open a file to begin. Packaged editing and Notebook dependencies are ready; AI sign-in and a full TeX distribution are separate.",
                        "下一步：打开文件即可开始使用。安装包已包含编辑和 Notebook 依赖；AI 登录及完整 TeX 发行版需要另行设置。"));
            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = ChildPath(root, "bin/neovide.exe");
            start.UseShellExecute = false;
            start.WorkingDirectory = Directory.GetCurrentDirectory();
            if ((start.WorkingDirectory.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar).StartsWith(root, StringComparison.OrdinalIgnoreCase))
                start.WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            List<string> arguments = new List<string>();
            arguments.Add("--neovim-bin");
            arguments.Add(ChildPath(root, "bin/nvim.exe"));
            string icon = ChildPath(root, "neovide.ico");
            if (File.Exists(FileSystemPath(icon))) { arguments.Add("--icon"); arguments.Add(icon); }
            arguments.AddRange(args);
            List<string> quoted = arguments.ConvertAll<string>(Quote);
            start.Arguments = String.Join(" ", quoted.ToArray());
            start.EnvironmentVariables["NEOVIDE_CONFIG"] = ChildPath(root, "config/neovide.toml");
            start.EnvironmentVariables["NEOVIDE_GLOW_ROOT"] = root;
            start.EnvironmentVariables["NEOVIDE_GLOW_INIT"] = ChildPath(root, "runtime/lua/WindowsInit.lua");
            ApplyRuntime(start, root, bundle);
            // Yazi's Lua os.getenv uses the Windows ANSI CRT. Keep this value
            // ASCII; its Rust command launcher resolves our Unicode PATH.
            start.EnvironmentVariables["YAZI_FILE_ONE"] = "file.exe";
            start.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
            start.EnvironmentVariables["PYTHONUTF8"] = "1";
            start.EnvironmentVariables.Remove("PYTHONHOME");
            start.EnvironmentVariables.Remove("PYTHONPATH");
            start.EnvironmentVariables.Remove("VIM");
            start.EnvironmentVariables.Remove("VIMRUNTIME");
            start.EnvironmentVariables["NVIM_APPNAME"] = "nvim";
            start.EnvironmentVariables["XDG_CONFIG_HOME"] = Path.GetDirectoryName(configuration);
            start.EnvironmentVariables["XDG_DATA_HOME"] = Path.Combine(profile, "data");
            start.EnvironmentVariables["XDG_STATE_HOME"] = Path.Combine(profile, "state");
            start.EnvironmentVariables["XDG_CACHE_HOME"] = Path.Combine(profile, "cache");
            start.EnvironmentVariables["JUPYTER_DATA_DIR"] = Path.Combine(profile, "data", "jupyter");
            start.EnvironmentVariables["JUPYTER_CONFIG_DIR"] = Path.Combine(profile, "config", "jupyter");
            start.EnvironmentVariables["JUPYTER_RUNTIME_DIR"] = Path.Combine(profile, "state", "jupyter");
            start.EnvironmentVariables["MPLCONFIGDIR"] = Path.Combine(profile, "cache", "matplotlib");
            start.EnvironmentVariables["PATH"] = ToolPath(root, bundle, profile);
            ApplyGraphicsDefault(start, ReadSystemBios);
            using (Process process = Process.Start(start))
            {
                if (process == null) throw new InvalidOperationException(Ui("Neovide could not be started.", "无法启动 Neovide。"));
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (OperationCanceledException) { return 0; }
        catch (Exception error)
        {
            if (headless)
            {
                try { Console.Error.WriteLine("Neovide Glow: " + error.Message); }
                catch (IOException) { }
            }
            else MessageBox.Show(Ui("Neovide Glow could not complete this operation.\n\n", "Neovide Glow 未能完成此操作。\n\n") + error.Message,
                Ui("Neovide Glow — error", "Neovide Glow — 错误"), MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
