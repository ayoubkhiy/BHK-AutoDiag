# Backend configuration

## Local development

Run the backend from this directory with `python manage.py runserver`. The
management command uses `backend.development_settings`; its built-in key is
for local development only.

## Production

The WSGI entry point uses `backend.settings`. Configure these environment
variables before starting the application:

- `DJANGO_DEBUG=false`
- `DJANGO_SECRET_KEY` with a private, randomly generated key
- `DJANGO_ALLOWED_HOSTS` with the exact API hostnames, separated by commas
- `DJANGO_CORS_ALLOWED_ORIGINS` with the exact browser app origins, if used
- `DJANGO_API_TOKEN_MAX_AGE_SECONDS` to override the 30-day token lifetime

Production startup fails if the secret key or explicit allowed hosts are
missing. Do not use the development key or wildcard hosts in production.
Build released Flutter clients with an HTTPS `API_BASE_URL`.
