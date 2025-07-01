# 🚀 Baltic DNS - Быстрый старт

## Развертывание одной командой

```bash
# Клонируем проект
git clone <repo-url> baltic-dns
cd baltic-dns

# Запускаем автоматическое развертывание
./deploy.sh
```

## 📋 Что нужно подготовить

1. **DNS записи** (ОБЯЗАТЕЛЬНО):
```
your-domain.com.        IN  A   YOUR_SERVER_IP
test.your-domain.com.   IN  A   YOUR_SERVER_IP
```

2. **Открытые порты**: 53, 80, 443, 853

3. **Установленный Docker**:
```bash
# Ubuntu/Debian
apt update && apt install -y docker.io docker-compose-plugin

# CentOS/RHEL  
yum install -y docker docker-compose
```

## 🛠 Доступные скрипты

### `./deploy.sh` - Полное развертывание
```bash
./deploy.sh                 # Интерактивное развертывание
./deploy.sh --config        # Только создание конфигов
./deploy.sh --dns-check-only # Только проверка DNS
```

### `./configure.sh` - Изменение настроек
```bash
./configure.sh                # Интерактивное изменение
./configure.sh --change-domain # Смена домена
./configure.sh --change-ip     # Смена IP
./configure.sh --change-password # Смена пароля
```

### `./scripts/generate-dynamic-config.sh` - Генерация Traefik конфигов
```bash
./scripts/generate-dynamic-config.sh
```

## ⚡ Основные команды

```bash
# Статус
docker compose ps

# Логи
docker compose logs -f

# Перезапуск
docker compose restart

# Остановка
docker compose down
```

## 🌐 После развертывания

- **Админка**: https://your-domain.com (admin / ваш_пароль)
- **DNS сервер**: YOUR_SERVER_IP:53
- **DoT**: your-domain.com:853  
- **DoH**: https://your-domain.com/dns-query

## 🆘 Проблемы?

1. **DNS не работает**: `nslookup your-domain.com`
2. **SSL ошибки**: `docker logs traefik`
3. **Админка недоступна**: `docker logs admin`

📖 Подробная документация: [DEPLOYMENT.md](DEPLOYMENT.md)