# 🚀 NAT Manager - 5 Dakikalık Başlangıç

## Probleminiz

```
Dün: MySQL (3306)
Bugün: RabbitMQ (5672) ekleyelim mi?
Yarın: PostgreSQL, Redis, MongoDB...

❌ Her defasında CLI komut yazmanız lazım
❌ Syntax hatası yaparsınız
❌ Kurallar çakışır
✅ Çözüm: Bir config dosyası → Otomatik yönetim
```

---

## ⚡ 5 Dakikalık Kurulum

### 1️⃣ Script'i Kur (30 saniye)

```bash
sudo cp nat-manager.sh /usr/local/bin/nat-manager
sudo chmod +x /usr/local/bin/nat-manager
```

### 2️⃣ İlklendir (30 saniye)

```bash
sudo nat-manager init
```

✓ `/etc/nat-config.yaml` dosyası oluşturuldu

### 3️⃣ Config Dosyasını Düzenle (2 dakika)

```bash
sudo nano /etc/nat-config.yaml
```

**Şu şekilde yapacak:**

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

✓ Kaydet (Ctrl+X, Y, Enter)

### 4️⃣ Kuralları Uygula (1 dakika)

```bash
sudo nat-manager apply
```

Çıktı:
```
═══════════════════════════════════════════════════════════
NAT Kuralları Uygulanıyor
═══════════════════════════════════════════════════════════
⚠ Service: mysql (Port: 3306 → 3306)
  → IP: 192.168.1.100
✓ DNAT kuralı eklendi
  → IP: 192.168.1.101
✓ DNAT kuralı eklendi
  → Diğer IP'leri reddet
✓ REJECT kuralı eklendi
  → MASQUERADE
✓ MASQUERADE kuralı eklendi

✓ Toplam 7 kural uygulandı!
```

### 5️⃣ Kalıcı Yap (1 dakika)

```bash
sudo nat-manager persist
```

✓ **Bitti!** Reboot'dan sonra da çalışacak.

---

## ✅ Kontrol Et

```bash
# Test et
sudo nat-manager test

# Durumu gör
sudo nat-manager status

# Rules'ları gör
nat-manager show-rules
```

Dışardan test:
```bash
telnet 138.201.80.48 3306
# İzin verilen IP'den: Connected ✓
# Diğer IP'den: Connection refused ✓
```

---

## 🎯 Yarın RabbitMQ Eklemek İstersen

**Eski Yol:**
```bash
# 5-6 komut yazman lazım...
sudo iptables -t nat -A PREROUTING ...
sudo iptables -t nat -A PREROUTING ...
sudo iptables -t nat -A POSTROUTING ...
# ... ve persist et
```

**Yeni Yol:**

### Option A: Interactive (Daha Kolay)

```bash
sudo nat-manager add
```

Menü:
```
Service adı: rabbitmq
Public port: 5672
Container IP: 10.10.20.110
Container port: 5672
Allowed IPs: 192.168.1.100,192.168.1.101
```

Sonra:
```bash
sudo nat-manager apply
```

### Option B: Manual Edit (Daha Kontrollü)

```bash
sudo nano /etc/nat-config.yaml
```

Ekle:
```yaml
  rabbitmq:
    public_port: 5672
    container_ip: 10.10.20.110
    container_port: 5672
    allowed_ips:
      - 192.168.1.100
      - 192.168.1.101
```

Sonra:
```bash
sudo nat-manager apply
```

**Kaç satır CLI komut yazdın? SIFIR!** 🎉

---

## 📋 Başlıca Komutlar

```bash
# İlklendir
sudo nat-manager init

# Config düzenle (nano editor)
sudo nat-manager edit

# Servis ekle (interactive menu)
sudo nat-manager add

# Servis sil
sudo nat-manager remove

# Config'den kuralları oluştur
sudo nat-manager apply

# Kuralları test et
sudo nat-manager test

# Reboot'dan sonra da çalışsın
sudo nat-manager persist

# Durumu gör
sudo nat-manager status

# Config dosyasını gör
nat-manager show-config

# İptables kurallarını gör
nat-manager show-rules

# Backup al
sudo nat-manager backup

# Backup'tan geri yükle
sudo nat-manager restore /var/backups/nat-rules/rules_ESKI.txt

# Log'ları gör
nat-manager logs
```

---

## 🔥 Avantajları

| Özellik | Eski (CLI) | Yeni (NAT Manager) |
|---------|----------|------------------|
| MySQL ekle | 6 satır komut | config + apply |
| RabbitMQ ekle | 6 satır komut | config + apply |
| PostgreSQL ekle | 6 satır komut | config + apply |
| Syntax hatası | ✓ Olabilir | ✗ Config validated |
| Kuralları geri dön | Zor | `nat-manager restore` |
| Reboot sonrası | Manual persist lazım | Otomatik |
| Merkezi yönetim | ✗ | ✓ Bir dosya |
| Dokumentasyon | ✗ | ✓ Config dosyası = doku |

---

## 📊 Örnek Config (Tüm Servisler)

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

  mongodb:
    public_port: 27017
    container_ip: 10.10.20.110
    container_port: 27017
    allowed_ips:
      - 192.168.1.100

  api_server:
    public_port: 8080
    container_ip: 10.10.20.111
    container_port: 8080
    allowed_ips:
      - 0.0.0.0/0  # Herkes erişebilir
```

**Sonra:**
```bash
sudo nat-manager apply
```

**Iptables'e 24 kural yazılmıştır.** (Otomatik!)

---

## 🔒 Güvenlik

```bash
# Config dosyası sadece root okunabilir
sudo chmod 600 /etc/nat-config.yaml

# Backup'larını güvenli yerde tut
sudo chmod 700 /var/backups/nat-rules/

# Sensitive bilgileri sakla
sudo chattr +i /etc/nat-config.yaml  # Değiştirilemesin
```

---

## 🚨 Hızlı Sorun Giderme

### Kurallar uygulanmadı mı?

```bash
sudo nat-manager test
```

### Config syntax hatalı mı?

```bash
nat-manager show-config
# Boşlukları kontrol et (YAML indentation önemli!)
```

### Eski kurallardan geri dönmek istiyorum?

```bash
sudo nat-manager backup          # Yeni backup
sudo nat-manager restore /eski/rules.txt
```

### Kurallar reboot'dan sonra kayboldu mu?

```bash
sudo nat-manager persist
```

---

## 📚 Şu Şekilde Başla

### Step 1: Kurulum (1 min)
```bash
sudo cp nat-manager.sh /usr/local/bin/nat-manager
sudo chmod +x /usr/local/bin/nat-manager
sudo nat-manager init
```

### Step 2: Config (2 min)
```bash
sudo nano /etc/nat-config.yaml
# MySQL ekle
```

### Step 3: Uygula (1 min)
```bash
sudo nat-manager apply
sudo nat-manager persist
```

### Step 4: Test (1 min)
```bash
sudo nat-manager test
telnet 138.201.80.48 3306
```

**Toplam: 5 dakika ✓**

---

## ⏰ Bundan Sonra...

**Yarın RabbitMQ eklemek istersen:**
```bash
# 30 saniye
sudo nano /etc/nat-config.yaml
# (rabbitmq ekle)
sudo nat-manager apply
```

**Bir hafta sonra PostgreSQL eklemek istersen:**
```bash
# 1 dakika
sudo nat-manager add
# (postgresql bilgilerini gir)
sudo nat-manager apply
```

**Bir ay sonra Redis kaldırmak istersen:**
```bash
# 30 saniye
sudo nat-manager remove
# (redis yazıp sil)
sudo nat-manager apply
```

---

## 🎁 CLI Kaosa Hoşça Kalınsın! 👋

```bash
# Eski:
# iptables -t nat -A ... (6 komut) × 10 servis = 60 komut = Kaos!

# Yeni:
# config + nat-manager apply = Düzeni
```

Başlayın! 🚀
