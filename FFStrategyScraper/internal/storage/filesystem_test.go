package storage

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/vincent/FFStrategyScraper/internal/models"
)

func TestSlugify(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"My Strategy Name", "my-strategy-name"},
		{"Strategy with CAPS", "strategy-with-caps"},
		{"Strategy!@#$%^&*()", "strategy"},
		{"Multiple   Spaces", "multiple-spaces"},
		{"Strategy_with_underscores", "strategy-with-underscores"},
		{"", "strategy"},
		{"Very Long Strategy Name That Exceeds Fifty Characters And Should Be Truncated", "very-long-strategy-name-that-exceeds-fifty-charact"},
	}

	for _, test := range tests {
		result := slugify(test.input)
		if result != test.expected {
			t.Errorf("slugify(%q) = %q, expected %q", test.input, result, test.expected)
		}
	}
}

func TestNewFileManager(t *testing.T) {
	tempDir := t.TempDir()

	fm, err := NewFileManager(tempDir)
	if err != nil {
		t.Fatalf("NewFileManager failed: %v", err)
	}

	if fm.baseDir != tempDir {
		t.Errorf("Expected baseDir %q, got %q", tempDir, fm.baseDir)
	}

	// Verify directory was created
	if _, err := os.Stat(tempDir); os.IsNotExist(err) {
		t.Error("Base directory was not created")
	}
}

func TestCreateStrategyFolder(t *testing.T) {
	tempDir := t.TempDir()
	fm, _ := NewFileManager(tempDir)

	folderPath, err := fm.CreateStrategyFolder("123456", "Test Strategy")
	if err != nil {
		t.Fatalf("CreateStrategyFolder failed: %v", err)
	}

	// Verify folder was created
	if _, err := os.Stat(folderPath); os.IsNotExist(err) {
		t.Error("Strategy folder was not created")
	}

	// Verify attachments subfolder was created
	attachmentsPath := filepath.Join(folderPath, "attachments")
	if _, err := os.Stat(attachmentsPath); os.IsNotExist(err) {
		t.Error("Attachments folder was not created")
	}

	// Verify folder name format
	expectedFolderName := "test-strategy-123456"
	if filepath.Base(folderPath) != expectedFolderName {
		t.Errorf("Expected folder name %q, got %q", expectedFolderName, filepath.Base(folderPath))
	}
}

func TestSaveStrategyMarkdown(t *testing.T) {
	tempDir := t.TempDir()
	fm, _ := NewFileManager(tempDir)
	folderPath, _ := fm.CreateStrategyFolder("123456", "Test Strategy")

	// Create test data
	thread := models.NewThread("123456", "Test Strategy", "https://example.com/thread")
	thread.Author.Username = "TestUser"
	thread.Stats.FirstPostDate = time.Date(2024, 1, 15, 10, 30, 0, 0, time.UTC)

	post1 := models.NewPost("1", "123456", "TestUser", 1)
	post1.Content = "This is the original strategy post."
	post1.PostedAt = time.Date(2024, 1, 15, 10, 30, 0, 0, time.UTC)

	post2 := models.NewPost("2", "123456", "TestUser", 2)
	post2.Content = "This is an update from the author."
	post2.PostedAt = time.Date(2024, 2, 20, 12, 0, 0, 0, time.UTC)

	posts := []*models.Post{post1, post2}

	// Save markdown
	err := fm.SaveStrategyMarkdown(folderPath, thread, posts)
	if err != nil {
		t.Fatalf("SaveStrategyMarkdown failed: %v", err)
	}

	// Verify file was created
	markdownPath := filepath.Join(folderPath, "strategy.md")
	if _, err := os.Stat(markdownPath); os.IsNotExist(err) {
		t.Error("strategy.md was not created")
	}

	// Read and verify content
	content, err := os.ReadFile(markdownPath)
	if err != nil {
		t.Fatalf("Failed to read strategy.md: %v", err)
	}

	contentStr := string(content)
	if !contains(contentStr, "# Test Strategy") {
		t.Error("Markdown missing title")
	}
	if !contains(contentStr, "**Author**: TestUser") {
		t.Error("Markdown missing author")
	}
	if !contains(contentStr, "## Original Strategy Post") {
		t.Error("Markdown missing original post section")
	}
	if !contains(contentStr, "This is the original strategy post.") {
		t.Error("Markdown missing original post content")
	}
}

func TestSaveMetadataJSON(t *testing.T) {
	tempDir := t.TempDir()
	fm, _ := NewFileManager(tempDir)
	folderPath, _ := fm.CreateStrategyFolder("123456", "Test Strategy")

	// Create test data
	thread := models.NewThread("123456", "Test Strategy", "https://example.com/thread")
	thread.Author.Username = "TestUser"

	// Save metadata
	err := fm.SaveMetadataJSON(folderPath, thread)
	if err != nil {
		t.Fatalf("SaveMetadataJSON failed: %v", err)
	}

	// Verify file was created
	metadataPath := filepath.Join(folderPath, "metadata.json")
	if _, err := os.Stat(metadataPath); os.IsNotExist(err) {
		t.Error("metadata.json was not created")
	}
}

func TestSaveAttachment(t *testing.T) {
	tempDir := t.TempDir()
	fm, _ := NewFileManager(tempDir)
	folderPath, _ := fm.CreateStrategyFolder("123456", "Test Strategy")

	// Test data
	filename := "test_indicator.mq5"
	data := []byte("// This is a test indicator file")

	// Save attachment
	err := fm.SaveAttachment(folderPath, filename, data)
	if err != nil {
		t.Fatalf("SaveAttachment failed: %v", err)
	}

	// Verify file was created in attachments folder
	attachmentPath := fm.GetAttachmentPath(folderPath, filename)
	if _, err := os.Stat(attachmentPath); os.IsNotExist(err) {
		t.Error("Attachment file was not created")
	}

	// Verify content
	savedData, err := os.ReadFile(attachmentPath)
	if err != nil {
		t.Fatalf("Failed to read attachment: %v", err)
	}
	if string(savedData) != string(data) {
		t.Error("Attachment content does not match")
	}
}

func TestStrategyFolderExists(t *testing.T) {
	tempDir := t.TempDir()
	fm, _ := NewFileManager(tempDir)

	// Test non-existent folder
	exists, _, err := fm.StrategyFolderExists("999999")
	if err != nil {
		t.Fatalf("StrategyFolderExists failed: %v", err)
	}
	if exists {
		t.Error("Expected folder to not exist")
	}

	// Create a folder
	folderPath, _ := fm.CreateStrategyFolder("123456", "Test Strategy")

	// Test existing folder
	exists, foundPath, err := fm.StrategyFolderExists("123456")
	if err != nil {
		t.Fatalf("StrategyFolderExists failed: %v", err)
	}
	if !exists {
		t.Error("Expected folder to exist")
	}
	if foundPath != folderPath {
		t.Errorf("Expected path %q, got %q", folderPath, foundPath)
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
