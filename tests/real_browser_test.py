#!/usr/bin/env python3
"""
Реальные браузерные тесты для проверки DNS функциональности Ninja DNS
Проверяют как работает проверка DNS в реальном браузере
"""
import asyncio
import pytest
import tempfile
import os
from playwright.async_api import async_playwright, Page, Browser


class DNSTestRunner:
    """Класс для эмуляции разных DNS настроек через hosts файл"""
    
    def __init__(self):
        self.original_hosts = None
        self.temp_hosts_file = None
        
    async def setup_hosts_for_baltic_dns(self):
        """Настроить hosts файл чтобы test.dns.uzicus.ru резолвился в наш IP"""
        try:
            # Создаем временный hosts файл
            self.temp_hosts_file = tempfile.NamedTemporaryFile(mode='w', delete=False)
            
            # Читаем оригинальный hosts файл
            try:
                with open('/etc/hosts', 'r') as f:
                    original_content = f.read()
                self.original_hosts = original_content
            except:
                self.original_hosts = ""
            
            # Записываем в временный файл оригинальное содержимое + наш домен
            hosts_content = self.original_hosts + "\n# Ninja DNS test\n185.237.95.211 test.dns.uzicus.ru\n"
            self.temp_hosts_file.write(hosts_content)
            self.temp_hosts_file.close()
            
            print(f"✅ Создан временный hosts файл: {self.temp_hosts_file.name}")
            return self.temp_hosts_file.name
            
        except Exception as e:
            print(f"❌ Ошибка при настройке hosts файла: {e}")
            return None
    
    async def setup_hosts_for_public_dns(self):
        """Настроить hosts файл БЕЗ test.dns.uzicus.ru (эмуляция публичного DNS)"""
        try:
            # Создаем временный hosts файл только с оригинальным содержимым
            self.temp_hosts_file = tempfile.NamedTemporaryFile(mode='w', delete=False)
            
            if self.original_hosts is None:
                try:
                    with open('/etc/hosts', 'r') as f:
                        self.original_hosts = f.read()
                except:
                    self.original_hosts = ""
            
            # Записываем только оригинальное содержимое (без test.dns.uzicus.ru)
            hosts_content = self.original_hosts
            self.temp_hosts_file.write(hosts_content)
            self.temp_hosts_file.close()
            
            print(f"✅ Создан hosts файл для публичного DNS: {self.temp_hosts_file.name}")
            return self.temp_hosts_file.name
            
        except Exception as e:
            print(f"❌ Ошибка при настройке hosts файла для публичного DNS: {e}")
            return None
    
    def cleanup(self):
        """Очистить временные файлы"""
        if self.temp_hosts_file and os.path.exists(self.temp_hosts_file.name):
            try:
                os.unlink(self.temp_hosts_file.name)
                print(f"✅ Удален временный hosts файл")
            except:
                pass


@pytest.fixture
async def browser():
    """Фикстура для создания браузера"""
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=True,
            args=[
                '--no-sandbox',
                '--disable-dev-shm-usage',
                '--disable-web-security',
                '--ignore-certificate-errors',
                '--disable-features=VizDisplayCompositor'
            ]
        )
        yield browser
        await browser.close()


async def create_page_with_hosts(browser: Browser, hosts_file: str = None):
    """Создать страницу браузера с кастомным hosts файлом"""
    if hosts_file:
        # Создаем контекст браузера с кастомным hosts файлом
        context = await browser.new_context(
            extra_http_headers={
                'Cache-Control': 'no-cache',
                'Pragma': 'no-cache'
            }
        )
        # К сожалению, Playwright не поддерживает кастомный hosts файл напрямую
        # Поэтому мы будем эмулировать поведение через перехват сетевых запросов
    else:
        context = await browser.new_context()
    
    page = await context.new_page()
    page.set_default_timeout(30000)
    return page, context


class TestDNSBrowserFunctionality:
    """Браузерные тесты для проверки DNS функциональности"""
    
    @pytest.mark.asyncio
    async def test_page_loads_without_auth(self, browser: Browser):
        """Тест 1: Проверка что страница загружается без авторизации"""
        page, context = await create_page_with_hosts(browser)
        
        try:
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Проверяем что страница загрузилась (не требует авторизации)
            title = await page.title()
            assert "Ninja DNS" in title
            
            # Проверяем что есть элементы проверки DNS
            check_button = page.locator("button:has-text('Проверить подключение')")
            await check_button.wait_for(state="visible")
            
            dns_title = page.locator("h1:has-text('Ninja DNS')")
            await dns_title.wait_for(state="visible")
            
            print("✅ Страница DNS проверки загружается без авторизации")
            
        except Exception as e:
            print(f"❌ Ошибка при загрузке страницы: {e}")
            raise
        finally:
            await context.close()
    
    @pytest.mark.asyncio 
    async def test_dns_check_with_mock_success(self, browser: Browser):
        """Тест 2: Эмуляция успешной DNS проверки"""
        page, context = await create_page_with_hosts(browser)
        
        try:
            # Перехватываем сетевые запросы к test.dns.uzicus.ru
            await context.route("**/test.dns.uzicus.ru/**", lambda route: route.fulfill(
                status=200,
                body="OK"
            ))
            
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Ждем завершения автоматической проверки или нажимаем кнопку
            await asyncio.sleep(8)
            
            # Проверяем результат
            success_indicator = page.locator("h3:has-text('✅ Подключен!')")
            
            if await success_indicator.count() > 0:
                print("✅ DNS проверка показала успешное подключение (мок)")
                
                # Проверяем детали
                test_domain = page.locator("span:has-text('test.dns.uzicus.ru')")
                if await test_domain.count() > 0:
                    print("✅ Тестовый домен отображается в результатах")
                    
            else:
                print("⚠️  DNS проверка не показала успешное подключение")
                # Получаем скриншот для отладки
                await page.screenshot(path="dns_test_mock_success.png")
            
        except Exception as e:
            print(f"❌ Ошибка при тестировании мок успешной проверки: {e}")
            await page.screenshot(path="dns_test_error.png")
            raise
        finally:
            await context.close()
    
    @pytest.mark.asyncio
    async def test_dns_check_with_mock_failure(self, browser: Browser):
        """Тест 3: Эмуляция неудачной DNS проверки"""
        page, context = await create_page_with_hosts(browser)
        
        try:
            # Перехватываем запросы к test.dns.uzicus.ru и возвращаем ошибку
            await context.route("**/test.dns.uzicus.ru/**", lambda route: route.abort("nameerror"))
            
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Ждем завершения автоматической проверки
            await asyncio.sleep(8)
            
            # Проверяем что показывается "НЕ подключен"
            error_indicator = page.locator("h3:has-text('❌ Не подключен')")
            
            if await error_indicator.count() > 0:
                print("✅ DNS проверка корректно показала отсутствие подключения")
                
                # Проверяем что есть инструкции
                instructions = page.locator("text=Как настроить Ninja DNS")
                if await instructions.count() > 0:
                    print("✅ Инструкции по настройке отображаются")
                    
            else:
                print("❌ DNS проверка не показала ожидаемый результат")
                await page.screenshot(path="dns_test_mock_failure.png")
                
                # Проверяем что не показывается успех
                success_indicator = page.locator("h3:has-text('✅ Подключен!')")
                if await success_indicator.count() > 0:
                    raise AssertionError("DNS проверка показала успех, хотя должна показать ошибку")
            
        except Exception as e:
            print(f"❌ Ошибка при тестировании мок неудачной проверки: {e}")
            raise
        finally:
            await context.close()
    
    @pytest.mark.asyncio
    async def test_manual_recheck_button(self, browser: Browser):
        """Тест 4: Проверка кнопки повторной проверки"""
        page, context = await create_page_with_hosts(browser)
        
        try:
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Ждем первой проверки
            await asyncio.sleep(5)
            
            # Нажимаем кнопку повторной проверки
            check_button = page.locator("button:has-text('Проверить подключение')")
            await check_button.click()
            
            # Проверяем что показывается индикатор загрузки
            loading_text = page.locator("text=Проверяем...")
            if await loading_text.count() > 0:
                print("✅ Индикатор загрузки отображается")
            
            # Ждем завершения
            await asyncio.sleep(8)
            
            # Проверяем что получили результат
            result_success = page.locator("h3:has-text('✅ Подключен!')")
            result_error = page.locator("h3:has-text('❌ Не подключен')")
            
            if await result_success.count() > 0 or await result_error.count() > 0:
                print("✅ Повторная проверка работает и возвращает результат")
            else:
                print("❌ Повторная проверка не вернула результат")
                await page.screenshot(path="manual_recheck_failed.png")
                raise AssertionError("Повторная проверка не работает")
            
        except Exception as e:
            print(f"❌ Ошибка при тестировании повторной проверки: {e}")
            raise
        finally:
            await context.close()
    
    @pytest.mark.asyncio
    async def test_console_output(self, browser: Browser):
        """Тест 5: Проверка console.log сообщений"""
        page, context = await create_page_with_hosts(browser)
        
        console_messages = []
        
        def handle_console(msg):
            console_messages.append(f"{msg.type}: {msg.text}")
        
        page.on("console", handle_console)
        
        try:
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Ждем выполнения проверки
            await asyncio.sleep(8)
            
            # Проверяем что есть логи о DNS проверке
            dns_logs = [msg for msg in console_messages if 'test.dns.uzicus.ru' in msg or 'DNS' in msg]
            
            if dns_logs:
                print("✅ JavaScript логирование работает:")
                for log in dns_logs[:3]:  # Показываем первые 3 лога
                    print(f"  {log}")
            else:
                print("⚠️  Нет логов о DNS проверке в консоли")
                print("Все сообщения консоли:")
                for msg in console_messages[:5]:
                    print(f"  {msg}")
            
        except Exception as e:
            print(f"❌ Ошибка при проверке console логов: {e}")
            raise
        finally:
            await context.close()


@pytest.mark.asyncio
async def test_full_integration():
    """Интеграционный тест всей системы"""
    print("🧪 Запуск полного интеграционного теста...")
    
    dns_runner = DNSTestRunner()
    
    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True, args=['--no-sandbox'])
            
            # Тест 1: Эмуляция Ninja DNS (test.dns.uzicus.ru резолвится)
            print("\n1️⃣ Тестируем с эмуляцией Ninja DNS...")
            hosts_file = await dns_runner.setup_hosts_for_baltic_dns()
            
            page, context = await create_page_with_hosts(browser, hosts_file)
            
            # Перехватываем запросы к test.dns.uzicus.ru чтобы эмулировать успешное резолвинг
            await context.route("**/test.dns.uzicus.ru/**", lambda route: route.fulfill(
                status=200, body="OK"
            ))
            
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            await asyncio.sleep(8)
            
            success_indicator = page.locator("h3:has-text('✅ Подключен!')")
            if await success_indicator.count() > 0:
                print("✅ С Ninja DNS показывается 'Подключен!'")
            else:
                print("❌ С Ninja DNS НЕ показывается 'Подключен!'")
            
            await context.close()
            
            # Тест 2: Эмуляция публичного DNS (test.dns.uzicus.ru НЕ резолвится)
            print("\n2️⃣ Тестируем с эмуляцией публичного DNS...")
            hosts_file2 = await dns_runner.setup_hosts_for_public_dns()
            
            page2, context2 = await create_page_with_hosts(browser, hosts_file2)
            
            # Блокируем запросы к test.dns.uzicus.ru чтобы эмулировать DNS failure
            await context2.route("**/test.dns.uzicus.ru/**", lambda route: route.abort("nameerror"))
            
            await page2.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            await asyncio.sleep(8)
            
            error_indicator = page2.locator("h3:has-text('❌ Не подключен')")
            if await error_indicator.count() > 0:
                print("✅ С публичным DNS показывается 'Не подключен!'")
            else:
                print("❌ С публичным DNS НЕ показывается 'Не подключен!'")
            
            await context2.close()
            await browser.close()
            
    finally:
        dns_runner.cleanup()


if __name__ == "__main__":
    print("🧪 Ninja DNS - Браузерные тесты с Playwright")
    print("=" * 50)
    
    # Запускаем интеграционный тест
    asyncio.run(test_full_integration())
    
    print("\n🧪 Запуск всех тестов через pytest...")
    # Запускаем все тесты
    pytest.main([__file__, "-v", "-s", "--tb=short"])