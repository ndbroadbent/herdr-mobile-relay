package readiness

import (
	"errors"
	"strings"
	"testing"
)

func TestVerifyReadiness(t *testing.T) {
	valid := `{"status":"ready","inventory":{"state":"ready","agents":[]},"instance":"instance","release_version":"version","revision":"revision","bundle_hash":"web","protocol":3}`
	expected := Expected{Instance: "instance", Version: "version", Revision: "revision", WebHash: "web"}
	if err := Verify(strings.NewReader(valid), expected); err != nil {
		t.Fatal(err)
	}
	for name, response := range map[string]string{
		"degraded":       strings.Replace(valid, `"state":"ready"`, `"state":"degraded"`, 1),
		"wrong instance": strings.Replace(valid, `"instance":"instance"`, `"instance":"foreign"`, 1),
		"wrong revision": strings.Replace(valid, `"revision":"revision"`, `"revision":"old"`, 1),
		"wrong bundle":   strings.Replace(valid, `"bundle_hash":"web"`, `"bundle_hash":"old"`, 1),
		"duplicate":      strings.Replace(valid, `"status":"ready"`, `"status":"unavailable","status":"ready"`, 1),
		"string spoof":   `{"diagnostic":` + `"status:ready,instance:instance,revision:revision"}`,
		"trailing":       valid + `{}`,
		"wrong type":     strings.Replace(valid, `"instance":"instance"`, `"instance":42`, 1),
	} {
		t.Run(name, func(t *testing.T) {
			if Verify(strings.NewReader(response), expected) == nil {
				t.Fatal("accepted invalid readiness")
			}
		})
	}
	if Verify(strings.NewReader(valid), Expected{}) == nil {
		t.Fatal("accepted unspecified instance")
	}
}

func TestVerifyReadinessReportsAStartingRelay(t *testing.T) {
	starting := `{"status":"unavailable","inventory":{"state":"starting"},"instance":"instance","release_version":"version","revision":"revision","bundle_hash":"web","protocol":3}`
	expected := Expected{Instance: "instance", Version: "version", Revision: "revision", WebHash: "web"}
	if err := Verify(strings.NewReader(starting), expected); !errors.Is(err, ErrStarting) {
		t.Fatalf("starting relay: %v", err)
	}
	for name, response := range map[string]string{
		"another relay":  strings.Replace(starting, `"instance":"instance"`, `"instance":"foreign"`, 1),
		"old release":    strings.Replace(starting, `"revision":"revision"`, `"revision":"old"`, 1),
		"failed":         strings.Replace(starting, `"state":"starting"`, `"state":"error"`, 1),
		"other protocol": strings.Replace(starting, `"protocol":3`, `"protocol":2`, 1),
	} {
		t.Run(name, func(t *testing.T) {
			if err := Verify(strings.NewReader(response), expected); err == nil || errors.Is(err, ErrStarting) {
				t.Fatalf("treated %s as still starting: %v", name, err)
			}
		})
	}
}
