# Tutorial Konfigurasi Switch MikroTik CHR via WinBox
## UKK TKJ 2026 — SPK Paket 1

Tutorial ini menggunakan **WinBox versi terbaru** (v3.x / v4.x) untuk mengkonfigurasi **VM Switch MikroTik (CHR)**, menggunakan metode **Bridge VLAN Filtering** (didukung RouterOS 6.41 ke atas dan RouterOS 7).

---

## 📋 Topologi Switch

| Interface | Fungsi | VLAN |
|---|---|---|
| Ether1 | Uplink ke Router | Trunk (tagged VLAN 10, 20, 30) |
| Ether2 | Ke Switch-Guru | Access — VLAN 10 |
| Ether3 | Ke Switch-Siswa | Access — VLAN 20 |
| Ether4 | Ke Server | Access — VLAN 30 |
| Ether5 | Management | Host Only — akses Winbox langsung dari PC Admin (di luar bridge) |

> **Akses ke switch:** Winbox/SSH lewat **IP** hanya dari subnet Host-Only `192.168.100.0/24` (Ether5). Winbox lewat **MAC Address** hanya dari **Ether5 (Host-Only), Ether2 (Guru), dan Ether4 (Server)**. Ether3 (Siswa) dan Ether1 (trunk) tidak diizinkan (lihat bagian 6c).

---

## 🔧 Persiapan

1. Buka WinBox → tab **Neighbors** → **Refresh**.
2. Klik MAC Address VM **Switch MikroTik CHR** → **Connect**.
3. Disarankan reset ke default dulu:
   - **System → Reset Configuration** → centang **No Default Configuration** → **Reset Configuration**.
   - Sambungkan ulang via MAC Address setelah reboot.
4. Kerjakan seluruh konfigurasi dari jalur **Ether5 (Host-Only)** ya. Setelah bagian 6c dan 7 diterapkan, sesi Winbox lewat port bridge lain akan terputus.

---

## 1️⃣ Membuat Bridge

RouterOS CHR modern menggunakan satu **bridge** dengan **VLAN filtering** untuk mengatur trunk & access port — ini menggantikan cara lama (VLAN interface per port).

1. Buka menu **Bridge**.
2. Tab **Bridge** → klik **`+`** (Add):
   - **Name**: `bridge-switch`
   - Tab **VLAN**: centang **VLAN Filtering** — **JANGAN dicentang dulu**, aktifkan ini di langkah paling akhir (setelah semua port & VLAN diatur), supaya switch tidak "terkunci" saat konfigurasi berjalan.
3. Klik **Apply → OK**.

**Terminal equivalent:**
```
/interface bridge add name=bridge-switch
```

---

## 2️⃣ Menambahkan Semua Port ke Bridge

1. Buka tab **Ports** pada menu **Bridge**.
2. Klik **`+`** (Add) untuk setiap interface, masukkan ke `bridge-switch`:
   - `ether1` → Bridge: `bridge-switch`
   - `ether2` → Bridge: `bridge-switch`
   - `ether3` → Bridge: `bridge-switch`
   - `ether4` → Bridge: `bridge-switch`
   - `ether5` → Bridge: `bridge-switch` *(opsional — lihat catatan di bagian 6)*

**Terminal equivalent:**
```
/interface bridge port add bridge=bridge-switch interface=ether1
/interface bridge port add bridge=bridge-switch interface=ether2
/interface bridge port add bridge=bridge-switch interface=ether3
/interface bridge port add bridge=bridge-switch interface=ether4
```

---

## 3️⃣ Konfigurasi Trunk Port (Ether1 — ke Router)

Ether1 harus meneruskan **semua VLAN (tagged)** ke router.

1. Buka tab **VLAN** pada menu **Bridge**.
2. Klik **`+`** (Add):
   - **Bridge**: `bridge-switch`
   - **VLAN IDs**: `10`
   - **Tagged**: `ether1, bridge-switch`
   - **Untagged**: *(kosongkan)*
3. Ulangi untuk VLAN 20 dan 30, dengan **Tagged: ether1, bridge-switch** juga.

Jadi total ada 3 entri VLAN (10, 20, 30), dan `ether1` masuk sebagai **tagged** di ketiganya (karena ether1 adalah trunk).

**Terminal equivalent:**
```
/interface bridge vlan add bridge=bridge-switch vlan-ids=10 tagged=bridge-switch,ether1
/interface bridge vlan add bridge=bridge-switch vlan-ids=20 tagged=bridge-switch,ether1
/interface bridge vlan add bridge=bridge-switch vlan-ids=30 tagged=bridge-switch,ether1
```

---

## 4️⃣ Konfigurasi Access Port (Ether2, Ether3, Ether4)

Sekarang tambahkan tiap access port sebagai **untagged** di VLAN masing-masing. Edit ulang 3 entri VLAN yang sudah dibuat:

| VLAN ID | Tagged | Untagged |
|---|---|---|
| 10 | ether1, bridge-switch | **ether2** |
| 20 | ether1, bridge-switch | **ether3** |
| 30 | ether1, bridge-switch | **ether4** |

Caranya di WinBox: buka tab **VLAN**, double-klik entri VLAN 10 → isi kolom **Untagged**: `ether2` → Apply. Ulangi untuk VLAN 20 (`ether3`) dan VLAN 30 (`ether4`).

**Terminal equivalent (edit ulang entri sebelumnya):**
```
/interface bridge vlan set [find vlan-ids=10] untagged=ether2
/interface bridge vlan set [find vlan-ids=20] untagged=ether3
/interface bridge vlan set [find vlan-ids=30] untagged=ether4
```

---

## 5️⃣ Set PVID pada Access Port

Supaya trafik **masuk tanpa tag** dari perangkat (PC Guru/Siswa/Server) otomatis dianggap sebagai VLAN yang benar, set **PVID** di tiap access port.

1. Buka tab **Ports** pada menu **Bridge**.
2. Double-klik `ether2` → isi **PVID**: `10` → Apply.
3. Double-klik `ether3` → isi **PVID**: `20` → Apply.
4. Double-klik `ether4` → isi **PVID**: `30` → Apply.
5. `ether1` biarkan **PVID: 1** (default), karena ether1 murni trunk.

**Terminal equivalent:**
```
/interface bridge port set [find interface=ether2] pvid=10
/interface bridge port set [find interface=ether3] pvid=20
/interface bridge port set [find interface=ether4] pvid=30
```

---

## 🔒 5️⃣b Hardening Layer 2 pada Port Bridge

Mencegah **VLAN hopping** (VLAN bocor): perangkat di port access tidak boleh mengirim frame ber-tag ke VLAN lain, dan trunk hanya membawa frame ber-tag.

| Port | Frame Types | Ingress Filtering |
|---|---|---|
| Ether1 (trunk) | `admit only VLAN tagged` | ✅ |
| Ether2, Ether3, Ether4 (access) | `admit only untagged and priority tagged` | ✅ |

1. Buka menu **Bridge → tab Ports**.
2. Klik dua kali `ether1`, atur **Frame Types** = `admit only VLAN tagged`, centang **Ingress Filtering**, lalu **OK**.
3. Ulangi untuk `ether2`, `ether3`, `ether4` dengan **Frame Types** = `admit only untagged and priority tagged` dan **Ingress Filtering** dicentang.

**Terminal equivalent:**
```
/interface bridge port set [find interface=ether1] frame-types=admit-only-vlan-tagged ingress-filtering=yes
/interface bridge port set [find interface=ether2] frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes
/interface bridge port set [find interface=ether3] frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes
/interface bridge port set [find interface=ether4] frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes
```

---

## 6️⃣ Ether5 — Management Port (Host Only untuk WinBox)

Ether5 digunakan **khusus untuk akses langsung Winbox** dari PC Admin (Host-Only), terpisah dari jalur VLAN produksi — supaya switch tetap bisa diakses meskipun ada kesalahan konfigurasi VLAN.

**Opsi A (Direkomendasikan) — Ether5 di luar bridge VLAN:**
- **Jangan** masukkan `ether5` ke `bridge-switch`.
- Beri IP management langsung di `ether5`, contoh:

```
/ip address add address=192.168.100.1/24 interface=ether5
```

Lalu PC Admin (host-only) **wajib** diset IP `192.168.100.x`, misalnya `192.168.100.2/24`, agar bisa Winbox langsung ke `192.168.100.1`. Setelah bagian 6b diterapkan, hanya subnet `192.168.100.0/24` yang boleh Winbox/SSH lewat IP ke switch.

**Opsi B — Ether5 ikut bridge tapi khusus VLAN management:**
Jika ingin tetap satu bridge, buat VLAN manajemen terpisah (misal VLAN 99) khusus untuk ether5, dan beri IP di interface VLAN tersebut. (Opsional, tidak wajib sesuai topologi dasar.)

> 💡 Gunakan **Opsi A** untuk kesederhanaan dan sesuai prinsip topologi (jalur Host-Only terpisah dari jalur data VLAN).

---

## 🔐 6️⃣b Hardening Layanan Switch

### b.1 Nonaktifkan layanan yang tidak diperlukan dan batasi SSH/Winbox
1. Buka menu **IP → Services**.
2. Pilih `telnet`, `ftp`, `www`, `api`, dan `api-ssl`, lalu klik tombol **X** (Disable) untuk masing-masing.
3. Klik dua kali `ssh`, isi **Available From** dengan `192.168.100.0/24`, lalu **OK**. Ulangi untuk `winbox`.

```
/ip service disable telnet,ftp,www,api,api-ssl
/ip service set ssh address=192.168.100.0/24
/ip service set winbox address=192.168.100.0/24
```

### b.2 Zona waktu
Buka **System → Clock**, atur **Time Zone Name** = `Asia/Jakarta`, lalu **OK**.

```
/system clock set time-zone-name=Asia/Jakarta
```

> NTP tidak dipasang di switch: switch hanya punya IP di Ether5 (Host-Only) dan tidak punya rute ke Internet.

### b.3 Ganti password admin
Password **tidak** ditulis di script agar tidak tersimpan di GitHub. Atur manual:

1. **System → Users**, klik dua kali `admin`, klik **Password...**, isi password baru, lalu **OK**.

```
/user set admin password="PASSWORD-KUAT-ANDA"
```

---

## 🛡️ 6️⃣c Batasi Akses MAC-Winbox ke Switch

Pembatasan IP di 6b **tidak berlaku** untuk akses lewat MAC Address (layer 2). VM Guru, Siswa, dan Server tersambung langsung ke port switch, jadi tanpa langkah ini Siswa tetap bisa Winbox ke switch lewat MAC dan mengubah konfigurasi VLAN. Caranya: MAC server hanya didengarkan pada interface yang diizinkan.

| Interface | Boleh MAC-Winbox? | Keterangan |
|---|---|---|
| Ether5 | ✅ | Host-Only (admin) |
| Ether2 | ✅ | Guru |
| Ether4 | ✅ | Server |
| Ether3 | ❌ | Siswa |
| Ether1 | ❌ | Trunk ke Router |

1. Buka **Interfaces**, lalu klik tombol **Interface List**.
2. Pada tab **Lists**, klik **+**, beri nama `Boleh-Winbox`, lalu **OK**.
3. Pindah ke tab **Interfaces** (di jendela yang sama), klik **+**, pilih **List** = `Boleh-Winbox` dan **Interface** = `ether5`. Ulangi untuk `ether2` dan `ether4`. **Jangan** masukkan `ether3` maupun `ether1`.
4. Buka **Tools → MAC Server**, lalu pada tab **MAC Winbox Server**, klik dua kali baris yang ada dan ubah **Allowed Interface List** dari `all` menjadi `Boleh-Winbox`. Klik **Apply → OK**.
5. Pada tab **MAC Server** (MAC-Telnet), lakukan hal yang sama.

```
/interface list add name=Boleh-Winbox
/interface list member add list=Boleh-Winbox interface=ether5
/interface list member add list=Boleh-Winbox interface=ether2
/interface list member add list=Boleh-Winbox interface=ether4
/tool mac-server set allowed-interface-list=Boleh-Winbox
/tool mac-server mac-winbox set allowed-interface-list=Boleh-Winbox
```

> ⚠️ **Jangan jalankan langkah ini dari sesi MAC-Winbox lewat Ether1 atau Ether3**: sesi akan terputus. Kerjakan dari Ether5 (Host-Only).
>
> 📝 **Catatan uji:** karena Ether2 dan Ether4 adalah anggota bridge, uji dari VM Guru atau Server: Winbox via MAC ke switch harus **berhasil**, dan dari VM Siswa harus **ditolak**. Jika Guru/Server tetap gagal padahal sudah terdaftar, cukup andalkan Ether5 saja (hapus `ether2` dan `ether4` dari list). Dengan begitu Siswa tetap tidak bisa masuk.
>
> Switch mungkin tetap terlihat di tab **Neighbors** milik Siswa (itu fitur discovery, bukan akses). Untuk menyembunyikannya (opsional): `/ip neighbor discovery-settings set discover-interface-list=Boleh-Winbox`.

---

## 7️⃣ Aktifkan VLAN Filtering

Setelah **semua port dan VLAN selesai dikonfigurasi**, baru aktifkan VLAN filtering supaya bridge benar-benar memisahkan trafik antar-VLAN.

1. Buka menu **Bridge → tab Bridge**.
2. Double-klik `bridge-switch`.
3. Tab **VLAN**: centang **VLAN Filtering**.
4. Klik **Apply → OK**.

**Terminal equivalent:**
```
/interface bridge set bridge-switch vlan-filtering=yes
```

⚠️ **PENTING:** Setelah langkah ini diaktifkan, pastikan koneksi Winbox kamu tidak melalui port trunk/access biasa (gunakan Ether5/Host-Only) — karena jika salah konfigurasi, port trunk/access bisa langsung ter-filter dan memutus akses Winbox via jalur tersebut. Setelah bagian 6c, MAC-Winbox juga hanya diterima dari Ether5, Ether2, dan Ether4.

---

## 💾 7️⃣b Backup Konfigurasi

Bukti pelaksanaan kebijakan backup. Hasilnya muncul di menu **Files**:

```
/export file=switch-config
/system backup save name=switch-backup
```

Salin kedua file ke komputer admin dengan drag-and-drop dari jendela **Files**.

---

## ✅ 8️⃣ Verifikasi

```
/interface bridge print                  → pastikan bridge-switch aktif, vlan-filtering: yes
/interface bridge port print             → cek PVID tiap port sudah benar
/interface bridge vlan print             → cek tagged/untagged tiap VLAN ID
/interface bridge host print             → cek MAC address yang terdeteksi per VLAN
/ip service print                        → telnet, ftp, www, api nonaktif; ssh & winbox dibatasi 192.168.100.0/24
/system clock print                      → zona waktu Asia/Jakarta
/interface list member print             → Boleh-Winbox berisi ether5, ether2, ether4
/tool mac-server print                   → allowed-interface-list=Boleh-Winbox
/tool mac-server mac-winbox print        → allowed-interface-list=Boleh-Winbox
```

Uji dari sisi client:
- PC/Server yang terhubung ke **Ether2** otomatis masuk **VLAN 10** dan dapat DHCP dari Router (192.168.10.x) ✅
- PC yang terhubung ke **Ether3** otomatis masuk **VLAN 20** dan dapat DHCP (192.168.20.x) ✅
- Server yang terhubung ke **Ether4** berada di **VLAN 30** (192.168.30.10 static) ✅
- Trafik VLAN 10, 20, 30 saling terisolasi di level Layer 2 kecuali diizinkan firewall router ✅
- Winbox tetap bisa diakses via Ether5 (Host-Only) walau ada perubahan pada VLAN ✅
- Winbox lewat **MAC Address** ke switch dari VM Siswa **ditolak**; dari Guru, Server, atau Ether5 **berhasil** ✅
- Winbox/SSH lewat **IP** ke switch hanya dari subnet `192.168.100.0/24` (Ether5) ✅

---

## 📌 Ringkasan Pemetaan Akhir

| Port | Bridge | PVID | Tagged | Untagged | Frame Types | MAC-Winbox ke switch | Fungsi |
|---|---|---|---|---|---|---|---|
| Ether1 | bridge-switch | 1 | VLAN 10, 20, 30 | - | VLAN tagged saja | ❌ | Trunk ke Router |
| Ether2 | bridge-switch | 10 | - | VLAN 10 | Untagged saja | ✅ | Ke Switch-Guru |
| Ether3 | bridge-switch | 20 | - | VLAN 20 | Untagged saja | ❌ | Ke Switch-Siswa |
| Ether4 | bridge-switch | 30 | - | VLAN 30 | Untagged saja | ✅ | Ke Server |
| Ether5 | *(luar bridge)* | - | - | - | - | ✅ | Management Winbox (Host-Only) |

---

**Referensi sebelumnya:** [`1-setup-router.md`](./1-setup-router.md)
