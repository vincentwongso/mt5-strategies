package storage

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	_ "github.com/mattn/go-sqlite3"

	"github.com/vincent/FFStrategyScraper/internal/models"
)

// Database wraps the SQLite database connection and provides data access methods
type Database struct {
	db *sql.DB
}

// NewDatabase initializes a new SQLite database connection and creates tables if they don't exist
func NewDatabase(dbPath string) (*Database, error) {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Set SQLite-specific optimizations
	pragmas := []string{
		"PRAGMA journal_mode=WAL",          // Write-Ahead Logging for better concurrency
		"PRAGMA synchronous=NORMAL",        // Balance between safety and speed
		"PRAGMA cache_size=10000",          // 10MB cache
		"PRAGMA foreign_keys=ON",           // Enable foreign key constraints
		"PRAGMA temp_store=MEMORY",         // Store temp tables in memory
		"PRAGMA busy_timeout=5000",         // 5 second timeout for locked database
	}

	for _, pragma := range pragmas {
		if _, err := db.Exec(pragma); err != nil {
			db.Close()
			return nil, fmt.Errorf("failed to set pragma %s: %w", pragma, err)
		}
	}

	// Test database connection
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	database := &Database{db: db}

	// Create tables if they don't exist
	if err := database.createTables(); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to create tables: %w", err)
	}

	return database, nil
}

// createTables creates the scraped_threads and scrape_runs tables if they don't exist
func (d *Database) createTables() error {
	// Create scraped_threads table
	createThreadsTable := `
	CREATE TABLE IF NOT EXISTS scraped_threads (
		thread_id TEXT PRIMARY KEY,
		title TEXT NOT NULL,
		url TEXT NOT NULL,
		author TEXT NOT NULL,
		total_replies INTEGER NOT NULL DEFAULT 0,
		last_reply_date DATETIME,
		view_count INTEGER NOT NULL DEFAULT 0,
		scraped_at DATETIME NOT NULL,
		needs_update INTEGER NOT NULL DEFAULT 0,
		thread_data TEXT
	);`

	// Create scrape_runs table
	createRunsTable := `
	CREATE TABLE IF NOT EXISTS scrape_runs (
		run_id INTEGER PRIMARY KEY AUTOINCREMENT,
		started_at DATETIME NOT NULL,
		completed_at DATETIME,
		threads_discovered INTEGER NOT NULL DEFAULT 0,
		threads_scraped INTEGER NOT NULL DEFAULT 0,
		threads_skipped INTEGER NOT NULL DEFAULT 0,
		status TEXT NOT NULL DEFAULT 'running'
	);`

	// Create indexes for better query performance
	createIndexes := `
	CREATE INDEX IF NOT EXISTS idx_scraped_threads_last_reply ON scraped_threads(last_reply_date);
	CREATE INDEX IF NOT EXISTS idx_scraped_threads_needs_update ON scraped_threads(needs_update);
	CREATE INDEX IF NOT EXISTS idx_scrape_runs_status ON scrape_runs(status);
	`

	// Execute table creation in a transaction
	tx, err := d.db.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}

	defer func() {
		if err != nil {
			tx.Rollback()
		}
	}()

	if _, err = tx.Exec(createThreadsTable); err != nil {
		return fmt.Errorf("failed to create scraped_threads table: %w", err)
	}

	if _, err = tx.Exec(createRunsTable); err != nil {
		return fmt.Errorf("failed to create scrape_runs table: %w", err)
	}

	if _, err = tx.Exec(createIndexes); err != nil {
		return fmt.Errorf("failed to create indexes: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// Close closes the database connection
func (d *Database) Close() error {
	if d.db != nil {
		return d.db.Close()
	}
	return nil
}

// SaveThread inserts or updates a thread record in the database
func (d *Database) SaveThread(thread *models.Thread) error {
	if thread == nil {
		return fmt.Errorf("thread cannot be nil")
	}

	// Serialize the entire thread object to JSON for complete storage
	threadData, err := json.Marshal(thread)
	if err != nil {
		return fmt.Errorf("failed to marshal thread data: %w", err)
	}

	query := `
		INSERT INTO scraped_threads (
			thread_id, title, url, author, total_replies, 
			last_reply_date, view_count, scraped_at, needs_update, thread_data
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(thread_id) DO UPDATE SET
			title = excluded.title,
			url = excluded.url,
			author = excluded.author,
			total_replies = excluded.total_replies,
			last_reply_date = excluded.last_reply_date,
			view_count = excluded.view_count,
			scraped_at = excluded.scraped_at,
			needs_update = 0,
			thread_data = excluded.thread_data
	`

	stmt, err := d.db.Prepare(query)
	if err != nil {
		return fmt.Errorf("failed to prepare statement: %w", err)
	}
	defer stmt.Close()

	_, err = stmt.Exec(
		thread.ThreadID,
		thread.Title,
		thread.URL,
		thread.Author.Username,
		thread.Stats.TotalReplies,
		thread.Stats.LastReplyDate,
		thread.Stats.ViewCount,
		thread.ScrapedAt,
		0, // needs_update set to 0 since we just scraped it
		string(threadData),
	)

	if err != nil {
		return fmt.Errorf("failed to save thread: %w", err)
	}

	return nil
}

// GetThread retrieves a thread by its ID from the database
func (d *Database) GetThread(threadID string) (*models.Thread, error) {
	query := `
		SELECT thread_data
		FROM scraped_threads
		WHERE thread_id = ?
	`

	var threadData string
	err := d.db.QueryRow(query, threadID).Scan(&threadData)
	if err == sql.ErrNoRows {
		return nil, nil // Thread not found
	}
	if err != nil {
		return nil, fmt.Errorf("failed to query thread: %w", err)
	}

	var thread models.Thread
	if err := json.Unmarshal([]byte(threadData), &thread); err != nil {
		return nil, fmt.Errorf("failed to unmarshal thread data: %w", err)
	}

	return &thread, nil
}

// IsThreadScraped checks if a thread has already been scraped
func (d *Database) IsThreadScraped(threadID string) (bool, error) {
	query := `SELECT EXISTS(SELECT 1 FROM scraped_threads WHERE thread_id = ?)`

	var exists bool
	err := d.db.QueryRow(query, threadID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check if thread is scraped: %w", err)
	}

	return exists, nil
}

// ThreadNeedsUpdate checks if a thread needs to be re-scraped based on the last reply date
func (d *Database) ThreadNeedsUpdate(threadID string, lastReplyDate time.Time) (bool, error) {
	query := `
		SELECT last_reply_date
		FROM scraped_threads
		WHERE thread_id = ?
	`

	var storedLastReplyDate time.Time
	err := d.db.QueryRow(query, threadID).Scan(&storedLastReplyDate)
	if err == sql.ErrNoRows {
		// Thread not in database, so it needs to be scraped
		return true, nil
	}
	if err != nil {
		return false, fmt.Errorf("failed to query thread update status: %w", err)
	}

	// If the new last reply date is after the stored one, the thread needs updating
	needsUpdate := lastReplyDate.After(storedLastReplyDate)
	
	// If thread needs update, mark it in the database
	if needsUpdate {
		updateQuery := `UPDATE scraped_threads SET needs_update = 1 WHERE thread_id = ?`
		if _, err := d.db.Exec(updateQuery, threadID); err != nil {
			return false, fmt.Errorf("failed to mark thread for update: %w", err)
		}
	}

	return needsUpdate, nil
}

// StartScrapeRun creates a new scrape run record and returns its ID
func (d *Database) StartScrapeRun() (int64, error) {
	query := `
		INSERT INTO scrape_runs (started_at, status)
		VALUES (?, 'running')
	`

	stmt, err := d.db.Prepare(query)
	if err != nil {
		return 0, fmt.Errorf("failed to prepare statement: %w", err)
	}
	defer stmt.Close()

	result, err := stmt.Exec(time.Now().UTC())
	if err != nil {
		return 0, fmt.Errorf("failed to start scrape run: %w", err)
	}

	runID, err := result.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("failed to get run ID: %w", err)
	}

	return runID, nil
}

// UpdateScrapeRun updates the statistics and status of a scrape run
func (d *Database) UpdateScrapeRun(runID int64, discovered, scraped, skipped int, status string) error {
	query := `
		UPDATE scrape_runs
		SET threads_discovered = ?,
		    threads_scraped = ?,
		    threads_skipped = ?,
		    status = ?
		WHERE run_id = ?
	`

	stmt, err := d.db.Prepare(query)
	if err != nil {
		return fmt.Errorf("failed to prepare statement: %w", err)
	}
	defer stmt.Close()

	result, err := stmt.Exec(discovered, scraped, skipped, status, runID)
	if err != nil {
		return fmt.Errorf("failed to update scrape run: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("scrape run with ID %d not found", runID)
	}

	return nil
}

// CompleteScrapeRun marks a scrape run as completed
func (d *Database) CompleteScrapeRun(runID int64) error {
	query := `
		UPDATE scrape_runs
		SET completed_at = ?,
		    status = 'completed'
		WHERE run_id = ?
	`

	stmt, err := d.db.Prepare(query)
	if err != nil {
		return fmt.Errorf("failed to prepare statement: %w", err)
	}
	defer stmt.Close()

	result, err := stmt.Exec(time.Now().UTC(), runID)
	if err != nil {
		return fmt.Errorf("failed to complete scrape run: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("scrape run with ID %d not found", runID)
	}

	return nil
}

// GetAllScrapedThreadIDs returns a list of all thread IDs that have been scraped
func (d *Database) GetAllScrapedThreadIDs() ([]string, error) {
	query := `SELECT thread_id FROM scraped_threads ORDER BY scraped_at DESC`

	rows, err := d.db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("failed to query scraped threads: %w", err)
	}
	defer rows.Close()

	var threadIDs []string
	for rows.Next() {
		var threadID string
		if err := rows.Scan(&threadID); err != nil {
			return nil, fmt.Errorf("failed to scan thread ID: %w", err)
		}
		threadIDs = append(threadIDs, threadID)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating rows: %w", err)
	}

	return threadIDs, nil
}
