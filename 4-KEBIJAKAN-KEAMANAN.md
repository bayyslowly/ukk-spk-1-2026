# Kebijakan Keamanan Informasi
## Laboratorium Jaringan SMK XYZ — UKK TKJ 2026, SPK Paket 1

| Item | Keterangan |
|---|---|
| Disusun oleh | Junior Cyber Security |
| Berlaku untuk | Router, Switch, Server, dan seluruh pengguna (Guru/Admin dan Siswa) |
| Ditinjau ulang | Setiap 6 bulan, atau setelah terjadi insiden besar |

Dokumen ini menjawab kondisi awal laboratorium: belum ada segmentasi VLAN, belum ada pengamanan antar-segmen, belum ada monitoring, dan pernah terjadi upaya brute-force pada router.

Untuk setiap kebijakan, bagian **Diterapkan** berisi hal yang sudah dikonfigurasi di perangkat, dan bagian **Rekomendasi** berisi hal yang belum dikonfigurasi tetapi disarankan.

---

## 1. Ruang Lingkup dan Pencatatan Aset TI

| Aset | Peran | Alamat | Layanan |
|---|---|---|---|
| Router MikroTik CHR | Gateway, DHCP, NAT, firewall | 192.168.10.1 / 192.168.20.1 / 192.168.30.1 | SSH (22), Winbox (8291), SNMP (161/udp) |
| Switch MikroTik CHR | Segmentasi VLAN | IP management pada port management | Winbox |
| Server Ubuntu 24.04 | DNS, Web, Monitoring | 192.168.30.10 (static) | DNS (53), HTTP/HTTPS (80/443), SSH (22) |
| Komputer Guru/Admin | Klien VLAN 10 | DHCP 192.168.10.0/24 | - |
| Komputer Siswa | Klien VLAN 20 | DHCP 192.168.20.0/24 | - |

Daftar aset diperbarui setiap kali ada perangkat atau layanan yang ditambah, diganti, atau dihentikan.

---

## 2. Kebijakan Password

**Aturan:**
1. Panjang minimal **12 karakter**, kombinasi huruf besar, huruf kecil, angka, dan simbol.
2. Dilarang memakai password bawaan (default), nama pengguna, tanggal lahir, atau kata umum.
3. Setiap administrator memakai **akun sendiri**, tidak berbagi akun.
4. Password diganti minimal **setiap 90 hari** dan segera setelah dicurigai bocor.
5. Password tidak boleh ditulis di tempat terbuka, dikirim lewat chat, atau disimpan di file tanpa perlindungan.
6. Password tidak boleh dipakai ulang pada perangkat atau layanan lain.
7. Akun `admin` bawaan MikroTik wajib diberi password, atau diganti dengan akun administrator baru lalu akun bawaan dinonaktifkan.
8. SNMP community string wajib diganti dari nilai bawaan `public` pada lingkungan produksi.

**Diterapkan:**
- Percobaan login berulang ke SSH/Winbox router dibatasi oleh firewall: **4 koneksi baru dalam ±1 menit** dari satu IP memasukkan IP tersebut ke daftar blokir selama 1 hari.
- SNMP router hanya menjawab permintaan dari server monitoring (192.168.30.10).

**Rekomendasi:** gunakan autentikasi kunci publik untuk SSH ke server, dan nonaktifkan login SSH dengan password setelah kunci terpasang.

> Catatan lab: pada lingkungan uji, community SNMP memakai nilai `public` agar sederhana. Nilai ini harus diganti sebelum dipakai di jaringan sekolah sungguhan.

---

## 3. Kebijakan Pembagian Akses VLAN

| VLAN | Nama | Jaringan | Gateway | Pengguna |
|---|---|---|---|---|
| 10 | Guru_Admin | 192.168.10.0/24 | 192.168.10.1 | Guru dan administrator |
| 20 | Siswa | 192.168.20.0/24 | 192.168.20.1 | Siswa |
| 30 | Server | 192.168.30.0/24 | 192.168.30.1 | Server layanan |

**Matriks akses:**

| Dari ↓ / Ke → | VLAN 10 | VLAN 20 | VLAN 30 | Internet | Router (SSH/Winbox) |
|---|---|---|---|---|---|
| **VLAN 10** | - | Boleh | Boleh | Boleh | **Boleh** |
| **VLAN 20** | **Diblokir** | - | Boleh (DNS, Web) | Boleh | **Diblokir** |
| **VLAN 30** | Boleh | Boleh | - | Boleh | **Boleh** |

**Diterapkan:**
- Firewall router memblokir koneksi baru dari VLAN 20 ke VLAN 10, dan setiap percobaan dicatat dengan awalan log `BLOCKED-VLAN20`.
- VLAN 30 diizinkan mengakses VLAN 10.
- Balasan atas koneksi yang sudah terbentuk (established/related) diizinkan, sehingga Guru tetap bisa menghubungi Siswa.
- SSH/Winbox ke router hanya diterima dari VLAN 10 dan VLAN 30. Sumber lain di-drop.
- DNS server menolak recursion dari VLAN 20.
- Firewall server (UFW) hanya membuka port 22, 53, 80, dan 443. Port monitoring internal (19999) ditutup dari luar dan hanya diakses lewat HTTPS.

**Rekomendasi:**
- Batasi SSH ke server hanya dari VLAN 10 (`ufw allow from 192.168.10.0/24 to any port 22`).
- Batasi dashboard monitoring hanya untuk VLAN 10 dan VLAN 30, karena saat ini VLAN 20 juga bisa membukanya.

---

## 4. Kebijakan Penggunaan Internet

1. Internet disediakan untuk kegiatan pembelajaran dan administrasi sekolah.
2. Dilarang mengakses atau mengunduh konten ilegal, pornografi, perjudian, atau perangkat lunak bajakan.
3. Dilarang memindai jaringan, mencoba menebak password, atau mengganggu layanan (DoS), baik ke jaringan sekolah maupun ke luar.
4. Semua perangkat memakai DNS server sekolah (192.168.30.10) yang diberikan lewat DHCP.
5. Trafik keluar melewati router (NAT). Aktivitas pada router dan server dapat dicatat dan dipantau oleh administrator.
6. Pelanggaran dikenai teguran, pembatasan akses, dan dilaporkan sesuai tingkat pelanggaran.

**Rekomendasi:** pasang pemfilteran konten (misalnya DNS filtering) dan batas bandwidth per VLAN, karena pembatasan ini belum dikonfigurasi.

---

## 5. Kebijakan Backup Konfigurasi

| Objek | Isi yang dibackup | Frekuensi |
|---|---|---|
| Router | Konfigurasi dan file binary | Sebelum dan sesudah setiap perubahan, serta mingguan |
| Switch | Konfigurasi dan file binary | Sebelum dan sesudah setiap perubahan, serta mingguan |
| Server | `/etc/bind`, `/etc/nginx`, `/etc/netdata`, `/etc/netplan`, `/var/www/lab-smk.xyz` | Mingguan dan sebelum perubahan layanan |

**Aturan:**
1. Backup disimpan di **minimal dua lokasi** berbeda (bukan hanya di perangkat itu sendiri).
2. Nama file memuat tanggal, misalnya `router-2026-07-13`.
3. Simpan **3 versi terakhir**, hapus yang lebih lama.
4. Uji pemulihan (restore) minimal **setiap semester**.
5. File backup berisi data sensitif (kunci SSL, community SNMP), jadi akses hanya untuk administrator.

**Cara backup router dan switch** (Terminal Winbox):
```
/export file=router-config
/system backup save name=router-backup
```
Ambil file dari menu **Files** di Winbox dengan drag-and-drop ke komputer administrator.

**Cara backup server:**
```bash
sudo tar czf backup-server-$(date +%F).tar.gz /etc/bind /etc/nginx /etc/netdata /etc/netplan /var/www/lab-smk.xyz
```

**Cara restore:** impor file `.rsc` dengan `/import router-config.rsc` pada perangkat yang sudah direset, atau ekstrak arsip server ke direktori semula lalu jalankan `sudo systemctl restart named nginx netdata`.

---

## 6. Pencatatan dan Pemantauan

1. Firewall router mencatat percobaan akses SSH/Winbox (`LOGIN-ATTEMPT`) dan pelanggaran VLAN 20 (`BLOCKED-VLAN20`). Log dilihat lewat menu **Log** di Winbox.
2. Monitoring server dan router dilakukan real-time lewat dashboard `https://monitor.lab-smk.xyz`.
3. Administrator memeriksa log dan dashboard minimal **sekali seminggu**.
4. Setiap kejadian mencurigakan ditangani sesuai dokumen [`SOP-INSIDEN.md`](./SOP-INSIDEN.md).

---

## 7. Sanksi dan Peninjauan

Pelanggaran terhadap kebijakan ini dapat dikenai pembatasan akses dan pelaporan kepada pimpinan sekolah. Kebijakan ditinjau minimal setiap 6 bulan.
