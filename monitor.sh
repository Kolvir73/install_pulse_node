
# v.0.1 
# Testing the monitoring add-on for my original install_pulse_node/validator script... this IS STILL in testing but should work
# ONLY WORKS FOR LIGHTHOUSE and GETH !
# these flags are req. in order for prometheus to receive data from your clients:
# --pprof --metrics for start_execution.sh
# --staking --metrics --validator-monitor-auto for start_consensus.sh 
# --metrics for start_validator.sh
# There is a part in this script that prompts, if you wanna add these flags, only confirm with y if you use my script to setup a node/validator prior to 26.April
# docker container needs to be restartet in order to run with the flags

start_dir=$(pwd)
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create users
echo "Adding users for prometheus and grafana"
sudo useradd -M -G docker prometheus
sudo useradd -M -G docker grafana


# Prompt the user for the location to store prometheus.yml (default: /blockchain)
read -p "Enter the location to store prometheus.yml (default: /blockchain): " config_location

# Set the default location to /blockchain if nothing is entered
if [ -z "$config_location" ]; then
  config_location="/blockchain"
fi

# Create directories
echo "creating directorys for the prometheus and grafana container"
sudo mkdir -p "$config_location/prometheus"
sudo mkdir -p "$config_location/grafana"

# Define the yml content
PROMETHEUS_YML="global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
   - job_name: 'node_exporter'
     static_configs:
       - targets: ['localhost:9100']
   - job_name: 'nodes'
     metrics_path: /metrics
     static_configs:
       - targets: ['localhost:5054']
   - job_name: 'validators'
     metrics_path: /metrics
     static_configs:
       - targets: ['localhost:5064']
   - job_name: 'geth'
     scrape_interval: 15s
     scrape_timeout: 10s
     metrics_path: /debug/metrics/prometheus
     scheme: http
     static_configs:
     - targets: ['localhost:6060']"
	 
	 
# Create prometheus.yml file
echo "creating the yml file for promethesu"
sudo bash -c "cat > $config_location/prometheus.yml << 'EOF'
$PROMETHEUS_YML
EOF"


# Set ownership and permissions
echo "setting ownership for container-folders"
sudo chown -R prometheus:prometheus "$config_location/prometheus"
sudo chown -R grafana:grafana "$config_location/grafana"
sudo chmod 644 "$config_location/prometheus.yml"
sudo chmod -R 777 "$config_location/grafana"

# Set UFW Rules
echo "setting up firewall rules to allow local connection for metric ports"
sudo ufw allow from 127.0.0.1 to any port 8545 proto tcp
sudo ufw allow from 127.0.0.1 to any port 8546 proto tcp
sudo ufw allow from 127.0.0.1 to any port 5052 proto tcp
sudo ufw allow from 127.0.0.1 to any port 5064 proto tcp

# Define Docker commands as variables
PROMETHEUS_CMD="sudo -u prometheus docker run -dt --name prometheus --restart=always \\
  --net='host' \\
  -v $config_location/prometheus.yml:/etc/prometheus/prometheus.yml \\
  -v $config_location/prometheus:/prometheus-data \\
  prom/prometheus
  
  "

PROMETHEUS_NODE_CMD="sudo -u prometheus docker run -dt --name node_exporter --restart=always \\
  --net='host' \\
  -v '/:/host:ro,rslave' \\
  prom/node-exporter --path.rootfs=/host 
  
  "

GRAFANA_CMD="sudo -u grafana docker run -dt --name grafana --restart=always \\
  --net='host' \\
  -v $config_location/grafana:/var/lib/grafana \\
  grafana/grafana
  
  "

# Create start_monitoring.sh script
echo "creating start_monitor.sh script"
sudo bash -c "cat > $config_location/start_monitoring.sh << 'EOF'
#!/bin/bash

$PROMETHEUS_CMD
$PROMETHEUS_NODE_CMD
$GRAFANA_CMD
EOF"

# Make start_monitoring.sh executable
sudo chmod +x $config_location/start_monitoring.sh

echo "created Monitoring-Scripts and Set Firewall rules"
cd $config_location
echo "..."
sleep 2

echo "launching prometheus, node-exporter and grafana containers"
echo ""
sudo $config_location/start_monitoring.sh
sleep 2

# checking if they are running 
echo ""
echo "checking if the docker started" 
echo ""
if sudo docker ps --format '{{.Names}}' | grep -q '^grafana$'; then
  echo "Grafana container is running"
else
  echo "Grafana container is not running"
fi
echo ""
if sudo docker ps --format '{{.Names}}' | grep -q '^prometheus$'; then
  echo "Prometheus container is running"
else
  echo "Prometheus container is not running"
fi
echo ""
if sudo docker ps --format '{{.Names}}' | grep -q '^node_exporter$'; then
  echo "Node Exporter container is running"
else
  echo "Node Exporter container is not running"
fi
echo ""

sleep 2

# Set variables for the API endpoint, authentication, and datasource configuration
grafana_api="http://localhost:3000/api/datasources"
grafana_auth="admin:admin"
prometheus_url="http://localhost:9090"
datasource_name="Prometheus"
datasource_type="prometheus"
access_mode="proxy"
basic_auth_user=""
basic_auth_password=""
is_default="true"

# Send the POST request to add the datasource using curl
curl -X POST -H "Content-Type: application/json" -d \
'{
    "name": "'$datasource_name'",
    "type": "'$datasource_type'",
    "url": "'$prometheus_url'",
    "access": "'$access_mode'",
    "basicAuthUser": "'$basic_auth_user'",
    "basicAuthPassword": "'$basic_auth_password'",
    "isDefault": '$is_default'
}' \
--user "$grafana_auth" \
$grafana_api

sleep 1
echo ""

echo "Downloading dashboard JSON..."
wget -qO- https://gist.githubusercontent.com/karalabe/e7ca79abdec54755ceae09c08bd090cd/raw/dashboard.json > "${start_dir}/Geth_dashboard.json"
wget -qO- https://grafana.com/api/dashboards/11074/revisions/9/download > "${start_dir}/System_dashboard.json"
wget -qO- https://raw.githubusercontent.com/sigp/lighthouse-metrics/master/dashboards/Summary.json > "${start_dir}/Lighthouse_beacon_dashboard.json"
wget -qO- https://raw.githubusercontent.com/sigp/lighthouse-metrics/master/dashboards/ValidatorClient.json > "${start_dir}/Lighthouse_validator_dashboard.json"
wget -qO- https://raw.githubusercontent.com/raskitoma/pulse-staking-dashboard/main/Yoldark_ETH_staking_dashboard.json > "${start_dir}/Staking_dashboard.json"
echo ""
echo "Dashboard Download complete."
echo ""


echo -e "${GREEN}Do you want to add the required flags to the start_xyz.sh scripts and restart Docker containers? (y/n)${NC}"
echo ""
echo -e "${RED}NOTE: This step is only necessary if you used my setup-script before April 26, 2023. From that date onwards, the required flags are already included in the start_ scripts during the initial setup.${NC}"
read answer

if [[ $answer == "y" ]]; then

  # Update start_execution.sh script
  if [ -f "${config_location}/start_execution.sh" ]; then
    sudo sed -i '14s:^:--metrics \\\n:' "${config_location}/start_execution.sh"
    sudo sed -i '15s:^:--pprof \\\n:' "${config_location}/start_execution.sh"
    echo -e "Updated start_execution.sh with --metrics and --pprof flags."
  else
    echo -e "start_execution.sh not found. Skipping."
  fi

  # Update start_consensus.sh script
  if [ -f "${config_location}/start_consensus.sh" ]; then
    sudo sed -i '14s:^:--metrics \\\n:' "${config_location}/start_consensus.sh"
    sudo sed -i '15s:^:--staking \\\n:' "${config_location}/start_consensus.sh"
    sudo sed -i '16s:^:--validator-monitor-auto \\\n:' "${config_location}/start_consensus.sh"
    echo -e "Updated start_consensus.sh with --metrics, --staking, and --validator-monitor-auto flags."
  else
    echo -e "start_consensus.sh not found. Skipping."
  fi

  # Update start_validator.sh script
  if [ -f "${config_location}/start_validator.sh" ]; then
    sudo sed -i '7s:^:--metrics \\\n:' "${config_location}/start_validator.sh"
    echo -e "Updated start_validator.sh with --metrics flag."
  else
    echo -e "start_validator.sh not found. Skipping."
  fi

  echo -e "${GREEN}Script finished. Check your files for updates.${NC}"
  echo ""
  echo "Please press Enter to continue..."
  read -p ""
  clear
  echo -e "${GREEN}Restarting Docker containers...${NC}"
  echo ""
  sudo docker restart execution
  sudo docker restart beacon
  sudo docker restart validator

  echo "Docker containers restarted successfully."
  echo ""
else
  echo "Please ensure your startup scripts contain the following required flags:"
  echo " - geth/execution: --metrics --pprof"
  echo " - ligthhouse/beacon: --staking --metrics --validator-monitor-auto"
  echo " - ligthhouse/validator: --metrics"
  echo ""
  echo "To restart containers after changes are applied, use:"
  echo " - sudo docker restart execution"
  echo " - sudo docker restart beacon"
  echo " - sudo docker restart validator"
  echo ""
fi
echo ""
echo -e "${GREEN}Congratulations, setup is now complete.${NC}"
echo ""
echo "Access Grafana: http://127.0.0.1:3000"
echo "Username: admin"
echo "Password: admin"
echo ""
echo "Add dashboards via: http://127.0.0.1:3000/dashboard/import"
echo "Import JSONs from '${start_dir}'"
echo ""
echo "Please press Enter to continue..."
read -p ""
clear
echo ""
echo "Special thanks to raskitoma (@raskitoma) for forking the Yoldark_ETH_staking_dashboard. GitHub link: https://github.com/raskitoma/pulse-staking-dashboard"
echo "Thanks to Jexxa (@JexxaJ) for providing further improvements to the forked dashboard. GitHub link: https://github.com/JexxaJ/Pulsechain-Validator-Script"
echo "Shoutout to @rainbowtopgun for his valuable contributions in alpha/beta testing and providing awesome feedback while refining the scripts."
echo "Greetings to the whole plsdev tg-channel, you guys rock"
echo ""
echo "HAPPY VALIDATIN' FRENS :p "
echo "..."
echo ""
echo "Brought to you by:
  ██████__██_██████__███████_██_______█████__██____██_███████_██████__
  ██___██_██_██___██_██______██______██___██__██__██__██______██___██_
  ██___██_██_██████__███████_██______███████___████___█████___██████__
  ██___██_██_██___________██_██______██___██____██____██______██___██_
  ██████__██_██______███████_███████_██___██____██____███████_██___██_"
echo -e "${GREEN}For Donations use ERC20: 0xCB00d822323B6f38d13A1f951d7e31D9dfDED4AA${NC}"
sleep 1
echo "Press enter to exit script"
read -p ""
exit 0