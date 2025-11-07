
source "$(dirname "$0")/_utils.sh"

SCRIPT_DIR="$(get_script_dir)"
import_env "$SCRIPT_DIR"

check_require_cmd gum "❌ gum n'est pas installé.\n👉 Installe-le puis relance ce script."
check_require_cmd_gum mysql "❌ mysql client introuvable. Installe-le avant de continuer."


VAR_PATH=$SCRIPT_DIR/../var
DOWNLOADS_ROOT_PATH="$VAR_PATH/downloads"

trap cleanup_on_error ERR

#-----------------------------#
#  Intro
#-----------------------------#
gum style --border double --border-foreground 212 --margin "1 0" --padding "1 2" \
"🐬 Import MySQL Assistant" "On va télécharger, créer, importer & nettoyer. Pose ton café et répond."



#-----------------------------#
# Infos MySQL
#-----------------------------#

DB_NAME=$(gum input --prompt "🗄️ Nom de la base à utiliser/créer : ")
[ -z "$DB_NAME" ] && gum style --foreground 196 "❌ Nom de base vide." && exit 1

. $SCRIPT_DIR/includes/mysql-connect.sh

testConnection "$MYSQL_HOST" "$MYSQL_PORT" "$DB_USER" "$DB_PASS"

#-----------------------------#
# Download
#-----------------------------#
SQL_URL=$(gum input \
  --placeholder "URL du dump (.sql, .sql.gz, .tar.gz, .tgz)" \
  --prompt "🌐 URL du fichier SQL : ")

[ -z "$SQL_URL" ] && gum style --foreground 196 "❌ URL vide. Abort." && exit 1

FILENAME=$(basename "${SQL_URL%%\?*}")
DOWNLOAD_PATH="$DOWNLOADS_ROOT_PATH/$FILENAME"

downloadFile "$SQL_URL" "$DOWNLOAD_PATH"



#-----------------------------#
# Décompression
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
# Création / recréation base
#-----------------------------#

. $SCRIPT_DIR/includes/create-db.sh


#-----------------------------#
# Import dans MySQL
#-----------------------------#
gum spin --spinner dot --title "Import dans '$DB_NAME' en cours..." -- \
bash -c 'mysql -h"'"$MYSQL_HOST"'" -P"'"$MYSQL_PORT"'" -u"'"$DB_USER"'" -p"'"$DB_PASS"'" "'"$DB_NAME"'" < "'"$SQL_FILE"'"'

gum style --foreground 82 "✅ Import terminé avec succès."

#-----------------------------#
# Nettoyage
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

