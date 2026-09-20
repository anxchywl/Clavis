FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:0.11.21 /uv /uvx /bin/

# dependencies before source, so a code change does not rebuild this layer
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY backend/app ./app
RUN uv sync --frozen --no-dev

# the database lives on a volume mounted here; a new volume takes this owner
RUN addgroup --system clavis && adduser --system --ingroup clavis clavis \
    && mkdir /data && chown clavis:clavis /data
USER clavis

EXPOSE 8000

# --factory: the app is built at startup, so importing the module never
# requires a configured environment
CMD [".venv/bin/uvicorn", "app.main:create_app", "--factory", \
     "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
