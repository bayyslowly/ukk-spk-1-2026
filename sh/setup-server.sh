#!/bin/bash
#
# =============================================================
#  Script Instalasi & Konfigurasi Server - UKK TKJ SPK PAKET 1
#  Target OS  : Ubuntu Server 24.04 LTS
#  IP Server  : 192.168.30.10/24 (VLAN 30)
#  Layanan    : DNS (bind9), Web (nginx + HTTPS), Monitoring (netdata)
#
#  CATATAN:
#  Script ini TIDAK mengubah konfigurasi IP.
#  IP Static (192.168.30.10/24) harus SUDAH dikonfigurasi manual
#  dan server sudah bisa akses internet SEBELUM script ini dijalankan.
#
#  Cara pakai:
#    sudo chmod +x setup-server.sh
#    sudo ./setup-server.sh
# =============================================================

set -e

# --------- Cek harus dijalankan sebagai root ----------
if [ "$EUID" -ne 0 ]; then
    echo ">> Jalankan script ini dengan sudo/root!"
    echo "   sudo ./setup-server.sh"
    exit 1
fi

# ================= VARIABEL KONFIGURASI =================
IP_ADDRESS="192.168.30.10"    # harus sama dengan IP static yang sudah diset manual
DOMAIN="lab-smk.xyz"
ALLOWED_RECURSION_NETS="192.168.30.0/24; 192.168.10.0/24"   # VLAN 30 & VLAN 10 boleh recursive query (VLAN 20 tidak)
WEBROOT="/var/www/${DOMAIN}"

ROUTER_IP="192.168.30.1"       # IP Router MikroTik (VLAN 30) - SNMP client harus sudah "on"
SNMP_COMMUNITY="public"        # sesuaikan dengan SNMP community string di router MikroTik

echo "======================================================"
echo " Memulai konfigurasi server ${DOMAIN} (${IP_ADDRESS})"
echo "======================================================"

# --------- Cek dulu apakah IP server sudah sesuai & internet nyambung ----------
CURRENT_IP=$(hostname -I | awk '{print $1}')
if [ "$CURRENT_IP" != "$IP_ADDRESS" ]; then
    echo ">> PERINGATAN: IP server saat ini (${CURRENT_IP}) berbeda dengan ${IP_ADDRESS}."
    echo "   Pastikan IP static sudah dikonfigurasi manual sebelum lanjut."
    read -p "   Lanjutkan tetap? (y/n): " confirm
    [ "$confirm" != "y" ] && exit 1
fi

if ! ping -c 2 8.8.8.8 >/dev/null 2>&1; then
    echo ">> ERROR: Server belum terkoneksi ke internet."
    echo "   Selesaikan konfigurasi IP static & gateway secara manual dulu."
    exit 1
fi
echo "   OK - IP: ${CURRENT_IP}, internet: terkoneksi."

# ================= 1. UPDATE SISTEM =================
echo ">> [1/5] Update repository & sistem..."
apt update -y && apt upgrade -y

# ================= 2. INSTALL & KONFIGURASI BIND9 (DNS SERVER) =================
echo ">> [2/5] Install & konfigurasi BIND9 (DNS Server)..."
apt install -y bind9 bind9utils bind9-doc dnsutils

# --- named.conf.options : disable recursion untuk VLAN 20, izinkan VLAN 10 & VLAN 30 ---
cat > /etc/bind/named.conf.options <<EOF
acl "allowed-recursion" {
    ${ALLOWED_RECURSION_NETS};
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
EOF

# --- named.conf.local : definisikan zone ---
cat > /etc/bind/named.conf.local <<EOF
zone "${DOMAIN}" {
    type master;
    file "/etc/bind/db.${DOMAIN}";
};
EOF

# --- File zone / record DNS ---
cat > /etc/bind/db.${DOMAIN} <<EOF
\$TTL    604800
@       IN      SOA     ${DOMAIN}. admin.${DOMAIN}. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ${DOMAIN}.
@       IN      A       ${IP_ADDRESS}
www     IN      A       ${IP_ADDRESS}
monitor IN      A       ${IP_ADDRESS}
EOF

# Cek konfigurasi bind
named-checkconf
named-checkzone ${DOMAIN} /etc/bind/db.${DOMAIN}

systemctl enable named
systemctl restart named
echo "   DNS server aktif untuk zone ${DOMAIN} (www, monitor -> ${IP_ADDRESS})"

# ================= 4. INSTALL & KONFIGURASI NGINX (WEB SERVER) =================
echo ">> [3/5] Install & konfigurasi NGINX (Web Server + HTTPS self-signed)..."
apt install -y nginx openssl

mkdir -p "${WEBROOT}"
mkdir -p /etc/nginx/ssl

# --- Landing Page: index.html ---
cat > "${WEBROOT}/index.html" <<'HTMLEOF'
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
HTMLEOF

# --- style.css ---
cat > "${WEBROOT}/style.css" <<'CSSEOF'
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
CSSEOF

# --- script.js ---
cat > "${WEBROOT}/script.js" <<'JSEOF'
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
JSEOF

chown -R www-data:www-data "${WEBROOT}"

# --- Buat sertifikat self-signed untuk HTTPS ---
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/${DOMAIN}.key \
    -out /etc/nginx/ssl/${DOMAIN}.crt \
    -subj "/C=ID/ST=JawaTengah/L=Purwokerto/O=SMK/OU=TKJ/CN=${DOMAIN}"

# --- Virtual host nginx (HTTP redirect ke HTTPS + HTTPS) ---
cat > /etc/nginx/sites-available/${DOMAIN} <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate     /etc/nginx/ssl/${DOMAIN}.crt;
    ssl_certificate_key /etc/nginx/ssl/${DOMAIN}.key;

    root ${WEBROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/${DOMAIN}
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx
systemctl restart nginx
echo "   Web server aktif: https://${DOMAIN} (self-signed)"

# ================= 5. INSTALL & KONFIGURASI NETDATA (MONITORING) =================
echo ">> [4/5] Install Netdata (Monitoring Server)..."
if ! command -v netdata >/dev/null 2>&1; then
    bash <(curl -Ss https://get.netdata.cloud/kickstart.sh) --non-interactive --stable-channel || \
    apt install -y netdata
fi

# Netdata dibatasi hanya bisa diakses dari localhost saja (127.0.0.1)
# Akses dari luar HARUS lewat reverse proxy nginx (HTTPS) di bawah ini
sed -i "s/# bind to = \*/bind to = 127.0.0.1/" /etc/netdata/netdata.conf 2>/dev/null || \
sed -i "/\[web\]/a\\    bind to = 127.0.0.1" /etc/netdata/netdata.conf

systemctl enable netdata
systemctl restart netdata
echo "   Netdata aktif secara internal di 127.0.0.1:19999 (tidak diekspos langsung)"

# --- Tambah host monitoring: ROUTER (via SNMP) ---
echo ">> Konfigurasi monitoring Router MikroTik (${ROUTER_IP}) via SNMP..."
apt install -y snmp

mkdir -p /etc/netdata/go.d

# Aktifkan plugin SNMP pada go.d
if [ -f /etc/netdata/go.d.conf ]; then
    if grep -q "^\s*snmp:" /etc/netdata/go.d.conf; then
        sed -i "s/^\s*snmp:.*/  snmp: yes/" /etc/netdata/go.d.conf
    else
        echo "  snmp: yes" >> /etc/netdata/go.d.conf
    fi
else
    cat > /etc/netdata/go.d.conf <<EOF
modules:
  snmp: yes
EOF
fi

# Konfigurasi job SNMP untuk host "router" - ambil metrik CPU & Memory
# OID di bawah mengikuti HOST-RESOURCES-MIB (umum didukung RouterOS).
# Cek/uji dulu dengan: snmpwalk -v2c -c ${SNMP_COMMUNITY} ${ROUTER_IP} 1.3.6.1.2.1.25.3.3.1.2
cat > /etc/netdata/go.d/snmp.conf <<EOF
jobs:
  - name: router
    update_every: 10
    hostname: '${ROUTER_IP}'
    community: '${SNMP_COMMUNITY}'
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
EOF

systemctl restart netdata
echo "   Host 'router' (${ROUTER_IP}) ditambahkan ke monitoring via SNMP."
echo "   PENTING: pastikan community string '${SNMP_COMMUNITY}' sesuai konfigurasi SNMP di router,"
echo "   dan OID CPU/Memory di /etc/netdata/go.d/snmp.conf sudah diverifikasi dengan snmpwalk."

# --- Reverse proxy nginx untuk monitor.${DOMAIN} (HTTPS) ---
echo ">> Konfigurasi reverse proxy HTTPS untuk monitor.${DOMAIN}..."
cat > /etc/nginx/sites-available/monitor.${DOMAIN} <<EOF
server {
    listen 80;
    server_name monitor.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name monitor.${DOMAIN};

    ssl_certificate     /etc/nginx/ssl/${DOMAIN}.crt;
    ssl_certificate_key /etc/nginx/ssl/${DOMAIN}.key;

    location / {
        proxy_pass http://127.0.0.1:19999;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Connection "keep-alive";
    }
}
EOF

ln -sf /etc/nginx/sites-available/monitor.${DOMAIN} /etc/nginx/sites-enabled/monitor.${DOMAIN}
nginx -t
systemctl restart nginx
echo "   Monitoring aktif via HTTPS: https://monitor.${DOMAIN}"

# ================= 6. FIREWALL DASAR SERVER (UFW) =================
echo ">> [5/5] Konfigurasi firewall dasar (UFW) pada server..."
apt install -y ufw
ufw allow 22/tcp      # SSH
ufw allow 53          # DNS
ufw allow 80/tcp      # HTTP
ufw allow 443/tcp     # HTTPS
ufw deny 19999/tcp    # Netdata TIDAK diakses langsung dari luar, hanya via proxy nginx
ufw --force enable

echo "======================================================"
echo " SELESAI!"
echo " - DNS   : dig @${IP_ADDRESS} ${DOMAIN}"
echo " - Web   : https://${DOMAIN}  (atau https://${IP_ADDRESS})"
echo " - Monitor: https://monitor.${DOMAIN}   (port 19999 tertutup dari luar)"
echo "   Host di monitoring: 'server' (localhost) & 'router' (${ROUTER_IP} via SNMP)"
echo "   Verifikasi SNMP router: snmpwalk -v2c -c ${SNMP_COMMUNITY} ${ROUTER_IP} system"
echo " Pastikan client (VLAN 10/20/30) mengarahkan DNS ke ${IP_ADDRESS}"
echo " agar domain ${DOMAIN} bisa di-resolve."
echo "======================================================"
