# dbops-project
Исходный репозиторий для выполнения проекта дисциплины "DBOps"

## Создадим базу данных и пользователя для миграций

Создание базы данных `store`:

```sql
CREATE DATABASE store;
```

## Создадим пользователя для подключения к базе данных и запуска автотестов и миграций

```sql
CREATE USER store_user WITH PASSWORD 'store_password';
```

