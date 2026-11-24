package main

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

func TestEnforceShutdown(t *testing.T) {
	run := func(signal, finish bool) (stopped, expired bool) {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		served := make(chan struct{})
		var stops, expiries atomic.Int32
		done := make(chan struct{})
		go func() {
			enforceShutdown(ctx, served, func() { stops.Add(1) }, 50*time.Millisecond, func() { expiries.Add(1) })
			close(done)
		}()
		if signal {
			cancel()
		}
		if finish {
			time.Sleep(10 * time.Millisecond)
			close(served)
		}
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			t.Fatal("enforceShutdown did not return")
		}
		return stops.Load() == 1, expiries.Load() == 1
	}
	if stopped, expired := run(false, true); stopped || expired {
		t.Fatalf("a relay that finished without a signal: stopped=%v expired=%v", stopped, expired)
	}
	if stopped, expired := run(true, true); !stopped || expired {
		t.Fatalf("a relay that shut down in time: stopped=%v expired=%v", stopped, expired)
	}
	if stopped, expired := run(true, false); !stopped || !expired {
		t.Fatalf("a relay stuck shutting down: stopped=%v expired=%v", stopped, expired)
	}
}
