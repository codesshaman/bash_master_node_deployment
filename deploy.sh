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
    curl gnupg lsb-release wget git
    ufw status
    ufw enable
    # Если порт конфигурации не менялся,
    if cat /etc/ssh/sshd_config | grep "#Port 22"; then
        #  Предлагаю сменить порт
        if confirm "Изменить порт для ssh? (y/n or enter for no)"; then
            # В случае согласия меняю порт в конфиге
            read -p "Введите порт для ssh:" sshport
            sed -i "s/#Port 22/Port $sshport/1" /etc/ssh/sshd_config
            service sshd restart
            service sshd status
            ufw allow $sshport
            sshchange=0
        else
            # В случае отказа открываю стандартный порт
            ufw allow ssh
        fi
    else
        # Иначе вывожу сообщение об изменении
        echo "Используется нестандартный порт ssh, пропускаю настройку"
    fi
    # Открываю остальные необходимые порты
    ufw allow 443
    ufw allow 80
    read -p "Введите порт для portainer:" port
    ufw allow $port
    ufw status
    # Запускаю docker в режиме роя
    echo "Запускаю docker в режиме роя"
    docker swarm init > swarm.txt && cat swarm.txt
    # Устанавливаю portainer
    echo "Устанавливаю portainer"
    docker volume create portainer_data
    mkdir portainer && cd portainer
    curl -L https://downloads.portainer.io/ce2-14/portainer-agent-stack.yml -o portainer-agent-stack.yml
    sed -i "s/9443:9443/$port:9443/g" portainer-agent-stack.yml
    sed -i 's!      - "9000:9000"!#      - "9000:9000"!1' portainer-agent-stack.yml
    sed -i 's!      - "8000:8000"!#      - "8000:8000"!1' portainer-agent-stack.yml
    docker stack deploy -c portainer-agent-stack.yml portainer && cd ..
    # Устанавливаю ctop
    echo "Устанавливаю ctop"
    curl -fsSL https://azlux.fr/repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/azlux-archive-keyring.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian \
        $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/azlux.list >/dev/null
    apt update && apt install docker-ctop
    chmod +x /usr/bin/ctop
    # Устанавливаю traefik
    if confirm "Установить traefik? (y/n or enter for no)"; then
        read -p "Введите  порт для traefik: " tport
        ufw allow $tport && ufw status
        git clone https://github.com/codesshaman/docker_traefik.git
        cd docker_traefik
        sed -i "s/80:80/$tport:80/1" docker-compose.yml
        chmod +x start.sh && ./start.sh
        cd ..
    else
        echo "Пропускаю установку traefik!"
    fi
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

# Предлагаю создать пользователя:
if confirm "Создать нового пользователя? (y/n or enter for no)"; then
    # Функция создания нового пользователя:
    read -p "Введите имя нового пользователя: " user
    if id -u "$user" >/dev/null 2>&1; then
        echo "Пользователь $user уже существует. Выберите другое имя пользователя"
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
        # Запрещаю логин под root
        # Если логин под суперпользователем возможен,
        if cat /etc/ssh/sshd_config | grep "#PermitRootLogin"; then
            #  Предлагаю запретить логин под root
            if confirm "Запретить логин под суперпользователем? (y/n or enter for no)"; then
                # В случае согласия добавляю строку
                sed -i -e '1 s/^/PermitRootLogin no\n/;' /etc/ssh/sshd_config
                service sshd restart
                service sshd status
                echo "Логин под суперпользователем запрещён"
            else
                # В случае отказа вывожу сообщение
                echo "Настройки входа под суперпользователем не менялись"
            fi
        else
            # Иначе вывожу сообщение
            echo "Настройки входа под суперпользователем не менялись"
        fi
    fi
else
    echo "Пропускаю создание пользователя"
fi


 #Проверяю, измнился ли порт ssh
if [ -z ${sshchange} ]; then
    echo "Настройка завершена"
else
    echo "Настройка завершена. Используйте порт $sshport для подключения по SSH"
fi