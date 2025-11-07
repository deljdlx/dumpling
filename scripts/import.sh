#!/usr/bin/env bash
# Import MySQL avec prompts sexy powered by gum 🫧

set -euo pipefail

#-----------------------------#
#  Préchecks
#-----------------------------#
command -v gum >/dev/null 2>&1 || {
  echo "❌ gum n'est pas installé."
  echo "👉 Installe-le puis relance ce script."
  exit 1
}

command -v mysql >/dev/null 2>&1 || {
  gum style --foreground 196 "❌ mysql client introuvable. Installe-le avant de continuer."
  exit 1
}

if command -v curl >/dev/null 2>&1; then
  DL_CMD="curl"
elif command -v wget >/dev/null 2>&1; then
  DL_CMD="wget"
else
  gum style --foreground 196 "❌ curl ou wget requis pour télécharger le fichier."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAR_PATH=$SCRIPT_DIR/../var
DOWNLOADS_ROOT_PATH="$VAR_PATH/downloads"

# import .env if present
if [ -f $SCRIPT_DIR/../.env ]; then
  . $SCRIPT_DIR/../.env
fi


#-----------------------------#
#  Gestion erreurs globale
#-----------------------------#
cleanup_on_error() {
  gum style --border normal --border-foreground 196 --margin "1 0" --padding "1 2" \
    "💥 Une erreur est survenue. Vérifie les messages ci-dessus."
}
trap cleanup_on_error ERR

#-----------------------------#
#  Intro
#-----------------------------#
gum style --border double --border-foreground 212 --margin "1 0" --padding "1 2" \
"🐬 Import MySQL Assistant" "On va télécharger, créer, importer & nettoyer. Pose ton café et répond."

#-----------------------------#
# 1. URL du fichier SQL
#-----------------------------#
SQL_URL=$(gum input \
  --placeholder "URL du dump (.sql, .sql.gz, .tar.gz, .tgz)" \
  --prompt "🌐 URL du fichier SQL : ")

[ -z "$SQL_URL" ] && gum style --foreground 196 "❌ URL vide. Abort." && exit 1

FILENAME=$(basename "${SQL_URL%%\?*}")
DOWNLOAD_PATH="$DOWNLOADS_ROOT_PATH/$FILENAME"

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

#-----------------------------#
# 3-5. Infos MySQL
#-----------------------------#
DB_NAME=$(gum input --prompt "🗄️ Nom de la base à utiliser/créer : ")
[ -z "$DB_NAME" ] && gum style --foreground 196 "❌ Nom de base vide." && exit 1

DB_USER=$(gum input --prompt "👤 Utilisateur MySQL : ")
[ -z "$DB_USER" ] && gum style --foreground 196 "❌ Utilisateur vide." && exit 1

DB_PASS=$(gum input --password --prompt "🔑 Mot de passe MySQL : ")

gum style --foreground 99 "🔗 Cible: $DB_USER@$MYSQL_HOST:$MYSQL_PORT / $DB_NAME"

#-----------------------------#
# 6-7. Création / recréation base
#-----------------------------#

# test connection

# Test connection
gum spin --spinner dot --title "Test connexion MySQL..." -- \
bash -c 'mysql \
  -h"'"$MYSQL_HOST"'" \
  -P"'"$MYSQL_PORT"'" \
  -u"'"$DB_USER"'" \
  -p"'"$DB_PASS"'" \
  -e "SELECT 1" >/dev/null 2>&1' || {
    gum style --foreground 196 "❌ Échec de la connexion MySQL. Vérifie l'hôte, le port, l'utilisateur ou le mot de passe."
    exit 1
}


DB_EXISTS=0
if mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$DB_USER" -p"$DB_PASS" \
  -e "USE \`$DB_NAME\`;" >/dev/null 2>&1; then
  DB_EXISTS=1
fi

if [ "$DB_EXISTS" -eq 0 ]; then
  gum style --foreground 81 "🆕 La base n'existe pas, création..."
  gum spin --spinner dot --title "Création base '$DB_NAME'..." -- \
  mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$DB_USER" -p"$DB_PASS" \
    -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  gum style --foreground 82 "✅ Base '$DB_NAME' créée."
else
  gum style --foreground 214 "⚠️ La base '$DB_NAME' existe déjà."
  if gum confirm "🔥 La supprimer puis la recréer ?"; then
    gum spin --spinner dot --title "Drop + recreate '$DB_NAME'..." -- \
    mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$DB_USER" -p"$DB_PASS" \
      -e "DROP DATABASE \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    gum style --foreground 82 "✅ Base '$DB_NAME' recréée proprement."
  else
    gum style --foreground 82 "✅ Ok, on garde la base existante. Import par dessus."
  fi
fi

#-----------------------------#
# 8. Décompression
#-----------------------------#
gum style --foreground 111 "📦 Analyse du fichier : $FILENAME"

SQL_FILE=""
TMP_DIR=""

case "$FILENAME" in
  *.sql)
    SQL_FILE="$DOWNLOAD_PATH"
    gum style --foreground 82 "✅ Fichier .sql détecté, pas de décompression."
    ;;
  *.sql.gz|*.gz)
    gum spin --spinner dot --title "Décompression .gz..." -- \
    gunzip -c "$DOWNLOAD_PATH" > "${DOWNLOAD_PATH%.gz}.sql"
    SQL_FILE="${DOWNLOAD_PATH%.gz}.sql"
    gum style --foreground 82 "✅ Décompression OK → $SQL_FILE"
    ;;
  *.tar.gz|*.tgz)
    TMP_DIR=$(mktemp -d)
    gum spin --spinner dot --title "Extraction archive (.tar.gz)..." -- \
    tar -xzf "$DOWNLOAD_PATH" -C "$TMP_DIR"
    SQL_FILE=$(find "$TMP_DIR" -maxdepth 5 -type f -name "*.sql" | head -n 1 || true)
    if [ -z "${SQL_FILE:-}" ]; then
      gum style --foreground 196 "❌ Aucun .sql trouvé dans l'archive."
      exit 1
    fi
    gum style --foreground 82 "✅ SQL trouvé dans l'archive → $SQL_FILE"
    ;;
  *)
    gum style --foreground 196 "❌ Extension non supportée: $FILENAME"
    exit 1
    ;;
esac

#-----------------------------#
# 9. Import dans MySQL
#-----------------------------#
gum spin --spinner dot --title "Import dans '$DB_NAME' en cours..." -- \
bash -c 'mysql -h"'"$MYSQL_HOST"'" -P"'"$MYSQL_PORT"'" -u"'"$DB_USER"'" -p"'"$DB_PASS"'" "'"$DB_NAME"'" < "'"$SQL_FILE"'"'

gum style --foreground 82 "✅ Import terminé avec succès."

#-----------------------------#
# 10. Nettoyage
#-----------------------------#
gum spin --spinner dot --title "Nettoyage des fichiers..." -- bash -c '
  # Supprime le fichier téléchargé
  rm -f "'"$DOWNLOAD_PATH"'"

  # Si décompression dans tmp, on nettoie
  if [ -n "'"${TMP_DIR:-}"'" ] && [ -d "'"${TMP_DIR:-}"'" ]; then
    rm -rf "'"$TMP_DIR"'"
  fi

  # Si on a généré un .sql différent du fichier d origine, on le supprime aussi
  if [ "'"$SQL_FILE"'" != "'"$DOWNLOAD_PATH"'" ] && [ -f "'"$SQL_FILE"'" ]; then
    rm -f "'"$SQL_FILE"'"
  fi
'

gum style --foreground 82 "🧹 Nettoyage OK."

#-----------------------------#
# 11. Message final
#-----------------------------#
gum style --border rounded --border-foreground 82 --padding "1 2" --margin "1 0" \
"🎉 Tout est bon." \
"Base : $DB_NAME" \
"Host : $MYSQL_HOST:$MYSQL_PORT" \
"Tu peux aller jouer avec tes données maintenant. 😉"

