#!/bin/bash

################################################################################
# Proxmox Config-Driven NAT Manager
#
# Usage: Manage all NAT rules from a single YAML config file
# Advantage: Get rid of CLI chaos, just edit the config file
################################################################################

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Settings
CONFIG_FILE="/etc/nat-config.yaml"
LOG_FILE="/var/log/nat-manager.log"
BACKUP_DIR="/var/backups/nat-rules"

# Utilities
print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# YAML Parser (simple)
parse_yaml() {
    local yaml_file=$1

    if [[ ! -f "$yaml_file" ]]; then
        print_error "Config file not found: $yaml_file"
        return 1
    fi

    # Read YAML file and process each service
    grep "^  [a-z].*:$" "$yaml_file" | sed 's/:$//' | while read service; do
        service=$(echo "$service" | xargs)

        # Get service information
        local public_port=$(grep -A 10 "^  $service:" "$yaml_file" | grep "public_port:" | head -1 | awk '{print $2}')
        local container_ip=$(grep -A 10 "^  $service:" "$yaml_file" | grep "container_ip:" | head -1 | awk '{print $2}')
        local container_port=$(grep -A 10 "^  $service:" "$yaml_file" | grep "container_port:" | head -1 | awk '{print $2}')

        if [[ -z "$public_port" || -z "$container_ip" || -z "$container_port" ]]; then
            print_error "Missing configuration: $service"
            continue
        fi

        # Get allowed IPs
        local ips=$(grep -A 10 "^  $service:" "$yaml_file" | grep -A 5 "allowed_ips:" | grep "^\s*-" | awk '{print $2}' | xargs)

        echo "$service|$public_port|$container_ip|$container_port|$ips"
    done
}

# Apply NAT rules
apply_nat_rules() {
    print_header "Applying NAT Rules"

    # Backup
    mkdir -p "$BACKUP_DIR"
    iptables-save > "$BACKUP_DIR/rules_$(date +%s).txt"
    print_success "Backup created: $BACKUP_DIR"

    # Clear existing rules
    print_warning "Cleaning old rules..."
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -F POSTROUTING 2>/dev/null || true

    # Read and apply rules from config
    local rule_count=0
    parse_yaml "$CONFIG_FILE" | while IFS='|' read service public_port container_ip container_port ips; do

        if [[ -z "$service" ]]; then
            continue
        fi

        print_warning "Service: $service (Port: $public_port → $container_port)"

        # DNAT rule for each allowed IP
        for ip in $ips; do
            echo "  → IP: $ip"
            iptables -t nat -A PREROUTING \
                -p tcp --dport "$public_port" \
                -s "$ip" \
                -j DNAT --to-destination "$container_ip:$container_port"
            print_success "DNAT rule added"
            ((rule_count++))
        done

        # Reject other sources
        echo "  → Reject other IPs"
        iptables -t nat -A PREROUTING \
            -p tcp --dport "$public_port" \
            -j REJECT --reject-with tcp-reset
        print_success "REJECT rule added"
        ((rule_count++))

        # MASQUERADE
        echo "  → MASQUERADE"
        iptables -t nat -A POSTROUTING \
            -d "$container_ip" -p tcp --dport "$container_port" \
            -j MASQUERADE
        print_success "MASQUERADE rule added"
        ((rule_count++))

        echo ""
    done

    print_success "Total $rule_count rules applied!"
    log_action "NAT rules applied. Total: $rule_count"
}

# Test NAT rules
test_nat_rules() {
    print_header "Testing NAT Rules"

    echo -e "\n${YELLOW}PREROUTING Rules:${NC}"
    iptables -t nat -L PREROUTING -n -v | tail -n +3

    echo -e "\n${YELLOW}POSTROUTING Rules:${NC}"
    iptables -t nat -L POSTROUTING -n -v | tail -n +3

    echo -e "\n${YELLOW}Services Read from Config:${NC}"
    parse_yaml "$CONFIG_FILE" | while IFS='|' read service public_port container_ip container_port ips; do
        if [[ -z "$service" ]]; then
            continue
        fi
        echo -e "${GREEN}$service${NC}"
        echo "  Public Port:    $public_port"
        echo "  Container:      $container_ip:$container_port"
        echo "  Allowed IPs:    $ips"
        echo ""
    done
}

# Persist rules
persist_rules() {
    print_header "Persisting Rules"

    print_warning "Installing iptables-persistent..."
    apt-get update > /dev/null 2>&1
    apt-get install -y iptables-persistent > /dev/null 2>&1
    print_success "iptables-persistent installed"

    print_warning "Saving rules..."
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    print_success "Rules saved"

    print_warning "Starting netfilter-persistent service..."
    systemctl enable netfilter-persistent
    systemctl restart netfilter-persistent
    print_success "Service started"

    log_action "NAT rules persisted"
}

# Create sample config file
create_sample_config() {
    print_header "Creating Sample Config File"

    cat > "$CONFIG_FILE" << 'EOF'
# Proxmox NAT Configuration File
#
# Usage:
#   1. Edit this file
#   2. Run 'nat-manager apply' command
#   3. Done!
#
# To add each service:
#   - Add public_port, container_ip, container_port, allowed_ips under service_name

services:
  mysql:
    public_port: 3306
    container_ip: 10.10.20.110
    container_port: 3306
    allowed_ips:
      - 192.168.1.100
      - 192.168.1.101

  # rabbitmq:
  #   public_port: 5672
  #   container_ip: 10.10.20.110
  #   container_port: 5672
  #   allowed_ips:
  #     - 192.168.1.100

  # postgresql:
  #   public_port: 5432
  #   container_ip: 10.10.20.110
  #   container_port: 5432
  #   allowed_ips:
  #     - 192.168.1.100
  #     - 203.0.113.50

  # redis:
  #   public_port: 6379
  #   container_ip: 10.10.20.110
  #   container_port: 6379
  #   allowed_ips:
  #     - 192.168.1.100

  # mongodb:
  #   public_port: 27017
  #   container_ip: 10.10.20.110
  #   container_port: 27017
  #   allowed_ips:
  #     - 192.168.1.100
EOF

    chmod 644 "$CONFIG_FILE"
    print_success "Config file created: $CONFIG_FILE"

    print_warning "Now edit the config file:"
    echo "  sudo nano $CONFIG_FILE"
}

# Interactive config editor
edit_config() {
    print_header "Edit Config File"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_warning "Config file not found, creating sample..."
        create_sample_config
    fi

    nano "$CONFIG_FILE"

    print_success "Config file saved"
}

# Add service (interactive)
add_service() {
    print_header "Add New Service"

    read -p "Service name (e.g.: rabbitmq): " service_name
    read -p "Public port (e.g.: 5672): " public_port
    read -p "Container IP (e.g.: 10.10.20.110): " container_ip
    read -p "Container port (e.g.: 5672): " container_port

    read -p "Allowed IPs (comma-separated): " allowed_ips_input

    # Check config file
    if [[ ! -f "$CONFIG_FILE" ]]; then
        create_sample_config
    fi

    # Add new service
    cat >> "$CONFIG_FILE" << EOF

  $service_name:
    public_port: $public_port
    container_ip: $container_ip
    container_port: $container_port
    allowed_ips:
EOF

    IFS=',' read -ra IPS <<< "$allowed_ips_input"
    for ip in "${IPS[@]}"; do
        ip=$(echo "$ip" | xargs)
        echo "      - $ip" >> "$CONFIG_FILE"
    done

    print_success "Service added: $service_name"
    print_warning "To apply rules: nat-manager apply"
}

# Remove service
remove_service() {
    print_header "Remove Service"

    read -p "Service name to remove: " service_name

    if grep -q "^  $service_name:" "$CONFIG_FILE"; then
        # Remove service from YAML (simple method)
        sed -i "/^  $service_name:/,/^  [a-z]/{ /^  $service_name:/,/^  [a-z]/{/^  [a-z]/!d;}; }" "$CONFIG_FILE"
        print_success "Service removed: $service_name"
    else
        print_error "Service not found: $service_name"
    fi
}

# Show status
show_status() {
    print_header "NAT Manager Status"

    echo ""
    echo -e "${YELLOW}Config File:${NC}"
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${GREEN}✓ $CONFIG_FILE exists${NC}"
        wc -l "$CONFIG_FILE" | awk '{print "  Total lines: " $1}'
    else
        echo -e "${RED}✗ Config file not found${NC}"
    fi

    echo ""
    echo -e "${YELLOW}System Status:${NC}"
    if systemctl is-active --quiet netfilter-persistent; then
        echo -e "${GREEN}✓ netfilter-persistent active${NC}"
    else
        echo -e "${RED}✗ netfilter-persistent inactive${NC}"
    fi

    if systemctl is-active --quiet pve-firewall; then
        echo -e "${GREEN}✓ pve-firewall active${NC}"
    else
        echo -e "${YELLOW}⚠ pve-firewall inactive${NC}"
    fi

    echo ""
    echo -e "${YELLOW}NAT Rules:${NC}"
    local rule_count=$(iptables -t nat -L PREROUTING -n | grep -c "DNAT\|REJECT" || echo "0")
    echo "  Total rules: $rule_count"

    echo ""
    echo -e "${YELLOW}Last Action:${NC}"
    tail -n 1 "$LOG_FILE" 2>/dev/null || echo "  (No log)"
}

# Command line interface
print_usage() {
    cat << EOF

${BLUE}╔════════════════════════════════════════════════════════════╗${NC}
${BLUE}║     Proxmox Config-Driven NAT Manager                      ║${NC}
${BLUE}╚════════════════════════════════════════════════════════════╝${NC}

${YELLOW}Usage:${NC}
  nat-manager [COMMAND]

${YELLOW}Commands:${NC}
  init              - Initial setup (create config file)
  edit              - Edit config file (nano)
  add               - Interactively add service
  remove            - Remove service
  apply             - Create and apply rules from config
  test              - Test rules
  persist           - Persist rules (survive reboot)
  status            - Show status
  show-config       - Display config file
  show-rules        - Display iptables rules
  backup            - Backup rules
  restore [FILE]    - Restore from backup
  logs              - Display log file
  help              - Show this help

${YELLOW}Example Usage:${NC}
  1. nat-manager init                    # Setup
  2. sudo nano /etc/nat-config.yaml      # Edit config
  3. nat-manager apply                   # Apply rules
  4. nat-manager test                    # Test
  5. nat-manager persist                 # Persist

${YELLOW}Config File:${NC}
  $CONFIG_FILE

${YELLOW}Log File:${NC}
  $LOG_FILE

EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    # Root check
    if [[ "$cmd" != "help" && "$cmd" != "show-config" && "$cmd" != "show-rules" && "$cmd" != "logs" && "$cmd" != "status" ]]; then
        if [[ $EUID -ne 0 ]]; then
            print_error "This command must be run as root!"
            exit 1
        fi
    fi

    case "$cmd" in
        init)
            create_sample_config
            ;;
        edit)
            edit_config
            ;;
        add)
            add_service
            print_warning "To apply rules: sudo nat-manager apply"
            ;;
        remove)
            remove_service
            print_warning "To apply rules: sudo nat-manager apply"
            ;;
        apply)
            apply_nat_rules
            ;;
        persist)
            persist_rules
            ;;
        test)
            test_nat_rules
            ;;
        status)
            show_status
            ;;
        show-config)
            if [[ -f "$CONFIG_FILE" ]]; then
                echo -e "\n${BLUE}Config File: $CONFIG_FILE${NC}\n"
                cat "$CONFIG_FILE"
            else
                print_error "Config file not found"
            fi
            ;;
        show-rules)
            echo -e "\n${BLUE}PREROUTING Rules:${NC}"
            iptables -t nat -L PREROUTING -n -v
            echo -e "\n${BLUE}POSTROUTING Rules:${NC}"
            iptables -t nat -L POSTROUTING -n -v
            ;;
        backup)
            mkdir -p "$BACKUP_DIR"
            local backup_file="$BACKUP_DIR/rules_$(date +%Y%m%d_%H%M%S).txt"
            iptables-save > "$backup_file"
            print_success "Backup created: $backup_file"
            ;;
        restore)
            local backup_file="${2:-}"
            if [[ -z "$backup_file" ]]; then
                print_error "You must specify a backup file"
                echo "Usage: nat-manager restore /path/to/backup.txt"
                exit 1
            fi
            if [[ ! -f "$backup_file" ]]; then
                print_error "File not found: $backup_file"
                exit 1
            fi
            iptables-restore < "$backup_file"
            print_success "Backup restored: $backup_file"
            ;;
        logs)
            if [[ -f "$LOG_FILE" ]]; then
                echo -e "\n${BLUE}Log File: $LOG_FILE${NC}\n"
                tail -n 20 "$LOG_FILE"
            else
                print_error "Log file not found"
            fi
            ;;
        help|*)
            print_usage
            ;;
    esac
}

# Run
main "$@"
