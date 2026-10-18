# Лабораторная работа: раздел /LOGS и архивация логов

Информационная система из трёх компонент пишет логи в `/LOGS/{auth_service,data_process_service,system_event_handler_service}`.
Имена файлов: `{компонента}_YYYY_MM_DD_{timestamp}.log`.

## Состав

| Файл | Назначение |
|---|---|
| `mount_logs.sh` | Монтирует отдельный раздел в `/LOGS`. Раздел — образ `/var/lib/logs_disk.img` (ext4, 100 МБ), подключается через loop-устройство. При первом запуске образ создаётся и форматируется |
| `logs-mount.service` | Юнит systemd, запускает `mount_logs.sh` при старте ОС |
| `log_archiver.sh` | Если раздел заполнен больше порога (90%), делит лимит на 3 папки и архивирует в `.tar.gz` самые старые логи в папках, превысивших свою долю. Самый свежий лог не трогается |
| `logs-archiver.service`, `logs-archiver.timer` | Запуск архиватора через минуту после загрузки и далее каждые 5 минут |
| `disk.sh` | Прототип проверки заполнения раздела |

## Установка

```bash
sudo install -m 755 mount_logs.sh log_archiver.sh /usr/local/bin/
sudo install -m 644 logs-mount.service logs-archiver.service logs-archiver.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now logs-mount.service logs-archiver.timer
```

## Проверка

```bash
df -h /LOGS
systemctl status logs-mount.service
systemctl list-timers logs-archiver.timer
sudo /usr/local/bin/log_archiver.sh /LOGS 90
journalctl -u logs-archiver.service
```

Запуск архиватора вручную: `sudo log_archiver.sh [ПАПКА] [ПОРОГ_%]`, по умолчанию `/LOGS 90`.
