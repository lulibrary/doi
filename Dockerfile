FROM ruby:2.3.0
RUN apt-get update -yqq
RUN apt-get install -yqq --no-install-recommends nodejs
WORKDIR /data
COPY Gemfile* ./
RUN bundle install
COPY . .

# Local requirement
COPY ./pure_ssl_certs/*.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]