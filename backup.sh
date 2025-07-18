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
: "${HEALTHCHECK_URL:=}"

# Переменные окружения для восстановления
: "${RESTORE_S3_BUCKET:=}"
: "${RESTORE_S3_ENDPOINT:=}"
: "${RESTORE_S3_PATH_STYLE:=true}"
: "${RESTORE_S3_REGION:=}"
: "${RESTORE_S3_PATH:=backups}"
: "${RESTORE_S3_ACCESS_KEY_ID:=}"
: "${RESTORE_S3_SECRET_ACCESS_KEY:=}"
: "${RESTORE_TIMESTAMP:=}" # Если не указано, берем последний бэкап
: "${RESTORE_DATABASES:=}" # Список баз данных для восстановления через запятую
: "${RESTORE_CRON_SCHEDULE:=}"

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

# Функция для генерации конфигурации rclone для восстановления
generate_restore_rclone_config() {
    log_step "Генерация конфигурации rclone для восстановления"
    mkdir -p /root/.config/rclone
    cat > /root/.config/rclone/rclone.conf <<EOF
[restore]
type = s3
provider = Minio
env_auth = false
access_key_id = ${RESTORE_S3_ACCESS_KEY_ID:-$S3_ACCESS_KEY_ID}
secret_access_key = ${RESTORE_S3_SECRET_ACCESS_KEY:-$S3_SECRET_ACCESS_KEY}
endpoint = ${RESTORE_S3_ENDPOINT:-$S3_ENDPOINT}
region = ${RESTORE_S3_REGION:-$S3_REGION}
path_style = ${RESTORE_S3_PATH_STYLE:-$S3_PATH_STYLE}
EOF

    log_success "Конфигурация rclone для восстановления создана"
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

        # Преобразуем список баз в строку с запятыми
        DATABASES=$(echo "$DATABASES" | xargs | tr ' ' ',')
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
    fi

    for DB in "${DATABASES[@]}"; do
        [ -n "$DB" ] || continue
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

# Функция восстановления из бэкапа
restore() {
    log_step "Начало процесса восстановления из бэкапа"
    RESTORE_DIR="/tmp/restore"
    mkdir -p "${RESTORE_DIR}"

    # Если RESTORE_TIMESTAMP не указан, получаем последний бэкап
    if [ -z "${RESTORE_TIMESTAMP}" ]; then
        log_step "Получение последнего доступного бэкапа"
        RESTORE_TIMESTAMP=$(rclone lsf "restore:${RESTORE_S3_BUCKET:-$S3_BUCKET}/${RESTORE_S3_PATH:-$S3_PATH}/" --dirs-only | sort -r | head -n 1 | tr -d '/')
        if [ -z "${RESTORE_TIMESTAMP}" ]; then
            log_fail "Не найдено ни одного бэкапа"
        fi
        log_success "Найден бэкап: ${RESTORE_TIMESTAMP}"
    fi

    # Скачиваем файлы бэкапа
    log_step "Скачивание файлов бэкапа ${RESTORE_TIMESTAMP}"
    rclone copy "restore:${RESTORE_S3_BUCKET:-$S3_BUCKET}/${RESTORE_S3_PATH:-$S3_PATH}/${RESTORE_TIMESTAMP}" "${RESTORE_DIR}" || log_fail "Не удалось скачать файлы бэкапа"
    log_success "Файлы бэкапа скачаны"

    # Восстанавливаем базы данных
    for BACKUP_FILE in "${RESTORE_DIR}"/*; do
        # Пропускаем если файл не существует (защита от */*)
        [ -f "${BACKUP_FILE}" ] || continue

        DB_NAME=$(basename "${BACKUP_FILE}" | sed -E 's/\.(sql\.gz|Fc|custom)$//')
        log_step "Найдена база данных ${DB_NAME}"

        # Проверяем, нужно ли восстанавливать эту базу
        if [ -n "${RESTORE_DATABASES}" ]; then
            if ! echo "${RESTORE_DATABASES}" | grep -q "${DB_NAME}"; then
                log_step "Пропуск базы ${DB_NAME} (не указана в RESTORE_DATABASES)"
                continue
            fi
        fi

        log_step "Восстановление базы данных ${DB_NAME}"

        # Проверяем существование базы
        if ! psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -lqt | cut -d \| -f 1 | grep -qw "${DB_NAME}"; then
            log_step "Создание базы данных ${DB_NAME}"
            createdb -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" "${DB_NAME}" || log_fail "Не удалось создать базу ${DB_NAME}"
        else
            log_step "Очистка существующей базы данных ${DB_NAME}"
            psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${DB_NAME}" -c "
                DO \$\$
                DECLARE
                    r RECORD;
                BEGIN
                    -- Отключаем только пользовательские триггеры на пользовательских таблицах
                    FOR r IN (
                        SELECT
                            tgname,
                            relname as tablename
                        FROM pg_trigger t
                        JOIN pg_class c ON t.tgrelid = c.oid
                        JOIN pg_namespace n ON c.relnamespace = n.oid
                        WHERE NOT t.tgisinternal
                        AND n.nspname = 'public'
                        AND c.relowner > 10000  -- Пропускаем системные объекты
                    ) LOOP
                        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' DISABLE TRIGGER ' || quote_ident(r.tgname);
                    END LOOP;

                    -- Очищаем только пользовательские таблицы в правильном порядке
                    FOR r IN (
                        WITH RECURSIVE deps AS (
                            SELECT
                                c.relname as tablename,
                                0 as level
                            FROM pg_class c
                            JOIN pg_namespace n ON c.relnamespace = n.oid
                            LEFT JOIN pg_constraint fk ON fk.confrelid = c.oid
                            WHERE c.relkind = 'r'
                            AND n.nspname = 'public'
                            AND c.relowner > 10000  -- Пропускаем системные объекты
                            AND fk.confrelid IS NULL
                            UNION ALL
                            SELECT
                                c.relname,
                                d.level + 1
                            FROM pg_class c
                            JOIN pg_namespace n ON c.relnamespace = n.oid
                            JOIN pg_constraint fk ON fk.confrelid = c.oid
                            JOIN deps d ON d.tablename = (
                                SELECT relname
                                FROM pg_class
                                WHERE oid = fk.conrelid
                            )
                            WHERE c.relkind = 'r'
                            AND n.nspname = 'public'
                            AND c.relowner > 10000  -- Пропускаем системные объекты
                        )
                        SELECT DISTINCT tablename, level
                        FROM deps
                        ORDER BY level DESC
                    ) LOOP
                        EXECUTE 'TRUNCATE TABLE public.' || quote_ident(r.tablename) || ' CASCADE';
                    END LOOP;

                    -- Включаем пользовательские триггеры обратно
                    FOR r IN (
                        SELECT
                            tgname,
                            relname as tablename
                        FROM pg_trigger t
                        JOIN pg_class c ON t.tgrelid = c.oid
                        JOIN pg_namespace n ON c.relnamespace = n.oid
                        WHERE NOT t.tgisinternal
                        AND n.nspname = 'public'
                        AND c.relowner > 10000  -- Пропускаем системные объекты
                    ) LOOP
                        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' ENABLE TRIGGER ' || quote_ident(r.tgname);
                    END LOOP;
                END \$\$;" || log_fail "Не удалось очистить базу ${DB_NAME}"
        fi

        # Восстановление в зависимости от формата
        if [[ "${BACKUP_FILE}" == *.sql.gz ]]; then
            pigz -dc "${BACKUP_FILE}" | psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" "${DB_NAME}" || log_fail "Не удалось восстановить базу ${DB_NAME}"
        elif [[ "${BACKUP_FILE}" == *.Fc || "${BACKUP_FILE}" == *.custom ]]; then
            pg_restore -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${DB_NAME}" --clean --if-exists "${BACKUP_FILE}" || log_fail "Не удалось восстановить базу ${DB_NAME}"
        fi

        log_success "База данных ${DB_NAME} восстановлена"
    done

    # Очистка
    log_step "Удаление временных файлов"
    rm -rf "${RESTORE_DIR}"
    log_success "Временные файлы удалены"
}

# Проверяем, как запускается скрипт
if [ "$1" == "restore" ]; then
    # Восстановление из бэкапа
    generate_restore_rclone_config
    restore
    log_success "Восстановление завершено"
    exit 0
elif [ "$1" == "restore-cron" ]; then
    # Восстановление через cron
    generate_restore_rclone_config
    restore
    log_success "Восстановление через cron завершено"
    exit 0
elif [ "$1" == "cron" ]; then
    # Скрипт запущен cron
    log_step "Выполнение через cron"
    generate_rclone_config
    backup
    if [ -n "${HEALTHCHECK_URL}" ]; then
        log_step "Отправка healthcheck"
        curl -fsS -m 10 --retry 5 -o /dev/null "${HEALTHCHECK_URL}" || log_fail "Не удалось отправить healthcheck"
        log_success "Healthcheck отправлен"
    fi
    rotate_backups
    log_success "Cron задача завершена"
    exit 0
fi

if [ -n "${RESTORE_CRON_SCHEDULE}" ]; then
    # Настройка cron для восстановления
    log_step "Настройка cron задачи для восстановления"
    if ! grep -Fxq "${RESTORE_CRON_SCHEDULE} /usr/local/bin/backup.sh restore-cron" /etc/crontabs/root; then
        echo "${RESTORE_CRON_SCHEDULE} /usr/local/bin/backup.sh restore-cron" >> /etc/crontabs/root || log_fail "Не удалось записать cron задачу для восстановления"
        log_success "Cron задача для восстановления добавлена: ${RESTORE_CRON_SCHEDULE}"
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
    fi

    log_step "Запуск crond"
    exec crond -f
elif [ -n "${BACKUP_CRON_SCHEDULE}" ]; then
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
    generate_rclone_config
    backup
    rotate_backups
    log_success "Однократный запуск завершен"
    exit 0
fi
