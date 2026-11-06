#!/bin/bash

# Abbrechen bei Fehlern
set -e

# --- KONFIGURATION ---
# In diesen Dateinamen soll jede übergebene Python-Datei im Repo umbenannt werden
TARGET_FILE="extract.py"

# --- VALIDIERUNG ---
if [ "$#" -ne 1 ]; then
    echo "❌ Fehler: Bitte genau eine Python-Datei übergeben!"
    echo "Verwendung: ./commit_file.sh /pfad/zu/deiner_datei.py"
    exit 1
fi

SOURCE_FILE="$1"

if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Fehler: Datei '$SOURCE_FILE' existiert nicht."
    exit 1
fi

# --- DATUMSAUSLESUNG ---
# Extrahiert das Änderungsdatum der Datei im Format YYYY-MM-DD HH:MM:SS
# Funktioniert nativ unter GNU/Linux
FILE_DATE=$(stat -c '%y' "$SOURCE_FILE" | cut -d'.' -f1)

echo "📄 Datei erkannt: $SOURCE_FILE"
echo "📅 Reales Änderungsdatum: $FILE_DATE"
echo "💬 Bitte Commit-Kommentar eingeben (beenden mit ENTER):"

# Liest den Kommentar aus stdin
read -r COMMIT_MSG

if [ -z "$COMMIT_MSG" ]; then
    echo "❌ Fehler: Commit-Kommentar darf nicht leer sein."
    exit 1
fi

# --- GIT OPERATIONEN ---
# 1. Datei an den Zielort kopieren und umbenennen
cp "$SOURCE_FILE" "$TARGET_FILE"

# 2. In Git stagen
git add "$TARGET_FILE"

# 3. Historischen Commit ausführen
GIT_AUTHOR_DATE="$FILE_DATE" GIT_COMMITTER_DATE="$FILE_DATE" git commit -m "$COMMIT_MSG"

echo "✅ Erfolgreich committet mit Datum $FILE_DATE!"
echo "------------------------------------------------"
exit 0
