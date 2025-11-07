if [ -z "${MYSQL_HOST:-}" ]; then
    MYSQL_HOST=$(gum input --prompt "🌍 Host MySQL (défaut 127.0.0.1) : " --value "${MYSQL_HOST:-127.0.0.1}")
    [ -z "$MYSQL_HOST" ] && MYSQL_HOST="127.0.0.1"
else
    MYSQL_HOST="$MYSQL_HOST"
    gum style --foreground 111 "🌍 Host MySQL prérempli : $MYSQL_HOST"
fi

if [ -z "${MYSQL_PORT:-}" ]; then
    MYSQL_PORT=$(gum input --prompt "🔌 Port MySQL (défaut 3306) : " --value "${MYSQL_PORT:-3306}")
    [ -z "$MYSQL_PORT" ] && MYSQL_PORT="3306"
else
    MYSQL_PORT="$MYSQL_PORT"
    gum style --foreground 111 "🔌 Port MySQL prérempli : $MYSQL_PORT"
fi


# if MYSQL_USER is not set, ask for it
if [ -z "${MYSQL_USER:-}" ]; then
  DB_USER=$(gum input --prompt "👤 Utilisateur MySQL : ")
  [ -z "$DB_USER" ] && gum style --foreground 196 "❌ Utilisateur vide." && exit 1
else
  DB_USER="$MYSQL_USER"
  gum style --foreground 111 "👤 Utilisateur MySQL prérempli : $DB_USER"
fi

if [ -z "${MYSQL_PASSWORD:-}" ]; then
  DB_PASS=$(gum input --password --prompt "🔑 Mot de passe MySQL : ")
else
  DB_PASS="$MYSQL_PASSWORD"
  gum style --foreground 111 "🔑 Mot de passe MySQL prérempli."
fi

gum style --foreground 99 "🔗 Cible: $DB_USER@$MYSQL_HOST:$MYSQL_PORT / $DB_NAME"

