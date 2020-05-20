# spejstore-labelmaker

```sh
bundle install
bundle exec ruby main.rb
```

try it out:

GET http://localhost:4567/api/1/preview/:label.png
GET http://localhost:4567/api/1/preview/:label.pdf
POST http://localhost:4567/api/1/print/:label

where :label is a `spejstore` label.id or item.short_id
