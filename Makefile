# Makefile — Laravel CLI-only dans Docker avec vérification gum
SHELL := /bin/bash
COMPOSE ?= docker compose
SERVICE ?= app

UID := $(shell id -u)
GID := $(shell id -g)
RUN := $(COMPOSE) run --rm --user $(UID):$(GID) $(SERVICE)

# ───────────────────────────────────────────────
# 💡 Vérification globale : gum doit être présent
# Cette ligne force l'exécution de check-gum avant chaque cible
# (sauf celles marquées comme .PHONY spéciales)
# ───────────────────────────────────────────────
.DEFAULT_GOAL := help
.PHONY: check-gum
check-gum:
	@if ! command -v gum >/dev/null 2>&1; then \
	  echo "❌ gum n'est pas installé."; \
	  echo "👉 Installe-le avec :"; \
	  echo "   brew install gum     # macOS"; \
	  echo "   sudo apt install gum  # Debian/Ubuntu"; \
	  echo "   ou via https://github.com/charmbracelet/gum"; \
	  exit 1; \
	else \
	  gum style \
	    --foreground 84 --border double --border-foreground 84 \
	    --align center --width 40 --margin "1 0" \
	    "✅ gum est installé" "Tout est prêt pour Dumpling !"; \
	fi


# On injecte 'check-gum' avant toutes les cibles sauf celles internes
# (utile pour ne pas dupliquer manuellement)
# Note: cette approche est GNU Make >=4.0
MAKEFLAGS += --warn-undefined-variables
ifneq ($(filter-out check-gum,$(MAKECMDGOALS)),)
  $(eval $(filter-out check-gum,$(MAKECMDGOALS)): check-gum)
endif

# ───────────────────────────────────────────────
# Commandes principales
# ───────────────────────────────────────────────
.PHONY: help init art composer php tinker clean nuke ls

help:
	@echo "📘 Dumpling (Laravel CLI-only)"
	@echo ""
	@echo "Targets :"
	@echo "  make init                 -> crée un projet Laravel 12 dans ./src"
	@echo "  make art CMD='migrate'    -> exécute php artisan <CMD> dans le container"
	@echo "  make composer CMD='install' -> exécute composer <CMD> dans ./src"
	@echo "  make php CMD='-v'         -> exécute php <CMD> dans ./src"
	@echo "  make tinker               -> lance php artisan tinker"
	@echo "  make clean                -> supprime vendor & caches Laravel"
	@echo "  make nuke                 -> supprime complètement ./src (⚠️)"

# 1) Créer un projet Laravel 12 dans ./src
init:
	@mkdir -p src
	@if [ -f src/artisan ]; then \
	  gum style --foreground 212 --bold "✅ src/ contient déjà un projet Laravel."; \
	else \
	  gum spin --title "Création du projet Laravel 12..." -- \
	    $(RUN) "cd /app && composer create-project laravel/laravel src '12.*'"; \
	  gum style --foreground 84 --bold "✅ Terminé. Essayez: make art CMD='--version'"; \
	fi

# 2) Exécuter artisan
art:
	@if [ ! -f src/artisan ]; then gum style --foreground 196 "❌ src/artisan introuvable. Lance d'abord: make init"; exit 1; fi
	@$(RUN) "php artisan $(CMD)"

# 3) Composer
composer:
	@if [ ! -f src/composer.json ]; then gum style --foreground 196 "❌ src/composer.json introuvable. make init d'abord."; exit 1; fi
	@$(RUN) "composer $(CMD)"

# 4) PHP brut
php:
	@$(RUN) "php $(CMD)"

# 5) Tinker
tinker:
	@$(MAKE) art CMD="tinker"

# 6) Nettoyage soft
clean:
	@rm -rf src/vendor src/storage/framework/{cache,views,sessions} 2>/dev/null || true
	@gum style --foreground 84 "🧹 Clean ok."

# 7) Nettoyage hard
nuke:
	@read -p '⚠️  Supprimer totalement ./src ? [y/N] ' ans; \
	if [[ $$ans == y || $$ans == Y ]]; then rm -rf src; gum style --foreground 196 "💥 ./src supprimé."; else gum style --foreground 240 "Annulé."; fi

importDb:
	@./scripts/import.sh

importCsv:
	@./scripts/importCsv.sh