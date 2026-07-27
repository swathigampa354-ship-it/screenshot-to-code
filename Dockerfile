FROM node:20-slim AS frontend-build
WORKDIR /frontend
RUN corepack enable
COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY frontend/ ./
RUN pnpm build

FROM python:3.12-slim
RUN apt-get update && apt-get install -y curl gettext-base nginx supervisor && rm -rf /var/lib/apt/lists/*
RUN pip install poetry

WORKDIR /app/backend
COPY backend/pyproject.toml backend/poetry.lock ./
RUN poetry config virtualenvs.create false && poetry install --no-root --no-interaction
COPY backend/ ./

COPY --from=frontend-build /frontend/dist /app/frontend-dist

RUN mkdir -p /etc/nginx/templates

RUN echo 'server { \
  listen ${PORT}; \
  location / { \
    root /app/frontend-dist; \
    try_files $uri $uri/ /index.html; \
  } \
  location /generate-code { \
    proxy_pass http://127.0.0.1:7861; \
    proxy_http_version 1.1; \
    proxy_set_header Upgrade $http_upgrade; \
    proxy_set_header Connection "upgrade"; \
  } \
  location /api/ { \
    proxy_pass http://127.0.0.1:7861; \
  } \
}' > /etc/nginx/templates/default.conf.template

RUN echo '[supervisord]\n\
nodaemon=true\n\
[program:backend]\n\
command=poetry run uvicorn main:app --host 0.0.0.0 --port 7861\n\
directory=/app/backend\n\
[program:nginx]\n\
command=/bin/sh -c "envsubst \x27$PORT\x27 < /etc/nginx/templates/default.conf.template > /etc/nginx/sites-enabled/default && nginx -g \x27daemon off;\x27"' > /etc/supervisor/conf.d/supervisord.conf

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
