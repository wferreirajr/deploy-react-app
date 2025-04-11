#!/bin/bash

# Exibe erros e interrompe o script em caso de falhas
set -e

# Função de exibição de ajuda
usage() {
    echo "Uso: $0 -p <projectName> -g <gitUrl> [-s <ssl>] [-d <domain>] [-e <email>]"
    echo "Parâmetros:"
    echo "  -p, --projectName       Nome do projeto"
    echo "  -g, --gitUrl            URL do repositório Git"
    echo "  -s, --ssl               Configuração SSL (true/false, padrão: false)"
    echo "  -d, --domain            Nome do domínio (obrigatório se SSL = true)"
    echo "  -e, --email             E-mail para SSL (obrigatório se SSL = true)"
    echo "Exemplo:"
    echo "  $0 -p minha-app-react -g https://github.com/usuario/meu-repositorio.git -s true -d exemplo.com -e usuario@exemplo.com"
    exit 1
}

# Verifica se existem parâmetros
if [ $# -lt 1 ]; then
    usage
fi

# Variáveis
projectName=""
gitUrl=""
ssl="false"
domain=""
email=""

# Processa os parâmetros
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--projectName) projectName="$2"; shift ;;
        -g|--gitUrl) gitUrl="$2"; shift ;;
        -s|--ssl) ssl="$2"; shift ;;
        -d|--domain) domain="$2"; shift ;;
        -e|--email) email="$2"; shift ;;
        *) echo "Parâmetro desconhecido: $1"; usage ;;
    esac
    shift
done

# Valida os parâmetros obrigatórios
if [ -z "$projectName" ] || [ -z "$gitUrl" ]; then
    echo "Os parâmetros -p (projectName) e -g (gitUrl) são obrigatórios."
    usage
fi

# Valida parâmetros de SSL
if [ "$ssl" == "true" ]; then
    if [ -z "$domain" ] || [ -z "$email" ]; then
        echo "Os parâmetros -d (domain) e -e (email) são obrigatórios quando SSL está habilitado."
        usage
    fi
fi

echo "Iniciando deploy do projeto '$projectName'..."
echo "Repositório Git: $gitUrl"
echo "SSL configurado: $ssl"
if [ "$ssl" == "true" ]; then
    echo "Domínio: $domain"
    echo "E-mail: $email"
fi

# Atualiza o sistema
echo "Atualizando o sistema..."
sudo apt update && sudo apt upgrade -y

# Instala dependências necessárias
echo "Instalando Node.js, npm, Git e Nginx..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs git nginx vite

# Clona o repositório e instala dependências do projeto
echo "Clonando repositório Git..."
sudo mkdir -p /var/www/$projectName
sudo git clone $gitUrl /var/www/$projectName

echo "Instalando dependências do projeto..."
cd /var/www/$projectName
sudo npm install
sudo npm run build

# Configura Nginx
echo "Configurando Nginx..."
nginx_config_path="/etc/nginx/sites-available/$projectName"

sudo bash -c "cat > $nginx_config_path" <<EOL
server {
    listen 80;
    server_name $domain;
    root /var/www/$projectName/dist;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOL

echo "Ativando configuração Nginx..."
sudo ln -s $nginx_config_path /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# Configura SSL usando Let's Encrypt (opcional)
if [ "$ssl" == "true" ]; then
    echo "Configurando SSL com Let's Encrypt..."
    sudo apt install -y certbot python3-certbot-nginx
    sudo certbot --nginx --non-interactive --agree-tos -d $domain -m $email

    # Verificando se o cron job de renovação automático já existe
    if ! crontab -l | grep -q "certbot renew"; then
        echo "Configurando renovação automática de certificados SSL..."
        (crontab -l 2>/dev/null; echo "0 0 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -
    else
        echo "Renovação automática de certificados SSL já está configurada."
    fi
fi

# Configurando firewall
echo "Configurando firewall..."
sudo ufw allow 'Nginx Full'
sudo ufw enable

echo "Deploy do projeto '$projectName' concluído!"
if [ "$ssl" == "true" ]; then
    echo "Acesse sua aplicação em: https://$domain"
else
    echo "Acesse sua aplicação pelo IP do servidor."
fi
