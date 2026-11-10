#!/usr/bin/env python3
"""Sucht das Audiomuster der bekannten alten MKV-Zusammenfuehrung.

Python 3.8+ und ffprobe im PATH; keine weiteren Python-Pakete erforderlich.

Beispiel:
  python3 find_old_movie_outputs.py /pfad/Filme --report altversion.tsv

Das alte Kommando kodierte die erste Audiospur als AAC. Fuer weitere
Audiospuren war kein Codec angegeben; der damalige Matroska/FFmpeg-Build
verwendete Vorbis. Die beiden bekannten alten Beispiele enthalten deshalb
deutsches AAC und englisches Vorbis mit einem libvorbis-Encoder-Tag.

ALTVERSION_MUSTER:
  Matroska, erste Audiospur AAC/deutsch, zweite Audiospur Vorbis/englisch,
  alle weiteren Audiospuren ebenfalls Vorbis; deren Encoder-Tags enthalten
  libvorbis. Passt zum alten Kommando und den bekannten Beispielen.
VORBIS_PRUEFEN:
  Mindestens eine Vorbis-Audiospur, aber nicht das vollstaendige Muster.
KEIN_MUSTER:
  Kein Vorbis gefunden; keine Aussage ueber Abspielbarkeit oder Skriptversion.
PRUEFFEHLER:
  ffprobe konnte keine fehlerfreien Metadaten liefern, etwa wegen eines
  Lesefehlers, Zeitlimits oder ungueltiger Datei.

WICHTIG: Dies ist eine Herkunfts-Heuristik, kein Plex-Kompatibilitaetstest.
Auch eine neue Zusammenfuehrung kann das Muster haben, wenn schon ihre
Eingabespur Vorbis mit denselben Tags enthielt. Spaeter neu kodierte Dateien
oder Ausgaben anderer Container/FFmpeg-Builds koennen dem Muster entgehen.
Ein abgespielter Browserfehler ist daraus weder bewiesen noch ausgeschlossen.
Der grosse Paket-Zeitstempelruecksprung unterschied alt/neu hier NICHT.

Es werden Spur-/Containerinformationen abgefragt, keine Filme vollstaendig
dekodiert und keine Originaldateien geaendert. Der TSV-Bericht enthaelt ALLE
Dateien samt Audioinfos, Begruendung und eventuellen Prueffehlern. Auf der
Konsole erscheinen Kandidaten und Fehler. Vorhandene Berichte werden nicht
ueberschrieben. Unterordner werden durchsucht, Verzeichnis-Symlinks nicht.

Exit-Code: 0 = keine Kandidaten, 1 = Kandidaten gefunden, 2 = Prueffehler,
130 = abgebrochen (bereits geschriebener Teilbericht bleibt erhalten).
"""

import argparse
import csv
import datetime
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


EXTENSIONS = {".mkv", ".mp4", ".m4v", ".avi", ".mov", ".m2ts", ".ts"}
GERMAN = {"ger", "deu", "de"}
ENGLISH = {"eng", "en"}
FIELDS = ["status", "datei", "container", "muxer_encoder", "audio", "begruendung"]


def tag(tags, name, default=""):
    return next((str(value) for key, value in (tags or {}).items()
                 if key.lower() == name), default)


def classify(metadata):
    fmt = metadata.get("format", {})
    audio = []
    for stream in metadata.get("streams", []):
        if stream.get("codec_type", "audio") != "audio":
            continue
        audio.append({
            "index": int(stream["index"]),
            "codec": str(stream.get("codec_name", "unbekannt")).lower(),
            "sprache": tag(stream.get("tags"), "language", "und").lower(),
            "encoder": tag(stream.get("tags"), "encoder"),
            "kanaele": stream.get("channels"),
        })
    audio.sort(key=lambda stream: stream["index"])
    container = fmt.get("format_name", "")
    status = "KEIN_MUSTER"
    reason = "Keine Vorbis-Audiospur; Skriptversion und Abspielbarkeit nicht bestimmt."
    if any(stream["codec"] == "vorbis" for stream in audio):
        status = "VORBIS_PRUEFEN"
        reason = "Vorbis vorhanden, aber nicht das vollstaendige alte Beispielmuster."
        if ("matroska" in container.split(",") and len(audio) >= 2
                and audio[0]["codec"] == "aac"
                and audio[0]["sprache"] in GERMAN
                and audio[1]["sprache"] in ENGLISH
                and all(stream["codec"] == "vorbis" for stream in audio[1:])
                and all("libvorbis" in stream["encoder"].lower()
                        for stream in audio[1:])):
            status = "ALTVERSION_MUSTER"
            reason = ("Matroska; zuerst deutsches AAC, dann englisches Vorbis; "
                      "alle folgenden Audiospuren Vorbis mit libvorbis-Encoder-Tag. "
                      "Starker Herkunftshinweis, kein Abspielfehlernachweis.")
    return {
        "status": status, "container": container,
        "muxer_encoder": tag(fmt.get("tags"), "encoder"),
        "audio": json.dumps(audio, ensure_ascii=False, separators=(",", ":")),
        "begruendung": reason,
    }

def inspect(path, ffprobe, timeout):
    command = [
        ffprobe, "-v", "error", "-select_streams", "a", "-show_entries",
        "stream=index,codec_type,codec_name,channels:stream_tags=language,encoder:"
        "format=format_name:format_tags=encoder", "-of", "json", str(path),
    ]
    result = subprocess.run(command, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            encoding="utf-8", errors="replace", timeout=timeout)
    if result.returncode or result.stderr.strip():
        raise RuntimeError(result.stderr.strip()[:4000]
                           or "ffprobe Exit-Code {}".format(result.returncode))
    metadata = json.loads(result.stdout)
    if not metadata.get("format", {}).get("format_name"):
        raise ValueError("Keine Containerinformationen von ffprobe erhalten.")
    return classify(metadata)


def discover(paths):
    files = set()

    def walk_error(error):
        raise error

    for raw in paths:
        path = Path(raw).expanduser().absolute()
        if path.is_file():
            if not path.name.startswith("._"):
                files.add(path.resolve())
        elif path.is_dir():
            for directory, dirs, names in os.walk(path, onerror=walk_error,
                                                   followlinks=False):
                dirs.sort()
                for name in names:
                    item = Path(directory) / name
                    if (not name.startswith("._")
                            and item.suffix.lower() in EXTENSIONS and item.is_file()):
                        files.add(item.resolve())
        else:
            raise ValueError("Datei oder Ordner existiert nicht: {}".format(path))
    return sorted(files)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", help="Filmdateien oder Filmordner (rekursiv)")
    parser.add_argument("--report", type=Path, help="Neuer TSV-Bericht")
    parser.add_argument("--timeout", type=float, default=60,
                        help="Zeitlimit pro ffprobe-Aufruf in Sekunden (Standard: 60)")
    args = parser.parse_args(argv)
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout muss eine positive endliche Zahl sein.")
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        parser.error("ffprobe wurde nicht im PATH gefunden.")
    try:
        files = discover(args.paths)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    if not files:
        parser.error("Keine passenden Filmdateien gefunden.")
    report = (args.report or Path("altversion-{}.tsv".format(
        datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")))).expanduser().absolute()
    # resolve() also catches a report path that is a symlink to an input file.
    if report.resolve() in files:
        parser.error("Der Bericht darf keine Eingabedatei ersetzen.")
    try:
        output = report.open("x", encoding="utf-8", errors="backslashreplace", newline="")
    except OSError as error:
        parser.error("Bericht kann nicht neu angelegt werden: {}".format(error))
    counts = {key: 0 for key in ("ALTVERSION_MUSTER", "VORBIS_PRUEFEN",
                                 "KEIN_MUSTER", "PRUEFFEHLER")}
    last_progress = 0.0
    try:
        with output:
            writer = csv.DictWriter(output, delimiter="\t", fieldnames=FIELDS)
            writer.writeheader()
            output.flush()
            for number, path in enumerate(files, 1):
                now = time.monotonic()
                if number == 1 or number % 50 == 0 or now - last_progress >= 5:
                    print("[{}/{}] Pruefe {}".format(number, len(files),
                          json.dumps(str(path), ensure_ascii=False)),
                          file=sys.stderr, flush=True)
                    last_progress = now
                try:
                    row = inspect(path, ffprobe, args.timeout)
                except subprocess.TimeoutExpired:
                    row = {"status": "PRUEFFEHLER", "begruendung":
                           "ffprobe-Zeitlimit nach {} Sekunden erreicht.".format(args.timeout)}
                except (OSError, RuntimeError, ValueError, TypeError, KeyError) as error:
                    row = {"status": "PRUEFFEHLER", "begruendung": str(error)[:4000]}
                row["datei"] = str(path)
                counts[row["status"]] += 1
                writer.writerow(row)
                output.flush()
                if row["status"] != "KEIN_MUSTER":
                    print("{}\t{}".format(row["status"],
                          json.dumps(str(path), ensure_ascii=False)), flush=True)
    except KeyboardInterrupt:
        print("\nAbgebrochen. Teilbericht: {}".format(report), file=sys.stderr)
        return 130
    print("\n{} Dateien: {} Altversion-Muster, {} weitere Vorbis-Kandidaten, "
          "{} ohne Muster, {} Prueffehler. Bericht: {}".format(
              len(files), counts["ALTVERSION_MUSTER"], counts["VORBIS_PRUEFEN"],
              counts["KEIN_MUSTER"], counts["PRUEFFEHLER"], report))
    return 2 if counts["PRUEFFEHLER"] else (1 if counts["ALTVERSION_MUSTER"]
                                           or counts["VORBIS_PRUEFEN"] else 0)


if __name__ == "__main__":
    sys.exit(main())

