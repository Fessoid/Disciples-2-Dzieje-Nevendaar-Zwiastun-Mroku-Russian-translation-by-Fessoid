# -*- coding: utf-8 -*-
"""Discipl2Pol_Launcher — запуск игры и обновление перевода.

Лежит в папке с игрой рядом с Discipl2.exe. Запускает игру и смотрит манифест
в репозитории перевода.

Себя обновляет молча: человек ничего не нажимает и ничего не замечает — новый
файл встаёт на место после выхода лаунчера.

Про перевод спрашивает: архив ставится поверх игры, и ради этого игру надо
закрыть — такое без согласия не делают.

Всё остальное молча: нет сети, нет ответа, сменился формат манифеста — игра
уже запущена и об этом не знает.

Сборка одной строкой из папки Launcher:

    pyinstaller --onefile --windowed --icon launcher.ico ^
        --name Discipl2Pol_Launcher --exclude-module tkinter ^
        --exclude-module unittest --exclude-module pydoc ^
        discipl2pol_launcher.py

Готовый exe появится в папке dist. Версия ниже должна совпадать с той, что
уходит в манифест: по ней лаунчер и решает, обновляться ему или нет.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

APP_NAME = "Discipl2Pol_Launcher"
APP_VERSION = "1.0"

# Манифест, а не /releases/latest: релизы этого репозитория — это релизы
# перевода с тегами-датами, версия лаунчера в такой ряд не встаёт. Здесь же
# лежит и версия перевода.
MANIFEST_URL = (
    "https://raw.githubusercontent.com/Fessoid/"
    "Disciples-2-Dzieje-Nevendaar-Zwiastun-Mroku-Russian-translation-by-Fessoid"
    "/main/Launcher/latest.json"
)

# Основное имя — из установки мода; запасное встречается в других сборках игры.
GAME_EXE_NAMES = ("Discipl2.exe", "Disciple.exe")

# Файл рядом с игрой: какая версия перевода стоит. Едет внутри архива, поэтому
# после ручной установки обновления версия оказывается верной сама собой.
MOD_VERSION_FILE = "Discipl2Pol_version.txt"

# Куда отправлять человека, если он отказался или скачать не вышло.
MOD_INFO_FILE = "!ОСОБЕННОСТИ МОДА.txt"

MANIFEST_TIMEOUT = 5
DOWNLOAD_TIMEOUT = 600


# =============================================================================
# ПУТИ
# =============================================================================

def app_dir():
    """Папка, из которой запущен лаунчер (для onefile-exe — папка с exe)."""
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


def running_as_exe():
    return bool(getattr(sys, "frozen", False))


def state_path():
    """Файл состояния — в %LOCALAPPDATA%, чтобы не сорить в папке игры."""
    base = os.environ.get("LOCALAPPDATA") or tempfile.gettempdir()
    return os.path.join(base, APP_NAME, "state.json")


def temp_dir():
    """Своя подпапка во временных, а не их корень.

    В корне %TEMP% файлы легко попадают под чужие правила: переименование
    там может быть запрещено политикой или песочницей, тогда как запись
    проходит — и загрузка падает уже на последнем шаге. В своей подпапке
    таких сюрпризов нет, и убирать за собой проще.
    """
    path = os.path.join(tempfile.gettempdir(), APP_NAME)
    try:
        os.makedirs(path, exist_ok=True)
    except OSError:
        return tempfile.gettempdir()
    return path


# =============================================================================
# ЗАПУСК И ЗАКРЫТИЕ ИГРЫ
#
# Запуск делается первым и без ожидания: проверка обновлений не должна стоять
# на пути к игре. Дальше лаунчер живёт своей жизнью.
# =============================================================================

def find_game(folder):
    for name in GAME_EXE_NAMES:
        path = os.path.join(folder, name)
        if os.path.isfile(path):
            return path
    return None


def start_game(folder):
    """True, если игра запущена. Иначе показывает ошибку — это тот случай,
    когда молчать нельзя: человек нажал на лаунчер и ничего не произошло."""
    game = find_game(folder)
    if not game:
        show_error(
            "Игра не найдена",
            "Рядом с лаунчером нет %s.\n\n"
            "Положите %s.exe в папку с игрой." % (
                " и ".join(GAME_EXE_NAMES), APP_NAME))
        return False
    try:
        subprocess.Popen([game], cwd=folder, close_fds=True)
    except OSError as exc:
        show_error("Не удалось запустить игру", "%s\n\n%s" % (game, exc))
        return False
    return True


def close_game():
    """Закрывает игру по имени процесса, а не по своему потомку: игра
    запускается через обёртку, и настоящий процесс лаунчеру не принадлежит."""
    for name in GAME_EXE_NAMES:
        try:
            subprocess.run(["taskkill", "/f", "/im", name],
                           capture_output=True, creationflags=no_window())
        except OSError:
            pass


def no_window():
    return getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0


# =============================================================================
# ОКНА
#
# Своего интерфейса у лаунчера нет — только системные окна, и только там, где
# без человека не обойтись. Берутся напрямую из user32, а не через tkinter:
# tkinter тянет в сборку tcl/tk, а это половина размера exe и заметная пауза
# на распаковку при каждом запуске — на пути к игре платить за это нечем.
# =============================================================================

MB_OK = 0x00000000
MB_YESNO = 0x00000004
MB_ICONERROR = 0x00000010
MB_ICONQUESTION = 0x00000020
MB_ICONINFORMATION = 0x00000040
MB_SETFOREGROUND = 0x00010000
# Игра полноэкранная — окну нужен WS_EX_TOPMOST, иначе оно уедет под неё.
# Даёт его MB_SYSTEMMODAL, а не MB_TOPMOST: измерено на Windows 10 21H2,
# с MB_TOPMOST стиль окна остаётся 0x10101 без бита 0x8. Документация обещает
# этот стиль обоим флагам — верно измерение.
MB_SYSTEMMODAL = 0x00001000
ID_YES = 6


def _dialog(flags, title, text):
    try:
        import ctypes
        user32 = ctypes.windll.user32
    except (ImportError, AttributeError):
        return 0
    return user32.MessageBoxW(
        None, str(text), "%s — %s" % (APP_NAME, title),
        flags | MB_SETFOREGROUND | MB_SYSTEMMODAL)


def ask_yes_no(title, text):
    return _dialog(MB_YESNO | MB_ICONQUESTION, title, text) == ID_YES


def show_error(title, text):
    _dialog(MB_OK | MB_ICONERROR, title, text)


def show_info(title, text):
    _dialog(MB_OK | MB_ICONINFORMATION, title, text)


# =============================================================================
# ВЕРСИИ
#
# Два разных ряда: у лаунчера «1.0», у перевода дата. Сравниваются оба
# кортежами чисел, но дата приводится к (год, месяц, день) — иначе 31.07.2026
# окажется «новее», чем 01.08.2026.
# =============================================================================

def parse_version(value):
    """Кортеж для сравнения. Мусор даёт пустой кортеж, а не исключение."""
    text = str(value or "").strip().lstrip("vV")
    if not text:
        return ()

    if "-" in text:                              # 2026-08-31
        parts = text.split("-")
        if len(parts) == 3 and parts[0].isdigit() and len(parts[0]) == 4:
            try:
                return tuple(int(p) for p in parts)
            except ValueError:
                return ()

    parts = text.split(".")
    # 31.07.2026 и 31.07.26 — дата: последняя часть длиннее двух цифр либо
    # первая больше 12. Версия «1.2.3» под это не подходит и разбирается ниже.
    if len(parts) == 3 and all(p.isdigit() for p in parts):
        day, month, year = int(parts[0]), int(parts[1]), int(parts[2])
        if len(parts[2]) == 4 or day > 12:
            if len(parts[2]) == 2:
                year += 2000
            return (year, month, day)

    numbers = []
    for chunk in parts:
        digits = "".join(c for c in chunk if c.isdigit())
        if not digits:
            break
        numbers.append(int(digits))
    return tuple(numbers)


def is_newer(candidate, current):
    a = parse_version(candidate)
    b = parse_version(current)
    return bool(a) and a > b


# =============================================================================
# СОСТОЯНИЕ
# =============================================================================

def load_state():
    try:
        with open(state_path(), "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(state):
    path = state_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
    except OSError:
        pass


def installed_mod_version(folder):
    try:
        with open(os.path.join(folder, MOD_VERSION_FILE), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def write_mod_version(folder, version):
    try:
        with open(os.path.join(folder, MOD_VERSION_FILE), "w",
                  encoding="utf-8") as f:
            f.write(version + "\n")
    except OSError:
        pass


# =============================================================================
# МАНИФЕСТ И ЗАГРУЗКА
# =============================================================================

def fetch_manifest():
    req = urllib.request.Request(MANIFEST_URL, headers={
        "User-Agent": "%s/%s" % (APP_NAME, APP_VERSION),
        "Accept": "application/json",
        # raw.githubusercontent отдаёт из CDN; без этого можно получить
        # вчерашний манифест сразу после публикации нового.
        "Cache-Control": "no-cache",
    })
    with urllib.request.urlopen(req, timeout=MANIFEST_TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def download_file(url, dest_path):
    """Качает во временное имя и переименовывает: обрыв связи не оставит
    рядом с игрой недокачанный файл."""
    tmp_path = dest_path + ".part"
    req = urllib.request.Request(url, headers={
        "User-Agent": "%s/%s" % (APP_NAME, APP_VERSION),
    })
    try:
        with urllib.request.urlopen(req, timeout=DOWNLOAD_TIMEOUT) as resp:
            with open(tmp_path, "wb") as f:
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    f.write(chunk)
        os.replace(tmp_path, dest_path)
    except Exception:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise
    return dest_path


# =============================================================================
# САМОЗАМЕНА
#
# Запущенный exe себя не перезапишет. Файл подменяет .cmd: он ждёт, пока
# лаунчер завершится и отпустит файл, переносит новую версию на место старой
# и стирает сам себя.
#
# Пути передаются аргументами, а не пишутся в тело файла. Причина — кодировка:
# cmd.exe читает .bat в OEM-кодировке консоли, и путь с кириллицей (папка
# игры, имя пользователя в %TEMP%) в теле файла превратится в мусор. Аргументы
# идут через CreateProcess в UTF-16 и не портятся. Поэтому сам .cmd — ASCII.
# =============================================================================

UPDATE_CMD = "\r\n".join([
    "@echo off",
    'set "TARGET=%~1"',
    'set "SOURCE=%~2"',
    "set /a TRIES=0",
    ":retry",
    "set /a TRIES+=1",
    'move /y "%SOURCE%" "%TARGET%" >nul 2>&1',
    "if not errorlevel 1 goto done",
    # ~60 секунд ожидания: файл держит не только сам лаунчер, но и антивирус,
    # который проверяет свежескачанный exe.
    "if %TRIES% geq 60 goto giveup",
    "ping -n 2 127.0.0.1 >nul",
    "goto retry",
    ":giveup",
    'del /f /q "%SOURCE%" >nul 2>&1',
    ":done",
    'del /f /q "%~f0" >nul 2>&1',
    "",
])


def schedule_replace(target_path, source_path):
    """Ставит подмену в очередь и возвращает True, если процесс запущен."""
    cmd_path = os.path.join(temp_dir(), "update.cmd")
    try:
        with open(cmd_path, "w", encoding="ascii", newline="") as f:
            f.write(UPDATE_CMD)
    except OSError:
        return False

    creation = 0
    startupinfo = None
    if os.name == "nt":
        creation = (getattr(subprocess, "DETACHED_PROCESS", 0)
                    | getattr(subprocess, "CREATE_NO_WINDOW", 0))
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startupinfo.wShowWindow = 0          # SW_HIDE
    try:
        subprocess.Popen(
            ["cmd.exe", "/c", cmd_path, target_path, source_path],
            creationflags=creation, startupinfo=startupinfo, close_fds=True)
    except OSError:
        return False
    return True


# =============================================================================
# ОБНОВЛЕНИЕ ЛАУНЧЕРА — без единого окна
#
# Спрашивать не о чем: файл меняется сам на себя, игра не трогается, человек
# ничего не теряет. Любая осечка — молчание, следующий запуск попробует снова.
# =============================================================================

def self_update(entry):
    """Качает новую версию и возвращает (куда, откуда) для подмены.

    Подмену НЕ запускает: помощник ждёт выхода лаунчера ограниченное время,
    а после этой функции может открыться окно про перевод и провисеть у
    человека сколько угодно. Поэтому подмена ставится последним действием
    в main, перед самым выходом.
    """
    version = str(entry.get("version") or "").strip()
    url = str(entry.get("url") or "").strip()
    if not is_newer(version, APP_VERSION) or not url or not running_as_exe():
        return None

    target = os.path.abspath(sys.executable)
    source = target + ".new"
    try:
        download_file(url, source)
    except Exception:
        return None
    return target, source


# =============================================================================
# ОБНОВЛЕНИЕ ПЕРЕВОДА — с вопросом
#
# Здесь без человека нельзя: архив ложится поверх файлов игры, а для этого
# игру надо закрыть. Отказ запоминается, чтобы про ту же версию не спрашивать
# при каждом запуске.
# =============================================================================

def unpack_over(zip_path, folder):
    """Распаковывает архив поверх папки игры.

    Пути из архива проверяются: он приехал из сети, и запись за пределы папки
    игры — не то, что должно получиться из обновления перевода.
    """
    folder = os.path.abspath(folder)
    with zipfile.ZipFile(zip_path) as zf:
        for member in zf.infolist():
            name = member.filename.replace("\\", "/")
            if name.startswith("/") or ".." in name.split("/"):
                raise ValueError("небезопасный путь в архиве: %s" % name)
            dest = os.path.abspath(os.path.join(folder, name))
            if dest != folder and not dest.startswith(folder + os.sep):
                raise ValueError("путь ведёт за пределы папки: %s" % name)
            if member.is_dir():
                os.makedirs(dest, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with zf.open(member) as src, open(dest, "wb") as out:
                shutil.copyfileobj(src, out)


def mod_update(entry, folder):
    version = str(entry.get("version") or "").strip()
    url = str(entry.get("url") or "").strip()
    installed = installed_mod_version(folder)

    # Файла с версией нет — значит перевод ставили руками до появления
    # лаунчера. Записываем текущую и молчим: предлагать переустановить то,
    # что человек только что распаковал, незачем.
    if not installed:
        write_mod_version(folder, version or "")
        return

    if not is_newer(version, installed):
        return

    state = load_state()
    if not is_newer(version, state.get("skipped_mod_version", "")):
        return

    notes = str(entry.get("notes") or "").strip()
    text = "Вышла новая версия перевода: %s.\nУ вас стоит %s.\n\n" % (
        version, installed)
    if notes:
        text += notes + "\n\n"
    # Игра закрывается принудительно, поэтому про несохранённую партию нужно
    # сказать до вопроса, а не после.
    text += ("Для установки игра будет закрыта.\n"
             "Несохранённая партия пропадёт.\n\nОбновить сейчас?")

    if not ask_yes_no("Обновление перевода", text):
        state["skipped_mod_version"] = version
        save_state(state)
        show_info("Обновление пропущено",
                  "Версия перевода %s будет пропущена — больше о ней "
                  "не спросим.\n\n"
                  "Скачать её самостоятельно можно по ссылке из файла\n"
                  "«%s» в папке с игрой." % (version, MOD_INFO_FILE))
        return

    if not url:
        show_error("Обновление недоступно",
                   "Ссылка на архив не указана.\n\n"
                   "Скачать перевод можно по ссылке из файла\n"
                   "«%s» в папке с игрой." % MOD_INFO_FILE)
        return

    close_game()
    archive = os.path.join(temp_dir(), "mod_%s.zip" % version)
    try:
        download_file(url, archive)
        unpack_over(archive, folder)
    except Exception as exc:
        show_error("Обновление не установлено",
                   "%s\n\nИгра сейчас запустится в прежнем виде.\n"
                   "Скачать перевод вручную можно по ссылке из файла\n"
                   "«%s» в папке с игрой." % (exc, MOD_INFO_FILE))
        start_game(folder)
        return
    finally:
        try:
            os.remove(archive)
        except OSError:
            pass

    write_mod_version(folder, version)
    show_info("Перевод обновлён",
              "Установлена версия %s.\n\nИгра сейчас запустится." % version)
    start_game(folder)


# =============================================================================
# ПРОВЕРКА
# =============================================================================

def check_updates(folder):
    """Возвращает (куда, откуда) для подмены лаунчера или None."""
    try:
        manifest = fetch_manifest()
    except Exception:
        return None                           # нет сети, нет ответа — молчим
    if not isinstance(manifest, dict):
        return None

    pending = None
    launcher = manifest.get("launcher")
    if isinstance(launcher, dict):
        try:
            pending = self_update(launcher)
        except Exception:
            pending = None                    # своя осечка мод не задевает

    mod = manifest.get("mod")
    if isinstance(mod, dict):
        mod_update(mod, folder)
    return pending


def main():
    folder = app_dir()
    started = start_game(folder)
    pending = None
    try:
        pending = check_updates(folder)
    except Exception:
        pass                                   # проверка не мешает игре
    if pending:
        schedule_replace(*pending)             # последним действием, см. self_update
    return 0 if started else 1


if __name__ == "__main__":
    sys.exit(main())
