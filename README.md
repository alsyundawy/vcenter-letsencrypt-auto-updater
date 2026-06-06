# vCenter LetsEncrypt Auto-Updater

Automatically keep Let's Encrypt certificates for vCenter Appliance up to date using acme.sh, certificate-manager, and Crontab.

## Features

✅ **Security Hardened**
- Replaced deprecated MD5 hashing with SHA256
- Validates X.509 certificates during download
- Secure credential handling
- File permission enforcement

✅ **Robust Error Handling**
- Comprehensive validation of configuration and certificates
- Automatic lockfile management (prevents concurrent execution)
- Detailed logging with retention policy
- Graceful error recovery

✅ **Modern Best Practices**
- Strict shell mode (`set -euo pipefail`)
- Readonly variables for security
- Proper signal handling with cleanup
- Timeout support for network operations
- Colored output for easy log reading

✅ **Production Ready**
- Log rotation (30-day retention)
- JSON-compatible output ready
- Comprehensive documentation
- Compatible with vCenter 7.x and 8.x

## Prerequisites

- vCenter Appliance (tested on 7.x, 8.x)
- acme.sh configured and working
- Root access
- Basic utilities: bash, curl, openssl, md5sum, sha256sum

## Installation

### 1. Clone Repository

```bash
git clone https://github.com/alsyundawy/vcenter-letsencrypt-auto-updater.git
cd vcenter-letsencrypt-auto-updater
```

### 2. Configure Credentials

```bash
cp update.conf /root/.acme.sh/update.conf
chmod 600 /root/.acme.sh/update.conf

# Edit with your credentials
vim /root/.acme.sh/update.conf
```

**Configuration variables:**
- `CERTNAME`: Domain name as registered in acme.sh (e.g., `vcenter.example.com`)
- `ADMINACCOUNT`: vCenter admin account (e.g., `administrator@vsphere.local`)
- `ADMINPASS`: vCenter admin password

### 3. Set Permissions

```bash
chmod 755 auto-updater.sh
chmod 600 /root/.acme.sh/update.conf
```

### 4. Test Manually

```bash
./auto-updater.sh
```

Check the output and log file:
```bash
tail -f /var/log/vcenter-cert-updater.log
```

## Crontab Setup

Schedule the script to run regularly (e.g., daily at 2 AM):

```bash
crontab -e
```

Add the following line:

```cron
# Update vCenter certificate daily at 2 AM
0 2 * * * /path/to/auto-updater.sh >> /var/log/vcenter-cert-updater.log 2>&1
```

For weekly updates (every Sunday at 3 AM):

```cron
0 3 * * 0 /path/to/auto-updater.sh >> /var/log/vcenter-cert-updater.log 2>&1
```

## How It Works

1. **Configuration Validation**: Verifies all required settings and certificates exist
2. **Certificate Comparison**: Uses SHA256 hashing to compare current vs. new certificate
3. **Chain Building**: Downloads Let's Encrypt root certificate and builds full chain
4. **Certificate Update**: Uses vCenter's certificate-manager to install new certificate
5. **Logging**: Records all operations for audit trail

## Logging

Logs are written to `/var/log/vcenter-cert-updater.log`

**Log Levels:**
- `[INFO]` - Normal operation
- `[WARN]` - Non-critical issues
- `[ERROR]` - Critical errors (stderr)
- `[SUCCESS]` - Successful operations

**View logs:**

```bash
# Real-time monitoring
tail -f /var/log/vcenter-cert-updater.log

# Recent errors
grep ERROR /var/log/vcenter-cert-updater.log

# Successful updates
grep SUCCESS /var/log/vcenter-cert-updater.log
```

## Troubleshooting

### Certificate not found error

```
ERROR: Certificate not found: /root/.acme.sh/my.certificate.name/my.certificate.name.cer
```

**Solution:** Ensure acme.sh has successfully issued the certificate:

```bash
/root/.acme.sh/acme.sh --list
```

### Configuration file not found

```
ERROR: Configuration file not found: /root/.acme.sh/update.conf
```

**Solution:** Create configuration file as described in Installation section.

### Certificate manager not found

```
ERROR: Failed to update certificate
```

**Solution:** Verify vCenter is running and certificate-manager is available:

```bash
ls -la /usr/lib/vmware-vmca/bin/certificate-manager
```

### Lock file prevents execution

```
ERROR: Another instance is already running
```

**Solution:** Check if another instance is running:

```bash
ps aux | grep auto-updater.sh
rm -f /var/run/vcenter-cert-updater.lock
```

## Security Best Practices

1. **Protect configuration file:**
   ```bash
   chmod 600 /root/.acme.sh/update.conf
   ```

2. **Use strong credentials:**
   - Use service account with minimal required permissions
   - Never commit `update.conf` to version control

3. **Monitor logs:**
   - Regularly review `/var/log/vcenter-cert-updater.log`
   - Set up alerts for errors

4. **Test before production:**
   ```bash
   ./auto-updater.sh
   # Verify vCenter accessibility
   ```

## License

GNU General Public License v3.0 - See LICENSE file for details

## Original Work

Based on original script by Rob Thomas (xrobau@linux.com)
For information: https://wiki.9r.com.au/display/9R/LetsEncrypt+Certificates+for+vCenter+and+PSC

## Contributing

Contributions welcome! Please ensure:
- Code follows shellcheck standards
- Changes include documentation
- Security implications are considered
- Backward compatibility is maintained

## Support

For issues, questions, or improvements, please open an issue on GitHub.
