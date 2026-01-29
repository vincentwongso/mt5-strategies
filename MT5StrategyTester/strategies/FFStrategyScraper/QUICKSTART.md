# FFStrategyScraper - Quick Start Guide

Get up and running with FFStrategyScraper in 5 minutes!

## 1. Quick Installation

```bash
cd FFStrategyScraper
go mod download
```

## 2. Quick Test (Dry-Run)

Test the scraper without saving any data:

```bash
go run cmd/scraper/main.go -dry-run -log-level debug
```

This will:
- Load the configuration
- Connect to ForexFactory
- Discover and filter threads
- Display what would be scraped
- Exit without saving anything

## 3. First Real Run

Run the scraper with default settings:

```bash
go run cmd/scraper/main.go
```

**What happens:**
1. Reads [`config.yaml`](config.yaml:1) for configuration
2. Creates `./scraper.db` (SQLite database)
3. Creates `./strategies/` folder
4. Creates `./scraper.log` (log file)
5. Discovers threads from ForexFactory
6. Filters threads (min 2000 replies, active within 90 days)
7. Scrapes qualifying threads
8. Downloads attachments
9. Saves structured files

**Expected output:**
```
2026-01-24 14:30:00 INFO Starting application app=FFStrategyScraper version=1.0.0
2026-01-24 14:30:00 INFO Loaded configuration config=./config.yaml
2026-01-24 14:30:00 INFO Initialized database path=./scraper.db
...
2026-01-24 14:35:00 INFO Scraping completed successfully
```

## 4. Check the Results

```bash
# View the strategies folder
ls -la strategies/

# View a scraped strategy
cat strategies/some-strategy-123456/strategy.md

# Check the database
sqlite3 scraper.db "SELECT thread_id, title, total_replies FROM scraped_threads;"

# View the logs
tail -f scraper.log
```

## 5. Build Standalone Executable

```bash
# Build
go build -o scraper cmd/scraper/main.go

# Run
./scraper

# Run with options
./scraper -log-level debug
./scraper -dry-run
./scraper -config custom-config.yaml
```

## Common Use Cases

### 1. Test Configuration Changes

```bash
# Edit config.yaml first, then:
go run cmd/scraper/main.go -dry-run
```

### 2. Run with Debug Logging

```bash
go run cmd/scraper/main.go -log-level debug
```

### 3. Use Custom Config

```bash
go run cmd/scraper/main.go -config ./my-config.yaml
```

### 4. Graceful Stop

While the scraper is running, press **Ctrl+C** to stop gracefully. It will:
1. Stop discovering new threads
2. Complete the current thread
3. Save all progress
4. Display summary

### 5. Continuous Monitoring

```bash
# In one terminal, run the scraper
go run cmd/scraper/main.go

# In another terminal, watch the logs
tail -f scraper.log
```

## Customization

Edit [`config.yaml`](config.yaml:1) to customize behavior:

```yaml
filters:
  min_replies: 2000        # Change to 1000 for more threads
  max_inactive_days: 90    # Change to 180 for older threads

scraper:
  min_delay_seconds: 2     # Increase for slower scraping
  max_delay_seconds: 5     # Adjust rate limiting

output:
  strategies_dir: "./my-strategies"  # Change output location
```

## Output Structure

After running, you'll have:

```
FFStrategyScraper/
├── strategies/              # Scraped strategies
│   ├── awesome-tdi-123456/
│   │   ├── strategy.md      # Main strategy content
│   │   ├── metadata.json    # Full metadata
│   │   └── attachments/     # Downloaded files
│   └── another-strategy-789012/
│       └── ...
├── scraper.db              # SQLite database
├── scraper.log             # Application log
└── config.yaml             # Configuration
```

## Troubleshooting

### "config file not found"
Make sure you're running from the `FFStrategyScraper` directory, or use `-config` flag.

### "failed to open database"
Check file permissions and disk space.

### "no threads found"
- Check internet connection
- Try with `-log-level debug`
- Verify ForexFactory is accessible

### Rate limiting / Connection errors
Increase `min_delay_seconds` and `max_delay_seconds` in config.yaml

## Next Steps

1. Review the full [README.md](README.md) for detailed documentation
2. Customize [`config.yaml`](config.yaml:1) for your needs
3. Check the database schema in [README.md](README.md)
4. Explore the code in `internal/` packages

## Tips

- **Start with dry-run**: Always test changes with `-dry-run` first
- **Use debug logging**: `-log-level debug` helps troubleshoot issues
- **Monitor the logs**: Keep `tail -f scraper.log` running
- **Be patient**: First run may take 10-30 minutes depending on threads found
- **Respect the site**: Don't reduce delays too much; be a good web citizen

## Quick Commands Reference

| Command | Purpose |
|---------|---------|
| `go run cmd/scraper/main.go` | Run scraper |
| `go run cmd/scraper/main.go -dry-run` | Test without saving |
| `go run cmd/scraper/main.go -version` | Show version |
| `go run cmd/scraper/main.go -h` | Show help |
| `go build -o scraper cmd/scraper/main.go` | Build executable |
| `./scraper -log-level debug` | Run with debug logs |
| `Ctrl+C` | Graceful shutdown |

## Support

For issues, check:
1. The log file (`scraper.log`)
2. Run with `-log-level debug`
3. Verify config.yaml syntax
4. Check [README.md](README.md) troubleshooting section

Happy scraping! 🚀
