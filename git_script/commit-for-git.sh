#!/bin/bash
# Version 3.0
# Erkennt jetzt automatisch seinen eigenen Speicherort
set -e

# --- KONFIGURATION ---
FILE_ACTION="cp -p" # Entweder "cp" oder "mv"
TARGET_FILE="4_cohens_rmse.py"
TARGET_BASENAME="${TARGET_FILE%.*}"
### --- ENDE der Konfiguration --- ###

# --- SELF ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"

# --- VALIDIERUNG ---
if [ "$#" -lt 1 ]; then
    echo "❌ Fehler: Bitte mindestens eine Datei übergeben!"
    echo "Verwendung: $0 datei1.py [datei2.py ...] oder $0 /pfad/*.py"
    exit 1
fi

# Prüfen, ob alle übergebenen Dateien existieren
for f in "$@"; do
    if [ ! -f "$f" ]; then
        echo "❌ Fehler: Datei '$f' existiert nicht."
        exit 1
    fi
done

# Batch-Modus aktivieren, wenn mehr als 1 Datei übergeben wurde
BATCH_MODE=false
if [ "$#" -gt 1 ]; then
    BATCH_MODE=true
    echo "📦 Batch-Modus erkannt ($# Dateien). Sortiere chronologisch..."
fi

# --- CHRONOLOGISCHE SORTIERUNG ---
# Liest Unix-Timestamp (%Y) + Dateipfad aus, sortiert aufsteigend und trennt den Pfad wieder ab
mapfile -d '' SORTED_FILES < <(
    for f in "$@"; do
        printf "%s\t%s\0" "$(stat -c %Y "$f")" "$f"
    done | sort -z -n | cut -z -f2-
)

# --- VERARBEITUNG ---
for SOURCE_FILE in "${SORTED_FILES[@]}"; do
    # Wichtig: Absolutpfad merken, falls wir gleich ins Repo wechseln
    ABS_SOURCE_FILE="$(cd "$(dirname "$SOURCE_FILE")" && pwd)/$(basename "$SOURCE_FILE")"
    SOURCE_FILENAME=$(basename -- "$SOURCE_FILE")
    DATE=$(date -r "$ABS_SOURCE_FILE" -Iseconds)

    echo "-----------------------------------------"
    echo "📄 Datei: $SOURCE_FILENAME"
    echo "📅 Datum: $DATE"

    # Datei bewegen
    $FILE_ACTION "$ABS_SOURCE_FILE" "$REPO_DIR/$TARGET_FILE"

    # Ins Repo wechseln
    cd "$REPO_DIR"
    git add "$TARGET_FILE"

    # Prüfen, ob es überhaupt Änderungen gegenüber dem letzten Commit gibt
    if git diff --cached --quiet; then
        echo "⏭️  Übersprungen: Inhalt ist identisch zum letzten Commit."
        continue
    fi

    # Technische Änderungen (Statistik & betroffene Python-Funktionen) auslesen
    DIFF_STAT=$(git diff --cached --shortstat | xargs)
    CHANGED_FUNCS=$(git diff --cached -U0 | grep -E "^@@.*@@ def " | sed -E 's/^@@.*@@ def ([^(]+).*/\1/' | sort -u | paste -sd ", " -)

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
