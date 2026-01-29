package storage

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/vincent/FFStrategyScraper/internal/models"
)

// FileManager handles filesystem operations for strategy storage
type FileManager struct {
	baseDir string
}

// NewFileManager initializes a new FileManager with the specified base directory
func NewFileManager(baseDir string) (*FileManager, error) {
	if baseDir == "" {
		return nil, fmt.Errorf("base directory cannot be empty")
	}

	// Create base directory if it doesn't exist
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create base directory: %w", err)
	}

	return &FileManager{
		baseDir: baseDir,
	}, nil
}

// CreateStrategyFolder creates a new folder for a strategy with slugified name
// Returns the full path to the created folder
func (fm *FileManager) CreateStrategyFolder(threadID, title string) (string, error) {
	if threadID == "" {
		return "", fmt.Errorf("thread ID cannot be empty")
	}

	// Create folder name: slugified-title-threadID
	slug := slugify(title)
	folderName := fmt.Sprintf("%s-%s", slug, threadID)
	folderPath := filepath.Join(fm.baseDir, folderName)

	// Create strategy folder
	if err := os.MkdirAll(folderPath, 0755); err != nil {
		return "", fmt.Errorf("failed to create strategy folder: %w", err)
	}

	// Create attachments subfolder
	attachmentsPath := filepath.Join(folderPath, "attachments")
	if err := os.MkdirAll(attachmentsPath, 0755); err != nil {
		return "", fmt.Errorf("failed to create attachments folder: %w", err)
	}

	return folderPath, nil
}

// SaveStrategyMarkdown generates and saves the strategy.md file from thread and posts
func (fm *FileManager) SaveStrategyMarkdown(folderPath string, thread *models.Thread, posts []*models.Post) error {
	if thread == nil {
		return fmt.Errorf("thread cannot be nil")
	}
	if posts == nil || len(posts) == 0 {
		return fmt.Errorf("posts cannot be empty")
	}

	// Build markdown content
	var builder strings.Builder

	// Header section
	builder.WriteString(fmt.Sprintf("# %s\n\n", thread.Title))
	builder.WriteString(fmt.Sprintf("**Author**: %s\n", thread.Author.Username))
	builder.WriteString(fmt.Sprintf("**Thread**: [View on ForexFactory](%s)\n", thread.URL))
	
	// Format first post date
	firstPostDate := thread.Stats.FirstPostDate.Format("2006-01-02")
	builder.WriteString(fmt.Sprintf("**Posted**: %s\n\n", firstPostDate))

	// Find and add original post (Post #1)
	var originalPost *models.Post
	var authorUpdates []*models.Post

	for _, post := range posts {
		if post.IsOriginalPost {
			originalPost = post
		} else if post.AuthorUsername == thread.Author.Username {
			authorUpdates = append(authorUpdates, post)
		}
	}

	// Original strategy post
	if originalPost != nil {
		builder.WriteString("## Original Strategy Post\n\n")
		builder.WriteString(originalPost.Content)
		builder.WriteString("\n\n")

		// Add attachment info if present
		if originalPost.HasAttachments() {
			builder.WriteString("**Attachments:**\n")
			for _, att := range originalPost.Attachments {
				builder.WriteString(fmt.Sprintf("- %s (%s)\n", att.Filename, att.Type))
			}
			builder.WriteString("\n")
		}
	}

	// Author updates section
	if len(authorUpdates) > 0 {
		builder.WriteString("## Author Updates (Page 1)\n\n")

		for i, post := range authorUpdates {
			postDate := post.PostedAt.Format("2006-01-02")
			builder.WriteString(fmt.Sprintf("### Update %d - Posted: %s\n\n", i+1, postDate))
			builder.WriteString(post.Content)
			builder.WriteString("\n\n")

			// Add attachment info if present
			if post.HasAttachments() {
				builder.WriteString("**Attachments:**\n")
				for _, att := range post.Attachments {
					builder.WriteString(fmt.Sprintf("- %s (%s)\n", att.Filename, att.Type))
				}
				builder.WriteString("\n")
			}
		}
	}

	// Write to file
	markdownPath := filepath.Join(folderPath, "strategy.md")
	if err := os.WriteFile(markdownPath, []byte(builder.String()), 0644); err != nil {
		return fmt.Errorf("failed to write strategy markdown: %w", err)
	}

	return nil
}

// SaveMetadataJSON saves the thread metadata as JSON
func (fm *FileManager) SaveMetadataJSON(folderPath string, thread *models.Thread) error {
	if thread == nil {
		return fmt.Errorf("thread cannot be nil")
	}

	// Serialize thread to JSON
	jsonData, err := thread.ToJSON()
	if err != nil {
		return fmt.Errorf("failed to serialize thread to JSON: %w", err)
	}

	// Write to file
	metadataPath := filepath.Join(folderPath, "metadata.json")
	if err := os.WriteFile(metadataPath, jsonData, 0644); err != nil {
		return fmt.Errorf("failed to write metadata JSON: %w", err)
	}

	return nil
}

// SaveAttachment saves an attachment file to the attachments subfolder
func (fm *FileManager) SaveAttachment(folderPath, filename string, data []byte) error {
	if filename == "" {
		return fmt.Errorf("filename cannot be empty")
	}
	if data == nil || len(data) == 0 {
		return fmt.Errorf("attachment data cannot be empty")
	}

	// Get attachment path
	attachmentPath := fm.GetAttachmentPath(folderPath, filename)

	// Write to file
	if err := os.WriteFile(attachmentPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write attachment: %w", err)
	}

	return nil
}

// StrategyFolderExists checks if a strategy folder exists for the given thread ID
// Returns (exists bool, folder path, error)
func (fm *FileManager) StrategyFolderExists(threadID string) (bool, string, error) {
	if threadID == "" {
		return false, "", fmt.Errorf("thread ID cannot be empty")
	}

	// Read directory entries
	entries, err := os.ReadDir(fm.baseDir)
	if err != nil {
		if os.IsNotExist(err) {
			return false, "", nil
		}
		return false, "", fmt.Errorf("failed to read base directory: %w", err)
	}

	// Look for folder ending with the thread ID
	suffix := "-" + threadID
	for _, entry := range entries {
		if entry.IsDir() && strings.HasSuffix(entry.Name(), suffix) {
			folderPath := filepath.Join(fm.baseDir, entry.Name())
			return true, folderPath, nil
		}
	}

	return false, "", nil
}

// GetAttachmentPath returns the full path for an attachment file
func (fm *FileManager) GetAttachmentPath(folderPath, filename string) string {
	return filepath.Join(folderPath, "attachments", filename)
}

// slugify converts a string to a filesystem-safe slug
// Example: "My Strategy Name!" -> "my-strategy-name"
func slugify(text string) string {
	// Convert to lowercase
	slug := strings.ToLower(text)

	// Replace spaces and underscores with hyphens
	slug = strings.ReplaceAll(slug, " ", "-")
	slug = strings.ReplaceAll(slug, "_", "-")

	// Remove special characters (keep only alphanumeric and hyphens)
	reg := regexp.MustCompile("[^a-z0-9-]+")
	slug = reg.ReplaceAllString(slug, "")

	// Remove multiple consecutive hyphens
	reg = regexp.MustCompile("-+")
	slug = reg.ReplaceAllString(slug, "-")

	// Trim hyphens from start and end
	slug = strings.Trim(slug, "-")

	// Limit length to avoid filesystem issues
	if len(slug) > 50 {
		slug = slug[:50]
		slug = strings.TrimRight(slug, "-")
	}

	// Fallback if slug is empty
	if slug == "" {
		slug = "strategy"
	}

	return slug
}
