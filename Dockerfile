FROM wordpress:latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl mariadb-server \
    && curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp \
    && rm -rf /var/lib/apt/lists/*

COPY docker/start-wordpress.sh /usr/local/bin/start-wordpress.sh
COPY docker/seed-rooms.sh /usr/local/bin/seed-rooms.sh
COPY docker/style-site.sh /usr/local/bin/style-site.sh

RUN chmod +x /usr/local/bin/start-wordpress.sh /usr/local/bin/seed-rooms.sh /usr/local/bin/style-site.sh

EXPOSE 80

ENTRYPOINT ["start-wordpress.sh"]
CMD ["apache2-foreground"]
