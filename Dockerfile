FROM postgres:17.5-alpine

LABEL maintainer="vasyakrg@gmail.com"

RUN apk add --no-cache bash pigz rclone curl tzdata \
  && rm -rf /var/cache/apk/*

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

ENTRYPOINT ["backup.sh"]
