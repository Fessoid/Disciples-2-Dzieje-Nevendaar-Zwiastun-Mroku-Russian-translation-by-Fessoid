// Discipl2Pol_Launcher — запуск игры и обновление перевода.
//
// Лежит в папке с игрой рядом с Discipl2.exe. Запускает игру и смотрит
// манифест в репозитории перевода.
//
// Себя обновляет молча: человек ничего не нажимает и ничего не замечает —
// новый файл встаёт на место после выхода лаунчера.
//
// Про перевод спрашивает: архив ложится поверх файлов игры, и ради этого игру
// надо закрыть. Такое без согласия не делают.
//
// Всё остальное молча: нет сети, нет ответа, сменился формат манифеста —
// игра уже запущена и об этом не знает.
//
// Сборка одной строкой из папки Launcher (csc есть в любой Windows):
//
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo
//       /target:winexe /out:Discipl2Pol_Launcher.exe /win32icon:launcher.ico
//       /reference:System.IO.Compression.dll
//       /reference:System.IO.Compression.FileSystem.dll
//       /reference:System.Web.Extensions.dll Discipl2PolLauncher.cs
//
// Компилятор из состава Windows понимает C# 5: без интерполяции строк,
// без ?. и без сопоставления с образцом.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;

[assembly: AssemblyTitle("Discipl2Pol_Launcher")]
[assembly: AssemblyProduct("Disciples 2: Dzieje Nevendaar - русский перевод")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

// Класс открытый, чтобы отдельная программа проверок могла дёргать разбор
// версий, распаковку и подмену файла, не поднимая окон.
public static class Launcher
{
    public const string AppName = "Discipl2Pol_Launcher";
    public const string AppVersion = "1.1";

    // Манифест, а не /releases/latest: релизы этого репозитория — релизы
    // перевода с тегами-датами, версия лаунчера в такой ряд не встаёт.
    const string ManifestUrl =
        "https://raw.githubusercontent.com/Fessoid/" +
        "Disciples-2-Dzieje-Nevendaar-Zwiastun-Mroku-Russian-translation-by-Fessoid" +
        "/main/Launcher/latest.json";

    // Основное имя — из установки мода; запасное встречается в других сборках.
    static readonly string[] GameNames = { "Discipl2.exe", "Disciple.exe" };

    // Какая версия перевода стоит. Файл едет внутри архива, поэтому после
    // ручной установки версия оказывается верной сама собой.
    const string ModVersionFile = "Discipl2Pol_version.txt";

    // Куда отправлять человека, если он отказался или скачать не вышло.
    const string ModInfoFile = "!ОСОБЕННОСТИ МОДА.txt";

    const int ManifestTimeout = 8000;
    const int DownloadTimeout = 600000;

    // =====================================================================
    // ТОЧКА ВХОДА
    // =====================================================================

    static int Main()
    {
        string folder = AppDir();
        bool started = StartGame(folder);

        string[] pending = null;
        try
        {
            pending = CheckUpdates(folder);
        }
        catch
        {
            // Проверка обновлений не имеет права мешать игре.
        }

        // Подмена ставится последним действием: помощник ждёт выхода лаунчера
        // ограниченное время, а всё, что делается после, это время съедает.
        if (pending != null)
        {
            ScheduleReplace(pending[0], pending[1]);
        }
        return started ? 0 : 1;
    }

    static string[] CheckUpdates(string folder)
    {
        Dictionary<string, object> manifest = FetchManifest();
        if (manifest == null)
        {
            return null;
        }

        string[] pending = null;
        Dictionary<string, object> launcher = Section(manifest, "launcher");
        if (launcher != null)
        {
            try
            {
                pending = SelfUpdate(launcher);
            }
            catch
            {
                pending = null;      // своя осечка перевода не задевает
            }
        }

        // Обновил себя — про перевод в этот запуск не спрашиваем. Тогда архив
        // всегда ставит та версия лаунчера, которая вышла вместе с ним.
        if (pending != null)
        {
            return pending;
        }

        Dictionary<string, object> mod = Section(manifest, "mod");
        if (mod != null)
        {
            ModUpdate(mod, folder);
        }
        return null;
    }

    // =====================================================================
    // ПУТИ
    // =====================================================================

    static string AppDir()
    {
        return Path.GetDirectoryName(Path.GetFullPath(
            Assembly.GetExecutingAssembly().Location));
    }

    static string ExePath()
    {
        return Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
    }

    /// <summary>Своя подпапка во временных, а не их корень: в корне запись
    /// файла может проходить, а переименование в тот же каталог — падать,
    /// и загрузка ломается на последнем шаге.</summary>
    static string TempDir()
    {
        string path = Path.Combine(Path.GetTempPath(), AppName);
        try
        {
            Directory.CreateDirectory(path);
        }
        catch
        {
            return Path.GetTempPath();
        }
        return path;
    }

    static string StatePath()
    {
        string basePath = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        if (string.IsNullOrEmpty(basePath))
        {
            basePath = Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData);
        }
        if (string.IsNullOrEmpty(basePath))
        {
            basePath = Path.GetTempPath();
        }
        return Path.Combine(Path.Combine(basePath, AppName), "state.txt");
    }

    // =====================================================================
    // ЗАПУСК И ЗАКРЫТИЕ ИГРЫ
    //
    // Запуск делается первым и без ожидания: проверка обновлений не должна
    // стоять на пути к игре.
    // =====================================================================

    static string FindGame(string folder)
    {
        foreach (string name in GameNames)
        {
            string path = Path.Combine(folder, name);
            if (File.Exists(path))
            {
                return path;
            }
        }
        return null;
    }

    static bool StartGame(string folder)
    {
        string game = FindGame(folder);
        if (game == null)
        {
            ShowError("Игра не найдена",
                "Рядом с лаунчером нет " + string.Join(" и ", GameNames) +
                ".\n\nПоложите " + AppName + ".exe в папку с игрой.");
            return false;
        }
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo(game);
            psi.WorkingDirectory = folder;
            psi.UseShellExecute = false;
            Process.Start(psi);
        }
        catch (Exception exc)
        {
            ShowError("Не удалось запустить игру", game + "\n\n" + exc.Message);
            return false;
        }
        return true;
    }

    /// <summary>Закрывает игру по имени процесса, а не своего потомка: игра
    /// запускается через обёртку, и настоящий процесс лаунчеру не принадлежит.
    /// </summary>
    static void CloseGame()
    {
        foreach (string name in GameNames)
        {
            Process[] found;
            try
            {
                found = Process.GetProcessesByName(
                    Path.GetFileNameWithoutExtension(name));
            }
            catch
            {
                continue;
            }
            foreach (Process p in found)
            {
                try
                {
                    p.Kill();
                    p.WaitForExit(5000);
                }
                catch
                {
                    // Процесс мог закрыться сам, пока мы до него шли.
                }
            }
        }
    }

    // =====================================================================
    // ОКНА
    //
    // Своего интерфейса у лаунчера нет — только системные окна, и только там,
    // где без человека не обойтись.
    // =====================================================================

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    const uint MB_OK = 0x00000000;
    const uint MB_YESNO = 0x00000004;
    const uint MB_ICONERROR = 0x00000010;
    const uint MB_ICONQUESTION = 0x00000020;
    const uint MB_ICONINFORMATION = 0x00000040;
    const uint MB_SETFOREGROUND = 0x00010000;

    // Игра полноэкранная — окну нужен WS_EX_TOPMOST, иначе оно уедет под неё.
    // Даёт его MB_SYSTEMMODAL, а не MB_TOPMOST: измерено на Windows 10 21H2,
    // с MB_TOPMOST расширенный стиль окна остаётся 0x10101 без бита 0x8.
    // Документация обещает этот стиль обоим флагам — верно измерение.
    const uint MB_SYSTEMMODAL = 0x00001000;

    const int ID_YES = 6;

    static int Dialog(uint flags, string title, string text)
    {
        try
        {
            return MessageBoxW(IntPtr.Zero, text, AppName + " — " + title,
                flags | MB_SETFOREGROUND | MB_SYSTEMMODAL);
        }
        catch
        {
            return 0;
        }
    }

    static bool AskYesNo(string title, string text)
    {
        return Dialog(MB_YESNO | MB_ICONQUESTION, title, text) == ID_YES;
    }

    static void ShowError(string title, string text)
    {
        Dialog(MB_OK | MB_ICONERROR, title, text);
    }

    static void ShowInfo(string title, string text)
    {
        Dialog(MB_OK | MB_ICONINFORMATION, title, text);
    }

    // =====================================================================
    // ВЕРСИИ
    //
    // Два разных ряда: у лаунчера «1.1», у перевода дата. Сравниваются оба
    // числами, но дата приводится к (год, месяц, день) — иначе 31.07.2026
    // окажется «новее», чем 01.08.2026.
    // =====================================================================

    public static int[] ParseVersion(string value)
    {
        if (value == null)
        {
            return new int[0];
        }
        string text = value.Trim().TrimStart('v', 'V');
        if (text.Length == 0)
        {
            return new int[0];
        }

        string[] dashed = text.Split('-');
        if (dashed.Length == 3 && dashed[0].Length == 4 && AllDigits(dashed))
        {
            return new int[] { Num(dashed[0]), Num(dashed[1]), Num(dashed[2]) };
        }

        string[] parts = text.Split('.');
        // 31.07.2026 и 31.07.26 — дата: последняя часть из четырёх цифр либо
        // первая больше 12. Версия «1.2.3» под это не подходит.
        if (parts.Length == 3 && AllDigits(parts))
        {
            int day = Num(parts[0]);
            int month = Num(parts[1]);
            int year = Num(parts[2]);
            if (parts[2].Length == 4 || day > 12)
            {
                if (parts[2].Length == 2)
                {
                    year += 2000;
                }
                return new int[] { year, month, day };
            }
        }

        List<int> numbers = new List<int>();
        foreach (string chunk in parts)
        {
            string digits = OnlyDigits(chunk);
            if (digits.Length == 0)
            {
                break;
            }
            numbers.Add(Num(digits));
        }
        return numbers.ToArray();
    }

    static bool AllDigits(string[] parts)
    {
        foreach (string p in parts)
        {
            if (p.Length == 0 || OnlyDigits(p).Length != p.Length)
            {
                return false;
            }
        }
        return true;
    }

    static string OnlyDigits(string s)
    {
        StringBuilder sb = new StringBuilder();
        foreach (char c in s)
        {
            if (c >= '0' && c <= '9')
            {
                sb.Append(c);
            }
        }
        return sb.ToString();
    }

    static int Num(string s)
    {
        int v;
        if (int.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out v))
        {
            return v;
        }
        return 0;
    }

    public static int Compare(string a, string b)
    {
        int[] x = ParseVersion(a);
        int[] y = ParseVersion(b);
        int n = Math.Max(x.Length, y.Length);
        for (int i = 0; i < n; i++)
        {
            int xi = i < x.Length ? x[i] : 0;
            int yi = i < y.Length ? y[i] : 0;
            if (xi != yi)
            {
                return xi < yi ? -1 : 1;
            }
        }
        return 0;
    }

    public static bool IsNewer(string candidate, string current)
    {
        return ParseVersion(candidate).Length > 0 && Compare(candidate, current) > 0;
    }

    // =====================================================================
    // ЧТО СТОИТ НА ДИСКЕ
    //
    // Два источника, берётся более старый. Удалили файл рядом с игрой —
    // ответит запись в %LOCALAPPDATA%. Накатили руками старый архив — ответит
    // файл из этого архива. Ошибиться в сторону «старее» стоит одного лишнего
    // вопроса, в сторону «новее» — потерянного обновления.
    // =====================================================================

    static string ReadFileVersion(string folder)
    {
        try
        {
            return File.ReadAllText(Path.Combine(folder, ModVersionFile),
                Encoding.UTF8).Trim();
        }
        catch
        {
            return "";
        }
    }

    public static string InstalledModVersion(string folder)
    {
        string fromFile = ReadFileVersion(folder);
        string fromState = GetState("mod_version");
        if (ParseVersion(fromFile).Length == 0)
        {
            return fromState;
        }
        if (ParseVersion(fromState).Length == 0)
        {
            return fromFile;
        }
        return Compare(fromFile, fromState) <= 0 ? fromFile : fromState;
    }

    public static void WriteModVersion(string folder, string version)
    {
        try
        {
            File.WriteAllText(Path.Combine(folder, ModVersionFile),
                version + Environment.NewLine, new UTF8Encoding(false));
        }
        catch
        {
            // Папка игры может быть только для чтения — запись в состоянии
            // всё равно останется.
        }
        SetState("mod_version", version);
    }

    // =====================================================================
    // СОСТОЯНИЕ: простые строки «ключ=значение»
    // =====================================================================

    static Dictionary<string, string> LoadState()
    {
        Dictionary<string, string> state = new Dictionary<string, string>();
        try
        {
            foreach (string line in File.ReadAllLines(StatePath(), Encoding.UTF8))
            {
                int eq = line.IndexOf('=');
                if (eq > 0)
                {
                    state[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
                }
            }
        }
        catch
        {
            // Нет файла — нет состояния, это нормальный первый запуск.
        }
        return state;
    }

    static string GetState(string key)
    {
        Dictionary<string, string> state = LoadState();
        return state.ContainsKey(key) ? state[key] : "";
    }

    static void SetState(string key, string value)
    {
        Dictionary<string, string> state = LoadState();
        state[key] = value;
        try
        {
            string path = StatePath();
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            StringBuilder sb = new StringBuilder();
            foreach (KeyValuePair<string, string> kv in state)
            {
                sb.Append(kv.Key).Append('=').Append(kv.Value).Append("\r\n");
            }
            File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
        }
        catch
        {
            // Не записалось — в следующий раз просто спросим ещё раз.
        }
    }

    // =====================================================================
    // МАНИФЕСТ И ЗАГРУЗКА
    // =====================================================================

    class TimedWebClient : WebClient
    {
        public int Timeout = ManifestTimeout;

        protected override WebRequest GetWebRequest(Uri address)
        {
            WebRequest request = base.GetWebRequest(address);
            request.Timeout = Timeout;
            HttpWebRequest http = request as HttpWebRequest;
            if (http != null)
            {
                http.ReadWriteTimeout = Timeout;
            }
            return request;
        }
    }

    static TimedWebClient MakeClient(int timeout)
    {
        // Старые сборки .NET по умолчанию говорят TLS 1.0, а GitHub его не
        // принимает. Значение числом, чтобы собиралось и там, где имени ещё нет.
        try
        {
            ServicePointManager.SecurityProtocol =
                ServicePointManager.SecurityProtocol | (SecurityProtocolType)3072;
        }
        catch
        {
            // Совсем старая система — пусть попробует как умеет.
        }
        TimedWebClient client = new TimedWebClient();
        client.Timeout = timeout;
        client.Headers.Add("User-Agent", AppName + "/" + AppVersion);
        client.Headers.Add("Cache-Control", "no-cache");
        return client;
    }

    static Dictionary<string, object> FetchManifest()
    {
        try
        {
            string body;
            using (TimedWebClient client = MakeClient(ManifestTimeout))
            {
                client.Encoding = Encoding.UTF8;
                body = client.DownloadString(ManifestUrl);
            }
            object parsed = new JavaScriptSerializer().DeserializeObject(body);
            return parsed as Dictionary<string, object>;
        }
        catch
        {
            return null;             // нет сети, нет ответа — молчим
        }
    }

    static Dictionary<string, object> Section(Dictionary<string, object> manifest,
                                              string name)
    {
        if (manifest == null || !manifest.ContainsKey(name))
        {
            return null;
        }
        return manifest[name] as Dictionary<string, object>;
    }

    static string Field(Dictionary<string, object> section, string name)
    {
        if (section == null || !section.ContainsKey(name) || section[name] == null)
        {
            return "";
        }
        return Convert.ToString(section[name], CultureInfo.InvariantCulture).Trim();
    }

    /// <summary>Качает во временное имя и переименовывает: обрыв связи не
    /// оставит рядом с игрой недокачанный файл.</summary>
    static void DownloadFile(string url, string destPath)
    {
        string tmpPath = destPath + ".part";
        try
        {
            using (TimedWebClient client = MakeClient(DownloadTimeout))
            {
                client.DownloadFile(url, tmpPath);
            }
            if (File.Exists(destPath))
            {
                File.Delete(destPath);
            }
            File.Move(tmpPath, destPath);
        }
        catch
        {
            try
            {
                if (File.Exists(tmpPath))
                {
                    File.Delete(tmpPath);
                }
            }
            catch
            {
            }
            throw;
        }
    }

    // =====================================================================
    // САМОЗАМЕНА
    //
    // Запущенный exe себя не перезапишет. Файл подменяет .cmd: он ждёт, пока
    // лаунчер завершится и отпустит файл, переносит новую версию на место
    // старой и стирает сам себя.
    //
    // Пути передаются аргументами, а не пишутся в тело файла. Причина —
    // кодировка: cmd.exe читает .bat в OEM-кодировке консоли, и путь с
    // кириллицей (папка игры, имя пользователя в %TEMP%) в теле файла
    // превратится в мусор. Аргументы идут через CreateProcess в UTF-16 и не
    // портятся. Поэтому сам .cmd — ASCII.
    // =====================================================================

    static readonly string[] UpdateCmdLines = {
        "@echo off",
        "set \"TARGET=%~1\"",
        "set \"SOURCE=%~2\"",
        "set /a TRIES=0",
        ":retry",
        "set /a TRIES+=1",
        "move /y \"%SOURCE%\" \"%TARGET%\" >nul 2>&1",
        "if not errorlevel 1 goto done",
        // ~60 секунд ожидания: файл держит не только сам лаунчер, но и
        // антивирус, проверяющий свежескачанный exe.
        "if %TRIES% geq 60 goto giveup",
        "ping -n 2 127.0.0.1 >nul",
        "goto retry",
        ":giveup",
        "del /f /q \"%SOURCE%\" >nul 2>&1",
        ":done",
        "del /f /q \"%~f0\" >nul 2>&1",
        ""
    };

    public static bool ScheduleReplace(string targetPath, string sourcePath)
    {
        string cmdPath = Path.Combine(TempDir(), "update.cmd");
        try
        {
            File.WriteAllText(cmdPath, string.Join("\r\n", UpdateCmdLines),
                Encoding.ASCII);
        }
        catch
        {
            return false;
        }

        try
        {
            ProcessStartInfo psi = new ProcessStartInfo("cmd.exe");
            // Форма /c ""файл" "арг1" "арг2"" — единственная, которую cmd.exe
            // разбирает верно, когда в путях есть пробелы.
            psi.Arguments = "/c \"\"" + cmdPath + "\" \"" + targetPath +
                            "\" \"" + sourcePath + "\"\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            Process.Start(psi);
        }
        catch
        {
            return false;
        }
        return true;
    }

    // =====================================================================
    // ОБНОВЛЕНИЕ ЛАУНЧЕРА — без единого окна
    //
    // Спрашивать не о чем: файл меняется сам на себя, игра не трогается,
    // человек ничего не теряет. Любая осечка — молчание, следующий запуск
    // попробует снова.
    // =====================================================================

    static string[] SelfUpdate(Dictionary<string, object> entry)
    {
        string version = Field(entry, "version");
        string url = Field(entry, "url");
        if (!IsNewer(version, AppVersion) || url.Length == 0)
        {
            return null;
        }

        string target = ExePath();
        string source = target + ".new";
        try
        {
            DownloadFile(url, source);
        }
        catch
        {
            return null;
        }
        return new string[] { target, source };
    }

    // =====================================================================
    // ОБНОВЛЕНИЕ ПЕРЕВОДА — с вопросом
    //
    // Здесь без человека нельзя: архив ложится поверх файлов игры, а для
    // этого игру надо закрыть.
    // =====================================================================

    /// <summary>Распаковывает архив поверх папки игры.
    ///
    /// Пути из архива проверяются: он приехал из сети, и запись за пределы
    /// папки игры — не то, что должно получиться из обновления перевода.
    ///
    /// Имена читаются в CP866, если в архиве не выставлен флаг UTF-8: архивы
    /// с русской Windows приезжают именно такими.</summary>
    public static void UnpackOver(string zipPath, string folder)
    {
        string root = Path.GetFullPath(folder);
        if (!root.EndsWith(Path.DirectorySeparatorChar.ToString()))
        {
            root += Path.DirectorySeparatorChar;
        }

        using (FileStream fs = File.OpenRead(zipPath))
        using (ZipArchive zip = new ZipArchive(fs, ZipArchiveMode.Read, false,
                                               Encoding.GetEncoding(866)))
        {
            foreach (ZipArchiveEntry entry in zip.Entries)
            {
                string name = entry.FullName.Replace('\\', '/');
                // Проверяются сегменты, а не подстрока: имя файла вида
                // «список..txt» законно, а сегмент «..» — нет.
                bool unsafePath = name.StartsWith("/") ||
                                  (name.Length > 1 && name[1] == ':');
                foreach (string seg in name.Split('/'))
                {
                    if (seg == "..")
                    {
                        unsafePath = true;
                    }
                }
                if (unsafePath)
                {
                    throw new InvalidDataException(
                        "небезопасный путь в архиве: " + name);
                }

                string dest = Path.GetFullPath(Path.Combine(root, name));
                if (!dest.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException(
                        "путь ведёт за пределы папки: " + name);
                }

                if (entry.Name.Length == 0)
                {
                    Directory.CreateDirectory(dest);
                    continue;
                }
                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                using (Stream src = entry.Open())
                using (FileStream outFile = new FileStream(
                    dest, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    src.CopyTo(outFile);
                }
            }
        }
    }

    static void ModUpdate(Dictionary<string, object> entry, string folder)
    {
        string version = Field(entry, "version");
        string url = Field(entry, "url");
        string installed = InstalledModVersion(folder);

        // Версия неизвестна — значит перевод ставили руками до появления
        // лаунчера. Записываем текущую и молчим: предлагать переустановить то,
        // что человек только что распаковал, незачем.
        if (ParseVersion(installed).Length == 0)
        {
            WriteModVersion(folder, version);
            return;
        }

        if (!IsNewer(version, installed))
        {
            return;
        }
        if (!IsNewer(version, GetState("skipped_mod_version")))
        {
            return;
        }

        string notes = Field(entry, "notes");
        string text = "Вышла новая версия перевода: " + version + ".\n" +
                      "У вас стоит " + installed + ".\n\n";
        if (notes.Length > 0)
        {
            text += notes + "\n\n";
        }
        // Игра закрывается принудительно, поэтому про несохранённую партию
        // нужно сказать до вопроса, а не после.
        text += "Для установки игра будет закрыта.\n" +
                "Несохранённая партия пропадёт.\n\nОбновить сейчас?";

        if (!AskYesNo("Обновление перевода", text))
        {
            SetState("skipped_mod_version", version);
            ShowInfo("Обновление пропущено",
                "Версия перевода " + version + " будет пропущена — больше " +
                "о ней не спросим.\n\n" +
                "Скачать её самостоятельно можно по ссылке из файла\n«" +
                ModInfoFile + "» в папке с игрой.");
            return;
        }

        if (url.Length == 0)
        {
            ShowError("Обновление недоступно",
                "Ссылка на архив не указана.\n\n" +
                "Скачать перевод можно по ссылке из файла\n«" +
                ModInfoFile + "» в папке с игрой.");
            return;
        }

        CloseGame();
        string archive = Path.Combine(TempDir(), "mod_" + SafeName(version) + ".zip");
        try
        {
            DownloadFile(url, archive);
            UnpackOver(archive, folder);
        }
        catch (Exception exc)
        {
            ShowError("Обновление не установлено",
                exc.Message + "\n\nИгра сейчас запустится в прежнем виде.\n" +
                "Скачать перевод вручную можно по ссылке из файла\n«" +
                ModInfoFile + "» в папке с игрой.");
            StartGame(folder);
            return;
        }
        finally
        {
            try
            {
                if (File.Exists(archive))
                {
                    File.Delete(archive);
                }
            }
            catch
            {
            }
        }

        WriteModVersion(folder, version);
        ShowInfo("Перевод обновлён",
            "Установлена версия " + version + ".\n\nИгра сейчас запустится.");
        StartGame(folder);
    }

    static string SafeName(string value)
    {
        StringBuilder sb = new StringBuilder();
        foreach (char c in value)
        {
            sb.Append(Array.IndexOf(Path.GetInvalidFileNameChars(), c) >= 0 ? '_' : c);
        }
        return sb.ToString();
    }
}
