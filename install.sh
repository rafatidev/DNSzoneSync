#!/bin/bash

echo "
  ____  _   _ ____    _____                  ____                   
 |  _ \| \ | / ___|  |__  /___  _ __   ___  / ___| _   _ _ __   ___ 
 | | | |  \| \___ \    / // _ \| '_ \ / _ \ \___ \| | | | '_ \ / __|
 | |_| | |\  |___) |  / /| (_) | | | |  __/  ___) | |_| | | | | (__ 
 |____/|_| \_|____/  /____\___/|_| |_|\___| |____/ \__, |_| |_|\___|
                                                   |___/            
"


# Check if the distribution is Debian or Ubuntu
if [ -f /etc/os-release ]; then
    DISTRO=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
    if [ "$DISTRO" != "debian" ] && [ "$DISTRO" != "ubuntu" ]; then
        show_error "Error: This script is only compatible with Debian or Ubuntu."
        exit 1
    fi
else
    show_error "Error: Unable to determine the Linux distribution."
    exit 1
fi

# Check if jq is installed and install it if not
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo apt update
    sudo apt install -y jq
fi


# Check if cowsay is installed and install it if not
if ! command -v cowsay &> /dev/null; then
    echo "Installing cowsay..."
    sudo apt update
    sudo apt install -y cowsay
fi

# Function to display a message using cowsay with custom colors
display_message() {
    if [ "$1" = "success" ]; then
        cowsay -f tux -b -n " $2 " | lolcat -a -d 1
    elif [ "$1" = "error" ]; then
        cowsay -f ghostbusters -b -n " $2 " | lolcat -a -d 1
    fi
}


show_error() {
  echo -e "\e[31m"
  cowsay -d "$1"
  echo -e "\e[0m"
}

show_success() {
  echo -e "\e[32m"
  cowsay -p "$1"
  echo -e "\e[0m"
}

show_warning() {
  echo -e "\e[33m" 
  cowsay -t "$1"
  echo -e "\e[0m"  
}


while true; do
  # Ask the user for required values
  read -p "Please enter the Cloudflare API Token value: " auth_token
  read -p "Please enter the zone_identifier value: " zone_identifier
  read -p "Please enter the Cloudflare Email Account value: " email
  read -p "Please enter the Domain Name value: " name
  read -p "Please enter the Hetzner API TOKEN value: " API_TOKEN
  read -p "Please enter the SERVER_ID value: " SERVER_ID
  


  # Request to the Cloudflare API and prevent other messages from being printed
  response=$(curl -s --request GET \
    --url "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records" \
    --header "Content-Type: application/json" \
    --header "Authorization: Bearer $auth_token" 2>&1) # Redirect stderr to stdout

  # Check API output for `jq: error' error
  if echo "$response" | grep -q 'jq: error'; then
    show_error "An error occurred while processing the API response."
    exit 1
  fi

  # Checking and extracting the id of the name field, whose value is equal to the value of the user's input
  identifier=$(echo "$response" | jq -e -r --arg name "$name" '.result[] | select(.name == $name) | .id')

  # Check and print the error related to not finding the name value
  if [ -z "$identifier" ]; then
    show_error "Record with name '$name' not found in the DNS records."
  else
    show_success "Identifier for name '$name' is: $identifier"
    break
  fi
done


# Create DNSzoneSync.sh in /home directory
echo "Creating DNSzoneSync.sh..."
cat > /home/DNSzoneSync.sh << EOL
#!/bin/bash



# User-defined values
zone_identifier="$zone_identifier"
identifier="$identifier"  # Use the record_id obtained from the API response
SERVER_ID="$SERVER_ID"
name="$name"

# ... Rest of the script continues ...

API_TOKEN="$API_TOKEN"

response=\$(curl -H "Authorization: Bearer \$API_TOKEN" "https://api.hetzner.cloud/v1/servers/\$SERVER_ID" | jq '.')

server_ip_v4=\$(echo "\$response" | jq -r '.server.public_net.ipv4.ip')

echo "Server IP Address: \$server_ip_v4"

auth_token="$auth_token"
email="$email"

api_url="https://api.cloudflare.com/client/v4/zones/\$zone_identifier/dns_records/\$identifier"

data='{
  "content": "'"\$server_ip_v4"'",
  "name": "'"\$name"'",
  "proxied": false,
  "type": "A",
  "ttl": 3600
}'

result=\$(curl -s -X PUT "\$api_url" \
     -H "Content-Type: application/json" \
     -H "X-Auth-Email: \$email" \
     -H "Authorization: Bearer \$auth_token" \
     --data "\$data" | jq '.success')

if [ "\$result" = "true" ]; then
    cowsay -p "Change IP For \$name Successful (IP Changed to \$server_ip_v4)"
else
    cowsay -d "Failed to change IP for \$name"
fi

EOL

# Set execute permission for DNSzoneSync.sh
chmod +x /home/DNSzoneSync.sh

cowsay -f eyes "Installation completed successfully!"

# Run DNSzoneSync.sh
echo "Running DNSzoneSync.sh..."
/home/DNSzoneSync.sh


# Add the script to crontab
add_to_crontab() {
    # Check if the crontab entry already exists
    if crontab -l | grep -q "/home/DNSzoneSync.sh"; then
        show_warning "Crontab entry already exists. No changes made."
    else
        # Add the entry to crontab
        (crontab -l; echo "@reboot /bin/bash /home/DNSzoneSync.sh") | crontab -
        show_success "Crontab entry added successfully."
    fi
}


# Call the function to add to crontab
add_to_crontab

# Finish the script
exit 0