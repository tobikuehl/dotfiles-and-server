#!/bin/bash
# Version 3.2
# Erkennt auch Änderungen in Bash-Funktionen.
set -e

# --- KONFIGURATION ---
FILE_ACTION="cp -p" # Entweder "cp" oder "mv"
TARGET_FILE="4_cohens_rmse.py"
TARGET_BASENAME="${TARGET_FILE%.*}"
### --- ENDE der Konfiguration --- ###

# --- SELF ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
SELF_PATH="$REPO_DIR/$(basename "${BASH_SOURCE}")"

# --- VALIDIERUNG & FILTERUNG ---
if [ "$#" -lt 1 ]; then
    echo "❌ Fehler: Bitte mindestens eine Datei übergeben!"
    echo "Verwendung: $0 /pfad/zu/dateien/*"
    exit 1
fi

VALID_FILES=()

for f in "$@"; do
    # 1. Unterordner stillschweigend überspringen
    if [ -d "$f" ]; then
        continue
    fi
    # 2. Prüfen, ob reguläre Datei existiert (fängt z.B. leere Wildcards ab)
    if [ ! -f "$f" ]; then
        echo "❌ Fehler: Datei '$f' existiert nicht."
        exit 1
    fi
    # 3. Das Skript selbst überspringen, falls es mit '*' erfasst wurde
    ABS_F="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    if [ "$ABS_F" = "$SELF_PATH" ]; then
        continue
    fi

    VALID_FILES+=("$f")
done

# Prüfen, ob nach dem Filtern überhaupt noch Dateien übrig sind
if [ "${#VALID_FILES[@]}" -eq 0 ]; then
    echo "❌ Fehler: Keine gültigen Dateien gefunden (nur Ordner übergeben?)."
    exit 1
fi

# Batch-Modus aktivieren, wenn mehr als 1 gültige Datei übrig ist
BATCH_MODE=false
if [ "${#VALID_FILES[@]}" -gt 1 ]; then
    BATCH_MODE=true
    echo "📦 Batch-Modus erkannt (${#VALID_FILES[@]} Dateien). Sortiere chronologisch..."
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
    echo "📄 Datei: $SOURCE_FILENAME"
    echo "📅 Datum: $DATE"

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

    # Technische Änderungen auslesen
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
