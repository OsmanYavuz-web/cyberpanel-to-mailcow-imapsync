# CyberPanel → Mailcow IMAPSYNC

`cyberpanel_to_mailcow_imapsync.sh` scripti CyberPanel'den Mailcow'a domain ve posta kutusu taşıma işlemlerini API ve imapsync ile otomatikleştirir.

## Kurulum

```bash
curl -o cyberpanel_to_mailcow_imapsync.sh https://raw.githubusercontent.com/OsmanYavuz-web/cyberpanel-to-mailcow-imapsync/refs/heads/main/cyberpanel_to_mailcow_imapsync.sh
```

## İzinler
```bash

chmod +x cyberpanel_to_mailcow_imapsync.sh
```

## Gereksinimler

- CyberPanel sunucusu erişilebilir olmalı.
- Mailcow sunucusunda `mailcowdockerized_mailcow-network` mevcut olmalı.
- Yerel ortamda `sshpass`, `docker`, `curl` kurulu olmalı.
- Script, GNU/Linux uyumlu bir Bash ortamında çalıştırılmalı.

### Bağımlılık Kurulumu

```bash
# Debian/Ubuntu
sudo apt-get install -y sshpass

# CentOS/RHEL
sudo yum install -y sshpass
```

## Giriş Parametreleri

```
./cyberpanel_to_mailcow_imapsync.sh \
  CYBERPANEL_IP SSH_USER SSH_PASS MYSQL_PASS MAILCOW_API_KEY MAILCOW_HOSTNAME
```

- `CYBERPANEL_IP`: CyberPanel sunucu IP'si
- `SSH_USER` / `SSH_PASS`: CyberPanel sunucusuna SSH ile bağlanacak kullanıcı ve şifre
- `MYSQL_PASS`: CyberPanel'deki `cyberpanel` veritabanı için MySQL şifresi
- `MAILCOW_API_KEY`: Mailcow API anahtarı
- `MAILCOW_HOSTNAME`: Mailcow’un HTTPS hostname’i (örn. `mail.domain.com`)

Script çalışırken ayrıca:

- CyberPanel IMAP hesabı için ortak şifre (tüm hesaplarda aynı kabul edilir)
- Mailcow tarafında oluşturulacak yeni şifre
- Domain importu (E/H) tercihi
- Mailbox migration (E/H) tercihi

sorulur.

## Çalışma Adımları

1. Log dosyaları `migration_full.log`, `FAILED_PASSWORDS.txt` ve `logs/` içinde hazırlanır.
2. SSH bağlantısı ve gerekli araçlar doğrulanır.
3. CyberPanel veritabanından kullanıcı listesi çekilir.
4. Domain importu seçildiyse her domain `v1/add/domain` endpoint’i ile eklenir.
5. Mailbox migration seçildiyse her hesap için:
   - Mailbox ve alias oluşturulur.
   - Kaynak IMAP erişimi test edilir.
   - `gilleslamiral/imapsync` konteyneri ile Mailcow’a senkronize edilir.

## Loglar ve Hata Takibi

- `migration_full.log`: Tüm işlemlerin detaylı logları (SSH testi, kullanıcı sayısı, domain import, mailbox migration).
- `FAILED_PASSWORDS.txt`: IMAP testini geçemeyen hesaplar (sadece mailbox migration sırasında doldurulur).
- `logs/<email_safelog>.log`: İlgili hesabın imapsync çıktısı (sadece mailbox migration sırasında oluşturulur).

## Öneriler

- Scripti çalıştırmadan önce Mailcow’da ilgili domainlerin DNS kayıtlarını hazırlayın.
- Çok sayıda hesapta çalışacaksanız, çalıştırmadan önce `docker pull gilleslamiral/imapsync` ile imajı güncelleyin.
