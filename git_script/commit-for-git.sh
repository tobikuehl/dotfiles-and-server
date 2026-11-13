#!/bin/bash
# Version 5.0
# Von einem Dotfile-Repo aus einsetzbar (Symlink-sicher)
# Unterordner werden besser unterstützt
set -e

# --- KONFIGURATION ---
FILE_ACTION="cp -p" # Entweder "cp -p" oder "mv"
### --- ENDE der Konfiguration --- ###

# Eigenen Pfad (inkl. Symlinks auflösen) merken
SELF_PATH="$(readlink -f "${BASH_SOURCE}")"

# --- PARAMETER-AUSLESE & VALIDIERUNG ---
if [ "$#" -lt 2 ]; then
    echo "❌ Fehler: Bitte Zieldatei und mindestens eine Quelldatei übergeben!"
    echo "Verwendung: $(basename "$0") <pfad/zur/zieldatei> <quelldatei1> [quelldatei2 ...]"
    exit 1
fi

# Ziel-Ordner und Ziel-Dateiname aus $1 ermitteln
TARGET_INPUT="$1"
TARGET_DIR_RAW="$(dirname -- "$TARGET_INPUT")"
TARGET_FILENAME="$(basename -- "$TARGET_INPUT")"
TARGET_BASENAME="${TARGET_FILENAME%.*}"

if [ ! -d "$TARGET_DIR_RAW" ]; then
    echo "❌ Fehler: Zielverzeichnis '$TARGET_DIR_RAW' existiert nicht."
    exit 1
fi

# Absoluten Pfad des Zielverzeichnisses und das zugehörige Git-Repo ermitteln
ABS_TARGET_DIR="$(cd "$TARGET_DIR_RAW" && pwd)"
REPO_DIR="$(git -C "$ABS_TARGET_DIR" rev-parse --show-toplevel 2>/dev/null || true)"

if [ -z "$REPO_DIR" ]; then
    echo "❌ Fehler: '$ABS_TARGET_DIR' liegt in keinem Git-Repository!"
    exit 1
fi

# Relativen Pfad der Zieldatei innerhalb des Repos bestimmen (funktioniert auch für Unterordner!)
ABS_TARGET_FILE="$ABS_TARGET_DIR/$TARGET_FILENAME"
REL_TARGET_FILE="${ABS_TARGET_FILE#$REPO_DIR/}"

# Sicherheitscheck: Verhindern, dass das Skript sich selbst überschreibt
if [ "$ABS_TARGET_FILE" = "$SELF_PATH" ]; then
    echo "❌ Fehler: Die Zieldatei darf nicht das Skript selbst sein!"
    exit 1
fi

shift

VALID_FILES=()

for f in "$@"; do
    if [ -d "$f" ]; then
        continue
    fi
    if [ ! -f "$f" ]; then
        echo "❌ Fehler: Quelldatei '$f' existiert nicht."
        exit 1
    fi
    ABS_F="$(readlink -f "$f")"
    if [ "$ABS_F" = "$SELF_PATH" ]; then
        continue
    fi
    VALID_FILES+=("$ABS_F")
done

if [ "${#VALID_FILES[@]}" -eq 0 ]; then
    echo "❌ Fehler: Keine gültigen Quelldateien gefunden."
    exit 1
fi

BATCH_MODE=false
if [ "${#VALID_FILES[@]}" -gt 1 ]; then
    BATCH_MODE=true
    echo "📦 Batch-Modus erkannt (${#VALID_FILES[@]} Dateien) für Repo: $REPO_DIR"
fi

# --- CHRONOLOGISCHE SORTIERUNG ---
mapfile -d '' SORTED_FILES < <(
    for f in "${VALID_FILES[@]}"; do
        printf "%s\t%s\0" "$(stat -c %Y "$f")" "$f"
    done | sort -z -n | cut -z -f2-
)

# --- VERARBEITUNG ---
for ABS_SOURCE_FILE in "${SORTED_FILES[@]}"; do
    SOURCE_FILENAME=$(basename -- "$ABS_SOURCE_FILE")
    DATE=$(date -r "$ABS_SOURCE_FILE" -Iseconds)

    echo "-----------------------------------------"
    echo "📂 Repo:   $(basename "$REPO_DIR")"
    echo "🎯 Ziel:   $REL_TARGET_FILE"
    echo "📄 Quelle: $SOURCE_FILENAME"
    echo "📅 Datum:  $DATE"

    # Datei kopieren oder verschieben
    $FILE_ACTION "$ABS_SOURCE_FILE" "$ABS_TARGET_FILE"

    # Direkt im gefundenen Git-Repo arbeiten
    cd "$REPO_DIR"
    git add "$REL_TARGET_FILE"

    if git diff --cached --quiet; then
        echo "⏭️  Übersprungen: Inhalt ist identisch zum letzten Commit."
        continue
    fi

    DIFF_STAT=$(git diff --cached --shortstat | xargs)
    CHANGED_FUNCS=$(git diff --cached -U0 | grep -E "^@@.*@@ (def |[a-zA-Z0-9_]+\s*\(\))" | sed -E 's/^@@.*@@ (def )?([a-zA-Z0-9_]+).*/\2/' | sort -u | paste -sd ", " -)

    AUTO_DETAILS="$DIFF_STAT"
    if [ -n "$CHANGED_FUNCS" ]; then
        AUTO_DETAILS="$AUTO_DETAILS | Funktionen: $CHANGED_FUNCS"
    fi

    if [ "$BATCH_MODE" = true ]; then
        COMMIT_MSG="Debug iteration: '${TARGET_BASENAME} (${SOURCE_FILENAME})' [${AUTO_DETAILS}]"
    else
        echo "💬 Commit-Kommentar (ENTER für automatisch):"
        read -r COMMIT_MSG
        if [ -z "$COMMIT_MSG" ]; then
            COMMIT_MSG="Debug iteration: '${TARGET_BASENAME} (${SOURCE_FILENAME})' [${AUTO_DETAILS}]"
        fi
    fi

    GIT_AUTHOR_DATE="$DATE" GIT_COMMITTER_DATE="$DATE" git commit -m "$COMMIT_MSG"
    echo "✅ Committet: $COMMIT_MSG"
done

echo "-----------------------------------------"
echo "🎉 Fertig!"
