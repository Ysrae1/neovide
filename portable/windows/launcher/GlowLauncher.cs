// Built on the Windows release worker, never compiled on an end user's machine.
// csc /target:winexe /platform:x64 /r:System.Windows.Forms.dll
//     /r:System.Runtime.Serialization.dll /out:Glow.exe GlowLauncher.cs
using System;
using System.Collections.Generic;
using System.Diagnostics;
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
            throw new FileNotFoundException("This installation is incomplete. Please reinstall the complete Neovide Glow package. Missing file: " + path);
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
            foreach (string relative in new string[] { "dependencies/Setup-Dependencies.ps1", "dependencies/WebView2.ps1", "dependencies/dependencies.json", "dependencies/Dependency-Helpers.ps1", "dependencies/system-assets.lock.json", "dependencies/Setup-LaTeX.ps1" })
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
        if (String.IsNullOrWhiteSpace(local)) throw new InvalidOperationException("The Windows user data directory is unavailable.");
        string root = FullLogicalPath(Path.Combine(local, "NeovideGlow", "profiles", stack));
        string installation = FullLogicalPath(installRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if ((root + Path.DirectorySeparatorChar).StartsWith(installation, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("The writable profile cannot be inside the application installation.");
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
                if (!acquired) throw new InvalidOperationException("Another Neovide Glow window is preparing this profile. Please try again shortly.");
                string marker = Path.Combine(profile, ".glow-profile.json");
                if (Directory.Exists(FileSystemPath(profile)))
                {
                    if (!File.Exists(FileSystemPath(marker)))
                        throw new InvalidOperationException("An existing unrecognized profile was preserved: " + profile);
                    ProfileMetadata current = ReadObject<ProfileMetadata>(marker);
                    if (current.SchemaVersion != 1 || !String.Equals(current.StackId, stack, StringComparison.Ordinal))
                        throw new InvalidDataException("The existing profile belongs to a different release and was preserved.");
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
            BundleMetadata bundle;
            string stack = ValidateBundle(root, out bundle);
            if (args.Length == 1 && args[0] == "--launcher-check") return 0;
            string profile = ProfileRoot(root, stack);
            PrepareProfile(root, profile, stack);
            if (args.Length == 1 && args[0] == "--initialize-profile") return 0;
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
            start.EnvironmentVariables["XDG_CONFIG_HOME"] = Path.Combine(profile, "config");
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
                if (process == null) throw new InvalidOperationException("Neovide could not be started.");
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            if (headless)
            {
                try { Console.Error.WriteLine("Neovide Glow: " + error.Message); }
                catch (IOException) { }
            }
            else MessageBox.Show(error.Message, "Neovide Glow", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
