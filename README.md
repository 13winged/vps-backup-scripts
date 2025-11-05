# 🛡️ VPS Backup Scripts

> Professional automated backup solutions for VPS servers with enterprise-grade features

![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![GitHub](https://img.shields.io/badge/GitHub-13winged-blue?style=for-the-badge&logo=github)

A comprehensive backup solution for VPS servers that provides reliable, automated backups of your system files, databases, and web services with integrity verification and monitoring.

## ✨ Features

| Category | Features |
|----------|----------|
| **🔧 System Backup** | Full system configs, home directories, package lists, user data |
| **🗄️ Database Backup** | MySQL & PostgreSQL support with transaction-safe dumps |
| **🌐 Web Services** | Website files, Nginx/Apache configs, SSL certificates |
| **🔒 Security** | Integrity checks, SHA256 verification, encrypted backups |
| **⚡ Automation** | Cron-ready, retention policies, automatic cleanup |
| **📊 Monitoring** | Detailed logging, email notifications, health checks |

## 🚀 Quick Start

### Prerequisites
- Linux-based VPS
- Bash shell
- Root/sudo access

### Installation

```bash
# Clone the repository
git clone https://github.com/13winged/vps-backup-scripts.git
cd vps-backup-scripts

# Make scripts executable
chmod +x scripts/*.sh

# Configure your backup settings
cp config.example config
nano config
```

### First Run

```bash
# Test full system backup
./scripts/backup-vps.sh

# Test database backup only  
./scripts/db-backup.sh

# Verify backup integrity
./scripts/integrity-check.sh --latest
```

## 📋 Scripts Overview

### `backup-vps.sh` - Full System Backup
```bash
./scripts/backup-vps.sh
```
**Backups:**
- ✅ System configuration (`/etc`)
- ✅ User data (`/home`, `/root`) 
- ✅ Package lists and system info
- ✅ Web directories and configs
- ✅ Database dumps (MySQL/PostgreSQL)

### `db-backup.sh` - Database Backup
```bash
./scripts/db-backup.sh
```
**Features:**
- 🗄️ Transaction-safe MySQL dumps
- 🗄️ PostgreSQL database backups
- 📦 Automatic compression
- 🔄 Incremental backup support

### `integrity-check.sh` - Backup Verification
```bash
./scripts/integrity-check.sh --latest
./scripts/integrity-check.sh --databases
./scripts/integrity-check.sh --file /backup/file.tar.gz
```
**Verification:**
- 🔍 Archive structure validation
- 🔐 SHA256 checksum verification
- 🗄️ Database dump integrity testing
- 🧪 Restoration capability checks

## ⚙️ Configuration

Edit the `config` file to match your environment:

```bash
# ===== BASIC SETTINGS =====
BACKUP_DIR="/backup"
RETENTION_DAYS=7

# ===== BACKUP TARGETS =====  
BACKUP_SYSTEM_FILES=true
BACKUP_WEB_DIRS=true
BACKUP_MYSQL=true
BACKUP_POSTGRES=true

# ===== INTEGRITY CHECKING =====
ENABLE_INTEGRITY_CHECK=true
VERIFY_CHECKSUMS=true

# ===== DATABASE SETTINGS =====
MYSQL_USER="root"
MYSQL_HOST="localhost"
PG_USER="postgres" 
PG_HOST="localhost"
```

## 📅 Automation

### Cron Setup
```bash
# Edit crontab
crontab -e

# Add these entries:
# Full system backup daily at 2:00 AM
0 2 * * * /opt/vps-backup-scripts/scripts/backup-vps.sh

# Database backup every 6 hours  
0 */6 * * * /opt/vps-backup-scripts/scripts/db-backup.sh

# Integrity verification daily at 4:00 AM
0 4 * * * /opt/vps-backup-scripts/scripts/integrity-check.sh --latest

# Cleanup old backups weekly on Sunday
0 3 * * 0 find /backup -name "*.tar.gz" -mtime +7 -delete
```

### Systemd Service (Alternative)
Create `/etc/systemd/system/vps-backup.service`:
```ini
[Unit]
Description=VPS Backup Service
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/opt/vps-backup-scripts/scripts/backup-vps.sh
```

## 🗂️ Backup Structure

```
/backup/
├── 📁 vps-backup-2001-01-01_01-00-01.tar.gz
├── 📁 databases/
│   └── 📁 2001-01-01/
│       ├── 📁 mysql/
│       │   ├── 📄 website_db.sql.gz
│       │   └── 📄 app_db.sql.gz
│       └── 📁 postgresql/
│           └── 📄 cms_db.sql.gz
└── 📁 logs/
    ├── 📄 vps-backup.log
    ├── 📄 db-backup.log
    └── 📄 integrity-check.log
```

## 🔧 Restoration Guide

### Emergency Recovery
```bash
# 1. Extract backup
tar -xzf vps-backup-2024-01-15_02-00-01.tar.gz

# 2. Restore MySQL databases
for db_file in mysql/*.sql.gz; do
    db_name=$(basename "$db_file" .sql.gz)
    echo "Restoring MySQL: $db_name"
    zcat "$db_file" | mysql -u root -p
done

# 3. Restore PostgreSQL databases  
for db_file in postgresql/*.sql.gz; do
    db_name=$(basename "$db_file" .sql.gz)
    echo "Restoring PostgreSQL: $db_name"
    zcat "$db_file" | sudo -u postgres psql
done

# 4. Restore system files
tar -xzf system/etc.tar.gz -C /
tar -xzf system/home.tar.gz -C /
```

### Selective Restoration
```bash
# Restore only specific database
zcat mysql/wordpress.sql.gz | mysql -u root -p wordpress

# Restore only website files
tar -xzf web/var-www.tar.gz -C /

# Restore only configuration
tar -xzf system/etc.tar.gz -C /
```

## 📊 Monitoring & Logs

### Log Files Location
```bash
/var/log/vps-backup.log      # Full backup logs
/var/log/db-backup.log       # Database backup logs  
/var/log/integrity-check.log # Integrity verification logs
```

### Real-time Monitoring
```bash
# Follow backup progress
tail -f /var/log/vps-backup.log

# Check backup status
grep -i "completed\|error\|failed" /var/log/vps-backup.log

# Monitor disk usage
watch df -h /backup
```

### Health Checks
```bash
# Verify latest backup
./scripts/integrity-check.sh --latest

# Check backup age
find /backup -name "*.tar.gz" -mtime -1

# Verify database backups
./scripts/integrity-check.sh --databases
```

## 🛡️ Security Best Practices

### File Permissions
```bash
# Secure configuration file
chmod 600 config
chown root:root config

# Secure backup directory
chmod 700 /backup
chown root:root /backup
```

### Encryption (Optional)
```bash
# Encrypt backups with GPG
tar -czf - /path/to/backup | gpg --encrypt --recipient user@domain.com > backup.tar.gz.gpg

# Decrypt for restoration
gpg --decrypt backup.tar.gz.gpg | tar -xzf -
```

### Remote Backup Security
```bash
# Use SSH keys for remote transfers
ssh-keygen -t rsa -b 4096 -C "backup@vps"
ssh-copy-id backup@remote-server

# Secure S3 backups
aws s3 cp backup.tar.gz s3://my-backup-bucket/ --sse AES256
```

## 🐛 Troubleshooting

### Common Issues & Solutions

| Problem | Solution |
|---------|----------|
| **Permission denied** | Run with `sudo` or check user permissions |
| **MySQL access denied** | Verify MySQL user privileges and credentials |
| **Disk space full** | Increase retention days or cleanup old backups |
| **Backup too slow** | Adjust compression level or exclude large files |
| **Database connection failed** | Check if database service is running |

### Debug Mode
```bash
# Enable verbose output
bash -x ./scripts/backup-vps.sh

# Check specific errors
./scripts/backup-vps.sh 2>&1 | grep -i "error\|warning\|failed"

# Test configuration
./scripts/backup-vps.sh --dry-run
```

### Log Analysis
```bash
# Check for errors in logs
grep -i error /var/log/vps-backup.log

# Monitor backup duration
grep "completed" /var/log/vps-backup.log

# Check backup sizes
ls -lh /backup/*.tar.gz
```

### Development Setup
```bash
# Clone and setup
git clone https://github.com/13winged/vps-backup-scripts.git
cd vps-backup-scripts

# Create test environment
mkdir -p test-backup
export BACKUP_DIR="$PWD/test-backup"

# Run tests
./scripts/backup-vps.sh
./scripts/integrity-check.sh --latest
```

### Reporting Issues
- Use the GitHub Issues page
- Include your system info and configuration
- Provide relevant log files
- Describe steps to reproduce

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Important Warning

**🚨 CRITICAL: Always test your backups!**

> A backup is only useful if it can be restored. Regularly test your backup restoration procedure in a safe, isolated environment to ensure your data can be recovered when needed.

### Testing Checklist
- [ ] Verify backup integrity regularly
- [ ] Test restoration process quarterly
- [ ] Keep multiple backup versions
- [ ] Store backups in separate locations
- [ ] Document restoration procedures

---