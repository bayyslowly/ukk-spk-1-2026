#!/bin/bash
#
# =============================================================
#  UKK TKJ 2026 - SPK PAKET 1
#  Setup Server Ubuntu 24.04 LTS
#  Layanan: BIND9 DNS, Nginx HTTPS, Netdata + SNMP, UFW
#
#  IP Server : 192.168.30.10/24 (VLAN 30)
#  Domain    : lab-smk.xyz
#
#  PENTING:
#  - Konfigurasi IP static dilakukan MANUAL sebelum menjalankan script.
#  - Pastikan server dapat ping gateway 192.168.30.1 dan internet 8.8.8.8.
#  - Sesuaikan identitas website pada bagian DATA di bawah.
#  - HTTPS menggunakan sertifikat self-signed; browser akan memberi
#    peringatan sampai sertifikat CA/sertifikat lab dipercaya client.
# =============================================================

set -Eeuo pipefail

# ================= VARIABEL KONFIGURASI =================
IP_ADDRESS="192.168.30.10"
ROUTER_IP="192.168.30.1"
DOMAIN="lab-smk.xyz"
WEBROOT="/var/www/${DOMAIN}"
SNMP_COMMUNITY="public"

# DNS recursion hanya untuk VLAN Guru dan Server sesuai skema awal.
# Client VLAN Siswa tetap dapat query record authoritative lab-smk.xyz.
ALLOWED_RECURSION_NETS="192.168.10.0/24; 192.168.30.0/24"

# Identitas yang tampil di landing page (ubah sesuai kebutuhan).
STUDENT_NAME="Bayu Aji Prasetya"
STUDENT_CLASS="XII TJKT 1"
SCHOOL_NAME="SMK Negeri 1 Banyumas"
EXAM_NUMBER="8"

# ================= FUNGSI BANTUAN =================
log() { echo -e "\n\033[1;36m[UKK SERVER]\033[0m $*"; }
die() { echo -e "\n\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
trap 'echo -e "\n\033[1;31mScript berhenti pada baris ${LINENO}. Periksa pesan error di atas.\033[0m" >&2' ERR

# Harus root
if [[ "${EUID}" -ne 0 ]]; then
    die "Jalankan dengan: sudo ./setup-server.sh"
fi

# Pastikan IP server benar-benar terpasang, tidak bergantung urutan hostname -I.
if ! ip -o -4 addr show | awk '{print $4}' | grep -q "^${IP_ADDRESS}/"; then
    die "IP ${IP_ADDRESS} tidak ditemukan. Konfigurasikan IP static VLAN 30 terlebih dahulu."
fi

# Pastikan gateway dan internet tersedia.
if ! ping -c 2 -W 3 "${ROUTER_IP}" >/dev/null 2>&1; then
    die "Gateway ${ROUTER_IP} tidak dapat dijangkau. Periksa VLAN 30 dan routing."
fi

if ! ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
    die "Internet belum tersedia (ping 8.8.8.8 gagal). Periksa gateway/NAT Router."
fi

log "IP ${IP_ADDRESS} terdeteksi; gateway dan koneksi internet berhasil."

# ================= 1. UPDATE SISTEM =================
log "[1/5] Update sistem dan atur timezone WIB..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
timedatectl set-timezone Asia/Jakarta

# SSH berguna untuk administrasi jarak jauh. Jika tidak diperlukan, port 22
# dapat dihapus dari aturan UFW di bagian firewall.
log "Memasang OpenSSH Server..."
apt-get install -y openssh-server curl ca-certificates
systemctl enable --now ssh

# ================= 2. BIND9 DNS SERVER =================
log "[2/5] Instalasi dan konfigurasi BIND9..."
apt-get install -y bind9 bind9utils bind9-doc dnsutils

cat > /etc/bind/named.conf.options <<EOF
acl "allowed-recursion" {
    ${ALLOWED_RECURSION_NETS};
    localhost;
};

options {
    directory "/var/cache/bind";

    recursion yes;
    allow-recursion { allowed-recursion; };
    allow-query { any; };

    listen-on { any; };
    listen-on-v6 { any; };

    dnssec-validation auto;

    forwarders {
        8.8.8.8;
        1.1.1.1;
    };
};
EOF

cat > /etc/bind/named.conf.local <<EOF
zone "${DOMAIN}" {
    type master;
    file "/etc/bind/db.${DOMAIN}";
};
EOF

cat > "/etc/bind/db.${DOMAIN}" <<EOF
\$TTL 604800
@   IN  SOA ${DOMAIN}. admin.${DOMAIN}. (
        2026110701 ; Serial - naikkan setiap mengubah record DNS
        604800     ; Refresh
        86400      ; Retry
        2419200    ; Expire
        604800 )   ; Negative Cache TTL

@       IN  NS  ${DOMAIN}.
@       IN  A   ${IP_ADDRESS}
www     IN  A   ${IP_ADDRESS}
monitor IN  A   ${IP_ADDRESS}
EOF

named-checkconf
named-checkzone "${DOMAIN}" "/etc/bind/db.${DOMAIN}"
systemctl enable named
systemctl restart named
log "BIND9 aktif untuk zona ${DOMAIN}."

# ================= 3. NGINX + WEBSITE BURGUNDY =================
log "[3/5] Instalasi Nginx dan pembuatan website..."
apt-get install -y nginx openssl

mkdir -p "${WEBROOT}" /etc/nginx/ssl

# HTML, CSS, dan JavaScript dijadikan SATU file index.html.
# Ubah identitas pada variabel STUDENT_* di bagian atas script.
cat > "${WEBROOT}/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="theme-color" content="#4b1025">
  <meta name="description" content="Website layanan jaringan dan server UKK TKJ 2026 - SPK Paket 1.">
  <title>Network Lab | UKK TKJ 2026</title>

  <style>
    :root {
      --burgundy: #4b1025;
      --burgundy-dark: #2b0916;
      --burgundy-light: #762b45;
      --rose: #b76e83;
      --cream: #f8f3f1;
      --paper: #fffdfc;
      --ink: #282126;
      --muted: #786d72;
      --line: #eadde1;
      --success: #26734d;
      --shadow: 0 18px 50px rgba(55, 15, 31, .09);
      --radius: 18px;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    html { scroll-behavior: smooth; scroll-padding-top: 85px; }
    body {
      font-family: Inter, "Segoe UI", Arial, sans-serif;
      color: var(--ink);
      background: var(--cream);
      line-height: 1.7;
    }
    a { color: inherit; text-decoration: none; }
    .container { width: min(1120px, calc(100% - 40px)); margin: auto; }

    .navbar {
      position: sticky; top: 0; z-index: 20;
      background: rgba(43, 9, 22, .96);
      backdrop-filter: blur(12px);
      border-bottom: 1px solid rgba(255,255,255,.1);
    }
    .nav-inner {
      min-height: 72px; display: flex; align-items: center;
      justify-content: space-between; gap: 24px;
    }
    .brand { color: white; font-size: 1.08rem; font-weight: 800; letter-spacing: .4px; }
    .brand span { color: #e5b6c4; }
    .nav-links { display: flex; align-items: center; gap: 27px; list-style: none; }
    .nav-links a { color: #f2e5e9; font-size: .9rem; transition: color .2s; }
    .nav-links a:hover { color: #e7aabd; }
    .menu-toggle {
      display: none; border: 1px solid rgba(255,255,255,.3);
      background: transparent; color: white; padding: 7px 11px;
      border-radius: 8px; cursor: pointer;
    }

    .hero {
      position: relative; overflow: hidden; color: white;
      background:
        radial-gradient(circle at 85% 20%, rgba(183,110,131,.3), transparent 28%),
        linear-gradient(125deg, var(--burgundy-dark), var(--burgundy) 58%, #713149);
      padding: 105px 0 115px;
    }
    .hero::after {
      content: ""; position: absolute; width: 380px; height: 380px;
      border: 1px solid rgba(255,255,255,.12); border-radius: 50%;
      right: -110px; bottom: -230px;
      box-shadow: 0 0 0 35px rgba(255,255,255,.025), 0 0 0 75px rgba(255,255,255,.02);
    }
    .eyebrow {
      display: inline-flex; align-items: center; gap: 9px;
      padding: 7px 13px; border: 1px solid rgba(255,255,255,.25);
      border-radius: 30px; color: #f2dce3; font-size: .78rem;
      letter-spacing: 1.2px; text-transform: uppercase;
    }
    .eyebrow::before {
      content: ""; width: 7px; height: 7px; border-radius: 50%;
      background: #d99bad; box-shadow: 0 0 12px #d99bad;
    }
    .hero h1 {
      max-width: 800px; margin: 25px 0 16px;
      font-family: Georgia, "Times New Roman", serif;
      font-size: clamp(2.5rem, 6vw, 4.7rem);
      line-height: 1.08; letter-spacing: -1.5px;
    }
    .hero h1 span { color: #e8b9c7; }
    .hero-copy { max-width: 650px; color: #eadde2; font-size: 1.05rem; }
    .hero-actions { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 30px; }
    .button {
      display: inline-flex; align-items: center; justify-content: center;
      min-height: 47px; padding: 0 21px; border-radius: 9px;
      border: 1px solid transparent; font-weight: 700; font-size: .9rem;
      cursor: pointer; transition: transform .2s, background .2s;
    }
    .button:hover { transform: translateY(-2px); }
    .button-primary { background: #f0d5dd; color: var(--burgundy-dark); }
    .button-outline { border-color: rgba(255,255,255,.4); color: white; background: transparent; }
    .hero-meta { display: flex; flex-wrap: wrap; gap: 25px; margin-top: 45px; color: #e6cbd4; font-size: .88rem; }
    .hero-meta strong { display: block; color: white; font-size: 1rem; }

    .section { padding: 82px 0; }
    .section-white { background: var(--paper); }
    .section-heading { max-width: 680px; margin-bottom: 35px; }
    .section-kicker {
      color: var(--burgundy-light); font-size: .76rem;
      font-weight: 800; letter-spacing: 1.5px; text-transform: uppercase;
    }
    .section-heading h2 {
      margin: 9px 0 12px; color: var(--burgundy-dark);
      font-family: Georgia, "Times New Roman", serif;
      font-size: clamp(2rem, 4vw, 2.8rem); line-height: 1.2;
    }
    .section-heading p { color: var(--muted); }

    .about-grid { display: grid; grid-template-columns: 1.2fr .8fr; gap: 25px; }
    .panel {
      background: white; border: 1px solid var(--line);
      border-radius: var(--radius); padding: 29px; box-shadow: var(--shadow);
    }
    .panel h3 { color: var(--burgundy); margin-bottom: 12px; font-size: 1.15rem; }
    .panel p { color: var(--muted); }
    .info-list { display: grid; gap: 13px; }
    .info-row { display: flex; justify-content: space-between; gap: 15px; border-bottom: 1px solid var(--line); padding-bottom: 10px; }
    .info-row:last-child { border: 0; padding-bottom: 0; }
    .info-row span:first-child { color: var(--muted); }
    .info-row strong { color: var(--burgundy-dark); text-align: right; }

    .service-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; }
    .service-card {
      background: white; border: 1px solid var(--line); border-radius: var(--radius);
      padding: 27px; transition: transform .2s, box-shadow .2s;
    }
    .service-card:hover { transform: translateY(-5px); box-shadow: var(--shadow); }
    .service-icon {
      width: 48px; height: 48px; display: grid; place-items: center;
      background: #f5e7eb; color: var(--burgundy); border-radius: 13px;
      font-size: 1.35rem; margin-bottom: 19px;
    }
    .service-card h3 { color: var(--burgundy-dark); margin-bottom: 8px; }
    .service-card p { color: var(--muted); font-size: .92rem; }
    .service-tag {
      display: inline-block; margin-top: 18px; padding: 5px 10px;
      background: #f8eef1; color: var(--burgundy-light);
      border-radius: 20px; font-size: .75rem; font-weight: 700;
    }

    .topology-box {
      background: linear-gradient(135deg, var(--burgundy-dark), var(--burgundy));
      color: white; border-radius: 22px; padding: 35px;
      display: grid; grid-template-columns: 1fr 1fr; gap: 30px;
    }
    .topology-box h3 { font-family: Georgia, serif; font-size: 1.8rem; margin-bottom: 12px; }
    .topology-box p { color: #eadde2; }
    .vlan-list { display: grid; gap: 10px; }
    .vlan-item {
      display: flex; justify-content: space-between; gap: 15px;
      padding: 12px 15px; border: 1px solid rgba(255,255,255,.2);
      background: rgba(255,255,255,.06); border-radius: 10px;
    }
    .vlan-item span { color: #e8cbd4; }
    .vlan-item strong { color: white; }

    .contact-card {
      display: flex; align-items: center; justify-content: space-between;
      gap: 25px; padding: 30px; background: white;
      border: 1px solid var(--line); border-radius: var(--radius);
    }
    .contact-card h3 { color: var(--burgundy-dark); margin-bottom: 5px; }
    .contact-card p { color: var(--muted); }
    .status-output { margin-top: 13px; min-height: 25px; color: #f4cbd7; font-weight: 600; }
    footer { background: var(--burgundy-dark); color: #d9c3cb; padding: 25px 0; text-align: center; font-size: .85rem; }

    @media (max-width: 760px) {
      .nav-inner { min-height: 65px; }
      .menu-toggle { display: block; }
      .nav-links {
        display: none; position: absolute; top: 65px; left: 0; right: 0;
        padding: 18px 22px 22px; background: var(--burgundy-dark);
        flex-direction: column; align-items: flex-start; gap: 16px;
      }
      .nav-links.open { display: flex; }
      .hero { padding: 78px 0 85px; }
      .about-grid, .topology-box { grid-template-columns: 1fr; }
      .service-grid { grid-template-columns: 1fr; }
      .section { padding: 65px 0; }
      .contact-card { align-items: flex-start; flex-direction: column; }
      .hero-meta { gap: 17px; }
    }
  </style>
</head>
<body>
  <nav class="navbar">
    <div class="container nav-inner">
      <a class="brand" href="#home">NETWORK<span>LAB.</span></a>
      <button class="menu-toggle" id="menuToggle" aria-label="Buka navigasi" aria-expanded="false">Menu</button>
      <ul class="nav-links" id="navLinks">
        <li><a href="#home">Beranda</a></li>
        <li><a href="#about">Tentang</a></li>
        <li><a href="#services">Layanan</a></li>
        <li><a href="#topology">Topologi</a></li>
        <li><a href="#contact">Kontak</a></li>
      </ul>
    </div>
  </nav>

  <header class="hero" id="home">
    <div class="container">
      <span class="eyebrow">UKK TKJ 2026 · SPK Paket 1</span>
      <h1>Membangun konektivitas, <span>menjaga layanan.</span></h1>
      <p class="hero-copy">
        Portal Network Lab yang mendemonstrasikan implementasi jaringan berbasis VLAN,
        layanan DNS, web server, dan monitoring pada Ubuntu Server 24.04.
      </p>
      <div class="hero-actions">
        <a class="button button-primary" href="#services">Jelajahi Layanan</a>
        <a class="button button-outline" href="https://monitor.lab-smk.xyz">Dashboard Monitoring</a>
      </div>
      <div class="hero-meta">
        <div><strong>Ubuntu 24.04 LTS</strong>Platform Server</div>
        <div><strong>MikroTik CHR</strong>Routing & Switching</div>
        <div><strong>192.168.30.10</strong>Server VLAN 30</div>
      </div>
      <p class="status-output" id="statusOutput" aria-live="polite"></p>
    </div>
  </header>

  <main>
    <section class="section section-white" id="about">
      <div class="container">
        <div class="section-heading">
          <span class="section-kicker">Profil Laboratorium</span>
          <h2>Infrastruktur jaringan yang terintegrasi.</h2>
          <p>Lingkungan praktik ini menggabungkan routing, switching, layanan jaringan, dan pemantauan dalam satu topologi terstruktur.</p>
        </div>
        <div class="about-grid">
          <article class="panel">
            <h3>Tentang proyek</h3>
            <p>
              Proyek UKK TKJ SPK Paket 1 berfokus pada pembangunan jaringan menggunakan
              MikroTik CHR dan server Ubuntu. Jaringan dipisahkan menjadi beberapa VLAN
              untuk mengatur komunikasi antara perangkat Guru, Siswa, dan Server.
              Setiap layanan diuji untuk memastikan konektivitas, resolusi DNS,
              akses website, serta pemantauan perangkat berjalan sesuai kebutuhan.
            </p>
          </article>
          <aside class="panel">
            <h3>Informasi pengerjaan</h3>
            <div class="info-list">
              <div class="info-row"><span>Nama</span><strong>STUDENT_NAME</strong></div>
              <div class="info-row"><span>Kelas</span><strong>STUDENT_CLASS</strong></div>
              <div class="info-row"><span>Nomor ujian</span><strong>EXAM_NUMBER</strong></div>
              <div class="info-row"><span>Sekolah</span><strong>SCHOOL_NAME</strong></div>
              <div class="info-row"><span>Domain</span><strong>lab-smk.xyz</strong></div>
            </div>
          </aside>
        </div>
      </div>
    </section>

    <section class="section" id="services">
      <div class="container">
        <div class="section-heading">
          <span class="section-kicker">Layanan Infrastruktur</span>
          <h2>Komponen utama server.</h2>
          <p>Tiga layanan utama yang disiapkan untuk mendukung kebutuhan jaringan laboratorium.</p>
        </div>
        <div class="service-grid">
          <article class="service-card">
            <div class="service-icon">⌘</div>
            <h3>DNS Server</h3>
            <p>BIND9 mengelola zona lokal dan menerjemahkan nama domain menjadi alamat IP server.</p>
            <span class="service-tag">lab-smk.xyz</span>
          </article>
          <article class="service-card">
            <div class="service-icon">▤</div>
            <h3>Web Server</h3>
            <p>Nginx menyajikan portal laboratorium melalui HTTP dan HTTPS menggunakan sertifikat self-signed.</p>
            <span class="service-tag">HTTPS · NGINX</span>
          </article>
          <article class="service-card">
            <div class="service-icon">◷</div>
            <h3>Monitoring</h3>
            <p>Netdata menampilkan metrik performa server dan data perangkat Router MikroTik melalui SNMP.</p>
            <a class="service-tag" href="https://monitor.lab-smk.xyz">monitor.lab-smk.xyz ↗</a>
          </article>
        </div>
      </div>
    </section>

    <section class="section section-white" id="topology">
      <div class="container">
        <div class="topology-box">
          <div>
            <span class="section-kicker" style="color:#e8b9c7">Segmentasi Jaringan</span>
            <h3>Terpisah secara logis, terhubung secara terkontrol.</h3>
            <p>Router MikroTik menangani routing antar-VLAN dan kebijakan firewall. Switch MikroTik mengatur trunk serta access port untuk setiap segmen jaringan.</p>
          </div>
          <div class="vlan-list">
            <div class="vlan-item"><span>VLAN 10 · Guru</span><strong>192.168.10.0/24</strong></div>
            <div class="vlan-item"><span>VLAN 20 · Siswa</span><strong>192.168.20.0/24</strong></div>
            <div class="vlan-item"><span>VLAN 30 · Server</span><strong>192.168.30.0/24</strong></div>
            <div class="vlan-item"><span>Gateway Server</span><strong>192.168.30.1</strong></div>
          </div>
        </div>
      </div>
    </section>

    <section class="section" id="contact">
      <div class="container">
        <div class="section-heading">
          <span class="section-kicker">Informasi & Pengujian</span>
          <h2>Server siap melayani jaringan.</h2>
          <p>Gunakan tombol berikut untuk menampilkan waktu lokal browser sebagai uji interaksi JavaScript.</p>
        </div>
        <div class="contact-card">
          <div>
            <h3>Network Lab · UKK TKJ 2026</h3>
            <p>DNS, Web Server, dan Monitoring dalam satu infrastruktur.</p>
          </div>
          <button class="button button-primary" id="checkButton" type="button">Cek Interaksi</button>
        </div>
      </div>
    </section>
  </main>

  <footer>
    <div class="container">
      <p>© 2026 STUDENT_NAME · STUDENT_CLASS · SCHOOL_NAME</p>
      <p>Network Lab — UKK TKJ SPK Paket 1</p>
    </div>
  </footer>

  <script>
    // Identitas website diisi otomatis dari variabel Bash pada saat deployment.
    document.querySelectorAll(".info-row strong").forEach(function (element) {
      const value = element.textContent.trim();
      if (value === "STUDENT_NAME") element.textContent = "STUDENT_NAME_VALUE";
      if (value === "STUDENT_CLASS") element.textContent = "STUDENT_CLASS_VALUE";
      if (value === "EXAM_NUMBER") element.textContent = "EXAM_NUMBER_VALUE";
      if (value === "SCHOOL_NAME") element.textContent = "SCHOOL_NAME_VALUE";
    });

    document.querySelectorAll("footer p").forEach(function (element) {
      element.textContent = element.textContent
        .replaceAll("STUDENT_NAME", "STUDENT_NAME_VALUE")
        .replaceAll("STUDENT_CLASS", "STUDENT_CLASS_VALUE")
        .replaceAll("SCHOOL_NAME", "SCHOOL_NAME_VALUE");
    });

    const checkButton = document.getElementById("checkButton");
    const statusOutput = document.getElementById("statusOutput");
    checkButton.addEventListener("click", function () {
      const now = new Date();
      statusOutput.textContent = "Interaksi berhasil dijalankan · " + now.toLocaleString("id-ID");
    });

    const menuToggle = document.getElementById("menuToggle");
    const navLinks = document.getElementById("navLinks");
    menuToggle.addEventListener("click", function () {
      const isOpen = navLinks.classList.toggle("open");
      menuToggle.setAttribute("aria-expanded", String(isOpen));
    });
    navLinks.querySelectorAll("a").forEach(function (link) {
      link.addEventListener("click", function () {
        navLinks.classList.remove("open");
        menuToggle.setAttribute("aria-expanded", "false");
      });
    });
  </script>
</body>
</html>
HTMLEOF

# Ganti placeholder identitas di HTML dengan nilai dari variabel Bash.
# Nilai di-escape agar karakter khusus tidak merusak sed replacement.
escape_sed() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }
sed -i \
    -e "s/STUDENT_NAME_VALUE/$(escape_sed "${STUDENT_NAME}")/g" \
    -e "s/STUDENT_CLASS_VALUE/$(escape_sed "${STUDENT_CLASS}")/g" \
    -e "s/EXAM_NUMBER_VALUE/$(escape_sed "${EXAM_NUMBER}")/g" \
    -e "s/SCHOOL_NAME_VALUE/$(escape_sed "${SCHOOL_NAME}")/g" \
    "${WEBROOT}/index.html"

chown -R www-data:www-data "${WEBROOT}"
chmod 755 "${WEBROOT}"
chmod 644 "${WEBROOT}/index.html"

# Sertifikat self-signed dengan SAN untuk semua hostname yang dipakai.
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "/etc/nginx/ssl/${DOMAIN}.key" \
    -out "/etc/nginx/ssl/${DOMAIN}.crt" \
    -subj "/C=ID/ST=JawaTengah/L=Purwokerto/O=SMK/OU=TKJ/CN=${DOMAIN}" \
    -addext "subjectAltName=DNS:${DOMAIN},DNS:www.${DOMAIN},DNS:monitor.${DOMAIN},IP:${IP_ADDRESS}"

cat > "/etc/nginx/sites-available/${DOMAIN}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate /etc/nginx/ssl/${DOMAIN}.crt;
    ssl_certificate_key /etc/nginx/ssl/${DOMAIN}.key;

    root ${WEBROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

cat > "/etc/nginx/sites-available/monitor.${DOMAIN}" <<EOF
server {
    listen 80;
    server_name monitor.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name monitor.${DOMAIN};

    ssl_certificate /etc/nginx/ssl/${DOMAIN}.crt;
    ssl_certificate_key /etc/nginx/ssl/${DOMAIN}.key;

    location / {
        proxy_pass http://127.0.0.1:19999;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
EOF

ln -sfn "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/${DOMAIN}"
ln -sfn "/etc/nginx/sites-available/monitor.${DOMAIN}" "/etc/nginx/sites-enabled/monitor.${DOMAIN}"
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx
systemctl restart nginx
log "Website burgundy aktif pada https://${DOMAIN}."

# ================= 4. NETDATA + SNMP =================
log "[4/5] Instalasi Netdata dan konfigurasi SNMP..."
if ! command -v netdata >/dev/null 2>&1; then
    bash <(curl -fsSL https://get.netdata.cloud/kickstart.sh) --non-interactive --stable-channel \
        || apt-get install -y netdata
fi

mkdir -p /etc/netdata
if ! grep -q '^\[web\]' /etc/netdata/netdata.conf 2>/dev/null; then
    printf '\n[web]\n    bind to = 127.0.0.1\n' >> /etc/netdata/netdata.conf
elif ! grep -q '^[[:space:]]*bind to = 127.0.0.1' /etc/netdata/netdata.conf; then
    sed -i '/^\[web\]/a\    bind to = 127.0.0.1' /etc/netdata/netdata.conf
fi

systemctl enable netdata
systemctl restart netdata

apt-get install -y snmp
mkdir -p /etc/netdata/go.d

# Aktifkan modul SNMP pada konfigurasi go.d.
if [[ -f /etc/netdata/go.d.conf ]]; then
    if grep -q '^[[:space:]]*snmp:' /etc/netdata/go.d.conf; then
        sed -i 's/^[[:space:]]*snmp:.*/  snmp: yes/' /etc/netdata/go.d.conf
    else
        printf '\n  snmp: yes\n' >> /etc/netdata/go.d.conf
    fi
else
    cat > /etc/netdata/go.d.conf <<'EOF'
modules:
  snmp: yes
EOF
fi

# Konfigurasi job SNMP dasar. OID dapat berbeda menurut versi/perangkat RouterOS;
# verifikasi dengan snmpwalk dan sesuaikan bila chart tidak muncul.
cat > /etc/netdata/go.d/snmp.conf <<EOF
jobs:
  - name: router
    update_every: 10
    hostname: '${ROUTER_IP}'
    community: '${SNMP_COMMUNITY}'
    options:
      port: 161
      retries: 1
EOF

systemctl restart netdata
log "Netdata aktif di localhost:19999; job SNMP router telah dibuat."

# ================= 5. FIREWALL UFW =================
log "[5/5] Konfigurasi firewall UFW..."
apt-get install -y ufw

ufw allow OpenSSH
ufw allow 53/tcp
ufw allow 53/udp
ufw allow 80/tcp
ufw allow 443/tcp
ufw deny 19999/tcp
ufw --force enable

# ================= VERIFIKASI AKHIR =================
log "Memeriksa layanan..."
systemctl is-active --quiet named || die "BIND9 tidak aktif."
systemctl is-active --quiet nginx || die "Nginx tidak aktif."
systemctl is-active --quiet netdata || die "Netdata tidak aktif."

echo
echo "============================================================"
echo " DEPLOYMENT SERVER UKK TKJ SPK PAKET 1 SELESAI"
echo "============================================================"
echo " DNS       : dig @${IP_ADDRESS} ${DOMAIN}"
echo " Web       : https://${DOMAIN}"
echo " WWW       : https://www.${DOMAIN}"
echo " Monitoring: https://monitor.${DOMAIN}"
echo " Netdata   : internal 127.0.0.1:19999 (via Nginx reverse proxy)"
echo " Server IP : ${IP_ADDRESS}/24"
echo " Gateway   : ${ROUTER_IP}"
echo " SNMP      : ${ROUTER_IP}, community ${SNMP_COMMUNITY}"
echo
echo "PENTING:"
echo "1. Pastikan DHCP client VLAN 10/20/30 menggunakan DNS ${IP_ADDRESS}."
echo "2. VLAN 20 tidak diizinkan recursive DNS sesuai ACL bawaan script."
echo "3. Verifikasi SNMP RouterOS dengan:"
echo "   snmpwalk -v2c -c ${SNMP_COMMUNITY} ${ROUTER_IP} system"
echo "4. HTTPS self-signed memerlukan trust sertifikat pada client."
echo "5. Ganti STUDENT_NAME, STUDENT_CLASS, dan EXAM_NUMBER di bagian"
echo "   variabel script sebelum deployment bila identitas berbeda."
echo "============================================================"
