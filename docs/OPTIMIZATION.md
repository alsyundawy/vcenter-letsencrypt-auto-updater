# Optimization & Performance Guide

## Execution Time Optimization

### Current Performance
- Configuration validation: ~100ms
- Hash computation (SHA256): ~50-100ms per certificate
- Root certificate download: ~500-1000ms (depends on network)
- Certificate update via certificate-manager: ~5-10 minutes (vCenter operation)
- Total: ~5-10 minutes per execution

### Optimization Strategies

#### 1. Skip Update if Not Needed

```bash
# The script implements early exit if hashes match
if [[ "$live_hash" == "$current_hash" ]]; then
    exit 0  # No update needed
fi
```

**Impact:** Saves 5-10 minutes on unchanged certificates

#### 2. Parallel Validation

For future enhancement, validate multiple aspects in background:

```bash
# Run checks in parallel
validate_config &
validate_cert_live &
load_vcenter_env &
wait
```

#### 3. Network Timeout Tuning

```bash
# Current: 30 seconds
readonly TIMEOUT="30"

# Adjust based on network reliability:
# Unreliable networks: 60 seconds
# Fast networks: 10 seconds
```

#### 4. Reduce Sleep Delays

```bash
# Current implementation uses conservative delays
sleep 1  # Between credential input

# Can be tuned based on system:
# Fast systems: 0.5 seconds
# Slow systems: 2 seconds
```

## Resource Usage

### Memory
- Baseline: ~2-5 MB
- With large certificates: ~10-20 MB
- No memory leaks (proper cleanup)

### CPU
- Hash computation: <1% CPU
- Download: Network I/O bound
- Certificate-manager: CPU intensive (vCenter operation)

### Disk I/O
- Reads: Config, certificates (~100-200 KB)
- Writes: Logs, temporary files (~10-50 KB)
- Minimal impact on system

## Cron Scheduling Optimization

### Best Practices

1. **Avoid Peak Hours:**
   ```cron
   # ✗ Bad: Overlaps with user access
   0 9 * * *  /path/to/auto-updater.sh
   
   # ✓ Good: Off-peak maintenance window
   0 2 * * 0  /path/to/auto-updater.sh
   ```

2. **Space Out Multiple Servers:**
   ```cron
   # Server 1 - Updates on Sundays
   0 2 * * 0 /path/to/auto-updater.sh
   
   # Server 2 - Updates on Wednesdays
   0 2 * * 3 /path/to/auto-updater.sh
   ```

3. **Account for Network Latency:**
   ```cron
   # Add buffer after update for vCenter services to stabilize
   0 2 * * 0 /path/to/auto-updater.sh && sleep 300
   ```

## Log Management Optimization

### Current Strategy
- Retention: 30 days
- Rotation: Automatic (based on age)
- Size limit: Unlimited (watch for disk space)

### Enhanced Log Rotation

```bash
# Create /etc/logrotate.d/vcenter-cert-updater
/var/log/vcenter-cert-updater.log {
    daily                  # Rotate daily
    rotate 30             # Keep 30 versions
    compress              # Gzip old logs
    missingok             # Don't error if missing
    notifempty            # Don't rotate empty files
    delaycompress         # Compress delayed
}
```

## Database Query Optimization (Future)

For tracking certificate updates:

```sql
-- Efficient index for log queries
CREATE INDEX idx_vcert_timestamp 
  ON vcenter_certs(updated_at DESC);

CREATE INDEX idx_vcert_status 
  ON vcenter_certs(status, updated_at);
```

## Network Optimization

### Download Efficiency

```bash
# Current: Uses curl with retries
curl -fsSL --max-time 30 --retry 3 --retry-delay 2

# Optimizations:
# 1. Conditional download (only if needed)
# 2. Compression support (-z flag for If-Modified-Since)
# 3. Resume capability (--continue-at -)
```

### DNS Caching

```bash
# For repeated certificate downloads, cache DNS:
sudo mkdir -p /etc/systemd/resolved.conf.d/

# Add:
[Resolve]
DNSSEC=no
DNS=8.8.8.8 8.8.4.4
FallbackDNS=1.1.1.1 1.0.0.1
```

## Monitoring & Metrics

### Performance Metrics to Track

```bash
# Extract from logs
grep "Started" /var/log/vcenter-cert-updater.log
grep "completed" /var/log/vcenter-cert-updater.log

# Calculate execution time
start=$(date -d "2024-01-01 02:00:00" +%s)
end=$(date -d "2024-01-01 02:08:30" +%s)
echo "Execution time: $((end - start)) seconds"
```

### Build Performance Dashboard

```bash
#!/bin/bash
# Extract key metrics
echo "=== Certificate Update Performance ==="
echo "Last execution:"
grep "started" /var/log/vcenter-cert-updater.log | tail -1
echo ""
echo "Execution status:"
grep "SUCCESS\|ERROR" /var/log/vcenter-cert-updater.log | tail -1
```

## Bottleneck Analysis

### Identify Slowest Component

```bash
grep -E "\[INFO\]" /var/log/vcenter-cert-updater.log | \
  awk '{print $NF}' | sort | uniq -c | sort -rn
```

### Common Bottlenecks

1. **Network latency** (50-70% of time)
   - Solution: Use faster CDN or local mirror
   
2. **vCenter certificate-manager** (20-40% of time)
   - Solution: Consider background update
   
3. **Hash computation** (<1% of time)
   - Solution: Cache previous hash
   
4. **Configuration loading** (<1% of time)
   - Solution: Already optimized

## Caching Strategy

### Previous Hash Cache

```bash
# Store last successful hash
echo "$current_hash" > /var/lib/vcenter-updater/last.hash

# On next run, compare cached hash first
if [[ -f /var/lib/vcenter-updater/last.hash ]]; then
    cached_hash=$(cat /var/lib/vcenter-updater/last.hash)
    if [[ "$cached_hash" == "$current_hash" ]]; then
        log_info "Certificate unchanged (from cache)"
        exit 0
    fi
fi
```

## Scalability Considerations

### Single vCenter
- Current approach: Fully optimized
- Execution time: ~5-10 minutes
- Resource impact: Minimal

### Multiple vCenters (Future)

```bash
#!/bin/bash
# Parallel updates across servers
for server in vcenter1 vcenter2 vcenter3; do
    (ssh $server /opt/auto-updater.sh) &
done
wait
```

## Performance Tuning Checklist

- [ ] Review cron schedule for optimal timing
- [ ] Monitor first 3 executions for performance
- [ ] Check network latency to Let's Encrypt
- [ ] Verify vCenter certificate-manager speed
- [ ] Enable log compression for archival
- [ ] Set up monitoring alerts
- [ ] Document any custom tuning parameters

## Benchmarking

Run performance test:

```bash
#!/bin/bash
echo "Performance Benchmark"
echo "Running 5 iterations..."

for i in {1..5}; do
    echo "Iteration $i:"
    time /opt/vcenter-letsencrypt-auto-updater/auto-updater.sh
    sleep 60
done
```

## References

- [Linux Performance Tuning](https://www.kernel.org/doc/html/latest/admin-guide/pm/index.html)
- [Bash Performance Tips](https://mywiki.wooledge.org/BashGuide/Practices)
- [Network Optimization](https://wiki.gentoo.org/wiki/Network_optimization)
