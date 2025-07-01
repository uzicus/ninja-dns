# Baltic DNS - Руководство по развертыванию

## 🚀 Быстрый старт

Система Baltic DNS теперь поддерживает автоматическое развертывание на любом сервере одной командой:

```bash
# Клонируем проект
git clone <your-repo-url> baltic-dns
cd baltic-dns

# Запускаем автоматическое развертывание
./deploy.sh
```

## 📋 Требования

### Системные требования
- **ОС**: Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- **RAM**: минимум 512MB (рекомендуется 1GB+)
- **Диск**: минимум 2GB свободного места
- **CPU**: 1 ядро (рекомендуется 2+)

### Сетевые требования
- **Открытые порты**: 53 (DNS), 80 (HTTP), 443 (HTTPS), 853 (DoT)
- **Домен**: настроенный A-записью на IP сервера
- **Интернет**: доступ для получения Let's Encrypt сертификатов

### Программное обеспечение
- Docker 20.10+
- Docker Compose 2.0+
- OpenSSL
- DNS утилиты (nslookup)

## 🛠 Подготовка к развертыванию

### 1. Настройка DNS
**КРИТИЧЕСКИ ВАЖНО**: Перед развертыванием настройте DNS записи:

```
# A-запись для основного домена
dns.example.com.    IN  A   YOUR_SERVER_IP

# A-запись для тестового поддомена  
test.dns.example.com.  IN  A   YOUR_SERVER_IP
```

Проверьте настройку:
```bash
nslookup dns.example.com
nslookup test.dns.example.com
```

### 2. Установка зависимостей

**Ubuntu/Debian:**
```bash
apt update
apt install -y docker.io docker-compose-plugin git curl openssl dnsutils
systemctl enable docker
systemctl start docker
```

**CentOS/RHEL:**
```bash
yum install -y docker docker-compose git curl openssl bind-utils
systemctl enable docker
systemctl start docker
```

### 3. Настройка файрвола

**UFW (Ubuntu):**
```bash
ufw allow 22/tcp    # SSH
ufw allow 53        # DNS
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS  
ufw allow 853/tcp   # DoT
ufw enable
```

**firewalld (CentOS):**
```bash
firewall-cmd --permanent --add-port=53/udp
firewall-cmd --permanent --add-port=53/tcp
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=853/tcp
firewall-cmd --reload
```

## 🚀 Процесс развертывания

### Автоматическое развертывание

1. **Скачайте проект:**
```bash
git clone <your-repo-url> baltic-dns
cd baltic-dns
```

2. **Запустите развертывание:**
```bash
./deploy.sh
```

3. **Следуйте интерактивным инструкциям:**
   - Введите основной домен (например: `dns.example.com`)
   - Подтвердите IP адрес сервера (определяется автоматически)
   - Введите email для Let's Encrypt
   - Установите пароль для админки
   - Настройте тестовый поддомен

4. **Скрипт автоматически:**
   - Проверит DNS настройки
   - Создаст конфигурационные файлы
   - Запустит все сервисы
   - Получит SSL сертификаты
   - Проверит работоспособность

### Ручное развертывание

Если автоматическое развертывание недоступно:

1. **Создайте .env файл:**
```bash
cp .env.example .env
nano .env  # Отредактируйте настройки
```

2. **Сгенерируйте конфигурации:**
```bash
./scripts/generate-dynamic-config.sh
```

3. **Создайте файл паролей:**
```bash
mkdir -p traefik/auth
htpasswd -c traefik/auth/.htpasswd admin
```

4. **Запустите систему:**
```bash
docker compose up -d
```

## ⚙️ Конфигурационные опции

### Переменные окружения (.env)

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `HOST_DOMAIN` | Основной домен системы | `dns.uzicus.ru` |
| `SERVER_IP` | IP адрес сервера | `185.237.95.211` |
| `TEST_SUBDOMAIN` | Поддомен для тестов | `test` |
| `ACME_EMAIL` | Email для Let's Encrypt | `admin@uzicus.ru` |
| `ADMIN_PASSWORD` | Пароль админки | `BalticDNS2024!` |
| `DEBUG` | Режим отладки | `false` |
| `LOG_LEVEL` | Уровень логирования | `info` |

### Режимы запуска deploy.sh

```bash
# Полное развертывание (интерактивно)
./deploy.sh

# Только генерация конфигов
./deploy.sh --config

# Только проверка DNS
./deploy.sh --dns-check-only

# Справка
./deploy.sh --help
```

## 🔧 Управление системой

### Основные команды

```bash
# Проверка статуса
docker compose ps

# Просмотр логов
docker compose logs -f

# Перезапуск всех сервисов
docker compose restart

# Перезапуск конкретного сервиса
docker compose restart smartdns

# Остановка системы
docker compose down

# Обновление конфигурации
./configure.sh
```

### Изменение настроек

Для изменения настроек уже развернутой системы:

```bash
# Интерактивное изменение всех настроек
./configure.sh

# Только смена домена
./configure.sh --change-domain

# Только смена IP
./configure.sh --change-ip

# Только смена пароля
./configure.sh --change-password
```

### Добавление доменов

Используйте веб-админку:
1. Откройте https://your-domain.com
2. Войдите (логин: `admin`, пароль: из .env)
3. Добавьте домены через интерфейс

## 🧪 Тестирование

### Проверка DNS
```bash
# Обычный DNS
nslookup netflix.com YOUR_SERVER_IP

# DoT (требует kdig)
kdig @YOUR_SERVER_IP +tls netflix.com

# DoH
curl -H "Accept: application/dns-json" \
  "https://your-domain.com/dns-query?name=netflix.com&type=A"
```

### Проверка HTTPS проксирования
```bash
# Тест через curl
curl -I https://netflix.com --resolve netflix.com:443:YOUR_SERVER_IP
```

### Проверка сертификатов
```bash
# Проверка SSL сертификата
openssl s_client -connect your-domain.com:443 -servername your-domain.com < /dev/null

# Проверка через браузер
# Откройте https://your-domain.com и проверьте сертификат
```

## 🔍 Диагностика проблем

### Частые проблемы и решения

#### 1. DNS не резолвится
```bash
# Проверьте настройки DNS
nslookup your-domain.com

# Проверьте что A-запись указывает на правильный IP
dig your-domain.com A
```

#### 2. Сертификаты не получаются
```bash
# Проверьте логи Traefik
docker logs traefik

# Убедитесь что домен доступен по HTTP
curl -I http://your-domain.com

# Проверьте что порт 80 открыт
telnet your-domain.com 80
```

#### 3. Админка недоступна
```bash
# Проверьте статус сервисов
docker compose ps

# Проверьте логи админки
docker logs admin

# Проверьте логи sniproxy
docker logs sniproxy
```

#### 4. Домены не добавляются
```bash
# Проверьте что админка может управлять Docker
docker logs admin | grep -i error

# Проверьте права доступа к Docker socket
ls -la /var/run/docker.sock
```

### Логи и мониторинг

```bash
# Все логи
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f smartdns
docker compose logs -f sniproxy
docker compose logs -f traefik
docker compose logs -f admin

# Потребление ресурсов
docker stats --no-stream

# Использование дискового пространства
docker system df
```

## 🔒 Безопасность

### Рекомендации по безопасности

1. **Регулярно обновляйте пароли:**
```bash
./configure.sh --change-password
```

2. **Мониторьте логи:**
```bash
docker compose logs admin | grep -i "error\|warning"
```

3. **Обновляйте систему:**
```bash
# Обновление образов Docker
docker compose pull
docker compose up -d
```

4. **Настройте fail2ban для SSH:**
```bash
apt install fail2ban
# Настройте согласно документации fail2ban
```

### Файрвол и доступ

- Закройте все неиспользуемые порты
- Ограничьте SSH доступ по IP
- Используйте ключи вместо паролей для SSH
- Регулярно проверяйте подключенные сервисы

## 🚚 Миграция

### Перенос на другой сервер

1. **На старом сервере:**
```bash
# Создайте бэкап
tar -czf baltic-dns-backup.tar.gz \
  .env domains.json traefik/auth/.htpasswd \
  letsencrypt/ 2>/dev/null || true
```

2. **На новом сервере:**
```bash
# Разверните систему
./deploy.sh

# Остановите сервисы
docker compose down

# Восстановите бэкап
tar -xzf baltic-dns-backup.tar.gz

# Обновите IP в конфигурации
./configure.sh --change-ip

# Запустите систему
docker compose up -d
```

### Обновление версии

```bash
# Сохраните конфигурацию
cp .env .env.backup
cp domains.json domains.json.backup

# Обновите код
git pull

# Перезапустите с сохранением данных
docker compose down
docker compose up -d
```

## 📞 Поддержка

### Полезные ресурсы

- [Docker документация](https://docs.docker.com/)
- [Traefik документация](https://doc.traefik.io/traefik/)
- [Let's Encrypt документация](https://letsencrypt.org/docs/)

### Сообщество

- Создавайте Issues в репозитории проекта
- Проверяйте существующие Issues перед созданием новых
- Прикладывайте логи при сообщении о проблемах

### Разработка

Проект открыт для вклада:
1. Fork репозитория
2. Создайте feature branch
3. Внесите изменения
4. Создайте Pull Request

---

## 📝 Заключение

Baltic DNS теперь может быть развернут на любом сервере за несколько минут. Главные преимущества:

- ✅ **Автоматизация**: Один скрипт для полного развертывания
- ✅ **Гибкость**: Легкая настройка под любой домен и IP
- ✅ **Безопасность**: Автоматические SSL сертификаты
- ✅ **Масштабируемость**: Простое добавление новых серверов
- ✅ **Надежность**: Проверка DNS и автоматическая диагностика

Наслаждайтесь свободным интернетом! 🌊