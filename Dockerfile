FROM ruby:latest
RUN mkdir /code
WORKDIR /code
ADD Gemfile /code/
ADD . /code/
RUN bundle install

CMD bundle exec ruby main.rb
