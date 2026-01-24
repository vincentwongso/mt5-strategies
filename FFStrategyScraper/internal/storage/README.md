# Storage Package

This package handles all filesystem and database operations for the FFStrategyScraper.

## FileManager

The `FileManager` struct provides operations for saving strategy content to the filesystem.

### Initialization

```go
import "github.com/vincent/FFStrategyScraper/internal/storage"

fm, err := storage.NewFileManager("./strategies")
if err != nil {
    log.Fatal(err)
}
```

### Creating Strategy Folders

Creates a folder with the pattern: `slugified-title-threadID`

```go
folderPath, err := fm.CreateStrategyFolder("123456", "My Trading Strategy")
// Creates: strategies/my-trading-strategy-123456/
//          strategies/my-trading-strategy-123456/attachments/
```

### Saving Strategy Content

#### Save Markdown Strategy File

Generates a markdown file with the strategy content following the format defined in the implementation plan:

```go
err := fm.SaveStrategyMarkdown(folderPath, thread, posts)
// Saves to: strategies/my-trading-strategy-123456/strategy.md
```

Generated format:
```markdown
# Strategy Name

**Author**: Username
**Thread**: [View on ForexFactory](url)
**Posted**: 2018-01-15

## Original Strategy Post

[Post #1 content]

## Author Updates (Page 1)

### Update 1 - Posted: 2018-02-20
[Author follow-up content]
```

#### Save Metadata JSON

Saves the complete thread metadata as JSON:

```go
err := fm.SaveMetadataJSON(folderPath, thread)
// Saves to: strategies/my-trading-strategy-123456/metadata.json
```

#### Save Attachments

Saves attachment files to the attachments subfolder:

```go
err := fm.SaveAttachment(folderPath, "indicator_v2.mq5", fileData)
// Saves to: strategies/my-trading-strategy-123456/attachments/indicator_v2.mq5
```

### Checking for Existing Strategies

Check if a strategy folder already exists for a thread ID:

```go
exists, folderPath, err := fm.StrategyFolderExists("123456")
if exists {
    fmt.Printf("Strategy already exists at: %s\n", folderPath)
}
```

### Utility Functions

#### Get Attachment Path

Get the full path for an attachment file:

```go
path := fm.GetAttachmentPath(folderPath, "indicator.mq5")
// Returns: strategies/my-trading-strategy-123456/attachments/indicator.mq5
```

### Slugify Function

The `slugify` function converts strategy titles to filesystem-safe names:

- Converts to lowercase
- Replaces spaces and underscores with hyphens
- Removes special characters (keeps only alphanumeric and hyphens)
- Removes multiple consecutive hyphens
- Limits length to 50 characters
- Fallback to "strategy" if empty

Examples:
- `"My Strategy Name"` → `"my-strategy-name"`
- `"Strategy with CAPS"` → `"strategy-with-caps"`
- `"Strategy!@#$%"` → `"strategy"`

## Error Handling

All functions return descriptive errors for common issues:
- Empty required parameters
- Directory creation failures
- File write failures
- Invalid data

Always check errors:

```go
if err != nil {
    log.Printf("Failed to save strategy: %v", err)
    return err
}
```

## File Structure

The package creates the following structure:

```
strategies/
├── strategy-name-123456/
│   ├── strategy.md      # Main strategy content
│   ├── metadata.json    # Full metadata
│   └── attachments/
│       ├── indicator_v2.mq5
│       └── strategy_guide.pdf
```

## Testing

Run tests with:
```bash
go test -v ./internal/storage/
```

All functions are thoroughly tested with unit tests covering:
- Slugify edge cases
- Directory creation
- File writing
- Attachment handling
- Existence checks
