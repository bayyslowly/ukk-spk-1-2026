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
# Perubahan hanya pada isi/tampilan website. Konfigurasi layanan di luar blok ini tetap.
cat > "${WEBROOT}/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="theme-color" content="#4b1025">
  <title>Network Lab | UKK TKJ</title>
  <style>
    :root{--wine:#4b1025;--wine2:#702b43;--cream:#fbf7f4;--ink:#28151c;--muted:#765f67;--line:#eadde1;--white:#fff}
    *{box-sizing:border-box;margin:0;padding:0}
    html{scroll-behavior:smooth}
    body{font-family:Inter,"Segoe UI",Arial,sans-serif;background:var(--cream);color:var(--ink);line-height:1.65}
    a{color:inherit;text-decoration:none}
    .navbar{height:76px;padding:0 7%;display:flex;align-items:center;justify-content:space-between;background:var(--wine);color:white;position:sticky;top:0;z-index:10;box-shadow:0 5px 20px #26091430}
    .logo{font-weight:800;letter-spacing:.5px;font-size:1.1rem}.logo span{color:#e8b8c7}
    .nav-links{display:flex;gap:28px;list-style:none;font-size:.92rem}.nav-links a{color:#f7e9ee;transition:.2s}.nav-links a:hover{color:#e8b8c7}
    .hero{padding:105px 7% 95px;background:radial-gradient(circle at 85% 20%,#873c57 0,transparent 34%),linear-gradient(125deg,#2b0916,#4b1025 58%,#702b43);color:white;min-height:440px;display:flex;flex-direction:column;justify-content:center;align-items:flex-start}
    .eyebrow{text-transform:uppercase;letter-spacing:3px;color:#e8b8c7;font-size:.76rem;font-weight:700;margin-bottom:18px}
    .hero h1{font-size:clamp(2.3rem,5vw,4.3rem);line-height:1.12;max-width:760px;margin-bottom:20px}.hero p{max-width:650px;color:#f0dfe5;font-size:1.05rem}
    .btn{margin-top:28px;padding:12px 22px;border:1px solid #e8b8c7;border-radius:7px;background:#f3dce4;color:var(--wine);font-weight:750;cursor:pointer;transition:.2s}.btn:hover{transform:translateY(-2px);background:white}.status{margin-top:12px;color:#f4dce5;font-size:.9rem;min-height:24px}
    .section{padding:76px 7%;max-width:1200px;margin:auto}.section.alt{max-width:none;background:#f2e9ec}.section h2{font-size:clamp(1.7rem,3vw,2.4rem);color:var(--wine);margin-bottom:12px}.lead{color:var(--muted);max-width:760px}
    .identity{display:grid;grid-template-columns:1.1fr .9fr;gap:24px;margin-top:30px}.panel{background:white;border:1px solid var(--line);border-radius:14px;padding:26px;box-shadow:0 10px 30px #4b10250b}.panel h3{color:var(--wine);margin-bottom:15px}.info{display:flex;justify-content:space-between;gap:16px;padding:10px 0;border-bottom:1px solid var(--line)}.info:last-child{border:0}.info span{color:var(--muted)}.info strong{text-align:right}
    .cards{display:grid;grid-template-columns:repeat(3,1fr);gap:20px;margin-top:30px}.card{background:white;border:1px solid var(--line);border-radius:14px;padding:25px;transition:.2s}.card:hover{transform:translateY(-5px);box-shadow:0 14px 30px #4b102515}.number{font-size:.78rem;color:var(--wine2);font-weight:800;letter-spacing:2px}.card h3{margin:10px 0 7px;color:var(--wine)}.card p{color:var(--muted);font-size:.94rem}
    .topology{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-top:28px}.vlan{border-left:4px solid var(--wine2);background:white;padding:18px;border-radius:8px}.vlan strong{display:block;color:var(--wine)}.vlan small{color:var(--muted)}
    .contact{background:var(--wine);color:white;border-radius:16px;padding:32px}.contact h2{color:white}.contact p{color:#f0dfe5}
    footer{background:#260914;color:#d9c3cb;text-align:center;padding:25px 7%;font-size:.88rem}
    @media(max-width:760px){.navbar{height:auto;min-height:70px;padding:16px 5%;align-items:flex-start;gap:12px;flex-direction:column}.nav-links{gap:16px;flex-wrap:wrap;font-size:.85rem}.hero{padding:78px 6%}.section{padding:58px 6%}.identity,.cards,.topology{grid-template-columns:1fr}.info{font-size:.92rem}}
  </style>
</head>
<body>
  <nav class="navbar">
    <a class="logo" href="#home">NETWORK<span>LAB</span></a>
    <ul class="nav-links"><li><a href="#home">Beranda</a></li><li><a href="#profil">Profil</a></li><li><a href="#layanan">Layanan</a></li><li><a href="#topologi">Topologi</a></li></ul>
  </nav>
  <header class="hero" id="home">
    <div class="eyebrow">UKK TKJ · SPK Paket 1 · 2026</div>
    <h1>Membangun konektivitas, menjaga layanan.</h1>
    <p>Website layanan jaringan yang berjalan pada Ubuntu Server 24.04 dengan integrasi DNS, web server, dan monitoring dalam satu lingkungan jaringan.</p>
    <button class="btn" id="btnCek" type="button">Periksa waktu server</button>
    <p class="status" id="statusOutput" aria-live="polite"></p>
  </header>
  <section class="section" id="profil">
    <h2>Profil Pengelola</h2>
    <p class="lead">Informasi identitas peserta dan lingkungan praktik UKK Teknik Jaringan Komputer dan Telekomunikasi.</p>
    <div class="identity">
      <div class="panel"><h3>Identitas Peserta</h3>
        <div class="info"><span>Nama</span><strong>Bayu Aji Prasetya</strong></div>
        <div class="info"><span>Kelas</span><strong>XII TJKT 1</strong></div>
        <div class="info"><span>Nomor Ujian</span><strong>8</strong></div>
        <div class="info"><span>Sekolah</span><strong>SMK Negeri 1 Banyumas</strong></div>
      </div>
      <div class="panel"><h3>Tentang Proyek</h3><p class="lead">Proyek ini menerapkan layanan jaringan terpusat pada server Ubuntu di VLAN 30. Setiap layanan disiapkan agar dapat diuji dari jaringan sesuai kebijakan akses yang ditentukan.</p></div>
    </div>
  </section>
  <section class="section alt" id="layanan">
    <h2>Layanan Server</h2><p class="lead">Tiga layanan utama yang disiapkan untuk mendukung operasional jaringan laboratorium.</p>
    <div class="cards">
      <article class="card"><div class="number">01 / NAME RESOLUTION</div><h3>DNS Server</h3><p>BIND9 mengelola domain lokal <b>lab-smk.xyz</b> beserta record untuk layanan web dan monitoring.</p></article>
      <article class="card"><div class="number">02 / WEB SERVICE</div><h3>Web Server</h3><p>Nginx menyajikan halaman informasi melalui HTTP dan HTTPS dengan sertifikat self-signed.</p></article>
      <article class="card"><div class="number">03 / OBSERVABILITY</div><h3>Monitoring</h3><p>Netdata menampilkan kondisi server dan menerima data perangkat jaringan melalui SNMP.</p></article>
    </div>
  </section>
  <section class="section" id="topologi">
    <h2>Pembagian Jaringan</h2><p class="lead">Segmentasi jaringan menggunakan VLAN untuk memisahkan akses guru, siswa, dan server.</p>
    <div class="topology">
      <div class="vlan"><strong>VLAN 10 · Guru</strong><small>192.168.10.0/24</small></div>
      <div class="vlan"><strong>VLAN 20 · Siswa</strong><small>192.168.20.0/24</small></div>
      <div class="vlan"><strong>VLAN 30 · Server</strong><small>192.168.30.0/24 · 192.168.30.10</small></div>
    </div>
  </section>
  <section class="section"><div class="contact"><h2>Network Lab</h2><p>Domain layanan: lab-smk.xyz<br>DNS: 192.168.30.10<br>Monitoring: monitor.lab-smk.xyz</p></div></section>
  <footer><p>&copy; 2026 UKK TKJ SPK Paket 1 · SMK Negeri 1 Banyumas</p></footer>
  <script>
    document.addEventListener('DOMContentLoaded',function(){
      const button=document.getElementById('btnCek');
      const output=document.getElementById('statusOutput');
      button.addEventListener('click',function(){output.textContent='Halaman berhasil dimuat. Waktu perangkat: '+new Date().toLocaleString('id-ID');});
      const nav=document.querySelector('.navbar');
      window.addEventListener('scroll',function(){nav.style.boxShadow=window.scrollY>20?'0 5px 20px #26091450':'0 5px 20px #26091430';});
    });
  </script>
</body>
</html>
HTMLEOF

chown -R www-data:www-data "${WEBROOT}"

# --- Buat sertifikat self-signed untuk HTTPS ---
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/${DOMAIN}.key -out /etc/nginx/ssl/${DOMAIN}.crt -subj "/C=ID/ST=JawaTengah/L=Purwokerto/O=SMK/OU=TKJ/CN=${DOMAIN}"

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
