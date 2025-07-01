#!/bin/bash

# ============================================================================
# Baltic DNS - Скрипт перенастройки
# ============================================================================
# 
# Этот скрипт позволяет изменить настройки уже развернутой системы
# без полной переустановки
#
# Использование:
#   ./configure.sh                 # Интерактивное изменение настроек
#   ./configure.sh --change-domain # Только смена домена
#   ./configure.sh --change-ip     # Только смена IP
#   ./configure.sh --change-password # Только смена пароля
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
BACKUP_DIR="$SCRIPT_DIR/backup/$(date +%Y%m%d_%H%M%S)"

# Функции вывода
print_header() {
    echo -e "${BOLD}${BLUE}"
    echo "============================================================================"
    echo "🔧 Baltic DNS - Перенастройка системы"
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

# Проверка что система уже развернута
check_system_exists() {
    if [[ ! -f "$ENV_FILE" ]]; then
        print_error "Система не развернута. Файл .env не найден."
        echo "Сначала запустите: ./deploy.sh"
        exit 1
    fi
    
    if ! docker compose ps &> /dev/null; then
        print_error "Docker Compose не найден или система не запущена"
        exit 1
    fi
}

# Загрузка текущих настроек
load_current_config() {
    print_step "Загрузка текущей конфигурации"
    
    source "$ENV_FILE"
    
    print_info "Текущие настройки:"
    echo "  HOST_DOMAIN: $HOST_DOMAIN"
    echo "  SERVER_IP: $SERVER_IP"
    echo "  ACME_EMAIL: $ACME_EMAIL"
    echo "  TEST_SUBDOMAIN: $TEST_SUBDOMAIN"
}

# Создание бэкапа
create_backup() {
    print_step "Создание бэкапа конфигурации"
    
    mkdir -p "$BACKUP_DIR"
    
    # Бэкапим важные файлы
    cp "$ENV_FILE" "$BACKUP_DIR/"
    cp -r "traefik" "$BACKUP_DIR/" 2>/dev/null || true
    cp "domains.json" "$BACKUP_DIR/" 2>/dev/null || true
    cp "docker-compose.yml" "$BACKUP_DIR/" 2>/dev/null || true
    
    print_success "Бэкап создан в: $BACKUP_DIR"
}

# Остановка сервисов
stop_services() {
    print_step "Остановка сервисов"
    
    cd "$SCRIPT_DIR"
    
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi
    
    $COMPOSE_CMD down
    print_success "Сервисы остановлены"
}

# Интерактивное изменение настроек
interactive_reconfigure() {
    print_step "Интерактивное изменение настроек"
    
    echo -e "${YELLOW}Текущие настройки (нажмите Enter чтобы оставить без изменений):${NC}"
    echo
    
    # HOST_DOMAIN
    echo -e "${BOLD}1. Основной домен${NC}"
    echo "   Текущий: $HOST_DOMAIN"
    echo -n "   Новый домен: "
    read -r NEW_HOST_DOMAIN
    NEW_HOST_DOMAIN=${NEW_HOST_DOMAIN:-$HOST_DOMAIN}
    
    # SERVER_IP
    echo
    echo -e "${BOLD}2. IP адрес сервера${NC}"
    echo "   Текущий: $SERVER_IP"
    echo -n "   Новый IP: "
    read -r NEW_SERVER_IP
    NEW_SERVER_IP=${NEW_SERVER_IP:-$SERVER_IP}
    
    # ACME_EMAIL
    echo
    echo -e "${BOLD}3. Email для Let's Encrypt${NC}"
    echo "   Текущий: $ACME_EMAIL"
    echo -n "   Новый email: "
    read -r NEW_ACME_EMAIL
    NEW_ACME_EMAIL=${NEW_ACME_EMAIL:-$ACME_EMAIL}
    
    # ADMIN_PASSWORD
    echo
    echo -e "${BOLD}4. Пароль для админки${NC}"
    echo "   Текущий: [скрыт]"
    echo -n "   Новый пароль (пусто = не менять): "
    read -r NEW_ADMIN_PASSWORD
    NEW_ADMIN_PASSWORD=${NEW_ADMIN_PASSWORD:-$ADMIN_PASSWORD}
    
    # TEST_SUBDOMAIN
    echo
    echo -e "${BOLD}5. Поддомен для тестирования${NC}"
    echo "   Текущий: $TEST_SUBDOMAIN"
    echo -n "   Новый поддомен: "
    read -r NEW_TEST_SUBDOMAIN
    NEW_TEST_SUBDOMAIN=${NEW_TEST_SUBDOMAIN:-$TEST_SUBDOMAIN}
    
    echo
    print_info "Новая конфигурация:"
    echo "  HOST_DOMAIN: $NEW_HOST_DOMAIN"
    echo "  SERVER_IP: $NEW_SERVER_IP"
    echo "  ACME_EMAIL: $NEW_ACME_EMAIL"
    echo "  ADMIN_PASSWORD: $NEW_ADMIN_PASSWORD"
    echo "  TEST_SUBDOMAIN: $NEW_TEST_SUBDOMAIN"
    echo
    
    echo -n "Применить изменения? [Y/n]: "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo "Отменено пользователем"
        exit 0
    fi
    
    # Обновляем переменные
    HOST_DOMAIN="$NEW_HOST_DOMAIN"
    SERVER_IP="$NEW_SERVER_IP"
    ACME_EMAIL="$NEW_ACME_EMAIL"
    ADMIN_PASSWORD="$NEW_ADMIN_PASSWORD"
    TEST_SUBDOMAIN="$NEW_TEST_SUBDOMAIN"
}

# Проверка DNS для нового домена
check_new_dns() {
    if [[ "$HOST_DOMAIN" != "$NEW_HOST_DOMAIN" ]] || [[ "$SERVER_IP" != "$NEW_SERVER_IP" ]]; then
        print_step "Проверка DNS для новых настроек"
        
        local resolved_ip=""
        if resolved_ip=$(nslookup "$HOST_DOMAIN" 2>/dev/null | grep "Address:" | tail -n1 | awk '{print $2}'); then
            if [[ "$resolved_ip" == "$SERVER_IP" ]]; then
                print_success "DNS корректно настроен: $HOST_DOMAIN → $resolved_ip"
            else
                print_warning "DNS настроен неправильно: $HOST_DOMAIN → $resolved_ip (ожидался $SERVER_IP)"
                echo -n "Продолжить без корректного DNS? [y/N]: "
                read -r confirm
                if [[ ! "$confirm" =~ ^[Yy] ]]; then
                    exit 1
                fi
            fi
        else
            print_warning "Домен $HOST_DOMAIN не резолвится"
            echo -n "Продолжить без резолвинга? [y/N]: "
            read -r confirm
            if [[ ! "$confirm" =~ ^[Yy] ]]; then
                exit 1
            fi
        fi
    fi
}

# Обновление .env файла
update_env_file() {
    print_step "Обновление .env файла"
    
    cat > "$ENV_FILE" << EOF
# Baltic DNS Configuration
# Обновлено $(date)

# Основные настройки
HOST_DOMAIN=$HOST_DOMAIN
SERVER_IP=$SERVER_IP
TEST_SUBDOMAIN=$TEST_SUBDOMAIN

# Let's Encrypt
ACME_EMAIL=$ACME_EMAIL

# Безопасность
ADMIN_PASSWORD=$ADMIN_PASSWORD

# Дополнительные настройки
DEBUG=${DEBUG:-false}
LOG_LEVEL=${LOG_LEVEL:-info}
EOF
    
    print_success "Файл .env обновлен"
}

# Обновление .htpasswd
update_htpasswd() {
    print_step "Обновление файла паролей"
    
    local htpasswd_file="$SCRIPT_DIR/traefik/auth/.htpasswd"
    
    # Генерируем новый хеш пароля
    local password_hash=$(openssl passwd -apr1 "$ADMIN_PASSWORD")
    echo "admin:$password_hash" > "$htpasswd_file"
    
    print_success "Файл .htpasswd обновлен"
}

# Обновление domains.json
update_domains_json() {
    print_step "Обновление domains.json"
    
    local domains_file="$SCRIPT_DIR/domains.json"
    local old_test_domain="${OLD_TEST_SUBDOMAIN:-test}.${OLD_HOST_DOMAIN:-$HOST_DOMAIN}"
    local new_test_domain="${TEST_SUBDOMAIN}.${HOST_DOMAIN}"
    
    if [[ -f "$domains_file" ]]; then
        # Обновляем server_ip
        jq --arg server_ip "$SERVER_IP" '.server_ip = $server_ip' "$domains_file" > "$domains_file.tmp"
        
        # Если изменился тестовый домен, обновляем его в списке
        if [[ "$old_test_domain" != "$new_test_domain" ]]; then
            jq --arg old_domain "$old_test_domain" --arg new_domain "$new_test_domain" '
                .domains |= map(if .name == $old_domain then .name = $new_domain else . end)
            ' "$domains_file.tmp" > "$domains_file"
            rm "$domains_file.tmp"
            print_info "Тестовый домен изменен: $old_test_domain → $new_test_domain"
        else
            mv "$domains_file.tmp" "$domains_file"
        fi
    else
        # Создаем новый файл
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
    fi
    
    print_success "Файл domains.json обновлен"
}

# Перегенерация конфигов
regenerate_configs() {
    print_step "Перегенерация конфигурационных файлов"
    
    # Удаляем старые сертификаты если сменился домен
    if [[ "$HOST_DOMAIN" != "${OLD_HOST_DOMAIN:-$HOST_DOMAIN}" ]]; then
        print_info "Домен изменился, удаляем старые сертификаты"
        docker volume rm baltic-dns_letsencrypt 2>/dev/null || true
    fi
    
    # Генерируем dynamic.yml
    if [[ -x "$SCRIPT_DIR/scripts/generate-dynamic-config.sh" ]]; then
        cd "$SCRIPT_DIR"
        ./scripts/generate-dynamic-config.sh
    else
        print_warning "Скрипт generate-dynamic-config.sh не найден"
    fi
    
    print_success "Конфигурации перегенерированы"
}

# Запуск системы
restart_services() {
    print_step "Запуск системы с новыми настройками"
    
    cd "$SCRIPT_DIR"
    
    $COMPOSE_CMD up -d
    
    print_info "Ожидание готовности сервисов..."
    sleep 10
    
    print_success "Система перезапущена"
}

# Проверка работы
verify_reconfiguration() {
    print_step "Проверка работы системы"
    
    # Проверяем что контейнеры запущены
    local running_containers=$($COMPOSE_CMD ps --services --filter "status=running" | wc -l)
    local total_containers=$($COMPOSE_CMD ps --services | wc -l)
    
    if [[ $running_containers -eq $total_containers ]]; then
        print_success "Все сервисы запущены ($running_containers/$total_containers)"
    else
        print_warning "Не все сервисы запущены ($running_containers/$total_containers)"
    fi
    
    # Проверяем админку
    sleep 5
    if curl -s -I "https://$HOST_DOMAIN" | grep -q "HTTP"; then
        print_success "Админка доступна: https://$HOST_DOMAIN"
    else
        print_info "Админка пока недоступна (возможно получаются сертификаты)"
    fi
}

# Основная функция
main() {
    print_header
    
    # Сохраняем старые значения
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        OLD_HOST_DOMAIN="$HOST_DOMAIN"
        OLD_SERVER_IP="$SERVER_IP"
        OLD_TEST_SUBDOMAIN="$TEST_SUBDOMAIN"
    fi
    
    # Парсинг аргументов
    case "${1:-}" in
        --help|-h)
            echo "Использование: $0 [ОПЦИИ]"
            echo
            echo "Опции:"
            echo "  --change-domain    Только смена домена"
            echo "  --change-ip        Только смена IP адреса"
            echo "  --change-password  Только смена пароля"
            echo "  --help, -h         Показать эту справку"
            echo
            exit 0
            ;;
        --change-domain)
            check_system_exists
            load_current_config
            echo -n "Новый домен: "
            read -r HOST_DOMAIN
            ;;
        --change-ip)
            check_system_exists
            load_current_config
            echo -n "Новый IP адрес: "
            read -r SERVER_IP
            ;;
        --change-password)
            check_system_exists
            load_current_config
            echo -n "Новый пароль: "
            read -r ADMIN_PASSWORD
            ;;
        *)
            check_system_exists
            load_current_config
            interactive_reconfigure
            ;;
    esac
    
    create_backup
    stop_services
    check_new_dns
    update_env_file
    update_htpasswd
    update_domains_json
    regenerate_configs
    restart_services
    verify_reconfiguration
    
    echo
    echo -e "${BOLD}${GREEN}🎉 Перенастройка завершена!${NC}"
    echo
    echo -e "${BOLD}Обновленная информация:${NC}"
    echo "  📱 Админка: https://$HOST_DOMAIN"
    echo "  👤 Логин: admin"
    echo "  🔐 Пароль: $ADMIN_PASSWORD"
    echo "  🌐 DNS сервер: $SERVER_IP"
    echo
    echo -e "${YELLOW}💡 Бэкап сохранен в: $BACKUP_DIR${NC}"
}

# Запуск
main "$@"