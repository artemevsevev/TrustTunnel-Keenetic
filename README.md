# Установка TrustTunnel с автозапуском на Keenetic

## Предварительные требования

Перед установкой на роутер необходимо:
1. Установить Entware на роутер: [Инструкция по установке Entware](https://help.keenetic.com/hc/ru/articles/360021214160-%D0%A3%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0-%D1%81%D0%B8%D1%81%D1%82%D0%B5%D0%BC%D1%8B-%D0%BF%D0%B0%D0%BA%D0%B5%D1%82%D0%BE%D0%B2-%D1%80%D0%B5%D0%BF%D0%BE%D0%B7%D0%B8%D1%82%D0%BE%D1%80%D0%B8%D1%8F-Entware-%D0%BD%D0%B0-USB-%D0%BD%D0%B0%D0%BA%D0%BE%D0%BF%D0%B8%D1%82%D0%B5%D0%BB%D1%8C)
2. Установить curl:
   ```bash
   opkg update
   opkg install curl
   ```
3. Установить и настроить сервер TrustTunnel на VPS (см. ниже)

### 1. Установка сервера на VPS

На VPS с Linux (x86_64 или aarch64) выполните:

```bash
curl -fsSL https://raw.githubusercontent.com/TrustTunnel/TrustTunnel/refs/heads/master/scripts/install.sh | sh -s -
```

Сервер установится в `/opt/trusttunnel`. Запустите мастер настройки:

```bash
cd /opt/trusttunnel/
sudo ./setup_wizard
```

Мастер запросит:
- Адрес для прослушивания (по умолчанию `0.0.0.0:443`)
- Учетные данные пользователя
- Путь для хранения правил фильтрации
- Выбор сертификата (Let's Encrypt, самоподписанный или существующий)

Настройте автозапуск через systemd:

```bash
cp /opt/trusttunnel/trusttunnel.service.template /etc/systemd/system/trusttunnel.service
sudo systemctl daemon-reload
sudo systemctl enable --now trusttunnel
```

#### Настройка Let's Encrypt с автообновлением

Установите Certbot:

```bash
sudo apt update
sudo apt install -y certbot
```

Получите сертификат (замените `example.com` на ваш домен):

```bash
sudo certbot certonly --standalone -d example.com
```

Сертификаты сохранятся в:
- `/etc/letsencrypt/live/example.com/fullchain.pem`
- `/etc/letsencrypt/live/example.com/privkey.pem`

Укажите пути в конфигурации TrustTunnel (`hosts.toml`):

```toml
[[main_hosts]]
hostname = "example.com"
cert_chain_path = "/etc/letsencrypt/live/example.com/fullchain.pem"
private_key_path = "/etc/letsencrypt/live/example.com/privkey.pem"
```

Настройте автоматический перезапуск сервера после обновления сертификата:

```bash
sudo certbot reconfigure --deploy-hook "systemctl reload trusttunnel"
```

Проверьте работу автообновления:

```bash
sudo certbot renew
```

#### Экспорт конфигурации для клиента

После настройки сервера экспортируйте конфигурацию для клиента:

```bash
cd /opt/trusttunnel/
./trusttunnel_endpoint vpn.toml hosts.toml -c имя_клиента -a публичный_ip_сервера > config.toml
```

Это создаст файл конфигурации `config.toml`, который нужно передать на роутер.

### 2. Установка клиента на Keenetic

Выполните одну команду на роутере:

```bash
curl -fsSL https://raw.githubusercontent.com/artemevsevev/TrustTunnel-Keenetic/main/install.sh | sh
```

или с wget:

```bash
wget -qO- https://raw.githubusercontent.com/artemevsevev/TrustTunnel-Keenetic/main/install.sh | sh
```

Скрипт установки выполнит следующее:
1. Скачает и установит скрипты автозапуска (`S99trusttunnel`, `010-trusttunnel.sh`)
2. Предложит создать интерфейс Proxy5 и политику маршрутизации TrustTunnel в Keenetic
3. Предложит установить/обновить клиент TrustTunnel (поддерживаемые архитектуры: x86_64, aarch64, armv7, mips, mipsel)

#### Настройка клиента

Сгенерируйте конфигурацию из файла, экспортированного с сервера:

```bash
cd /opt/trusttunnel_client/
./setup_wizard --mode non-interactive --endpoint_config config.toml --settings trusttunnel_client.toml
```

Подробная документация: https://github.com/TrustTunnel/TrustTunnel

В файле `trusttunnel_client.toml` должен быть настроен SOCKS-прокси listener:

```toml
[listener]

[listener.socks]
# IP address to bind the listener to
address = "127.0.0.1:1080"
# Username for authentication if desired
username = ""
# Password for authentication if desired
password = ""
```

Секции `[listener.tun]` в файле быть не должно.

Проверить запуск:
```bash
./trusttunnel_client -c trusttunnel_client.toml
```

После настройки запустите сервис:
```bash
/opt/etc/init.d/S99trusttunnel start
```

### Настройка прокси вручную в веб-интерфейсе Keenetic

Если при установке вы пропустили автоматическое создание интерфейса и политики, добавьте прокси-соединение вручную:

1. Откройте веб-интерфейс Keenetic
2. Перейдите в раздел **Другие подключения** -> **Прокси-соединения**
3. Добавьте новое SOCKS5 прокси-соединение с адресом `127.0.0.1` и портом `1080`
4. Настройте маршрутизацию трафика через это соединение

## Структура файлов

```
/opt/
├── etc/
│   ├── init.d/
│   │   └── S99trusttunnel          # Основной init-скрипт
│   └── ndm/
│       └── wan.d/
│           └── 010-trusttunnel.sh  # Хук при поднятии WAN
├── var/
│   ├── run/
│   │   ├── trusttunnel.pid         # PID клиента
│   │   └── trusttunnel_watchdog.pid # PID watchdog
│   └── log/
│       └── trusttunnel.log         # Лог работы
└── trusttunnel_client/
    ├── trusttunnel_client          # Бинарник клиента
    └── trusttunnel_client.toml     # Конфигурация
```

## Ручная установка

Если вы предпочитаете ручную установку вместо скрипта:

```bash
# Создаём директории
mkdir -p /opt/etc/init.d
mkdir -p /opt/etc/ndm/wan.d
mkdir -p /opt/var/run
mkdir -p /opt/var/log

# Init-скрипт
curl -fsSL https://raw.githubusercontent.com/artemevsevev/TrustTunnel-Keenetic/main/S99trusttunnel -o /opt/etc/init.d/S99trusttunnel
chmod +x /opt/etc/init.d/S99trusttunnel

# WAN-хук
curl -fsSL https://raw.githubusercontent.com/artemevsevev/TrustTunnel-Keenetic/main/010-trusttunnel.sh -o /opt/etc/ndm/wan.d/010-trusttunnel.sh
chmod +x /opt/etc/ndm/wan.d/010-trusttunnel.sh

# Убедитесь, что клиент исполняемый
chmod +x /opt/trusttunnel_client/trusttunnel_client
```

## Использование

### Управление сервисом

```bash
# Запуск (клиент + watchdog)
/opt/etc/init.d/S99trusttunnel start

# Остановка (клиент + watchdog)
/opt/etc/init.d/S99trusttunnel stop

# Полный перезапуск
/opt/etc/init.d/S99trusttunnel restart

# Мягкий перезапуск (только клиент, watchdog перезапустит его)
/opt/etc/init.d/S99trusttunnel reload

# Проверка статуса
/opt/etc/init.d/S99trusttunnel status
```

### Просмотр логов

```bash
# Текущий лог
cat /opt/var/log/trusttunnel.log

# В реальном времени
tail -f /opt/var/log/trusttunnel.log
```

## Как это работает

### Автозапуск при загрузке
- Entware автоматически запускает все скрипты `S*` в `/opt/etc/init.d/` при старте
- Скрипт `S99trusttunnel` запускается последним (99 = высокий приоритет)

### Watchdog (перезапуск при падении)
- После запуска клиента стартует фоновый процесс watchdog
- Каждые 10 секунд проверяет, жив ли клиент
- При падении автоматически перезапускает

### Переподключение WAN
- Keenetic вызывает скрипты из `/opt/etc/ndm/wan.d/` при поднятии WAN
- Скрипт `010-trusttunnel.sh` инициирует перезапуск клиента
- Watchdog подхватит и запустит клиент заново

### Защита от дублей
- PID-файл предотвращает запуск нескольких экземпляров
- Проверка через `pidof` как fallback

## Отключение автозапуска

```bash
# Временно (до следующего ребута)
/opt/etc/init.d/S99trusttunnel stop

# Постоянно
# Измените ENABLED=yes на ENABLED=no в скрипте
# или удалите/переименуйте скрипт:
mv /opt/etc/init.d/S99trusttunnel /opt/etc/init.d/_S99trusttunnel
```

## Troubleshooting

### Клиент не запускается
```bash
# Проверьте права
ls -la /opt/trusttunnel_client/

# Попробуйте запустить вручную
/opt/trusttunnel_client/trusttunnel_client -c /opt/trusttunnel_client/trusttunnel_client.toml

# Проверьте лог
cat /opt/var/log/trusttunnel.log
```

### Watchdog не работает
```bash
# Проверьте процессы
ps | grep trusttunnel

# Проверьте PID файлы
cat /opt/var/run/trusttunnel_watchdog.pid
```

### WAN-хук не срабатывает
```bash
# Проверьте права
ls -la /opt/etc/ndm/wan.d/

# Проверьте, что Keenetic поддерживает ndm хуки
# (требуется установленный пакет opt в прошивке)
```
