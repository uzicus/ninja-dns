# 🥷 Ninja DNS - Portable SmartDNS Proxy System

Система для обхода геоблокировки с поддержкой современных DNS протоколов, веб-админкой и **автоматическим развертыванием на любых серверах**.

## ✨ Новое в v3.0

🚀 **Полная портативность** - развертывание одной командой на любом сервере  
🔧 **Автоматическая настройка** - интерактивная конфигурация доменов и IP  
🛡️ **DNS валидация** - проверка корректности настройки перед запуском  
📋 **Простая миграция** - перенос между серверами за минуты  
🔄 **Горячая перенастройка** - изменение параметров без переустановки  

## 🚀 Быстрый старт

```bash
# Один скрипт для развертывания на любом сервере
git clone <your-repo> baltic-dns && cd baltic-dns
./deploy.sh
```

**Всё!** Система автоматически:
- Проверит DNS настройки
- Создаст конфигурации  
- Получит SSL сертификаты
- Запустит все сервисы
- Настроит мониторинг

## 🏗 Архитектура

```
                    ┌─────────────────┐
                    │   Client Apps   │
                    └─────────────────┘
                             │
                    ┌─────────────────┐
                    │ Baltic DNS      │
                    │ (YOUR_DOMAIN)   │  
                    └─────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌─────────┐          ┌─────────┐          ┌─────────┐
   │SmartDNS │          │sniproxy │          │ Traefik │
   │Port: 53 │          │Port:443 │          │Port:443 │
   │DoT: 853 │          │         │          │Let's    │
   └─────────┘          └─────────┘          │Encrypt  │
        │                    │               └─────────┘
        │               ┌─────────┐               │
        │               │Real     │               │
        │               │Servers  │               │
        │               └─────────┘               │
        │                                         │
   ┌─────────┐                               ┌─────────┐
   │Upstream │                               │Web      │
   │DNS      │                               │Admin    │
   └─────────┘                               └─────────┘
```

### Компоненты

- **SmartDNS**: DNS сервер с DoH/DoT поддержкой (~10MB RAM)
- **sniproxy**: HTTPS проксирование по SNI (~5MB RAM)  
- **Traefik**: Реверс-прокси + Let's Encrypt (~20MB RAM)
- **Admin Panel**: Веб-управление доменами (~10MB RAM)
- **DoH Proxy**: HTTP/2 DNS over HTTPS (~5MB RAM)

**Общее потребление**: 50-80MB RAM

## 📋 Требования

### Сервер
- **OS**: Ubuntu 18.04+ / Debian 10+ / CentOS 7+
- **RAM**: 512MB+ (рекомендуется 1GB+)
- **CPU**: 1 ядро (рекомендуется 2+)
- **Диск**: 2GB+ свободного места
- **Порты**: 53, 80, 443, 853

### DNS настройки
```bash
# ОБЯЗАТЕЛЬНО: Настройте A-записи перед развертыванием
your-domain.com.        IN  A   YOUR_SERVER_IP
test.your-domain.com.   IN  A   YOUR_SERVER_IP
```

### Программное обеспечение
- Docker 20.10+
- Docker Compose 2.0+
- Доступ в интернет для Let's Encrypt

## 🛠 Установка

### 1. Автоматическое развертывание (рекомендуется)

```bash
# Скачиваем и разворачиваем
git clone <repo-url> baltic-dns
cd baltic-dns
./deploy.sh
```

Скрипт запросит:
- **Домен**: Основной домен (например: `dns.example.com`)
- **IP**: IP адрес сервера (определяется автоматически)
- **Email**: Для Let's Encrypt уведомлений
- **Пароль**: Для веб-админки

### 2. Быстрая настройка существующей системы

```bash
# Изменить настройки
./configure.sh

# Только сменить домен
./configure.sh --change-domain

# Только сменить IP
./configure.sh --change-ip
```

### 3. Ручная установка

```bash
# 1. Настройка конфигурации
cp .env.example .env
nano .env  # Отредактируйте параметры

# 2. Генерация конфигов
./scripts/generate-dynamic-config.sh

# 3. Создание паролей
mkdir -p traefik/auth
htpasswd -c traefik/auth/.htpasswd admin

# 4. Запуск
docker compose up -d
```

## 🎛 Управление

### Веб-админка

```
URL: https://your-domain.com
Логин: admin
Пароль: (из .env файла)
```

**Функции:**
- ➕ Добавление/удаление доменов
- 📊 Мониторинг статуса сервисов  
- ⚡ Real-time WebSocket обновления
- 🔍 Валидация доменов перед добавлением
- 📱 Mobile-friendly интерфейс

### CLI команды

```bash
# Статус системы
docker compose ps

# Логи
docker compose logs -f [service]

# Перезапуск
docker compose restart

# Добавление домена через API
curl -X POST -H "Content-Type: application/json" \
  -u admin:password \
  -d '{"name":"netflix.com","category":"streaming"}' \
  https://your-domain.com/api/domains
```

## 🧪 Тестирование

### DNS проверки
```bash
# Обычный DNS
nslookup netflix.com YOUR_SERVER_IP

# DNS over TLS
kdig @YOUR_SERVER_IP +tls netflix.com

# DNS over HTTPS  
curl -H "Accept: application/dns-json" \
  "https://your-domain.com/dns-query?name=netflix.com&type=A"
```

### HTTPS проксирование
```bash
# Тест проксирования
curl -I https://netflix.com \
  --resolve netflix.com:443:YOUR_SERVER_IP
```

## 🔧 Конфигурация

### Переменные окружения

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `HOST_DOMAIN` | Основной домен | `dns.uzicus.ru` |
| `SERVER_IP` | IP сервера | `185.237.95.211` |
| `TEST_SUBDOMAIN` | Тестовый поддомен | `test` |
| `ACME_EMAIL` | Email для Let's Encrypt | `admin@uzicus.ru` |
| `ADMIN_PASSWORD` | Пароль админки | `NinjaDNS2024!` |

### Структура файлов

```
baltic-dns/
├── deploy.sh              # 🚀 Автоматическое развертывание
├── configure.sh           # 🔧 Перенастройка системы  
├── .env.example           # 📋 Шаблон конфигурации
├── docker-compose.yml     # 🐳 Оркестрация сервисов
├── domains.json           # 📝 Список доменов (генерируется)
├── scripts/
│   └── generate-dynamic-config.sh  # 🔄 Генерация Traefik конфигов
├── traefik/
│   ├── traefik.yml        # ⚙️ Основная конфигурация Traefik
│   ├── dynamic/
│   │   ├── dynamic.yml.template  # 📄 Шаблон маршрутов
│   │   └── dynamic.yml    # 🔀 Сгенерированные маршруты
│   └── auth/
│       └── .htpasswd      # 🔐 Пароли (генерируется)
├── admin/                 # 🖥️ Веб-админка
└── DEPLOYMENT.md          # 📖 Подробное руководство
```

## 🚚 Миграция между серверами

### Экспорт конфигурации
```bash
# На старом сервере
tar -czf baltic-backup.tar.gz .env domains.json traefik/auth/
```

### Импорт на новый сервер
```bash
# На новом сервере
./deploy.sh --config      # Создаем базовую конфигурацию
docker compose down       # Останавливаем
tar -xzf baltic-backup.tar.gz  # Восстанавливаем настройки
./configure.sh --change-ip     # Обновляем IP
docker compose up -d      # Запускаем
```

## 🔍 Диагностика и мониторинг

### Автоматическая диагностика
```bash
# Полная диагностика системы
./diagnose.sh

# Быстрая проверка
./diagnose.sh --quick

# Диагностика с автоисправлением
./diagnose.sh --fix
```

### Мониторинг в реальном времени
```bash
# Полный мониторинг
./monitor.sh

# Компактный режим
./monitor.sh --compact

# Только алерты и проблемы
./monitor.sh --alerts-only
```

### Что проверяется автоматически
- ✅ **Системные требования** (Docker, память, диск)
- ✅ **Сетевые порты** (53, 80, 443, 853)
- ✅ **DNS настройки** (резолвинг доменов)
- ✅ **Docker контейнеры** (статус, ресурсы, логи)
- ✅ **Сетевые сервисы** (HTTP, HTTPS, SSL сертификаты)
- ✅ **DNS функциональность** (обычный DNS, DoH, DoT)
- ✅ **Веб-админка** (доступность, API, WebSocket)
- ✅ **Производительность** (скорость ответов)

## 📊 Мониторинг

### Системные метрики
```bash
# Использование ресурсов
docker stats --no-stream

# Дисковое пространство
docker system df

# Сетевая активность
docker compose logs --tail=100
```

### API мониторинга
```bash
# Статус сервисов
curl -u admin:password https://your-domain.com/api/status

# Список доменов  
curl -u admin:password https://your-domain.com/api/domains
```

## 🔒 Безопасность

- 🛡️ **HTTP Basic Auth** для админки
- 🔐 **Rate Limiting** (100 req/min)
- 📜 **Let's Encrypt** SSL сертификаты
- 🚫 **Минимальное логирование** для приватности
- 🔄 **Автоматическое обновление** сертификатов

## 🌍 Настройка клиентов

### Использование DNS

**Обычный DNS:**
```
DNS сервер: YOUR_SERVER_IP
```

**DNS over TLS (Android 9+, iOS 14+):**
```
Сервер: your-domain.com
Порт: 853
```

**DNS over HTTPS (современные браузеры):**
```
URL: https://your-domain.com/dns-query
```

### Профили для iOS/macOS

Загрузите готовые профили:
- https://your-domain.com/download/mobileconfig
- https://your-domain.com/download/mobileconfig-macos

## 🎯 Примеры использования

### Разблокировка стриминговых сервисов
```bash
# Через веб-админку добавьте:
netflix.com
hulu.com  
disney.com
```

### Обход блокировок соцсетей
```bash
# Добавьте домены:
facebook.com
instagram.com
twitter.com
```

### Доступ к AI сервисам
```bash
# Уже преднастроено:
claude.ai
openai.com
chatgpt.com
```

## 🤝 Поддержка

### Документация
- 📖 [Подробное руководство](DEPLOYMENT.md)
- 🔍 [Диагностика и мониторинг](DIAGNOSTICS.md)
- 🚀 [Быстрый старт](QUICK_START.md)
- 🐳 [Docker документация](https://docs.docker.com/)
- 🔀 [Traefik документация](https://doc.traefik.io/traefik/)

### Сообщество
- 🐛 [Сообщить о проблеме](../../issues)
- 💡 [Предложить улучшение](../../issues)
- 🔧 [Pull Requests приветствуются](../../pulls)

## 📝 Лицензия

MIT License - смотрите файл [LICENSE](LICENSE)

## 🙏 Благодарности

- [SmartDNS](https://github.com/pymumu/smartdns) - за отличный DNS сервер
- [Traefik](https://traefik.io/) - за простую настройку reverse proxy
- [Let's Encrypt](https://letsencrypt.org/) - за бесплатные SSL сертификаты

---

⭐ **Понравился проект? Поставьте звездочку!**

🥷 **Ninja DNS - ваш путь к свободному интернету!**