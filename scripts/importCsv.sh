
source "$(dirname "$0")/_utils.sh"

SCRIPT_DIR="$(get_script_dir)"
import_env "$SCRIPT_DIR"

check_require_cmd gum "❌ gum n'est pas installé.\n👉 https://github.com/charmbracelet/gum"
check_require_cmd_gum mysql "❌ mysql client introuvable."

gum style --border double --border-foreground 213 --margin "1 0" --padding "1 2" \
  "📊 Import CSV → MySQL" \
  "On va vérifier, nommer proprement, créer la table et ingérer les données."

########################################
# Saisie chemin CSV
########################################

CSV_PATH=$(gum input --prompt "📂 Chemin du fichier CSV : ")

if [ -z "${CSV_PATH}" ]; then
  gum style --foreground 196 "❌ Chemin vide. Abort."
  exit 1
fi

if [ ! -f "${CSV_PATH}" ]; then
  gum style --foreground 196 "❌ Fichier introuvable : ${CSV_PATH}"
  exit 1
fi

case "$CSV_PATH" in
  *.csv|*.CSV) ;;
  *)
    gum style --foreground 196 "❌ Le fichier ne se termine pas par .csv"
    exit 1
    ;;
esac

gum style --foreground 82 "✅ Fichier trouvé et extension .csv valide."

########################################
# Connexion MySQL (DB, user, pass, host, port)
########################################

DB_NAME=$(gum input --prompt "🗄️ Nom de la base MySQL : ")
[ -z "$DB_NAME" ] && { gum style --foreground 196 "❌ Nom de base vide."; exit 1; }

TABLE_NAME=$(gum input --prompt "📌 Nom de la table à créer : ")
[ -z "$TABLE_NAME" ] && { gum style --foreground 196 "❌ Nom de table vide."; exit 1; }


. $SCRIPT_DIR/includes/mysql-connect.sh



# DB_USER=$(gum input --prompt "👤 Utilisateur MySQL : ")
# [ -z "$DB_USER" ] && { gum style --foreground 196 "❌ Utilisateur vide."; exit 1; }

# DB_PASS=$(gum input --password --prompt "🔑 Mot de passe MySQL : ")


gum style --foreground 99 "🔗 Cible: $DB_USER@$MYSQL_HOST:$MYSQL_PORT / $DB_NAME ($TABLE_NAME)"

# Vérif base ou création
if mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$DB_USER" -p"$DB_PASS" \
    -e "USE \`$DB_NAME\`;" >/dev/null 2>&1; then
  gum style --foreground 82 "✅ Base '$DB_NAME' trouvée."
else
  gum style --foreground 214 "⚠️ La base '$DB_NAME' n'existe pas."
  if gum confirm "🆕 La créer maintenant ?"; then
    if mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$DB_USER" -p"$DB_PASS" \
        -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
      gum style --foreground 82 "✅ Base '$DB_NAME' créée."
    else
      gum style --foreground 196 "❌ Impossible de créer la base '$DB_NAME'."
      exit 1
    fi
  else
    gum style --foreground 196 "❌ Sans base valide, on s'arrête là."
    exit 1
  fi
fi

########################################
# Séparateur CSV
########################################

SEP_INPUT=$(gum input --prompt "🔹 Séparateur CSV (ex: , ; \\t |) : " --value ",")
[ -z "$SEP_INPUT" ] && SEP_INPUT=","

if [ "$SEP_INPUT" = '\t' ]; then
  SEP=$'\t'
  SEP_LABEL="tabulation"
else
  SEP="$SEP_INPUT"
  SEP_LABEL="$SEP_INPUT"
fi

gum style --foreground 82 "✅ Séparateur utilisé: '$SEP_LABEL'"

########################################
# Lecture de la première ligne -> colonnes détectées
########################################

HEADER_LINE=$(head -n 1 "$CSV_PATH")

IFS="$SEP" read -r -a RAW_COLS <<< "$HEADER_LINE"
COL_COUNT=${#RAW_COLS[@]}

if [ "$COL_COUNT" -eq 0 ]; then
  gum style --foreground 196 "❌ Impossible de détecter les colonnes."
  exit 1
fi

gum style --border normal --border-foreground 111 --padding "1 2" \
"🧐 Colonnes détectées dans la première ligne :"

i=1
for col in "${RAW_COLS[@]}"; do
  gum style "  $i. ${col}"
  i=$((i+1))
done

if gum confirm "✅ Ces colonnes correspondent-elles aux en-têtes ?"; then
  HEADERS_OK=1
else
  HEADERS_OK=0
fi

########################################
# Normalisation des noms de colonnes
########################################

normalize_col() {
  local input="$1"
  local idx="$2"

  # trim
  input=$(printf "%s" "$input" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')

  # minuscules
  input=$(printf "%s" "$input" | tr '[:upper:]' '[:lower:]')

  # accents → ascii (fréquent)
  input=$(printf "%s" "$input" | sed \
    -e 's/[àáâãäå]/a/g' \
    -e 's/[æ]/ae/g' \
    -e 's/[ç]/c/g' \
    -e 's/[èéêë]/e/g' \
    -e 's/[ìíîï]/i/g' \
    -e 's/[ñ]/n/g' \
    -e 's/[òóôõöø]/o/g' \
    -e 's/[ùúûü]/u/g' \
    -e 's/[ýÿ]/y/g' \
    -e 's/œ/oe/g')

  # non [a-z0-9] → _
  input=$(printf "%s" "$input" | sed -E 's/[^a-z0-9]+/_/g')

  # compresse / trim _
  input=$(printf "%s" "$input" | sed -E 's/^_+//; s/_+$//; s/_+/_/g')

  # fallback
  [ -z "$input" ] && input="col$idx"

  printf "%s" "$input"
}

declare -a FINAL_COLS=()
IGNORE_FIRST_LINE=0

if [ "$HEADERS_OK" -eq 1 ]; then
  declare -A seen=()
  for idx in "${!RAW_COLS[@]}"; do
    base=$(normalize_col "${RAW_COLS[$idx]}" $((idx+1)))
    name="$base"
    c=1
    while [[ -n "${seen[$name]:-}" ]]; do
      c=$((c+1))
      name="${base}_${c}"
    done
    seen["$name"]=1
    FINAL_COLS+=("$name")
  done

  gum style --border normal --border-foreground 111 --padding "1 2" \
  "🔤 Noms normalisés proposés :"
  j=1
  for col in "${FINAL_COLS[@]}"; do
    gum style "  $j. $col"
    j=$((j+1))
  done

  if gum confirm "👍 Utiliser ces noms normalisés ?"; then
    IGNORE_FIRST_LINE=1
  else
    if gum confirm "📦 Utiliser un nommage par défaut (col1, col2, ...) ?"; then
      FINAL_COLS=()
      for ((k=1; k<=COL_COUNT; k++)); do
        FINAL_COLS+=("col$k")
      done
      IGNORE_FIRST_LINE=1
    else
      gum style --foreground 196 "❌ Pas de stratégie de colonnes choisie. Abort."
      exit 1
    fi
  fi

else
  gum style --foreground 214 "ℹ️ La première ligne n'est pas considérée comme en-têtes fiables."

  if ! gum confirm "📦 Utiliser un nommage par défaut (col1, col2, ...) ?"; then
    gum style --foreground 196 "❌ Sans noms par défaut, on arrête."
    exit 1
  fi

  if gum confirm "🗑️ Ignorer la première ligne (considérée comme en-têtes) ?"; then
    IGNORE_FIRST_LINE=1
  else
    IGNORE_FIRST_LINE=0
  fi

  FINAL_COLS=()
  for ((k=1; k<=COL_COUNT; k++)); do
    FINAL_COLS+=("col$k")
  done
fi

########################################
# Vérifier / gérer existence de la table
########################################

TABLE_EXISTS=0
if mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    -e "SHOW TABLES LIKE '${TABLE_NAME}';" | grep -q "$TABLE_NAME"; then
  TABLE_EXISTS=1
fi

if [ "$TABLE_EXISTS" -eq 1 ]; then
  gum style --foreground 214 "⚠️ La table '$TABLE_NAME' existe déjà."
  if gum confirm "🔥 La supprimer et la recréer ?"; then
    if ! mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -e "DROP TABLE \`$TABLE_NAME\`;"; then
      gum style --foreground 196 "❌ Impossible de supprimer la table existante."
      exit 1
    fi
  else
    gum style --foreground 196 "❌ On ne va pas écraser une table existante sans ton accord. Abort."
    exit 1
  fi
fi

########################################
# Génération CREATE TABLE
########################################

CREATE_SQL="CREATE TABLE \`$TABLE_NAME\` ("
for idx in "${!FINAL_COLS[@]}"; do
  col="${FINAL_COLS[$idx]}"
  [ "$idx" -gt 0 ] && CREATE_SQL+=", "
  CREATE_SQL+="\`$col\` TEXT NULL"
done
CREATE_SQL+=");"

gum style --foreground 111 "🏗️ Création de la table '$TABLE_NAME'..."

if mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    -e "$CREATE_SQL"; then
  gum style --foreground 82 "✅ Table '$TABLE_NAME' créée."
else
  gum style --foreground 196 "❌ Erreur lors de la création de la table."
  exit 1
fi

########################################
# Construction liste colonnes pour LOAD DATA
########################################

COL_LIST=""
for col in "${FINAL_COLS[@]}"; do
  if [ -n "$COL_LIST" ]; then
    COL_LIST+=", "
  fi
  COL_LIST+="\`$col\`"
done

########################################
# Import des données (LOAD DATA LOCAL INFILE)
########################################

# Séparateur pour MySQL
if [ "$SEP" = $'\t' ]; then
  MYSQL_SEP='\t'
else
  MYSQL_SEP="$SEP"
fi

IGNORE_CLAUSE=""
if [ "$IGNORE_FIRST_LINE" -eq 1 ]; then
  IGNORE_CLAUSE="IGNORE 1 LINES"
fi

CSV_ESCAPED=$(printf "%s" "$CSV_PATH" | sed "s/'/''/g")

# Construction du LOAD DATA
read -r -d '' LOAD_SQL <<EOF || true
LOAD DATA LOCAL INFILE '${CSV_ESCAPED}'
INTO TABLE \`${TABLE_NAME}\`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY '${MYSQL_SEP}'
ENCLOSED BY '"'
ESCAPED BY '\\\\'
LINES TERMINATED BY '\n'
${IGNORE_CLAUSE}
(${COL_LIST});
EOF

gum style --foreground 111 "📥 Import des données dans '$TABLE_NAME'..."

if mysql --local-infile=1 \
    -h"$MYSQL_HOST" -P"$MYSQL_PORT" \
    -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    -e "$LOAD_SQL"; then
  gum style --border rounded --border-foreground 82 --padding "1 2" --margin "1 0" \
    "🎉 Import terminé avec succès." \
    "Base : $DB_NAME" \
    "Table : $TABLE_NAME"
else
  gum style --foreground 196 "❌ Erreur lors de l'import des données."
  exit 1
fi
