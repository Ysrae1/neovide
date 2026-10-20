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

internal static class GlowLauncher
{
    [DataContract]
    private sealed class BundleMetadata
    {
        [DataMember(Name = "schema_version")] public int SchemaVersion { get; set; }
        [DataMember(Name = "stack_id")] public string StackId { get; set; }
        [DataMember(Name = "native_required")] public string[] NativeRequired { get; set; }
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
        string full = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("The bundle contains a path outside its installation directory.");
        return full;
    }

    private static T ReadObject<T>(string path) where T : class
    {
        using (FileStream stream = File.OpenRead(path))
        {
            T result = new DataContractJsonSerializer(typeof(T)).ReadObject(stream) as T;
            if (result == null) throw new InvalidDataException("Invalid bundle metadata: " + Path.GetFileName(path));
            return result;
        }
    }

    private static void RequireFile(string path)
    {
        if (!File.Exists(path))
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
        string[] basic = {
            "bin/neovide.exe", "bin/nvim.exe", "share/nvim/runtime/filetype.lua", "config/neovide.toml",
            "runtime/python/python.exe", "runtime/node/node.exe", "runtime/lua/WindowsInit.lua",
            "profile/config/nvim/init.lua", "profile/config/nvim/lazy-lock.json"
        };
        foreach (string relative in basic) RequireFile(ChildPath(root, relative));
        if (!Directory.Exists(ChildPath(root, "profile/data/nvim/lazy")) ||
            !Directory.Exists(ChildPath(root, "runtime/python/Lib/site-packages")))
            throw new InvalidDataException("This installation is missing its packaged plugins or Python dependencies.");
        if (bundle.NativeRequired == null || bundle.NativeRequired.Length == 0)
            throw new InvalidDataException("The bundle does not declare its prebuilt native components.");
        foreach (string entry in bundle.NativeRequired)
        {
            RequireFile(ChildPath(root, entry));
        }
        return bundle.StackId;
    }

    private static string PackagedSourcePath(string root, string path)
    {
        string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        string full = Path.GetFullPath(path);
        return full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
            ? full.Substring(prefix.Length).Replace('\\', '/') : "<outside packaged profile>";
    }

    private static void CopyTree(string source, string destination, string packageRoot)
    {
        DirectoryInfo directory = new DirectoryInfo(source);
        if ((directory.Attributes & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException("Links are not permitted in the packaged profile: " + directory.Name);
        Directory.CreateDirectory(destination);
        foreach (FileInfo file in directory.GetFiles())
        {
            if ((file.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Links are not permitted in the packaged profile: " + file.Name);
            if (file.Name.Equals("auth.json", StringComparison.OrdinalIgnoreCase) ||
                file.Name.Equals("credentials.json", StringComparison.OrdinalIgnoreCase) ||
                file.Name.Equals(".env", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Credential-like files must not be present in the packaged profile: "
                    + PackagedSourcePath(packageRoot, file.FullName));
            string target = Path.Combine(destination, file.Name);
            file.CopyTo(target, false);
            File.SetAttributes(target, File.GetAttributes(target) & ~FileAttributes.ReadOnly);
        }
        foreach (DirectoryInfo child in directory.GetDirectories())
        {
            if (child.Name.Equals(".git", StringComparison.OrdinalIgnoreCase) ||
                child.Name.Equals(".codex", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Private or source-control state must not be present in the packaged profile.");
            CopyTree(child.FullName, Path.Combine(destination, child.Name), packageRoot);
        }
    }

    private static string ProfileRoot(string installRoot, string stack)
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (String.IsNullOrWhiteSpace(local)) throw new InvalidOperationException("The Windows user data directory is unavailable.");
        string root = Path.GetFullPath(Path.Combine(local, "NeovideGlow", "profiles", stack));
        string installation = Path.GetFullPath(installRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
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
                if (Directory.Exists(profile))
                {
                    if (!File.Exists(marker))
                        throw new InvalidOperationException("An existing unrecognized profile was preserved: " + profile);
                    ProfileMetadata current = ReadObject<ProfileMetadata>(marker);
                    if (current.SchemaVersion != 1 || !String.Equals(current.StackId, stack, StringComparison.Ordinal))
                        throw new InvalidDataException("The existing profile belongs to a different release and was preserved.");
                    return;
                }
                string parent = Path.GetDirectoryName(profile);
                Directory.CreateDirectory(parent);
                staging = profile + ".preparing-" + Guid.NewGuid().ToString("N");
                Directory.CreateDirectory(staging);
                CopyTree(ChildPath(installRoot, "profile/config"), Path.Combine(staging, "config"), installRoot);
                CopyTree(ChildPath(installRoot, "profile/data"), Path.Combine(staging, "data"), installRoot);
                // Native Windows Nvim uses the nvim-data suffix for data/state/cache.
                // The shipped snapshot keeps the shared portable data/nvim layout.
                Directory.Move(Path.Combine(staging, "data", "nvim"), Path.Combine(staging, "data", "nvim-data"));
                Directory.CreateDirectory(Path.Combine(staging, "state"));
                Directory.CreateDirectory(Path.Combine(staging, "cache"));
                ProfileMetadata record = new ProfileMetadata();
                record.SchemaVersion = 1;
                record.StackId = stack;
                using (FileStream stream = File.Create(Path.Combine(staging, ".glow-profile.json")))
                    new DataContractJsonSerializer(typeof(ProfileMetadata)).WriteObject(stream, record);
                Directory.Move(staging, profile);
                staging = null;
            }
            finally
            {
                if (staging != null && Directory.Exists(staging)) Directory.Delete(staging, true);
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
                if (!Directory.Exists(selectedPath)) throw new DirectoryNotFoundException("A packaged tool directory is missing: " + selectedPath);
                paths.Add(selectedPath);
            }
        }
        else
        {
            string tools = ChildPath(root, "tools");
            if (Directory.Exists(tools))
            {
                paths.Add(tools);
                string[] directories = Directory.GetDirectories(tools);
                Array.Sort(directories, StringComparer.OrdinalIgnoreCase);
                foreach (string directory in directories)
                {
                    paths.Add(directory);
                    if (Directory.Exists(Path.Combine(directory, "bin"))) paths.Add(Path.Combine(directory, "bin"));
                }
            }
        }
        string inherited = Environment.GetEnvironmentVariable("PATH");
        if (!String.IsNullOrEmpty(inherited)) paths.Add(inherited);
        return String.Join(Path.PathSeparator.ToString(), paths.ToArray());
    }

    [STAThread]
    private static int Main(string[] args)
    {
        bool headless = args.Length == 1 && (args[0] == "--launcher-check" || args[0] == "--initialize-profile");
        try
        {
            string root = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
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
            if (File.Exists(icon)) { arguments.Add("--icon"); arguments.Add(icon); }
            arguments.AddRange(args);
            List<string> quoted = arguments.ConvertAll<string>(Quote);
            start.Arguments = String.Join(" ", quoted.ToArray());
            start.EnvironmentVariables["NEOVIDE_CONFIG"] = ChildPath(root, "config/neovide.toml");
            start.EnvironmentVariables["NEOVIDE_GLOW_ROOT"] = root;
            start.EnvironmentVariables["NEOVIDE_GLOW_INIT"] = ChildPath(root, "runtime/lua/WindowsInit.lua");
            start.EnvironmentVariables["GLOW_PYTHON"] = ChildPath(root, "runtime/python/python.exe");
            start.EnvironmentVariables["JAVA_HOME"] = ChildPath(root, "runtime/java");
            start.EnvironmentVariables["YAZI_FILE_ONE"] = ChildPath(root, "tools/git/usr/bin/file.exe");
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
