FROM ruby:3.3-alpine

RUN apk add --no-cache build-base postgresql-dev postgresql-client tzdata

WORKDIR /app
COPY apps/api/Gemfile ./
RUN bundle install
COPY apps/api/ ./

ENV RACK_ENV=production
EXPOSE 4567
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:4567", "config.ru"]
