## Purpose

Controls request throughput per client to protect system availability.

## Requirements

### Requirement: fixed-window enforcement

The system SHALL reject requests exceeding the configured limit within a fixed time window.

#### Scenario: over limit

GIVEN a client with a limit of 100 requests per minute
WHEN the client sends request 101 within the same minute
THEN the system responds with 429 and a Retry-After header

#### Scenario: window reset

GIVEN a client that hit the limit in the previous window
WHEN a new window starts
THEN the client can send requests again

### Requirement: burst detection

The system SHALL flag clients whose request rate exceeds 3x the average over a 10-second sliding window.

#### Boundary: true positives

- 350 requests in 10s against a 100 req/min baseline → flagged
- 500 requests in 10s from a single IP → flagged

#### Boundary: true negatives

- 110 requests in 10s during a known traffic spike → not flagged
- Gradual ramp from 80 to 150 over 60s → not flagged

#### Known tradeoff

Bursty but legitimate traffic (e.g., webhook retries) may trigger false positives. Accepted because missing actual abuse is costlier than a transient false flag.
