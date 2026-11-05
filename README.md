# MultiSub Panel

Веб-панель для управления данными MultiSub. Установщик подготовлен для Ubuntu 24.04.

## Установка

```bash
git clone https://github.com/plaphase/sub-multi_base.git
cd sub-multi_base
sudo bash installer/install.sh
```

Установщик проверит систему, предложит создать новый каталог данных или подключить существующий, установит Python-зависимости и Nginx, создаст системного пользователя и службу `multisub-panel`, а затем настроит обратный прокси.

Укажите публичный IP или домен, по которому будет открываться панель. Для нового VPS выберите новую установку и задайте путь `/var/lib/multisub-panel`. Для подключения имеющихся данных сначала укажите исходный каталог, затем путь для рабочей копии.

Установщик генерирует пароль администратора и сохраняет его в `/etc/multisub-panel/panel.env` с правами доступа `600`. Посмотреть логин и пароль можно на сервере:

```bash
sudo grep -E '^PANEL_(USERNAME|PASSWORD)=' /etc/multisub-panel/panel.env
```

Панель доступна через Nginx на порту 80. Приложение Gunicorn слушает только `127.0.0.1:18082`. Управление службой:

```bash
sudo systemctl status multisub-panel
sudo systemctl restart multisub-panel
sudo journalctl -u multisub-panel -f
```

## HTTP и HTTPS

Без домена установщик может настроить HTTP по IP для временной проверки. HTTP не шифрует пароль, сессию и данные панели. Не используйте этот режим для реальной эксплуатации или настоящих учетных данных. Для постоянного использования настройте домен и HTTPS, затем задайте `PANEL_COOKIE_SECURE=true`.

## Проверки

```bash
sudo bash installer/preflight.sh
sudo bash tests/test_installer_paths.sh
sudo bash tests/test_create_config.sh
sudo bash tests/test_install_flow.sh
```
