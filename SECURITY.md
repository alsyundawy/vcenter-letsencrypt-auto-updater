# Security Policy

## Sensitive Information Handling

### Credentials Storage

1. **Configuration File Protection:**
   ```bash
   chmod 600 /root/.acme.sh/update.conf
   ```
   - Only readable by root user
   - Contains plaintext password (unavoidable for automation)
   - Never commit to version control

2. **Alternative: Environment Variables**
   
   For enhanced security, modify the script to use environment variables:
   ```bash
   ADMINPASS=${VCENTER_ADMIN_PASS:-}
   ```
   Then set in secure environment:
   ```bash
   export VCENTER_ADMIN_PASS="password"
   ```

3. **Alternative: Credential File in /etc/secrets**
   
   Store with root-only access:
   ```bash
   sudo install -m 600 /dev/null /etc/vcenter-creds.conf
   ```

### Log Security

- Logs are written to `/var/log/vcenter-cert-updater.log`
- No passwords are logged (script sanitizes output)
- Log retention: 30 days (configurable)

## Vulnerability Scanning

### Static Analysis

Run ShellCheck to detect potential issues:

```bash
shellcheck -x auto-updater.sh
```

### Recommended Rules

- ✅ SC2086: Double-quote variables
- ✅ SC2181: Check exit codes
- ✅ SC1091: Source file checking
- ✅ SC2015: Logical operators

## Cryptographic Hash Functions

### MD5 → SHA256 Migration

**Why:**
- MD5 has known collision vulnerabilities
- SHA256 is FIPS-approved
- NIST recommends SHA256 for certificates

**Implementation:**
```bash
# Old (deprecated):
md5sum "$file" | cut -d' ' -f1

# New (secure):
sha256sum "$file" | cut -d' ' -f1
```

## Certificate Validation

### Root Certificate Verification

1. **Download Integrity:**
   - Uses HTTPS with certificate validation
   - Timeout protection against hanging connections
   - Retry logic for transient failures

2. **Content Validation:**
   ```bash
   openssl x509 -in "$file" -noout
   ```
   - Ensures downloaded file is valid X.509 certificate
   - Prevents execution of malicious content

3. **Chain Verification:**
   ```bash
   openssl crl2pkcs7 -nocrl -certfile "$chain"
   ```
   - Validates certificate chain syntax
   - Detects corrupted or incomplete chains

## Access Control

### Required Permissions

```bash
# Script execution
-rwxr-xr-x root:root auto-updater.sh

# Configuration (secrets)
-rw------- root:root /root/.acme.sh/update.conf

# Log file
-rw-r--r-- root:root /var/log/vcenter-cert-updater.log
```

### Sudo Configuration (if needed)

For non-root execution via sudo:

```bash
# /etc/sudoers.d/vcenter-updater
ALLOW_USER ALL=(ALL) NOPASSWD: /path/to/auto-updater.sh
```

## Reporting Security Issues

If you discover a security vulnerability:

1. **Do NOT open a public issue**
2. Email security details to repository maintainer
3. Include:
   - Description of vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if available)

## Security Checklist

- [ ] File permissions verified (600 for config, 755 for script)
- [ ] Configuration file never committed to git
- [ ] Strong vCenter admin password used
- [ ] Logs monitored for errors
- [ ] HTTPS validation enabled for downloads
- [ ] Script runs with minimal required privileges
- [ ] Cron job scheduled during maintenance window
- [ ] Backup of current certificates before update

## Future Improvements

- [ ] Vault/Secrets management integration
- [ ] Certificate backup automation
- [ ] Slack/Email notifications on errors
- [ ] Pre/post-update hooks
- [ ] Rollback capability

## References

- [NIST Hash Function Standards](https://csrc.nist.gov/projects/hash-functions)
- [Let's Encrypt Security](https://letsencrypt.org/docs/security/)
- [vCenter Certificate Management](https://docs.vmware.com/en/VMware-vSphere/)
- [ShellCheck Wiki](https://www.shellcheck.net/)
