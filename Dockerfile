FROM python:3.10-slim AS base

ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

RUN pip install --no-cache-dir --upgrade pip


FROM base AS builder

WORKDIR /tmp

ENV POETRY_NO_INTERACTION=1
ARG ENVIRONMENT

COPY ./pyproject.toml ./poetry.lock* /tmp/

RUN pip install poetry==1.2.0
RUN poetry check
RUN poetry export -f requirements.txt --output requirements.txt --without-hashes --with $ENVIRONMENT


FROM base AS runtime

WORKDIR /code

COPY ./app /code/app
COPY ./tests /code/tests
COPY --from=builder /tmp/requirements.txt /code/requirements.txt

RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

CMD exec uvicorn app.main:app --reload --workers 1 --host 0.0.0.0 --port $PORT

