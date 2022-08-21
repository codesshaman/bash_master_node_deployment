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
    curl gnupg lsb-release wget
    ufw status
    ufw enable
    ufw allow ssh
    ufw allow 443
    ufw allow 80
    read -p "Введите порт для portainer:" port
    ufw allow $port
    ufw status
    echo "Запускаю docker в режиме роя"
    docker swarm init > swarm.txt && cat swarm.txt
    echo "Устанавливаю portainer"
    docker volume create portainer_data
    mkdir portainer && cd portainer
    curl -L https://downloads.portainer.io/ce2-14/portainer-agent-stack.yml -o portainer-agent-stack.yml
    sed -i "s/9443:9443/$port:9443/g" portainer-agent-stack.yml
    sed -i 's!      - "9000:9000"!#      - "9000:9000"!1' portainer-agent-stack.yml
    sed -i 's!      - "8000:8000"!#      - "8000:8000"!1' portainer-agent-stack.yml
    docker stack deploy -c portainer-agent-stack.yml portainer && cd ..
    echo "Устанавливаю ctop"
    curl -fsSL https://azlux.fr/repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/azlux-archive-keyring.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian \
        $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/azlux.list >/dev/null
    apt update && apt install docker-ctop
    chmod +x /usr/bin/ctop
    if confirm "Установить traefik? (y/n or enter for no)"; then
        read -p "Введите  порт для traefik: " tport
        ufw allow $tport && ufw status
        mkdir traefik && cd traefik
        echo "version: '3'"  > docker-compose.yml
        echo "services:" >> docker-compose.yml
        echo "  reverse-proxy:" >> docker-compose.yml
        echo "    # The official v2 Traefik docker image" >> docker-compose.yml
        echo "    image: traefik:v2.8" >> docker-compose.yml
        echo "    # Enables the web UI and tells Traefik to listen to docker" >> docker-compose.yml
        echo "    command: --api.insecure=true --providers.docker" >> docker-compose.yml
        echo "    ports:" >> docker-compose.yml
        echo "      # The HTTP port" >> docker-compose.yml
        echo '      - "80:80"' >> docker-compose.yml
        echo "      # The Web UI (enabled by --api.insecure=true)" >> docker-compose.yml
        echo '      - "8080:8080"' >> docker-compose.yml
        echo "    volumes:" >> docker-compose.yml
        echo "      # So that Traefik can listen to the Docker events" >> docker-compose.yml
        echo "      - /var/run/docker.sock:/var/run/docker.sock" >> docker-compose.yml
        sed -i "s!80:80!$tport:80!1" portainer-agent-stack.yml
        echo "#!/bin/bash" >  start.sh
        echo "docker-compose up -d reverse-proxy" >>  start.sh
        chmod +x  start.sh && ./start.sh
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
fi
