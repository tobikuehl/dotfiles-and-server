#!/bin/bash
# Version 2
set -e

# --- KONFIGURATION ---
FILE_ACTION="cp" # Entweder "cp" oder "mv"
TARGET_FILE="4_cohens_rmse.py"
TARGET_BASENAME="${TARGET_FILE%.*}"
### --- ENDE der Konfiguration --- ###

# --- SELF ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- VALIDIERUNG ---
if [ "$#" -ne 1 ]; then
    echo "❌ Fehler: Bitte genau eine Datei übergeben!"
    echo "Verwendung: $0 /pfad/zu/deiner_datei.py"
    exit 1
fi

SOURCE_FILE="$1"

if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Fehler: Datei '$SOURCE_FILE' existiert nicht."
    exit 1
fi

# WICHTIG: Vor dem Verzeichniswechsel das Datum und den Namen auslesen,
# damit relative Pfade zu $SOURCE_FILE (z.B. "./test.py") noch stimmen!
SOURCE_FILENAME=$(basename -- "$SOURCE_FILE")
DATE=$(date -r "$SOURCE_FILE" -Iseconds)

echo "📄 Datei erkannt: $SOURCE_FILENAME"
echo "📅 Letztes Änderungsdatum: $DATE"
echo "💬 Ggf. Commit-Kommentar (beenden mit ENTER):"

read -r COMMIT_MSG

if [ -z "$COMMIT_MSG" ]; then
    COMMIT_MSG="Debug iteration: '${TARGET_BASENAME} (${SOURCE_FILENAME})'"
fi

# --- GIT OPERATIONEN ---
# 1. Datei in den Repo-Ordner verschieben (funktioniert auch mit relativen Quellpfaden)
$FILE_ACTION "$SOURCE_FILE" "$REPO_DIR/$TARGET_FILE"

# 2. Ab hier direkt im Git-Repo arbeiten
cd "$REPO_DIR"
git add "$TARGET_FILE"
GIT_AUTHOR_DATE="$DATE" GIT_COMMITTER_DATE="$DATE" git commit -m "$COMMIT_MSG"

echo "✅ Erfolgreich in $REPO_DIR committet."
echo "--------------------------------------------"
exit 0
