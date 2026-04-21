FROM wordpress:latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends mariadb-server \
    && rm -rf /var/lib/apt/lists/*

COPY docker/start-wordpress.sh /usr/local/bin/start-wordpress.sh

RUN chmod +x /usr/local/bin/start-wordpress.sh

EXPOSE 80

ENTRYPOINT ["start-wordpress.sh"]
CMD ["apache2-foreground"]
