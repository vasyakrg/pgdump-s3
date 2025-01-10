ARG DOCKER_BASEIMAGE=postgres:16-alpine
FROM ${DOCKER_BASEIMAGE}

RUN apk add --no-cache python3 py3-pip && \
    apk add --no-cache bash curl && \
    python3 -m ensurepip && \
    pip3 install --upgrade pip

# Создадим виртуальное окружение и установим AWS CLI
RUN python3 -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install awscli && \
    deactivate && \
    mkdir /backup

# Настроим PATH для доступа к awscli
ENV PATH="/opt/venv/bin:$PATH"
ENV AWS_DEFAULT_REGION=us-east-1

COPY entrypoint.sh /usr/local/bin/entrypoint
COPY backup.sh /usr/local/bin/backup
COPY pguri.py /usr/local/bin/pguri

CMD /usr/local/bin/entrypoint
