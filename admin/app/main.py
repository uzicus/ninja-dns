from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
import json
import asyncio
import docker
import os
import re
import socket
from typing import List, Dict, Any
import logging
from app.mobileconfig_generator import generate_universal_profile, generate_dot_profile, MobileConfigGenerator

# Читаем переменные окружения
HOST_DOMAIN = os.getenv('HOST_DOMAIN', 'dns.uzicus.ru')
SERVER_IP = os.getenv('SERVER_IP', '185.237.95.211')
TEST_SUBDOMAIN = os.getenv('TEST_SUBDOMAIN', 'test')
DEBUG = os.getenv('DEBUG', 'false').lower() == 'true'
LOG_LEVEL = os.getenv('LOG_LEVEL', 'info').upper()

# Настройка логирования
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Логируем конфигурацию при запуске
logger.info(f"Ninja DNS Admin starting with HOST_DOMAIN={HOST_DOMAIN}, SERVER_IP={SERVER_IP}")

# Формируем полное имя тестового домена
TEST_DOMAIN = f"{TEST_SUBDOMAIN}.{HOST_DOMAIN}"

def get_client_ip(request: Request) -> str:
    """Получить реальный IP клиента"""
    # Проверяем заголовки прокси
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip
    
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    
    # Fallback на прямое соединение
    return request.client.host if request.client else "unknown"

app = FastAPI(title="Ninja DNS Admin", description="DNS Domain Management Interface")

# Добавляем CORS middleware с ограничениями
app.add_middleware(
    CORSMiddleware,
    allow_origins=[f"https://{HOST_DOMAIN}"],  # Только наш домен
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["*"],
)

templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static"), name="static")

DOMAINS_FILE = "/data/domains.json"
SMARTDNS_CONFIG = "/data/smartdns/smartdns.conf"
SNIPROXY_CONFIG = "/data/sniproxy/nginx.conf"

class DomainValidator:
    """Класс для валидации доменов"""
    
    @staticmethod
    def is_valid_domain_format(domain: str) -> bool:
        """Проверка формата домена"""
        if not domain or len(domain) > 253:
            return False
            
        # Регулярное выражение для валидного домена
        domain_pattern = re.compile(
            r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
        )
        
        return bool(domain_pattern.match(domain))
    
    @staticmethod
    def can_resolve_domain(domain: str) -> tuple[bool, str]:
        """Проверка что домен резолвится"""
        try:
            # socket уже импортирован выше
            
            # Попробуем резолвить домен через стандартную библиотеку Python
            try:
                addresses = socket.getaddrinfo(domain, None, socket.AF_INET)
                if addresses:
                    # Извлекаем уникальные IP адреса
                    ips = list(set([addr[4][0] for addr in addresses]))
                    return True, f"Резолвится в: {', '.join(ips[:3])}"
                else:
                    return False, "Домен не резолвится"
            except socket.gaierror as e:
                # Попробуем альтернативный метод через gethostbyname
                try:
                    ip = socket.gethostbyname(domain)
                    return True, f"Резолвится в: {ip}"
                except socket.gaierror:
                    return False, f"Домен не резолвится: {str(e)}"
            
        except Exception as e:
            return False, f"Ошибка проверки DNS: {str(e)}"
    
    @staticmethod
    def check_https_availability(domain: str) -> tuple[bool, str]:
        """Проверка доступности HTTPS"""
        try:
            import requests
            
            response = requests.get(
                f"https://{domain}",
                timeout=5,
                verify=True,
                allow_redirects=True
            )
            
            if response.status_code < 400:
                return True, f"HTTPS доступен (код: {response.status_code})"
            else:
                return False, f"HTTPS вернул код: {response.status_code}"
                
        except requests.exceptions.SSLError as e:
            return False, f"SSL ошибка: {str(e)[:100]}"
        except requests.exceptions.ConnectionError:
            return False, "Не удается подключиться к домену"
        except requests.exceptions.Timeout:
            return False, "Таймаут подключения"
        except Exception as e:
            return False, f"Ошибка HTTPS проверки: {str(e)}"
    
    @classmethod
    def validate_domain(cls, domain: str) -> Dict[str, Any]:
        """Полная валидация домена"""
        domain = domain.lower().strip()
        
        result = {
            "domain": domain,
            "valid": False,
            "errors": [],
            "warnings": [],
            "info": []
        }
        
        # Проверка формата
        if not cls.is_valid_domain_format(domain):
            result["errors"].append("Неверный формат домена")
            return result
        
        # Проверка зарезервированных доменов
        reserved_domains = [
            "localhost", "example.com", "example.org", "example.net",
            "test.com", "invalid", "local"
        ]
        
        if domain in reserved_domains:
            result["warnings"].append("Это зарезервированный/тестовый домен")
        
        # Проверка DNS резолвинга
        can_resolve, dns_message = cls.can_resolve_domain(domain)
        if not can_resolve:
            result["errors"].append(dns_message)
            return result
        else:
            result["info"].append(dns_message)
        
        # Проверка HTTPS доступности (не критично)
        https_ok, https_message = cls.check_https_availability(domain)
        if https_ok:
            result["info"].append(https_message)
        else:
            result["warnings"].append(https_message)
        
        result["valid"] = True
        return result

class DomainManager:
    def __init__(self):
        self.docker_client = docker.from_env()
        
    def load_domains(self) -> Dict[str, Any]:
        try:
            if os.path.exists(DOMAINS_FILE):
                with open(DOMAINS_FILE, 'r', encoding='utf-8') as f:
                    return json.load(f)
            return {"domains": [], "server_ip": SERVER_IP}
        except Exception as e:
            logger.error(f"Error loading domains: {e}")
            return {"domains": [], "server_ip": SERVER_IP}
    
    def save_domains(self, data: Dict[str, Any]):
        try:
            with open(DOMAINS_FILE, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            logger.info("Domains saved successfully")
        except Exception as e:
            logger.error(f"Error saving domains: {e}")
            raise HTTPException(status_code=500, detail=f"Error saving domains: {e}")
    
    def generate_smartdns_config(self, domains_data: Dict[str, Any]):
        config_lines = []
        
        # Basic SmartDNS configuration
        basic_config = """bind :53
bind-tcp :53

server-tls 8.8.8.8:853 -group upstream
server-tls 1.1.1.1:853 -group upstream
server-https https://dns.google/dns-query -group upstream
server-https https://cloudflare-dns.com/dns-query -group upstream

server 8.8.8.8:53 -group fallback
server 1.1.1.1:53 -group fallback

speed-check-mode ping,tcp:80,tcp:443
response-mode fastest-ip
cache-size 4096
cache-persist yes
cache-file /var/cache/smartdns.cache

rr-ttl-min 300
rr-ttl-max 86400
rr-ttl 600

log-level info
log-size 128K
log-num 2
log-file /var/log/smartdns.log

prefetch-domain yes
serve-expired yes
serve-expired-ttl 86400

"""
        config_lines.append(basic_config)
        
        # Add domain redirections
        for domain in domains_data.get("domains", []):
            if domain.get("enabled", True):
                config_lines.append(f"address /{domain['name']}/{domains_data['server_ip']}")
        
        return "\n".join(config_lines)
    
    def generate_sniproxy_config(self, domains_data: Dict[str, Any]):
        config_lines = []
        
        # Basic nginx configuration header with resolver
        config_lines.append("""error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

stream {
    # DNS resolver configuration - using public DNS servers
    resolver 8.8.8.8 1.1.1.1 valid=300s ipv6=off;
    resolver_timeout 5s;
    
    # Special upstream for admin panel
    upstream dnsuzicus {
        server traefik:8443;
    }
    
    # Map configuration for dynamic proxy pass
    map $ssl_preread_server_name $backend_name {""")
        
        # Generate map entries for domains
        for domain in domains_data.get("domains", []):
            if domain.get("enabled", True):
                domain_name = domain["name"]
                # Map domain to itself with port 443 for direct proxy
                config_lines.append(f"        ~*{domain_name} {domain_name}:443;")
        
        # Special handling for admin panel
        config_lines.append(f"        ~*{HOST_DOMAIN} dnsuzicus;")
        config_lines.append("        default $ssl_preread_server_name:443;")
        config_lines.append("    }")
        
        # Server block with dynamic proxy
        config_lines.append("""
    server {
        listen 443;
        ssl_preread on;
        proxy_pass $backend_name;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_buffer_size 16k;
        
        # Enable TCP keepalive for better connection handling
        proxy_socket_keepalive on;
        
        # Log errors for debugging
        error_log /var/log/nginx/sniproxy.log;
        
        # Access log disabled for performance
        access_log off;
    }
}""")
        
        return "\n".join(config_lines)
    
    def update_configs(self):
        try:
            domains_data = self.load_domains()
            
            # Generate and save SmartDNS config
            smartdns_config = self.generate_smartdns_config(domains_data)
            with open(SMARTDNS_CONFIG, 'w', encoding='utf-8') as f:
                f.write(smartdns_config)
            
            # Generate and save sniproxy config
            sniproxy_config = self.generate_sniproxy_config(domains_data)
            with open(SNIPROXY_CONFIG, 'w', encoding='utf-8') as f:
                f.write(sniproxy_config)
            
            logger.info("Configs updated successfully")
        except Exception as e:
            logger.error(f"Error updating configs: {e}")
            raise HTTPException(status_code=500, detail=f"Error updating configs: {e}")
    
    def restart_services(self):
        try:
            # Restart SmartDNS
            smartdns_container = self.docker_client.containers.get("smartdns")
            smartdns_container.restart()
            
            # Graceful reload nginx config without full restart
            try:
                sniproxy_container = self.docker_client.containers.get("sniproxy")
                # Test nginx config first
                test_result = sniproxy_container.exec_run("nginx -t")
                if test_result.exit_code == 0:
                    # Config is valid, reload gracefully
                    reload_result = sniproxy_container.exec_run("nginx -s reload")
                    if reload_result.exit_code != 0:
                        logger.warning("Graceful reload failed, doing full restart")
                        sniproxy_container.restart()
                else:
                    logger.warning("Nginx config test failed, doing full restart")
                    sniproxy_container.restart()
            except Exception as e:
                logger.error(f"Error with graceful reload, doing full restart: {e}")
                sniproxy_container = self.docker_client.containers.get("sniproxy")
                sniproxy_container.restart()
            
            logger.info("Services restarted successfully")
        except Exception as e:
            logger.error(f"Error restarting services: {e}")
            raise HTTPException(status_code=500, detail=f"Error restarting services: {e}")
    
    def get_service_status(self) -> Dict[str, str]:
        status = {}
        try:
            for service in ["smartdns", "sniproxy", "traefik"]:
                container = self.docker_client.containers.get(service)
                status[service] = container.status
        except Exception as e:
            logger.error(f"Error getting service status: {e}")
            status = {"error": str(e)}
        return status

domain_manager = DomainManager()

# WebSocket connections for real-time updates
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                pass

manager = ConnectionManager()

@app.get("/", response_class=HTMLResponse)
async def root(request: Request):
    return templates.TemplateResponse("dns_check.html", {"request": request})

@app.get("/pixel.png")
async def pixel_image(request: Request):
    """Отдаем картинку только для тестового домена"""
    host = request.headers.get("host", "").lower()
    
    # Проверяем что запрос идет с тестового домена
    if host == TEST_DOMAIN or host.startswith(f"{TEST_DOMAIN}:"):
        # Отдаем картинку
        return FileResponse(
            path="/app/static/pixel.png",
            media_type="image/png",
            headers={
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Pragma": "no-cache",
                "Expires": "0"
            }
        )
    else:
        # Для других доменов возвращаем 404
        raise HTTPException(status_code=404, detail="Not found")

@app.websocket("/dns-check")
async def dns_check_websocket(websocket: WebSocket):
    """WebSocket endpoint для проверки DNS только для тестового домена"""
    # Получаем Host заголовок из WebSocket запроса
    host = websocket.headers.get("host", "").lower()
    
    # Проверяем что запрос идет с тестового домена
    if host == TEST_DOMAIN or host.startswith(f"{TEST_DOMAIN}:"):
        await websocket.accept()
        try:
            # Отправляем подтверждение что DNS работает
            await websocket.send_json({
                "status": "success",
                "message": "DNS check passed",
                "server_ip": SERVER_IP,
                "domain": host
            })
            # Закрываем соединение
            await websocket.close()
        except Exception as e:
            await websocket.close()
    else:
        # Для других доменов отклоняем соединение
        await websocket.close(code=1003, reason="Forbidden domain")

@app.get("/admin", response_class=HTMLResponse)
async def admin(request: Request):
    return templates.TemplateResponse("admin.html", {"request": request})

@app.get("/api/domains")
async def get_domains():
    return domain_manager.load_domains()

@app.post("/api/domains/validate")
async def validate_domain(domain_data: dict):
    """Валидация домена без добавления"""
    domain_name = domain_data.get("name", "").strip()
    
    if not domain_name:
        raise HTTPException(status_code=400, detail="Domain name is required")
    
    # Валидируем домен
    validation_result = DomainValidator.validate_domain(domain_name)
    
    return validation_result

@app.post("/api/domains")
async def add_domain(domain_data: dict, request: Request):
    client_ip = get_client_ip(request)
    try:
        domain_name = domain_data.get("name", "").strip()
        logger.info(f"Attempt to add domain '{domain_name}' from IP: {client_ip}")
        
        if not domain_name:
            raise HTTPException(status_code=400, detail="Domain name is required")
        
        # Валидируем домен перед добавлением
        validation_result = DomainValidator.validate_domain(domain_name)
        
        if not validation_result["valid"]:
            error_message = "; ".join(validation_result["errors"])
            raise HTTPException(status_code=400, detail=f"Domain validation failed: {error_message}")
        
        domains_data = domain_manager.load_domains()
        
        # Check if domain already exists
        for existing_domain in domains_data["domains"]:
            if existing_domain["name"] == domain_name:
                raise HTTPException(status_code=400, detail="Domain already exists")
        
        # Add new domain
        new_domain = {
            "name": domain_name,
            "category": domain_data.get("category", "misc"),
            "enabled": domain_data.get("enabled", True)
        }
        
        domains_data["domains"].append(new_domain)
        domain_manager.save_domains(domains_data)
        domain_manager.update_configs()
        domain_manager.restart_services()
        
        # Broadcast update to WebSocket clients
        await manager.broadcast({"type": "domain_added", "domain": new_domain})
        
        logger.info(f"Successfully added domain '{domain_name}' from IP: {client_ip}")
        return {
            "success": True, 
            "message": "Domain added successfully",
            "validation": validation_result
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error adding domain '{domain_name}' from IP {client_ip}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/domains/{domain_name}")
async def remove_domain(domain_name: str, request: Request):
    client_ip = get_client_ip(request)
    logger.info(f"Attempt to remove domain '{domain_name}' from IP: {client_ip}")
    try:
        domains_data = domain_manager.load_domains()
        
        # Find and remove domain
        original_count = len(domains_data["domains"])
        domains_data["domains"] = [d for d in domains_data["domains"] if d["name"] != domain_name]
        
        if len(domains_data["domains"]) == original_count:
            raise HTTPException(status_code=404, detail="Domain not found")
        
        domain_manager.save_domains(domains_data)
        domain_manager.update_configs()
        domain_manager.restart_services()
        
        # Broadcast update to WebSocket clients
        await manager.broadcast({"type": "domain_removed", "domain": domain_name})
        
        logger.info(f"Successfully removed domain '{domain_name}' from IP: {client_ip}")
        return {"success": True, "message": "Domain removed successfully"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error removing domain '{domain_name}' from IP {client_ip}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/status")
async def get_status():
    return domain_manager.get_service_status()



@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            # Send periodic status updates
            status = domain_manager.get_service_status()
            await websocket.send_json({"type": "status_update", "status": status})
            await asyncio.sleep(30)  # Update every 30 seconds
    except WebSocketDisconnect:
        manager.disconnect(websocket)

@app.get("/download", response_class=HTMLResponse)
async def download_page(request: Request):
    """Страница для скачивания mobileconfig профиля"""
    client_ip = get_client_ip(request)
    logger.info(f"Download page accessed from IP: {client_ip}")
    
    # Получаем информацию о профиле для отображения
    generator = MobileConfigGenerator(HOST_DOMAIN, SERVER_IP)
    profile_info = generator.get_profile_info()
    
    return templates.TemplateResponse("download.html", {
        "request": request,
        "profile_info": profile_info,
        "host_domain": HOST_DOMAIN,
        "server_ip": SERVER_IP
    })

@app.get("/api/profile-info")
async def get_profile_info():
    """API для получения информации о DNS профиле"""
    generator = MobileConfigGenerator(HOST_DOMAIN, SERVER_IP)
    return generator.get_profile_info()

@app.get("/download/mobileconfig")
async def download_mobileconfig(request: Request):
    """Скачивание динамически сгенерированного mobileconfig для iOS/универсального"""
    client_ip = get_client_ip(request)
    logger.info(f"Dynamic mobileconfig download requested from IP: {client_ip}")
    
    try:
        # Генерируем профиль динамически
        profile_content = generate_universal_profile(
            host_domain=HOST_DOMAIN,
            server_ip=SERVER_IP,
            profile_name="Ninja DNS"
        )
        
        # Создаем Response с сгенерированным содержимым
        from fastapi.responses import Response
        return Response(
            content=profile_content,
            media_type="application/x-apple-aspen-config",
            headers={
                "Content-Disposition": f"attachment; filename=baltic-dns.mobileconfig"
            }
        )
        
    except Exception as e:
        logger.error(f"Error generating mobileconfig for IP {client_ip}: {e}")
        raise HTTPException(status_code=500, detail="Error generating configuration file")

@app.get("/download/mobileconfig-macos")
async def download_mobileconfig_macos(request: Request):
    """Скачивание файла mobileconfig специально для macOS"""
    client_ip = get_client_ip(request)
    logger.info(f"macOS mobileconfig download requested from IP: {client_ip}")
    
    try:
        # Генерируем профиль динамически (тот же универсальный)
        profile_content = generate_universal_profile(
            host_domain=HOST_DOMAIN,
            server_ip=SERVER_IP,
            profile_name="Ninja DNS macOS"
        )
        
        # Создаем Response с сгенерированным содержимым
        from fastapi.responses import Response
        return Response(
            content=profile_content,
            media_type="application/x-apple-aspen-config",
            headers={
                "Content-Disposition": f"attachment; filename=baltic-dns-macos.mobileconfig"
            }
        )
        
    except Exception as e:
        logger.error(f"Error generating macOS mobileconfig for IP {client_ip}: {e}")
        raise HTTPException(status_code=500, detail="Error generating configuration file")

@app.get("/download/mobileconfig-dot")
async def download_mobileconfig_dot(request: Request):
    """Скачивание файла mobileconfig с поддержкой DNS-over-TLS"""
    client_ip = get_client_ip(request)
    logger.info(f"DoT mobileconfig download requested from IP: {client_ip}")
    
    try:
        # Генерируем DoT профиль
        profile_content = generate_dot_profile(
            host_domain=HOST_DOMAIN,
            server_ip=SERVER_IP,
            profile_name="Ninja DNS DoT"
        )
        
        # Создаем Response с сгенерированным содержимым
        from fastapi.responses import Response
        return Response(
            content=profile_content,
            media_type="application/x-apple-aspen-config",
            headers={
                "Content-Disposition": f"attachment; filename=baltic-dns-dot.mobileconfig"
            }
        )
        
    except Exception as e:
        logger.error(f"Error generating DoT mobileconfig for IP {client_ip}: {e}")
        raise HTTPException(status_code=500, detail="Error generating configuration file")

@app.get("/download/uzicus")
async def download_uzicus_mobileconfig(request: Request):
    """Скачивание универсального файла mobileconfig для всех устройств Apple (главный эндпоинт)"""
    client_ip = get_client_ip(request)
    logger.info(f"Universal mobileconfig download requested from IP: {client_ip}")
    
    try:
        # Генерируем универсальный профиль (как uzicus.mobileconfig)
        profile_content = generate_universal_profile(
            host_domain=HOST_DOMAIN,
            server_ip=SERVER_IP,
            profile_name="Ninja DNS"
        )
        
        # Создаем Response с сгенерированным содержимым
        from fastapi.responses import Response
        return Response(
            content=profile_content,
            media_type="application/x-apple-aspen-config",
            headers={
                "Content-Disposition": f"attachment; filename=baltic-dns.mobileconfig"
            }
        )
        
    except Exception as e:
        logger.error(f"Error generating universal mobileconfig for IP {client_ip}: {e}")
        raise HTTPException(status_code=500, detail="Error generating configuration file")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)