# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Ninja DNS - SmartDNS + sniproxy + Traefik + Web Admin

## Описание проекта
Система для обхода геоблокировки с поддержкой современных DNS протоколов и веб-админкой для управления доменами.

**VPS**: 185.237.95.211 (SSH доступ)  
**Цель**: Минимальное потребление ресурсов (~60-120MB RAM)  
**Технологии**: Docker Compose, SmartDNS, sniproxy, Traefik, FastAPI, Alpine.js
**Админка**: https://dns.uzicus.ru/

## Архитектура решения

### Компоненты системы

1. **SmartDNS**
   - DNS сервер с поддержкой DoH/DoT
   - Порты: 53/udp (DNS), 853/tcp (DoT)
   - DoH через Traefik на порту 443
   - Потребление: ~10-15MB RAM

2. **sniproxy** 
   - HTTPS проксирование по SNI без расшифровки с динамической конфигурацией
   - Порт: 443/tcp (совместно с Traefik)
   - Использует nginx map для динамического роутинга
   - Потребление: ~5-10MB RAM

3. **Traefik**
   - Реверс-прокси с автоматическими Let's Encrypt сертификатами
   - HTTP/HTTPS маршрутизация для админки и DoH
   - Порты: 80/tcp, 443/tcp
   - Потребление: ~20-30MB RAM

4. **Admin Panel (Новое!)**
   - Веб-интерфейс для управления доменами на FastAPI
   - Темная тема с Tailwind CSS и Alpine.js  
   - Real-time WebSocket обновления статуса сервисов
   - Автоматическая генерация конфигов SmartDNS и sniproxy
   - Потребление: ~10-15MB RAM

### Схема трафика

```
DNS запросы:
Client → 185.237.95.211:53 → SmartDNS (обычный DNS)
Client → 185.237.95.211:853 → SmartDNS (DoT)
Client → 185.237.95.211:443/dns-query → Traefik → DoH-proxy → SmartDNS

HTTPS трафик:
Client → 185.237.95.211:443 → sniproxy (nginx map) → Target Server

Админка:
Browser → dns.uzicus.ru/ → Traefik → Admin Panel (FastAPI)
Browser → dns.uzicus.ru/api/* → Traefik → Admin Panel API
Browser → dns.uzicus.ru/ws → Traefik → Admin Panel WebSocket
```

### Структура проекта на VPS

```
/root/ninja-dns/
├── docker-compose.yml          # Docker Compose конфигурация (5 сервисов)
├── domains.json               # Централизованное хранение доменов
├── traefik/
│   ├── traefik.yml           # Основная конфигурация Traefik
│   ├── auth/
│   │   └── .htpasswd         # Пароли для HTTP Basic Auth
│   └── dynamic/              
│       └── dynamic.yml       # Роутинг для админки и DoH + middlewares безопасности
├── smartdns/
│   └── smartdns.conf         # Генерируется автоматически из domains.json
├── sniproxy/
│   └── nginx.conf            # Генерируется автоматически (динамическая конфигурация)
└── admin/                    # Веб-админка
    ├── Dockerfile
    ├── requirements.txt
    ├── app/
    │   └── main.py           # FastAPI приложение с логированием и CORS защитой
    └── templates/
        └── index.html        # SPA интерфейс
```

## Инструкции по развертыванию

### 1. Подключение к VPS
```bash
ssh root@185.237.95.211
```

### 2. Создание структуры проекта
```bash
mkdir -p /root/ninja-dns/{traefik/dynamic,smartdns,sniproxy}
cd /root/baltic-dns
```

### 3. Запуск системы
```bash
docker-compose up -d
```

### 4. Проверка состояния
```bash
docker-compose ps
docker-compose logs
```

## Тестирование

### DNS (порт 53)
```bash
nslookup google.com 185.237.95.211
dig @185.237.95.211 google.com
```

### DoT (порт 853)
```bash
kdig @185.237.95.211 +tls google.com
```

### DoH (порт 443)
```bash
curl -H "Accept: application/dns-json" \
  "https://185.237.95.211/dns-query?name=google.com&type=A"
```

## Управление доменами через веб-админку

### Доступ к панели администрирования
- **URL**: https://dns.uzicus.ru/
- **Логин**: admin
- **Пароль**: NinjaDNS2024!
- **Интерфейс**: Современная темная тема с минималистичным дизайном
- **Функции**: Добавление/удаление доменов, мониторинг статуса сервисов
- **Безопасность**: HTTP Basic Auth + Rate Limiting (100 req/min)

### Основные операции
1. **Добавление домена**:
   - Введите домен в поле "Добавить домен"
   - Выберите категорию (streaming, ai, social, video, misc)
   - Нажмите "Добавить"
   - Автоматически обновятся конфиги SmartDNS и sniproxy

2. **Удаление домена**:
   - Найдите домен в списке (используйте поиск)
   - Нажмите кнопку корзины
   - Подтвердите удаление в модальном окне

3. **Мониторинг**:
   - В шапке отображается статус всех сервисов (зеленые/красные точки)
   - WebSocket обновления в реальном времени
   - Индикатор подключения к админке

### API Endpoints
```bash
# Получить список доменов
curl https://dns.uzicus.ru/api/domains

# Добавить домен
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"example.com","category":"misc"}' \
  https://dns.uzicus.ru/api/domains

# Удалить домен  
curl -X DELETE https://dns.uzicus.ru/api/domains/example.com

# Статус сервисов
curl https://dns.uzicus.ru/api/status
```

## Управление через консоль

### Просмотр логов
```bash
docker compose logs smartdns
docker compose logs sniproxy  
docker compose logs traefik
docker compose logs admin
```

### Перезапуск сервисов
```bash
docker compose restart
docker compose restart smartdns
```

### Обновление конфигурации (устарело - используйте админку!)
```bash
# Ручное изменение domains.json и перегенерация конфигов
docker compose exec admin python -c "
from app.main import domain_manager
domain_manager.update_configs()
domain_manager.restart_services()
"
```

## Troubleshooting

### Админка не открывается
- Проверить статус админки: `docker compose logs admin`
- Убедиться что sniproxy работает: `docker compose ps`
- Проверить маршрутизацию Traefik: `docker compose logs traefik`

### sniproxy часто перезапускается
- Это было исправлено! Теперь используется динамическая конфигурация
- Если проблема возникла, проверить logs: `docker compose logs sniproxy`
- Убедиться что nginx.conf использует `map $ssl_preread_server_name $backend_pool`

### Домен не добавляется через админку
- Проверить логи админки: `docker compose logs admin`
- Убедиться что домен валидный (без http://, только доменное имя)
- Проверить что домен резолвится: система автоматически валидирует DNS
- Проверить что админка может перезапустить сервисы (доступ к Docker socket)
- Если валидация показывает ошибки DNS - домен может быть заблокирован или недоступен

### DNS не отвечает для нового домена
- Домен должен автоматически добавиться в SmartDNS
- Проверить `domains.json` - должен содержать новый домен
- Перезапустить SmartDNS: `docker compose restart smartdns`

### HTTPS проксирование не работает для домена
- Убедиться что домен добавлен через админку
- Проверить sniproxy конфигурацию: `docker compose exec sniproxy cat /etc/nginx/nginx.conf`
- Перезагрузить nginx: `docker compose exec sniproxy nginx -s reload`

### Проблемы с SSL сертификатами
- Проверить логи Traefik: `docker compose logs traefik`
- Убедиться что домен указывает на IP сервера
- Проверить доступность портов 80/443

## Безопасность

- Все сертификаты автоматически обновляются через Let's Encrypt
- sniproxy не расшифровывает HTTPS трафик
- DoH/DoT обеспечивают шифрование DNS запросов
- Логирование минимизировано для приватности

## Мониторинг ресурсов

```bash
# Потребление памяти
docker stats --no-stream

# Использование дискового пространства  
docker system df

# Сетевая активность
docker-compose logs --tail=100
```

## Команды разработки

### Основные операции
```bash
# Запуск всех сервисов
docker-compose up -d

# Остановка всех сервисов
docker-compose down

# Перезапуск после изменения конфигурации
docker-compose down && docker-compose up -d

# Просмотр состояния всех контейнеров
docker-compose ps

# Просмотр логов всех сервисов
docker-compose logs -f

# Просмотр логов конкретного сервиса
docker-compose logs -f smartdns
docker-compose logs -f sniproxy
docker-compose logs -f traefik
```

### Валидация конфигураций
```bash
# Проверка docker-compose.yml
docker-compose config

# Проверка синтаксиса nginx (sniproxy)
docker-compose exec sniproxy nginx -t

# Проверка конфигурации Traefik
docker-compose exec traefik traefik validate --configfile=/etc/traefik/traefik.yml
```

### Отладка
```bash
# Вход в контейнер для отладки
docker-compose exec smartdns sh
docker-compose exec sniproxy sh
docker-compose exec traefik sh

# Просмотр сетевых соединений
docker-compose exec smartdns netstat -tulpn
docker-compose exec sniproxy netstat -tulpn

# Проверка разрешения DNS внутри контейнера
docker-compose exec smartdns nslookup google.com 127.0.0.1
```

## Важные детали реализации

### Конфигурация портов
- **Traefik**: Использует порты 80, 443 (основные) и 8080 (dashboard)
- **SmartDNS**: Порты 53 (UDP/TCP), 853 (DoT), 6053 (внутренний для DoH)
- **sniproxy**: Порт 8443 (mapped to internal 443)

### Сетевая архитектура
- Все сервисы находятся в единой Docker сети `proxy`
- SmartDNS перенаправляет запросы на заблокированные домены на IP VPS (185.237.95.211)
- sniproxy использует nginx в stream mode для SNI-based проксирования
- Traefik обрабатывает DoH запросы и проксирует их на SmartDNS:6053

### Критические файлы конфигурации
1. **docker-compose.yml**: Главный файл оркестрации (5 сервисов)
2. **domains.json**: Централизованное хранение доменов (источник истины)
3. **admin/app/main.py**: FastAPI приложение с логикой управления
4. **smartdns/smartdns.conf**: Генерируется автоматически из domains.json
5. **sniproxy/nginx.conf**: Генерируется автоматически (динамическая конфигурация)
6. **traefik/dynamic/dynamic.yml**: Роутинг для админки, API и DoH

### Особенности новой архитектуры
- **Динамическая конфигурация sniproxy**: Используется nginx map вместо статических upstream'ов
- **Graceful reload**: nginx перезагружается без простоев (`nginx -s reload`)
- **Централизованное управление**: Все домены хранятся в одном JSON файле
- **Автоматическая генерация**: Конфиги SmartDNS и sniproxy создаются программно
- **Устойчивость к ошибкам**: Если домен не резолвится, система продолжает работать

### Особенности безопасности
- Админка доступна только по HTTPS с Let's Encrypt сертификатами
- sniproxy не расшифровывает SSL/TLS трафик, только читает SNI
- Минимальное логирование для приватности пользователей
- Docker socket доступен только админке для управления сервисами

### Примечания по производительности
- Общее потребление памяти: ~60-120MB (включая админку)
- SmartDNS кеширует DNS ответы для ускорения
- nginx в stream mode с динамическим роутингом
- WebSocket соединения для real-time обновлений
- Автоматическая генерация конфигов без ручного редактирования

## Важные заметки и памятки

### Основные принципы работы с системой
- **Используй веб-админку**: https://dns.uzicus.ru/ для управления доменами
- **Не редактируй конфиги вручную**: smartdns.conf и nginx.conf генерируются автоматически
- **Источник истины**: domains.json - единственное место где хранятся домены
- **Проверяй статус**: В админке видны статусы всех сервисов в реальном времени

### Быстрые команды
```bash
# Статус всех сервисов  
docker compose ps

# Перезапуск всей системы
docker compose restart

# Просмотр логов админки
docker compose logs admin -f

# Проверка nginx конфигурации sniproxy
docker compose exec sniproxy nginx -t

# Graceful reload sniproxy
docker compose exec sniproxy nginx -s reload

# Принудительная регенерация конфигов
docker compose exec admin python -c "
from app.main import domain_manager
domain_manager.update_configs()
"
```

### Тестирование функциональности
```bash
# DNS
nslookup netflix.com 185.237.95.211

# DoH  
curl -H "Accept: application/dns-json" \
  "https://dns.uzicus.ru/dns-query?name=google.com&type=A"

# Админка API (требует пароль)
curl -u admin:NinjaDNS2024! https://dns.uzicus.ru/api/status
curl -u admin:NinjaDNS2024! https://dns.uzicus.ru/api/domains
```

## Changelog

### v2.2 - Критические исправления безопасности
- ✅ **Добавлена HTTP Basic Auth защита админки** (логин: admin, пароль: NinjaDNS2024!)
- ✅ **Закрыт публичный доступ к Traefik Dashboard** (только localhost:8080)
- ✅ **Добавлен Rate Limiting** (100 req/min с burst 200) для админки
- ✅ **Исправлены проблемы HTTPS валидации** (убрано verify=False)
- ✅ **Добавлены строгие таймауты** (5 сек) для внешних запросов
- ✅ **CORS защита** только для dns.uzicus.ru
- ✅ **Подробное логирование** всех операций с IP адресами
- ✅ **DoH остается публично доступным** без аутентификации
- ✅ **Все admin routes защищены** паролем (/api, /ws, /, /admin)

### v2.1 - Валидация доменов и статические upstream'ы
- ✅ Добавлена система валидации доменов в админке
- ✅ DomainValidator класс с проверкой формата, DNS резолвинга и HTTPS
- ✅ Предотвращение добавления невалидных доменов
- ✅ Использование Python socket вместо nslookup для DNS резолвинга
- ✅ Статические upstream'ы для проблемных доменов (IPv6 issues)
- ✅ Исправлена проблема с DNS резолвингом в контейнере админки
- ✅ Автоматическое создание тестовых сценариев для проверки системы

### v2.0 - Веб-админка и динамическая конфигурация  
- ✅ Добавлена красивая веб-админка на FastAPI + Alpine.js
- ✅ Централизованное хранение доменов в domains.json  
- ✅ Автоматическая генерация конфигов SmartDNS и sniproxy
- ✅ Переход на статические upstream'ы для устойчивости
- ✅ Graceful reload без простоев
- ✅ Real-time мониторинг статуса сервисов через WebSocket
- ✅ REST API для управления доменами
- ✅ Устойчивость к проблемным доменам (IPv6, несуществующие домены)

### v1.0 - Базовая система
- ✅ SmartDNS + sniproxy + Traefik  
- ✅ Поддержка DoH/DoT
- ✅ SNI-based HTTPS проксирование
- ✅ Let's Encrypt сертификаты

## Заметки для разработчика
- ты уже на VPS тебе не нужно никуда подключаться
- Используй `docker compose` вместо `docker-compose` (новая версия)
- Админка - основной способ управления, консольные команды - для отладки
- При проблемах с sniproxy смотри раздел Troubleshooting