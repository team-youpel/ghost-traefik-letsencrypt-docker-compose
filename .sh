#!/bin/bash
# shellcheck disable=SC2162
RED="31"
GREEN="32"
BOLDGREEN="\e[1;${GREEN}m"
ITALICRED="\e[3;${RED}m"
ENDCOLOR="\e[0m"

# Function to validate password
validate_password() {
    local password=$1
    local has_string=false
    local has_number=false

    # Check if password contains at least one string character and one number
    if [[ "$password" =~ [[:alpha:]] ]]; then
        has_string=true
    fi
    if [[ "$password" =~ [[:digit:]] ]]; then
        has_number=true
    fi

    # Check if password meets length requirement and contains both strings and numbers
    if [ ${#password} -ge 10 ] && [ "$has_string" = true ] && [ "$has_number" = true ]; then
        return 0
    else
        return 1
    fi
}

# Function to check and install Docker if necessary
check_and_install_docker() {
    if command -v docker &>/dev/null; then
        echo -e "Docker is already installed."
    else
        echo "Docker is not installed. Installing..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker "$USER"
        echo "Docker has been installed."
    fi
}

# Function to check if Docker Compose exists
check_docker_compose() {
    if command -v docker-compose &>/dev/null; then
        echo -e "Docker Compose is already installed."
    else
        echo "Docker Compose is not installed. Installing..."
        sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo "Docker Compose has been installed."
    fi
}

# Prompt for configuration values
read -p "Enter your desired domain name (e.g., example.com): " domain_name
echo
read -p "Enter your email address for Let's Encrypt: " email_address
echo
read -p "Enter your desired database user password (min length 10, containing both strings and numbers): " db_user_password
echo
while ! validate_password "$db_user_password"; do
    echo "Password must be at least 10 characters long and contain both strings and numbers."
    read -p "Enter your desired database user password again: " db_user_password
    echo
done
read -p "Enter your desired database admin password (min length 10, containing both strings and numbers): " db_admin_password
echo
while ! validate_password "$db_admin_password"; do
    echo "Password must be at least 10 characters long and contain both strings and numbers."
    read -p "Enter your desired database admin password again: " db_admin_password
    echo
done

# Confirm user input
echo "You entered the following values:"
echo "Domain name: $domain_name"
echo "Email address: $email_address"
echo "Database user password: $db_user_password"
echo "Database admin password: $db_admin_password"

read -p "Do you want to proceed with these values? (y/n) " choice

if [[ "$choice" =~ ^[Yy]$ ]]; then
    # Navigate to home directory
    home_dir=$(eval echo "~$USER")
    cd "$home_dir" || exit
    # Check and install Docker if necessary
    check_and_install_docker
    # Check and install Docker Compose if necessary
    check_docker_compose
    # Navigate to home directory
    home_dir=$(eval echo "~$USER")
    cd "$home_dir" || exit
    # Clone the Ghost repository
    git clone https://github.com/team-youpel/ghost-traefik-letsencrypt-docker-compose.git
    # Change directory to the cloned repository
    cd ghost-traefik-letsencrypt-docker-compose || exit
    # Create a new .env file with the provided values
    rm -rf .env
    cat >.env <<EOF
# Traefik Variables
TRAEFIK_IMAGE_TAG=traefik:2.9
TRAEFIK_LOG_LEVEL=WARN
TRAEFIK_ACME_EMAIL=$email_address
TRAEFIK_HOSTNAME=traefik.postgoo.net
TRAEFIK_BASIC_AUTH=traefikadmin:\$\$2y\$\$10\$\$sMzJfirKC75x/hVpiINeZOiSm.Jkity9cn4KwNkRvO7hSQVFc5FLO

# Ghost Variables
GHOST_MYSQL_IMAGE_TAG=mysql:11.1
GHOST_IMAGE_TAG=ghost:5.60
GHOST_DB_NAME=ghostdb
GHOST_DB_USER=ghostdbbuser
GHOST_DB_PASSWORD=$db_user_password
GHOST_DB_ADMIN_PASSWORD=$db_admin_password
GHOST_URL=https://$domain_name
GHOST_HOSTNAME=$domain_name

# Backup Variables
BACKUP_INIT_SLEEP=30m
BACKUP_INTERVAL=24h
MYSQL_BACKUP_PRUNE_DAYS=7
DATA_BACKUP_PRUNE_DAYS=7
MYSQL_BACKUPS_PATH=/srv/ghost-mysql/backups
DATA_BACKUPS_PATH=/srv/ghost-application-data/backups
DATA_PATH=/var/lib/ghost/content
MYSQL_BACKUP_NAME=ghost-mysql-backup
DATA_BACKUP_NAME=ghost-application-data-backup
EOF

    # Create necessary Docker networks
    docker network create traefik-network
    docker network create ghost-network

    # Start the Docker containers
    docker compose -f ghost-traefik-letsencrypt-docker-compose.yml -p ghost up -d

    echo -e "${BOLDGREEN}✔ Ghost blog should now be accessible after a few seconds at https://$domain_name${ENDCOLOR}"
else
    echo -e "${ITALICRED}Installation aborted.${ENDCOLOR}"
fi