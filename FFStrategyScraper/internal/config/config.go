package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Config represents the complete application configuration
type Config struct {
	Scraper ScraperConfig `yaml:"scraper"`
	Filters FilterConfig  `yaml:"filters"`
	Output  OutputConfig  `yaml:"output"`
	Logging LoggingConfig `yaml:"logging"`
}

// ScraperConfig contains scraper-related settings
type ScraperConfig struct {
	BaseURL          string `yaml:"base_url"`
	ForumPath        string `yaml:"forum_path"`
	MinDelaySeconds  int    `yaml:"min_delay_seconds"`
	MaxDelaySeconds  int    `yaml:"max_delay_seconds"`
	UserAgent        string `yaml:"user_agent"`
}

// FilterConfig contains filtering criteria for strategies
type FilterConfig struct {
	MinReplies       int `yaml:"min_replies"`
	MaxInactiveDays  int `yaml:"max_inactive_days"`
}

// OutputConfig contains output-related settings
type OutputConfig struct {
	StrategiesDir string `yaml:"strategies_dir"`
	DatabasePath  string `yaml:"database_path"`
}

// LoggingConfig contains logging-related settings
type LoggingConfig struct {
	Level string `yaml:"level"`
	File  string `yaml:"file"`
}

// LoadConfig reads and parses the YAML configuration file
// Returns a Config struct with parsed values or an error if loading/parsing fails
func LoadConfig(path string) (*Config, error) {
	// Check if file exists
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil, fmt.Errorf("config file not found: %s", path)
	}

	// Read the file
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("error reading config file: %w", err)
	}

	// Parse YAML
	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("error parsing config file: %w", err)
	}

	// Apply defaults and validate
	if err := config.setDefaults(); err != nil {
		return nil, fmt.Errorf("error applying defaults: %w", err)
	}

	if err := config.validate(); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	return &config, nil
}

// setDefaults applies default values for missing configuration fields
func (c *Config) setDefaults() error {
	// Scraper defaults
	if c.Scraper.BaseURL == "" {
		c.Scraper.BaseURL = "https://www.forexfactory.com"
	}
	if c.Scraper.ForumPath == "" {
		c.Scraper.ForumPath = "/forum/71-trading-systems"
	}
	if c.Scraper.MinDelaySeconds == 0 {
		c.Scraper.MinDelaySeconds = 2
	}
	if c.Scraper.MaxDelaySeconds == 0 {
		c.Scraper.MaxDelaySeconds = 5
	}
	if c.Scraper.UserAgent == "" {
		c.Scraper.UserAgent = "Mozilla/5.0 (compatible; StrategyResearchBot/1.0)"
	}

	// Filter defaults
	if c.Filters.MinReplies == 0 {
		c.Filters.MinReplies = 2000
	}
	if c.Filters.MaxInactiveDays == 0 {
		c.Filters.MaxInactiveDays = 90
	}

	// Output defaults
	if c.Output.StrategiesDir == "" {
		c.Output.StrategiesDir = "./strategies"
	}
	if c.Output.DatabasePath == "" {
		c.Output.DatabasePath = "./scraper.db"
	}

	// Logging defaults
	if c.Logging.Level == "" {
		c.Logging.Level = "info"
	}
	if c.Logging.File == "" {
		c.Logging.File = "./scraper.log"
	}

	return nil
}

// validate checks that the configuration values are valid
func (c *Config) validate() error {
	// Validate scraper config
	if c.Scraper.BaseURL == "" {
		return fmt.Errorf("scraper.base_url cannot be empty")
	}
	if c.Scraper.ForumPath == "" {
		return fmt.Errorf("scraper.forum_path cannot be empty")
	}
	if c.Scraper.MinDelaySeconds < 0 {
		return fmt.Errorf("scraper.min_delay_seconds must be non-negative")
	}
	if c.Scraper.MaxDelaySeconds < c.Scraper.MinDelaySeconds {
		return fmt.Errorf("scraper.max_delay_seconds must be >= min_delay_seconds")
	}

	// Validate filter config
	if c.Filters.MinReplies < 0 {
		return fmt.Errorf("filters.min_replies must be non-negative")
	}
	if c.Filters.MaxInactiveDays < 0 {
		return fmt.Errorf("filters.max_inactive_days must be non-negative")
	}

	// Validate output config
	if c.Output.StrategiesDir == "" {
		return fmt.Errorf("output.strategies_dir cannot be empty")
	}
	if c.Output.DatabasePath == "" {
		return fmt.Errorf("output.database_path cannot be empty")
	}

	// Validate logging config
	validLogLevels := map[string]bool{
		"debug": true,
		"info":  true,
		"warn":  true,
		"error": true,
	}
	if !validLogLevels[c.Logging.Level] {
		return fmt.Errorf("logging.level must be one of: debug, info, warn, error")
	}

	return nil
}
