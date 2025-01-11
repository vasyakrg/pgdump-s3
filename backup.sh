#!/bin/bash

set -e

# Цвета для логирования
GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"

# Функция для логирования успешных шагов
log_success() {
    echo -e "${GREEN}[ OK ]${RESET} $1"
}

# Функция для логирования ошибок
log_fail() {
    echo -e "${RED}[ Fail ]${RESET} $1"
    exit 1
}

# Функция для логирования обычных шагов
log_step() {
    echo -e "[...] $1"
}

# Переменные окружения
: "${POSTGRES_HOST:=localhost}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_PASSWORD:=password}"
: "${BACKUP_CRON_SCHEDULE:=}"
: "${BACKUP_TYPE:=sql}" # sql или -Fc
: "${BACKUP_DATABASES:=all}" # all или перечисленные базы через запятую
: "${EXCLUDE_DB:=}" # Список баз данных через запятую, которые нужно исключить из бэкапа
: "${BACKUP_RETENTION_DAYS:=30}"
: "${BACKUP_MAX_VERSIONS:=10}"
: "${S3_BUCKET:=}"
: "${S3_ENDPOINT:=}"
: "${S3_PATH_STYLE:=true}"
: "${S3_REGION:=}"
: "${S3_PATH:=backups}"
: "${S3_ACCESS_KEY_ID:=}"
: "${S3_SECRET_ACCESS_KEY:=}"

# Генерация rclone конфигурации
generate_rclone_config() {
    log_step "Генерация конфигурации rclone"
    mkdir -p /root/.config/rclone
    cat > /root/.config/rclone/rclone.conf <<EOF
[s3]
type = s3
provider = Minio
env_auth = false
access_key_id = ${S3_ACCESS_KEY_ID}
secret_access_key = ${S3_SECRET_ACCESS_KEY}
endpoint = ${S3_ENDPOINT}
region = ${S3_REGION}
path_style = ${S3_PATH_STYLE}
EOF

  log_success "Конфигурация rclone создана"
}

# Устанавливаем переменные окружения для pg_dump
export PGPASSWORD=${POSTGRES_PASSWORD}

# Создание бэкапа
backup() {
    log_step "Начало процесса создания бэкапа"
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_DIR="/tmp/backups/${TIMESTAMP}"
    mkdir -p "${BACKUP_DIR}"

    PSQL_URI="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}"


    if [ "${BACKUP_DATABASES}" == "all" ]; then
        log_step "Получение списка всех баз данных"
        DATABASES=$(psql "${PSQL_URI}" -tAc "SELECT datname FROM pg_database WHERE datistemplate = false;") || log_fail "Не удалось получить список баз данных"
        if [ -z "${DATABASES}" ]; then
            log_warning "На сервере нет ни одной базы данных. Работа завершена."
            exit 0
        fi

        if [ -n "${EXCLUDE_DB}" ]; then
            log_step "Исключение баз данных: ${EXCLUDE_DB}"
            for EXCLUDED in $(echo "${EXCLUDE_DB}" | tr ',' ' '); do
                DATABASES=$(echo "${DATABASES}" | grep -vw "${EXCLUDED}")
            done
        fi

        if [ -z "${DATABASES}" ]; then
            log_warning "Все базы данных исключены из бэкапа. Работа завершена."
            exit 0
        fi

        DATABASES_LIST=$(echo "${DATABASES}" | tr '\n' ',' | sed 's/,$//')
        log_success "Список баз данных: ${DATABASES_LIST}"
    else
        IFS=',' read -ra DATABASES <<< "${BACKUP_DATABASES}"
        if [ -n "${EXCLUDE_DB}" ]; then
            log_step "Исключение баз данных: ${EXCLUDE_DB}"
            DATABASES=($(echo "${DATABASES[@]}" | tr ' ' '\n' | grep -vwF -f <(echo "${EXCLUDE_DB}" | tr ',' '\n')))
        fi

        if [ ${#DATABASES[@]} -eq 0 ]; then
            log_warning "Все указанные базы данных исключены из бэкапа. Работа завершена."
            exit 0
        fi

        DATABASES_LIST=$(echo "${DATABASES[@]}" | tr ' ' ',')
        log_success "Указанные базы данных для бэкапа: ${DATABASES_LIST}"
    fi

    for DB in ${DATABASES}; do
        log_step "Создание бэкапа для базы данных ${DB}"
        BACKUP_FILE="${BACKUP_DIR}/${DB}.${BACKUP_TYPE}"

        if [ "${BACKUP_TYPE}" == "sql" ]; then
            log_step "Создание SQL бэкапа для базы данных ${DB}"
            pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" "${DB}" | pigz > "${BACKUP_FILE}.gz" || log_fail "Не удалось создать бэкап базы ${DB}"
            log_success "SQL бэкап для базы данных ${DB} создан"
        else
            log_step "Создание бэкапа для базы данных ${DB} в формате custom"
            pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -Fc "${DB}" -f "${BACKUP_FILE}" || log_fail "Не удалось создать бэкап базы ${DB}"
            log_success "Бэкап для базы данных ${DB} в формате custom создан"
        fi
    done

    # Архивируем в S3
    FOLDER_NAME=$(date +%Y%m%d%H%M%S)
    log_step "Копирование бэкапов в S3"
    rclone copy "${BACKUP_DIR}" "s3:${S3_BUCKET}/${S3_PATH}/${FOLDER_NAME}" || log_fail "Не удалось скопировать бэкапы в S3"
    log_success "Бэкапы скопированы в S3"

    # Удаление временных файлов
    log_step "Удаление временных файлов"
    rm -rf "${BACKUP_DIR}"
    log_success "Временные файлы удалены"
}

# Ротация старых бэкапов
rotate_backups() {
    if [ -n "${BACKUP_RETENTION_DAYS}" ]; then
        log_step "Ротация по дням (старше ${BACKUP_RETENTION_DAYS} дней)"
        rclone delete "s3:${S3_BUCKET}/${S3_PATH}" --min-age "${BACKUP_RETENTION_DAYS}d" --include "*/" || log_fail "Ошибка ротации по дням"
        log_success "Ротация по дням выполнена"
    fi

    if [ -n "${BACKUP_MAX_VERSIONS}" ]; then
        log_step "Ротация по количеству версий (оставить ${BACKUP_MAX_VERSIONS} папок)"
        # Получаем список папок, сортируем их по имени (включая дату в имени), оставляем ${BACKUP_MAX_VERSIONS} последних
        FOLDERS=$(rclone lsf "s3:${S3_BUCKET}/${S3_PATH}/" --dirs-only | sort -r)
        COUNT=0
        echo "${FOLDERS}" | while read -r folder; do
            COUNT=$((COUNT + 1))
            if [ "${COUNT}" -gt "${BACKUP_MAX_VERSIONS}" ]; then
                log_step "Удаление папки: ${folder}"
                rclone purge "s3:${S3_BUCKET}/${S3_PATH}/${folder}" || log_fail "Ошибка удаления папки ${folder}"
            fi
        done
        log_success "Ротация по количеству версий выполнена"
    fi
}

generate_rclone_config

# Проверяем, как запускается скрипт
if [ "$1" == "cron" ]; then
    # Скрипт запущен cron
    log_step "Выполнение через cron"
    backup
    rotate_backups
    log_success "Cron задача завершена"
    exit 0
fi

if [ -n "${BACKUP_CRON_SCHEDULE}" ]; then
    # Проверяем наличие задачи в crontab
    log_step "Настройка cron задачи"
    if ! grep -Fxq "${BACKUP_CRON_SCHEDULE} /usr/local/bin/backup.sh cron" /etc/crontabs/root; then
        echo "${BACKUP_CRON_SCHEDULE} /usr/local/bin/backup.sh cron" >> /etc/crontabs/root || log_fail "Не удалось записать cron задачу"
        log_success "Cron задача добавлена: ${BACKUP_CRON_SCHEDULE}"
    else
        log_step "Cron задача уже существует, пропускаем добавление"
    fi

    log_step "Запуск crond"
    exec crond -f
else
    # Выполняем однократный запуск
    log_step "Запуск однократного запуска"
    backup
    rotate_backups
    log_success "Однократный запуск завершен"
    exit 0
fi
