# Docket test report

## Scope and promotion criterion

This report covers the five deployable services: `auth-api`, `users-api`,
`todos-api`, `log-message-processor`, and `frontend`. A version may be promoted
only when the GitHub required check **Promotion gate** succeeds. That check
requires:

- all unit suites to pass;
- the configured coverage floor in every repository to pass;
- 100% of the critical integration/E2E scenarios to pass.

Coverage floors are 55% for `auth-api` and `log-message-processor`, 40% for
`users-api`, and 70% line coverage for `todos-api` and `frontend` (with 65%
branches for `todos-api` and 60% for `frontend`). The `unit-coverage` job
publishes all native reports in the single `docket-consolidated-coverage`
artifact.

Configure **Promotion gate** as a required status check on `main` and on the
protected staging/production promotion branches. A failed or cancelled check
must block merge and therefore blocks Argo CD promotion.

## Automated scenarios

| Level | Component/relationship | Scenarios |
| --- | --- | --- |
| Unit | auth-api | valid/invalid login, upstream failure, signed HS256 JWT claims and expiry |
| Unit | users-api | context, user lookup authorization, rejected cross-user lookup, metrics |
| Unit | todos-api | JWT enforcement, list/create/update/delete, validation, Redis event payloads |
| Unit | log-message-processor | valid/invalid Redis messages, tracing behavior and worker metrics |
| Unit | frontend | authentication/user state mutations and request metrics |
| Integration | auth-api -> users-api -> todos-api | login token is produced upstream, accepted by todos, and missing JWT is rejected |
| Integration | todos-api -> Redis -> log-message-processor | CREATE and UPDATE events are published and two successful consumptions appear in worker metrics |
| E2E critical | Docket API/board flow | login -> create task -> list it on the board -> update status to `done` |

The integration environment is reproducible with:

```bash
docker compose -f tests/docker-compose.yml up --build -d
python tests/e2e_test.py
docker compose -f tests/docker-compose.yml down -v
```

## Results

Local verification on 2026-09-23:

- critical integration/E2E flow: PASS;
- `todos-api`: 8 tests PASS, 100% lines/statements/functions, 87.5% branches;
- `auth-api`: PASS, 57.5% statements;
- `log-message-processor`: 4 tests PASS, 56% statements;
- Compose configuration and Python E2E syntax: PASS.

The CI pipeline is authoritative for the complete five-service coverage
artifact because it provisions the exact Go, Java, Node, and Python versions.

## Limitations

- The E2E scenario drives the public HTTP contracts and validates the board via
  `GET /todos`; it does not use a real browser or perform visual assertions.
- Todo storage remains process-local memory, so persistence/restart and
  concurrency are outside this iteration.
- Redis uses Pub/Sub, so delivery durability after worker downtime is not
  covered.
- Test credentials and JWT secrets are fixed, CI-only values and must never be
  reused in an environment.
- The legacy frontend and todos images use Node 8 and have known dependency
  vulnerabilities; dependency modernization is separate from this quality HU.
