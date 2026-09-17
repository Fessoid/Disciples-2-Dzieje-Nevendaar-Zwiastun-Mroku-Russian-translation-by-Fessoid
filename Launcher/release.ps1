<#
Сборка и проверка выпуска русского перевода.

Запуск из папки проекта:

  powershell -ExecutionPolicy Bypass -File Launcher\release.ps1 -Version 17.09.2026
  powershell -ExecutionPolicy Bypass -File Launcher\release.ps1 -Check
  powershell -ExecutionPolicy Bypass -File Launcher\release.ps1 -Verify путь\к\архиву.zip

-Version  собирает архив перевода в Launcher\dist\ из того, что лежит в git,
          кладёт внутрь файл версии и проверяет архив распаковкой самого лаунчера.
-Check    после выкладки на GitHub сверяет ассет, манифест и лаунчер. Когда
          выложенное ещё не названо в манифесте, готовит Launcher\latest.json к пушу.
-Verify   проверяет zip, собранный не этим скриптом.

Файл хранится в UTF-8 с BOM: без него PowerShell 5.1 читает кириллицу как ANSI
и не разбирает скрипт целиком.
#>

param(
    [string]$Version,
    [switch]$Check,
    [string]$Verify
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.Web.Extensions

$Root = Split-Path -Parent $PSScriptRoot
$LauncherExe = Join-Path $Root 'Discipl2Pol_Launcher.exe'
$LauncherSource = Join-Path $PSScriptRoot 'Discipl2PolLauncher.cs'
$ManifestPath = Join-Path $PSScriptRoot 'latest.json'
$DistDir = Join-Path $PSScriptRoot 'dist'

# Имена, которые лаунчер знает наизусть.
$VersionFile = 'Discipl2Pol_version.txt'
$InfoFile = '!ОСОБЕННОСТИ МОДА.txt'

# В архив едет всё, что лежит в git, кроме этого. Перечень «что оставить», а не
# «что взять»: новая папка с данными попадает в архив сама, стоит её закоммитить.
# Файл версии тоже здесь — его пишет скрипт, а не git.
$DevOnlyFiles = @('.gitignore', '.gitattributes', 'README.md', 'Update.md',
                  'Discipl2Pol_Launcher.exe', $VersionFile)
$DevOnlyDirs = @('Launcher/', 'docs/')

$Problems = New-Object 'Collections.Generic.List[string]'
$Dict = [Collections.Generic.Dictionary[string, object]]
$ManifestKeys = [ordered]@{
    LauncherVersion = 'launcher.version'
    LauncherUrl     = 'launcher.url'
    LauncherNotes   = 'launcher.notes'
    ModVersion      = 'mod.version'
    ModUrl          = 'mod.url'
    ModNotes        = 'mod.notes'
}

trap {
    Write-Host ''
    Write-Host "Скрипт упал: $(Get-Reason $_)" -ForegroundColor Red
    exit 2
}

# =====================================================================
# ОБЩЕЕ
# =====================================================================

function Get-Reason($Record) {
    $e = $Record.Exception
    while ($e.InnerException) { $e = $e.InnerException }
    return $e.Message
}

function Add-Problem([string]$Text) {
    $Problems.Add($Text)
}

function Add-ListProblem([string]$Title, [object[]]$Items) {
    if (-not $Items -or $Items.Count -eq 0) { return }
    $shown = @($Items | Select-Object -First 10)
    $text = "${Title}:`n      " + ($shown -join "`n      ")
    if ($Items.Count -gt $shown.Count) {
        $text += "`n      и ещё $($Items.Count - $shown.Count)"
    }
    Add-Problem $text
}

function Stop-OnProblems {
    if ($Problems.Count -eq 0) { return }
    Write-Host ''
    Write-Host 'Остановлено:' -ForegroundColor Red
    foreach ($p in $Problems) { Write-Host "  - $p" }
    exit 1
}

function Read-Text([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Get-AssetName([string]$ModVersion) {
    return "D2PolskiyModRus_$ModVersion.zip"
}

function Get-AssetUrl([string]$ModVersion) {
    return "$ReleaseBase/$ModVersion/$(Get-AssetName $ModVersion)"
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Test-ModVersionDate([string]$ModVersion) {
    $date = [datetime]::MinValue
    $isDate = [datetime]::TryParseExact($ModVersion, 'dd.MM.yyyy',
        [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)
    if (-not $isDate) {
        Add-Problem "версия «$ModVersion» не дата вида ДД.ММ.ГГГГ. В этом виде её пишут тег, файл версии и манифест"
        return
    }
    # День запаса — на выпуск за полночь. Лаунчер ставит только строго более
    # новую версию, поэтому дата из будущего глушит все выпуски до неё.
    if ($date -gt (Get-Date).Date.AddDays(1)) {
        Add-Problem "версия $ModVersion позже сегодняшней даты: пока она не наступит, лаунчер не предложит ни один следующий выпуск. День и месяц не перепутаны?"
    }
}

# =====================================================================
# GIT
# =====================================================================

function Invoke-Git([string]$Arguments) {
    $psi = New-Object Diagnostics.ProcessStartInfo('git', "-c core.quotepath=false $Arguments")
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Вывод читается в UTF-8 напрямую, а не через консоль: кодировка консоли
    # у всех своя, и кириллица в путях превращается в мусор.
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding $false
    try {
        $p = [Diagnostics.Process]::Start($psi)
    } catch {
        Add-Problem 'git не найден, а список файлов архива берётся из git'
        Stop-OnProblems
    }
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        Add-Problem "git $Arguments завершился ошибкой: $($err.Trim())"
        Stop-OnProblems
    }
    # Массив символов явно: с одиночным [char] PowerShell выбирает перегрузку
    # Split(params char[]), и пустые записи остаются.
    return ,$out.Split([char[]]@([char]0), [StringSplitOptions]::RemoveEmptyEntries)
}

function Test-DevOnly([string]$Path) {
    foreach ($f in $DevOnlyFiles) {
        if ($Path -ieq $f) { return $true }
    }
    foreach ($d in $DevOnlyDirs) {
        if ($Path.StartsWith($d, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-ModFiles {
    $tracked = Invoke-Git 'ls-files -z'
    $files = @($tracked | Where-Object { -not (Test-DevOnly $_) })
    $gone = @($files | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf) })
    Add-ListProblem 'файлы есть в git, но их нет на диске' $gone
    return ,$files
}

# Архив собирается из рабочей папки, а не из git: при core.autocrlf данные
# в git и на диске различаются переводами строк, а в игре проверено то, что
# на диске. Поэтому рабочая папка обязана совпадать с последним коммитом.
function Test-CleanTree([switch]$WithVersionFile) {
    $items = Invoke-Git 'status --porcelain=v1 -z --untracked-files=all'
    $dirty = @()
    $untracked = @()
    for ($i = 0; $i -lt $items.Count; $i++) {
        $code = $items[$i].Substring(0, 2)
        $paths = @($items[$i].Substring(3))
        # У переименования за новым путём идёт старый. Проверяются оба: файл,
        # переехавший из данных в служебную папку, иначе выпал бы из архива молча.
        if ($code.Contains('R') -or $code.Contains('C')) {
            $i++
            $paths += $items[$i]
        }
        $counted = @($paths | Where-Object { -not (Test-DevOnly $_) -or ($WithVersionFile -and $_ -ieq $VersionFile) })
        if ($counted.Count -eq 0) { continue }
        if ($code -eq '??') { $untracked += $counted } else { $dirty += $counted }
    }
    Add-ListProblem 'не закоммичено' $dirty
    Add-ListProblem 'не в git и в архив не попадёт — закоммить или внеси в .gitignore' $untracked
}

# =====================================================================
# ЛАУНЧЕР КАК ПРОВЕРЯЮЩИЙ
#
# Архив, версии и адрес манифеста берутся из кода самого лаунчера, а не из
# пересказа его правил: расхождение пересказа с оригиналом и было бы дефектом.
# =====================================================================

function Import-Launcher([byte[]]$Bytes) {
    # Из байтов, а не с диска: exe, загруженный с диска, остаётся занят до
    # закрытия консоли, и пересборка лаунчера падает на записи файла.
    return [Reflection.Assembly]::Load($Bytes).GetType('Launcher', $true)
}

function Get-LauncherConst($Type, [string]$Name) {
    $field = $Type.GetField($Name, [Reflection.BindingFlags]'Public, NonPublic, Static')
    if (-not $field) { return '' }
    return [string]$field.GetRawConstantValue()
}

function Test-Newer([string]$Candidate, [string]$Current) {
    return [bool]$Launcher.GetMethod('IsNewer').Invoke($null, [object[]]@($Candidate, $Current))
}

function Compare-Version([string]$A, [string]$B) {
    return [int]$Launcher.GetMethod('Compare').Invoke($null, [object[]]@($A, $B))
}

# =====================================================================
# АРХИВ
# =====================================================================

function New-ModArchive([string]$ZipPath, [string[]]$Entries) {
    New-Item -ItemType Directory -Force -Path (Split-Path $ZipPath) | Out-Null
    $part = "$ZipPath.part"
    try {
        $fs = [IO.File]::Open($part, [IO.FileMode]::Create)
        try {
            # Кодировка имён не задаётся: .NET пишет кириллицу в UTF-8 с флагом.
            # Такие имена верно читают и лаунчер, и Проводник Windows 10 —
            # измерено 16.09.2026.
            $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create, $false)
            try {
                foreach ($rel in $Entries) {
                    $full = Join-Path $Root $rel
                    $entry = $zip.CreateEntry($rel, [IO.Compression.CompressionLevel]::Optimal)
                    $stamp = [IO.File]::GetLastWriteTime($full)
                    if ($stamp.Year -lt 1980) { $stamp = New-Object DateTime(1980, 1, 1) }
                    $entry.LastWriteTime = [DateTimeOffset]$stamp
                    $out = $entry.Open()
                    try {
                        $in = [IO.File]::OpenRead($full)
                        try { $in.CopyTo($out) } finally { $in.Dispose() }
                    } finally {
                        $out.Dispose()
                    }
                }
            } finally {
                $zip.Dispose()
            }
        } finally {
            $fs.Dispose()
        }
        if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
        [IO.File]::Move($part, $ZipPath)
    } catch {
        if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }
        throw
    }
}

function Read-EntryNames([string]$ZipPath, [int]$CodePage) {
    $names = New-Object 'Collections.Generic.List[string]'
    $fs = [IO.File]::OpenRead($ZipPath)
    try {
        $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Read, $false, [Text.Encoding]::GetEncoding($CodePage))
        foreach ($e in $zip.Entries) {
            if ($e.Name.Length -gt 0) { $names.Add($e.FullName) }
        }
        $zip.Dispose()
    } finally {
        $fs.Dispose()
    }
    return ,$names
}

# Возвращает папку, куда архив распаковал лаунчер, или $null, если до
# распаковки не дошло. Папку удаляет вызывающий.
function Test-Archive([string]$ZipPath, [string]$ExpectedVersion) {
    try {
        # Имена читаются так же, как их прочтёт лаунчер: CP866 там, где
        # у записи нет флага UTF-8.
        $names = Read-EntryNames $ZipPath 866
        $western = Read-EntryNames $ZipPath 437
    } catch {
        Add-Problem "архив не открывается как zip, а лаунчер умеет только zip: $(Get-Reason $_)"
        return $null
    }

    # Имя с флагом UTF-8 одинаково в любой кодировке чтения. Разное прочтение
    # в CP866 и CP437 значит, что флага нет: такое имя верно разложат только
    # лаунчер и Проводник русской Windows, остальные распаковщики — мусором.
    $unflagged = @()
    for ($i = 0; $i -lt $names.Count; $i++) {
        if ($names[$i] -cne $western[$i]) { $unflagged += $names[$i] }
    }
    Add-ListProblem 'имена без флага UTF-8 — верно прочтутся только на русской Windows; собери архив этим скриптом' $unflagged

    foreach ($n in $names) {
        if ($n.Contains('\')) {
            Add-Problem "обратная косая черта в имени записи: $n"
        }
        if ($n.Replace('\', '/').Split('/')[-1] -ieq 'Discipl2Pol_Launcher.exe') {
            Add-Problem "в архиве лаунчер ($n). При обновлении он запущен, Windows не даст писать поверх, и распаковка оборвётся на середине"
        }
    }
    foreach ($required in @($VersionFile, $InfoFile)) {
        if ($names -icontains $required) { continue }
        $nested = @($names | Where-Object { $_.Replace('\', '/').Split('/')[-1] -ieq $required })
        if ($nested.Count -gt 0) {
            Add-Problem "$required лежит не в корне архива, а в $($nested[0]): архив завёрнут в папку, и лаунчер разложит файлы на уровень ниже игры"
        } elseif ($required -eq $InfoFile) {
            Add-Problem "в корне архива нет $required — или имя записано в кодировке, которую лаунчер не читает"
        } else {
            Add-Problem "в корне архива нет $required"
        }
    }
    foreach ($dir in @('Interf/', 'Globals/')) {
        $inside = @($names | Where-Object { $_.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) })
        if ($inside.Count -eq 0) {
            Add-Problem "в корне архива нет папки $dir — раскладка не от папки игры"
        }
    }

    [string]$unpacked = Join-Path ([IO.Path]::GetTempPath()) ('Discipl2Pol_release_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $unpacked | Out-Null
    try {
        [void]$Launcher.GetMethod('UnpackOver').Invoke($null, [object[]]@($ZipPath, $unpacked))
    } catch {
        Add-Problem "лаунчер не смог распаковать архив, игрок увидит «Обновление не установлено»: $(Get-Reason $_)"
        Remove-Item -LiteralPath $unpacked -Recurse -Force
        return $null
    }

    $versionPath = Join-Path $unpacked $VersionFile
    if (Test-Path -LiteralPath $versionPath) {
        $inside = (Read-Text $versionPath).Trim()
        if ($inside -ne $ExpectedVersion) {
            Add-Problem "в $VersionFile внутри архива «$inside», а ожидается $ExpectedVersion"
        }
    }
    return $unpacked
}

function Compare-WithTree([string]$Unpacked, [string[]]$ModFiles) {
    # Путь к временной папке бывает коротким 8.3-именем (USERNA~1), а
    # Get-ChildItem отдаёт длинный — относительный путь отсчитывается от
    # имени самой папки.
    $marker = [IO.Path]::GetFileName($Unpacked) + '\'
    $got = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $Unpacked -Recurse -File -Force)) {
        $at = $f.FullName.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase)
        $got[$f.FullName.Substring($at + $marker.Length).Replace('\', '/')] = $f.FullName
    }
    $missing = @()
    $differ = @()
    foreach ($rel in $ModFiles) {
        if (-not $got.ContainsKey($rel)) {
            $missing += $rel
            continue
        }
        if ((Get-Sha256 (Join-Path $Root $rel)) -ne (Get-Sha256 $got[$rel])) { $differ += $rel }
        $got.Remove($rel)
    }
    $got.Remove($VersionFile)
    $service = @($got.Keys | Where-Object { Test-DevOnly $_ })
    $extra = @($got.Keys | Where-Object { -not (Test-DevOnly $_) })
    Add-ListProblem 'после распаковки лаунчером нет файлов из git' $missing
    Add-ListProblem 'после распаковки файл не совпадает с рабочей папкой' $differ
    Add-ListProblem 'в архиве служебные файлы, игрокам они не нужны' $service
    Add-ListProblem 'в архиве файлы, которых нет среди файлов git' $extra
}

function Test-ArchiveAgainstTree([string]$ZipPath, [string]$ExpectedVersion, [string[]]$ModFiles) {
    $before = $Problems.Count
    $unpacked = Test-Archive $ZipPath $ExpectedVersion
    if (-not $unpacked) { return }
    try {
        # Сверка по файлам имеет смысл только у архива верной формы: у
        # завёрнутого в папку она перечислит всё содержимое и скроет причину.
        if ($Problems.Count -eq $before) { Compare-WithTree $unpacked $ModFiles }
    } finally {
        Remove-Item -LiteralPath $unpacked -Recurse -Force
    }
}

# =====================================================================
# СЕТЬ И МАНИФЕСТ
# =====================================================================

function New-WebClient {
    # Как у лаунчера: TLS 1.2 числом и отказ от кэша — видно то, что увидит игрок.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'Discipl2Pol_release')
    $wc.Headers.Add('Cache-Control', 'no-cache')
    $wc.Encoding = [Text.Encoding]::UTF8
    return $wc
}

# Пустая строка — скачалось, иначе причина.
function Save-Url([string]$Url, [string]$Path) {
    if (-not $Url) { return 'ссылка пустая' }
    $wc = New-WebClient
    try {
        $wc.DownloadFile($Url, $Path)
        return ''
    } catch {
        return (Get-Reason $_)
    } finally {
        $wc.Dispose()
    }
}

function Get-UrlText([string]$Url) {
    $wc = New-WebClient
    try {
        return @{ Text = $wc.DownloadString($Url); Error = '' }
    } catch {
        return @{ Text = ''; Error = (Get-Reason $_) }
    } finally {
        $wc.Dispose()
    }
}

# Разбор тем же JavaScriptSerializer, что у лаунчера.
function ConvertFrom-Manifest([string]$Text, [string]$Where) {
    try {
        $m = (New-Object Web.Script.Serialization.JavaScriptSerializer).DeserializeObject($Text)
    } catch {
        Add-Problem "$Where не разбирается как JSON: $(Get-Reason $_)"
        return $null
    }
    if (-not ($m -is $Dict)) {
        Add-Problem "$Where — не объект JSON"
        return $null
    }
    return ,$m
}

function Get-Field($Manifest, [string]$Section, [string]$Name) {
    if (-not $Manifest -or -not $Manifest.ContainsKey($Section)) { return '' }
    $part = $Manifest[$Section]
    if (-not ($part -is $Dict) -or -not $part.ContainsKey($Name) -or $null -eq $part[$Name]) { return '' }
    return ([string]$part[$Name]).Trim()
}

function Get-ManifestValues($Manifest) {
    $values = @{}
    foreach ($key in $ManifestKeys.Keys) {
        $section, $name = $ManifestKeys[$key].Split('.')
        $values[$key] = Get-Field $Manifest $section $name
    }
    return $values
}

function ConvertTo-JsonString([string]$Text) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($c in $Text.ToCharArray()) {
        if ($c -eq [char]'"') { [void]$sb.Append('\"') }
        elseif ($c -eq [char]'\') { [void]$sb.Append('\\') }
        elseif ([int]$c -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Save-Manifest($Values) {
    $nl = "`n"
    if ((Read-Text $ManifestPath).Contains("`r`n")) { $nl = "`r`n" }
    $lines = @(
        '{',
        '  "launcher": {',
        ('    "version": ' + (ConvertTo-JsonString $Values.LauncherVersion) + ','),
        ('    "url": ' + (ConvertTo-JsonString $Values.LauncherUrl) + ','),
        ('    "notes": ' + (ConvertTo-JsonString $Values.LauncherNotes)),
        '  },',
        '  "mod": {',
        ('    "version": ' + (ConvertTo-JsonString $Values.ModVersion) + ','),
        ('    "url": ' + (ConvertTo-JsonString $Values.ModUrl) + ','),
        ('    "notes": ' + (ConvertTo-JsonString $Values.ModNotes)),
        '  }',
        '}',
        ''
    )
    [IO.File]::WriteAllText($ManifestPath, ($lines -join $nl), (New-Object Text.UTF8Encoding $false))

    # Перечитать тем же разборщиком: ошибка экранирования всплывёт здесь,
    # а не у игроков.
    $again = Get-ManifestValues (ConvertFrom-Manifest (Read-Text $ManifestPath) 'Launcher\latest.json после записи')
    foreach ($key in $ManifestKeys.Keys) {
        if ($again[$key] -cne $Values[$key].Trim()) {
            Add-Problem "Launcher\latest.json после записи читается не так, как записан: $($ManifestKeys[$key])"
        }
    }
}

# =====================================================================
# РЕЖИМЫ
# =====================================================================

$modes = 0
if ($Version) { $modes++ }
if ($Check) { $modes++ }
if ($Verify) { $modes++ }
if ($modes -ne 1) {
    Write-Host 'Нужен ровно один режим:'
    Write-Host '  -Version ДД.ММ.ГГГГ   собрать архив перевода'
    Write-Host '  -Check                проверить выкладку на GitHub'
    Write-Host '  -Verify архив.zip     проверить готовый архив'
    exit 1
}

if (-not (Test-Path -LiteralPath $LauncherExe -PathType Leaf)) {
    Add-Problem "нет $LauncherExe — архив проверяется распаковкой самого лаунчера"
    Stop-OnProblems
}
$Launcher = Import-Launcher ([IO.File]::ReadAllBytes($LauncherExe))

# Адрес манифеста и репозиторий — из самого лаунчера: своей копии у скрипта
# нет, и разойтись с тем, что читают игроки, нечему.
$ManifestUrl = Get-LauncherConst $Launcher 'ManifestUrl'
if ($ManifestUrl -notmatch '^https://raw\.githubusercontent\.com/([^/]+/[^/]+)/') {
    Add-Problem "адрес манифеста в лаунчере не похож на raw-ссылку GitHub: $ManifestUrl"
    Stop-OnProblems
}
$ReleaseBase = "https://github.com/$($Matches[1])/releases/download"

# ---------------------------------------------------------------------
# -Version: сборка
# ---------------------------------------------------------------------

if ($Version) {
    Test-ModVersionDate $Version
    Stop-OnProblems

    $local = ConvertFrom-Manifest (Read-Text $ManifestPath) 'Launcher\latest.json'
    Stop-OnProblems
    $published = Get-Field $local 'mod' 'version'
    if (-not (Test-Newer $Version $published)) {
        Add-Problem "версия $Version не новее опубликованной в Launcher\latest.json ($published): лаунчер её никому не предложит"
    }
    Test-CleanTree
    Stop-OnProblems
    $modFiles = Get-ModFiles
    Stop-OnProblems

    [IO.File]::WriteAllText((Join-Path $Root $VersionFile), "$Version`r`n", (New-Object Text.UTF8Encoding $false))
    $zipPath = Join-Path $DistDir (Get-AssetName $Version)
    New-ModArchive $zipPath (@($modFiles) + $VersionFile)

    Test-ArchiveAgainstTree $zipPath $Version $modFiles
    if ($Problems.Count -gt 0) {
        # Негодный архив не оставлять: его легко выложить по ошибке.
        Remove-Item -LiteralPath $zipPath -Force
        Stop-OnProblems
    }

    $size = '{0:N1}' -f ((Get-Item -LiteralPath $zipPath).Length / 1MB)
    Write-Host ''
    Write-Host 'Архив собран и проверен распаковкой самого лаунчера:'
    Write-Host "  $zipPath"
    Write-Host "  файлов: $($modFiles.Count + 1), размер: $size МБ"
    foreach ($doc in @('README.md', 'Update.md')) {
        if (-not (Read-Text (Join-Path $Root $doc)).Contains($Version)) {
            Write-Host "  в $doc нет даты $Version"
        }
    }
    Write-Host ''
    Write-Host 'Дальше:'
    Write-Host "  1. Закоммить и запушь $VersionFile, дату в README.md и Update.md."
    Write-Host "  2. На GitHub создай релиз с тегом $Version и приложи этот архив, не меняя имени."
    Write-Host '  3. Запусти этот скрипт с -Check.'
    exit 0
}

# ---------------------------------------------------------------------
# -Verify: чужой архив
# ---------------------------------------------------------------------

if ($Verify) {
    if (-not (Test-Path -LiteralPath $Verify -PathType Leaf)) {
        Add-Problem "нет файла $Verify"
        Stop-OnProblems
    }
    $zipPath = (Resolve-Path -LiteralPath $Verify).ProviderPath
    $expected = (Read-Text (Join-Path $Root $VersionFile)).Trim()
    $modFiles = Get-ModFiles
    Test-ArchiveAgainstTree $zipPath $expected $modFiles
    Stop-OnProblems
    Write-Host "Архив годится: лаунчер его распаковывает, содержимое совпадает с рабочей папкой, версия $expected."
    exit 0
}

# ---------------------------------------------------------------------
# -Check: выкладка на GitHub
# ---------------------------------------------------------------------

$work = Join-Path ([IO.Path]::GetTempPath()) ('Discipl2Pol_check_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $fetched = Get-UrlText $ManifestUrl
    if ($fetched.Error) {
        Add-Problem "манифест с GitHub не скачивается: $($fetched.Error)"
        Stop-OnProblems
    }
    $remote = ConvertFrom-Manifest $fetched.Text 'манифест на GitHub'
    $local = ConvertFrom-Manifest (Read-Text $ManifestPath) 'Launcher\latest.json'
    Stop-OnProblems

    $remoteValues = Get-ManifestValues $remote
    $localValues = Get-ManifestValues $local
    # Файл к пушу строится из опубликованного манифеста, а не из локального:
    # уезжают только поля, которые этот прогон сам проверил.
    $values = Get-ManifestValues $remote
    $prepared = @()
    $next = @()

    Write-Host 'Лаунчер'
    $sourceVersion = ''
    if ((Read-Text $LauncherSource) -match 'AppVersion\s*=\s*"([^"]+)"') { $sourceVersion = $Matches[1] }
    $rootVersion = Get-LauncherConst $Launcher 'AppVersion'
    if ($sourceVersion -ne $rootVersion) {
        Add-Problem "в исходнике лаунчера версия $sourceVersion, а Discipl2Pol_Launcher.exe в корне собран как ${rootVersion}: пересобери и положи exe в корень"
    }
    $launcherBlocked = $false
    $manifestLauncher = $remoteValues.LauncherVersion
    $publishedExe = Join-Path $work 'launcher.exe'
    $publishedType = $null
    $err = Save-Url $remoteValues.LauncherUrl $publishedExe
    if ($err) {
        Add-Problem "exe лаунчера по ссылке из манифеста не скачивается: $err"
    } else {
        try {
            $publishedType = Import-Launcher ([IO.File]::ReadAllBytes($publishedExe))
        } catch {
            Add-Problem "по launcher.url лежит не exe лаунчера: $($remoteValues.LauncherUrl). Игроки скачают это вместо лаунчера"
        }
    }
    if ($publishedType) {
        $publishedVersion = Get-LauncherConst $publishedType 'AppVersion'
        $publishedManifest = Get-LauncherConst $publishedType 'ManifestUrl'
        if ($publishedManifest -ne $ManifestUrl) {
            Add-Problem "опубликованный exe читает манифест $publishedManifest, а exe в корне — $ManifestUrl"
        }
        $sameFile = (Get-Sha256 $publishedExe) -eq (Get-Sha256 $LauncherExe)
        $manifestVsPublished = Compare-Version $manifestLauncher $publishedVersion
        $rootVsPublished = Compare-Version $rootVersion $publishedVersion
        if ($manifestVsPublished -gt 0) {
            Add-Problem "манифест обещает лаунчер $manifestLauncher, а по его ссылке лежит ${publishedVersion}: у игроков он будет качаться на каждом запуске, и про перевод их не спросят"
        } elseif ($rootVsPublished -gt 0) {
            $launcherBlocked = $true
            Write-Host "  exe $rootVersion собран, а в main ещё $publishedVersion"
            $next += 'закоммить и запушь Discipl2Pol_Launcher.exe, потом снова -Check (raw отдаёт свежий файл через несколько минут)'
        } elseif ($rootVsPublished -lt 0) {
            Add-Problem "в корне exe $rootVersion, а в main уже ${publishedVersion}: обнови рабочую копию"
        } elseif (-not $sameFile) {
            Add-Problem "exe в корне пересобран, а AppVersion та же (${rootVersion}): если код менялся — подними AppVersion, если нет — верни закоммиченный exe"
        } elseif ($manifestVsPublished -lt 0) {
            Write-Host "  в main лежит exe $publishedVersion, а манифест ещё говорит $manifestLauncher"
            $values.LauncherVersion = $publishedVersion
            $values.LauncherNotes = $localValues.LauncherNotes
            $prepared += 'LauncherVersion', 'LauncherNotes'
        } else {
            Write-Host "  ОК: $publishedVersion, манифест и опубликованный exe сходятся"
        }
    }

    Write-Host 'Перевод'
    $localVersion = (Read-Text (Join-Path $Root $VersionFile)).Trim()
    $manifestMod = $remoteValues.ModVersion
    $publishedZip = Join-Path $work 'mod.zip'
    $cmp = Compare-Version $localVersion $manifestMod
    if ($cmp -lt 0) {
        Add-Problem "$VersionFile ($localVersion) старее перевода, опубликованного в манифесте ($manifestMod)"
    } elseif ($cmp -gt 0 -and $launcherBlocked) {
        # Лаунчер, обновивший себя, про перевод в этот запуск не спрашивает:
        # архив ставит уже новый. Пока нового exe нет в main, ставил бы старый.
        Write-Host "  перевод $localVersion проверю, когда exe лаунчера доедет до main"
    } elseif ($cmp -gt 0) {
        $assetName = Get-AssetName $localVersion
        $assetUrl = Get-AssetUrl $localVersion
        $localZip = Join-Path $DistDir $assetName
        $before = $Problems.Count
        Test-ModVersionDate $localVersion
        if (-not (Test-Path -LiteralPath $localZip)) {
            Add-Problem "нет собранного архива Launcher\dist\$assetName — сначала -Version $localVersion"
        }
        if ($Problems.Count -eq $before) {
            # Архив сверяется и с текущим коммитом: правка, закоммиченная после
            # сборки, иначе в выпуск бы не попала.
            Test-CleanTree -WithVersionFile
            if ($Problems.Count -eq $before) {
                Test-ArchiveAgainstTree $localZip $localVersion (Get-ModFiles)
                if ($Problems.Count -gt $before) {
                    Add-Problem "архив в Launcher\dist не совпадает с текущим коммитом: пересобери (-Version $localVersion) и перезалей ассет"
                }
            }
        }
        if ($Problems.Count -eq $before) {
            $err = Save-Url $assetUrl $publishedZip
            if ($err -and $prepared.Count -gt 0) {
                Write-Host "  ассета $localVersion ещё нет — манифест готовлю только для лаунчера"
            } elseif ($err) {
                Add-Problem "ассет не скачивается: $assetUrl`n      Релиз с тегом $localVersion и файлом $assetName не выложен или назван иначе ($err)"
            } elseif ((Get-Sha256 $publishedZip) -ne (Get-Sha256 $localZip)) {
                Add-Problem "по ссылке ассета лежит не тот файл, что собран в Launcher\dist — перезалей $assetName"
            } else {
                Write-Host "  ОК: ассет $localVersion выложен и совпадает с архивом из текущего коммита"
                $values.ModVersion = $localVersion
                $values.ModUrl = $assetUrl
                if ($localValues.ModVersion -eq $localVersion -and $localValues.ModNotes) {
                    $values.ModNotes = $localValues.ModNotes
                } else {
                    $values.ModNotes = "Перевод от $localVersion."
                }
                $prepared += 'ModVersion', 'ModUrl', 'ModNotes'
            }
        }
    } else {
        $err = Save-Url $remoteValues.ModUrl $publishedZip
        if ($err) {
            Add-Problem "манифест ведёт перевод $manifestMod по ссылке, которая не скачивается: $($remoteValues.ModUrl) ($err)"
        } else {
            $before = $Problems.Count
            $unpacked = Test-Archive $publishedZip $manifestMod
            if ($unpacked) { Remove-Item -LiteralPath $unpacked -Recurse -Force }
            if ($Problems.Count -eq $before) {
                Write-Host "  ОК: $manifestMod, манифест ведёт на архив, который лаунчер распаковывает"
            }
        }
    }

    Stop-OnProblems

    if ($prepared.Count -gt 0) {
        foreach ($key in $ManifestKeys.Keys) {
            if ($prepared -contains $key -or $localValues[$key] -ceq $remoteValues[$key]) { continue }
            Add-Problem "в Launcher\latest.json $($ManifestKeys[$key]) «$($localValues[$key])», а опубликовано «$($remoteValues[$key])». Этот прогон поле не проверял — верни как на GitHub"
        }
        Stop-OnProblems

        $changed = @($ManifestKeys.Keys | Where-Object { $values[$_] -cne $localValues[$_] })
        Write-Host ''
        if ($changed.Count -gt 0) {
            Save-Manifest $values
            Stop-OnProblems
            Write-Host 'Launcher\latest.json подготовлен:'
            foreach ($key in $changed) { Write-Host "  $($ManifestKeys[$key]) = $($values[$key])" }
        } else {
            Write-Host 'Launcher\latest.json уже подготовлен.'
        }
        if ($changed -contains 'ModNotes') {
            Write-Host '  mod.notes игрок увидит в окне обновления — поправь при желании'
        } elseif ($prepared -contains 'ModNotes') {
            Write-Host "  mod.notes игрок увидит в окне обновления: «$($values.ModNotes)» — поправь при желании"
        }
        $next += 'закоммить и запушь Launcher\latest.json, через несколько минут снова -Check (уже запушил — raw ещё отдаёт старый манифест)'
    }

    Write-Host ''
    if ($next.Count -gt 0) {
        Write-Host 'Дальше:'
        foreach ($n in $next) { Write-Host "  $n" }
    } else {
        Write-Host 'Всё сходится: игроки с лаунчером получат опубликованное при следующем запуске.'
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
exit 0
