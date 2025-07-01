#!/bin/bash

# Скрипт для генерации dynamic.yml из template
# Использует переменные окружения из .env файла

set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔧 Генерация dynamic.yml из template...${NC}"

# Проверяем что мы в корневой директории проекта
if [[ ! -f "docker-compose.yml" ]]; then
    echo -e "${RED}❌ Ошибка: Запустите скрипт из корневой директории проекта${NC}"
    exit 1
fi

# Проверяем наличие .env файла
if [[ ! -f ".env" ]]; then
    echo -e "${RED}❌ Ошибка: Файл .env не найден. Скопируйте .env.example в .env и настройте${NC}"
    exit 1
fi

# Загружаем переменные из .env
echo -e "${YELLOW}📋 Загружаем конфигурацию из .env...${NC}"
export $(grep -v '^#' .env | xargs)

# Проверяем обязательные переменные
if [[ -z "$HOST_DOMAIN" ]]; then
    echo -e "${RED}❌ Ошибка: HOST_DOMAIN не установлен в .env${NC}"
    exit 1
fi

if [[ -z "$TEST_SUBDOMAIN" ]]; then
    TEST_SUBDOMAIN="test"
fi

# Формируем полный тестовый домен
TEST_DOMAIN="${TEST_SUBDOMAIN}.${HOST_DOMAIN}"

echo -e "${YELLOW}🌐 HOST_DOMAIN: ${HOST_DOMAIN}${NC}"
echo -e "${YELLOW}🧪 TEST_DOMAIN: ${TEST_DOMAIN}${NC}"

# Проверяем наличие template файла
TEMPLATE_FILE="traefik/dynamic/dynamic.yml.template"
OUTPUT_FILE="traefik/dynamic/dynamic.yml"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo -e "${RED}❌ Ошибка: Template файл $TEMPLATE_FILE не найден${NC}"
    exit 1
fi

# Создаем директорию если не существует
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Генерируем dynamic.yml из template
echo -e "${YELLOW}📝 Генерируем $OUTPUT_FILE...${NC}"

sed -e "s/{{HOST_DOMAIN}}/$HOST_DOMAIN/g" \
    -e "s/{{TEST_DOMAIN}}/$TEST_DOMAIN/g" \
    "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo -e "${GREEN}✅ Файл $OUTPUT_FILE успешно сгенерирован${NC}"

# Проверяем валидность YAML (если установлен yq)
if command -v yq > /dev/null 2>&1; then
    echo -e "${YELLOW}🔍 Проверяем валидность YAML...${NC}"
    if yq eval . "$OUTPUT_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ YAML файл валиден${NC}"
    else
        echo -e "${RED}❌ Ошибка: Сгенерированный YAML файл невалиден${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  yq не найден, пропускаем валидацию YAML${NC}"
fi

echo -e "${GREEN}🎉 Конфигурация Traefik готова!${NC}"