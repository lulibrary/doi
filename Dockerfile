FROM ruby:2.5
RUN apt-get update -yqq
RUN apt-get install -yqq --no-install-recommends nodejs
COPY Gemfile* /data/
WORKDIR /data
RUN bundle install
COPY . /data/
EXPOSE 3000