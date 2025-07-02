#!/bin/bash

# ============================================================================
# Ninja DNS - Скрипт мониторинга в реальном времени
# ============================================================================
# 
# Этот скрипт обеспечивает мониторинг работоспособности системы
# в реальном времени с красивым интерфейсом
#
# Использование:
#   ./monitor.sh                # Полный мониторинг
#   ./monitor.sh --compact      # Компактный режим
#   ./monitor.sh --alerts-only  # Только алерты
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
REFRESH_INTERVAL=5
COMPACT_MODE=false
ALERTS_ONLY=false

# Загрузка конфигурации
load_config() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    else
        echo -e "${RED}❌ Файл .env не найден${NC}"
        exit 1
    fi
}

# Очистка экрана и установка курсора
clear_screen() {
    clear
    tput cup 0 0
}

# Заголовок
print_header() {
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}🌊 Ninja DNS - Мониторинг в реальном времени${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Домен: ${HOST_DOMAIN} | IP: ${SERVER_IP} | Обновление каждые ${REFRESH_INTERVAL}с${NC}"
    echo -e "${CYAN}Время: $(date) | Нажмите Ctrl+C для выхода${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo
}

# Статус индикатор
status_indicator() {
    local status="$1"
    case "$status" in
        "UP"|"running"|"PASS")
            echo -e "${GREEN}●${NC}"
            ;;
        "DOWN"|"exited"|"FAIL")
            echo -e "${RED}●${NC}"
            ;;
        "WARN"|"WARNING")
            echo -e "${YELLOW}●${NC}"
            ;;
        *)
            echo -e "${YELLOW}?${NC}"
            ;;
    esac
}

# Проверка Docker контейнеров
check_containers() {
    local compose_cmd="docker compose"
    if ! docker compose version &> /dev/null; then
        compose_cmd="docker-compose"
    fi
    
    echo -e "${BOLD}🐳 Docker Контейнеры:${NC}"
    
    local services=("traefik" "smartdns" "sniproxy" "doh-proxy" "admin")
    local all_up=true
    
    for service in "${services[@]}"; do
        local status=$($compose_cmd ps "$service" 2>/dev/null | grep "$service" | awk '{print $NF}' || echo "DOWN")
        local indicator=$(status_indicator "$status")
        
        if [[ "$COMPACT_MODE" == false ]]; then
            printf "  %-12s %s %s\n" "$service" "$indicator" "$status"
        fi
        
        if [[ "$status" != "Up" && "$status" != "running" ]]; then
            all_up=false
            if [[ "$ALERTS_ONLY" == true ]]; then
                echo -e "${RED}🚨 АЛЕРТ: Контейнер $service не работает ($status)${NC}"
            fi
        fi
    done
    
    if [[ "$COMPACT_MODE" == true ]]; then
        if [[ "$all_up" == true ]]; then
            echo -e "  Все контейнеры: ${GREEN}● UP${NC}"
        else
            echo -e "  Контейнеры: ${RED}● ПРОБЛЕМЫ${NC}"
        fi
    fi
    
    echo
}

# Проверка сетевых сервисов
check_network() {
    echo -e "${BOLD}🌍 Сетевые Сервисы:${NC}"
    
    # HTTP
    local http_status="DOWN"
    if curl -s -I --connect-timeout 3 "http://$HOST_DOMAIN" | grep -q "HTTP"; then
        http_status="UP"
    fi
    local http_indicator=$(status_indicator "$http_status")
    
    # HTTPS
    local https_status="DOWN"
    local https_time=""
    if https_time=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 3 "https://$HOST_DOMAIN" 2>/dev/null); then
        https_status="UP"
        https_time=$(echo "$https_time * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "999")
    fi
    local https_indicator=$(status_indicator "$https_status")
    
    # DNS
    local dns_status="DOWN"
    local dns_time=""
    local start_time=$(date +%s%N)
    if nslookup google.com "$SERVER_IP" &> /dev/null; then
        dns_status="UP"
        local end_time=$(date +%s%N)
        dns_time=$(( (end_time - start_time) / 1000000 ))
    fi
    local dns_indicator=$(status_indicator "$dns_status")
    
    if [[ "$COMPACT_MODE" == false ]]; then
        printf "  %-12s %s %s\n" "HTTP" "$http_indicator" "$http_status"
        printf "  %-12s %s %s" "HTTPS" "$https_indicator" "$https_status"
        [[ -n "$https_time" ]] && printf " (%sms)" "$https_time"
        echo
        printf "  %-12s %s %s" "DNS" "$dns_indicator" "$dns_status"
        [[ -n "$dns_time" ]] && printf " (%sms)" "$dns_time"
        echo
    else
        local network_ok=true
        [[ "$http_status" != "UP" ]] && network_ok=false
        [[ "$https_status" != "UP" ]] && network_ok=false
        [[ "$dns_status" != "UP" ]] && network_ok=false
        
        if [[ "$network_ok" == true ]]; then
            echo -e "  Сеть: ${GREEN}● ВСЕ ОК${NC} (DNS:${dns_time}ms, HTTPS:${https_time}ms)"
        else
            echo -e "  Сеть: ${RED}● ПРОБЛЕМЫ${NC}"
        fi
    fi
    
    # Алерты
    if [[ "$ALERTS_ONLY" == true ]]; then
        [[ "$http_status" != "UP" ]] && echo -e "${RED}🚨 АЛЕРТ: HTTP недоступен${NC}"
        [[ "$https_status" != "UP" ]] && echo -e "${RED}🚨 АЛЕРТ: HTTPS недоступен${NC}"
        [[ "$dns_status" != "UP" ]] && echo -e "${RED}🚨 АЛЕРТ: DNS не отвечает${NC}"
        [[ -n "$dns_time" && $dns_time -gt 500 ]] && echo -e "${YELLOW}⚠️  ПРЕДУПРЕЖДЕНИЕ: Медленный DNS (${dns_time}ms)${NC}"
        [[ -n "$https_time" && $https_time -gt 2000 ]] && echo -e "${YELLOW}⚠️  ПРЕДУПРЕЖДЕНИЕ: Медленный HTTPS (${https_time}ms)${NC}"
    fi
    
    echo
}

# Проверка SSL сертификата
check_ssl() {
    if [[ "$COMPACT_MODE" == true ]]; then
        return 0
    fi
    
    echo -e "${BOLD}🔒 SSL Сертификат:${NC}"
    
    local cert_status="UNKNOWN"
    local days_left="?"
    
    if openssl s_client -connect "$HOST_DOMAIN:443" -servername "$HOST_DOMAIN" < /dev/null 2>/dev/null | openssl x509 -noout -dates > /tmp/cert_info 2>/dev/null; then
        local not_after=$(grep "notAfter" /tmp/cert_info | cut -d= -f2)
        local expiry_date=$(date -d "$not_after" +%s 2>/dev/null || echo "0")
        local current_date=$(date +%s)
        days_left=$(( (expiry_date - current_date) / 86400 ))
        
        if [[ $days_left -gt 30 ]]; then
            cert_status="VALID"
        elif [[ $days_left -gt 7 ]]; then
            cert_status="WARN"
        else
            cert_status="CRITICAL"
        fi
    else
        cert_status="ERROR"
    fi
    
    local cert_indicator=$(status_indicator "$cert_status")
    printf "  %-12s %s %s" "Сертификат" "$cert_indicator" "$cert_status"
    [[ "$days_left" != "?" ]] && printf " (%s дней)" "$days_left"
    echo
    
    # Алерты для SSL
    if [[ "$ALERTS_ONLY" == true ]]; then
        [[ "$cert_status" == "ERROR" ]] && echo -e "${RED}🚨 АЛЕРТ: Ошибка проверки SSL сертификата${NC}"
        [[ "$cert_status" == "CRITICAL" ]] && echo -e "${RED}🚨 АЛЕРТ: SSL сертификат истекает через $days_left дней${NC}"
        [[ "$cert_status" == "WARN" ]] && echo -e "${YELLOW}⚠️  ПРЕДУПРЕЖДЕНИЕ: SSL сертификат истекает через $days_left дней${NC}"
    fi
    
    echo
}

# Системные ресурсы
check_resources() {
    echo -e "${BOLD}💻 Системные Ресурсы:${NC}"
    
    # Память
    local mem_info=$(free -m | awk '/^Mem:/{printf "%.1f/%.1fGB (%.0f%%)", $3/1024, $2/1024, $3*100/$2}')
    local mem_percent=$(free | awk '/^Mem:/{printf "%.0f", $3*100/$2}')
    local mem_indicator
    if [[ $mem_percent -lt 80 ]]; then
        mem_indicator=$(status_indicator "UP")
    elif [[ $mem_percent -lt 90 ]]; then
        mem_indicator=$(status_indicator "WARN")
    else
        mem_indicator=$(status_indicator "DOWN")
    fi
    
    # Диск
    local disk_info=$(df -h "$SCRIPT_DIR" | awk 'NR==2 {printf "%s/%s (%s)", $3, $2, $5}')
    local disk_percent=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    local disk_indicator
    if [[ $disk_percent -lt 80 ]]; then
        disk_indicator=$(status_indicator "UP")
    elif [[ $disk_percent -lt 90 ]]; then
        disk_indicator=$(status_indicator "WARN")
    else
        disk_indicator=$(status_indicator "DOWN")
    fi
    
    # CPU Load
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    local load_percent=$(echo "scale=0; $load_avg * 100 / $cpu_cores" | bc -l 2>/dev/null || echo "0")
    local load_indicator
    if [[ $load_percent -lt 70 ]]; then
        load_indicator=$(status_indicator "UP")
    elif [[ $load_percent -lt 90 ]]; then
        load_indicator=$(status_indicator "WARN")
    else
        load_indicator=$(status_indicator "DOWN")
    fi
    
    if [[ "$COMPACT_MODE" == false ]]; then
        printf "  %-12s %s %s\n" "Память" "$mem_indicator" "$mem_info"
        printf "  %-12s %s %s\n" "Диск" "$disk_indicator" "$disk_info"
        printf "  %-12s %s %s\n" "Нагрузка" "$load_indicator" "${load_avg} (${load_percent}%)"
    else
        local resources_ok=true
        [[ $mem_percent -gt 90 ]] && resources_ok=false
        [[ $disk_percent -gt 90 ]] && resources_ok=false
        [[ $load_percent -gt 90 ]] && resources_ok=false
        
        if [[ "$resources_ok" == true ]]; then
            echo -e "  Ресурсы: ${GREEN}● НОРМА${NC} (RAM:${mem_percent}%, Диск:${disk_percent}%, CPU:${load_percent}%)"
        else
            echo -e "  Ресурсы: ${YELLOW}● НАГРУЗКА${NC} (RAM:${mem_percent}%, Диск:${disk_percent}%, CPU:${load_percent}%)"
        fi
    fi
    
    # Алерты для ресурсов
    if [[ "$ALERTS_ONLY" == true ]]; then
        [[ $mem_percent -gt 90 ]] && echo -e "${RED}🚨 АЛЕРТ: Высокое использование памяти (${mem_percent}%)${NC}"
        [[ $disk_percent -gt 90 ]] && echo -e "${RED}🚨 АЛЕРТ: Мало места на диске (${disk_percent}%)${NC}"
        [[ $load_percent -gt 90 ]] && echo -e "${RED}🚨 АЛЕРТ: Высокая нагрузка на CPU (${load_percent}%)${NC}"
    fi
    
    echo
}

# Docker статистика
check_docker_stats() {
    if [[ "$COMPACT_MODE" == true ]]; then
        return 0
    fi
    
    echo -e "${BOLD}📊 Docker Статистика:${NC}"
    
    # Получаем статистику контейнеров
    local stats_output=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | tail -n +2)
    
    if [[ -n "$stats_output" ]]; then
        echo "$stats_output" | while IFS=$'\t' read -r name cpu mem; do
            local cpu_num=$(echo "$cpu" | sed 's/%//')
            local cpu_indicator
            if [[ $(echo "$cpu_num < 50" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                cpu_indicator=$(status_indicator "UP")
            elif [[ $(echo "$cpu_num < 80" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                cpu_indicator=$(status_indicator "WARN")
            else
                cpu_indicator=$(status_indicator "DOWN")
            fi
            
            printf "  %-12s %s CPU: %s, RAM: %s\n" "$name" "$cpu_indicator" "$cpu" "$mem"
        done
    else
        echo -e "  ${YELLOW}Нет данных о контейнерах${NC}"
    fi
    
    echo
}

# Последние события
check_recent_events() {
    if [[ "$COMPACT_MODE" == true ]]; then
        return 0
    fi
    
    echo -e "${BOLD}📅 Последние События:${NC}"
    
    local compose_cmd="docker compose"
    if ! docker compose version &> /dev/null; then
        compose_cmd="docker-compose"
    fi
    
    # Последние логи с ошибками
    local recent_errors=$($compose_cmd logs --since=1m 2>/dev/null | grep -i "error\|fail\|fatal" | tail -3)
    
    if [[ -n "$recent_errors" ]]; then
        echo -e "  ${RED}Недавние ошибки:${NC}"
        echo "$recent_errors" | while read -r line; do
            echo -e "    ${RED}•${NC} $(echo "$line" | cut -c1-80)..."
        done
    else
        echo -e "  ${GREEN}✓ Нет недавних ошибок${NC}"
    fi
    
    echo
}

# Основной цикл мониторинга
monitor_loop() {
    while true; do
        clear_screen
        print_header
        
        check_containers
        check_network
        check_ssl
        check_resources
        check_docker_stats
        check_recent_events
        
        echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Следующее обновление через ${REFRESH_INTERVAL} секунд... (Ctrl+C для выхода)${NC}"
        
        sleep "$REFRESH_INTERVAL"
    done
}

# Основная функция
main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --compact)
                COMPACT_MODE=true
                shift
                ;;
            --alerts-only)
                ALERTS_ONLY=true
                shift
                ;;
            --interval)
                REFRESH_INTERVAL="$2"
                shift 2
                ;;
            --help|-h)
                echo "Использование: $0 [ОПЦИИ]"
                echo
                echo "Опции:"
                echo "  --compact        Компактный режим отображения"
                echo "  --alerts-only    Показывать только алерты и предупреждения"
                echo "  --interval SEC   Интервал обновления в секундах (по умолчанию: 5)"
                echo "  --help, -h       Показать эту справку"
                echo
                echo "Примеры:"
                echo "  $0               Полный мониторинг"
                echo "  $0 --compact     Компактный режим"
                echo "  $0 --alerts-only Только алерты"
                echo
                echo "Горячие клавиши:"
                echo "  Ctrl+C           Выход"
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
    
    # Проверяем что мы в правильной директории
    if [[ ! -f "docker-compose.yml" ]]; then
        echo -e "${RED}❌ Ошибка: Запустите скрипт из корневой директории Ninja DNS${NC}"
        exit 1
    fi
    
    load_config
    
    # Устанавливаем обработчик сигналов
    trap 'echo -e "\n${CYAN}Мониторинг остановлен.${NC}"; exit 0' INT TERM
    
    # Проверяем зависимости
    for cmd in docker curl nslookup bc; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}❌ Ошибка: Команда $cmd не найдена${NC}"
            exit 1
        fi
    done
    
    monitor_loop
}

# Запуск
main "$@"