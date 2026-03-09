#!/bin/bash

################################################################################
# Proxmox NAT Manager - SIMPLIFIED (v2)
#
# Override fields destegi:
# - interface
# - container_subnet
# - egress_interface
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_FILE="/etc/nat-config.yaml"
LOG_FILE="/var/log/nat-manager.log"
BACKUP_DIR="/var/backups/nat-rules"

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

# Auto-detect container_subnet from container_ip
detect_subnet() {
    local container_ip=$1
    # /24 subnet assume et (10.10.20.110 → 10.10.20.0/24)
    echo "${container_ip%.*}.0/24"
}

# YAML Parser
parse_yaml() {
    local yaml_file=$1

    if [[ ! -f "$yaml_file" ]]; then
        print_error "Config dosyası bulunamadı: $yaml_file"
        return 1
    fi

    grep "^  [a-z].*:$" "$yaml_file" | sed 's/:$//' | while read service; do
        service=$(echo "$service" | xargs)

        local public_ip=$(grep -A 15 "^  $service:" "$yaml_file" | grep "public_ip:" | head -1 | awk '{print $2}')
        local public_port=$(grep -A 15 "^  $service:" "$yaml_file" | grep "public_port:" | head -1 | awk '{print $2}')
        local container_ip=$(grep -A 15 "^  $service:" "$yaml_file" | grep "container_ip:" | head -1 | awk '{print $2}')
        local container_port=$(grep -A 15 "^  $service:" "$yaml_file" | grep "container_port:" | head -1 | awk '{print $2}')

        # Override fields - eğer varsa kullan, yoksa auto-detect
        local interface=$(grep -A 15 "^  $service:" "$yaml_file" | grep "interface:" | head -1 | awk '{print $2}')
        local container_subnet=$(grep -A 15 "^  $service:" "$yaml_file" | grep "container_subnet:" | head -1 | awk '{print $2}')
        local egress_interface=$(grep -A 15 "^  $service:" "$yaml_file" | grep "egress_interface:" | head -1 | awk '{print $2}')

        # Defaults
        [[ -z "$interface" ]] && interface="vmbr0"
        [[ -z "$container_subnet" ]] && container_subnet=$(detect_subnet "$container_ip")
        [[ -z "$egress_interface" ]] && egress_interface="vmbr0"

        if [[ -z "$public_port" || -z "$container_ip" || -z "$container_port" || -z "$public_ip" ]]; then
            print_error "Eksik: $service (public_ip, public_port, container_ip, container_port gerekli)"
            continue
        fi

        local ips=$(grep -A 15 "^  $service:" "$yaml_file" | grep -A 5 "allowed_ips:" | grep "^\s*-" | awk '{print $2}' | xargs)

        echo "$service|$public_ip|$public_port|$interface|$container_ip|$container_port|$container_subnet|$egress_interface|$ips"
    done
}

# Apply NAT rules
apply_nat_rules() {
    print_header "NAT Kuralları Uygulanıyor"

    mkdir -p "$BACKUP_DIR"
    iptables-save > "$BACKUP_DIR/rules_$(date +%s).txt"
    print_success "Backup oluşturuldu"

    print_warning "Eski kurallar temizleniyor..."
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -F POSTROUTING 2>/dev/null || true

    local rule_count=0
    parse_yaml "$CONFIG_FILE" | while IFS='|' read service public_ip public_port interface container_ip container_port container_subnet egress_interface ips; do

        if [[ -z "$service" ]]; then
            continue
        fi

        echo ""
        print_warning "Service: $service"
        echo "  $public_ip:$public_port → $container_ip:$container_port"
        [[ "$interface" != "vmbr0" ]] && echo "  Interface: $interface (custom)"
        [[ "$egress_interface" != "vmbr0" ]] && echo "  Egress: $egress_interface (custom)"

        # DNAT kuralları
        if [[ -n "$ips" && "$ips" != "none" ]]; then
            for ip in $ips; do
                iptables -t nat -A PREROUTING \
                    -i "$interface" \
                    -d "$public_ip" \
                    -p tcp --dport "$public_port" \
                    -s "$ip" \
                    -j DNAT --to-destination "$container_ip:$container_port"
                ((rule_count++))
            done

            iptables -t nat -A PREROUTING \
                -i "$interface" \
                -d "$public_ip" \
                -p tcp --dport "$public_port" \
                -j REJECT --reject-with tcp-reset
            ((rule_count++))
        else
            iptables -t nat -A PREROUTING \
                -i "$interface" \
                -d "$public_ip" \
                -p tcp --dport "$public_port" \
                -j DNAT --to-destination "$container_ip:$container_port"
            ((rule_count++))
        fi

        # MASQUERADE - service port
        iptables -t nat -A POSTROUTING \
            -d "$container_ip" \
            -p tcp --dport "$container_port" \
            -j MASQUERADE
        ((rule_count++))

        # MASQUERADE - internet çıkışı
        iptables -t nat -A POSTROUTING \
            -o "$egress_interface" \
            -s "$container_subnet" \
            -j MASQUERADE
        ((rule_count++))

        print_success "Kurallar eklendi"
    done

    print_success "Tamamlandı!"
    log_action "NAT kuralları uygulandı"
}

# Test rules
test_nat_rules() {
    print_header "NAT Kuralları"

    echo -e "\n${YELLOW}PREROUTING:${NC}"
    iptables -t nat -L PREROUTING -n -v | tail -n +3

    echo -e "\n${YELLOW}POSTROUTING:${NC}"
    iptables -t nat -L POSTROUTING -n -v | tail -n +3

    echo -e "\n${YELLOW}Servisler:${NC}"
    parse_yaml "$CONFIG_FILE" | while IFS='|' read service public_ip public_port interface container_ip container_port container_subnet egress_interface ips; do
        if [[ -z "$service" ]]; then
            continue
        fi
        echo -e "${GREEN}$service${NC}: $public_ip:$public_port → $container_ip:$container_port"
        [[ "$interface" != "vmbr0" ]] && echo "  Interface: $interface"
        [[ "$egress_interface" != "vmbr0" ]] && echo "  Egress: $egress_interface"
        [[ -n "$ips" && "$ips" != "none" ]] && echo "  Allowed: $ips" || echo "  Allowed: Herkes"
    done
}

# Persist rules
persist_rules() {
    print_header "Persist Etme"

    apt-get update > /dev/null 2>&1
    apt-get install -y iptables-persistent > /dev/null 2>&1

    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6

    systemctl enable netfilter-persistent > /dev/null 2>&1
    systemctl restart netfilter-persistent > /dev/null 2>&1

    print_success "Persist tamamlandı"
}

# Create sample config
create_sample_config() {
    print_header "Config Oluşturuluyor"

    cat > "$CONFIG_FILE" << 'EOF'
# Proxmox NAT Configuration - SIMPLIFIED
# Basit ve temiz. Yalnızca gerekli alanlar.
#
# Otomatik olarak ayarlanır (değiştirmek istersen aşağıya yaz):
#   interface: vmbr0 (default)
#   container_subnet: 10.10.20.0/24 (auto-detect)
#   egress_interface: vmbr0 (default)

services:
  web_http:
    public_ip: 138.201.80.48
    public_port: 80
    container_ip: 10.10.20.102
    container_port: 80
    # interface: vmbr0                    # Optional
    # container_subnet: 10.10.20.0/24    # Optional
    # egress_interface: vmbr0             # Optional

  web_https:
    public_ip: 138.201.80.48
    public_port: 443
    container_ip: 10.10.20.102
    container_port: 443

  mysql:
    public_ip: 138.201.80.48
    public_port: 3306
    container_ip: 10.10.20.110
    container_port: 3306
    allowed_ips:
      - 104.247.164.228

  dokploy_panel:
    public_ip: 88.99.130.158
    public_port: 3000
    container_ip: 10.10.20.111
    container_port: 3000
    allowed_ips:
      - 104.247.164.228
EOF

    chmod 644 "$CONFIG_FILE"
    print_success "Config oluşturuldu: $CONFIG_FILE"
    echo ""
    echo "Config'i düzenle:"
    echo "  sudo nano $CONFIG_FILE"
}

# Show status
show_status() {
    print_header "Status"

    echo ""
    echo "Config: $CONFIG_FILE"
    [[ -f "$CONFIG_FILE" ]] && echo -e "${GREEN}✓ Mevcut${NC}" || echo -e "${RED}✗ Yok${NC}"

    echo ""
    echo "Service Status:"
    systemctl is-active --quiet netfilter-persistent && echo -e "${GREEN}✓ netfilter-persistent${NC}" || echo -e "${RED}✗ netfilter-persistent${NC}"

    echo ""
    echo "NAT Kuralları:"
    local count=$(iptables -t nat -L PREROUTING -n | grep -c "DNAT\|REJECT" || echo "0")
    echo "  Toplam: $count"
}

print_usage() {
    cat << USAGE

${BLUE}╔════════════════════════════════════════════╗${NC}
${BLUE}║  Proxmox NAT Manager - SIMPLIFIED (v2)     ║${NC}
${BLUE}╚════════════════════════════════════════════╝${NC}

${YELLOW}Komutlar:${NC}
  init              Config oluştur
  edit              Config düzenle
  apply             Kuralları uygula
  persist           Persist et (reboot'da kalacak)
  test              Kuralları göster
  status            Status göster
  logs              Log'ları göster
  help              Bu yardımı göster

${YELLOW}Örnek:${NC}
  1. sudo nat-manager init
  2. sudo nano /etc/nat-config.yaml
  3. sudo nat-manager apply
  4. sudo nat-manager persist
  5. nat-manager test

${YELLOW}Override Fields:${NC}
  interface (default: vmbr0)
  container_subnet (auto-detect)
  egress_interface (default: vmbr0)

USAGE
}

main() {
    local cmd="${1:-help}"

    if [[ "$cmd" != "help" && "$cmd" != "test" && "$cmd" != "status" && "$cmd" != "logs" && "$cmd" != "show-config" ]]; then
        if [[ $EUID -ne 0 ]]; then
            print_error "Root gerekli"
            exit 1
        fi
    fi

    case "$cmd" in
        init)
            create_sample_config
            ;;
        edit)
            [[ ! -f "$CONFIG_FILE" ]] && create_sample_config
            nano "$CONFIG_FILE"
            print_success "Config kaydedildi"
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
        logs)
            [[ -f "$LOG_FILE" ]] && tail -n 20 "$LOG_FILE" || echo "Log yok"
            ;;
        show-config)
            [[ -f "$CONFIG_FILE" ]] && cat "$CONFIG_FILE" || echo "Config bulunamadı"
            ;;
        help|*)
            print_usage
            ;;
    esac
}

main "$@"
