# Dockerfile — PHP CLI + Composer + extensions minimales pour Artisan
FROM php:8.3-cli

# Outils système utiles (zip pour composer, git pour packages)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip libzip-dev \
 && docker-php-ext-install -j$(nproc) pcntl bcmath \
 && rm -rf /var/lib/apt/lists/*

# Composer (officiel)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Dossier de travail (on pointera sur /app/src via docker-compose)
WORKDIR /app
