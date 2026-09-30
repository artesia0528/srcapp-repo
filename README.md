# srcapp — mini package manager non-apt

`srcapp` melacak, meng-update, dan menghapus aplikasi yang **tidak** dipasang lewat
apt: tarball rilis, `cargo install`, `npm -g`, `go install`, `uv`, script build, dll.
Semua command update/uninstall disimpan sebagai satu file konfigurasi per aplikasi,
jadi tidak perlu mengingat lagi cara install/update masing-masing tool.

## Install

`srcapp` satu file bash tanpa dependency. Cukup taruh di `PATH`:

```bash
git clone https://github.com/<user>/srcapp.git
install -Dm755 srcapp-repo/srcapp ~/.local/bin/srcapp
srcapp list            # katalog kosong — normal
```

Tidak ada setup tambahan: `~/.config/srcapp`, `~/.local/share/srcapp`, dan
`~/.local/bin` dibuat sendiri saat `srcapp` pertama kali dijalankan.

Kalau `~/.local/bin` belum ada di `PATH`, tambahkan dulu:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

## Requirements

| Kebutuhan | Keterangan |
|-----------|------------|
| `bash` 4+ | shebang `#!/usr/bin/env bash` |
| `curl` | unduh tarball (method `tar`) |
| `tar` | ekstrak (method `tar`) |
| `find`, `coreutils` GNU | symlink binari & `mv` |
| GNU `grep` **dengan `-P`** | dipakai `update all` membaca tag `TAG=` |

> **Linux + GNU tools.** `grep -P` tidak ada di BSD/macOS, jadi `srcapp update all`
> akan gagal di sana. `add tar`, `add cmd`, `update <nama>`, dan `remove` tetap jalan.

Test: `bash test/smoke.sh` (pakai `$HOME` sementara, tidak menyentuh katalog asli).

---

## Cheat sheet

```bash
srcapp list                      # lihat semua app di katalog + versi (default kalau tanpa argumen)
srcapp list <nama>               # lihat 1 app
srcapp update <nama>             # update 1 app
srcapp update <nama> <url>       # update app tarball + ganti URL sumber
srcapp update all                # update SEMUA app TAG=user (tanpa sudo)
srcapp remove <nama>             # uninstall + hapus dari katalog
srcapp add tar <nama> <url> [bin...] [--tag user|system]
srcapp add cmd <nama> '<update-cmd>' '<uninstall-cmd>' [--ver '<ver-cmd>'] [--tag user|system]
```

---

## 1. Konsep & arsitektur

Tiga lokasi yang dipakai:

| Lokasi | Isi |
|--------|-----|
| `~/.config/srcapp/<nama>.conf` | **Katalog**: resep 1 app (method, URL, command update/uninstall, tag) |
| `~/.config/srcapp/updates/<nama>.sh` | **Script updater** opsional (untuk app sistem yang butuh sudo) |
| `~/.local/share/srcapp/<nama>/<versi>/` | **Install root**: hasil ekstrak tarball. File `CURRENT` menunjuk versi aktif |
| `~/.local/bin/<bin>` | **Symlink** ke binari hasil install (sudah ada di `PATH`) |

> **Katalog = state lokal, bukan bagian dari repo.** `~/.config/srcapp/*.conf` dan
> `updates/*.sh` berisi path/komponen pribadi, jadi tidak ikut di-commit ke GitHub.
> Pindah mesin: salin kedua folder itu, lalu jalankan `srcapp update <nama>` untuk
> app yang perlu install ulang.

### TAG: `user` vs `system`

- **`user`** — update tanpa sudo (`cargo`, `npm`, `uv`, `go`, tarball ke `~/.local`).
  Ikut dijalankan oleh `srcapp update all`.
- **`system`** — butuh sudo / menulis ke `/usr/local` atau `/opt`.
  **Dilewati** oleh `update all` supaya tidak memunculkan prompt sudo tak terduga.
  Update manual: `srcapp update <nama>`.

---

## 2. Perintah dasar

### `srcapp list [nama]`
Menampilkan katalog. Kolom: `nama  method  tag  bin=[...]  ver=...`

```
bluetui          cmd   user   bin=['-'] ver=bluetui 0.8.0
nvim             cmd   system bin=['-'] ver=NVIM v0.12.2
```

- Untuk `cmd`, versi diambil dari command `VER` (kalau ada), jika tidak → `?`.
- Untuk `tar`, versi diambil dari file `CURRENT`.

### `srcapp update <nama> [url]`
Menjalankan update sesuai method app.
- Method `cmd`: menjalankan `UP`.
- Method `tar`: mengunduh URL di konf. Bisa sekalian ganti URL: `srcapp update <nama> <url-baru>`
  (URL baru otomatis disimpan ke konf).

### `srcapp update all`
Update semua app **TAG=user**. App `system` di-skip dengan pesan pengingat.

### `srcapp remove <nama>`
- Method `tar`: hapus symlink binari + seluruh install root.
- Method `cmd`: jalankan command `UN` (kalau ada).
- Terakhir: hapus file `.conf` dari katalog.

---

## 3. Menambah app baru — metode `tar`

Untuk aplikasi yang didistribusikan sebagai arsip rilis (GitHub releases, dsb).

### Langkah

1. **Cari URL rilis.** Buka halaman releases, salin link *asset* (klik kanan → copy link),
   bukan link halaman. Contoh: `https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz`
2. **(Opsional) cari nama binari di dalam arsip.** Ini penting kalau nama binari beda
   dari nama arsip. Tentukan juga nama bin yang mau di-symlink.
3. **Jalankan `add tar`** — app langsung diunduh & dipasang:
   ```bash
   srcapp add tar starship \
     https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz \
     starship
   ```
   - Argumen setelah URL (`starship`) = nama binari yang dicari di hasil ekstrak,
     lalu di-symlink ke `~/.local/bin/`. Boleh lebih dari satu: `bin1 bin2`.
   - Tanpa nama bin: srcapp mendeteksi sendiri executable pertama, dan tidak membuat symlink.
4. **Tentang `--tag`:**
   - Metode `tar` **selalu** menginstall ke `~/.local` (tanpa sudo), sekalipun `--tag system`.
     `TAG` di sini hanya menandai agar app **dilewati** oleh `srcapp update all`.
   - Kalau app harus ditaruh di `/usr/local` atau `/opt`, jangan pakai `add tar` —
     gunakan `add cmd` + script updater (bagian 5).

### Apa yang terjadi di balik layar

1. Unduh URL ke folder sementara. URL boleh `http(s)://` **atau path file lokal**.
2. Ekstrak sesuai ekstensi: `.tar.gz`/`.tgz` → `-xzf`, `.tar.xz` → `-xJf`,
   `.tar.bz2` → `-xjf`, selain itu → `-xzf`. **`.zip` tidak didukung.**
3. Cari binari (sesuai argumen `bin...`), ambil versinya (`--version`/`-V`) →
   jadikan **slug** nama versi (spasi jadi `-`). Kalau gagal: `manual-<tanggal-jam>`.
4. Pindahkan hasil ekstrak ke `~/.local/share/srcapp/<nama>/<slug>/`.
5. Buat symlink binari → `~/.local/bin/`, tulis `CURRENT` berisi `<slug>`.
6. Kalau ada versi lama di slug berbeda, **hapus versi lama** (hemat ruang, tinggal 1 versi).

### Format arsip yang didukung
`.tar.gz`, `.tgz`, `.tar.xz`, `.tar.bz2`. **Tidak**: `.zip`, `.7z`.

---

## 4. Menambah app baru — metode `cmd`

Untuk app yang diinstall/update lewat perintah (cargo, npm, go, uv, git pull, dll).
Metode ini **hanya mendaftarkan** ke katalog — install pertama dilakukan saat `update`.

```bash
srcapp add cmd <nama> '<update-cmd>' '<uninstall-cmd>' [--ver '<version-cmd>'] [--tag user|system]
```

- `'<update-cmd>'` → dijalankan tiap `srcapp update <nama>`.
- `'<uninstall-cmd>'` → dijalankan tiap `srcapp remove <nama>`. Boleh `''` (kosong).
- `--ver '<cmd>'` → opsional, untuk menampilkan versi di `srcapp list`.
- `--tag user|system` → default `user`.

### Contoh nyata

```bash
# cargo (crates.io)
srcapp add cmd bluetui 'cargo install --force bluetui' 'cargo uninstall bluetui' --ver 'bluetui --version'

# npm global
srcapp add cmd codegraph 'npm update -g @colbymchenry/codegraph' 'npm rm -g @colbymchenry/codegraph' --ver 'codegraph --version'

# uv self-update
srcapp add cmd uv 'uv self update' 'rm -f ~/.local/bin/uv ~/.local/bin/uvx' --ver 'uv --version'

# go install (app bertag user — tanpa sudo)
srcapp add cmd lazygit 'go install github.com/jesseduffield/lazygit@latest' 'rm -f ~/go/bin/lazygit' --ver 'lazygit --version'
```

Setelah `add`, jalankan **install pertama**:
```bash
srcapp update bluetui
```

> Command ditulis apa adanya (boleh `&&`, `|`, `$HOME`, `~`, `$(...)`) karena
> dijalankan lewat shell. Karena itu **selalu kutip** command dengan tanda kutip tunggal.

---

## 5. App sistem (butuh sudo) — `add cmd` + script updater

Untuk app di `/usr/local` atau `/opt` yang perlu sudo. Pola: buat script updater
yang mengunduh ke folder sementara, memverifikasi, baru menukar secara atomik.

### Langkah

1. **Tulis script** di `~/.config/srcapp/updates/<nama>.sh`, mis. `update-nvim.sh`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   SRC=$(mktemp -d); trap 'rm -rf "$SRC"' EXIT
   curl -fL -o "$SRC/nvim.tar.gz" \
     https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
   mkdir "$SRC/x"; tar -xzf "$SRC/nvim.tar.gz" -C "$SRC/x"
   sudo rm -rf /usr/local/nvim-linux-x86_64
   sudo mv "$SRC/x/nvim-linux-x86_64" /usr/local/nvim-linux-x86_64
   sudo ln -sf /usr/local/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
   ```
2. **Chmod + cek syntax:**
   ```bash
   chmod +x ~/.config/srcapp/updates/update-nvim.sh
   bash -n ~/.config/srcapp/updates/update-nvim.sh
   ```
3. **Daftarkan** dengan `--tag system`:
   ```bash
   srcapp add cmd nvim '~/.config/srcapp/updates/update-nvim.sh' \
     'sudo rm -rf /usr/local/nvim-linux-x86_64 /usr/local/bin/nvim' \
     --ver 'nvim --version | head -1' --tag system
   ```
4. **Update manual** (akan minta password sudo):
   ```bash
   srcapp update nvim
   ```

### Prinsip script updater yang baik
- `set -euo pipefail` — berhenti kalau ada langkah gagal.
- Unduh & ekstrak dulu ke `mktemp -d`, verifikasi binari ada, **baru** `sudo` tukar.
  Kalau unduhan gagal, sistem sama sekali tidak tersentuh.
- Verifikasi versi/kode keluar sebelum menaruh ke lokasi sistem.

---

## 6. Format file `.conf`

File: `~/.config/srcapp/<nama>.conf`.

```ini
# komentar diawali '#' (diabaikan)
METHOD=cmd
TAG=user
UP=cargo install --force bluetui
UN=cargo uninstall bluetui
VER=bluetui --version
```

| KEY | Untuk | Isi |
|-----|-------|-----|
| `METHOD` | wajib | `tar` atau `cmd` (default `cmd`) |
| `TAG` | opsional | `user` (default) atau `system` |
| `URL` | method `tar` | URL asset rilis (atau path file lokal) |
| `BIN` | method `tar` | nama binari dipisah spasi; di-symlink ke `~/.local/bin` |
| `UP` | method `cmd` | command update (dijalankan `srcapp update`) |
| `UN` | method `cmd` | command uninstall (dijalankan `srcapp remove`) |
| `VER` | opsional | command untuk menampilkan versi di `srcapp list` |

### Aturan parsing (penting)
- Nilai diambil setelah tanda `=` **pertama** — jadi nilai boleh berisi `=`, `;`, `&&`,
  spasi, tanda kutip, dll.
- Satu nilai **harus satu baris** (tidak ada multiline).
- Baris kosong & baris berawalan `#` dilewati.

> **Dianjurkan** menambah app lewat `srcapp add ...` daripada menulis `.conf` manual,
> supaya formatnya pasti benar. Untuk kasus khusus (mis. `nvim` yang multi-baris),
> edit `.conf` langsung dengan `srcapp list <nama>` sebagai pengecekan.

---

## 7. Batasan / non-goals

Supaya tidak ada ekspektasi keliru:

- **Bukan pengganti apt.** Tidak ada resolusi dependensi, tidak ada lockfile.
- **Tanpa rollback.** Hanya 1 versi yang disimpan; install versi baru langsung
  menghapus versi lama.
- **Tanpa verifikasi integritas.** Method `tar` tidak mengecek checksum maupun
  signature dari unduhan.
- **Binary hasil unduh dieksekusi.** Untuk membaca nomor versi, `srcapp` menjalankan
  `<bin> --version` dari arsip yang baru diunduh. Perlakukan arsip dari sumber tak
  terpercayai sebagai kode yang akan dijalankan.
- **Format arsip:** `.tar.gz`, `.tgz`, `.tar.xz`, `.tar.bz2`. **Tidak didukung:**
  `.zip`, `.7z`.
- **Linux + GNU tools** (lihat § Requirements). Tidak ada dukungan Windows/macOS/BSD.
- **`add cmd` mencatat, tidak memasang.** Install pertama tetap perlu
  `srcapp update <nama>`.

## 8. Troubleshooting

| Gejala | Penyebab & solusi |
|--------|-------------------|
| `ver=?` padahal app jalan | Command `VER` menulis versi ke **stderr** (bukan stdout). Tambahkan `2>&1`, mis. `i3lock-color --version 2>&1 \| head -1` |
| `add tar` gagal `extraction failed (wrong url?)` | URL salah / bukan arsip tar, atau format `.zip` (tidak didukung). Pastikan link asset, bukan link halaman rilis |
| `binary '<x>' not found in the download` | Nama di argumen `bin...` salah, atau binari di dalam arsip tidak executable. Cek isi arsip dengan `tar -tzf file.tar.gz` |
| `update all` tidak mengupdate app tertentu | App bertag `system` memang di-skip. Jalankan `srcapp update <nama>` manual |
| `update all` berhenti di tengah | Sengaja: begitu satu app gagal, sisanya tidak dijalankan. `srcapp update <nama>` manual untuk app itu, lalu ulangi `update all` |
| App di `~/.local/bin` tidak terpakai | Ada binari lain dengan nama sama di `/usr/local/bin` atau `/usr/bin` yang lebih dulu di `PATH`? Cek `which -a <bin>`. Pastikan `~/.local/bin` ada di `PATH` |
| `remove` gagal `uninstall command failed` | Command `UN` error. Perbaiki `UN` atau kosongkan (`''`) lalu hapus manual |
| Ingin update tanpa ganti versi lama terhapus | Bawaan: versi lama dihapus setelah install sukses (hanya 1 versi disimpan). Kalau butuh arsip versi, salin dulu |

---

## 9. Contoh lengkap: dari manual → dikelola `srcapp`

Misal dulu `wlctl` diinstall manual lewat git + cargo:

```bash
# sebelum: manual
git clone https://github.com/aashish-thapa/wlctl ~/wlctl
cargo install --path ~/wlctl
```

Daftarkan ke srcapp:

```bash
srcapp add cmd wlctl \
  'git -C ~/wlctl pull --ff-only && cargo install --path ~/wlctl' \
  'rm -f ~/.cargo/bin/wlctl' \
  --ver 'wlctl --version'
```

Sekarang cukup:
```bash
srcapp update wlctl     # git pull + build ulang
srcapp list wlctl       # cek versi
srcapp remove wlctl     # hapus
```

### App GUI yang punya `install.sh` resmi

Beberapa app (mis. `zed`) sudah punya script installer sendiri yang menangani
`.desktop` file, icon, dan symlink. Cukup panggil script itu sebagai command update:

```bash
srcapp add cmd zed \
  'curl -fsSL https://zed.dev/install.sh | sh' \
  'rm -rf ~/.local/zed.app ~/.local/bin/zed ~/.local/share/applications/dev.zed.Zed.desktop' \
  --ver 'zed --version'

srcapp update zed
```

Kenapa bukan `add tar` dengan URL rilisnya? `add tar` hanya ekstrak + symlink, jadi
entri menunya hilang. Installer resmi sudah menangani semuanya, dan `srcapp` tinggal
memanggil ulang tiap update. Kalau mau ganti channel rilis (mis. preview), edit
baris `UP=` di `~/.config/srcapp/zed.conf`.
