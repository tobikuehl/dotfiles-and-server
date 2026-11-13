#!/bin/bash
# Version 4.0
# Target-File wird zum Parameter, ist nicht mehr in der Konfiguration
set -e

# --- KONFIGURATION ---
FILE_ACTION="cp -p" # Entweder "cp -p" oder "mv"
### --- ENDE der Konfiguration --- ###

# --- SELF ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
SELF_PATH="$REPO_DIR/$(basename "${BASH_SOURCE}")"

# --- PARAMETER-AUSLESE & VALIDIERUNG ---
if [ "$#" -lt 2 ]; then
    echo "❌ Fehler: Bitte Zieldatei und mindestens eine Quelldatei übergeben!"
    echo "Verwendung: $0 <zieldatei_im_repo> <quelldatei1> [quelldatei2 ...]"
    echo "Beispiel:   $0 4_cohens_rmse.py /tmp/backups/*.py"
    exit 1
fi

# Erstes Argument ist die Zieldatei (nur Dateiname ohne eventuellen Pfad)
TARGET_FILE=$(basename -- "$1")
TARGET_BASENAME="${TARGET_FILE%.*}"

# Sicherheitscheck: Verhindern, dass das Skript sich selbst überschreibt
if [ "$REPO_DIR/$TARGET_FILE" = "$SELF_PATH" ]; then
    echo "❌ Fehler: Die Zieldatei darf nicht das Skript selbst sein!"
    exit 1
fi

# Erstes Argument ($1) entfernen, damit in "$@" nur noch die Quelldateien übrig bleiben
shift

VALID_FILES=()

for f in "$@"; do
    # 1. Unterordner stillschweigend überspringen
    if [ -d "$f" ]; then
        continue
    fi
    # 2. Prüfen, ob reguläre Datei existiert
    if [ ! -f "$f" ]; then
        echo "❌ Fehler: Quelldatei '$f' existiert nicht."
        exit 1
    fi
    # 3. Das Skript selbst überspringen, falls es per '*' erfasst wurde
    ABS_F="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    if [ "$ABS_F" = "$SELF_PATH" ]; then
        continue
    fi

    VALID_FILES+=("$f")
done

if [ "${#VALID_FILES[@]}" -eq 0 ]; then
    echo "❌ Fehler: Keine gültigen Quelldateien gefunden."
    exit 1
fi

# Batch-Modus aktivieren, wenn mehr als 1 Quelldatei übergeben wurde
BATCH_MODE=false
if [ "${#VALID_FILES[@]}" -gt 1 ]; then
    BATCH_MODE=true
    echo "📦 Batch-Modus für '$TARGET_FILE' (${#VALID_FILES[@]} Dateien). Sortiere chronologisch..."
fi

# --- CHRONOLOGISCHE SORTIERUNG ---
mapfile -d '' SORTED_FILES < <(
    for f in "${VALID_FILES[@]}"; do
        printf "%s\t%s\0" "$(stat -c %Y "$f")" "$f"
    done | sort -z -n | cut -z -f2-
)

# --- VERARBEITUNG ---
for SOURCE_FILE in "${SORTED_FILES[@]}"; do
    ABS_SOURCE_FILE="$(cd "$(dirname "$SOURCE_FILE")" && pwd)/$(basename "$SOURCE_FILE")"
    SOURCE_FILENAME=$(basename -- "$SOURCE_FILE")
    DATE=$(date -r "$ABS_SOURCE_FILE" -Iseconds)

    echo "-----------------------------------------"
    echo "🎯 Ziel:   $TARGET_FILE"
    echo "📄 Quelle: $SOURCE_FILENAME"
    echo "📅 Datum:  $DATE"

    # Datei kopieren oder verschieben
    $FILE_ACTION "$ABS_SOURCE_FILE" "$REPO_DIR/$TARGET_FILE"

    # Ins Repo wechseln
    cd "$REPO_DIR"
    git add "$TARGET_FILE"

    # Prüfen, ob es Änderungen gegenüber dem letzten Commit gibt
    if git diff --cached --quiet; then
        echo "⏭️  Übersprungen: Inhalt ist identisch zum letzten Commit."
        continue
    fi

    # Technische Änderungen auslesen (erkennt Python- 'def' und Bash-Funktionen)
    DIFF_STAT=$(git diff --cached --shortstat | xargs)
    CHANGED_FUNCS=$(git diff --cached -U0 | grep -E "^@@.*@@ (def |[a-zA-Z0-9_]+\s*\(\))" | sed -E 's/^@@.*@@ (def )?([a-zA-Z0-9_]+).*/\2/' | sort -u | paste -sd ", " -)

    AUTO_DETAILS="$DIFF_STAT"
    if [ -n "$CHANGED_FUNCS" ]; then
        AUTO_DETAILS="$AUTO_DETAILS | Funktionen: $CHANGED_FUNCS"
    fi

    # Commit-Nachricht bestimmen
    if [ "$BATCH_MODE" = true ]; then
        COMMIT_MSG="Debug iteration: '${TARGET_BASENAME} (${SOURCE_FILENAME})' [${AUTO_DETAILS}]"
    else
        echo "💬 Commit-Kommentar (ENTER für automatisch):"
        read -r COMMIT_MSG
        if [ -z "$COMMIT_MSG" ]; then
            COMMIT_MSG="Debug iteration: '${TARGET_BASENAME} (${SOURCE_FILENAME})' [${AUTO_DETAILS}]"
        fi
    fi

    # Commit ausführen
    GIT_AUTHOR_DATE="$DATE" GIT_COMMITTER_DATE="$DATE" git commit -m "$COMMIT_MSG"
    echo "✅ Committet: $COMMIT_MSG"
done

echo "-----------------------------------------"
echo "🎉 Fertig!"
