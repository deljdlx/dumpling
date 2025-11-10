#!/usr/bin/env bash

# Factorised utils for import scripts

# set -euo pipefail

# Get script directory
get_script_dir() {
	local src="${BASH_SOURCE[0]}"
	cd "$(dirname "$src")" && pwd
}

# Import .env if present
import_env() {
	local script_dir="$1"
	if [ -f "$script_dir/../.env" ]; then
		# shellcheck disable=SC1091
		. "$script_dir/../.env"
	fi
}

# Check required commands
check_require_cmd() {
	local cmd="$1"
	local msg="$2"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "$msg"
		exit 1
	fi
}

# Check required commands with gum style
check_require_cmd_gum() {
	local cmd="$1"
	local msg="$2"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		gum style --foreground 196 "$msg"
		exit 1
	fi
}

# Error handler for trap
cleanup_on_error() {
	gum style --border normal --border-foreground 196 --margin "1 0" --padding "1 2" \
		"💥 Une erreur est survenue. Vérifie les messages ci-dessus."
}

testConnection() {
    local MYSQL_HOST="$1"
    local MYSQL_PORT="$2"
    local DB_USER="$3"
    local DB_PASS="$4"

    if gum spin --spinner dot --title "Test connexion MySQL..." -- \
        mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$DB_USER" -p"$DB_PASS" \
              -e "SELECT 1" >/dev/null 2>&1
    then
        gum style --foreground 82 "✅ Connexion MySQL OK."
    else
        gum style --foreground 196 "❌ Échec de la connexion MySQL. Vérifie l'hôte, le port, l'utilisateur ou le mot de passe. ${DB_USER}@${MYSQL_HOST}:${MYSQL_PORT}"
        exit 1
    fi
}

function downloadFile() {
    local URL="$1"
    local OUTPUT_PATH="$2"

    if command -v curl >/dev/null 2>&1; then
        DL_CMD="curl"
    elif command -v wget >/dev/null 2>&1; then
        DL_CMD="wget"
    else
        gum style --foreground 196 "❌ curl ou wget requis pour télécharger le fichier."
        exit 1
    fi


    gum style --foreground 111 "📥 Fichier cible : $DOWNLOAD_PATH"

    #-----------------------------#
    # 2. Téléchargement
    #-----------------------------#
    gum spin --spinner dot --title "Téléchargement en cours..." -- \
    bash -c '
    if [ "'"$DL_CMD"'" = "curl" ]; then
        curl -fSL "'"$SQL_URL"'" -o "'"$DOWNLOAD_PATH"'"
    else
        wget -q "'"$SQL_URL"'" -O "'"$DOWNLOAD_PATH"'"
    fi
    '
    gum style --foreground 82 "✅ Téléchargement OK."
}
