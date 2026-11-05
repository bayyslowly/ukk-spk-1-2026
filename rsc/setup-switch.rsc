# =====================================================================
#  setup-switch.rsc
#  UKK TKJ 2026 - SPK PAKET 1
#  Konfigurasi Otomatis: VM Switch MikroTik (CHR)
#  Metode: Bridge VLAN Filtering (RouterOS 6.41 ke atas dan RouterOS 7)
# =====================================================================
#
#  CARA PAKAI (Upload & Jalankan via Winbox):
#
#  1. Buka Winbox, masuk ke menu "Files", lalu drag-and-drop file
#     setup-switch.rsc ini ke dalam direktori utama Files List.
#
#  2. Buka menu "Terminal" di Winbox, lalu ketikkan perintah berikut:
#
#     /import setup-switch.rsc
#
#  3. Tunggu proses selesai, lalu cek hasilnya dengan perintah verifikasi
#     yang ada di bagian paling bawah file ini (lihat komentar VERIFIKASI).
#
#  CATATAN PENTING:
#  - Jalankan script ini pada switch yang MASIH KOSONG / default config
#    supaya tidak bentrok dengan konfigurasi lama.
#  - PENTING: jalankan /import dari Ether5 (Host-Only), lewat MAC-Winbox
#    atau lewat IP 192.168.100.1. Sesi Winbox lewat ether1/2/3/4 akan
#    terputus setelah bagian 6 (batas MAC-Winbox) dan bagian 7 (VLAN
#    filtering) diterapkan.
#  - Ether5 SENGAJA TIDAK dimasukkan ke bridge, supaya tetap bisa
#    dipakai sebagai jalur management independen (Host-Only untuk Winbox).
#  - Winbox/SSH lewat IP hanya diterima dari subnet 192.168.100.0/24
#    (Ether5). PC Admin Host-Only WAJIB memakai IP 192.168.100.x.
#  - MAC-Winbox/MAC-Telnet ke switch hanya diterima dari Ether5 (Host-Only),
#    Ether2 (Guru), dan Ether4 (Server). Ether3 (Siswa) dan Ether1 (trunk)
#    TIDAK dimasukkan, sehingga Siswa tidak bisa masuk lewat MAC Address.
#  - Password admin TIDAK diatur oleh script ini (agar tidak tersimpan di
#    GitHub). Setelah import, jalankan manual:
#    /user set admin password="PASSWORD-KUAT-ANDA"
# =====================================================================

:log info "=== MEMULAI IMPORT KONFIGURASI SWITCH - SPK PAKET 1 ==="

# ---------------------------------------------------------------------
# 1. MEMBUAT BRIDGE (VLAN Filtering belum diaktifkan dulu)
# ---------------------------------------------------------------------
/interface bridge
add name=bridge-switch comment="Bridge utama VLAN 10/20/30"

# ---------------------------------------------------------------------
# 2. MENAMBAHKAN PORT KE BRIDGE (+ HARDENING LAYER 2)
#    Ether1 = trunk ke Router
#    Ether2 = access ke VM Guru      (VLAN 10)
#    Ether3 = access ke VM Siswa     (VLAN 20)
#    Ether4 = access ke VM Server    (VLAN 30)
#    Ether5 = TIDAK dimasukkan (dipakai khusus management Host-Only)
#
#    Hardening Layer 2 (mencegah VLAN hopping / VLAN bocor):
#    - Trunk (ether1)  : hanya menerima frame ber-tag VLAN
#    - Access (ether2-4): hanya menerima frame tanpa tag; frame ber-tag
#      dari perangkat di port access dibuang
#    - ingress-filtering=yes: frame dengan VLAN yang tidak terdaftar di
#      port tersebut dibuang
# ---------------------------------------------------------------------
/interface bridge port
add bridge=bridge-switch interface=ether1 \
    frame-types=admit-only-vlan-tagged ingress-filtering=yes \
    comment="Trunk ke Router"
add bridge=bridge-switch interface=ether2 pvid=10 \
    frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes \
    comment="Access VLAN10 - Guru"
add bridge=bridge-switch interface=ether3 pvid=20 \
    frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes \
    comment="Access VLAN20 - Siswa"
add bridge=bridge-switch interface=ether4 pvid=30 \
    frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes \
    comment="Access VLAN30 - Server"

# ---------------------------------------------------------------------
# 3. KONFIGURASI VLAN PADA BRIDGE
#    Ether1 = tagged di ketiga VLAN (trunk)
#    Ether2/3/4 = untagged sesuai VLAN masing-masing (access port)
# ---------------------------------------------------------------------
/interface bridge vlan
add bridge=bridge-switch vlan-ids=10 tagged=bridge-switch,ether1 untagged=ether2 comment="VLAN 10 - Guru"
add bridge=bridge-switch vlan-ids=20 tagged=bridge-switch,ether1 untagged=ether3 comment="VLAN 20 - Siswa"
add bridge=bridge-switch vlan-ids=30 tagged=bridge-switch,ether1 untagged=ether4 comment="VLAN 30 - Server"

# ---------------------------------------------------------------------
# 4. KONFIGURASI ETHER5 - MANAGEMENT PORT (HOST-ONLY UNTUK WINBOX)
#    Diberi IP terpisah, DI LUAR bridge, agar tetap bisa diakses
#    walau ada kesalahan konfigurasi VLAN pada bridge.
# ---------------------------------------------------------------------
/ip address
add address=192.168.100.1/24 interface=ether5 comment="Management Winbox - Host Only"

# ---------------------------------------------------------------------
# 5. HARDENING LAYANAN SWITCH
#    - Nonaktifkan layanan yang tidak diperlukan (telnet, ftp, www, api)
#    - Batasi SSH & Winbox (lewat IP) hanya dari subnet management Ether5
#    - Zona waktu WIB agar log berwaktu benar
#    NTP tidak dipasang: switch hanya punya IP di Ether5 (Host-Only) dan
#    tidak punya rute ke Internet.
#    Password admin diatur MANUAL (lihat CATATAN PENTING di atas).
# ---------------------------------------------------------------------
/ip service
disable telnet,ftp,www,api,api-ssl
set ssh address=192.168.10.0/24,192.168.30.0/24
set winbox address=192.168.10.0/24,192.168.30.0/24

/system clock
set time-zone-name=Asia/Jakarta

# ---------------------------------------------------------------------
# 6. BATASI AKSES MAC-WINBOX / MAC-TELNET
#    Pembatasan IP di atas tidak berlaku untuk akses lewat MAC Address
#    (layer 2). VM Guru, Siswa, dan Server tersambung langsung ke port
#    switch, jadi tanpa langkah ini Siswa bisa Winbox ke switch lewat MAC.
#    MAC server hanya aktif pada interface list "Boleh-Winbox":
#      ether5 = Host-Only (admin), ether2 = Guru, ether4 = Server.
#    Ether3 (Siswa) dan ether1 (trunk) TIDAK dimasukkan.
# ---------------------------------------------------------------------
/interface list
add name=Boleh-Winbox comment="Interface yang boleh MAC-Winbox dan MAC-Telnet"

/interface list member
add list=Boleh-Winbox interface=ether5
add list=Boleh-Winbox interface=ether2
add list=Boleh-Winbox interface=ether4

/tool mac-server
set allowed-interface-list=Boleh-Winbox

/tool mac-server mac-winbox
set allowed-interface-list=Boleh-Winbox

# (Opsional) sembunyikan switch dari daftar Neighbors pada interface lain:
# /ip neighbor discovery-settings set discover-interface-list=Boleh-Winbox

# ---------------------------------------------------------------------
# 7. AKTIFKAN VLAN FILTERING (PERUBAHAN KONFIGURASI PALING TERAKHIR)
# ---------------------------------------------------------------------
/interface bridge
set bridge-switch vlan-filtering=yes

# ---------------------------------------------------------------------
# 8. BACKUP KONFIGURASI (bukti kebijakan backup)
#    Hasil muncul di menu Files: switch-config.rsc dan switch-backup.backup
# ---------------------------------------------------------------------
/export file=switch-config
/system backup save name=switch-backup

:log info "=== KONFIGURASI SWITCH SELESAI DI-IMPORT ==="

# =====================================================================
#  VERIFIKASI (jalankan manual satu per satu di Terminal setelah import)
# =====================================================================
#  /interface bridge print
#  /interface bridge port print
#  /interface bridge vlan print
#  /interface bridge host print
#  /ip address print
#  /ip service print
#  /system clock print
#  /interface list member print
#  /tool mac-server print
#  /tool mac-server mac-winbox print
#
#  Uji dari client:
#  - VM Guru  (terhubung Ether2) -> otomatis masuk VLAN 10, dapat DHCP dari Router
#  - VM Siswa (terhubung Ether3) -> otomatis masuk VLAN 20, dapat DHCP dari Router
#  - VM Server(terhubung Ether4) -> berada di VLAN 30 (IP static 192.168.30.10)
#  - Winbox tetap bisa diakses via Ether5 (192.168.100.1) walau VLAN filtering aktif
#  - MAC-Winbox ke switch dari VM Siswa                HARUS DITOLAK
#  - MAC-Winbox ke switch dari Guru / Server / Ether5  HARUS BERHASIL
#    (jika Guru/Server gagal padahal ether2/ether4 ada di list, lihat
#     catatan uji pada 2-setup-switch.md bagian 6c)
# =====================================================================
