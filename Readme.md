# dbops-project
Исходный репозиторий для выполнения проекта дисциплины "DBOps"

## Создадим базу данных и пользователя для миграций

Создание базы данных `store`:

```sql
CREATE DATABASE store;
```

## Создадим пользователя для подключения к базе данных и запуска автотестов и миграций и дадим ему права на создание

```sql
CREATE USER store_user WITH PASSWORD 'store_password';
\c store
GRANT CREATE ON SCHEMA public TO store_user;
```

## Заполнены значения secrets для GitHub Actions для базы на полученной виртуальной машине с полученными данными для миграций:

```text
DB_HOST
DB_PORT
DB_NAME
DB_USER
DB_PASSWORD
```
