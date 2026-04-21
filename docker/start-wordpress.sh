#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '[bootstrap] %s\n' "$*"
}

generate_password() {
    php -r 'echo bin2hex(random_bytes(12));'
}

sql_string() {
    printf "%s" "$1" | sed "s/'/''/g"
}

sql_ident() {
    printf "%s" "$1" | sed 's/`/``/g'
}

configure_apache_port() {
    local port="${PORT:-80}"

    sed -ri "s/Listen [0-9]+/Listen ${port}/" /etc/apache2/ports.conf
    sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:${port}>/" /etc/apache2/sites-available/000-default.conf

    if [ -f /etc/apache2/sites-available/default-ssl.conf ]; then
        sed -ri "s/<VirtualHost _default_:[0-9]+>/<VirtualHost _default_:${port}>/" /etc/apache2/sites-available/default-ssl.conf
    fi
}

prepare_wordpress_storage() {
    mkdir -p "${APP_DATA_DIR}" "${MYSQL_DATA_DIR}" "${WP_CONTENT_DIR}" /run/mysqld

    # Backfill default themes/plugins from the image without overwriting persisted content.
    if [ -d /usr/src/wordpress/wp-content ]; then
        cp -an /usr/src/wordpress/wp-content/. "${WP_CONTENT_DIR}/"
    fi

    rm -rf /var/www/html/wp-content
    ln -sfn "${WP_CONTENT_DIR}" /var/www/html/wp-content

    chown -R mysql:mysql "${MYSQL_DATA_DIR}" /run/mysqld
    chown -R www-data:www-data "${WP_CONTENT_DIR}"
}

wait_for_mysql() {
    local tries=60

    until mysqladmin --protocol=socket --socket="${MYSQL_SOCKET}" ping >/dev/null 2>&1; do
        tries=$((tries - 1))
        if [ "${tries}" -le 0 ]; then
            log "MySQL did not become ready in time"
            exit 1
        fi
        sleep 1
    done
}

start_local_mysql() {
    if [ ! -d "${MYSQL_DATA_DIR}/mysql" ]; then
        log "Initializing local MySQL data directory"
        mariadb-install-db --user=mysql --datadir="${MYSQL_DATA_DIR}" --skip-test-db >/dev/null
    fi

    log "Starting local MySQL"
    mariadbd \
        --user=mysql \
        --datadir="${MYSQL_DATA_DIR}" \
        --bind-address=127.0.0.1 \
        --port=3306 \
        --socket="${MYSQL_SOCKET}" &
    MYSQL_PID=$!

    trap 'if [ -n "${MYSQL_PID:-}" ] && kill -0 "${MYSQL_PID}" 2>/dev/null; then kill -TERM "${MYSQL_PID}"; wait "${MYSQL_PID}" || true; fi' EXIT

    wait_for_mysql
}

initialize_local_mysql() {
    if [ -f "${MYSQL_INIT_MARKER}" ]; then
        return
    fi

    log "Configuring local MySQL database and user"

    local escaped_db escaped_user escaped_pass escaped_root
    escaped_db="$(sql_ident "${MYSQL_DATABASE}")"
    escaped_user="$(sql_string "${MYSQL_USER}")"
    escaped_pass="$(sql_string "${MYSQL_PASSWORD}")"
    escaped_root="$(sql_string "${MYSQL_ROOT_PASSWORD}")"

    mysql --protocol=socket --socket="${MYSQL_SOCKET}" -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_root}';
CREATE DATABASE IF NOT EXISTS \`${escaped_db}\`;
CREATE USER IF NOT EXISTS '${escaped_user}'@'%' IDENTIFIED BY '${escaped_pass}';
ALTER USER '${escaped_user}'@'%' IDENTIFIED BY '${escaped_pass}';
GRANT ALL PRIVILEGES ON \`${escaped_db}\`.* TO '${escaped_user}'@'%';
FLUSH PRIVILEGES;
SQL

    touch "${MYSQL_INIT_MARKER}"
    chown mysql:mysql "${MYSQL_INIT_MARKER}"
}

use_local_mysql() {
    case "${WORDPRESS_DB_HOST}" in
        127.0.0.1|127.0.0.1:3306|localhost|localhost:3306)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_proxy_https_support() {
    local forwarded_proto_snippet
    forwarded_proto_snippet=$(cat <<'PHP'
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {
    $_SERVER['HTTPS'] = 'on';
}
PHP
)

    if [[ "${WORDPRESS_CONFIG_EXTRA:-}" != *"HTTP_X_FORWARDED_PROTO"* ]]; then
        if [ -n "${WORDPRESS_CONFIG_EXTRA:-}" ]; then
            export WORDPRESS_CONFIG_EXTRA="${WORDPRESS_CONFIG_EXTRA}

${forwarded_proto_snippet}"
        else
            export WORDPRESS_CONFIG_EXTRA="${forwarded_proto_snippet}"
        fi
    fi
}

prepare_wordpress_core_files() {
    cd /var/www/html

    if [ ! -e index.php ] || [ ! -e wp-includes/version.php ]; then
        log "Copying WordPress core files"
        tar --create --file - --directory /usr/src/wordpress --exclude='./wp-content' . | tar --extract --file - --directory /var/www/html
        chown -R www-data:www-data /var/www/html
    fi
}

prepare_wordpress_config() {
    local wp_config_docker

    if [ -s /var/www/html/wp-config.php ]; then
        return
    fi

    for wp_config_docker in /var/www/html/wp-config-docker.php /usr/src/wordpress/wp-config-docker.php; do
        if [ -s "${wp_config_docker}" ]; then
            log "Creating wp-config.php from ${wp_config_docker}"
            awk '
                /put your unique phrase here/ {
                    cmd = "head -c1m /dev/urandom | sha1sum | cut -d\\  -f1"
                    cmd | getline str
                    close(cmd)
                    gsub("put your unique phrase here", str)
                }
                { print }
            ' "${wp_config_docker}" >/var/www/html/wp-config.php
            chown www-data:www-data /var/www/html/wp-config.php || true
            return
        fi
    done

    log "Unable to locate wp-config-docker.php"
    exit 1
}

resolve_wordpress_install_settings() {
    : "${WORDPRESS_SITE_URL:=${RENDER_EXTERNAL_URL:-http://127.0.0.1:${PORT}}}"
    : "${WORDPRESS_SITE_TITLE:=${RENDER_SERVICE_NAME:-WordPress}}"
    : "${WORDPRESS_ADMIN_USER:=admin}"

    if [ -z "${WORDPRESS_ADMIN_EMAIL:-}" ]; then
        if [ -n "${RENDER_EXTERNAL_HOSTNAME:-}" ]; then
            WORDPRESS_ADMIN_EMAIL="admin@${RENDER_EXTERNAL_HOSTNAME}"
        else
            WORDPRESS_ADMIN_EMAIL="admin@example.com"
        fi
    fi

    if [ -n "${WORDPRESS_ADMIN_PASSWORD:-}" ]; then
        ADMIN_PASSWORD_SOURCE="env"
    elif [ -s "${WORDPRESS_ADMIN_PASSWORD_FILE}" ]; then
        WORDPRESS_ADMIN_PASSWORD="$(cat "${WORDPRESS_ADMIN_PASSWORD_FILE}")"
        ADMIN_PASSWORD_SOURCE="file"
    else
        WORDPRESS_ADMIN_PASSWORD="$(generate_password)"
        ADMIN_PASSWORD_SOURCE="generated"
        printf '%s\n' "${WORDPRESS_ADMIN_PASSWORD}" >"${WORDPRESS_ADMIN_PASSWORD_FILE}"
        chmod 600 "${WORDPRESS_ADMIN_PASSWORD_FILE}"
        chown www-data:www-data "${WORDPRESS_ADMIN_PASSWORD_FILE}"
    fi

    export WORDPRESS_SITE_URL
    export WORDPRESS_SITE_TITLE
    export WORDPRESS_ADMIN_USER
    export WORDPRESS_ADMIN_EMAIL
    export WORDPRESS_ADMIN_PASSWORD
    export ADMIN_PASSWORD_SOURCE
}

wp_cli() {
    wp --allow-root --path=/var/www/html "$@"
}

auto_install_wordpress() {
    if wp_cli core is-installed >/dev/null 2>&1; then
        return
    fi

    resolve_wordpress_install_settings

    log "Installing WordPress"
    wp_cli core install \
        --url="${WORDPRESS_SITE_URL}" \
        --title="${WORDPRESS_SITE_TITLE}" \
        --admin_user="${WORDPRESS_ADMIN_USER}" \
        --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
        --admin_email="${WORDPRESS_ADMIN_EMAIL}" \
        --skip-email

    log "WordPress admin username: ${WORDPRESS_ADMIN_USER}"
    log "WordPress admin password (${ADMIN_PASSWORD_SOURCE}): ${WORDPRESS_ADMIN_PASSWORD}"
    log "WordPress admin login: ${WORDPRESS_SITE_URL%/}/wp-admin/"
}

: "${PORT:=80}"
: "${APP_DATA_DIR:=/var/lib/abbeylodge}"
: "${MYSQL_DATABASE:=wordpress}"
: "${MYSQL_USER:=wordpress}"
: "${MYSQL_PASSWORD:=wordpress}"
: "${MYSQL_ROOT_PASSWORD:=change-me-root-password}"
: "${WORDPRESS_DB_HOST:=127.0.0.1:3306}"
: "${WORDPRESS_DB_NAME:=${MYSQL_DATABASE}}"
: "${WORDPRESS_DB_USER:=${MYSQL_USER}}"
: "${WORDPRESS_DB_PASSWORD:=${MYSQL_PASSWORD}}"

MYSQL_DATA_DIR="${APP_DATA_DIR}/mysql"
WP_CONTENT_DIR="${APP_DATA_DIR}/wp-content"
MYSQL_SOCKET="/run/mysqld/mysqld.sock"
MYSQL_INIT_MARKER="${MYSQL_DATA_DIR}/.wordpress-bootstrap-initialized"
WORDPRESS_ADMIN_PASSWORD_FILE="${APP_DATA_DIR}/wordpress-admin-password"

export PORT
export APP_DATA_DIR
export MYSQL_DATABASE
export MYSQL_USER
export MYSQL_PASSWORD
export MYSQL_ROOT_PASSWORD
export WORDPRESS_DB_HOST
export WORDPRESS_DB_NAME
export WORDPRESS_DB_USER
export WORDPRESS_DB_PASSWORD

configure_apache_port
prepare_wordpress_storage
ensure_proxy_https_support

if use_local_mysql; then
    start_local_mysql
    initialize_local_mysql
else
    log "Using external database host ${WORDPRESS_DB_HOST}; skipping local MySQL startup"
fi

prepare_wordpress_core_files
prepare_wordpress_config
auto_install_wordpress

exec /usr/local/bin/docker-entrypoint.sh "$@"
