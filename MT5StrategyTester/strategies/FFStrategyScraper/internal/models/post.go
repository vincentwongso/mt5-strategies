package models

import (
	"encoding/json"
	"time"
)

// Post represents a single post within a ForexFactory forum thread
type Post struct {
	PostID         string       `json:"post_id"`
	PostNumber     int          `json:"post_number"`
	ThreadID       string       `json:"thread_id"`
	AuthorUsername string       `json:"author_username"`
	Content        string       `json:"content"`          // Cleaned text content
	PostedAt       time.Time    `json:"posted_at"`
	Attachments    []Attachment `json:"attachments"`
	IsOriginalPost bool         `json:"is_original_post"` // True if this is post #1
}

// ToJSON serializes the Post to a JSON byte slice
func (p *Post) ToJSON() ([]byte, error) {
	return json.MarshalIndent(p, "", "  ")
}

// ToJSONString serializes the Post to a formatted JSON string
func (p *Post) ToJSONString() (string, error) {
	jsonBytes, err := p.ToJSON()
	if err != nil {
		return "", err
	}
	return string(jsonBytes), nil
}

// NewPost creates and initializes a new Post instance
func NewPost(postID, threadID, authorUsername string, postNumber int) *Post {
	return &Post{
		PostID:         postID,
		PostNumber:     postNumber,
		ThreadID:       threadID,
		AuthorUsername: authorUsername,
		Attachments:    make([]Attachment, 0),
		IsOriginalPost: postNumber == 1,
	}
}

// AddAttachment adds an attachment to the post
func (p *Post) AddAttachment(filename, fileType string, sizeBytes int64) {
	attachment := Attachment{
		Filename:  filename,
		Type:      fileType,
		SizeBytes: sizeBytes,
	}
	p.Attachments = append(p.Attachments, attachment)
}

// HasAttachments returns true if the post has any attachments
func (p *Post) HasAttachments() bool {
	return len(p.Attachments) > 0
}

// IsAuthorPost checks if the post is authored by the thread creator
func (p *Post) IsAuthorPost(threadAuthor string) bool {
	return p.AuthorUsername == threadAuthor
}

// SetContent sets the cleaned content for the post
func (p *Post) SetContent(content string) {
	p.Content = content
}

// PostCollection represents a collection of posts for batch operations
type PostCollection struct {
	Posts []Post `json:"posts"`
}

// NewPostCollection creates a new PostCollection
func NewPostCollection() *PostCollection {
	return &PostCollection{
		Posts: make([]Post, 0),
	}
}

// Add adds a post to the collection
func (pc *PostCollection) Add(post Post) {
	pc.Posts = append(pc.Posts, post)
}

// FilterByAuthor returns all posts by a specific author
func (pc *PostCollection) FilterByAuthor(authorUsername string) []Post {
	filtered := make([]Post, 0)
	for _, post := range pc.Posts {
		if post.AuthorUsername == authorUsername {
			filtered = append(filtered, post)
		}
	}
	return filtered
}

// GetOriginalPost returns the original post (post #1) if it exists
func (pc *PostCollection) GetOriginalPost() *Post {
	for i := range pc.Posts {
		if pc.Posts[i].IsOriginalPost {
			return &pc.Posts[i]
		}
	}
	return nil
}

// ToJSON serializes the PostCollection to a JSON byte slice
func (pc *PostCollection) ToJSON() ([]byte, error) {
	return json.MarshalIndent(pc, "", "  ")
}
