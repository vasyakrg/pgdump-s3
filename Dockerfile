ARG DOCKER_BASEIMAGE
FROM ${DOCKER_BASEIMAGE}

RUN apk add --no-cache \
  python3 \
  py3-pip \
  && pip install awscli \
  && mkdir /backup

ENV AWS_DEFAULT_REGION=us-east-1

COPY entrypoint.sh /usr/local/bin/entrypoint
COPY backup.sh /usr/local/bin/backup
COPY pguri.py /usr/local/bin/pguri

CMD /usr/local/bin/entrypoint
