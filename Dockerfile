# --- Stage 1: Build Laravel + PHP Extensions ---
FROM php:8.2-cli-alpine AS builder

WORKDIR /var/www

# Install build dependencies for PHP extensions (including Redis)
RUN apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        build-base \
        linux-headers \
        curl \
        unzip \
        git \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        libzip-dev \
        openssl-dev \
    # Install PHP core extensions
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd zip pdo pdo_mysql pcntl sockets \
    # Install Redis via PECL
    && pecl install redis \
    && docker-php-ext-enable redis \
    # Clean up build dependencies
    && apk del .build-deps

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy only composer files first (for caching)
COPY composer.json composer.lock ./

# Install PHP dependencies (vendor)
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

# Now copy the rest of the app
COPY . .
RUN composer run-script post-autoload-dump

# --- Stage 2: Runtime (Alpine, minimal) ---
FROM php:8.2-cli-alpine AS runtime

WORKDIR /var/www

# Install runtime libs (needed for PHP extensions but not build tools)
RUN apk add --no-cache \
        curl \
        libpng \
        libjpeg-turbo \
        freetype \
        libzip \
        openssl

# Install RoadRunner binary
RUN curl -sSL https://github.com/roadrunner-server/roadrunner/releases/download/v2.11.1/roadrunner-2.11.1-linux-amd64 \
    -o /usr/local/bin/rr && chmod +x /usr/local/bin/rr

# Copy built app and extensions
COPY --from=builder /var/www /var/www
COPY --from=builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=builder /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d

# Non-root user for security
RUN adduser -D -H -u 1000 www && chown -R www:www /var/www
USER www

CMD ["php", "artisan", "octane:start", "--server=roadrunner", "--host=0.0.0.0"]
