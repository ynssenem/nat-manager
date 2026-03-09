# Proxmox NAT Configuration - SIMPLIFIED
# Basit ve temiz. Yalnızca gerekli alanlar.
#
# Otomatik olarak ayarlanır (değiştirmek istersen aşağıya yaz):
#   interface: vmbr0 (default)
#   container_subnet: 10.10.10.0/24 (auto-detect)
#   egress_interface: vmbr0 (default)

services:
  web_http:
    public_ip: 80.*.*.* -> your ip
    public_port: 80
    container_ip: 10.10.10.100
    container_port: 80
    # interface: vmbr0                    # Optional - değiştir istersen
    # container_subnet: 10.10.10.0/24    # Optional - değiştir istersen
    # egress_interface: vmbr0             # Optional - değiştir istersen

  web_https:
    public_ip: 80.*.*.* -> your ip
    public_port: 443
    container_ip: 10.10.10.100
    container_port: 443

  mysql:
    public_ip: 80.*.*.* -> your ip
    public_port: 3306
    container_ip: 10.10.10.110
    container_port: 3306
    allowed_ips:
      - 104.247.164.228

  dokploy_panel:
    public_ip: 88.99.130.158
    public_port: 3000
    container_ip: 10.10.10.111
    container_port: 3000
    allowed_ips:
      - 104.247.164.228

  # ÖRNEK: vmbr1'de farklı subnet
  # app_on_vmbr1:
  #   public_ip: 10.20.30.40
  #   public_port: 8080
  #   container_ip: 10.20.30.112
  #   container_port: 8080
  #   interface: vmbr1                       # Override et
  #   container_subnet: 10.20.30.0/24       # Override et
  #   egress_interface: vmbr0                # Internet çıkışı vmbr0'dan

  # rabbitmq:
  #   public_ip: 80.*.*.* -> your ip
  #   public_port: 5672
  #   container_ip: 10.10.10.110
  #   container_port: 5672
  #   allowed_ips:
  #     - 104.247.164.228
