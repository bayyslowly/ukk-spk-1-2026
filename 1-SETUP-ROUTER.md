# Tutorial Konfigurasi Router MikroTik CHR via WinBox
## UKK TKJ 2026 — SPK Paket 1

Tutorial ini menggunakan **WinBox versi terbaru** (v3.x / v4.x) untuk mengkonfigurasi **VM Router MikroTik (CHR)** sesuai topologi SPK Paket 1.

---

## 📋 Topologi Router

| Interface | Fungsi | Keterangan |
|---|---|---|
| Ether1 | WAN / Internet | DHCP Client (Use Peer DNS: **off**) |
| Ether2 | Trunk ke Switch | Membawa VLAN 10, 20, 30 |
| Ether3 | Management | Host Only — akses Winbox dari PC Admin via MAC-Winbox (tanpa IP); termasuk interface yang boleh MAC-Winbox (bagian 8c) |

| VLAN | IP Gateway | Fungsi |
|---|---|---|
| VLAN 10 | 192.168.10.1/24 | Jaringan Guru |
| VLAN 20 | 192.168.20.1/24 | Jaringan Siswa |
| VLAN 30 | 192.168.30.1/24 | Jaringan Server |

---

## 🔧 Persiapan

1. Download **WinBox terbaru** dari situs resmi MikroTik: `https://mikrotik.com/download`
2. Buka WinBox, pada tab **Neighbors** klik **Refresh** untuk mendeteksi VM Router CHR.
3. Klik pada MAC Address router yang muncul → klik **Connect** (login default: `admin`, password kosong).
4. Setelah masuk, disarankan langsung reset konfigurasi default agar bersih:
   - Menu **System → Reset Configuration** → centang **No Default Configuration** → klik **Reset Configuration**.
   - Winbox akan terputus, sambungkan ulang via MAC Address.

---

## 1️⃣ Konfigurasi Ether1 (DHCP Client / Internet)

1. Buka menu **IP → DHCP Client**.
2. Klik tombol **`+`** (Add).
3. Pada tab **General**:
   - **Interface**: `ether1`
   - **Use Peer DNS**: **hilangkan centang (off)** — sesuai requirement (DNS akan diarahkan manual ke server).
4. Klik **Apply → OK**.
5. Cek status DHCP Client, pastikan **Status: bound** dan mendapat IP dari internet/bridge.

**Terminal equivalent** (bisa dicek via New Terminal):
```
/ip dhcp-client add interface=ether1 use-peer-dns=no disabled=no
```

---

## 2️⃣ Konfigurasi DNS Server

1. Buka menu **IP → DNS**.
2. Pada kolom **Servers**, tambahkan:
   - `192.168.30.10` (DNS server internal)
   - `8.8.8.8` (DNS publik cadangan)
3. **JANGAN** centang "Allow Remote Requests" kecuali memang dibutuhkan sebagai DNS relay.
4. Klik **Apply → OK**.

**Terminal equivalent:**
```
/ip dns set servers=192.168.30.10,8.8.8.8
```

---

## 3️⃣ Aktifkan SNMP (untuk Monitoring)

Router akan dipantau oleh server monitoring (Netdata) via SNMP.

1. Buka menu **IP → SNMP**.
2. Centang **Enabled**.
3. Pada tab **Communities**, edit/tambah community:
   - **Name**: `public` (atau sesuaikan dengan yang dipakai di server monitoring)
   - **Addresses**: `192.168.30.10/32` (agar SNMP hanya bisa diakses dari server monitoring)
4. Klik **Apply → OK**.

**Terminal equivalent:**
```
/snmp set enabled=yes
/snmp community set [find default=yes] name=public addresses=192.168.30.10/32
```

⚠️ **Catatan:** community string ini **harus sama persis** dengan yang dikonfigurasi di script server (`SNMP_COMMUNITY` pada `setup-server.sh`).

---

## 4️⃣ Membuat VLAN 10, 20, 30 di atas Ether2 (Trunk)

1. Buka menu **Interfaces → VLAN**.
2. Klik **`+`** (Add) untuk masing-masing VLAN:

**VLAN 10:**
- **Name**: `Guru_Admin`
- **VLAN ID**: `10`
- **Interface**: `ether2`

**VLAN 20:**
- **Name**: `Siswa`
- **VLAN ID**: `20`
- **Interface**: `ether2`

**VLAN 30:**
- **Name**: `Server`
- **VLAN ID**: `30`
- **Interface**: `ether2`

3. Klik **Apply → OK** untuk masing-masing.

**Terminal equivalent:**
```
/interface vlan add name=Guru_Admin vlan-id=10 interface=ether2
/interface vlan add name=Siswa vlan-id=20 interface=ether2
/interface vlan add name=Server vlan-id=30 interface=ether2
```

---

## 5️⃣ Pengalamatan IP Tiap VLAN

1. Buka menu **IP → Addresses**.
2. Klik **`+`** (Add) untuk masing-masing:

| Address | Network | Interface |
|---|---|---|
| 192.168.10.1/24 | 192.168.10.0 | Guru_Admin |
| 192.168.20.1/24 | 192.168.20.0 | Siswa |
| 192.168.30.1/24 | 192.168.30.0 | Server |

**Terminal equivalent:**
```
/ip address add address=192.168.10.1/24 interface=Guru_Admin
/ip address add address=192.168.20.1/24 interface=Siswa
/ip address add address=192.168.30.1/24 interface=Server
```

---

## 6️⃣ DHCP Server untuk VLAN 10 dan VLAN 20

Gunakan **DHCP Setup Wizard** agar lebih cepat.

### DHCP Server VLAN 10 (Guru)
1. Buka menu **IP → DHCP Server → DHCP Setup**.
2. **DHCP Server Interface**: `Guru_Admin` → Next
3. **DHCP Address Space**: `192.168.10.0/24` → Next
4. **Gateway for DHCP Network**: `192.168.10.1` → Next
5. **Addresses to Give Out**: `192.168.10.10-192.168.10.254` → Next
6. **DNS Servers**: `192.168.30.10, 8.8.8.8` → Next
7. **Lease Time**: default (`00:10:00` atau sesuaikan) → Next → **selesai**.

### DHCP Server VLAN 20 (Siswa)
Ulangi langkah yang sama dengan:
- Interface: `Siswa`
- Address Space: `192.168.20.0/24`
- Gateway: `192.168.20.1`
- Pool: `192.168.20.10-192.168.20.254`

**Terminal equivalent (ringkas, tanpa wizard):**
```
/ip pool add name=pool-vlan10 ranges=192.168.10.10-192.168.10.254
/ip dhcp-server add name=dhcp-vlan10 interface=Guru_Admin address-pool=pool-vlan10 disabled=no
/ip dhcp-server network add address=192.168.10.0/24 gateway=192.168.10.1 dns-server=192.168.30.10,8.8.8.8

/ip pool add name=pool-vlan20 ranges=192.168.20.10-192.168.20.254
/ip dhcp-server add name=dhcp-vlan20 interface=Siswa address-pool=pool-vlan20 disabled=no
/ip dhcp-server network add address=192.168.20.0/24 gateway=192.168.20.1 dns-server=192.168.30.10,8.8.8.8
```

> Catatan: VLAN 30 (Server) **tidak perlu DHCP Server** karena server menggunakan IP static (192.168.30.10).

---

## 7️⃣ NAT Masquerade (Akses Internet)

1. Buka menu **IP → Firewall → tab NAT**.
2. Klik **`+`** (Add).
3. Tab **General**:
   - **Chain**: `srcnat`
   - **Out. Interface**: `ether1`
4. Tab **Action**:
   - **Action**: `masquerade`
5. Klik **Apply → OK**.

**Terminal equivalent:**
```
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade
```

---

## 8️⃣ Firewall Rules

Buka menu **IP → Firewall → tab Filter Rules**. Tambahkan rule secara **berurutan** (urutan sangat penting — firewall MikroTik memproses rule dari atas ke bawah / top-down!):

### a. Izinkan Balasan Koneksi dan VLAN 30 akses ke VLAN 10 (chain: forward)

**a.1 — Izinkan koneksi established/related (paling atas chain forward)**
- **Chain**: `forward`
- **Connection State**: `established, related`
- **Action**: `accept`

```
/ip firewall filter add chain=forward connection-state=established,related action=accept comment="Izinkan established/related"
```

> Tanpa rule ini, Guru **tidak bisa** ping ke Siswa: permintaan ping Guru → Siswa lolos, tetapi balasan Siswa → Guru cocok dengan rule blok VLAN 20 → VLAN 10 (rule c) dan ikut terdrop. Dengan rule ini, yang diblok hanya koneksi **baru** dari Siswa ke Guru, sedangkan Guru → Siswa tetap berjalan normal.

**a.2 — Izinkan VLAN 30 akses ke VLAN 10**
- **Chain**: `forward`
- **Src. Address**: `192.168.30.0/24`
- **Dst. Address**: `192.168.10.0/24`
- **Action**: `accept`

```
/ip firewall filter add chain=forward src-address=192.168.30.0/24 dst-address=192.168.10.0/24 action=accept comment="Izinkan VLAN30 ke VLAN10"
```

### b. Log percobaan VLAN 20 ke VLAN 10 (chain: forward)
- **Chain**: `forward`
- **Src. Address**: `192.168.20.0/24`
- **Dst. Address**: `192.168.10.0/24`
- **Action**: `log`

```
/ip firewall filter add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 action=log log-prefix="BLOCKED-VLAN20: " comment="Log percobaan VLAN20 ke VLAN10"
```

> Rule `log` tidak menghentikan proses (tetap lanjut ke rule berikutnya), jadi harus diletakkan **sebelum** rule drop terkait.

### c. Blok VLAN 20 akses ke VLAN 10 (chain: forward)
- **Chain**: `forward`
- **Src. Address**: `192.168.20.0/24`
- **Dst. Address**: `192.168.10.0/24`
- **Action**: `drop`

```
/ip firewall filter add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 action=drop comment="Blok VLAN20 ke VLAN10"
```

### c.2 Izinkan VLAN 20 (Siswa) hanya ke Server (chain: forward)
- **Chain**: `forward`
- **Src. Address**: `192.168.20.0/24`
- **Dst. Address**: `192.168.30.0/24`
- **Action**: `accept`

```
/ip firewall filter add chain=forward src-address=192.168.20.0/24 dst-address=192.168.30.0/24 action=accept comment="Izinkan VLAN20 ke Server"
```

### c.3 Blok VLAN 20 ke tujuan lain, termasuk Internet (chain: forward)
- **Chain**: `forward`
- **Src. Address**: `192.168.20.0/24`
- **Action**: `drop`

```
/ip firewall filter add chain=forward src-address=192.168.20.0/24 action=drop comment="Blok VLAN20 ke selain Server (tanpa Internet)"
```

> Rule c.3 **harus setelah c.2** (urutan top-down). Rule ini sengaja **tanpa log**: Windows terus menghubungi internet di latar belakang dan akan memenuhi log memori router (1000 baris), sehingga log penting (`BLOCKED-VLAN20`, `LOGIN-ATTEMPT`) tergeser. Bukti rule bekerja cukup dengan melihat kolom **Bytes/Packets** yang bertambah di Filter Rules.
>
> Dampaknya: Siswa hanya bisa mencapai Server (DNS, web, monitoring). DNS kedua `8.8.8.8` dari DHCP tidak akan terjangkau, dan itu tidak masalah karena DNS utama Siswa adalah Server.

> ⚠️ Urutan chain forward **wajib**: a (established/related, VLAN30 → VLAN10) → b (log) → c (drop VLAN20 → VLAN10) → c.2 (accept Siswa → Server) → c.3 (drop Siswa → lainnya). Rule c.2 harus di atas c.3, kalau terbalik Siswa kehilangan akses ke Server.

---

> Mulai bagian d, semua rule memakai `chain=input` dan **urutan penambahannya harus persis seperti di bawah**. `/ip firewall filter add` otomatis menaruh rule baru di baris paling bawah, jadi cukup menambahkannya berurutan (tanpa `place-before`).

### d. Drop IP yang Sudah Masuk Blacklist — **PALING ATAS**

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=blacklist action=drop comment="Drop brute force SSH/Winbox"
```

> Rule ini harus berada **di atas** rule accept VLAN 10/30 (bagian g). Kalau diletakkan di bawahnya, IP dari VLAN 10/30 yang sudah di-blacklist akan tetap diterima oleh rule accept sebelum sempat di-drop, sehingga blacklist tidak ada gunanya.

### e. Logging Koneksi Baru SSH/Winbox

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new action=log log-prefix="LOGIN-ATTEMPT: " comment="Log percobaan akses SSH/Winbox"
```

`connection-state=new` membuat log hanya mencatat koneksi baru, bukan setiap paket. Letaknya setelah rule d agar IP yang sudah diblokir tidak membanjiri log.

Untuk melihat log: menu **Log** di WinBox, atau via terminal:
```
/log print
```

### f. Anti Brute-Force Bertahap

Empat rule ini **harus berurutan dari stage tertinggi ke terendah**:

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_stage3 action=add-src-to-address-list address-list=blacklist address-list-timeout=1d comment="Stage 3 ke blacklist"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_stage2 action=add-src-to-address-list address-list=ssh_stage3 address-list-timeout=1m comment="Stage 2 ke stage3"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_stage1 action=add-src-to-address-list address-list=ssh_stage2 address-list-timeout=1m comment="Stage 1 ke stage2"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new action=add-src-to-address-list address-list=ssh_stage1 address-list-timeout=1m comment="Percobaan koneksi baru SSH/Winbox"
```

**Kenapa urutannya terbalik (rule "new → stage1" justru paling bawah)?** Action `add-src-to-address-list` tidak menghentikan pemrosesan, jadi paket yang sama lanjut ke rule berikutnya. Kalau `new → stage1` ditaruh paling atas, percobaan pertama langsung masuk stage1, lalu dipindah ke stage2, stage3, dan blacklist dalam satu paket. Dengan urutan terbalik, tiap paket hanya naik **satu tingkat**:

| Percobaan (dalam ±1 menit) | Yang terjadi |
|---|---|
| 1 | Masuk `ssh_stage1` |
| 2 | Naik ke `ssh_stage2` |
| 3 | Naik ke `ssh_stage3` |
| 4 | Masuk `blacklist` (1 hari) |
| 5 dst. | Di-drop oleh rule d |

> 💡 Address-list (`ssh_stage1`, `ssh_stage2`, `ssh_stage3`, `blacklist`) **tidak perlu dibuat manual**. RouterOS membuatnya otomatis saat ada traffic yang men-trigger action `add-src-to-address-list` pertama kali. Wajar kalau menu **IP → Firewall → Address Lists** kosong sebelum ada percobaan koneksi.

### g. Izinkan Akses SSH/Winbox dari VLAN 10 & VLAN 30

Rule accept diletakkan **setelah** staging. Dengan begitu percobaan login berulang dari VLAN 10/30 tetap terhitung sebagai brute-force, sedangkan login normal tidak terpengaruh.

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.10.0/24 action=accept comment="Izinkan akses VLAN10 ke router"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.30.0/24 action=accept comment="Izinkan akses VLAN30 ke router"
```

⚠️ **Konsekuensinya:** admin yang membuka 4 koneksi baru ke SSH/Winbox dalam ±1 menit akan ikut masuk blacklist selama 1 hari. Kalau terkunci, sambungkan lewat **MAC-Winbox dari PC Admin (Ether3 / Host-Only)** (Winbox → tab **Neighbors** → klik MAC Address router), lalu hapus blacklist:

```
/ip firewall address-list remove [find list=blacklist]
```

MAC-Winbox bekerja di layer 2 sehingga **tidak terkena** firewall IP ini; pembatasannya diatur terpisah di bagian **8c** (hanya interface Guru_Admin, Server, dan Ether3). Akses lewat **IP** di Ether3 (Host-Only) **tidak diizinkan** oleh rule ini, karena Ether3 bukan VLAN 10/30.

### h. Blok Semua Akses SSH/Winbox Lainnya — paling bawah

Rule penutup (catch-all). Pastikan kamu masih terhubung dari VLAN 10/30 sebelum menambahkannya.

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 action=drop comment="Blok akses SSH/Winbox selain VLAN10 & VLAN30"
```

### 📌 Urutan Akhir Chain Input (SSH/Winbox) — Ringkasan

| # | Rule | Alasan urutan |
|---|---|---|
| 1 | Drop jika src di `blacklist` | Di atas accept, agar blacklist berlaku juga untuk VLAN 10/30 |
| 2 | Log koneksi baru SSH/Winbox | Setelah drop blacklist, agar IP yang diblokir tidak membanjiri log |
| 3 | Stage3 → blacklist | Stage tertinggi dulu, agar tiap paket hanya naik satu tingkat |
| 4 | Stage2 → stage3 | Sama |
| 5 | Stage1 → stage2 | Sama |
| 6 | New connection → stage1 | Harus paling bawah dari empat rule staging |
| 7 | Accept VLAN10 → router | Setelah staging, agar login berulang tetap terhitung |
| 8 | Accept VLAN30 → router | Sama |
| 9 | Drop semua sisanya (catch-all) | Penutup: blok semua sumber selain VLAN 10/30 |

---

## 🔒 8️⃣b Hardening Layanan Router

Tujuannya: layanan yang tidak dipakai dimatikan, akses manajemen dibatasi, dan log berwaktu benar.

### b.1 Nonaktifkan layanan yang tidak diperlukan dan batasi SSH/Winbox
1. Buka menu **IP → Services**.
2. Pilih `telnet`, `ftp`, `www`, `api`, dan `api-ssl`, lalu klik tombol **X** (Disable) untuk masing-masing.
3. Klik dua kali `ssh`, isi **Available From** dengan `192.168.10.0/24` dan `192.168.30.0/24` (klik tanda panah ▼ untuk menambah alamat kedua), lalu **OK**.
4. Ulangi untuk `winbox`.

```
/ip service disable telnet,ftp,www,api,api-ssl
/ip service set ssh address=192.168.10.0/24,192.168.30.0/24
/ip service set winbox address=192.168.10.0/24,192.168.30.0/24
```

### b.2 Zona waktu dan NTP (agar log berwaktu benar)
1. **System → Clock**: **Time Zone Name** = `Asia/Jakarta`, lalu **OK**.
2. **System → NTP Client**: centang **Enabled**, **Primary NTP Server** = `162.159.200.1`, **Secondary NTP Server** = `216.239.35.0`, lalu **OK**.

```
/system clock set time-zone-name=Asia/Jakarta
/system ntp client set enabled=yes primary-ntp=162.159.200.1 secondary-ntp=216.239.35.0
```

> Perintah NTP di atas memakai sintaks **RouterOS 6**. Pada RouterOS 7, NTP client memakai tab **Servers** (`/system ntp client servers add address=...`). Alamat NTP boleh diganti dengan server NTP sekolah.

### b.3 Ganti password admin
Password **tidak** ditulis di script agar tidak tersimpan di GitHub. Atur manual:

1. **System → Users**, klik dua kali `admin`, klik **Password...**, isi password baru, lalu **OK**.

```
/user set admin password="PASSWORD-KUAT-ANDA"
```

---

## 🛡️ 8️⃣c Batasi Akses MAC-Winbox (Siswa Tidak Boleh Masuk Lewat MAC Address)

Firewall IP **tidak berlaku** untuk akses lewat MAC Address (layer 2). Tanpa langkah ini, Siswa tetap bisa Winbox ke router lewat MAC walaupun rule IP sudah memblokirnya. Caranya: MAC server hanya didengarkan pada interface yang diizinkan.

1. Buka **Interfaces**, lalu klik tombol **Interface List**.
2. Pada tab **Lists**, klik **+**, beri nama `Boleh-Winbox`, lalu **OK**.
3. Pindah ke tab **Interfaces** (di jendela yang sama), klik **+**, pilih **List** = `Boleh-Winbox` dan **Interface** = `Guru_Admin`. Ulangi untuk `Server` dan `ether3`. **Jangan** masukkan interface `Siswa`, `ether1`, maupun `ether2`.
4. Buka **Tools → MAC Server**, lalu pada tab **MAC Winbox Server**, klik dua kali baris yang ada dan ubah **Allowed Interface List** dari `all` menjadi `Boleh-Winbox`. Klik **Apply → OK**.
5. Pada tab **MAC Server** (MAC-Telnet), lakukan hal yang sama.

```
/interface list add name=Boleh-Winbox
/interface list member add list=Boleh-Winbox interface=Guru_Admin
/interface list member add list=Boleh-Winbox interface=Server
/interface list member add list=Boleh-Winbox interface=ether3
/tool mac-server set allowed-interface-list=Boleh-Winbox
/tool mac-server mac-winbox set allowed-interface-list=Boleh-Winbox
```

> ⚠️ **Jangan jalankan langkah ini dari sesi MAC-Winbox lewat interface lain** (misalnya Ether1): sesi akan terputus. Kerjakan dari Ether3 (Host-Only) atau dari IP VLAN 10/30.
>
> Router mungkin tetap terlihat di tab **Neighbors** milik Siswa (itu fitur discovery, bukan akses). Untuk menyembunyikannya (opsional): `/ip neighbor discovery-settings set discover-interface-list=Boleh-Winbox`.

---

## 💾 8️⃣d Backup Konfigurasi

Bukti pelaksanaan kebijakan backup. Hasilnya muncul di menu **Files**:

```
/export file=router-config
/system backup save name=router-backup
```

Salin kedua file ke komputer admin dengan drag-and-drop dari jendela **Files**.

---

## ✅ 9️⃣ Verifikasi

Cek semua konfigurasi berjalan dengan baik:

```
/interface vlan print          → pastikan Guru_Admin, Siswa, Server aktif
/ip address print              → pastikan IP tiap VLAN sudah benar
/ip dhcp-server print          → pastikan DHCP Guru_Admin & Siswa running
/ip firewall filter print      → cek urutan rule firewall (pastikan urutan sesuai tabel di atas)
/ip firewall nat print         → cek rule masquerade
/snmp print                    → pastikan SNMP enabled
/ip service print              → telnet, ftp, www, api nonaktif; ssh & winbox dibatasi VLAN 10/30
/system clock print            → zona waktu Asia/Jakarta, jam benar
/tool mac-server print         → allowed-interface-list=Boleh-Winbox
/tool mac-server mac-winbox print → allowed-interface-list=Boleh-Winbox
/ping 8.8.8.8                  → tes koneksi internet dari router
```

Uji dari sisi client (**penting:** Windows 7 memblok ping masuk secara default, jadi izinkan ICMP di Guru dan Siswa lebih dulu agar hasil uji benar-benar menguji firewall router, bukan firewall Windows):
```
netsh advfirewall firewall add rule name="Allow ICMPv4-In" protocol=icmpv4:8,any dir=in action=allow
```

- PC di VLAN 20 (Siswa) **tidak bisa** ping ke VLAN 10 (Guru) ✅
- PC di VLAN 20 (Siswa) **tidak bisa** ping `8.8.8.8` / membuka internet, tetapi **bisa** ping dan membuka web Server (`192.168.30.10`) ✅
- PC di VLAN 10 (Guru) **bisa** ping ke VLAN 20 (Siswa) dan ping `8.8.8.8` ✅
- Server di VLAN 30 **bisa** ping ke VLAN 10 (Guru) ✅
- Client VLAN 10/20 mendapat IP otomatis dari DHCP ✅
- Winbox/SSH ke router dari VLAN 20 **ditolak**, dari VLAN 10/30 **berhasil** ✅
- Winbox lewat **MAC Address** dari VM Siswa **ditolak**; dari Guru, Server, atau Ether3 **berhasil** ✅

**Uji brute-force** (dari VM Server di VLAN 30):
```bash
for i in 1 2 3 4 5; do nc -zv -w 2 192.168.30.1 22; done
```
Lalu di router, buka **IP → Firewall → Address Lists** (atau `/ip firewall address-list print`). IP `192.168.30.10` harus muncul di `blacklist`. Setelah uji, bersihkan agar Server tidak terblokir 1 hari:
```
/ip firewall address-list remove [find list=blacklist]
```

---

**Selanjutnya:** lanjut ke [`2-setup-switch.md`](./2-setup-switch.md) untuk konfigurasi VM Switch MikroTik (CHR).
