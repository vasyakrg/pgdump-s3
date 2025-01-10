ARG DOCKER_BASEIMAGE=postgres:16-alpine
FROM ${DOCKER_BASEIMAGE}

RUN apk add --no-cache python3 py3-pip && \
  apk add --no-cache bash curl && \
  python3 -m ensurepip && \
  pip3 install --upgrade pip && \
  pip3 install awscli && \
  rm -rf /var/cache/apk/* && \
  mkdir /backup

ENV AWS_DEFAULT_REGION=us-east-1

COPY entrypoint.sh /usr/local/bin/entrypoint
COPY backup.sh /usr/local/bin/backup
COPY pguri.py /usr/local/bin/pguri

CMD /usr/local/bin/entrypoint
