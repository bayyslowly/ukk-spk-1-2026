# =====================================================================
#  setup-router.rsc
#  UKK TKJ 2026 - SPK PAKET 1
#  Konfigurasi Otomatis: VM Router MikroTik (CHR)
# =====================================================================
#
#  CARA PAKAI (Upload & Jalankan via Winbox):
#
#  1. Buka Winbox, masuk ke menu "Files", lalu drag-and-drop file
#     setup-router.rsc ini ke dalam direktori utama Files List.
#
#  2. Buka menu "Terminal" di Winbox, lalu ketikkan perintah berikut:
#
#     /import setup-router.rsc
#
#  3. Tunggu proses selesai, lalu cek hasilnya dengan perintah verifikasi
#     yang ada di bagian paling bawah file ini (lihat komentar VERIFIKASI).
#
#  CATATAN PENTING:
#  - Pastikan Ether1 sudah terhubung ke Internet/Bridge sebelum import,
#    supaya DHCP Client bisa langsung bound.
#  - Pastikan Ether2 sudah terhubung ke Ether1 Switch (trunk) sebelum
#    atau sesudah import (VLAN tetap akan terbentuk meski belum terhubung).
#  - Jalankan script ini pada router yang MASIH KOSONG / default config
#    supaya tidak bentrok dengan konfigurasi lama.
#  - Rule firewall membatasi SSH/Winbox (port TCP 22/8291) HANYA dari
#    VLAN 10 & VLAN 30. Ether3 (Host-Only) tidak punya IP di script ini,
#    jadi akses lewat Ether3 dilakukan dengan MAC-Winbox (Winbox ->
#    tab Neighbors -> klik MAC Address). MAC-Winbox bekerja di layer 2
#    dan TIDAK terpengaruh firewall IP ini, jadi aman dipakai untuk
#    menyambung ulang jika terkunci.
#  - Brute-force protection berlaku juga untuk VLAN 10/30: 4 koneksi
#    baru ke SSH/Winbox dalam +-1 menit akan memasukkan IP ke blacklist
#    selama 1 hari. Jika admin terblokir, sambungkan via MAC-Winbox lalu:
#    /ip firewall address-list remove [find list=ssh_blacklist]
# =====================================================================

:log info "=== MEMULAI IMPORT KONFIGURASI ROUTER - SPK PAKET 1 ==="

# ---------------------------------------------------------------------
# 1. KONFIGURASI ETHER1 - DHCP CLIENT (INTERNET)
#    Use Peer DNS: off (DNS akan diatur manual ke server)
# ---------------------------------------------------------------------
/ip dhcp-client
add interface=ether1 use-peer-dns=no disabled=no comment="WAN - Internet"

# ---------------------------------------------------------------------
# 2. KONFIGURASI DNS SERVER
#    Diarahkan ke server internal (192.168.30.10) dan DNS publik (8.8.8.8)
# ---------------------------------------------------------------------
/ip dns
set servers=192.168.30.10,8.8.8.8

# ---------------------------------------------------------------------
# 3. AKTIFKAN SNMP (untuk monitoring oleh server)
#    Community "public" hanya bisa diakses dari IP server monitoring.
#    Sesuaikan community ini dengan SNMP_COMMUNITY di server jika berbeda.
# ---------------------------------------------------------------------
/snmp
set enabled=yes
/snmp community
set [find default=yes] name=public addresses=192.168.30.10/32

# ---------------------------------------------------------------------
# 4. MEMBUAT VLAN 10, 20, 30 DI ATAS ETHER2 (TRUNK KE SWITCH)
# ---------------------------------------------------------------------
/interface vlan
add name=Guru_Admin vlan-id=10 interface=ether2 comment="VLAN Guru"
add name=Siswa vlan-id=20 interface=ether2 comment="VLAN Siswa"
add name=Server vlan-id=30 interface=ether2 comment="VLAN Server"

# ---------------------------------------------------------------------
# 5. PENGALAMATAN IP TIAP VLAN
# ---------------------------------------------------------------------
/ip address
add address=192.168.10.1/24 interface=vlan10 comment="Gateway VLAN 10 - Guru"
add address=192.168.20.1/24 interface=vlan20 comment="Gateway VLAN 20 - Siswa"
add address=192.168.30.1/24 interface=vlan30 comment="Gateway VLAN 30 - Server"

# ---------------------------------------------------------------------
# 6. DHCP SERVER UNTUK VLAN 10 (GURU) DAN VLAN 20 (SISWA)
#    VLAN 30 (Server) TIDAK dibuatkan DHCP karena server pakai IP static.
# ---------------------------------------------------------------------
/ip pool
add name=pool-vlan10 ranges=192.168.10.10-192.168.10.254
add name=pool-vlan20 ranges=192.168.20.10-192.168.20.254

/ip dhcp-server
add name=dhcp-vlan10 interface=vlan10 address-pool=pool-vlan10 disabled=no
add name=dhcp-vlan20 interface=vlan20 address-pool=pool-vlan20 disabled=no

/ip dhcp-server network
add address=192.168.10.0/24 gateway=192.168.10.1 dns-server=192.168.30.10,8.8.8.8
add address=192.168.20.0/24 gateway=192.168.20.1 dns-server=192.168.30.10,8.8.8.8

# ---------------------------------------------------------------------
# 7. NAT MASQUERADE (AKSES INTERNET UNTUK SEMUA VLAN)
# ---------------------------------------------------------------------
/ip firewall nat
add chain=srcnat out-interface=ether1 action=masquerade comment="NAT Masquerade - Internet"

# ---------------------------------------------------------------------
# 8. FIREWALL RULES
#    Rule chain=forward dan chain=input diproses terpisah oleh RouterOS,
#    jadi yang penting adalah urutan di dalam masing-masing chain.
#
#    Chain FORWARD (isolasi antar-VLAN):
#    (a0) Izinkan koneksi established/related - PALING ATAS. Tanpa ini,
#        balasan Siswa untuk koneksi yang DIMULAI Guru (mis. ping Guru ->
#        Siswa) ikut terdrop oleh rule blok VLAN 20 -> VLAN 10. Dengan
#        rule ini, hanya koneksi BARU dari Siswa ke Guru yang diblok.
#    (a) Izinkan VLAN 30 -> VLAN 10
#    (b) Log percobaan VLAN 20 -> VLAN 10 (harus SEBELUM drop, karena
#        action log tidak menghentikan proses)
#    (c) Blok VLAN 20 -> VLAN 10
#
#    Chain INPUT (akses SSH/Winbox ke router), dari atas ke bawah:
#    (d) Drop IP yang sudah di blacklist - PALING ATAS, supaya blacklist
#        berlaku untuk SEMUA sumber, termasuk VLAN 10/30.
#    (e) Log koneksi baru SSH/Winbox
#    (f) Anti brute-force bertahap. Urutan dari stage TERTINGGI ke
#        terendah itu SENGAJA: action add-src-to-address-list tidak
#        menghentikan pemrosesan, jadi kalau "new -> stage1" ditaruh di
#        atas, paket yang sama langsung naik stage1 -> 2 -> 3 -> blacklist
#        pada percobaan pertama.
#    (g) Izinkan VLAN 10 & VLAN 30 - di BAWAH staging, supaya percobaan
#        login berulang dari VLAN 10/30 tetap terhitung brute-force.
#    (h) Drop semua akses SSH/Winbox lainnya - PALING BAWAH (catch-all)
# ---------------------------------------------------------------------

/ip firewall filter

# --- Chain FORWARD: isolasi VLAN ---

# (a0) Izinkan balasan koneksi yang sudah terbentuk - PALING ATAS chain forward
add chain=forward connection-state=established,related action=accept \
    comment="Izinkan established/related"

# (a) Izinkan VLAN 30 (Server) akses ke VLAN 10 (Guru)
add chain=forward src-address=192.168.30.0/24 dst-address=192.168.10.0/24 \
    action=accept comment="Izinkan VLAN30 ke VLAN10"

# (b) Logging percobaan VLAN 20 -> VLAN 10 (sebelum di-drop)
add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 \
    action=log log-prefix="BLOCKED-VLAN20: " comment="Log percobaan VLAN20 ke VLAN10"

# (c) Blok VLAN 20 (Siswa) akses ke VLAN 10 (Guru)
add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 \
    action=drop comment="Blok VLAN20 ke VLAN10"

# --- Chain INPUT: akses SSH/Winbox ke router ---

# (d) Drop IP yang sudah masuk blacklist - PALING ATAS
add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    src-address-list=ssh_blacklist action=drop comment="Drop brute force SSH/Winbox"

# (e) Logging koneksi baru SSH/Winbox
add chain=input protocol=tcp dst-port=22,8291 connection-state=new action=log \
    log-prefix="LOGIN-ATTEMPT: " comment="Log percobaan akses SSH/Winbox"

# (f) Anti brute-force bertahap: urutan stage3 -> stage2 -> stage1 -> new
#     Address-list ssh_stage1/2/3 dan ssh_blacklist TIDAK perlu dibuat manual;
#     RouterOS otomatis membuatnya saat action add-src-to-address-list pertama
#     kali ter-trigger oleh traffic yang cocok.
add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    src-address-list=ssh_stage3 action=add-src-to-address-list \
    address-list=ssh_blacklist address-list-timeout=1d comment="Stage 3 ke blacklist"

add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    src-address-list=ssh_stage2 action=add-src-to-address-list \
    address-list=ssh_stage3 address-list-timeout=1m comment="Stage 2 ke stage3"

add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    src-address-list=ssh_stage1 action=add-src-to-address-list \
    address-list=ssh_stage2 address-list-timeout=1m comment="Stage 1 ke stage2"

add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    action=add-src-to-address-list address-list=ssh_stage1 address-list-timeout=1m \
    comment="Percobaan koneksi baru SSH/Winbox"

# (g) Izinkan akses SSH/Winbox dari VLAN 10 & VLAN 30 (setelah staging)
add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.10.0/24 \
    action=accept comment="Izinkan akses VLAN10 ke router"

add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.30.0/24 \
    action=accept comment="Izinkan akses VLAN30 ke router"

# (h) Blok semua akses SSH/Winbox lainnya (catch-all, paling bawah)
add chain=input protocol=tcp dst-port=22,8291 action=drop \
    comment="Blok akses SSH/Winbox selain VLAN10 & VLAN30"

:log info "=== KONFIGURASI ROUTER SELESAI DI-IMPORT ==="

# =====================================================================
#  VERIFIKASI (jalankan manual satu per satu di Terminal setelah import)
#  Urutan LOGIS chain input (SSH/Winbox) setelah import (cek dengan
#  '/ip firewall filter print chain=input'):
#  1. drop jika src di ssh_blacklist
#  2. log koneksi baru SSH/Winbox
#  3. stage3 -> blacklist
#  4. stage2 -> stage3
#  5. stage1 -> stage2
#  6. new connection -> stage1
#  7. accept VLAN10 -> router
#  8. accept VLAN30 -> router
#  9. drop semua sisanya (catch-all)
#
#  UJI BRUTE-FORCE (dari VM Server, VLAN 30):
#    for i in 1 2 3 4 5; do nc -zv -w 2 192.168.30.1 22; done
#  Lalu di router: /ip firewall address-list print
#  -> IP 192.168.30.10 harus muncul di ssh_blacklist.
#  BERSIHKAN setelah uji (lewat Winbox/MAC-Winbox):
#    /ip firewall address-list remove [find list=ssh_blacklist]
# =====================================================================
#  /interface vlan print
#  /ip address print
#  /ip dhcp-server print
#  /ip firewall nat print
#  /ip firewall filter print
#  /snmp print
#  /ping 8.8.8.8
#
#  Uji dari client (firewall Windows 7 harus mengizinkan ICMP):
#  - PC VLAN 20 (Siswa)  -> ping ke VLAN 10 (Guru)   HARUS GAGAL
#  - PC VLAN 10 (Guru)   -> ping ke VLAN 20 (Siswa)  HARUS BERHASIL
#  - Server VLAN 30      -> ping ke VLAN 10 (Guru)   HARUS BERHASIL
#  - Winbox/SSH dari VLAN 20 ke router               HARUS DITOLAK
#  - Winbox/SSH dari VLAN 10/30 ke router            HARUS BERHASIL
# =====================================================================
