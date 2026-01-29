# FFStrategyScraper

A Go-based web scraper for collecting and organizing trading strategies from ForexFactory's Trading Systems forum.

## Features

- **Automated Discovery**: Scans ForexFactory forum for trading strategy threads
- **Smart Filtering**: Filters threads based on reply count and activity
- **Content Extraction**: Extracts strategy posts, author updates, and attachments
- **Structured Storage**: Saves strategies in both database and organized file structure
- **Rate Limiting**: Respects website with configurable delays between requests
- **Graceful Shutdown**: Handles interruptions cleanly with signal handling
- **Dry-run Mode**: Test without saving data

## Project Structure

```
FFStrategyScraper/
├── cmd/
│   └── scraper/
│       └── main.go           # Application entry point
├── internal/
│   ├── config/
│   │   └── config.go         # Configuration management
│   ├── models/
│   │   ├── thread.go         # Thread data model
│   │   └── post.go           # Post data model
│   ├── scraper/
│   │   ├── scraper.go        # Main scraping logic
│   │   ├── parser.go         # HTML parsing functions
│   │   └── ratelimit.go      # Rate limiting
│   └── storage/
│       ├── sqlite.go         # Database operations
│       └── filesystem.go     # File system operations
├── config.yaml               # Configuration file
├── go.mod                    # Go module definition
└── README.md                 # This file
```

## Prerequisites

- Go 1.21 or later
- SQLite3 (included via go-sqlite3 driver)

## Installation

1. **Clone or navigate to the project directory:**

```bash
cd FFStrategyScraper
```

2. **Install dependencies:**

```bash
go mod download
```

3. **Verify installation:**

```bash
go mod verify
```

## Configuration

Edit [`config.yaml`](config.yaml:1) to customize the scraper behavior:

```yaml
scraper:
  base_url: "https://www.forexfactory.com"
  forum_path: "/forum/71-trading-systems"
  min_delay_seconds: 2
  max_delay_seconds: 5
  user_agent: "Mozilla/5.0 (compatible; StrategyResearchBot/1.0)"

filters:
  min_replies: 2000        # Minimum reply count
  max_inactive_days: 90    # Maximum days since last reply

output:
  strategies_dir: "./strategies"
  database_path: "./scraper.db"

logging:
  level: "info"            # debug, info, warn, error
  file: "./scraper.log"
```

## Usage

### Basic Usage

Run the scraper with default configuration:

```bash
go run cmd/scraper/main.go
```

### Build and Run

Build a standalone executable:

```bash
go build -o scraper cmd/scraper/main.go
./scraper
```

### Command-line Options

```bash
# Specify custom config file
go run cmd/scraper/main.go -config ./my-config.yaml

# Display version
go run cmd/scraper/main.go -version

# Override log level
go run cmd/scraper/main.go -log-level debug

# Dry-run mode (test without saving)
go run cmd/scraper/main.go -dry-run
```

### Available Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-config` | `./config.yaml` | Path to configuration file |
| `-version` | - | Display version and exit |
| `-log-level` | - | Override log level (debug, info, warn, error) |
| `-dry-run` | `false` | Run without saving to database/disk |

## Output

The scraper creates the following output structure:

```
strategies/
├── awesome-strategy-123456/
│   ├── strategy.md          # Formatted strategy content
│   ├── metadata.json        # Thread metadata
│   └── attachments/         # Downloaded files
│       ├── indicator.ex4
│       └── template.tpl
├── another-strategy-789012/
│   └── ...
└── ...

scraper.db                   # SQLite database with thread info
scraper.log                  # Application log file
```

### Strategy Output Format

Each strategy folder contains:

1. **`strategy.md`**: Markdown-formatted strategy including:
   - Original strategy post
   - Author updates from page 1
   - Attachment references

2. **`metadata.json`**: Complete thread metadata including:
   - Thread statistics (views, replies, dates)
   - Author information
   - All post content
   - Attachment details

3. **`attachments/`**: All downloadable files referenced in the strategy

## Example Output

```
$ go run cmd/scraper/main.go

2026-01-24 14:30:00 INFO Starting application app=FFStrategyScraper version=1.0.0
2026-01-24 14:30:00 INFO Loaded configuration config=./config.yaml
2026-01-24 14:30:00 INFO Initialized database path=./scraper.db
2026-01-24 14:30:01 INFO Initialized file manager strategies_dir=./strategies
2026-01-24 14:30:01 INFO Starting scrape run...
2026-01-24 14:30:05 INFO Discovered 45 threads
2026-01-24 14:30:06 INFO Filtered to 12 qualified threads
2026-01-24 14:30:10 INFO Processing thread 1/12: "TDI Strategy"
...
2026-01-24 14:35:00 INFO Scraping completed successfully

========================================
Scraping Summary
========================================
Statistics:
  Threads Discovered: 45
  Threads Scraped: 12
  Threads Skipped: 33
  Threads Filtered: 0
  Attachments: 28
  Errors: 0
Timing:
  Duration: 4m 59s
  Rate: 2.4 threads/minute
Output:
  Strategies Dir: ./strategies
  Database: ./scraper.db
  Log File: ./scraper.log
========================================
```

## Graceful Shutdown

The scraper handles interruption signals (Ctrl+C, SIGTERM) gracefully:

1. Stops accepting new threads to scrape
2. Completes current thread scraping
3. Updates database with final statistics
4. Displays summary before exit
5. Exit code 2 indicates interrupted execution

## Testing

### Run Unit Tests

```bash
# Run all tests
go test ./...

# Run tests with verbose output
go test -v ./...

# Run tests for specific package
go test -v ./internal/scraper
go test -v ./internal/storage
```

### Run with Coverage

```bash
go test -cover ./...
```

### Dry-run Mode

Test the scraper without saving data:

```bash
go run cmd/scraper/main.go -dry-run -log-level debug
```

## Database Schema

The application creates two tables:

### `scraped_threads`

Stores information about scraped strategy threads:

```sql
CREATE TABLE scraped_threads (
    thread_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    url TEXT NOT NULL,
    author TEXT NOT NULL,
    total_replies INTEGER NOT NULL,
    last_reply_date DATETIME,
    view_count INTEGER NOT NULL,
    scraped_at DATETIME NOT NULL,
    needs_update INTEGER NOT NULL,
    thread_data TEXT  -- Complete thread JSON
);
```

### `scrape_runs`

Tracks scraping runs and their statistics:

```sql
CREATE TABLE scrape_runs (
    run_id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at DATETIME NOT NULL,
    completed_at DATETIME,
    threads_discovered INTEGER NOT NULL,
    threads_scraped INTEGER NOT NULL,
    threads_skipped INTEGER NOT NULL,
    status TEXT NOT NULL
);
```

## Error Handling

The application handles common errors gracefully:

- **Config not found**: Clear error message with file path
- **Database errors**: Automatic retry for locked database
- **Network errors**: Retry with exponential backoff (up to 3 attempts)
- **Parse errors**: Log and continue to next thread
- **Signal interruption**: Graceful shutdown with summary

### Exit Codes

- `0` - Success
- `1` - Error (configuration, database, network, etc.)
- `2` - Interrupted (SIGINT/SIGTERM)

## Rate Limiting

The scraper implements intelligent rate limiting to be respectful:

- Random delay between `min_delay_seconds` and `max_delay_seconds`
- Exponential backoff for retries
- Configurable via config.yaml
- Context-aware (respects cancellation)

## Logging

Logs are written to both stdout and the log file specified in config:

- **Timestamp**: ISO 8601 format
- **Level**: DEBUG, INFO, WARN, ERROR
- **Structured**: Key-value pairs for easy parsing
- **Configurable**: Set level via config or CLI flag

## Troubleshooting

### Database locked errors

The scraper uses WAL mode with a 5-second busy timeout. If you still see locked errors:

1. Ensure no other process is using the database
2. Check disk space
3. Verify file permissions

### No threads found

1. Check your internet connection
2. Verify ForexFactory is accessible
3. Check if the forum URL has changed
4. Try with `-log-level debug` for detailed output

### Parsing failures

1. The HTML structure may have changed
2. Check logs for specific parsing errors
3. File an issue with the thread URL that failed

## Development

### Building for Production

```bash
# Build optimized binary
go build -ldflags="-s -w" -o scraper cmd/scraper/main.go

# Cross-compile for other platforms
GOOS=linux GOARCH=amd64 go build -o scraper-linux cmd/scraper/main.go
GOOS=windows GOARCH=amd64 go build -o scraper.exe cmd/scraper/main.go
```

### Code Organization

- **cmd/scraper/main.go**: Entry point, CLI handling, initialization
- **internal/config**: Configuration loading and validation
- **internal/models**: Data structures for threads and posts
- **internal/scraper**: Core scraping logic and HTML parsing
- **internal/storage**: Database and filesystem operations

## License

This tool is for educational and research purposes. Please respect ForexFactory's terms of service and be considerate with scraping frequency.

## Disclaimer

This scraper is designed to be respectful of ForexFactory's servers with built-in rate limiting. Users are responsible for complying with ForexFactory's terms of service and robots.txt. Use responsibly.
