#!/bin/bash

echo "🧪 Baltic DNS - Запуск браузерных тестов"
echo "========================================"

# Проверяем что мы находимся в правильной директории
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Запустите скрипт из корня проекта baltic-dns"
    exit 1
fi

# Переходим в директорию тестов
cd tests

# Устанавливаем зависимости если нужно
if [ ! -d "venv" ]; then
    echo "📦 Создаем виртуальное окружение для тестов..."
    python3 -m venv venv
fi

echo "📦 Активируем виртуальное окружение..."
source venv/bin/activate

echo "📦 Устанавливаем зависимости..."
pip install -r requirements.txt

echo "🌐 Устанавливаем браузеры Playwright..."
playwright install chromium

echo "🧪 Запускаем тесты..."
python browser_dns_test.py

echo "✅ Тесты завершены!"