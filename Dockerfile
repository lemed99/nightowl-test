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

# nightowl/agent is required via a PATH repo (../nightowl-agent) that does NOT exist
# in this build context. Point it at the published GitHub VCS repo and re-resolve
# the two NightOwl packages from VCS (the now-missing path repo is inert, so it can't
# shadow the VCS one). Both are in `require`, so --no-dev keeps them.
COPY composer.json composer.lock ./
RUN composer config repositories.nightowl-agent vcs https://github.com/lemed99/nightowl-agent \
    && composer update nightowl/agent nightowl/agent-simulator \
       --no-dev --no-interaction --no-scripts --optimize-autoloader --with-all-dependencies

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

ENTRYPOINT ["/usr/local/bin/feeder-entrypoint.sh"]
