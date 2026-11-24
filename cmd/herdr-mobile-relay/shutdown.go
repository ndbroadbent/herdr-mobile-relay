package main

import (
	"context"
	"time"
)

// shutdownDeadline bounds how long the relay keeps running after SIGINT or
// SIGTERM. Shutdown waits for background work, and some of it (reading a long
// agent transcript to find its title) does not observe cancellation, so a
// relay asked to stop during its first inventory could otherwise keep running,
// busy and orphaned, after its service was stopped or rolled back.
const shutdownDeadline = 20 * time.Second

// enforceShutdown returns when served is closed. Once a signal cancels ctx, it
// calls stop, so a second signal ends the process at once, and calls expired if
// the relay has still not finished after deadline.
func enforceShutdown(ctx context.Context, served <-chan struct{}, stop func(), deadline time.Duration, expired func()) {
	select {
	case <-served:
		return
	case <-ctx.Done():
	}
	stop()
	timer := time.NewTimer(deadline)
	defer timer.Stop()
	select {
	case <-served:
	case <-timer.C:
		expired()
	}
}
