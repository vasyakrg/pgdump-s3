# Скрипт для резервного копирования PostgreSQL в S3

## Описание

- Скрипт автоматизирует резервное копирование баз данных PostgreSQL и их сохранение в S3-совместимом хранилище.
- Поддерживается однократный запуск, работа по расписанию через cron, исключение баз данных, управление ротацией старых бэкапов и сжатие.

## Возможности

- Резервное копирование всех баз данных или указанных вручную.
- Исключение определённых баз данных из бэкапа.
- Сохранение дампов в формате sql или -Fc.
- Сжатие дампов с использованием pigz.
- Сохранение бэкапов в S3-совместимом хранилище.
- Ротация старых бэкапов по времени или количеству версий.
- Автоматическая настройка cron задачи для регулярного резервного копирования.
- Восстановление баз данных из бэкапа (ручное или по расписанию)
- Поддержка отдельных настроек S3 для восстановления
- Восстановление всех баз или выборочное восстановление

## Переменные окружения

### Настройки PostgreSQL

| Переменная          | Описание                                        | Значение по умолчанию |
|---------------------|-------------------------------------------------|-----------------------|
| `POSTGRES_HOST`     | Хост PostgreSQL                                 | `localhost`           |
| `POSTGRES_PORT`     | Порт PostgreSQL                                 | `5432`                |
| `POSTGRES_USER`     | Пользователь PostgreSQL                         | `postgres`            |
| `POSTGRES_PASSWORD` | Пароль PostgreSQL                               | `password`            |
| `BACKUP_DATABASES`  | Базы данных для бэкапа (`all` или перечисление) | `all`                 |
| `EXCLUDE_DB`        | Базы данных, которые нужно исключить            | -                     |

---

### Настройки S3

| Переменная             | Описание                          | Значение по умолчанию |
|------------------------|-----------------------------------|-----------------------|
| `S3_BUCKET`            | Имя S3 бакета                     | -                     |
| `S3_ENDPOINT`          | URL S3 совместимого хранилища     | -                     |
| `S3_ACCESS_KEY_ID`     | Ключ доступа к S3                 | -                     |
| `S3_SECRET_ACCESS_KEY` | Секретный ключ доступа к S3       | -                     |
| `S3_REGION`            | Регион S3                         | -                     |
| `S3_PATH`              | Путь внутри S3 бакета             | `backups`             |
| `S3_PATH_STYLE`        | Использование `path-style` режима | `true`                |

---

### Настройки бэкапа

| Переменная              | Описание                                      | Значение по умолчанию |
|-------------------------|-----------------------------------------------|-----------------------|
| `BACKUP_TYPE`           | Тип дампа: `sql` или `dump`                   | `sql`                 |
| `BACKUP_RETENTION_DAYS` | Удаление бэкапов старше указанного числа дней | `30`                  |
| `BACKUP_MAX_VERSIONS`   | Количество последних версий для хранения      | `10`                  |

---

### Настройки cron

| Переменная             | Описание                                   | Значение по умолчанию |
|------------------------|--------------------------------------------|-----------------------|
| `BACKUP_CRON_SCHEDULE` | Cron расписание для автоматических бэкапов | -                     |

---

### Настройки восстановления

| Переменная                     | Описание                                           | Значение по умолчанию        |
|--------------------------------|----------------------------------------------------|------------------------------|
| `RESTORE_S3_BUCKET`            | S3 бакет для восстановления                        | как в `S3_BUCKET`            |
| `RESTORE_S3_ENDPOINT`          | Эндпоинт S3 для восстановления                     | как в `S3_ENDPOINT`          |
| `RESTORE_S3_ACCESS_KEY_ID`     | Ключ доступа к S3 для восстановления               | как в `S3_ACCESS_KEY_ID`     |
| `RESTORE_S3_SECRET_ACCESS_KEY` | Секретный ключ S3 для восстановления               | как в `S3_SECRET_ACCESS_KEY` |
| `RESTORE_S3_REGION`            | Регион S3 для восстановления                       | как в `S3_REGION`            |
| `RESTORE_S3_PATH`              | Путь в S3 для восстановления                       | как в `S3_PATH`              |
| `RESTORE_S3_PATH_STYLE`        | Path-style доступ для восстановления               | как в `S3_PATH_STYLE`        |
| `RESTORE_TIMESTAMP`            | Временная метка бэкапа для восстановления          | последний доступный          |
| `RESTORE_DATABASES`            | Список баз данных для восстановления               | все доступные в бэкапе       |
| `RESTORE_CRON_SCHEDULE`        | Cron расписание для автоматического восстановления | -                            |

## Использование

### Однократный запуск

1. Выполните команду:

```bash
docker run --rm \
    --env-file .env \
    postgres-backup
```

2. Скрипт выполнит резервное копирование всех баз данных, загрузит их в S3 и завершит работу.

### Запуск через cron

1. Убедитесь, что указана переменная BACKUP_CRON_SCHEDULE (например, 0 2 * * *).
2. Запустите контейнер:

```bash
docker run --rm \
    --env-file .env \
    postgres-backup
```

3. Контейнер настроит cron и будет ожидать выполнения задач.

### Запуск в docker-compose.yaml

```yaml
services:
  postgres-backup:
    image: psql-backup:latest
    container_name: postgres-backup
    env_file:
      - .env
```

### Восстановление из бэкапа

1. Однократное восстановление:

```bash
docker run --rm \
    --env-file .env \
    postgres-backup restore
```

2. Восстановление конкретных баз:

```bash
docker run --rm \
    -e RESTORE_DATABASES=mydb1,mydb2 \
    --env-file .env \
    postgres-backup restore
```

3. Восстановление из конкретного бэкапа:

```bash
docker run --rm \
    -e RESTORE_TIMESTAMP=20240315120000 \
    --env-file .env \
    postgres-backup restore
```

## Пример .env файла

```bash
# PostgreSQL настройки
PGHOST=localhost
PGPORT=5432
PGUSER=postgres
PGPASSWORD=secret

# Базы для бэкапа
BACKUP_DATABASES=all
EXCLUDE_DB=template0,template1

# Настройки S3
S3_BUCKET=my-backup-bucket
S3_ENDPOINT=https://s3.example.com
S3_ACCESS_KEY_ID=my-access-key
S3_SECRET_ACCESS_KEY=my-secret-key
S3_REGION=us-east-1
S3_PATH_STYLE=true
S3_PATH=backups

# Настройки бэкапа
BACKUP_TYPE=sql

# Ротация
BACKUP_RETENTION_DAYS=30
BACKUP_MAX_VERSIONS=10

# Cron расписание
BACKUP_CRON_SCHEDULE=0 2 * * *
```

## Логика работы

1. Однократный запуск:

- Выполняется создание дампа и его отправка в S3.
- Применяется ротация старых бэкапов (если указаны параметры ротации).

2. Запуск через cron:

- Контейнер добавляет cron задачу (если её ещё нет).
- При наступлении времени cron запускает скрипт с аргументом cron, который выполняет только backup и rotate_backups.

## Примеры

Однократный бэкап:

```basg
docker run --rm \
    -e PGHOST=db.example.com \
    -e PGUSER=admin \
    -e PGPASSWORD=secret \
    -e S3_BUCKET=my-bucket \
    -e BACKUP_TYPE=sql \
    -e BACKUP_DATABASES=mydb1,mydb2 \
    postgres-backup
```

Автоматический бэкап через cron:

```bash
docker run --rm \
    -e BACKUP_CRON_SCHEDULE="0 3 * * *" \
    --env-file .env \
    postgres-backup
```

## Логирование

Скрипт выводит:

- Успешные действия: [ OK ] (зелёный цвет).
- Предупреждения: [ Warn ] (жёлтый цвет).
- Ошибки: [ Fail ] (красный цвет).

### Пример вывода

```bash
[...] Генерация конфигурации rclone
[ OK ] Конфигурация rclone создана
[...] Начало процесса создания бэкапа
[ OK ] SQL бэкап для базы данных mydb1 создан
[...] Копирование бэкапов в S3
[ OK ] Бэкапы скопированы в S3
[...] Ротация по количеству версий
[ OK ] Ротация выполнена
[ OK ] Однократный запуск завершен
```

## Запуск в k8s как CronJob

1. Создание секрета для PostgreSQL и S3

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-backup-secret
  namespace: default
type: Opaque
data:
  POSTGRES_USER: cG9zdGdyZXM=  # base64 от postgres
  POSTGRES_PASSWORD: cG9zdGdyZXM=  # base64 от postgres
  POSTGRES_HOST: cG9zdGdyZXM=  # base64 от postgres
  POSTGRES_PORT: NTQzMg==  # base64 от 5432
  S3_BUCKET: c3luMS1wc3Fs  # base64 от syn1-psql
  S3_ENDPOINT: aHR0cHM6Ly9zMy1nYXRlLmRvbWFpbi5ydQ==  # base64 от https://s3-gate.domain.ru
  S3_ACCESS_KEY_ID: dGVzdA==  # base64 от test
  S3_SECRET_ACCESS_KEY: dGVzdA==  # base64 от test
  S3_REGION: cnUtbXNr  # base64 от ru-msk
  S3_PATH_STYLE: dHJ1ZQ==  # base64 от true
  S3_PATH: YmFja3Vwcw==  # base64 от backups
```

2. Создание ConfigMap для настроек бэкапа

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-backup-config
  namespace: default
data:
  BACKUP_DATABASES: "all"
  EXCLUDE_DB: "postgres"
  BACKUP_TYPE: "sql"
  BACKUP_RETENTION_DAYS: "30"
  BACKUP_MAX_VERSIONS: "10"
```

3. Создание CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: default
spec:
  schedule: "0 3 * * *"  # Запуск каждый день в 3 часа ночи
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: postgres-backup
            image: hub.realmanual.ru/pub/pgdump-s3:2.0.0
            envFrom:
            - secretRef:
                name: postgres-backup-secret
            - configMapRef:
                name: postgres-backup-config
          restartPolicy: OnFailure
```

4. Применение манифестов

Сохраняем манифесты в файлы, например:

- secret.yaml
- configmap.yaml
- cronjob.yaml

Применяем их:

```bash
kubectl apply -f secret.yaml
kubectl apply -f configmap.yaml
kubectl apply -f cronjob.yaml
```

### CronJob для восстановления

1. Создание секрета для восстановления (если отличается от бэкапа)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-restore-secret
  namespace: default
type: Opaque
data:
  POSTGRES_USER: cG9zdGdyZXM=
  POSTGRES_PASSWORD: cG9zdGdyZXM=
  POSTGRES_HOST: cG9zdGdyZXM=
  POSTGRES_PORT: NTQzMg==
  RESTORE_S3_BUCKET: cmVzdG9yZS1idWNrZXQ=
  RESTORE_S3_ENDPOINT: aHR0cHM6Ly9zMy1nYXRlLmRvbWFpbi5ydQ==
  RESTORE_S3_ACCESS_KEY_ID: dGVzdA==
  RESTORE_S3_SECRET_ACCESS_KEY: dGVzdA==
  RESTORE_S3_REGION: cnUtbXNr
```

2. Создание ConfigMap для настроек восстановления

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-restore-config
  namespace: default
data:
  RESTORE_DATABASES: "mydb1,mydb2"  # Опционально, если нужны конкретные базы
  RESTORE_TIMESTAMP: ""  # Пустое значение для последнего бэкапа
```

3. Создание CronJob для восстановления

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-restore
  namespace: default
spec:
  schedule: "0 4 * * 0"  # Пример: каждое воскресенье в 4 утра
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: postgres-restore
            image: hub.realmanual.ru/pub/pgdump-s3:2.0.0
            args: ["restore"]
            envFrom:
            - secretRef:
                name: postgres-restore-secret
            - configMapRef:
                name: postgres-restore-config
          restartPolicy: OnFailure
```

4. Применение манифестов:

```bash
kubectl apply -f restore-secret.yaml
kubectl apply -f restore-configmap.yaml
kubectl apply -f restore-cronjob.yaml
```

Важно: При настройке восстановления по расписанию убедитесь, что:

- Время восстановления не пересекается со временем создания бэкапов
- У вас есть достаточно ресурсов для выполнения операции
- Настроено корректное управление конфликтами при восстановлении существующих баз данных
