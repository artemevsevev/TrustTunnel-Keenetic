# Установка TrustTunnel с автозапуском на Keenetic

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

## Установка

### 1. Копирование файлов

```bash
# Init-скрипт
cp S99trusttunnel /opt/etc/init.d/S99trusttunnel
chmod +x /opt/etc/init.d/S99trusttunnel

# WAN-хук (создаём директорию если нет)
mkdir -p /opt/etc/ndm/wan.d
cp 010-trusttunnel.sh /opt/etc/ndm/wan.d/010-trusttunnel.sh
chmod +x /opt/etc/ndm/wan.d/010-trusttunnel.sh

# Создаём директории для runtime файлов
mkdir -p /opt/var/run
mkdir -p /opt/var/log
```

### 2. Проверка клиента

```bash
# Убедитесь, что клиент исполняемый
chmod +x /opt/trusttunnel_client/trusttunnel_client

# Проверьте конфигурацию
ls -la /opt/trusttunnel_client/trusttunnel_client.toml
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
