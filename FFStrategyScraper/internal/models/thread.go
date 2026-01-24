package models

import (
	"encoding/json"
	"time"
)

// Thread represents a ForexFactory forum thread with all its metadata and content
type Thread struct {
	ThreadID      string        `json:"thread_id"`
	Title         string        `json:"title"`
	URL           string        `json:"url"`
	Author        AuthorInfo    `json:"author"`
	Stats         ThreadStats   `json:"stats"`
	ExtractedInfo ExtractedInfo `json:"extracted_info"`
	LikesCount    int           `json:"likes_count"`
	Attachments   []Attachment  `json:"attachments"`
	ScrapedAt     time.Time     `json:"scraped_at"`
}

// AuthorInfo contains information about the thread author
type AuthorInfo struct {
	Username   string    `json:"username"`
	JoinDate   string    `json:"join_date"`   // Format: "2015-03-15"
	TotalPosts int       `json:"total_posts"`
}

// ThreadStats contains statistical information about the thread
type ThreadStats struct {
	TotalReplies  int       `json:"total_replies"`
	ViewCount     int       `json:"view_count"`
	FirstPostDate time.Time `json:"first_post_date"`
	LastReplyDate time.Time `json:"last_reply_date"`
}

// ExtractedInfo contains trading-related information extracted from the thread
type ExtractedInfo struct {
	Symbols             []string `json:"symbols"`
	Timeframes          []string `json:"timeframes"`
	IndicatorsMentioned []string `json:"indicators_mentioned"`
}

// Attachment represents a file attachment from the thread
type Attachment struct {
	Filename  string `json:"filename"`
	Type      string `json:"type"`       // e.g., "indicator", "document", "image"
	SizeBytes int64  `json:"size_bytes"`
}

// ToJSON serializes the Thread to a JSON byte slice
func (t *Thread) ToJSON() ([]byte, error) {
	return json.MarshalIndent(t, "", "  ")
}

// ToJSONString serializes the Thread to a formatted JSON string
func (t *Thread) ToJSONString() (string, error) {
	jsonBytes, err := t.ToJSON()
	if err != nil {
		return "", err
	}
	return string(jsonBytes), nil
}

// NewThread creates and initializes a new Thread instance
func NewThread(threadID, title, url string) *Thread {
	return &Thread{
		ThreadID:    threadID,
		Title:       title,
		URL:         url,
		ScrapedAt:   time.Now().UTC(),
		Attachments: make([]Attachment, 0),
		ExtractedInfo: ExtractedInfo{
			Symbols:             make([]string, 0),
			Timeframes:          make([]string, 0),
			IndicatorsMentioned: make([]string, 0),
		},
	}
}

// AddAttachment adds an attachment to the thread
func (t *Thread) AddAttachment(filename, fileType string, sizeBytes int64) {
	attachment := Attachment{
		Filename:  filename,
		Type:      fileType,
		SizeBytes: sizeBytes,
	}
	t.Attachments = append(t.Attachments, attachment)
}

// HasAttachments returns true if the thread has any attachments
func (t *Thread) HasAttachments() bool {
	return len(t.Attachments) > 0
}

// MeetsFilterCriteria checks if the thread meets the minimum filtering requirements
func (t *Thread) MeetsFilterCriteria(minReplies int, maxInactiveDays int) bool {
	// Check minimum replies
	if t.Stats.TotalReplies < minReplies {
		return false
	}

	// Check recent activity
	daysSinceLastReply := int(time.Since(t.Stats.LastReplyDate).Hours() / 24)
	if daysSinceLastReply > maxInactiveDays {
		return false
	}

	return true
}
