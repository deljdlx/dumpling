#!/usr/bin/env bash

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

if [ -z "$CSV_PATH" ]; then
  gum style --foreground 196 "❌ Chemin vide. Abort."
  exit 1
fi

if [ ! -f "$CSV_PATH" ]; then
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
# Connexion MySQL
########################################

# Charge fonctions + variables MYSQL_HOST / PORT / USER / PASS
. "$SCRIPT_DIR/includes/mysql-connect.sh"

DB_NAME=$(gum input --prompt "🗄️ Nom de la base MySQL : ")
[ -z "$DB_NAME" ] && { gum style --foreground 196 "❌ Nom de base vide."; exit 1; }

TABLE_NAME=$(gum input --prompt "📌 Nom de la table à créer : ")
[ -z "$TABLE_NAME" ] && { gum style --foreground 196 "❌ Nom de table vide."; exit 1; }

testConnection "$MYSQL_HOST" "$MYSQL_PORT" "$DB_USER" "$DB_PASS"

# Création base si besoin
. "$SCRIPT_DIR/includes/create-db.sh"

########################################
# Séparateur CSV
########################################

SEP_INPUT=$(gum input --prompt "🔹 Séparateur CSV (ex: , ; \\t |) : " --value "")
[ -z "$SEP_INPUT" ] && {
  gum style --foreground 196 "❌ Séparateur vide."
  exit 1
}

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

  input=$(printf "%s" "$input" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  input=$(printf "%s" "$input" | tr '[:upper:]' '[:lower:]')
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
  input=$(printf "%s" "$input" | sed -E 's/[^a-z0-9]+/_/g')
  input=$(printf "%s" "$input" | sed -E 's/^_+//; s/_+$//; s/_+/_/g')
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
# Option: colonne auto-incrément
########################################

USE_AI=0
AI_COL=""

if gum confirm "➕ Créer un champ auto incrément (PRIMARY KEY) ?"; then
  default_name="id"
  for c in "${FINAL_COLS[@]}"; do
    if [ "$c" = "id" ]; then
      default_name="row_id"
      break
    fi
  done

  AI_COL=$(gum input --prompt "🔑 Nom de la colonne auto-incrément : " --value "$default_name")
  [ -z "$AI_COL" ] && AI_COL="$default_name"
  AI_COL=$(normalize_col "$AI_COL" 0)

  for c in "${FINAL_COLS[@]}"; do
    if [ "$c" = "$AI_COL" ]; then
      gum style --foreground 196 "❌ Le nom '$AI_COL' existe déjà parmi les colonnes détectées."
      exit 1
    fi
  done

  USE_AI=1
  gum style --foreground 82 "✅ Colonne auto-incrément utilisée : \`$AI_COL\`"
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

if [ "$USE_AI" -eq 1 ]; then
  CREATE_SQL+="\`$AI_COL\` INT UNSIGNED NOT NULL AUTO_INCREMENT, "
fi

for idx in "${!FINAL_COLS[@]}"; do
  col="${FINAL_COLS[$idx]}"
  [ "$idx" -gt 0 ] && CREATE_SQL+=", "
  CREATE_SQL+="\`$col\` TEXT NULL"
done

if [ "$USE_AI" -eq 1 ]; then
  CREATE_SQL+=", PRIMARY KEY (\`$AI_COL\`)"
fi

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
# (⚠️ sans la colonne auto-incrément)
########################################

COL_LIST=""
for col in "${FINAL_COLS[@]}"; do
  [ -n "$COL_LIST" ] && COL_LIST+=", "
  COL_LIST+="\`$col\`"
done

########################################
# Détection FIELDS_CLAUSE (auto)
########################################

detect_fields_clause() {
  local sep="$1"
  local file="$2"

  local mysql_sep="$sep"
  if [ "$sep" = $'\t' ]; then
    mysql_sep='\t'
  fi

  # Cas fichiers pipe (open data type RPPS/etc) : par défaut brut
  if [ "$sep" = "|" ]; then
    # Check rapide sur 500 lignes pour voir s'il y a beaucoup de champs vraiment quotés
    local quoted_count
    quoted_count=$(head -n 500 "$file" | grep -Eo '(^|\|)"[^"]*"' | wc -l || true)
    if [ "$quoted_count" -gt 5 ]; then
      echo "FIELDS TERMINATED BY '|' OPTIONALLY ENCLOSED BY '\"' ESCAPED BY '\"'"
    else
      echo "FIELDS TERMINATED BY '|'"
    fi
    return
  fi

  # Cas séparateur standard (; , \t) : CSV classique
  echo "FIELDS TERMINATED BY '${mysql_sep}' OPTIONALLY ENCLOSED BY '\"' ESCAPED BY '\"'"
}

# Pour ton exemple `;` sans guillemets : ça donnera bien FIELDS TERMINATED BY ';' OPTIONALLY...
# (ce qui est accepté même sans guillemets dans les données)

########################################
# Import des données (LOAD DATA LOCAL INFILE)
########################################

# Séparateur MySQL
if [ "$SEP" = $'\t' ]; then
  MYSQL_SEP=$'\t'
else
  MYSQL_SEP="$SEP"
fi

IGNORE_CLAUSE=""
if [ "$IGNORE_FIRST_LINE" -eq 1 ]; then
  IGNORE_CLAUSE="IGNORE 1 LINES"
fi

FIELDS_CLAUSE=$(detect_fields_clause "$MYSQL_SEP" "$CSV_PATH")

gum style --foreground 111 "📥 Import des données dans '$TABLE_NAME'..."
gum style --foreground 99  "ℹ️ Mode FIELDS: ${FIELDS_CLAUSE}"

if mysql --local-infile=1 \
    -h"$MYSQL_HOST" -P"$MYSQL_PORT" \
    -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
SET SESSION sql_mode = REPLACE(@@sql_mode, 'STRICT_ALL_TABLES', '');
SET SESSION sql_mode = REPLACE(@@sql_mode, 'STRICT_TRANS_TABLES', '');

LOAD DATA LOCAL INFILE '${CSV_PATH}'
INTO TABLE \`${TABLE_NAME}\`
CHARACTER SET utf8mb4
${FIELDS_CLAUSE}
LINES TERMINATED BY '\n'
${IGNORE_CLAUSE}
(${COL_LIST});

SELECT COUNT(*) AS rows_loaded FROM \`${TABLE_NAME}\`;
EOF
then
  gum style --border rounded --border-foreground 82 --padding "1 2" --margin "1 0" \
    "🎉 Import terminé." \
    "Base : $DB_NAME" \
    "Table : $TABLE_NAME"
else
  gum style --foreground 196 "❌ Erreur lors de l'import des données (LOAD DATA LOCAL INFILE)."
  exit 1
fi
