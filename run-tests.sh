#!/bin/bash

# Ninja DNS - Автоматические тесты системы
# Этот скрипт проверяет всю инфраструктуру и выдает отчет

echo "🧪 Ninja DNS - Автоматические тесты"
echo "======================================"

# Проверяем что мы в правильной директории
cd /root/baltic-dns

# Устанавливаем зависимости для тестов если нужно
if ! python3 -c "import requests" 2>/dev/null; then
    echo "📦 Устанавливаем зависимости для тестов..."
    pip3 install requests urllib3
fi

# Запускаем тесты
echo "🚀 Запуск тестов..."
python3 tests/test_system.py

# Сохраняем результат
exit_code=$?

echo ""
echo "======================================"
if [ $exit_code -eq 0 ]; then
    echo "✅ Все тесты прошли успешно!"
    echo "🎉 Ninja DNS система работает корректно"
else
    echo "❌ Некоторые тесты провалились"
    echo "🔧 Требуется диагностика системы"
fi

echo ""
echo "📝 Для диагностики используйте:"
echo "   docker compose ps          # Статус контейнеров"
echo "   docker compose logs        # Логи всех сервисов"
echo "   curl -k https://dns.uzicus.ru/api/domains  # API админки"
echo ""

exit $exit_code