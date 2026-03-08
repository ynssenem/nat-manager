#!/bin/bash

################################################################################
# Proxmox Config-Driven NAT Manager
# 
# Kullanım: Tek bir YAML config dosyasından tüm NAT kurallarını yönet
# Advantage: CLI karmaşasından kurtul, sadece config dosyasını düzenle
################################################################################

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ayarlar
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

# YAML Parser (basit)
parse_yaml() {
    local yaml_file=$1
    
    if [[ ! -f "$yaml_file" ]]; then
        print_error "Config dosyası bulunamadı: $yaml_file"
        return 1
    fi
    
    # YAML dosyasını oku ve her servisi işle
    grep "^  [a-z].*:$" "$yaml_file" | sed 's/:$//' | while read service; do
        service=$(echo "$service" | xargs)
        
        # Her servis için bilgileri çek
        local public_port=$(grep -A 10 "^  $service:" "$yaml_file" | grep "public_port:" | head -1 | awk '{print $2}')
        local container_ip=$(grep -A 10 "^  $service:" "$yaml_file" | grep "container_ip:" | head -1 | awk '{print $2}')
        local container_port=$(grep -A 10 "^  $service:" "$yaml_file" | grep "container_port:" | head -1 | awk '{print $2}')
        
        if [[ -z "$public_port" || -z "$container_ip" || -z "$container_port" ]]; then
            print_error "Eksik konfigürasyon: $service"
            continue
        fi
        
        # Allowed IPs'i çek
        local ips=$(grep -A 10 "^  $service:" "$yaml_file" | grep -A 5 "allowed_ips:" | grep "^\s*-" | awk '{print $2}' | xargs)
        
        echo "$service|$public_port|$container_ip|$container_port|$ips"
    done
}

# NAT kurallarını uygula
apply_nat_rules() {
    print_header "NAT Kuralları Uygulanıyor"
    
    # Backup al
    mkdir -p "$BACKUP_DIR"
    iptables-save > "$BACKUP_DIR/rules_$(date +%s).txt"
    print_success "Backup oluşturuldu: $BACKUP_DIR"
    
    # Mevcut kuralları temizle
    print_warning "Eski kurallar temizleniyor..."
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -F POSTROUTING 2>/dev/null || true
    
    # Config'den kuralları oku ve uygula
    local rule_count=0
    parse_yaml "$CONFIG_FILE" | while IFS='|' read service public_port container_ip container_port ips; do
        
        if [[ -z "$service" ]]; then
            continue
        fi
        
        print_warning "Service: $service (Port: $public_port → $container_port)"
        
        # Her izin verilen IP için DNAT kuralı
        for ip in $ips; do
            echo "  → IP: $ip"
            iptables -t nat -A PREROUTING \
                -p tcp --dport "$public_port" \
                -s "$ip" \
                -j DNAT --to-destination "$container_ip:$container_port"
            print_success "DNAT kuralı eklendi"
            ((rule_count++))
        done
        
        # Diğer kaynakları reddet
        echo "  → Diğer IP'leri reddet"
        iptables -t nat -A PREROUTING \
            -p tcp --dport "$public_port" \
            -j REJECT --reject-with tcp-reset
        print_success "REJECT kuralı eklendi"
        ((rule_count++))
        
        # MASQUERADE
        echo "  → MASQUERADE"
        iptables -t nat -A POSTROUTING \
            -d "$container_ip" -p tcp --dport "$container_port" \
            -j MASQUERADE
        print_success "MASQUERADE kuralı eklendi"
        ((rule_count++))
        
        echo ""
    done
    
    print_success "Toplam $rule_count kural uygulandı!"
    log_action "NAT kuralları uygulandı. Toplam: $rule_count"
}

# NAT kurallarını test et
test_nat_rules() {
    print_header "NAT Kuralları Test Ediliyor"
    
    echo -e "\n${YELLOW}PREROUTING Kuralları:${NC}"
    iptables -t nat -L PREROUTING -n -v | tail -n +3
    
    echo -e "\n${YELLOW}POSTROUTING Kuralları:${NC}"
    iptables -t nat -L POSTROUTING -n -v | tail -n +3
    
    echo -e "\n${YELLOW}Config Dosyasından Okunan Servisler:${NC}"
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

# Kuralları persist et
persist_rules() {
    print_header "Kuralları Persist Etme"
    
    print_warning "iptables-persistent yükleniyor..."
    apt-get update > /dev/null 2>&1
    apt-get install -y iptables-persistent > /dev/null 2>&1
    print_success "iptables-persistent kuruldu"
    
    print_warning "Kurallar kaydediliyor..."
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    print_success "Kurallar kaydedildi"
    
    print_warning "netfilter-persistent service'i başlatılıyor..."
    systemctl enable netfilter-persistent
    systemctl restart netfilter-persistent
    print_success "Service başlatıldı"
    
    log_action "NAT kuralları persist edildi"
}

# Config dosyasını oluştur
create_sample_config() {
    print_header "Örnek Config Dosyası Oluşturuluyor"
    
    cat > "$CONFIG_FILE" << 'EOF'
# Proxmox NAT Configuration File
# 
# Kullanım:
#   1. Bu dosyayı düzenle
#   2. 'nat-manager apply' komutunu çalıştır
#   3. Tamamdır!
#
# Her servisi eklemek:
#   - service_name altında public_port, container_ip, container_port, allowed_ips ekle

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
    print_success "Config dosyası oluşturuldu: $CONFIG_FILE"
    
    print_warning "Şimdi config dosyasını düzenle:"
    echo "  sudo nano $CONFIG_FILE"
}

# Interactive config editor
edit_config() {
    print_header "Config Dosyasını Düzenle"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_warning "Config dosyası yok, örnek oluşturuluyor..."
        create_sample_config
    fi
    
    nano "$CONFIG_FILE"
    
    print_success "Config dosyası kaydedildi"
}

# Servis ekle (interactive)
add_service() {
    print_header "Yeni Servis Ekle"
    
    read -p "Service adı (örn: rabbitmq): " service_name
    read -p "Public port (örn: 5672): " public_port
    read -p "Container IP (örn: 10.10.20.110): " container_ip
    read -p "Container port (örn: 5672): " container_port
    
    read -p "Allowed IP'ler (virgülle ayırarak): " allowed_ips_input
    
    # Config dosyasını kontrol et
    if [[ ! -f "$CONFIG_FILE" ]]; then
        create_sample_config
    fi
    
    # Yeni servisi ekle
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
    
    print_success "Servis eklendi: $service_name"
    print_warning "Kuralları uygulamak için: nat-manager apply"
}

# Servis sil
remove_service() {
    print_header "Servis Sil"
    
    read -p "Silinecek service adı: " service_name
    
    if grep -q "^  $service_name:" "$CONFIG_FILE"; then
        # YAML'da servisi sil (basit yöntem)
        sed -i "/^  $service_name:/,/^  [a-z]/{ /^  $service_name:/,/^  [a-z]/{/^  [a-z]/!d;}; }" "$CONFIG_FILE"
        print_success "Servis silindi: $service_name"
    else
        print_error "Servis bulunamadı: $service_name"
    fi
}

# Durumu göster
show_status() {
    print_header "NAT Manager Durumu"
    
    echo ""
    echo -e "${YELLOW}Config Dosyası:${NC}"
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${GREEN}✓ $CONFIG_FILE mevcut${NC}"
        wc -l "$CONFIG_FILE" | awk '{print "  Toplam satır: " $1}'
    else
        echo -e "${RED}✗ Config dosyası bulunamadı${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Sistem Durumu:${NC}"
    if systemctl is-active --quiet netfilter-persistent; then
        echo -e "${GREEN}✓ netfilter-persistent aktif${NC}"
    else
        echo -e "${RED}✗ netfilter-persistent aktif değil${NC}"
    fi
    
    if systemctl is-active --quiet pve-firewall; then
        echo -e "${GREEN}✓ pve-firewall aktif${NC}"
    else
        echo -e "${YELLOW}⚠ pve-firewall aktif değil${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}NAT Kuralları:${NC}"
    local rule_count=$(iptables -t nat -L PREROUTING -n | grep -c "DNAT\|REJECT" || echo "0")
    echo "  Toplam kural: $rule_count"
    
    echo ""
    echo -e "${YELLOW}Son İşlem:${NC}"
    tail -n 1 "$LOG_FILE" 2>/dev/null || echo "  (Log yok)"
}

# Komut satırı arayüzü
print_usage() {
    cat << EOF

${BLUE}╔════════════════════════════════════════════════════════════╗${NC}
${BLUE}║     Proxmox Config-Driven NAT Manager                      ║${NC}
${BLUE}╚════════════════════════════════════════════════════════════╝${NC}

${YELLOW}Kullanım:${NC}
  nat-manager [KOMUT]

${YELLOW}Komutlar:${NC}
  init              - İlk kurulum (config dosyası oluştur)
  edit              - Config dosyasını düzenle (nano)
  add               - Interaktif olarak servis ekle
  remove            - Servis sil
  apply             - Config'den kuralları oluştur ve uygula
  test              - Kuralları test et
  persist           - Kuralları kalıcı yap (reboot sonrasında)
  status            - Durumu göster
  show-config       - Config dosyasını göster
  show-rules        - Iptables kurallarını göster
  backup            - Kuralları backup'la
  restore [FILE]    - Backup'tan geri yükle
  logs              - Log dosyasını göster
  help              - Bu yardımı göster

${YELLOW}Örnek Kullanım:${NC}
  1. nat-manager init                    # Kurulum
  2. sudo nano /etc/nat-config.yaml      # Config düzenle
  3. nat-manager apply                   # Kuralları uygula
  4. nat-manager test                    # Test et
  5. nat-manager persist                 # Kalıcı yap

${YELLOW}Config Dosyası:${NC}
  $CONFIG_FILE

${YELLOW}Log Dosyası:${NC}
  $LOG_FILE

EOF
}

# Main komut işleyici
main() {
    local cmd="${1:-help}"
    
    # Root check
    if [[ "$cmd" != "help" && "$cmd" != "show-config" && "$cmd" != "show-rules" && "$cmd" != "logs" && "$cmd" != "status" ]]; then
        if [[ $EUID -ne 0 ]]; then
            print_error "Bu komut root olarak çalıştırılmalı!"
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
            print_warning "Kuralları uygulamak için: sudo nat-manager apply"
            ;;
        remove)
            remove_service
            print_warning "Kuralları uygulamak için: sudo nat-manager apply"
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
                echo -e "\n${BLUE}Config Dosyası: $CONFIG_FILE${NC}\n"
                cat "$CONFIG_FILE"
            else
                print_error "Config dosyası bulunamadı"
            fi
            ;;
        show-rules)
            echo -e "\n${BLUE}PREROUTING Kuralları:${NC}"
            iptables -t nat -L PREROUTING -n -v
            echo -e "\n${BLUE}POSTROUTING Kuralları:${NC}"
            iptables -t nat -L POSTROUTING -n -v
            ;;
        backup)
            mkdir -p "$BACKUP_DIR"
            local backup_file="$BACKUP_DIR/rules_$(date +%Y%m%d_%H%M%S).txt"
            iptables-save > "$backup_file"
            print_success "Backup oluşturuldu: $backup_file"
            ;;
        restore)
            local backup_file="${2:-}"
            if [[ -z "$backup_file" ]]; then
                print_error "Backup dosyası belirtmelisin"
                echo "Kullanım: nat-manager restore /path/to/backup.txt"
                exit 1
            fi
            if [[ ! -f "$backup_file" ]]; then
                print_error "Dosya bulunamadı: $backup_file"
                exit 1
            fi
            iptables-restore < "$backup_file"
            print_success "Backup geri yüklendi: $backup_file"
            ;;
        logs)
            if [[ -f "$LOG_FILE" ]]; then
                echo -e "\n${BLUE}Log Dosyası: $LOG_FILE${NC}\n"
                tail -n 20 "$LOG_FILE"
            else
                print_error "Log dosyası bulunamadı"
            fi
            ;;
        help|*)
            print_usage
            ;;
    esac
}

# Çalıştır
main "$@"
