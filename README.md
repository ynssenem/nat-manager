# NAT Manager - Proxmox NAT Configuration Tool

![GitHub release](https://img.shields.io/github/v/release/ynssenem/nat-manager)
![GitHub](https://img.shields.io/github/license/ynssenem/nat-manager)
![Bash](https://img.shields.io/badge/bash-5.0+-blue)
![Proxmox](https://img.shields.io/badge/Proxmox-6.0+-green)
![Status](https://img.shields.io/badge/status-active-success)

A configuration-driven firewall management solution for Proxmox environments that eliminates the complexity of manually managing multiple port forwarding rules.

---

## Demo

```bash
$ sudo nat-manager apply
═══════════════════════════════════════════════════════════
Applying NAT Rules
═══════════════════════════════════════════════════════════
✓ Service: mysql (Port: 3306 → 3306)
✓ Service: rabbitmq (Port: 5672 → 5672)
✓ Service: postgresql (Port: 5432 → 5432)
✓ Total 9 rules applied
```

## 🎯 Problem Statement

Managing multiple NAT (Network Address Translation) rules in Proxmox through command-line interfaces becomes increasingly complex as your infrastructure grows:

- **Day 1:** Single MySQL instance (port 3306)
- **Day 3:** Add RabbitMQ (port 5672)
- **Week 2:** Add PostgreSQL (port 5432), Redis (port 6379)
- **Month 2:** Add MongoDB, additional services...

Each new service requires writing multiple `iptables` commands, creating opportunities for syntax errors and misconfigurations that can impact service availability.

---

## ✅ Solution

NAT Manager centralizes all port forwarding configuration into a single YAML file, allowing you to manage your entire NAT infrastructure declaratively.

### Before NAT Manager
```bash
# For each service, run 6+ commands:
sudo iptables -t nat -A PREROUTING -d 138.201.80.48 -p tcp --dport 3306 \
  -s 192.168.1.100 -j DNAT --to-destination 10.10.20.110:3306
sudo iptables -t nat -A PREROUTING -d 138.201.80.48 -p tcp --dport 3306 \
  -j REJECT --reject-with tcp-reset
sudo iptables -t nat -A POSTROUTING -d 10.10.20.110 -p tcp --dport 3306 \
  -j MASQUERADE
# ... repeat for each service
# ... manage persistent configuration
# ... handle rule conflicts and backups manually
```

### After NAT Manager
```yaml
services:
  mysql:
    public_port: 3306
    container_ip: 10.10.20.110
    container_port: 3306
    allowed_ips:
      - 192.168.1.100
      - 192.168.1.101

  rabbitmq:
    public_port: 5672
    container_ip: 10.10.20.110
    container_port: 5672
    allowed_ips:
      - 192.168.1.100
```

Then simply run:
```bash
sudo nat-manager apply
```

All rules are automatically generated, validated, and persisted.

---

## 🚀 Quick Start

### 1. Installation (30 seconds)

```bash
sudo cp nat-manager.sh /usr/local/bin/nat-manager
sudo chmod +x /usr/local/bin/nat-manager
```

### 2. Initialize Configuration (30 seconds)

```bash
sudo nat-manager init
```

This creates `/etc/nat-config.yaml` with example configuration.

### 3. Edit Configuration (2 minutes)

```bash
sudo nano /etc/nat-config.yaml
```

Define your services:

```yaml
services:
  mysql:
    public_port: 3306
    container_ip: 10.10.20.110
    container_port: 3306
    allowed_ips:
      - 192.168.1.100
      - 192.168.1.101
```

### 4. Apply Rules (1 minute)

```bash
sudo nat-manager apply
```

### 5. Persist Configuration (1 minute)

```bash
sudo nat-manager persist
```

Rules are now persistent across system reboots.

---

## 📋 Configuration Reference

### Basic Structure

```yaml
services:
  service_name:
    public_port: <external_port>
    container_ip: <internal_ip>
    container_port: <internal_port>
    allowed_ips:
      - <ip_address_or_subnet>
      - <ip_address_or_subnet>
```

### Configuration Examples

#### Single IP Access
```yaml
  mysql:
    public_port: 3306
    container_ip: 10.10.20.110
    container_port: 3306
    allowed_ips:
      - 192.168.1.100
```

#### Multiple IP Access
```yaml
  postgresql:
    public_port: 5432
    container_ip: 10.10.20.110
    container_port: 5432
    allowed_ips:
      - 192.168.1.100
      - 192.168.1.101
      - 203.0.113.50
```

#### Subnet Access
```yaml
  redis:
    public_port: 6379
    container_ip: 10.10.20.110
    container_port: 6379
    allowed_ips:
      - 192.168.1.0/24
```

#### Public Access (No Restrictions)
```yaml
  web:
    public_port: 80
    container_ip: 10.10.20.102
    container_port: 80
    allowed_ips:
      - 0.0.0.0/0
```

---

## 📚 Command Reference

### Core Commands

```bash
# Initialize configuration
sudo nat-manager init

# Edit configuration in text editor
sudo nat-manager edit

# Add service interactively
sudo nat-manager add

# Remove service
sudo nat-manager remove

# Apply configuration to system
sudo nat-manager apply

# Test current rules
sudo nat-manager test

# Make rules persistent (survives reboot)
sudo nat-manager persist

# Display system status
sudo nat-manager status
```

### Diagnostic Commands

```bash
# Display current configuration
nat-manager show-config

# Display active iptables rules
nat-manager show-rules

# Display operation logs
nat-manager logs

# Create backup of current rules
sudo nat-manager backup

# Restore rules from backup file
sudo nat-manager restore /var/backups/nat-rules/rules_TIMESTAMP.txt
```

---

## 🔄 Workflow Examples

### Adding a New Service

#### Interactive Method
```bash
sudo nat-manager add

# Prompts:
# Service name: rabbitmq
# Public port: 5672
# Container IP: 10.10.20.110
# Container port: 5672
# Allowed IPs: 192.168.1.100,192.168.1.101

sudo nat-manager apply
```

#### Manual Method
```bash
sudo nano /etc/nat-config.yaml
# Add service configuration
sudo nat-manager apply
```

### Managing Multiple Services

```yaml
services:
  web:
    public_port: 80
    container_ip: 10.10.20.102
    container_port: 80
    allowed_ips:
      - 0.0.0.0/0

  web_ssl:
    public_port: 443
    container_ip: 10.10.20.102
    container_port: 443
    allowed_ips:
      - 0.0.0.0/0

  mysql:
    public_port: 3306
    container_ip: 10.10.20.110
    container_port: 3306
    allowed_ips:
      - 192.168.1.100

  postgresql:
    public_port: 5432
    container_ip: 10.10.20.110
    container_port: 5432
    allowed_ips:
      - 192.168.1.100
      - 203.0.113.50

  redis:
    public_port: 6379
    container_ip: 10.10.20.110
    container_port: 6379
    allowed_ips:
      - 192.168.1.0/24

  rabbitmq:
    public_port: 5672
    container_ip: 10.10.20.110
    container_port: 5672
    allowed_ips:
      - 192.168.1.100
```

Apply all rules:
```bash
sudo nat-manager apply
```

This automatically generates and manages all necessary iptables rules.

---

## 🧪 Testing

### Verify Configuration

```bash
sudo nat-manager test
```

Output displays all active rules and configured services.

### Test Service Connectivity

```bash
# From authorized IP address
telnet 138.201.80.48 3306
# Expected: Connected ✓

# From unauthorized IP address
telnet 138.201.80.48 3306
# Expected: Connection refused ✓
```

### Test Web Services

```bash
curl -I http://138.201.80.48
curl -I https://138.201.80.48
```

---

## 🔒 Security Considerations

### File Permissions

```bash
# Restrict configuration file to root only
sudo chmod 600 /etc/nat-config.yaml

# Secure backup directory
sudo chmod 700 /var/backups/nat-rules/
```

### Best Practices

1. **Principle of Least Privilege:** Only grant access to the minimum required IP addresses
2. **Regular Backups:** Use `nat-manager backup` before making changes
3. **Version Control:** Track configuration changes in Git
4. **Testing:** Always test rules from authorized IPs before deploying

### Monitoring

```bash
# Monitor rule application
sudo nat-manager logs

# Check system status
sudo nat-manager status

# Verify persistent rules
cat /etc/iptables/rules.v4 | grep DNAT
```

---

## 🔧 Troubleshooting

### Rules Not Applied

```bash
# Verify configuration syntax
sudo nat-manager show-config

# Check YAML indentation
# YAML requires consistent spacing (2 spaces per level)
```

### Connectivity Issues

```bash
# Review active rules
sudo nat-manager test

# Verify container is running
lxc-ls -f

# Check container firewall
lxc-attach -n container_name -- iptables -L
```

### Restore Previous Configuration

```bash
# List available backups
ls /var/backups/nat-rules/

# Restore specific backup
sudo nat-manager restore /var/backups/nat-rules/rules_TIMESTAMP.txt

# Verify restoration
sudo nat-manager test
```

---

## 📊 Comparison: Traditional vs NAT Manager

| Feature | Traditional | NAT Manager |
|---------|-----------|------------|
| Add service | 6+ commands | Update config + apply |
| Remove service | Manual cleanup | Update config + apply |
| Syntax validation | Manual | Automatic |
| Centralized management | No | Yes (YAML file) |
| Backup/Restore | Complex | Single command |
| Documentation | External | Config file |
| Persistence handling | Manual | Automatic |
| Rule conflicts | Possible | Prevented |
| Time to add service | 10 minutes | 2 minutes |

---

## 🏗️ Architecture

### Rule Generation Flow

```
Configuration File (YAML)
         ↓
    Parsing Engine
         ↓
    Rule Validation
         ↓
    iptables Application
         ↓
    Persistence Layer
         ↓
    Active Rules
```

### Generated Rules by Service

For each configured service, NAT Manager generates:

1. **PREROUTING Rule (DNAT):** Routes external traffic to internal container
2. **POSTROUTING Rule (MASQUERADE):** Manages response traffic
3. **Optional REJECT Rules:** Restricts access to authorized IPs

---

## 📂 Files and Locations

| File/Directory | Purpose |
|---|---|
| `/usr/local/bin/nat-manager` | Executable script |
| `/etc/nat-config.yaml` | Configuration file |
| `/var/log/nat-manager.log` | Operation logs |
| `/var/backups/nat-rules/` | Backup directory |
| `/etc/iptables/rules.v4` | Persistent IPv4 rules |

---

## 🔄 Integration Examples

### Systemd Automation

Create `/etc/systemd/system/nat-manager-apply.service`:

```ini
[Unit]
Description=NAT Manager Rule Application
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nat-manager apply
User=root

[Install]
WantedBy=multi-user.target
```

Enable on boot:
```bash
sudo systemctl enable nat-manager-apply.service
```

### Git Version Control

```bash
cd /etc
git init
git add nat-config.yaml
git commit -m "Initial NAT configuration"

# Track all changes
git log nat-config.yaml
```

### Automated Backups

```bash
# Add to crontab
sudo crontab -e

# Daily backup at 2 AM
0 2 * * * /usr/local/bin/nat-manager backup
```

---

## 📝 Change Log

### Version 1.0
- Initial release
- Support for DNAT port forwarding
- YAML-based configuration
- Automatic persistence
- Backup and restore functionality
- Service management (add/remove)

---

## 🤝 Contributing

Report issues or suggest improvements by providing:
- Configuration file content
- Error messages
- Expected vs actual behavior
- System information (Proxmox version, OS)

---

## 📄 License

This tool is provided as-is for use in Proxmox environments.

---

## 🆘 Support

### Common Issues and Solutions

**Issue:** Configuration not applied
```bash
sudo nat-manager apply
sudo nat-manager test
```

**Issue:** Rules lost after reboot
```bash
sudo nat-manager persist
```

**Issue:** Service connectivity failures
```bash
sudo nat-manager test
# Review output and verify IP addresses
```

---

## ✨ Key Benefits

- **Simplified Management:** Single configuration file for all rules
- **Error Prevention:** Automatic validation and syntax checking
- **Scalability:** Easily manage dozens of services
- **Consistency:** Standardized rule generation
- **Recoverability:** Built-in backup and restore
- **Transparency:** Configuration documents your infrastructure
- **Efficiency:** Reduce time spent on manual configuration

---

## 🎓 Best Practices

1. **Always backup before changes:**
   ```bash
   sudo nat-manager backup
   ```

2. **Test after modifications:**
   ```bash
   sudo nat-manager test
   ```

3. **Use meaningful service names:**
   ```yaml
   web_production:      # Good
   ws1:                 # Avoid
   ```

4. **Document special requirements:**
   ```yaml
   # Database server - restricted access
   # Only allow from app servers
   mysql:
     allowed_ips:
       - 192.168.1.50   # App server 1
       - 192.168.1.51   # App server 2
   ```

5. **Review logs regularly:**
   ```bash
   sudo nat-manager logs
   ```

---

## 📞 Getting Help

For detailed information about specific commands:

```bash
nat-manager help
nat-manager show-config
nat-manager show-rules
nat-manager logs
```

For system-level diagnostics:

```bash
sudo iptables -t nat -L -n -v
sudo nat-manager status
```

---

**NAT Manager - Infrastructure as Code for Proxmox Networking**
