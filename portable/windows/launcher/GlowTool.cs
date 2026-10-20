// Build once as a console EXE; copy to bin/{python,python3,jupytext,latex2text,codex,codex-acp}.exe.
// csc /target:exe /platform:x64 /r:System.Runtime.Serialization.dll /out:GlowTool.exe GlowTool.cs
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;

internal static class GlowTool
{
    [DataContract]
    private sealed class ToolCommand
    {
        [DataMember(Name = "runtime")] public string Runtime { get; set; }
        [DataMember(Name = "script")] public string Script { get; set; }
    }

    private static string Quote(string value)
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
            throw new InvalidDataException("Invalid packaged tool path.");
        string full = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Packaged tool paths must remain inside the application directory.");
        if (!File.Exists(full)) throw new FileNotFoundException("A packaged tool file is missing: " + full);
        return full;
    }

    private static int Main(string[] args)
    {
        try
        {
            string binary = Process.GetCurrentProcess().MainModule.FileName;
            string name = Path.GetFileNameWithoutExtension(binary).ToLowerInvariant();
            string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
            List<string> arguments = new List<string>();
            string executable;
            if (name == "python" || name == "python3")
                executable = ChildPath(root, "runtime/python/python.exe");
            else if (name == "jupytext" || name == "latex2text")
            {
                executable = ChildPath(root, "runtime/python/python.exe");
                arguments.Add(ChildPath(root, "runtime/tool.py"));
                arguments.Add("--entry");
                arguments.Add(name);
            }
            else if (name == "codex" || name == "codex-acp")
            {
                string metadata = ChildPath(root, "runtime/tool-commands.json");
                Dictionary<string, ToolCommand> commands;
                DataContractJsonSerializerSettings settings = new DataContractJsonSerializerSettings();
                settings.UseSimpleDictionaryFormat = true;
                using (FileStream stream = File.OpenRead(metadata))
                    commands = new DataContractJsonSerializer(typeof(Dictionary<string, ToolCommand>), settings).ReadObject(stream) as Dictionary<string, ToolCommand>;
                ToolCommand command;
                if (commands == null || !commands.TryGetValue(name, out command) || command == null || command.Runtime != "node")
                    throw new InvalidDataException("This package does not declare a valid " + name + " entry point.");
                executable = ChildPath(root, "runtime/node/node.exe");
                arguments.Add(ChildPath(root, command.Script));
            }
            else throw new InvalidOperationException("This helper must be run through a packaged tool entry point.");
            arguments.AddRange(args);
            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = executable;
            start.UseShellExecute = false;
            start.WorkingDirectory = Directory.GetCurrentDirectory();
            start.Arguments = String.Join(" ", arguments.ConvertAll<string>(Quote).ToArray());
            start.EnvironmentVariables["NEOVIDE_GLOW_ROOT"] = root;
            start.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
            start.EnvironmentVariables["PYTHONUTF8"] = "1";
            start.EnvironmentVariables.Remove("PYTHONHOME");
            start.EnvironmentVariables.Remove("PYTHONPATH");
            // No redirection: preserve the calling terminal's input/output handles.
            using (Process process = Process.Start(start))
            {
                if (process == null) throw new InvalidOperationException("The packaged tool could not be started.");
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("Neovide Glow: " + error.Message);
            return 1;
        }
    }
}
