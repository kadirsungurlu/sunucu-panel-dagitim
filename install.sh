#!/usr/bin/env bash
# sunucu-panel kurulum önyükleyicisi (Ubuntu 24.04).
#
#   curl -fsSL <URL>/install.sh | sudo bash -s -- [önyükleme bayrakları] [--] [kurulum bayrakları]
#
# Önyükleme bayrakları:
#   --from <URL|dizin>        sürüm dosyalarının kaynağı (varsayılan: GitHub release, kadirsungurlu/sunucu-panel-dagitim)
#   --version <vX>            belirli sürüm (varsayılan: en son yayımlanan)
#   --github-token-file <f>   isteğe bağlı GitHub jetonu (API sınırı için) (dosyadan okunur, yazdırılmaz)
#   --upgrade                 kurulum yerine yükseltme (sunucu-panel upgrade)
#   --verify-only             yalnız imza + özet doğrula, kurma (root gerekmez)
# Kalan bayraklar (ya da `--` sonrası her şey) `sunucu-panel install|upgrade`e aynen geçer.
#
# Güven zinciri: SHA256SUMS dosyası, bu betiğe derlemede gömülen ed25519 açık
# anahtarıyla doğrulanır; sonra her dosya SHA256SUMS'a göre denetlenir.
set -euo pipefail

# Derlemede `make dist` yerleştirir (ham 32 baytlık ed25519 açık anahtar, base64).
PUBKEY_B64='fnZXF9YpHw0Kt005rAG0E1eJZxsWj9u3LAcMI5zD8uE='
GITHUB_REPO='kadirsungurlu/sunucu-panel-dagitim'

FROM=''
VERSION=''
TOKEN_FILE=''
MODE='install'
VERIFY_ONLY=0

hata() { printf 'HATA: %s\n' "$*" >&2; exit 1; }
bilgi() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--from) [ $# -ge 2 ] || hata "--from değer ister"; FROM="$2"; shift 2 ;;
		--version) [ $# -ge 2 ] || hata "--version değer ister"; VERSION="$2"; shift 2 ;;
		--github-token-file) [ $# -ge 2 ] || hata "--github-token-file değer ister"; TOKEN_FILE="$2"; shift 2 ;;
		--upgrade) MODE='upgrade'; shift ;;
		--verify-only) VERIFY_ONLY=1; shift ;;
		--) shift; break ;;
		*) break ;;
	esac
done

case "$PUBKEY_B64" in
	@@*) hata "betik açık anahtar gömülmeden derlenmiş (make dist kullanın)" ;;
esac

if [ "$VERIFY_ONLY" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
	hata "root olarak çalıştırın (sudo bash -s -- ...)"
fi

for k in curl openssl sha256sum base64; do
	command -v "$k" >/dev/null 2>&1 || hata "gerekli komut yok: $k (apt-get install -y $k)"
done

case "$(uname -m)" in
	x86_64 | amd64) ARCH=amd64 ;;
	aarch64 | arm64) ARCH=arm64 ;;
	*) hata "desteklenmeyen mimari: $(uname -m)" ;;
esac

if [ "$VERIFY_ONLY" -eq 0 ] && [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	if [ "${ID:-}" != "ubuntu" ] || [ "${VERSION_ID:-}" != "24.04" ]; then
		printf 'UYARI: yalnız Ubuntu 24.04 denendi (bu sistem: %s %s)\n' "${ID:-?}" "${VERSION_ID:-?}" >&2
	fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"
ART="$TMP/artifacts"
mkdir -p "$ART"

CURL=(curl -fsSL --retry 3 --proto '=https,http')
AUTH=()
if [ -n "$TOKEN_FILE" ]; then
	[ -r "$TOKEN_FILE" ] || hata "jeton dosyası okunamıyor: $TOKEN_FILE"
	# Jeton komut satırına düşmesin diye başlık dosyası kullanılır.
	( umask 077; printf 'Authorization: Bearer %s\n' "$(tr -d '[:space:]' <"$TOKEN_FILE")" >"$TMP/auth.h" )
	AUTH=(-H "@$TMP/auth.h")
fi

# Kaynak türü: yerel dizin, düz URL ya da GitHub release.
SRC_KIND='github'
if [ -n "$FROM" ]; then
	if [ -d "$FROM" ]; then
		SRC_KIND='dir'
	else
		SRC_KIND='url'
		FROM="${FROM%/}"
	fi
fi

ASSETS="$TMP/assets.txt"
if [ "$SRC_KIND" = 'github' ]; then
	if [ -n "$VERSION" ]; then
		API="https://api.github.com/repos/$GITHUB_REPO/releases/tags/$VERSION"
	else
		API="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
	fi
	"${CURL[@]}" "${AUTH[@]}" -H 'Accept: application/vnd.github+json' "$API" -o "$TMP/release.json" ||
		hata "sürüm bilgisi alınamadı (API sınırı aşıldıysa --github-token-file verin): $API"
	# Varlık listesi: "ad url" (url = API varlık adresi; octet-stream ile indirilir).
	awk '
		/"url": *"https:\/\/api\.github\.com\/repos\/[^"]*\/releases\/assets\/[0-9]+"/ {
			u = $0; sub(/.*"url": *"/, "", u); sub(/".*/, "", u); next
		}
		/"name": *"/ && u != "" {
			n = $0; sub(/.*"name": *"/, "", n); sub(/".*/, "", n); print n " " u; u = ""
		}
	' "$TMP/release.json" >"$ASSETS"
	[ -s "$ASSETS" ] || hata "sürümde varlık bulunamadı"
fi

# indir <ad>: kaynaktan $ART/<ad> dosyasına alır.
indir() {
	local ad="$1" url
	case "$ad" in */* | .* | '') hata "geçersiz dosya adı: $ad" ;; esac
	case "$SRC_KIND" in
		dir)
			[ -f "$FROM/$ad" ] || hata "dosya yok: $FROM/$ad"
			cp "$FROM/$ad" "$ART/$ad"
			;;
		url)
			"${CURL[@]}" "${AUTH[@]}" "$FROM/$ad" -o "$ART/$ad" || hata "indirilemedi: $FROM/$ad"
			;;
		github)
			url="$(awk -v n="$ad" '$1 == n { print $2; exit }' "$ASSETS")"
			[ -n "$url" ] || hata "sürümde varlık yok: $ad"
			"${CURL[@]}" "${AUTH[@]}" -H 'Accept: application/octet-stream' "$url" -o "$ART/$ad" ||
				hata "indirilemedi: $ad"
			;;
	esac
}

# imza_dogrula <dosya> <imza>: gömülü ed25519 açık anahtarıyla doğrular.
imza_dogrula() {
	local dosya="$1" imza="$2"
	# SubjectPublicKeyInfo DER öneki (ed25519) + 32 baytlık ham anahtar -> PEM.
	{
		printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'
		printf '%s' "$PUBKEY_B64" | base64 -d
	} >"$TMP/pub.der"
	[ "$(wc -c <"$TMP/pub.der")" -eq 44 ] || hata "gömülü açık anahtar bozuk"
	{
		echo '-----BEGIN PUBLIC KEY-----'
		base64 -w0 <"$TMP/pub.der"
		echo
		echo '-----END PUBLIC KEY-----'
	} >"$TMP/pub.pem"
	base64 -d <"$imza" >"$TMP/sig.bin" 2>/dev/null || hata "imza dosyası okunamadı"
	openssl pkeyutl -verify -pubin -inkey "$TMP/pub.pem" -rawin \
		-in "$dosya" -sigfile "$TMP/sig.bin" >/dev/null 2>&1
}

bilgi "-> SHA256SUMS ve imza indiriliyor"
indir SHA256SUMS
indir SHA256SUMS.sig
imza_dogrula "$ART/SHA256SUMS" "$ART/SHA256SUMS.sig" || hata "İMZA GEÇERSİZ: SHA256SUMS güvenilir değil, kurulum durduruldu"
bilgi "   imza doğru"

# SHA256SUMS'taki tüm dosyalar indirilir (panel install ajan ikililerini,
# ajan-kur.sh'ı, caddy-sp'yi ve imzayı artifacts dizininden dağıtır).
mapfile -t DOSYALAR < <(awk '{ f = $2; sub(/^\*/, "", f); print f }' "$ART/SHA256SUMS")
[ "${#DOSYALAR[@]}" -gt 0 ] || hata "SHA256SUMS boş"
for f in "${DOSYALAR[@]}"; do
	bilgi "-> $f"
	indir "$f"
done

( cd "$ART" && sha256sum -c --ignore-missing --quiet SHA256SUMS ) || hata "ÖZET UYUŞMUYOR: dosyalar bozuk ya da değiştirilmiş, kurulum durduruldu"
PANEL="sunucu-panel_linux_$ARCH"
[ -f "$ART/$PANEL" ] || hata "sürümde $PANEL yok"
bilgi "   özetler doğru ($(cat "$ART/surum" 2>/dev/null || echo '?'))"

if [ "$VERIFY_ONLY" -eq 1 ]; then
	bilgi "doğrulama tamam (--verify-only; kurulum yapılmadı)"
	exit 0
fi

chmod 0755 "$ART/$PANEL"
bilgi "-> sunucu-panel $MODE"
"$ART/$PANEL" "$MODE" --artifacts "$ART" "$@"
