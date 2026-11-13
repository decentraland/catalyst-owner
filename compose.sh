# Sourced by the scripts that run Compose. Sets COMPOSE_CMD to the Compose v2
# plugin ("docker compose") when available, else the legacy docker-compose
# binary, else leaves it empty.
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  COMPOSE_CMD=""
fi
export COMPOSE_CMD
