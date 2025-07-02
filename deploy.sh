#!/bin/bash

# ============================================================================
# Ninja DNS - Скрипт автоматического развертывания
# ============================================================================
# 
# Этот скрипт позволяет быстро развернуть Ninja DNS на новом сервере
# с автоматической проверкой DNS и настройкой сертификатов
#
# Использование:
#   ./deploy.sh                    # Интерактивный режим
#   ./deploy.sh --config           # Только генерация конфигов
#   ./deploy.sh --dns-check-only   # Только проверка DNS
#
# ============================================================================

set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Переменные
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

# Функции
print_header() {
    echo -e "${BOLD}${BLUE}"
    echo "============================================================================"
    echo "🌊 Ninja DNS - Автоматическое развертывание"
    echo "============================================================================"
    echo -e "${NC}"
}

print_step() {
    echo -e "${BOLD}${GREEN}==> $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ Ошибка: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Проверка зависимостей
check_dependencies() {
    print_step "Проверка зависимостей"
    
    local missing_deps=()
    
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_deps+=("docker-compose")
    fi
    
    if ! command -v nslookup &> /dev/null; then
        missing_deps+=("nslookup")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Отсутствуют зависимости: ${missing_deps[*]}"
        echo -e "${YELLOW}Установите их командой:${NC}"
        echo "  apt update && apt install -y docker.io docker-compose-plugin dnsutils openssl"
        exit 1
    fi
    
    print_success "Все зависимости установлены"
}

# Определение внешнего IP
detect_server_ip() {
    print_step "Определение IP адреса сервера"
    
    local ip=""
    
    # Пробуем разные методы определения IP
    if command -v curl &> /dev/null; then
        ip=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || true)
    fi
    
    if [[ -z "$ip" ]] && command -v wget &> /dev/null; then
        ip=$(wget -qO- -4 ifconfig.me 2>/dev/null || wget -qO- -4 icanhazip.com 2>/dev/null || true)
    fi
    
    if [[ -z "$ip" ]]; then
        # Fallback на hostname -I
        ip=$(hostname -I | awk '{print $1}')
    fi
    
    if [[ -n "$ip" ]]; then
        print_success "Обнаружен IP адрес: $ip"
        echo "$ip"
    else
        print_warning "Не удалось автоматически определить IP адрес"
        echo ""
    fi
}

# Проверка DNS резолвинга
check_dns_resolution() {
    local domain="$1"
    local expected_ip="$2"
    
    print_step "Проверка DNS резолвинга для $domain"
    
    local resolved_ip=""
    if resolved_ip=$(nslookup "$domain" 2>/dev/null | grep "Address:" | tail -n1 | awk '{print $2}'); then
        if [[ "$resolved_ip" == "$expected_ip" ]]; then
            print_success "DNS корректно настроен: $domain → $resolved_ip"
            return 0
        else
            print_error "DNS настроен неправильно: $domain → $resolved_ip (ожидался $expected_ip)"
            return 1
        fi
    else
        print_error "Домен $domain не резолвится"
        return 1
    fi
}

# Интерактивный ввод конфигурации
interactive_config() {
    print_step "Интерактивная настройка конфигурации"
    
    # Определяем IP автоматически
    local auto_ip=$(detect_server_ip)
    
    echo -e "${YELLOW}Введите параметры для развертывания:${NC}"
    echo
    
    # HOST_DOMAIN
    echo -e "${BOLD}1. Основной домен${NC}"
    echo "   Это домен для размещения админки и DNS сервисов"
    echo "   Примеры: dns.example.com, proxy.mydomain.org"
    echo -n "   Домен: "
    read -r HOST_DOMAIN
    
    if [[ -z "$HOST_DOMAIN" ]]; then
        print_error "Домен обязателен"
        exit 1
    fi
    
    # SERVER_IP
    echo
    echo -e "${BOLD}2. IP адрес сервера${NC}"
    if [[ -n "$auto_ip" ]]; then
        echo "   Автоматически определен: $auto_ip"
        echo -n "   IP адрес [$auto_ip]: "
        read -r SERVER_IP
        SERVER_IP=${SERVER_IP:-$auto_ip}
    else
        echo -n "   IP адрес: "
        read -r SERVER_IP
    fi
    
    if [[ -z "$SERVER_IP" ]]; then
        print_error "IP адрес обязателен"
        exit 1
    fi
    
    # ACME_EMAIL
    echo
    echo -e "${BOLD}3. Email для Let's Encrypt${NC}"
    echo "   Используется для уведомлений о сертификатах"
    echo -n "   Email: "
    read -r ACME_EMAIL
    
    if [[ -z "$ACME_EMAIL" ]]; then
        print_error "Email обязателен"
        exit 1
    fi
    
    # ADMIN_PASSWORD
    echo
    echo -e "${BOLD}4. Пароль для админки${NC}"
    echo "   Логин всегда: admin"
    echo -n "   Пароль [BalticDNS2024!]: "
    read -r ADMIN_PASSWORD
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-BalticDNS2024!}
    
    # TEST_SUBDOMAIN
    echo
    echo -e "${BOLD}5. Поддомен для тестирования${NC}"
    echo "   Будет создан как: test.$HOST_DOMAIN"
    echo -n "   Поддомен [test]: "
    read -r TEST_SUBDOMAIN
    TEST_SUBDOMAIN=${TEST_SUBDOMAIN:-test}
    
    echo
    print_info "Конфигурация:"
    echo "  HOST_DOMAIN: $HOST_DOMAIN"
    echo "  SERVER_IP: $SERVER_IP"
    echo "  ACME_EMAIL: $ACME_EMAIL"
    echo "  ADMIN_PASSWORD: $ADMIN_PASSWORD"
    echo "  TEST_SUBDOMAIN: $TEST_SUBDOMAIN"
    echo
    
    echo -n "Продолжить с этими настройками? [Y/n]: "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo "Отменено пользователем"
        exit 0
    fi
}

# Генерация .env файла
generate_env_file() {
    print_step "Генерация .env файла"
    
    cat > "$ENV_FILE" << EOF
# Ninja DNS Configuration
# Сгенерировано автоматически $(date)

# Основные настройки
HOST_DOMAIN=$HOST_DOMAIN
SERVER_IP=$SERVER_IP
TEST_SUBDOMAIN=$TEST_SUBDOMAIN

# Let's Encrypt
ACME_EMAIL=$ACME_EMAIL

# Безопасность
ADMIN_PASSWORD=$ADMIN_PASSWORD

# Дополнительные настройки
DEBUG=false
LOG_LEVEL=info
EOF
    
    print_success "Файл .env создан"
}

# Генерация .htpasswd
generate_htpasswd() {
    print_step "Генерация файла паролей"
    
    local htpasswd_file="$SCRIPT_DIR/traefik/auth/.htpasswd"
    mkdir -p "$(dirname "$htpasswd_file")"
    
    # Генерируем хеш пароля
    local password_hash=$(openssl passwd -apr1 "$ADMIN_PASSWORD")
    echo "admin:$password_hash" > "$htpasswd_file"
    
    print_success "Файл .htpasswd создан"
}

# Создание начального domains.json
create_initial_domains() {
    print_step "Создание начального domains.json"
    
    local domains_file="$SCRIPT_DIR/domains.json"
    local test_domain="${TEST_SUBDOMAIN}.${HOST_DOMAIN}"
    
    cat > "$domains_file" << EOF
{
  "domains": [
    {
      "name": "$test_domain",
      "category": "dns-test",
      "enabled": true
    }
  ],
  "server_ip": "$SERVER_IP"
}
EOF
    
    print_success "Файл domains.json создан с тестовым доменом: $test_domain"
}

# Генерация конфигов
generate_configs() {
    print_step "Генерация конфигурационных файлов"
    
    # Генерируем dynamic.yml
    if [[ -x "$SCRIPT_DIR/scripts/generate-dynamic-config.sh" ]]; then
        cd "$SCRIPT_DIR"
        ./scripts/generate-dynamic-config.sh
    else
        print_warning "Скрипт generate-dynamic-config.sh не найден или не исполняем"
    fi
    
    print_success "Конфигурации сгенерированы"
}

# Проверка портов
check_ports() {
    print_step "Проверка доступности портов"
    
    local required_ports=(53 80 443 853)
    local busy_ports=()
    
    for port in "${required_ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            busy_ports+=("$port")
        fi
    done
    
    if [[ ${#busy_ports[@]} -gt 0 ]]; then
        print_warning "Занятые порты: ${busy_ports[*]}"
        echo "Убедитесь что эти службы можно остановить или они совместимы с Ninja DNS"
        echo -n "Продолжить? [y/N]: "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            exit 1
        fi
    else
        print_success "Все необходимые порты свободны"
    fi
}

# Запуск системы
start_system() {
    print_step "Запуск Ninja DNS"
    
    cd "$SCRIPT_DIR"
    
    # Проверяем наличие docker compose
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi
    
    print_info "Запуск сервисов..."
    $COMPOSE_CMD up -d
    
    print_info "Ожидание готовности сервисов..."
    sleep 10
    
    print_success "Система запущена"
}

# Проверка сертификатов
check_certificates() {
    print_step "Проверка получения SSL сертификатов"
    
    print_info "Ожидание получения сертификатов (это может занять до 2 минут)..."
    
    local max_attempts=24  # 2 минуты
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s -I "https://$HOST_DOMAIN" | grep -q "HTTP"; then
            print_success "SSL сертификат получен и работает"
            return 0
        fi
        
        sleep 5
        ((attempt++))
        echo -n "."
    done
    
    echo
    print_warning "SSL сертификат еще не готов. Проверьте логи Traefik:"
    echo "  docker logs traefik"
}

# Проверка работы системы
verify_system() {
    print_step "Проверка работы системы"
    
    local test_domain="${TEST_SUBDOMAIN}.${HOST_DOMAIN}"
    
    # Проверяем DNS
    if check_dns_resolution "$test_domain" "$SERVER_IP"; then
        print_success "DNS работает корректно"
    else
        print_warning "Проблемы с DNS резолвингом"
    fi
    
    # Проверяем админку
    if curl -s -I "https://$HOST_DOMAIN" | grep -q "HTTP"; then
        print_success "Админка доступна: https://$HOST_DOMAIN"
    else
        print_warning "Админка пока недоступна"
    fi
    
    # Проверяем DoH
    if curl -s -I "https://$HOST_DOMAIN/dns-query" | grep -q "HTTP"; then
        print_success "DoH сервис доступен"
    else
        print_warning "DoH сервис пока недоступен"
    fi
}

# Вывод финальной информации
print_final_info() {
    echo
    echo -e "${BOLD}${GREEN}🎉 Развертывание завершено!${NC}"
    echo
    echo -e "${BOLD}Информация для доступа:${NC}"
    echo "  📱 Админка: https://$HOST_DOMAIN"
    echo "  👤 Логин: admin"
    echo "  🔐 Пароль: $ADMIN_PASSWORD"
    echo
    echo -e "${BOLD}DNS настройки для клиентов:${NC}"
    echo "  🌐 DNS сервер: $SERVER_IP"
    echo "  🔒 DoT: $HOST_DOMAIN:853"
    echo "  🔗 DoH: https://$HOST_DOMAIN/dns-query"
    echo
    echo -e "${BOLD}Полезные команды:${NC}"
    echo "  📊 Логи: docker logs <service_name>"
    echo "  🔄 Перезапуск: docker compose restart"
    echo "  ⏹️  Остановка: docker compose down"
    echo "  📝 Статус: docker compose ps"
    echo
    echo -e "${YELLOW}💡 Добавляйте домены через веб-админку для обхода блокировок${NC}"
}

# Основная функция
main() {
    print_header
    
    # Парсинг аргументов
    case "${1:-}" in
        --help|-h)
            echo "Использование: $0 [ОПЦИИ]"
            echo
            echo "Опции:"
            echo "  --config          Только генерация конфигов"
            echo "  --dns-check-only  Только проверка DNS"
            echo "  --help, -h        Показать эту справку"
            echo
            exit 0
            ;;
        --dns-check-only)
            if [[ ! -f "$ENV_FILE" ]]; then
                print_error "Файл .env не найден. Запустите полное развертывание сначала."
                exit 1
            fi
            source "$ENV_FILE"
            check_dns_resolution "$HOST_DOMAIN" "$SERVER_IP"
            check_dns_resolution "${TEST_SUBDOMAIN}.${HOST_DOMAIN}" "$SERVER_IP"
            exit 0
            ;;
        --config)
            interactive_config
            generate_env_file
            generate_htpasswd
            create_initial_domains
            generate_configs
            print_success "Конфигурация готова. Запустите: docker compose up -d"
            exit 0
            ;;
    esac
    
    # Полное развертывание
    check_dependencies
    interactive_config
    
    # Критическая проверка DNS
    print_step "Критическая проверка DNS"
    if ! check_dns_resolution "$HOST_DOMAIN" "$SERVER_IP"; then
        print_error "DNS не настроен! Настройте A-запись для $HOST_DOMAIN → $SERVER_IP"
        echo -e "${YELLOW}Без корректного DNS Let's Encrypt не сможет выдать сертификат${NC}"
        echo -n "Продолжить без проверки DNS? [y/N]: "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            exit 1
        fi
    fi
    
    generate_env_file
    generate_htpasswd
    create_initial_domains
    generate_configs
    check_ports
    start_system
    check_certificates
    verify_system
    print_final_info
}

# Запуск
main "$@"