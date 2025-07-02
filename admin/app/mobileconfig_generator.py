"""
Mobile Configuration Generator for Baltic DNS
Generates iOS/macOS configuration profiles dynamically based on environment variables
"""

import uuid
import xml.etree.ElementTree as ET
from xml.dom import minidom
from typing import Dict, Any


class MobileConfigGenerator:
    """Генератор mobileconfig профилей для устройств Apple"""
    
    def __init__(self, host_domain: str, server_ip: str):
        self.host_domain = host_domain
        self.server_ip = server_ip
        
    def generate_doh_profile(self, profile_name: str = "Baltic DNS") -> str:
        """
        Генерирует mobileconfig профиль для DNS-over-HTTPS
        
        Args:
            profile_name: Название профиля
            
        Returns:
            XML строка с конфигурацией
        """
        # Создаем корневой элемент
        root = ET.Element("plist", version="1.0")
        
        # Создаем основной dict
        main_dict = ET.SubElement(root, "dict")
        
        # PayloadContent
        self._add_key_value(main_dict, "PayloadContent", None)
        payload_content_array = ET.SubElement(main_dict, "array")
        
        # DNS Settings Dict
        dns_dict = ET.SubElement(payload_content_array, "dict")
        
        # DNSSettings
        self._add_key_value(dns_dict, "DNSSettings", None)
        dns_settings_dict = ET.SubElement(dns_dict, "dict")
        
        self._add_key_value(dns_settings_dict, "DNSProtocol", "HTTPS")
        self._add_key_value(dns_settings_dict, "ServerURL", f"https://{self.host_domain}/dns-query")
        self._add_key_value(dns_settings_dict, "ServerName", self.host_domain)
        
        # Payload info for DNS settings
        self._add_key_value(dns_dict, "PayloadDisplayName", f"{profile_name} - DoH")
        self._add_key_value(dns_dict, "PayloadIdentifier", f"com.apple.dnsSettings.managed.{self._generate_safe_identifier()}-doh")
        self._add_key_value(dns_dict, "PayloadType", "com.apple.dnsSettings.managed")
        self._add_key_value(dns_dict, "PayloadUUID", str(uuid.uuid4()).upper())
        self._add_key_value(dns_dict, "PayloadVersion", 1)
        
        # Main payload info
        self._add_key_value(main_dict, "PayloadDescription", f"DNS профиль {profile_name} с поддержкой DNS-over-HTTPS для безопасного интернета")
        self._add_key_value(main_dict, "PayloadDisplayName", profile_name)
        self._add_key_value(main_dict, "PayloadIdentifier", f"com.{self._generate_safe_identifier()}.dns")
        self._add_key_value(main_dict, "PayloadOrganization", profile_name)
        self._add_key_value(main_dict, "PayloadRemovalDisallowed", False)
        self._add_key_value(main_dict, "PayloadType", "Configuration")
        self._add_key_value(main_dict, "PayloadUUID", str(uuid.uuid4()).upper())
        self._add_key_value(main_dict, "PayloadVersion", 1)
        
        return self._prettify_xml(root)
    
    def generate_dot_profile(self, profile_name: str = "Baltic DNS") -> str:
        """
        Генерирует mobileconfig профиль для DNS-over-TLS
        
        Args:
            profile_name: Название профиля
            
        Returns:
            XML строка с конфигурацией
        """
        # Создаем корневой элемент
        root = ET.Element("plist", version="1.0")
        
        # Создаем основной dict
        main_dict = ET.SubElement(root, "dict")
        
        # PayloadContent
        self._add_key_value(main_dict, "PayloadContent", None)
        payload_content_array = ET.SubElement(main_dict, "array")
        
        # DNS Settings Dict
        dns_dict = ET.SubElement(payload_content_array, "dict")
        
        # DNSSettings
        self._add_key_value(dns_dict, "DNSSettings", None)
        dns_settings_dict = ET.SubElement(dns_dict, "dict")
        
        self._add_key_value(dns_settings_dict, "DNSProtocol", "TLS")
        self._add_key_value(dns_settings_dict, "ServerName", self.host_domain)
        
        # ServerAddresses array
        self._add_key_value(dns_settings_dict, "ServerAddresses", None)
        server_addresses_array = ET.SubElement(dns_settings_dict, "array")
        server_string = ET.SubElement(server_addresses_array, "string")
        server_string.text = self.server_ip
        
        # Payload info for DNS settings
        self._add_key_value(dns_dict, "PayloadDisplayName", f"{profile_name} - DoT")
        self._add_key_value(dns_dict, "PayloadIdentifier", f"com.apple.dnsSettings.managed.{self._generate_safe_identifier()}-dot")
        self._add_key_value(dns_dict, "PayloadType", "com.apple.dnsSettings.managed")
        self._add_key_value(dns_dict, "PayloadUUID", str(uuid.uuid4()).upper())
        self._add_key_value(dns_dict, "PayloadVersion", 1)
        
        # Main payload info
        self._add_key_value(main_dict, "PayloadDescription", f"DNS профиль {profile_name} с поддержкой DNS-over-TLS для защищенного интернета")
        self._add_key_value(main_dict, "PayloadDisplayName", f"{profile_name} DoT")
        self._add_key_value(main_dict, "PayloadIdentifier", f"com.{self._generate_safe_identifier()}.dns.dot")
        self._add_key_value(main_dict, "PayloadOrganization", profile_name)
        self._add_key_value(main_dict, "PayloadRemovalDisallowed", False)
        self._add_key_value(main_dict, "PayloadType", "Configuration")
        self._add_key_value(main_dict, "PayloadUUID", str(uuid.uuid4()).upper())
        self._add_key_value(main_dict, "PayloadVersion", 1)
        
        return self._prettify_xml(root)
    
    def _add_key_value(self, parent: ET.Element, key: str, value: Any) -> None:
        """Добавляет пару ключ-значение в XML"""
        key_elem = ET.SubElement(parent, "key")
        key_elem.text = key
        
        if value is None:
            return
        elif isinstance(value, bool):
            ET.SubElement(parent, "true" if value else "false")
        elif isinstance(value, int):
            integer_elem = ET.SubElement(parent, "integer")
            integer_elem.text = str(value)
        else:
            string_elem = ET.SubElement(parent, "string")
            string_elem.text = str(value)
    
    def _generate_safe_identifier(self) -> str:
        """Генерирует безопасный идентификатор из доменного имени"""
        # Убираем недопустимые символы и заменяем точки на тире
        safe_name = self.host_domain.replace(".", "-").replace("_", "-")
        # Убираем недопустимые символы
        safe_name = "".join(c for c in safe_name if c.isalnum() or c == "-")
        return safe_name.lower()
    
    def _prettify_xml(self, root: ET.Element) -> str:
        """Форматирует XML для читаемости"""
        # Добавляем DOCTYPE
        xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>\n'
        doctype = '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        
        # Форматируем XML
        rough_string = ET.tostring(root, encoding='unicode')
        reparsed = minidom.parseString(rough_string)
        pretty_xml = reparsed.toprettyxml(indent="\t")[23:]  # Убираем первую строку с XML declaration
        
        return xml_declaration + doctype + pretty_xml
    
    def get_profile_info(self) -> Dict[str, str]:
        """Возвращает информацию о профиле для отображения в интерфейсе"""
        return {
            "doh_url": f"https://{self.host_domain}/dns-query",
            "dot_server": f"{self.host_domain}:853",
            "dns_server": self.server_ip,
            "domain": self.host_domain
        }


def generate_universal_profile(host_domain: str, server_ip: str, profile_name: str = "Baltic DNS") -> str:
    """
    Генерирует универсальный профиль с поддержкой DoH (основной рабочий вариант)
    
    Args:
        host_domain: Доменное имя DNS сервера
        server_ip: IP адрес сервера  
        profile_name: Название профиля
        
    Returns:
        XML строка с mobileconfig профилем
    """
    generator = MobileConfigGenerator(host_domain, server_ip)
    return generator.generate_doh_profile(profile_name)


def generate_dot_profile(host_domain: str, server_ip: str, profile_name: str = "Baltic DNS") -> str:
    """
    Генерирует профиль с поддержкой DoT
    
    Args:
        host_domain: Доменное имя DNS сервера
        server_ip: IP адрес сервера
        profile_name: Название профиля
        
    Returns:
        XML строка с mobileconfig профилем
    """
    generator = MobileConfigGenerator(host_domain, server_ip)
    return generator.generate_dot_profile(profile_name)