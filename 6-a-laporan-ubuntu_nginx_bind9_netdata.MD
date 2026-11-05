# LEMBAR LAPORAN PRAKTIK KEJURUAN (CONTOH TERISI)

**UKK TKJ Tahun Pelajaran 2026/2027 | Paket 1 | KM25.4.2.1**
Pembangunan Sistem Monitoring Jaringan dan Server Real-Time untuk Peningkatan Kinerja dan Keamanan Layanan Jaringan

> Contoh isian acuan penguji untuk kombinasi: **Ubuntu Server 24.04 LTS, Nginx, BIND9, Netdata**. Isian siswa boleh berbeda selama hasilnya benar dan sesuai soal.

| | |
|---|---|
| **No. Ujian** | 25-TKJ-001 |
| **Nama** | Contoh Siswa |
| **OS Server / Web** | Ubuntu Server 24.04 LTS / Nginx |
| **DNS / Monitoring** | BIND9 / Netdata |

---

## A. INVENTARIS ASET TI  *(dinilai: U2, U13)*

| No | Nama Aset | IP / VLAN | OS / Fungsi | Penting (T/S/R) | Risiko utama |
|---|---|---|---|---|---|
| 1 | Router (MikroTik CHR) | VLAN 10 192.168.10.1, VLAN 20 192.168.20.1, VLAN 30 192.168.30.1 | RouterOS 7; gateway, firewall, DHCP, NAT | T | Brute-force login |
| 2 | Switch (MikroTik CHR) | L2: trunk ke router, access VLAN 10/20/30 | RouterOS 7; segmentasi VLAN | T | Salah PVID / VLAN bocor |
| 3 | Server Linux | 192.168.30.10 (VLAN 30) | Ubuntu Server 24.04; DNS (BIND9), Web (Nginx), Monitoring (Netdata) | T | Layanan down, recursion DNS terbuka |
| 4 | Klien Guru | DHCP 192.168.10.x (VLAN 10) | Windows 7; pekerjaan guru/admin | S | OS tidak didukung |
| 5 | Klien Siswa | DHCP 192.168.20.x (VLAN 20) | Windows 7; praktik siswa | R | Malware, OS usang |

*T = Tinggi, S = Sedang, R = Rendah.*

---

## B. HASIL PENGUJIAN  *(dinilai: U1, U3, U4, U5, U7, U8, U9, U10)*

| No | Pengujian | Perintah yang dijalankan dan hasilnya |
|---|---|---|
| 1 | VLAN 10/20/30 berfungsi dan terisolasi | Router: `/interface vlan print` menampilkan vlan10, vlan20, vlan30 di ether2. Switch: `/interface bridge vlan print` menampilkan VLAN 10/20/30 terdaftar; `/interface bridge port print` menampilkan PVID port 2-3 = 10, port 4-7 = 20, port 8 = 30. Klien Guru `ipconfig`: 192.168.10.x/24, gateway 192.168.10.1. Klien Siswa: 192.168.20.x/24, gateway 192.168.20.1. Server `ip a`: 192.168.30.10/24. |
| 2 | VLAN 20 TIDAK bisa akses VLAN 10 | Klien Siswa: `ping 192.168.10.x` menghasilkan *Request timed out*, 100% loss. Aturan: `chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 action=drop` (counter bertambah). |
| 3 | VLAN 30 DAPAT berkomunikasi dengan VLAN 10 | Server: `ping 192.168.10.x` menghasilkan *bytes from*, 0% loss. Aturan: `chain=forward src-address=192.168.30.0/24 dst-address=192.168.10.0/24 action=accept`, diletakkan di atas aturan drop. |
| 4 | Domain lab-smk.xyz, www, monitor dapat diakses | Server: `named-checkzone lab-smk.xyz /etc/bind/db.lab-smk.xyz` menghasilkan *OK*. Klien Guru: `nslookup www.lab-smk.xyz 192.168.30.10` menghasilkan 192.168.30.10; `nslookup monitor.lab-smk.xyz` menghasilkan 192.168.30.10; `nslookup lab-smk.xyz` menghasilkan 192.168.30.10. Browser: `http://www.lab-smk.xyz` menampilkan halaman web sederhana. |
| 5 | Web monitoring terbuka melalui HTTPS | Browser: `https://monitor.lab-smk.xyz` menampilkan peringatan sertifikat self-signed; setelah dilanjutkan, dashboard Netdata tampil (Nginx reverse proxy ke 127.0.0.1:19999). Sertifikat dibuat dengan `openssl req -x509 -nodes -days 365 -newkey rsa:2048 ...`. `nginx -t` menghasilkan *syntax is ok*. |
| 6 | Dashboard: router dan server tampil + 1 grafik CPU/Memory | Dashboard Netdata: node server menampilkan grafik **System CPU** (atau **System RAM**) yang bergerak real-time setiap detik. Router (192.168.30.1) tampil sebagai job SNMP/ping pada bagian *Collectors* dengan data aktif. |
| 7 | Firewall efektif | `/ip firewall filter print`: (1) accept VLAN 30 ke VLAN 10, (2) drop VLAN 20 ke VLAN 10, (3) anti brute-force pada port 22 dan 8291 (stage1-stage3, pelanggar masuk address-list `blacklist` lalu drop), (4) chain input: accept SSH/Winbox hanya dari 192.168.10.0/24 dan 192.168.30.0/24, selain itu drop. Uji: 5x login gagal menyebabkan IP masuk `blacklist`. DNS: klien Siswa `nslookup google.com 192.168.30.10` menghasilkan *REFUSED* (`allow-recursion` hanya VLAN 10 dan VLAN 30). |
| 8 | Logging keamanan aktif | `/system logging print`: topics `firewall` dan `system,error,critical` dengan action=memory. `/log print` menampilkan `DROP-V20-V10 forward: in:vlan20 ... proto ICMP, 192.168.20.x->192.168.10.x` dan `login failure for user admin from 192.168.20.x via ssh`. |

---


## C. KEBIJAKAN KEAMANAN INFORMASI  *(dinilai: U11, P1, P4, P6, P10)*

**C1. Password policy**
Minimal 8 karakter, kombinasi huruf besar, huruf kecil, angka, dan simbol. Password default (admin tanpa password) wajib diganti saat awal. Diganti tiap 90 hari, tidak boleh dibagikan, dan setiap pengguna punya akun sendiri.

**C2. Pembagian akses VLAN (peran dan hak akses)**

| Peran / VLAN | Boleh mengakses | Tidak boleh mengakses |
|---|---|---|
| Guru/Admin (VLAN 10) | Internet, server (web, DNS, monitoring), manajemen router (SSH/Winbox) | Berbagi akun admin; perangkat di luar kewenangan |
| Siswa (VLAN 20) | Internet, web sekolah (HTTPS), DNS server | VLAN 10 (Guru/Admin), manajemen router, SSH ke server |
| Server (VLAN 30) | VLAN 10 (pemeliharaan), internet untuk pembaruan | Dijangkau langsung oleh VLAN 20 selain layanan web dan DNS |

**C3. Kebijakan penggunaan internet**
Internet digunakan untuk kegiatan belajar dan tugas sekolah. Dilarang mengakses situs judi, pornografi, dan situs berbahaya, serta mengunduh file besar saat jam pelajaran. Aktivitas dicatat di log router; pelanggaran dilaporkan ke guru/admin dan dapat dikenai sanksi sesuai tata tertib.

**C4. Kebijakan backup konfigurasi**
Konfigurasi router dan switch di-backup (`/system backup save` dan `/export`) serta konfigurasi server (`/etc/bind`, `/etc/nginx`, `/etc/netdata`) setiap selesai perubahan dan minimal seminggu sekali. Disimpan di server dan media terpisah. File yang dibuat: `router-backup.backup`, `router-config.rsc`, `switch-backup.backup`.

---

## D. SOP PENANGANAN INSIDEN  *(dinilai: U9, P8, P11, P17)*

**D1. Saat terjadi brute-force login**

| No | Tindakan | Perintah / alat |
|---|---|---|
| 1 | Deteksi: periksa log login gagal berulang dari satu IP | `/log print where message~"login failure"` |
| 2 | Blokir IP penyerang | `/ip firewall address-list add list=blacklist address=<IP> timeout=1d` |
| 3 | Ganti password admin; pastikan SSH/Winbox hanya dari VLAN 10/30 | `/user set admin password=...` ; `/ip service set ssh address=192.168.10.0/24,192.168.30.0/24` |
| 4 | Catat kejadian, laporkan ke Kepala Lab, backup konfigurasi | `/export file=setelah-insiden` ; formulir laporan insiden |

**D2. Saat server down**

| No | Tindakan | Perintah / alat |
|---|---|---|
| 1 | Cek konektivitas dan status di dashboard monitoring | `ping 192.168.30.10` dari router/klien; dashboard Netdata |
| 2 | Cek layanan dan sumber daya di konsol VM server | `systemctl status nginx bind9 netdata` ; `df -h` ; `free -m` |
| 3 | Pulihkan: perbaiki konfigurasi lalu restart layanan, atau restore dari backup | `nginx -t && systemctl restart nginx` ; `journalctl -xeu bind9` |
| 4 | Verifikasi web, DNS, dan monitoring normal; catat dan laporkan | Buka web dan monitoring; `nslookup lab-smk.xyz` |

**D3. Alur eskalasi**

| Level | Pihak / Jabatan | Batas waktu |
|---|---|---|
| Level 1 | Teknisi / Admin Lab | Ditangani maks. 15 menit |
| Level 2 | Kepala Lab / Ketua Program Keahlian TKJ | Bila belum pulih dalam 1 jam |
| Level 3 | Wakil Kepala Sekolah Sarana Prasarana / Kepala Sekolah | Bila belum pulih dalam 4 jam |

---

## E. STANDAR ACUAN DAN REKOMENDASI  *(dinilai: U6, U12, P2, P5, P9, P13, P14)*

**E1. Standar acuan dan jenis serangan yang dicegah**
Acuan: ISO/IEC 27001 (kontrol akses, logging, backup) dan CIS Benchmark (hardening). Serangan: brute force dicegah dengan anti brute-force dan akses manajemen dibatasi; web lambat/DoS dengan monitoring CPU/Memory real-time di Netdata; sniffing/spoofing dengan HTTPS dan segmentasi VLAN.

**E2. Rekomendasi**
Pengadaan: UPS dan penyimpanan backup eksternal; ganti Windows 7 dengan OS yang masih didukung. Fisik: ruang server dikunci, hanya petugas yang berhak masuk. Tambahan: IDS (mis. Suricata), notifikasi alert Netdata lewat email/Telegram, backup otomatis terjadwal.

---

Saya menyatakan laporan ini hasil pekerjaan saya sendiri.

| Penguji, | ............., .................... 2026 <br> Peserta, |
|---|---|
| ( ........................ ) | ( Contoh Siswa ) |

---

## LAMPIRAN (khusus penguji): potongan konfigurasi acuan

Bukan bagian laporan siswa. Dipakai sebagai pembanding saat memeriksa konfigurasi di VM.

**BIND9: `/etc/bind/named.conf.local`**
```
zone "lab-smk.xyz" {
    type master;
    file "/etc/bind/db.lab-smk.xyz";
};
```

**BIND9: `/etc/bind/db.lab-smk.xyz`**
```
$TTL 604800
@   IN SOA ns1.lab-smk.xyz. admin.lab-smk.xyz. (
        2026100901 604800 86400 2419200 604800 )
@       IN NS  ns1.lab-smk.xyz.
ns1     IN A   192.168.30.10
@       IN A   192.168.30.10
www     IN A   192.168.30.10
monitor IN A   192.168.30.10
```

**BIND9: `/etc/bind/named.conf.options`** (bagian penting)
```
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-recursion { 192.168.10.0/24; 192.168.30.0/24; localhost; };
    allow-query { any; };
    dnssec-validation auto;
    listen-on-v6 { any; };
};
```

**Nginx: `/etc/nginx/sites-available/lab-smk`** (aktifkan dengan symlink ke `sites-enabled`)
```
server {
    listen 80;
    server_name lab-smk.xyz www.lab-smk.xyz;
    root /var/www/lab-smk;
    index index.html;
}
server {
    listen 443 ssl;
    server_name monitor.lab-smk.xyz www.lab-smk.xyz lab-smk.xyz;
    ssl_certificate     /etc/ssl/certs/lab-smk.crt;
    ssl_certificate_key /etc/ssl/private/lab-smk.key;
    location / {
        proxy_pass http://127.0.0.1:19999;
        proxy_set_header Host $host;
    }
}
```
> Bila `www.lab-smk.xyz` juga ingin HTTPS menampilkan halaman web (bukan Netdata), pisahkan menjadi blok `server` tersendiri dengan `root /var/www/lab-smk;`.

**Netdata: monitoring router via SNMP**: `sudo /etc/netdata/edit-config go.d/snmp.conf`
```
jobs:
  - name: router
    hostname: 192.168.30.1
    community: lab-smk
    options:
      version: 2
```
Di router: `/snmp set enabled=yes` dan `/snmp community add name=lab-smk addresses=192.168.30.10/32`, serta izinkan UDP 161 dari 192.168.30.10 di chain input. Alternatif yang lebih sederhana: collector *ping* ke 192.168.30.1 (`go.d/ping.conf`).

**Catatan teknis untuk penguji**
- Pada Ubuntu 24.04 layanan BIND9 bernama `bind9` (alias `named`); cek dengan `systemctl status bind9`.
- Netdata secara bawaan hanya mendengarkan di `127.0.0.1:19999`, sehingga akses lewat Nginx reverse proxy (HTTPS) adalah cara yang wajar.
- Jika VLAN 20 hanya memakai DNS 192.168.30.10 dengan recursion dimatikan, siswa tidak bisa membuka domain internet. Solusinya DHCP VLAN 20 memberi DNS kedua (mis. 8.8.8.8) atau cukup menunjukkan hasil REFUSED sesuai soal.
