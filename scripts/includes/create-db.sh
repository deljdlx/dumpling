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