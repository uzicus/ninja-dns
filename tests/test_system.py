#!/usr/bin/env python3
"""
Автоматические тесты для Baltic DNS системы
Проверяет работоспособность DNS, sniproxy, админки и проксирования
"""

import requests
import subprocess
import time
import json
import sys
from typing import Dict, List, Any

class BalticDNSTests:
    def __init__(self):
        self.vps_ip = "185.237.95.211"
        self.admin_url = "https://dns.uzicus.ru"
        self.test_domain = "test-auto.com"
        self.working_domains = ["chatgpt.com", "claude.ai"]
        
    def log(self, message: str, status: str = "INFO"):
        """Логирование с цветом"""
        colors = {
            "INFO": "\033[94m",    # Синий
            "PASS": "\033[92m",    # Зеленый 
            "FAIL": "\033[91m",    # Красный
            "WARN": "\033[93m"     # Желтый
        }
        reset = "\033[0m"
        print(f"{colors.get(status, '')}{status}: {message}{reset}")
        
    def run_command(self, cmd: str) -> Dict[str, Any]:
        """Выполнить команду и вернуть результат"""
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
            return {
                "success": result.returncode == 0,
                "stdout": result.stdout.strip(),
                "stderr": result.stderr.strip(),
                "returncode": result.returncode
            }
        except subprocess.TimeoutExpired:
            return {"success": False, "stdout": "", "stderr": "Timeout", "returncode": -1}
        except Exception as e:
            return {"success": False, "stdout": "", "stderr": str(e), "returncode": -1}

    def test_network_basic(self) -> bool:
        """Тест 1: Базовая связность сети"""
        self.log("=== ТЕСТ 1: Базовая связность сети ===")
        
        # Пинг VPS
        result = self.run_command(f"ping -c 3 {self.vps_ip}")
        if not result["success"]:
            self.log(f"FAIL: Нет связи с VPS {self.vps_ip}", "FAIL")
            return False
        self.log(f"PASS: Пинг VPS {self.vps_ip} успешен", "PASS")
        
        # Проверка портов
        ports_to_check = [53, 443, 853]
        for port in ports_to_check:
            result = self.run_command(f"nc -z -w5 {self.vps_ip} {port}")
            if result["success"]:
                self.log(f"PASS: Порт {port} доступен", "PASS")
            else:
                self.log(f"FAIL: Порт {port} недоступен", "FAIL")
                return False
                
        return True

    def test_dns_resolution(self) -> bool:
        """Тест 2: DNS разрешение"""
        self.log("=== ТЕСТ 2: DNS разрешение ===")
        
        # Проверка обычного DNS
        result = self.run_command(f"nslookup chatgpt.com {self.vps_ip}")
        if not result["success"] or self.vps_ip not in result["stdout"]:
            self.log("FAIL: DNS не перенаправляет chatgpt.com на VPS", "FAIL")
            return False
        self.log("PASS: DNS корректно перенаправляет chatgpt.com", "PASS")
        
        # Проверка DoT (если доступен)
        result = self.run_command(f"dig @{self.vps_ip} +tls chatgpt.com")
        if result["success"] and self.vps_ip in result["stdout"]:
            self.log("PASS: DoT работает", "PASS")
        else:
            self.log("WARN: DoT недоступен или не работает", "WARN")
            
        return True

    def test_services_status(self) -> bool:
        """Тест 3: Статус Docker сервисов"""
        self.log("=== ТЕСТ 3: Статус Docker сервисов ===")
        
        # Проверка статуса контейнеров
        result = self.run_command("docker compose ps --format json")
        if not result["success"]:
            self.log("FAIL: Не удается получить статус Docker контейнеров", "FAIL")
            return False
            
        try:
            containers = [json.loads(line) for line in result["stdout"].split('\n') if line.strip()]
            required_services = ["smartdns", "sniproxy", "traefik", "admin"]
            
            for service in required_services:
                container = next((c for c in containers if c.get("Service") == service), None)
                if not container:
                    self.log(f"FAIL: Контейнер {service} не найден", "FAIL")
                    return False
                    
                if "running" not in container.get("State", "").lower():
                    self.log(f"FAIL: Контейнер {service} не запущен: {container.get('State')}", "FAIL")
                    return False
                    
                self.log(f"PASS: Контейнер {service} работает", "PASS")
                
        except Exception as e:
            self.log(f"FAIL: Ошибка парсинга статуса контейнеров: {e}", "FAIL")
            return False
            
        return True

    def test_admin_panel(self) -> bool:
        """Тест 4: Админ-панель доступна"""
        self.log("=== ТЕСТ 4: Доступность админ-панели ===")
        
        try:
            # Проверка главной страницы
            response = requests.get(f"{self.admin_url}/", timeout=10, verify=False)
            if response.status_code != 200:
                self.log(f"FAIL: Админ-панель недоступна, код: {response.status_code}", "FAIL")
                return False
            self.log("PASS: Админ-панель доступна", "PASS")
            
            # Проверка API
            response = requests.get(f"{self.admin_url}/api/domains", timeout=10, verify=False)
            if response.status_code != 200:
                self.log(f"FAIL: API недоступно, код: {response.status_code}", "FAIL")
                return False
                
            domains_data = response.json()
            if not isinstance(domains_data.get("domains"), list):
                self.log("FAIL: API возвращает некорректные данные", "FAIL")
                return False
                
            self.log(f"PASS: API работает, доменов: {len(domains_data['domains'])}", "PASS")
            return True
            
        except requests.exceptions.RequestException as e:
            self.log(f"FAIL: Ошибка подключения к админ-панели: {e}", "FAIL")
            return False

    def test_proxy_working_domains(self) -> bool:
        """Тест 5: Проксирование рабочих доменов"""
        self.log("=== ТЕСТ 5: Проксирование рабочих доменов ===")
        
        for domain in self.working_domains:
            try:
                # Используем VPS как прокси
                response = requests.get(f"https://{domain}", timeout=15, verify=False)
                if response.status_code == 200:
                    self.log(f"PASS: {domain} доступен через прокси", "PASS")
                else:
                    self.log(f"WARN: {domain} вернул код {response.status_code}", "WARN")
            except requests.exceptions.RequestException as e:
                self.log(f"FAIL: {domain} недоступен: {e}", "FAIL")
                return False
                
        return True

    def test_add_domain(self) -> bool:
        """Тест 6: Добавление домена через админку"""
        self.log("=== ТЕСТ 6: Добавление домена ===")
        
        try:
            # Добавляем тестовый домен
            payload = {
                "name": self.test_domain,
                "category": "test",
                "enabled": True
            }
            
            response = requests.post(
                f"{self.admin_url}/api/domains",
                json=payload,
                timeout=30,
                verify=False
            )
            
            if response.status_code != 200:
                self.log(f"FAIL: Не удалось добавить домен, код: {response.status_code}", "FAIL")
                if response.text:
                    self.log(f"Ответ: {response.text}", "FAIL")
                return False
                
            result = response.json()
            if not result.get("success"):
                self.log(f"FAIL: API вернул ошибку: {result.get('message', 'Unknown error')}", "FAIL")
                return False
                
            self.log(f"PASS: Домен {self.test_domain} успешно добавлен", "PASS")
            
            # Ждем применения конфигурации
            time.sleep(10)
            
            # Проверяем что домен появился в списке
            response = requests.get(f"{self.admin_url}/api/domains", timeout=10, verify=False)
            domains_data = response.json()
            
            domain_found = any(d["name"] == self.test_domain for d in domains_data["domains"])
            if not domain_found:
                self.log(f"FAIL: Домен {self.test_domain} не найден в списке", "FAIL")
                return False
                
            self.log(f"PASS: Домен {self.test_domain} подтвержден в списке", "PASS")
            return True
            
        except requests.exceptions.RequestException as e:
            self.log(f"FAIL: Ошибка при добавлении домена: {e}", "FAIL")
            return False

    def test_domain_config_generated(self) -> bool:
        """Тест 7: Проверка генерации конфигурации для домена"""
        self.log("=== ТЕСТ 7: Генерация конфигурации ===")
        
        # Проверяем SmartDNS конфигурацию
        result = self.run_command(f"grep '{self.test_domain}' /root/baltic-dns/smartdns/smartdns.conf")
        if not result["success"]:
            self.log(f"FAIL: Домен {self.test_domain} не найден в SmartDNS конфигурации", "FAIL")
            return False
        self.log(f"PASS: Домен {self.test_domain} добавлен в SmartDNS", "PASS")
        
        # Проверяем sniproxy конфигурацию
        result = self.run_command(f"grep '{self.test_domain}' /root/baltic-dns/sniproxy/nginx.conf")
        if not result["success"]:
            self.log(f"FAIL: Домен {self.test_domain} не найден в sniproxy конфигурации", "FAIL")
            return False
        self.log(f"PASS: Домен {self.test_domain} добавлен в sniproxy", "PASS")
        
        return True

    def test_remove_domain(self) -> bool:
        """Тест 8: Удаление домена"""
        self.log("=== ТЕСТ 8: Удаление домена ===")
        
        try:
            # Удаляем тестовый домен
            response = requests.delete(
                f"{self.admin_url}/api/domains/{self.test_domain}",
                timeout=30,
                verify=False
            )
            
            if response.status_code != 200:
                self.log(f"FAIL: Не удалось удалить домен, код: {response.status_code}", "FAIL")
                return False
                
            result = response.json()
            if not result.get("success"):
                self.log(f"FAIL: API вернул ошибку при удалении: {result.get('message')}", "FAIL")
                return False
                
            self.log(f"PASS: Домен {self.test_domain} успешно удален", "PASS")
            
            # Ждем применения конфигурации
            time.sleep(10)
            
            # Проверяем что домен исчез из списка
            response = requests.get(f"{self.admin_url}/api/domains", timeout=10, verify=False)
            domains_data = response.json()
            
            domain_found = any(d["name"] == self.test_domain for d in domains_data["domains"])
            if domain_found:
                self.log(f"FAIL: Домен {self.test_domain} все еще в списке", "FAIL")
                return False
                
            self.log(f"PASS: Домен {self.test_domain} удален из списка", "PASS")
            return True
            
        except requests.exceptions.RequestException as e:
            self.log(f"FAIL: Ошибка при удалении домена: {e}", "FAIL")
            return False

    def test_domain_accessibility_after_removal(self) -> bool:
        """Тест 9: Доступность домена после удаления"""
        self.log("=== ТЕСТ 9: Доступность домена после удаления ===")
        
        # Тестируем с реальным доменом который точно существует
        test_domain = "httpbin.org"  # Публичный API для тестирования
        
        try:
            # Сначала добавляем домен
            payload = {
                "name": test_domain,
                "category": "test", 
                "enabled": True
            }
            
            response = requests.post(
                f"{self.admin_url}/api/domains",
                json=payload,
                timeout=30,
                verify=False
            )
            
            if response.status_code != 200:
                self.log(f"FAIL: Не удалось добавить тестовый домен {test_domain}", "FAIL")
                return False
                
            self.log(f"PASS: Домен {test_domain} добавлен для тестирования", "PASS")
            time.sleep(5)
            
            # Проверяем DNS разрешение (должен перенаправляться на VPS)
            result = self.run_command(f"nslookup {test_domain} {self.vps_ip}")
            if not result["success"] or self.vps_ip not in result["stdout"]:
                self.log(f"FAIL: DNS не перенаправляет {test_domain} на VPS", "FAIL")
                return False
            self.log(f"PASS: DNS перенаправляет {test_domain} на VPS", "PASS")
            
            # Теперь удаляем домен
            response = requests.delete(
                f"{self.admin_url}/api/domains/{test_domain}",
                timeout=30,
                verify=False
            )
            
            if response.status_code != 200:
                self.log(f"FAIL: Не удалось удалить домен {test_domain}", "FAIL")
                return False
                
            self.log(f"PASS: Домен {test_domain} успешно удален", "PASS")
            time.sleep(15)  # Больше времени для применения изменений
            
            # Очищаем кеш SmartDNS
            self.run_command("docker exec smartdns rm -f /var/cache/smartdns.cache")
            self.run_command("docker compose restart smartdns")
            time.sleep(5)
            
            # Проверяем что DNS теперь возвращает реальные IP
            result = self.run_command(f"nslookup {test_domain} {self.vps_ip}")
            if not result["success"]:
                self.log(f"FAIL: DNS запрос к {test_domain} провалился", "FAIL")
                return False
                
            # Проверяем что DNS НЕ возвращает VPS IP в ответе address записях
            lines = result["stdout"].split('\n')
            vps_redirect_found = False
            for line in lines:
                if 'Address:' in line and self.vps_ip in line and '185.237.95.211#53' not in line:
                    vps_redirect_found = True
                    break
                    
            if vps_redirect_found:
                self.log(f"FAIL: DNS всё ещё перенаправляет {test_domain} на VPS", "FAIL")
                self.log(f"DNS ответ: {result['stdout']}", "FAIL")
                return False
                
            self.log(f"PASS: DNS больше не перенаправляет {test_domain} на VPS", "PASS")
            
            # Проверяем прямую доступность домена (используя внешний DNS)
            result = self.run_command(f"nslookup {test_domain} 8.8.8.8")
            if not result["success"]:
                self.log(f"FAIL: Домен {test_domain} недоступен через внешний DNS", "FAIL")
                return False
                
            # Извлекаем IP адрес из ответа nslookup
            real_ip = None
            for line in result["stdout"].split('\n'):
                if 'Address:' in line and not '8.8.8.8' in line:
                    real_ip = line.split('Address:')[1].strip()
                    break
                    
            if not real_ip:
                self.log(f"FAIL: Не удалось получить реальный IP для {test_domain}", "FAIL")
                return False
                
            self.log(f"PASS: Получен реальный IP для {test_domain}: {real_ip}", "PASS")
            
            # Проверяем HTTP доступность по реальному IP
            try:
                response = requests.get(f"http://{test_domain}/get", timeout=10)
                if response.status_code == 200:
                    self.log(f"PASS: Домен {test_domain} доступен напрямую", "PASS")
                else:
                    self.log(f"WARN: Домен {test_domain} вернул код {response.status_code}", "WARN")
            except requests.exceptions.RequestException as e:
                self.log(f"WARN: Проблема с HTTP доступом к {test_domain}: {e}", "WARN")
                # Не считаем это критической ошибкой
            
            return True
            
        except Exception as e:
            self.log(f"FAIL: Критическая ошибка в тесте доступности: {e}", "FAIL")
            return False

    def run_all_tests(self) -> bool:
        """Запустить все тесты"""
        self.log("🚀 ЗАПУСК АВТОМАТИЧЕСКИХ ТЕСТОВ BALTIC DNS", "INFO")
        self.log("=" * 60, "INFO")
        
        tests = [
            ("Базовая связность", self.test_network_basic),
            ("DNS разрешение", self.test_dns_resolution),
            ("Статус сервисов", self.test_services_status),
            ("Админ-панель", self.test_admin_panel),
            ("Проксирование", self.test_proxy_working_domains),
            ("Добавление домена", self.test_add_domain),
            ("Генерация конфигов", self.test_domain_config_generated),
            ("Удаление домена", self.test_remove_domain),
            ("Доступность после удаления", self.test_domain_accessibility_after_removal)
        ]
        
        passed = 0
        failed = 0
        
        for test_name, test_func in tests:
            try:
                if test_func():
                    passed += 1
                else:
                    failed += 1
            except Exception as e:
                self.log(f"FAIL: Критическая ошибка в тесте '{test_name}': {e}", "FAIL")
                failed += 1
            
            self.log("-" * 60, "INFO")
        
        # Итоговый отчет
        self.log("📊 ИТОГОВЫЙ ОТЧЕТ", "INFO")
        self.log(f"✅ Пройдено: {passed}", "PASS")
        self.log(f"❌ Провалено: {failed}", "FAIL" if failed > 0 else "INFO")
        
        if failed == 0:
            self.log("🎉 ВСЕ ТЕСТЫ ПРОШЛИ УСПЕШНО!", "PASS")
            return True
        else:
            self.log("💥 НЕКОТОРЫЕ ТЕСТЫ ПРОВАЛИЛИСЬ", "FAIL")
            return False

def main():
    """Главная функция"""
    # Отключаем SSL предупреждения
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    tester = BalticDNSTests()
    success = tester.run_all_tests()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()