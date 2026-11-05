# Setup Server Manual — UKK TKJ 2026 SPK Paket 1
## Ubuntu Server 24.04 LTS — Tanpa Bash Script (Full Manual)

Server ini akan menjalankan 3 layanan: **DNS (bind9)**, **Web (nginx + HTTPS)**, dan **Monitoring (netdata + SNMP router)**, sesuai topologi VLAN 30 (`192.168.30.10/24`).

---

## 📋 Daftar Isi
1. [Konfigurasi IP Static](#1-konfigurasi-ip-static)
2. [Update Sistem](#2-update-sistem)
3. [Instalasi & Konfigurasi DNS Server (bind9)](#3-instalasi--konfigurasi-dns-server-bind9)
4. [Instalasi & Konfigurasi Web Server (nginx + HTTPS)](#4-instalasi--konfigurasi-web-server-nginx--https)
5. [Instalasi & Konfigurasi Monitoring (netdata + SNMP)](#5-instalasi--konfigurasi-monitoring-netdata--snmp)
6. [Firewall Server (UFW)](#6-firewall-server-ufw)
7. [Verifikasi Akhir](#7-verifikasi-akhir)

---

## 1. Konfigurasi IP Static

Masuk ke server (via console/VM), lalu edit file netplan:

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

Cek dulu nama interface yang terpasang:

```bash
ip a
```

Isi/edit file netplan menjadi:

```yaml
network:
  version: 2
  ethernets:
    ens33:                      # ganti sesuai nama interface asli hasil 'ip a'
      dhcp4: no
      addresses:
        - 192.168.30.10/24
      routes:
        - to: default
          via: 192.168.30.1     # gateway VLAN 30 dari router MikroTik
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]   # sementara DNS publik dulu
```

Simpan file (`Ctrl+O`, `Enter`, `Ctrl+X`), lalu terapkan:

```bash
sudo chmod 600 /etc/netplan/50-cloud-init.yaml
sudo netplan apply
```

Verifikasi IP dan koneksi internet **sebelum lanjut ke tahap berikutnya**:

```bash
ip a                     # pastikan 192.168.30.10/24 aktif di interface
ping -c 4 192.168.30.1   # tes gateway (Router MikroTik)
ping -c 4 8.8.8.8        # tes internet
```

✅ Pastikan `ping 8.8.8.8` berhasil (ada reply, bukan timeout) sebelum melanjutkan.

---

## 2. Update Sistem

```bash
sudo apt update -y
sudo apt upgrade -y
```

---

## 3. Instalasi & Konfigurasi DNS Server (bind9)

### 3.1 Install bind9

```bash
sudo apt install -y bind9 bind9utils bind9-doc dnsutils
```

### 3.2 Konfigurasi `named.conf.options`

Buka file:

```bash
sudo nano /etc/bind/named.conf.options
```

Ganti seluruh isinya menjadi:

```
acl "allowed-recursion" {
    192.168.30.0/24;
    192.168.10.0/24;
    localhost;
};

options {
    directory "/var/cache/bind";

    recursion yes;
    allow-recursion { allowed-recursion; };
    // VLAN 20 (192.168.20.0/24) tidak termasuk allowed-recursion -> otomatis ditolak

    listen-on { any; };
    listen-on-v6 { any; };

    dnssec-validation auto;

    forwarders {
        8.8.8.8;
    };
};
```

Simpan (`Ctrl+O`, `Enter`, `Ctrl+X`).

### 3.3 Konfigurasi `named.conf.local` (Definisi Zone)

```bash
sudo nano /etc/bind/named.conf.local
```

Isi:

```
zone "lab-smk.xyz" {
    type master;
    file "/etc/bind/db.lab-smk.xyz";
};
```

Simpan.

### 3.4 Buat File Zone / Record DNS

```bash
sudo nano /etc/bind/db.lab-smk.xyz
```

Isi:

```
$TTL    604800
@       IN      SOA     lab-smk.xyz. admin.lab-smk.xyz. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      lab-smk.xyz.
@       IN      A       192.168.30.10
www     IN      A       192.168.30.10
monitor IN      A       192.168.30.10
```

Simpan.

### 3.5 Cek Konfigurasi & Restart Service

```bash
sudo named-checkconf
sudo named-checkzone lab-smk.xyz /etc/bind/db.lab-smk.xyz
```

Jika muncul `OK`, lanjutkan:

```bash
sudo systemctl enable named
sudo systemctl restart named
sudo systemctl status named
```

### 3.6 Tes DNS

```bash
dig @192.168.30.10 lab-smk.xyz
dig @192.168.30.10 monitor.lab-smk.xyz
```

Tes recursion (domain luar). Dari server/VLAN 30 dan Guru/VLAN 10 harus berhasil, sedangkan dari Siswa/VLAN 20 harus **REFUSED**:

```bash
dig @192.168.30.10 google.com
```

---

## 4. Instalasi & Konfigurasi Web Server (nginx + HTTPS)

### 4.1 Install nginx & openssl

```bash
sudo apt install -y nginx openssl
```

### 4.2 Buat Folder Website

```bash
sudo mkdir -p /var/www/lab-smk.xyz
sudo mkdir -p /etc/nginx/ssl
```

### 4.3 Buat `index.html`

```bash
sudo nano /var/www/lab-smk.xyz/index.html
```

Isi:

```html
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SPK Paket 1 - Lab SMK</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <nav class="navbar">
        <div class="logo">Lab-SMK.xyz</div>
        <ul class="nav-links">
            <li><a href="#home">Home</a></li>
            <li><a href="#tentang">Tentang</a></li>
            <li><a href="#layanan">Layanan</a></li>
            <li><a href="#kontak">Kontak</a></li>
        </ul>
    </nav>

    <header id="home" class="hero">
        <h1>Selamat Datang di Server SPK Paket 1</h1>
        <p>Landing page ini disajikan oleh Nginx pada Ubuntu Server 24.04</p>
        <button id="btnCek" class="btn">Cek Status Server</button>
        <p id="statusOutput"></p>
    </header>

    <section id="tentang" class="section">
        <h2>Tentang Topologi</h2>
        <p>Server ini merupakan bagian dari topologi UKK TKJ SPK Paket 1, dengan
        layanan DNS, Web Server, dan Monitoring yang berjalan pada satu VM Ubuntu/Debian
        di VLAN 30 (192.168.30.10/24).</p>
    </section>

    <section id="layanan" class="section alt">
        <h2>Layanan Server</h2>
        <div class="cards">
            <div class="card">
                <h3>DNS Server</h3>
                <p>BIND9 - domain lab-smk.xyz</p>
            </div>
            <div class="card">
                <h3>Web Server</h3>
                <p>Nginx + HTTPS Self-Signed</p>
            </div>
            <div class="card">
                <h3>Monitoring</h3>
                <p>Netdata - monitor.lab-smk.xyz</p>
            </div>
        </div>
    </section>

    <section id="kontak" class="section">
        <h2>Kontak</h2>
        <p>Admin Lab SMK &mdash; admin@lab-smk.xyz</p>
    </section>

    <footer>
        <p>&copy; 2026 UKK TKJ - SPK Paket 1</p>
    </footer>

    <script src="script.js"></script>
</body>
</html>
```

Simpan.

### 4.4 Buat `style.css`

```bash
sudo nano /var/www/lab-smk.xyz/style.css
```

Isi:

```css
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
    font-family: 'Segoe UI', Arial, sans-serif;
}

body {
    background-color: #f4f6f8;
    color: #222;
    scroll-behavior: smooth;
}

.navbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    background-color: #0f172a;
    padding: 16px 40px;
    position: sticky;
    top: 0;
    z-index: 10;
}

.navbar .logo {
    color: #38bdf8;
    font-weight: bold;
    font-size: 1.3rem;
}

.nav-links {
    list-style: none;
    display: flex;
    gap: 24px;
}

.nav-links a {
    color: #e2e8f0;
    text-decoration: none;
    font-weight: 500;
    transition: color 0.2s;
}

.nav-links a:hover {
    color: #38bdf8;
}

.hero {
    background: linear-gradient(135deg, #0f172a, #1e3a8a);
    color: white;
    text-align: center;
    padding: 100px 20px;
}

.hero h1 {
    font-size: 2.4rem;
    margin-bottom: 12px;
}

.hero p {
    margin-bottom: 24px;
    color: #cbd5e1;
}

.btn {
    background-color: #38bdf8;
    color: #0f172a;
    border: none;
    padding: 12px 28px;
    border-radius: 6px;
    font-weight: bold;
    cursor: pointer;
    transition: transform 0.2s, background-color 0.2s;
}

.btn:hover {
    background-color: #0ea5e9;
    transform: translateY(-2px);
}

#statusOutput {
    margin-top: 16px;
    font-weight: bold;
    color: #4ade80;
}

.section {
    padding: 60px 40px;
    max-width: 900px;
    margin: 0 auto;
}

.section.alt {
    background-color: #eef2f6;
    max-width: 100%;
}

.section h2 {
    margin-bottom: 16px;
    color: #0f172a;
}

.cards {
    display: flex;
    gap: 20px;
    flex-wrap: wrap;
    justify-content: center;
    margin-top: 20px;
}

.card {
    background: white;
    border-radius: 10px;
    padding: 24px;
    width: 220px;
    box-shadow: 0 4px 10px rgba(0,0,0,0.08);
    text-align: center;
    transition: transform 0.2s;
}

.card:hover {
    transform: translateY(-5px);
}

footer {
    text-align: center;
    padding: 20px;
    background-color: #0f172a;
    color: #94a3b8;
}
```

Simpan.

### 4.5 Buat `script.js`

```bash
sudo nano /var/www/lab-smk.xyz/script.js
```

Isi:

```javascript
document.addEventListener('DOMContentLoaded', function () {
    const btn = document.getElementById('btnCek');
    const output = document.getElementById('statusOutput');

    btn.addEventListener('click', function () {
        const now = new Date();
        output.textContent = 'Server aktif - waktu cek: ' + now.toLocaleString('id-ID');
    });

    // Efek scroll aktif pada navbar
    const navbar = document.querySelector('.navbar');
    window.addEventListener('scroll', function () {
        if (window.scrollY > 50) {
            navbar.style.boxShadow = '0 2px 8px rgba(0,0,0,0.3)';
        } else {
            navbar.style.boxShadow = 'none';
        }
    });
});
```

Simpan.

### 4.6 Set Kepemilikan File

```bash
sudo chown -R www-data:www-data /var/www/lab-smk.xyz
```

### 4.7 Buat Sertifikat SSL Self-Signed

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/lab-smk.xyz.key -out /etc/nginx/ssl/lab-smk.xyz.crt -subj "/C=ID/ST=JawaTengah/L=Purwokerto/O=SMK/OU=TKJ/CN=lab-smk.xyz"
```

### 4.8 Buat Virtual Host Nginx (HTTP → HTTPS)

```bash
sudo nano /etc/nginx/sites-available/lab-smk.xyz
```

Isi:

```nginx
server {
    listen 80;
    server_name lab-smk.xyz www.lab-smk.xyz;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name lab-smk.xyz www.lab-smk.xyz;

    ssl_certificate     /etc/nginx/ssl/lab-smk.xyz.crt;
    ssl_certificate_key /etc/nginx/ssl/lab-smk.xyz.key;

    root /var/www/lab-smk.xyz;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Simpan.

### 4.9 Aktifkan Virtual Host & Hapus Default

```bash
sudo ln -sf /etc/nginx/sites-available/lab-smk.xyz /etc/nginx/sites-enabled/lab-smk.xyz
sudo rm -f /etc/nginx/sites-enabled/default
```

### 4.10 Cek Konfigurasi & Restart Nginx

```bash
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx
```

### 4.11 Tes Web Server

```bash
curl -k https://lab-smk.xyz
```

Atau buka browser (dari client yang DNS-nya sudah mengarah ke 192.168.30.10): `https://lab-smk.xyz`

---

## 5. Instalasi & Konfigurasi Monitoring (netdata + SNMP)

### 5.1 Install Netdata

```bash
bash <(curl -Ss https://get.netdata.cloud/kickstart.sh) --non-interactive --stable-channel
```

Jika gagal (misal karena jaringan terbatas), install via apt:

```bash
sudo apt install -y netdata
```

### 5.2 Batasi Netdata Hanya Bisa Diakses dari Localhost

```bash
sudo nano /etc/netdata/netdata.conf
```

Cari bagian `[web]`, tambahkan/ubah baris:

```
[web]
    bind to = 127.0.0.1
```

Simpan.

```bash
sudo systemctl enable netdata
sudo systemctl restart netdata
```

### 5.3 Install Tools SNMP (untuk verifikasi manual)

```bash
sudo apt install -y snmp
```

### 5.4 Aktifkan Plugin SNMP pada Netdata

```bash
sudo nano /etc/netdata/go.d.conf
```

Pastikan ada baris berikut di dalam `modules:`:

```yaml
modules:
  snmp: yes
```

Simpan.

### 5.5 Buat Konfigurasi Job SNMP untuk Monitoring Router

```bash
sudo mkdir -p /etc/netdata/go.d
sudo nano /etc/netdata/go.d/snmp.conf
```

Isi (sesuaikan `community` dengan yang dikonfigurasi di router MikroTik):

```yaml
jobs:
  - name: router
    update_every: 10
    hostname: '192.168.30.1'
    community: 'public'
    options:
      port: 161
      retries: 1
    charts:
      - table:
          - name: cpu_load
            title: 'Router CPU Load'
            units: '%'
            family: 'cpu'
            type: line
            dimensions:
              - oid: 1.3.6.1.2.1.25.3.3.1.2.1
                name: cpu
                algorithm: absolute
      - table:
          - name: memory_usage
            title: 'Router Memory Used'
            units: 'bytes'
            family: 'memory'
            type: area
            dimensions:
              - oid: 1.3.6.1.2.1.25.2.3.1.6.65536
                name: memory_used
                algorithm: absolute
```

Simpan.

⚠️ **Sebelum lanjut, verifikasi dulu OID benar-benar didukung router:**

```bash
snmpwalk -v2c -c public 192.168.30.1 1.3.6.1.2.1.25.3.3.1.2
snmpwalk -v2c -c public 192.168.30.1 1.3.6.1.2.1.25.2.3.1.6
```

Jika index OID berbeda (tergantung versi RouterOS), sesuaikan angka di akhir OID pada `snmp.conf` sebelum restart.

```bash
sudo systemctl restart netdata
```

### 5.6 Buat Reverse Proxy HTTPS untuk Netdata (`monitor.lab-smk.xyz`)

```bash
sudo nano /etc/nginx/sites-available/monitor.lab-smk.xyz
```

Isi:

```nginx
server {
    listen 80;
    server_name monitor.lab-smk.xyz;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name monitor.lab-smk.xyz;

    ssl_certificate     /etc/nginx/ssl/lab-smk.xyz.crt;
    ssl_certificate_key /etc/nginx/ssl/lab-smk.xyz.key;

    location / {
        proxy_pass http://127.0.0.1:19999;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Connection "keep-alive";
    }
}
```

Simpan.

```bash
sudo ln -sf /etc/nginx/sites-available/monitor.lab-smk.xyz /etc/nginx/sites-enabled/monitor.lab-smk.xyz
sudo nginx -t
sudo systemctl restart nginx
```

### 5.7 Tes Monitoring

```bash
curl -k https://monitor.lab-smk.xyz
snmpwalk -v2c -c public 192.168.30.1 system
```

Atau buka browser: `https://monitor.lab-smk.xyz` — pastikan muncul dashboard Netdata dengan host **server** (localhost) dan **router** (via SNMP).

---

## 6. Firewall Server (UFW)

```bash
sudo apt install -y ufw
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 53          # DNS
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw deny 19999/tcp    # Netdata TIDAK boleh diakses langsung dari luar
sudo ufw --force enable
```

Cek status:

```bash
sudo ufw status verbose
```

---

## 7. Verifikasi Akhir

Jalankan semua perintah berikut untuk memastikan semua layanan berjalan normal:

```bash
sudo systemctl status named       # DNS Server
sudo systemctl status nginx       # Web Server
sudo systemctl status netdata     # Monitoring
sudo ufw status                   # Firewall

dig @192.168.30.10 lab-smk.xyz
dig @192.168.30.10 monitor.lab-smk.xyz
curl -k https://lab-smk.xyz
curl -k https://monitor.lab-smk.xyz
snmpwalk -v2c -c public 192.168.30.1 system
```

**Checklist hasil akhir:**

- [ ] IP Static `192.168.30.10/24` aktif & bisa akses internet
- [ ] `dig lab-smk.xyz` mengembalikan `192.168.30.10`
- [ ] `dig` dari VLAN 20 untuk domain luar (recursive) **ditolak** (status: REFUSED), sedangkan dari VLAN 10 dan VLAN 30 **berhasil**
- [ ] `https://lab-smk.xyz` menampilkan landing page (index.html, style.css, script.js)
- [ ] `https://monitor.lab-smk.xyz` menampilkan dashboard Netdata (HTTPS, bukan HTTP)
- [ ] Dashboard monitoring menampilkan 2 host: **server** dan **router** (CPU/Memory)
- [ ] Port 19999 tidak bisa diakses langsung dari luar (`ufw deny`)
- [ ] Firewall UFW aktif dengan port 22/53/80/443 terbuka

---

**Selesai!** Semua layanan (DNS, Web, Monitoring) sudah berjalan secara manual tanpa bash script, sesuai topologi SPK Paket 1.
