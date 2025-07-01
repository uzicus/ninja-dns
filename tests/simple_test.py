#!/usr/bin/env python3
"""
Простой тест DNS функциональности без изменения системных настроек
"""
import subprocess
import requests
import json


def test_dns_resolution():
    """Тест резолвинга тестового домена через наш DNS"""
    print("🧪 Тест 1: Резолвинг test.dns.uzicus.ru через наш DNS")
    
    try:
        # Тестируем через наш DNS
        result = subprocess.run([
            'nslookup', 'test.dns.uzicus.ru', '185.237.95.211'
        ], capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0 and '185.237.95.211' in result.stdout:
            print("✅ test.dns.uzicus.ru корректно резолвится через наш DNS в 185.237.95.211")
            return True
        else:
            print(f"❌ Ошибка резолвинга через наш DNS: {result.stdout} {result.stderr}")
            return False
            
    except Exception as e:
        print(f"❌ Ошибка при тестировании резолвинга: {e}")
        return False


def test_public_dns_resolution():
    """Тест что тестовый домен НЕ резолвится через публичный DNS"""
    print("\n🧪 Тест 2: test.dns.uzicus.ru НЕ должен резолвиться через 8.8.8.8")
    
    try:
        # Тестируем через публичный DNS - должно упасть
        result = subprocess.run([
            'nslookup', 'test.dns.uzicus.ru', '8.8.8.8'
        ], capture_output=True, text=True, timeout=10)
        
        if result.returncode != 0 and ('NXDOMAIN' in result.stderr or 'NXDOMAIN' in result.stdout):
            print("✅ test.dns.uzicus.ru корректно НЕ резолвится через публичный DNS")
            return True
        elif 'NXDOMAIN' in result.stdout:
            print("✅ test.dns.uzicus.ru корректно НЕ резолвится через публичный DNS")
            return True
        else:
            print(f"❌ Неожиданно: домен резолвится через публичный DNS: {result.stdout}")
            return False
            
    except Exception as e:
        print(f"❌ Ошибка при тестировании публичного DNS: {e}")
        return False


def test_main_page_loads():
    """Тест загрузки основной страницы"""
    print("\n🧪 Тест 3: Загрузка главной страницы DNS проверки")
    
    try:
        response = requests.get('https://dns.uzicus.ru/', timeout=10, verify=False)
        
        if response.status_code == 200:
            if 'Baltic DNS' in response.text and 'checkDNS' in response.text:
                print("✅ Главная страница загружается и содержит функцию проверки DNS")
                return True
            else:
                print("❌ Страница загружается, но не содержит ожидаемый контент")
                return False
        else:
            print(f"❌ Ошибка загрузки страницы: HTTP {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ Ошибка при загрузке страницы: {e}")
        return False


def test_static_file_via_dns():
    """Тест доступности статического файла через наш DNS"""
    print("\n🧪 Тест 4: Доступность test.json через наш DNS (косвенно)")
    
    try:
        # Используем dig для проверки что домен резолвится правильно
        result = subprocess.run([
            'dig', '@185.237.95.211', 'test.dns.uzicus.ru', 'A', '+short'
        ], capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0 and '185.237.95.211' in result.stdout:
            print("✅ test.dns.uzicus.ru резолвится в правильный IP через dig")
            
            # Проверим что traefik правильно настроен для test домена
            # (мы не можем напрямую обратиться к test.dns.uzicus.ru без настройки DNS)
            print("ℹ️  Для полной проверки нужно настроить DNS клиента на 185.237.95.211")
            return True
        else:
            print(f"❌ dig не смог резолвить домен: {result.stdout} {result.stderr}")
            return False
            
    except Exception as e:
        print(f"❌ Ошибка при тестировании dig: {e}")
        return False


def test_services_running():
    """Тест что все сервисы запущены"""
    print("\n🧪 Тест 5: Проверка статуса Docker сервисов")
    
    try:
        result = subprocess.run([
            'docker', 'compose', 'ps', '--format', 'json'
        ], capture_output=True, text=True, timeout=10, cwd='/root/baltic-dns')
        
        if result.returncode == 0:
            services = []
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    try:
                        service = json.loads(line)
                        services.append(service)
                    except:
                        pass
            
            running_services = [s for s in services if s.get('State') == 'running']
            
            expected_services = ['admin', 'traefik', 'smartdns', 'sniproxy', 'doh-proxy']
            running_names = [s.get('Service', s.get('Name', '')) for s in running_services]
            
            all_running = all(svc in running_names for svc in expected_services)
            
            if all_running:
                print(f"✅ Все сервисы запущены: {running_names}")
                return True
            else:
                print(f"❌ Не все сервисы запущены. Ожидали: {expected_services}, Запущены: {running_names}")
                return False
        else:
            print(f"❌ Ошибка получения статуса Docker: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"❌ Ошибка при проверке Docker сервисов: {e}")
        return False


def main():
    """Запуск всех тестов"""
    print("🧪 Baltic DNS - Простые тесты функциональности")
    print("=" * 50)
    
    tests = [
        test_dns_resolution,
        test_public_dns_resolution,
        test_main_page_loads,
        test_static_file_via_dns,
        test_services_running
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        if test():
            passed += 1
    
    print(f"\n📊 Результаты: {passed}/{total} тестов прошли")
    
    if passed == total:
        print("🎉 Все тесты прошли успешно!")
        print("\n💡 Для полного тестирования в браузере:")
        print("   1. Настройте DNS клиента на 185.237.95.211")
        print("   2. Откройте https://dns.uzicus.ru/")
        print("   3. Проверьте что показывается '✅ Подключен!'")
        return True
    else:
        print("❌ Некоторые тесты не прошли. Проверьте настройки сервисов.")
        return False


if __name__ == "__main__":
    main()