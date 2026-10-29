# Sunucu Panel: sürüm dosyaları

Bu repo yalnız Sunucu Panel'in **imzalı sürüm dosyalarını** taşır: panel, ajan ve Caddy ikilileri (linux amd64/arm64), `SHA256SUMS`, `SHA256SUMS.sig` (ed25519) ve kurulum betikleri. Kaynak kod burada değil.

Son sürüm: v0.4.0 (bkz. Releases).

## Kurulum (Ubuntu 24.04, root)

```sh
curl -fsSL https://raw.githubusercontent.com/kadirsungurlu/sunucu-panel-dagitim/main/install.sh -o install.sh
bash install.sh                     # son sürüm, eksik bilgileri sorar
bash install.sh --version v0.4.0 # belirli sürüm
bash install.sh --verify-only       # yalnız indir ve imzayı doğrula
```

`install.sh` içinde güncelleme açık anahtarı gömülüdür. Betik indirdiği her dosyanın SHA-256 özetini `SHA256SUMS` ile, `SHA256SUMS` dosyasını da imzayla doğrular. Doğrulama başarısızsa hiçbir şey kurulmaz.

Ajanlar panelin kendi `/dagitim/` adresinden kurulur; katılma komutu panelde Sunucular > Sunucu ekle ekranında verilir.
