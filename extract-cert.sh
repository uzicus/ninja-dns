#!/bin/bash

# Скрипт для извлечения сертификата из acme.json
ACME_FILE="/letsencrypt/acme.json"
CERT_DIR="/etc/smartdns/certs"

if [ ! -f "$ACME_FILE" ]; then
    echo "Файл $ACME_FILE не найден"
    exit 1
fi

# Извлекаем сертификат для dns.uzicus.ru
python3 -c "
import json
import base64

with open('$ACME_FILE', 'r') as f:
    data = json.load(f)

for resolver in data.get('letsencrypt', {}).get('Certificates', []):
    if 'dns.uzicus.ru' in resolver.get('domain', {}).get('main', ''):
        cert = base64.b64decode(resolver['certificate']).decode('utf-8')
        key = base64.b64decode(resolver['key']).decode('utf-8')
        
        with open('$CERT_DIR/le-server.crt', 'w') as cert_file:
            cert_file.write(cert)
        
        with open('$CERT_DIR/le-server.key', 'w') as key_file:
            key_file.write(key)
        
        print('Сертификат извлечен успешно')
        exit(0)

print('Сертификат для dns.uzicus.ru не найден')
"