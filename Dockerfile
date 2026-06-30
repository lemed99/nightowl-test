# NightOwl Tier-1 demo FEEDER image — NOT the production API image.
#
# Runs, in one container (via supervisord): the NightOwl agent + a continuous
# simulator-loop + the scheduler. Three of these (compose) keep the three demo
# tenant DBs continuously populated. The agent's TCP ingest stays on 127.0.0.1
# inside the container; nothing is published to ingress.
FROM dunglas/frankenphp:1-php8.4

# Agent runtime extensions: pdo_pgsql (drain target), pdo_sqlite (WAL buffer),
# pcntl + posix (multi-fork drain workers), zip (composer). + supervisord.
RUN install-php-extensions pdo_pgsql pdo_sqlite pcntl posix zip \
    && apt-get update \
    && apt-get install -y --no-install-recommends supervisor \
    && rm -rf /var/lib/apt/lists/*

RUN echo "memory_limit=256M" > "$PHP_INI_DIR/conf.d/zz-feeder.ini"

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
WORKDIR /app

# nightowl/agent + nightowl/agent-simulator come from their public GitHub repos,
# declared as `no-api` VCS repositories in composer.json so composer clones over git
# instead of hitting the rate-limited/authenticated GitHub API. The lock is already
# resolved against those repos, so a plain install suffices. Both are in `require`.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-scripts --optimize-autoloader

# App source (vendor/ is .dockerignore'd, so this does not clobber the install above).
COPY . .
RUN composer dump-autoload --optimize --no-scripts \
    && mkdir -p storage/nightowl \
       storage/framework/sessions storage/framework/views storage/framework/cache \
       storage/logs bootstrap/cache \
    && chmod -R 777 storage bootstrap/cache

COPY docker/supervisord.conf /etc/supervisor/feeder.conf
COPY docker/feeder-entrypoint.sh /usr/local/bin/feeder-entrypoint.sh
RUN chmod +x /usr/local/bin/feeder-entrypoint.sh

# Real health = the agent's TCP ingest port is listening. (The frankenphp base image
# ships a HEALTHCHECK that curls port 2019, which these feeders never start since the
# entrypoint runs supervisord, not the FrankenPHP server — hence a false "unhealthy".)
HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
  CMD php -r 'exit(@fsockopen("127.0.0.1",2407,$e,$s,2)?0:1);'

ENTRYPOINT ["/usr/local/bin/feeder-entrypoint.sh"]
