// .NET Framework 4.8 regression for the actual launcher's child-only graphics policy.
// csc /nologo /target:exe /platform:x64 /main:WindowsLauncherGraphics
//   /r:System.Windows.Forms.dll /r:System.Runtime.Serialization.dll
//   /out:WindowsLauncherGraphics.exe portable/windows/launcher/GlowLauncher.cs tests/windows_launcher_graphics.cs
// No process launch, real BIOS/registry read, GUI or parent environment mutation.
using System;
using System.Diagnostics;

internal static class WindowsLauncherGraphics
{
    private static int passed;
    private static readonly string ParentOpenGL = Environment.GetEnvironmentVariable("NEOVIDE_OPENGL");
    private static readonly string ParentSentinel = Environment.GetEnvironmentVariable("GLOW_GRAPHICS_TEST_SENTINEL");
    private const string Arguments = "--geometry=100x30 -- C:\\fixture\\file's name.txt";

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    private static ProcessStartInfo Child()
    {
        ProcessStartInfo child = new ProcessStartInfo();
        child.UseShellExecute = false;
        child.Arguments = Arguments;
        child.EnvironmentVariables.Remove("NEOVIDE_OPENGL");
        child.EnvironmentVariables["GLOW_GRAPHICS_TEST_SENTINEL"] = "child-only";
        return child;
    }

    private static void Preserved(ProcessStartInfo child)
    {
        Check(child.Arguments == Arguments, "Graphics selection changed launch arguments");
        Check(child.EnvironmentVariables["GLOW_GRAPHICS_TEST_SENTINEL"] == "child-only",
            "Graphics selection changed an unrelated child variable");
        Check(Environment.GetEnvironmentVariable("NEOVIDE_OPENGL") == ParentOpenGL,
            "Graphics selection changed the parent process environment");
        Check(Environment.GetEnvironmentVariable("GLOW_GRAPHICS_TEST_SENTINEL") == ParentSentinel,
            "Child environment setup changed the parent sentinel");
    }

    private static void Pass(string name)
    {
        passed++;
        Console.WriteLine("PASS " + name);
    }

    private static void Identity(string name, string manufacturer, string product, bool expectedOpenGL)
    {
        ProcessStartInfo child = Child();
        int reads = 0;
        GlowLauncher.ApplyGraphicsDefault(child, delegate {
            reads++;
            return new string[] { manufacturer, product };
        });
        Check(reads == 1, "The injected BIOS reader was not called exactly once");
        Check(child.EnvironmentVariables.ContainsKey("NEOVIDE_OPENGL") == expectedOpenGL,
            "Unexpected default selection for " + name);
        if (expectedOpenGL) Check(child.EnvironmentVariables["NEOVIDE_OPENGL"] == "1", "Wrong OpenGL default value");
        Preserved(child);
        Pass(name);
    }

    private static void ExplicitValue(string name, string key, string value)
    {
        ProcessStartInfo child = Child();
        child.EnvironmentVariables[key] = value;
        int reads = 0;
        GlowLauncher.ApplyGraphicsDefault(child, delegate {
            reads++;
            return new string[] { "Parallels International GmbH", "Parallels ARM Virtual Machine" };
        });
        Check(reads == 0, "BIOS was inspected despite an explicit user value");
        Check(child.EnvironmentVariables.ContainsKey("NEOVIDE_OPENGL") &&
            child.EnvironmentVariables["NEOVIDE_OPENGL"] == value, "Explicit OpenGL value was overwritten");
        Preserved(child);
        Pass(name);
    }

    private static int Main()
    {
        try
        {
            Identity("Parallels manufacturer and ARM product", "Parallels International GmbH", "Parallels ARM Virtual Machine", true);
            Identity("Parallels platform match is case insensitive", "PARALLELS SOFTWARE INTERNATIONAL INC.", "parallels virtual platform", true);
            Identity("ordinary Windows hardware keeps default", "Dell Inc.", "Precision 3680", false);
            Identity("manufacturer alone does not select OpenGL", "Parallels International GmbH", "Virtual Machine", false);
            Identity("product alone does not select OpenGL", "Other Manufacturer", "Parallels ARM Virtual Machine", false);
            Identity("missing manufacturer keeps default", null, "Parallels ARM Virtual Machine", false);
            Identity("empty product keeps default", "Parallels International GmbH", " ", false);
            Identity("partial vendor token does not count as Parallels", "NotParallels", "Parallels ARM Virtual Machine", false);
            ExplicitValue("explicit true is preserved", "NEOVIDE_OPENGL", "true");
            ExplicitValue("explicit false is preserved", "NEOVIDE_OPENGL", "false");
            ExplicitValue("explicit empty is preserved", "NEOVIDE_OPENGL", "");
            ExplicitValue("Windows environment keys are case insensitive", "neovide_opengl", "false");

            ProcessStartInfo missing = Child();
            GlowLauncher.ApplyGraphicsDefault(missing, delegate { return null; });
            Check(!missing.EnvironmentVariables.ContainsKey("NEOVIDE_OPENGL"), "Missing BIOS data changed the default");
            Preserved(missing);
            Pass("unavailable BIOS keeps default");

            ProcessStartInfo denied = Child();
            GlowLauncher.ApplyGraphicsDefault(denied, delegate { throw new UnauthorizedAccessException("fixture"); });
            Check(!denied.EnvironmentVariables.ContainsKey("NEOVIDE_OPENGL"), "BIOS exception changed the default");
            Preserved(denied);
            Pass("BIOS read exception keeps default");

            Console.WriteLine("Windows launcher graphics passed: " + passed + " cases; parent environment and arguments preserved");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("FAIL " + error.Message);
            return 1;
        }
    }
}
