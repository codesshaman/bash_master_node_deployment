#!/bin/bash

# Функция подтверждения (да-нет)
confirm() {
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

# Функция установки софта:
if confirm "Установить базовый набор программ? (y/n or enter for no)"; then
    echo "Запускаю установку софта"
    apt update && apt install -y \
    docker sudo docker-compose mc \
    tmux ufw htop ca-certificates \
    curl gnupg lsb-release
    ufw status
    ufw enable
    ufw allow ssh
    ufw allow 443
    ufw allow 80
    read -p "Введите порт для portainer:" port
    ufw allow $port
    ufw status
    echo "Устанавливаю portainer"
    docker volume create portainer_data
    echo "Устанавливаю ctop"
    curl -fsSL https://azlux.fr/repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/azlux-archive-keyring.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian \
        $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/azlux.list >/dev/null
    apt update && apt install docker-ctop
    chmod +x /usr/bin/ctop
else
    echo "Выход."
fi

# Проверяем существование папки проектов 
# и создаём её в случае отсутствия
if ls -l /var/projects >/dev/null 2>&1; then
    echo "Каталог /var/projects существует"
else
    mkdir /var/projects
    echo "Каталог /var/projects успешно создан"
fi

# Функция создания нового пользователя:
read -p "Введите имя нового пользователя: " user
if id -u "$user" >/dev/null 2>&1; then
    echo "Пользователь $user уже существует. Выберите другое имя пользователя."
else
    echo "Создаю пользователя с именем $user"
    read -p "Введите пароль нового пользователя:" pass
    if confirm "Добавить пользователя в группу Docker? (y/n or enter for n)"; then
        useradd -m -s /bin/bash -G docker ${user}
    else
        useradd -m -s /bin/bash ${user}
    fi
    if confirm "Добавить пользователя в группу sudo? (y/n or enter for n)"; then
        echo "%$user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$user
    else
        echo "Отменено"
    fi

    # Устанавливаю пароль
    echo "$user:$pass" | chpasswd
    # Создаю рабочую директорию
    mkdir /var/projects/$user
    chown -R $user:$user /var/projects/$user
    # Создаю символьную ссылку из рабочей в домашнюю
    ln -s /var/projects/$user/ /home/$user/projects
    # Создаю директорию для документов
    mkdir /home/$user/documents/
    chown -R $user:$user /home/$user/documents/
    # Создаю директорию для загрузок
    mkdir /home/$user/downloads/
    chown -R $user:$user /home/$user/downloads/
    # Создаю элиас для ctop
    echo 'alias ctop="/usr/bin/ctop"' >> /home/$user/.bashrc
    echo "Пользователь $user успешно создан!"
fi
