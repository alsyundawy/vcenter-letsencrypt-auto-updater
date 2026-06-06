# Installation Guide

## Prerequisites

### System Requirements
- vCenter Appliance 7.0+ or 8.0+
- RHEL/CentOS/Photon OS base system
- Bash 4.0+
- Root access

### Required Tools
```bash
# Verify installation
which bash curl openssl sha256sum
```

### acme.sh Configuration
Ensure acme.sh is properly installed and configured:

```bash
# Check acme.sh installation
/root/.acme.sh/acme.sh --version

# List issued certificates
/root/.acme.sh/acme.sh --list
```

## Step-by-Step Installation

### 1. Clone Repository

```bash
cd /opt
git clone https://github.com/alsyundawy/vcenter-letsencrypt-auto-updater.git
cd vcenter-letsencrypt-auto-updater
```

### 2. Setup Configuration

```bash
# Create backup of existing config if present
if [ -f /root/.acme.sh/update.conf ]; then
    cp /root/.acme.sh/update.conf /root/.acme.sh/update.conf.bak
fi

# Copy template
cp update.conf /root/.acme.sh/update.conf

# Set restrictive permissions
chmod 600 /root/.acme.sh/update.conf

# Edit with your values
vim /root/.acme.sh/update.conf
```

### 3. Verify Configuration

```bash
# Check file permissions
ls -la /root/.acme.sh/update.conf
# Output: -rw------- 1 root root 84 Jun  6 10:00 /root/.acme.sh/update.conf

# Verify certificate existence
CERTNAME=$(grep CERTNAME /root/.acme.sh/update.conf | cut -d\' -f2)
ls -la /root/.acme.sh/$CERTNAME/
```

### 4. Set Script Permissions

```bash
chmod 755 /opt/vcenter-letsencrypt-auto-updater/auto-updater.sh
ls -la /opt/vcenter-letsencrypt-auto-updater/auto-updater.sh
```

### 5. Test Execution

```bash
# Run as root
sudo /opt/vcenter-letsencrypt-auto-updater/auto-updater.sh

# Monitor output
tail -f /var/log/vcenter-cert-updater.log
```

### 6. Cron Job Setup

**Option A: Daily Update**

```bash
# Edit crontab
sudo crontab -e

# Add line (updates daily at 2 AM)
0 2 * * * /opt/vcenter-letsencrypt-auto-updater/auto-updater.sh
```

**Option B: Weekly Update**

```cron
# Sunday at 3 AM
0 3 * * 0 /opt/vcenter-letsencrypt-auto-updater/auto-updater.sh
```

**Option C: Bi-weekly Update**

```cron
# 1st and 15th at 2 AM
0 2 1,15 * * /opt/vcenter-letsencrypt-auto-updater/auto-updater.sh
```

### 7. Verify Cron Setup

```bash
# List scheduled jobs
sudo crontab -l | grep auto-updater

# Check cron logs
sudo grep auto-updater /var/log/cron
```

## Configuration Parameters

### CERTNAME

The domain name as registered with acme.sh:

```bash
# Find your certificate name
/root/.acme.sh/acme.sh --list | grep -E '^[^|]*\|'

# Example output
# Main_Domain   |San Domains                  |AcmeVersion|Created     |Renew
# vcenter.example.com|vcenter.example.com|acme_v2|2024-01-10T00:00:00Z|2024-04-10T00:00:00Z

CERTNAME='vcenter.example.com'  # Use Main_Domain
```

### ADMINACCOUNT

The vCenter administrator account:

```bash
# Default accounts
ADMINCOUNT='administrator@vsphere.local'  # Standard vCenter SSO
ADMINCOUNT='root@psc.local'              # PSC (Platform Services Controller)
ADMINCOUNT='administrator@yourdomain.local'  # Custom domain
```

### ADMINPASS

The password for the administrator account:

```bash
# Requirements
# - Must be the EXACT password (no escaping needed)
# - File permissions MUST be 600
# - Never commit to version control
ADMINPASS='YourSecurePassword123!'
```

## Validation Checklist

```bash
#!/bin/bash
echo "=== Installation Validation ==="

echo "[1] Checking script..."
test -f /opt/vcenter-letsencrypt-auto-updater/auto-updater.sh && echo "✓ Script found" || echo "✗ Script missing"

echo "[2] Checking configuration..."
test -f /root/.acme.sh/update.conf && echo "✓ Config found" || echo "✗ Config missing"

echo "[3] Checking permissions..."
perms=$(stat -c %a /root/.acme.sh/update.conf)
if [ "$perms" == "600" ]; then
    echo "✓ Config permissions correct (600)"
else
    echo "✗ Config permissions incorrect ($perms, should be 600)"
fi

echo "[4] Checking certificate..."
CERTNAME=$(grep CERTNAME /root/.acme.sh/update.conf | cut -d\' -f2)
test -f /root/.acme.sh/$CERTNAME/$CERTNAME.cer && echo "✓ Certificate found" || echo "✗ Certificate missing"

echo "[5] Checking cron job..."
sudo crontab -l 2>/dev/null | grep auto-updater && echo "✓ Cron job configured" || echo "✗ Cron job not found"

echo "[6] Testing script execution..."
/opt/vcenter-letsencrypt-auto-updater/auto-updater.sh && echo "✓ Script executed successfully" || echo "✗ Script execution failed"

echo "[7] Checking logs..."
test -f /var/log/vcenter-cert-updater.log && echo "✓ Log file created" || echo "✗ Log file missing"

echo "=== Validation Complete ==="
```

Run the validation:

```bash
bash validation_checklist.sh
```

## Troubleshooting Installation

### Script not executable

```bash
chmod 755 /opt/vcenter-letsencrypt-auto-updater/auto-updater.sh
```

### Configuration file permission errors

```bash
chmod 600 /root/.acme.sh/update.conf
ls -la /root/.acme.sh/update.conf  # Verify
```

### Certificate not found

```bash
# List available certificates
/root/.acme.sh/acme.sh --list

# Check directory
ls -la /root/.acme.sh/
```

### Cron job not executing

```bash
# Check cron daemon
sudo systemctl status crond

# Check cron logs
sudo tail -50 /var/log/cron | grep auto-updater

# Test cron permissions
sudo ls -la /var/spool/cron/root
```

## Post-Installation

1. **Monitor First Execution:**
   ```bash
   tail -f /var/log/vcenter-cert-updater.log
   ```

2. **Verify Certificate Update:**
   ```bash
   openssl x509 -in /etc/vmware-rhttpproxy/ssl/rui.crt -text -noout | grep -A2 "Validity"
   ```

3. **Set Up Monitoring:**
   - Configure log rotation
   - Set up alerts for errors
   - Monitor vCenter accessibility

## Uninstallation

```bash
# Remove cron job
sudo crontab -e  # Remove the auto-updater line

# Remove script
sudo rm -rf /opt/vcenter-letsencrypt-auto-updater

# Optional: Keep config for future reference
# Or remove: rm /root/.acme.sh/update.conf
```
