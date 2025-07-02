#!/bin/bash

# ============================================================================
# Ninja DNS - Скрипт диагностики системы
# ============================================================================
# 
# Этот скрипт проводит комплексную диагностику работоспособности
# системы Ninja DNS и предоставляет детальный отчет
#
# Использование:
#   ./diagnose.sh                    # Полная диагностика
#   ./diagnose.sh --quick           # Быстрая проверка
#   ./diagnose.sh --dns-only        # Только DNS тесты
#   ./diagnose.sh --network-only    # Только сетевые тесты
#   ./diagnose.sh --fix             # Диагностика + исправление проблем
#
# ============================================================================

set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Переменные
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
REPORT_FILE="$SCRIPT_DIR/diagnostic_report_$(date +%Y%m%d_%H%M%S).txt"
TEMP_DIR="/tmp/baltic_dns_diag_$$"

# Счетчики для статистики
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Режимы работы
QUICK_MODE=false
DNS_ONLY=false
NETWORK_ONLY=false
FIX_MODE=false

# Функции вывода
print_header() {
    echo -e "${BOLD}${BLUE}"
    echo "============================================================================"
    echo "🔍 Ninja DNS - Диагностика системы"
    echo "============================================================================"
    echo -e "${NC}"
    echo "Время начала: $(date)"
    echo "Отчет будет сохранен в: $REPORT_FILE"
    echo
}

print_section() {
    echo -e "${BOLD}${CYAN}==> $1${NC}"
    echo "==> $1" >> "$REPORT_FILE"
}

print_test() {
    echo -n -e "${YELLOW}  📋 $1... ${NC}"
    echo -n "  📋 $1... " >> "$REPORT_FILE"
    ((TOTAL_TESTS++))
}

print_pass() {
    echo -e "${GREEN}✅ PASS${NC}"
    echo "✅ PASS" >> "$REPORT_FILE"
    ((PASSED_TESTS++))
}

print_fail() {
    echo -e "${RED}❌ FAIL${NC}"
    echo "❌ FAIL" >> "$REPORT_FILE"
    if [[ -n "$1" ]]; then
        echo -e "${RED}     └─ $1${NC}"
        echo "     └─ $1" >> "$REPORT_FILE"
    fi
    ((FAILED_TESTS++))
}

print_warning() {
    echo -e "${YELLOW}⚠️  WARN${NC}"
    echo "⚠️  WARN" >> "$REPORT_FILE"
    if [[ -n "$1" ]]; then
        echo -e "${YELLOW}     └─ $1${NC}"
        echo "     └─ $1" >> "$REPORT_FILE"
    fi
    ((WARNING_TESTS++))
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
    echo "ℹ️  $1" >> "$REPORT_FILE"
}

print_fix() {
    echo -e "${MAGENTA}🔧 $1${NC}"
    echo "🔧 $1" >> "$REPORT_FILE"
}

# Создание временной директории
create_temp_dir() {
    mkdir -p "$TEMP_DIR"
    trap "rm -rf $TEMP_DIR" EXIT
}

# Инициализация отчета
init_report() {
    cat > "$REPORT_FILE" << EOF
Ninja DNS - Диагностический отчет
=================================

Дата: $(date)
Сервер: $(hostname)
Пользователь: $(whoami)
Рабочая директория: $SCRIPT_DIR

EOF
}

# Загрузка конфигурации
load_config() {
    print_section "🔧 Загрузка конфигурации"
    
    print_test "Проверка существования .env файла"
    if [[ -f "$ENV_FILE" ]]; then
        print_pass
        source "$ENV_FILE"
    else
        print_fail "Файл .env не найден"
        return 1
    fi
    
    print_test "Проверка обязательных переменных"
    local missing_vars=()
    [[ -z "$HOST_DOMAIN" ]] && missing_vars+=("HOST_DOMAIN")
    [[ -z "$SERVER_IP" ]] && missing_vars+=("SERVER_IP")
    [[ -z "$ACME_EMAIL" ]] && missing_vars+=("ACME_EMAIL")
    
    if [[ ${#missing_vars[@]} -eq 0 ]]; then
        print_pass
        print_info "HOST_DOMAIN: $HOST_DOMAIN"
        print_info "SERVER_IP: $SERVER_IP"
        print_info "TEST_DOMAIN: ${TEST_SUBDOMAIN:-test}.$HOST_DOMAIN"
    else
        print_fail "Отсутствуют переменные: ${missing_vars[*]}"
        return 1
    fi
}

# Проверка системных требований
check_system_requirements() {
    print_section "🖥️  Системные требования"
    
    # Проверка Docker
    print_test "Docker установлен и запущен"
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        print_pass
        local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        print_info "Версия Docker: $docker_version"
    else
        print_fail "Docker не установлен или не запущен"
    fi
    
    # Проверка Docker Compose
    print_test "Docker Compose доступен"
    if docker compose version &> /dev/null || command -v docker-compose &> /dev/null; then
        print_pass
        if docker compose version &> /dev/null; then
            local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
            print_info "Docker Compose: $compose_version"
        else
            print_info "Docker Compose: legacy version"
        fi
    else
        print_fail "Docker Compose не найден"
    fi
    
    # Проверка доступной памяти
    print_test "Достаточно оперативной памяти"
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $total_mem -ge 512 ]]; then
        print_pass
        print_info "Доступно памяти: ${total_mem}MB"
    else
        print_warning "Мало памяти: ${total_mem}MB (рекомендуется 512MB+)"
    fi
    
    # Проверка дискового пространства
    print_test "Достаточно места на диске"
    local available_space=$(df -BM "$SCRIPT_DIR" | awk 'NR==2 {print $4}' | sed 's/M//')
    if [[ $available_space -ge 1024 ]]; then
        print_pass
        print_info "Свободно места: ${available_space}MB"
    else
        print_warning "Мало места: ${available_space}MB (рекомендуется 1GB+)"
    fi
    
    # Проверка утилит
    print_test "Необходимые утилиты установлены"
    local missing_utils=()
    for util in curl nslookup openssl; do
        if ! command -v "$util" &> /dev/null; then
            missing_utils+=("$util")
        fi
    done
    
    if [[ ${#missing_utils[@]} -eq 0 ]]; then
        print_pass
    else
        print_warning "Отсутствуют утилиты: ${missing_utils[*]}"
    fi
}

# Проверка портов
check_ports() {
    print_section "🔌 Проверка портов"
    
    local required_ports=(53 80 443 853)
    local busy_ports=()
    
    for port in "${required_ports[@]}"; do
        print_test "Порт $port доступен"
        if ss -tuln | grep -q ":$port "; then
            # Проверяем, занят ли порт нашими контейнерами
            local process=$(ss -tuln | grep ":$port " | head -1)
            if docker compose ps --services 2>/dev/null | xargs -I {} docker compose ps {} | grep -q "Up"; then
                # Если наши контейнеры запущены, порт может быть занят ими
                print_pass
                print_info "Порт занят (возможно нашими сервисами)"
            else
                print_warning "Порт занят другим процессом"
                busy_ports+=("$port")
            fi
        else
            print_pass
        fi
    done
    
    if [[ ${#busy_ports[@]} -gt 0 ]] && [[ "$FIX_MODE" == true ]]; then
        print_fix "Попытка освобождения портов: ${busy_ports[*]}"
        # Здесь можно добавить логику для остановки конфликтующих сервисов
    fi
}

# Проверка DNS настроек
check_dns_settings() {
    print_section "🌐 DNS настройки"
    
    # Проверка резолвинга основного домена
    print_test "Резолвинг основного домена $HOST_DOMAIN"
    local resolved_ip=""
    if resolved_ip=$(nslookup "$HOST_DOMAIN" 2>/dev/null | grep "Address:" | tail -n1 | awk '{print $2}'); then
        if [[ "$resolved_ip" == "$SERVER_IP" ]]; then
            print_pass
            print_info "Резолвится корректно: $HOST_DOMAIN → $resolved_ip"
        else
            print_fail "Неверный IP: $resolved_ip (ожидался $SERVER_IP)"
        fi
    else
        print_fail "Домен не резолвится"
    fi
    
    # Проверка тестового домена
    local test_domain="${TEST_SUBDOMAIN:-test}.$HOST_DOMAIN"
    print_test "Резолвинг тестового домена $test_domain"
    if resolved_ip=$(nslookup "$test_domain" 2>/dev/null | grep "Address:" | tail -n1 | awk '{print $2}'); then
        if [[ "$resolved_ip" == "$SERVER_IP" ]]; then
            print_pass
        else
            print_warning "Неверный IP для тестового домена: $resolved_ip"
        fi
    else
        print_warning "Тестовый домен не резолвится"
    fi
    
    # Проверка обратного DNS
    if [[ "$QUICK_MODE" == false ]]; then
        print_test "Обратный DNS для $SERVER_IP"
        if nslookup "$SERVER_IP" &> /dev/null; then
            print_pass
        else
            print_warning "Обратный DNS не настроен"
        fi
    fi
}

# Проверка Docker контейнеров
check_docker_containers() {
    print_section "🐳 Docker контейнеры"
    
    # Определяем команду compose
    local compose_cmd="docker compose"
    if ! docker compose version &> /dev/null; then
        compose_cmd="docker-compose"
    fi
    
    print_test "Docker Compose проект существует"
    if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        print_pass
    else
        print_fail "Файл docker-compose.yml не найден"
        return 1
    fi
    
    # Проверка статуса сервисов
    local services=("traefik" "smartdns" "sniproxy" "doh-proxy" "admin")
    
    for service in "${services[@]}"; do
        print_test "Контейнер $service"
        local status=$($compose_cmd ps "$service" 2>/dev/null | grep "$service" | awk '{print $NF}' || echo "not found")
        
        case "$status" in
            "Up"|"running")
                print_pass
                ;;
            "Exit"*|"Exited"*)
                print_fail "Контейнер завершился с ошибкой"
                if [[ "$FIX_MODE" == true ]]; then
                    print_fix "Перезапуск контейнера $service"
                    $compose_cmd restart "$service" &> /dev/null || true
                fi
                ;;
            *)
                print_fail "Контейнер не запущен или не найден"
                ;;
        esac
    done
    
    # Проверка использования ресурсов
    if [[ "$QUICK_MODE" == false ]]; then
        print_test "Использование ресурсов контейнерами"
        local total_memory=$(docker stats --no-stream --format "table {{.MemUsage}}" 2>/dev/null | tail -n +2 | grep -o "[0-9.]*MiB" | sed 's/MiB//' | awk '{sum += $1} END {print sum}')
        
        if [[ -n "$total_memory" ]] && (( $(echo "$total_memory < 200" | bc -l 2>/dev/null || echo 0) )); then
            print_pass
            print_info "Общее потребление памяти: ${total_memory}MB"
        else
            print_warning "Высокое потребление памяти: ${total_memory}MB"
        fi
    fi
}

# Проверка сетевых сервисов
check_network_services() {
    print_section "🌍 Сетевые сервисы"
    
    # Проверка HTTP доступности
    print_test "HTTP доступность (порт 80)"
    if curl -s -I --connect-timeout 5 "http://$HOST_DOMAIN" | grep -q "HTTP"; then
        print_pass
    else
        print_fail "HTTP недоступен"
    fi
    
    # Проверка HTTPS доступности
    print_test "HTTPS доступность (порт 443)"
    if curl -s -I --connect-timeout 5 "https://$HOST_DOMAIN" | grep -q "HTTP"; then
        print_pass
    else
        print_fail "HTTPS недоступен"
    fi
    
    # Проверка SSL сертификата
    print_test "Валидность SSL сертификата"
    if openssl s_client -connect "$HOST_DOMAIN:443" -servername "$HOST_DOMAIN" < /dev/null 2>/dev/null | openssl x509 -noout -dates > "$TEMP_DIR/cert_info" 2>/dev/null; then
        local not_after=$(grep "notAfter" "$TEMP_DIR/cert_info" | cut -d= -f2)
        local expiry_date=$(date -d "$not_after" +%s 2>/dev/null || echo "0")
        local current_date=$(date +%s)
        local days_left=$(( (expiry_date - current_date) / 86400 ))
        
        if [[ $days_left -gt 7 ]]; then
            print_pass
            print_info "Сертификат действителен еще $days_left дней"
        else
            print_warning "Сертификат истекает через $days_left дней"
        fi
    else
        print_fail "Не удалось проверить сертификат"
    fi
    
    # Проверка DoT (DNS over TLS)
    if command -v kdig &> /dev/null && [[ "$QUICK_MODE" == false ]]; then
        print_test "DNS over TLS (порт 853)"
        if timeout 10 kdig @"$SERVER_IP" +tls google.com A &> /dev/null; then
            print_pass
        else
            print_warning "DoT не отвечает или kdig не установлен"
        fi
    fi
}

# Проверка DNS функциональности
check_dns_functionality() {
    if [[ "$NETWORK_ONLY" == true ]]; then
        return 0
    fi
    
    print_section "🔍 DNS функциональность"
    
    # Проверка обычного DNS
    print_test "Обычный DNS запрос"
    if nslookup google.com "$SERVER_IP" &> /dev/null; then
        print_pass
    else
        print_fail "DNS сервер не отвечает"
    fi
    
    # Проверка DoH
    print_test "DNS over HTTPS"
    if curl -s -H "Accept: application/dns-json" "https://$HOST_DOMAIN/dns-query?name=google.com&type=A" | grep -q "Status.*0"; then
        print_pass
    else
        print_fail "DoH не работает"
    fi
    
    # Проверка перенаправления заблокированных доменов
    if [[ -f "$SCRIPT_DIR/domains.json" ]]; then
        print_test "Перенаправление заблокированных доменов"
        local test_domain=$(jq -r '.domains[0].name' "$SCRIPT_DIR/domains.json" 2>/dev/null || echo "")
        
        if [[ -n "$test_domain" ]]; then
            local resolved_ip=$(nslookup "$test_domain" "$SERVER_IP" 2>/dev/null | grep "Address:" | tail -n1 | awk '{print $2}')
            if [[ "$resolved_ip" == "$SERVER_IP" ]]; then
                print_pass
                print_info "Домен $test_domain перенаправляется на $resolved_ip"
            else
                print_warning "Домен $test_domain не перенаправляется"
            fi
        else
            print_warning "Нет доменов для тестирования"
        fi
    fi
}

# Проверка веб-админки
check_web_admin() {
    if [[ "$DNS_ONLY" == true ]]; then
        return 0
    fi
    
    print_section "🖥️  Веб-админка"
    
    # Проверка доступности админки
    print_test "Доступность веб-админки"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://$HOST_DOMAIN" || echo "000")
    
    case "$http_code" in
        200)
            print_pass
            ;;
        401)
            print_pass
            print_info "Требуется авторизация (это нормально)"
            ;;
        000)
            print_fail "Не удается подключиться"
            ;;
        *)
            print_warning "HTTP код: $http_code"
            ;;
    esac
    
    # Проверка API админки
    if [[ -n "$ADMIN_PASSWORD" ]]; then
        print_test "API админки"
        if curl -s -u "admin:$ADMIN_PASSWORD" "https://$HOST_DOMAIN/api/status" | grep -q "smartdns\|traefik"; then
            print_pass
        else
            print_warning "API не отвечает или неверный пароль"
        fi
    fi
    
    # Проверка WebSocket
    if [[ "$QUICK_MODE" == false ]]; then
        print_test "WebSocket подключение"
        # Простая проверка доступности WebSocket endpoint
        local ws_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 -H "Upgrade: websocket" "https://$HOST_DOMAIN/ws" || echo "000")
        if [[ "$ws_code" =~ ^(101|400|426)$ ]]; then
            print_pass
        else
            print_warning "WebSocket может быть недоступен"
        fi
    fi
}

# Проверка логов
check_logs() {
    if [[ "$QUICK_MODE" == true ]]; then
        return 0
    fi
    
    print_section "📋 Анализ логов"
    
    local compose_cmd="docker compose"
    if ! docker compose version &> /dev/null; then
        compose_cmd="docker-compose"
    fi
    
    # Проверка логов на ошибки
    local services=("traefik" "smartdns" "admin")
    
    for service in "${services[@]}"; do
        print_test "Логи $service на наличие ошибок"
        local error_count=$($compose_cmd logs --tail=100 "$service" 2>/dev/null | grep -i "error\|fail\|fatal" | wc -l)
        
        if [[ $error_count -eq 0 ]]; then
            print_pass
        elif [[ $error_count -lt 5 ]]; then
            print_warning "$error_count ошибок найдено"
        else
            print_fail "$error_count ошибок найдено"
        fi
    done
    
    # Проверка размера логов
    print_test "Размер лог-файлов Docker"
    local total_log_size=$(docker system df --format "table {{.Type}}\t{{.Size}}" | grep "Local Volumes" | awk '{print $3}' | sed 's/[^0-9.]//g' || echo "0")
    if [[ -n "$total_log_size" ]] && (( $(echo "$total_log_size < 1" | bc -l 2>/dev/null || echo 1) )); then
        print_pass
    else
        print_warning "Логи занимают много места: ${total_log_size}GB"
    fi
}

# Проверка производительности
check_performance() {
    if [[ "$QUICK_MODE" == true || "$DNS_ONLY" == true ]]; then
        return 0
    fi
    
    print_section "⚡ Производительность"
    
    # Тест скорости DNS
    print_test "Скорость DNS ответов"
    local start_time=$(date +%s%N)
    nslookup google.com "$SERVER_IP" &> /dev/null
    local end_time=$(date +%s%N)
    local dns_time=$(( (end_time - start_time) / 1000000 ))
    
    if [[ $dns_time -lt 100 ]]; then
        print_pass
        print_info "Время ответа DNS: ${dns_time}ms"
    elif [[ $dns_time -lt 500 ]]; then
        print_warning "Медленный DNS: ${dns_time}ms"
    else
        print_fail "Очень медленный DNS: ${dns_time}ms"
    fi
    
    # Тест скорости HTTPS
    print_test "Скорость HTTPS ответов"
    local https_time=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 5 "https://$HOST_DOMAIN" 2>/dev/null || echo "999")
    local https_ms=$(echo "$https_time * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "999")
    
    if [[ $https_ms -lt 1000 ]]; then
        print_pass
        print_info "Время ответа HTTPS: ${https_ms}ms"
    elif [[ $https_ms -lt 3000 ]]; then
        print_warning "Медленный HTTPS: ${https_ms}ms"
    else
        print_fail "Очень медленный HTTPS: ${https_ms}ms"
    fi
}

# Исправление проблем
fix_common_issues() {
    if [[ "$FIX_MODE" != true ]]; then
        return 0
    fi
    
    print_section "🔧 Исправление проблем"
    
    local compose_cmd="docker compose"
    if ! docker compose version &> /dev/null; then
        compose_cmd="docker-compose"
    fi
    
    # Перезапуск упавших контейнеров
    print_fix "Перезапуск упавших контейнеров"
    $compose_cmd ps --format json 2>/dev/null | jq -r '.[] | select(.State != "running") | .Service' 2>/dev/null | while read -r service; do
        if [[ -n "$service" ]]; then
            print_info "Перезапуск $service"
            $compose_cmd restart "$service" &> /dev/null || true
        fi
    done
    
    # Очистка старых логов
    print_fix "Очистка старых Docker логов"
    docker system prune -f &> /dev/null || true
    
    # Обновление DNS записей в domains.json
    if [[ -f "$SCRIPT_DIR/domains.json" ]]; then
        print_fix "Обновление server_ip в domains.json"
        jq --arg server_ip "$SERVER_IP" '.server_ip = $server_ip' "$SCRIPT_DIR/domains.json" > "$SCRIPT_DIR/domains.json.tmp" && mv "$SCRIPT_DIR/domains.json.tmp" "$SCRIPT_DIR/domains.json"
    fi
}

# Генерация итогового отчета
generate_summary() {
    print_section "📊 Итоговый отчет"
    
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    fi
    
    echo -e "${BOLD}Результаты диагностики:${NC}"
    echo -e "  📊 Всего тестов: ${TOTAL_TESTS}"
    echo -e "  ✅ Пройдено: ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "  ❌ Провалено: ${RED}${FAILED_TESTS}${NC}"
    echo -e "  ⚠️  Предупреждений: ${YELLOW}${WARNING_TESTS}${NC}"
    echo -e "  📈 Успешность: ${success_rate}%"
    echo
    
    # Добавляем в отчет
    cat >> "$REPORT_FILE" << EOF

============================================================================
ИТОГОВЫЙ ОТЧЕТ
============================================================================

Всего тестов: $TOTAL_TESTS
Пройдено: $PASSED_TESTS
Провалено: $FAILED_TESTS
Предупреждений: $WARNING_TESTS
Успешность: ${success_rate}%

Время завершения: $(date)
EOF
    
    # Рекомендации
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo -e "${RED}❌ Обнаружены критические проблемы!${NC}"
        echo -e "   Рекомендации:"
        echo -e "   • Проверьте логи: ${CYAN}docker compose logs${NC}"
        echo -e "   • Запустите с исправлением: ${CYAN}./diagnose.sh --fix${NC}"
        echo -e "   • Обратитесь к документации: ${CYAN}DEPLOYMENT.md${NC}"
    elif [[ $WARNING_TESTS -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Система работает, но есть предупреждения${NC}"
        echo -e "   Рекомендуется устранить предупреждения для оптимальной работы"
    else
        echo -e "${GREEN}🎉 Система работает отлично!${NC}"
        echo -e "   Все тесты пройдены успешно"
    fi
    
    echo
    echo -e "📄 Подробный отчет сохранен в: ${CYAN}$REPORT_FILE${NC}"
}

# Основная функция
main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                QUICK_MODE=true
                shift
                ;;
            --dns-only)
                DNS_ONLY=true
                shift
                ;;
            --network-only)
                NETWORK_ONLY=true
                shift
                ;;
            --fix)
                FIX_MODE=true
                shift
                ;;
            --help|-h)
                echo "Использование: $0 [ОПЦИИ]"
                echo
                echo "Опции:"
                echo "  --quick          Быстрая диагностика (основные проверки)"
                echo "  --dns-only       Только DNS тесты"
                echo "  --network-only   Только сетевые тесты"
                echo "  --fix            Попытка исправления найденных проблем"
                echo "  --help, -h       Показать эту справку"
                echo
                echo "Примеры:"
                echo "  $0               Полная диагностика"
                echo "  $0 --quick       Быстрая проверка"
                echo "  $0 --fix         Диагностика с исправлением"
                echo
                exit 0
                ;;
            *)
                echo "Неизвестная опция: $1"
                echo "Используйте --help для справки"
                exit 1
                ;;
        esac
    done
    
    print_header
    create_temp_dir
    init_report
    
    # Проверяем что мы в правильной директории
    if [[ ! -f "docker-compose.yml" ]]; then
        echo -e "${RED}❌ Ошибка: Запустите скрипт из корневой директории Ninja DNS${NC}"
        exit 1
    fi
    
    # Выполняем диагностику
    load_config || exit 1
    check_system_requirements
    check_ports
    check_dns_settings
    check_docker_containers
    
    if [[ "$DNS_ONLY" != true ]]; then
        check_network_services
        check_web_admin
        check_logs
        check_performance
    fi
    
    if [[ "$NETWORK_ONLY" != true ]]; then
        check_dns_functionality
    fi
    
    fix_common_issues
    generate_summary
    
    # Возвращаем код выхода в зависимости от результатов
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    elif [[ $WARNING_TESTS -gt 0 ]]; then
        exit 2
    else
        exit 0
    fi
}

# Запуск
main "$@"