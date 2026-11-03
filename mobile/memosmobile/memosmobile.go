// Package memosmobile embeds the open-source Memos server so it can run
// entirely on-device. It is copied into the upstream Memos source tree at
// build time (so it can import Memos' internal packages) and compiled into
// an iOS framework with gomobile.
package memosmobile

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os"
	"sync"
	"time"

	"github.com/usememos/memos/internal/profile"
	"github.com/usememos/memos/internal/version"
	"github.com/usememos/memos/server"
	"github.com/usememos/memos/store"
	"github.com/usememos/memos/store/db"
)

var (
	mu      sync.Mutex
	current *server.Server
	curPort int
)

// Start launches Memos on 127.0.0.1:port using SQLite under dataDir.
// It returns an empty string on success, or an error message.
func Start(dataDir string, port int) string {
	mu.Lock()
	defer mu.Unlock()
	if current != nil {
		if curPort == port && alive(port) {
			return ""
		}
		stopLocked()
	}
	if err := start(dataDir, port); err != nil {
		return err.Error()
	}
	return ""
}

// Stop shuts the server down.
func Stop() {
	mu.Lock()
	defer mu.Unlock()
	stopLocked()
}

// IsAlive reports whether the server accepts connections on its port.
func IsAlive() bool {
	mu.Lock()
	defer mu.Unlock()
	return current != nil && alive(curPort)
}

// PortAvailable reports whether 127.0.0.1:port can be bound.
func PortAvailable(port int) bool {
	l, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return false
	}
	_ = l.Close()
	return true
}

// Version returns the embedded Memos version.
func Version() string {
	return version.GetCurrentVersion()
}

func alive(port int) bool {
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 500*time.Millisecond)
	if err != nil {
		return false
	}
	_ = c.Close()
	return true
}

func stopLocked() {
	if current == nil {
		return
	}
	current.Shutdown(context.Background())
	current = nil
	curPort = 0
}

func start(dataDir string, port int) error {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn})))

	p := &profile.Profile{
		Addr:           "127.0.0.1",
		Port:           port,
		Data:           dataDir,
		Driver:         "sqlite",
		RateLimit:      false,
		TrustedProxies: []string{"none"},
		Version:        version.GetCurrentVersion(),
		Commit:         version.Commit,
	}
	if err := p.Validate(); err != nil {
		return fmt.Errorf("invalid profile: %w", err)
	}

	ctx := context.Background()
	driver, err := db.NewDBDriver(p)
	if err != nil {
		return fmt.Errorf("open database: %w", err)
	}
	st := store.New(driver, p)
	ok := false
	defer func() {
		if !ok {
			_ = st.Close()
		}
	}()
	if err := st.Migrate(ctx); err != nil {
		return fmt.Errorf("migrate database: %w", err)
	}
	if err := st.LoadDeploymentConfiguration(ctx); err != nil {
		return fmt.Errorf("load configuration: %w", err)
	}
	s, err := server.NewServer(ctx, p, st)
	if err != nil {
		return fmt.Errorf("create server: %w", err)
	}
	if err := s.Start(); err != nil {
		return fmt.Errorf("start server: %w", err)
	}
	ok = true
	current = s
	curPort = port
	return nil
}
