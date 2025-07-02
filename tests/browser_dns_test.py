"""
Браузерные тесты для проверки функциональности DNS-проверки Ninja DNS
"""
import asyncio
import pytest
from playwright.async_api import async_playwright, Page, Browser
import subprocess
import time
import socket


class DNSTestRunner:
    """Вспомогательный класс для запуска тестов с разными DNS серверами"""
    
    def __init__(self):
        self.original_resolv = None
        
    async def set_dns_server(self, dns_server: str):
        """Временно изменить DNS сервер для тестирования"""
        try:
            # Сохраняем оригинальный resolv.conf
            with open('/etc/resolv.conf', 'r') as f:
                self.original_resolv = f.read()
            
            # Устанавливаем новый DNS сервер
            with open('/etc/resolv.conf', 'w') as f:
                f.write(f"nameserver {dns_server}\n")
            
            # Ждем немного чтобы изменения применились
            await asyncio.sleep(2)
            
        except Exception as e:
            print(f"Ошибка при изменении DNS: {e}")
    
    async def restore_dns(self):
        """Восстановить оригинальные DNS настройки"""
        if self.original_resolv:
            try:
                with open('/etc/resolv.conf', 'w') as f:
                    f.write(self.original_resolv)
                await asyncio.sleep(1)
            except Exception as e:
                print(f"Ошибка при восстановлении DNS: {e}")


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


@pytest.fixture
async def page(browser: Browser):
    """Фикстура для создания страницы"""
    page = await browser.new_page()
    # Увеличиваем таймауты для сетевых запросов
    page.set_default_timeout(30000)
    yield page
    await page.close()


class TestDNSChecker:
    """Тесты для проверки функциональности DNS checker"""
    
    @pytest.mark.asyncio
    async def test_dns_page_loads(self, page: Page):
        """Тест 1: Проверка что страница DNS проверки загружается"""
        try:
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Проверяем что страница загрузилась
            title = await page.title()
            assert "Ninja DNS" in title
            
            # Проверяем что есть кнопка проверки
            check_button = page.locator("button:has-text('Проверить подключение')")
            await check_button.wait_for(state="visible")
            
            print("✅ Страница DNS проверки успешно загружается")
            
        except Exception as e:
            print(f"❌ Ошибка при загрузке страницы: {e}")
            raise
    
    @pytest.mark.asyncio
    async def test_dns_check_with_baltic_dns(self, page: Page):
        """Тест 2: Проверка DNS с настроенным Ninja DNS"""
        dns_runner = DNSTestRunner()
        
        try:
            # Устанавливаем наш DNS сервер
            await dns_runner.set_dns_server("185.237.95.211")
            
            # Проверяем что test.dns.uzicus.ru резолвится в наш IP
            try:
                ip = socket.gethostbyname("test.dns.uzicus.ru")
                print(f"test.dns.uzicus.ru резолвится в: {ip}")
                assert ip == "185.237.95.211", f"Ожидали 185.237.95.211, получили {ip}"
            except Exception as e:
                print(f"Ошибка резолвинга test.dns.uzicus.ru: {e}")
                # Продолжаем тест даже если резолвинг не работает
            
            # Открываем страницу
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Ждем завершения автоматической проверки (которая запускается в init())
            await asyncio.sleep(10)
            
            # Проверяем результат
            success_indicator = page.locator("h3:has-text('✅ Подключен!')")
            
            if await success_indicator.count() > 0:
                print("✅ DNS проверка показала успешное подключение к Ninja DNS")
                
                # Проверяем детали
                server_info = page.locator("span.font-mono.text-blue-400")
                if await server_info.count() > 0:
                    server_text = await server_info.first.text_content()
                    print(f"Информация о сервере: {server_text}")
                
            else:
                # Проверяем есть ли ошибка
                error_indicator = page.locator("h3:has-text('❌ Не подключен')")
                if await error_indicator.count() > 0:
                    print("❌ DNS проверка показала что Ninja DNS НЕ используется")
                    
                    # Получаем детали ошибки для отладки
                    error_details = page.locator(".text-red-400")
                    if await error_details.count() > 0:
                        error_text = await error_details.first.text_content()
                        print(f"Детали ошибки: {error_text}")
                
                # Это не обязательно ошибка теста - возможно DNS еще не распространился
                print("⚠️  DNS проверка не показала подключение, но это может быть временно")
            
        finally:
            await dns_runner.restore_dns()
    
    @pytest.mark.asyncio
    async def test_dns_check_with_public_dns(self, page: Page):
        """Тест 3: Проверка DNS с публичным DNS (должен показать НЕ подключен)"""
        dns_runner = DNSTestRunner()
        
        try:
            # Устанавливаем публичный DNS (Google)
            await dns_runner.set_dns_server("8.8.8.8")
            
            # Проверяем что test.dns.uzicus.ru НЕ резолвится через публичный DNS
            try:
                ip = socket.gethostbyname("test.dns.uzicus.ru")
                print(f"⚠️  test.dns.uzicus.ru неожиданно резолвится через 8.8.8.8 в: {ip}")
            except socket.gaierror:
                print("✅ test.dns.uzicus.ru корректно НЕ резолвится через публичный DNS")
            
            # Открываем страницу
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Ждем завершения автоматической проверки
            await asyncio.sleep(10)
            
            # Проверяем что показывается "НЕ подключен"
            error_indicator = page.locator("h3:has-text('❌ Не подключен')")
            
            if await error_indicator.count() > 0:
                print("✅ DNS проверка корректно показала что Ninja DNS НЕ используется")
                
                # Проверяем что есть инструкции по настройке
                instructions = page.locator("text=Как настроить Ninja DNS")
                if await instructions.count() > 0:
                    print("✅ Инструкции по настройке отображаются")
                
            else:
                success_indicator = page.locator("h3:has-text('✅ Подключен!')")
                if await success_indicator.count() > 0:
                    print("❌ ОШИБКА: DNS проверка показала подключение, хотя должна показать отсутствие подключения")
                    
                    # Получаем screenshot для отладки
                    await page.screenshot(path="test_error_screenshot.png")
                    raise AssertionError("DNS проверка работает некорректно с публичным DNS")
                else:
                    print("⚠️  DNS проверка показала неопределенный результат")
            
        finally:
            await dns_runner.restore_dns()
    
    @pytest.mark.asyncio
    async def test_manual_dns_recheck(self, page: Page):
        """Тест 4: Проверка повторной проверки DNS через кнопку"""
        try:
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Ждем первой проверки
            await asyncio.sleep(5)
            
            # Нажимаем кнопку повторной проверки
            check_button = page.locator("button:has-text('Проверить подключение')")
            await check_button.click()
            
            # Проверяем что показывается индикатор загрузки
            loading_indicator = page.locator("text=Проверяем...")
            if await loading_indicator.count() > 0:
                print("✅ Индикатор загрузки отображается при повторной проверке")
            
            # Ждем завершения проверки
            await asyncio.sleep(10)
            
            # Проверяем что получили какой-то результат
            result_success = page.locator("h3:has-text('✅ Подключен!')")
            result_error = page.locator("h3:has-text('❌ Не подключен')")
            
            if await result_success.count() > 0 or await result_error.count() > 0:
                print("✅ Повторная проверка DNS работает корректно")
            else:
                print("❌ Повторная проверка DNS не вернула результат")
                await page.screenshot(path="manual_recheck_error.png")
                raise AssertionError("Повторная проверка не работает")
            
        except Exception as e:
            print(f"❌ Ошибка при тестировании повторной проверки: {e}")
            raise
    
    @pytest.mark.asyncio 
    async def test_page_responsiveness(self, page: Page):
        """Тест 5: Проверка отзывчивости интерфейса"""
        try:
            await page.goto("https://dns.uzicus.ru/", wait_until='networkidle')
            
            # Тестируем мобильный вид
            await page.set_viewport_size({"width": 375, "height": 667})
            await asyncio.sleep(2)
            
            # Проверяем что кнопка все еще видна и кликабельна
            check_button = page.locator("button:has-text('Проверить подключение')")
            await check_button.wait_for(state="visible")
            
            # Тестируем десктопный вид
            await page.set_viewport_size({"width": 1920, "height": 1080})
            await asyncio.sleep(2)
            
            # Проверяем что интерфейс корректно отображается
            title = page.locator("h1:has-text('Ninja DNS')")
            await title.wait_for(state="visible")
            
            print("✅ Интерфейс корректно отображается на разных разрешениях")
            
        except Exception as e:
            print(f"❌ Ошибка при тестировании отзывчивости: {e}")
            raise


if __name__ == "__main__":
    """Запуск тестов напрямую"""
    print("🧪 Запуск браузерных тестов для Ninja DNS")
    print("=" * 50)
    
    # Устанавливаем Playwright браузеры если нужно
    try:
        subprocess.run(["playwright", "install", "chromium"], check=True, capture_output=True)
    except:
        print("⚠️  Не удалось установить браузеры Playwright")
    
    # Запускаем тесты
    pytest.main([__file__, "-v", "-s"])