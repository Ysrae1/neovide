// Native Windows fixture: no real user configuration, registry, GUI or downloads.
// csc /nologo /codepage:65001 /target:exe /platform:x64 /main:WindowsLauncherConfig
// /r:System.Windows.Forms.dll /r:System.Runtime.Serialization.dll
// /out:WindowsLauncherConfig.exe portable/windows/launcher/GlowLauncher.cs tests/windows_launcher_config.cs
using System;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

internal static class WindowsLauncherConfig
{
    private const string Hook = "if vim.env.NEOVIDE_GLOW_INIT then dofile(vim.env.NEOVIDE_GLOW_INIT) end\r\n";
    private const string Stack = "glow-config-fixture";
    private static string root;
    private static int passed;
    private static object Call(string method, params object[] args)
    {
        try { return typeof(GlowLauncher).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Static).Invoke(null, args); }
        catch (TargetInvocationException error) { throw error.InnerException; }
    }
    private static string FS(string path) { return (string)Call("FileSystemPath", path); }
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
    private static void Pass(string message) { passed++; Console.WriteLine("PASS " + message); }
    private static void UseLanguage(string language)
    {
        typeof(GlowLauncher).GetField("uiLanguage", BindingFlags.NonPublic | BindingFlags.Static).SetValue(null, language);
    }
    private static void Write(string path, string value)
    {
        Directory.CreateDirectory(FS(Path.GetDirectoryName(path)));
        File.WriteAllText(FS(path), value, new UTF8Encoding(false));
    }
    private static string External(string name, string init)
    {
        string directory = Path.Combine(root, name, ".config", "nvim");
        Write(Path.Combine(directory, "init.lua"), init);
        return directory;
    }
    private static string Profile(string name)
    {
        string profile = Path.Combine(root, "profiles", name);
        Directory.CreateDirectory(FS(profile));
        return profile;
    }
    private static string Selection(string profile) { return Path.Combine(profile, ".glow-config.json"); }
    private static string Resolve(string profile, string candidate, Func<string, DialogResult> choose, Action<string> announce)
    {
        return (string)Call("ResolveConfiguration", profile, Stack, candidate, choose, announce, "Fixture next step.");
    }
    private static bool Compatible(string candidate)
    {
        object[] arguments = { candidate, null };
        return (bool)Call("CompatibleExternalConfiguration", arguments);
    }
    private static void RejectSaved(string profile, string candidate, Type exception)
    {
        bool rejected = false;
        try { Resolve(profile, candidate, delegate { throw new Exception("Saved choices must not prompt"); }, delegate { throw new Exception("Saved choices must not announce"); }); }
        catch (Exception error) { rejected = exception.IsInstanceOfType(error); }
        Check(rejected, "Invalid saved choice was silently replaced");
    }
    private static int Main()
    {
        CultureInfo originalCulture = System.Threading.Thread.CurrentThread.CurrentUICulture;
        try
        {
            System.Threading.Thread.CurrentThread.CurrentUICulture = CultureInfo.GetCultureInfo("en-US");
            System.Runtime.CompilerServices.RuntimeHelpers.RunClassConstructor(typeof(GlowLauncher).TypeHandle);
            root = Path.Combine(Path.GetTempPath(), "glow-config-中文 O'Brien-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(FS(root));
            CultureInfo english = CultureInfo.GetCultureInfo("en-US");
            CultureInfo chinese = CultureInfo.GetCultureInfo("zh-CN");
            string languageFile = Path.Combine(root, "glow-ui-language.txt");
            Check((string)Call("ReadUiLanguage", root, english) == "en" &&
                (string)Call("ReadUiLanguage", root, chinese) == "zh-CN" &&
                (string)Call("ReadUiLanguage", root, CultureInfo.GetCultureInfo("zh-TW")) == "zh-CN" &&
                (string)Call("ReadUiLanguage", root, CultureInfo.GetCultureInfo("fr-FR")) == "en", "Missing installer language did not use UI culture fallback");
            Check(!File.Exists(FS(languageFile)), "Reading fallback persisted a language preference");
            Write(languageFile, " \r\n en \t");
            Check((string)Call("ReadUiLanguage", root, chinese) == "en", "Installer English did not override Chinese Windows");
            File.WriteAllText(FS(languageFile), "\r\n zh-CN \t", new UTF8Encoding(true));
            byte[] languageBytes = File.ReadAllBytes(FS(languageFile));
            Check((string)Call("ReadUiLanguage", root, english) == "zh-CN", "BOM/whitespace installer Chinese did not override English Windows");
            Check(Convert.ToBase64String(languageBytes) == Convert.ToBase64String(File.ReadAllBytes(FS(languageFile))), "Language selection file changed during read");
            foreach (string unsupported in new string[] { "", "fr", "zh", "en\" -Command Write-Host unsafe" })
            {
                Write(languageFile, unsupported);
                Check((string)Call("ReadUiLanguage", root, english) == "en" && (string)Call("ReadUiLanguage", root, chinese) == "zh-CN",
                    "Unknown/empty/injected installer language bypassed culture fallback");
            }
            File.Delete(FS(languageFile));
            UseLanguage((string)Call("ReadUiLanguage", root, CultureInfo.CurrentUICulture));
            Pass("installer language overrides UI culture, tolerates BOM/whitespace, and reads without writes");
            string existing = External("existing", Hook + "-- independent Windows settings\r\n");
            string init = Path.Combine(existing, "init.lua");
            string theme = Path.Combine(existing, "lua", "config", "appearance", "themes", "ayu_light_customed.lua");
            Write(theme, "return { user_color = '#92929B' }\r\n");
            byte[] initialInit = File.ReadAllBytes(FS(init));
            byte[] initialTheme = File.ReadAllBytes(FS(theme));
            Check(Compatible(existing), "Current Windows early hook rejected");
            string bom = External("bom", "-- Windows comment\r\n\r\n" + Hook);
            File.WriteAllText(FS(Path.Combine(bom, "init.lua")), "-- Windows comment\r\n\r\n" + Hook, new UTF8Encoding(true));
            Check(Compatible(bom), "UTF-8 BOM/comment preamble rejected");
            Pass("current early hook and UTF-8 BOM/comments recognized");

            Check(!Compatible(External("missing-hook", "require('config.bootstrap').setup()\n")), "Missing early hook accepted");
            Check(!Compatible(External("late-hook", "require('config.lazy')\n" + Hook)), "Late runtime hook accepted");
            Check(!Compatible(External("commented-hook", "--[[\n" + Hook + "]]\nrequire('config.lazy')\n")), "Commented runtime hook accepted");
            Check(!Compatible(External("string-hook", "local text = [[" + Hook + "]]\n")), "String containing hook accepted");
            Pass("missing, late, long-comment and string hooks declined without executing Lua");

            int choices = 0, notices = 0;
            string externalProfile = Profile("external");
            string selected = Resolve(externalProfile, existing, delegate(string path) { choices++; Check(path == existing, "Wrong existing config"); return DialogResult.Yes; }, delegate { notices++; });
            Check(selected == existing && choices == 1 && notices == 0, "Existing choice did not select exact Windows config");
            string record = File.ReadAllText(FS(Selection(externalProfile)));
            Check(record.Contains("external") && record.Contains(Stack), "Choice was not bound to profile/release");
            Check(Resolve(externalProfile, existing, delegate { throw new Exception("Prompt repeated"); }, delegate { throw new Exception("Notice repeated"); }) == existing, "Persisted choice was not reused");
            Pass("external choice persists once and does not prompt on later launch");

            Check(Convert.ToBase64String(initialInit) == Convert.ToBase64String(File.ReadAllBytes(FS(init))) &&
                Convert.ToBase64String(initialTheme) == Convert.ToBase64String(File.ReadAllBytes(FS(theme))), "Existing init/theme bytes changed");
            Check(!Directory.Exists(FS(Path.Combine(existing, "lazy"))), "Runtime data was written into external configuration");
            Pass("external init and theme bytes remain unchanged");

            string privateProfile = Profile("private");
            choices = notices = 0;
            selected = Resolve(privateProfile, existing, delegate { choices++; return DialogResult.No; }, delegate(string message) { notices++; Check(message.Contains("Fixture next step."), "Missing next step"); });
            Check(selected == Path.Combine(privateProfile, "config", "nvim") && choices == 1 && notices == 1, "Independent default selection failed");
            Resolve(privateProfile, existing, delegate { throw new Exception("Prompt repeated"); }, delegate { throw new Exception("Notice repeated"); });
            Pass("declining existing config selects separate defaults and announces only once");

            string missing = Path.Combine(root, "absent", ".config", "nvim");
            string fresh = Profile("fresh");
            notices = 0;
            selected = Resolve(fresh, missing, delegate { throw new Exception("Missing config prompted"); }, delegate(string message) { notices++; Check(message.Contains(Path.Combine(fresh, "config", "nvim")), "Default path not shown"); });
            Check(selected == Path.Combine(fresh, "config", "nvim") && notices == 1 && !Directory.Exists(FS(missing)), "New-user default created an external config");
            Pass("new user gets private defaults, actual path and next step without external writes");

            UseLanguage("zh-CN");
            string chineseProfile = Profile("chinese");
            Resolve(chineseProfile, missing, delegate { throw new Exception("Missing config prompted"); }, delegate(string message) {
                Check(message.Contains("Glow 将使用独立配置") && message.Contains("此选择已为本发行版本保存"), "Chinese first-start notice was not localized");
            });
            string invalidChinese = Profile("invalid-chinese");
            Write(Selection(invalidChinese), "{\"schema_version\":1,\"stack_id\":\"other-release\",\"mode\":\"profile\"}");
            bool chineseError = false;
            try { Resolve(invalidChinese, existing, delegate { return DialogResult.Yes; }, delegate { }); }
            catch (InvalidDataException error) { chineseError = error.Message.Contains("配置选择无效"); }
            Check(chineseError, "Saved configuration error was not localized");
            UseLanguage("en");
            Pass("Chinese first-start notice and actionable configuration errors use the selected language");

            string incompatible = External("incompatible", "-- unrelated user config\n");
            string declined = Profile("incompatible");
            Resolve(declined, incompatible, delegate { throw new Exception("Unsafe config offered"); }, delegate(string message) { Check(message.Contains("could not be safely reused"), "Incompatible config reason missing"); });
            Check(File.ReadAllText(FS(Path.Combine(incompatible, "init.lua"))) == "-- unrelated user config\n", "Incompatible config was changed");
            Pass("incompatible existing config is explained and preserved");

            string cancel = Profile("cancel");
            bool cancelled = false;
            try { Resolve(cancel, existing, delegate { return DialogResult.Cancel; }, delegate { throw new Exception("Cancellation announced defaults"); }); }
            catch (OperationCanceledException) { cancelled = true; }
            Check(cancelled && !File.Exists(FS(Selection(cancel))), "Cancellation persisted a choice");
            Pass("cancel preserves configuration and leaves choice for next launch");

            File.Delete(FS(init));
            RejectSaved(externalProfile, existing, typeof(InvalidOperationException));
            Check(File.ReadAllText(FS(Selection(externalProfile))) == record, "Missing external config overwrote its choice");
            Write(init, "require('config.lazy')\n" + Hook);
            RejectSaved(externalProfile, existing, typeof(InvalidOperationException));
            Pass("missing or no-longer-safe external config fails explicitly without silent fallback");

            string invalid = Profile("invalid-selection");
            Write(Selection(invalid), "{\"schema_version\":1,\"stack_id\":\"other-release\",\"mode\":\"profile\"}");
            RejectSaved(invalid, existing, typeof(InvalidDataException));
            Pass("wrong-release selection rejected and preserved");

            string package = Path.Combine(root, "package");
            Write(Path.Combine(package, "profile", "config", "nvim", "init.lua"), Hook);
            Write(Path.Combine(package, "profile", "data", "nvim", "lazy", "fixture", "plugin.lua"), "return {}\n");
            string initialize = Path.Combine(root, "initialize-only");
            Call("PrepareProfile", package, initialize, Stack);
            Check(!File.Exists(FS(Selection(initialize))) && File.Exists(FS(Path.Combine(initialize, "config", "nvim", "init.lua"))), "Profile initialization made an interactive configuration choice");
            Check(Directory.Exists(FS(Path.Combine(initialize, "data", "nvim-data", "lazy"))), "Private runtime data layout changed");
            Pass("initialize-profile prepares isolated data without choosing external config or showing UI");

            string wizard = Path.Combine(root, "App 中文", "dependencies", "Setup-Wizard.ps1");
            string arguments = (string)Call("DependencySetupArguments", wizard, new string[] { "--setup", "--notebook", "--latex" });
            Check(arguments.Contains("-STA -NoProfile -NonInteractive") && arguments.Contains("-File \"" + wizard + "\"") &&
                arguments.Contains(" -Language \"en\"") && arguments.EndsWith(" -InstallNotebook -InstallLatex"), "Setup command quoting, language or switch conversion failed");
            string audit = (string)Call("DependencySetupArguments", wizard, new string[] { "--setup" });
            Check(!audit.Contains(" -InstallNotebook") && !audit.Contains(" -InstallLatex"), "Default setup forced optional feature switches");
            UseLanguage("zh-CN");
            string chineseArguments = (string)Call("DependencySetupArguments", wizard, new string[] { "--setup" });
            Check(chineseArguments.EndsWith(" -Language \"zh-CN\""), "Selected Chinese language was not forwarded to setup");
            Write(languageFile, "en\" -Command Write-Host unsafe");
            UseLanguage((string)Call("ReadUiLanguage", root, english));
            string safeArguments = (string)Call("DependencySetupArguments", wizard, new string[] { "--setup" });
            Check(safeArguments.EndsWith(" -Language \"en\"") && !safeArguments.Contains("-Command"), "Invalid installer language was forwarded as executable arguments");
            foreach (string[] bad in new string[][] { new string[] { "--setup", "--unknown" }, new string[] { "--setup", "--latex", "--latex" },
                new string[] { "--setup", "-Command", "Write-Host unsafe" } })
            {
                bool rejected = false;
                try { Call("DependencySetupArguments", wizard, bad); } catch (ArgumentException) { rejected = true; }
                Check(rejected, "Unknown/repeated/injected setup arguments accepted");
            }
            Pass("GUI setup uses fixed PowerShell flags, quoted path and allowlisted feature switches");
            Console.WriteLine("Launcher configuration regression passed: " + passed + " cases; fixture files only");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally
        {
            System.Threading.Thread.CurrentThread.CurrentUICulture = originalCulture;
            if (root != null && Directory.Exists(FS(root))) Directory.Delete(FS(root), true);
        }
    }
}
