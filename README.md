# WdSinatraSequel

A Ruby gem to avoid reinventing the wheel every time you want to use
[Sequel](https://github.com/jeremyevans/sequel) in a
[WeaselDiesel](https://github.com/mattetti/Weasel-Diesel) app backed by
Sinatra ([wd_sinatra](https://github.com/mattetti/wd-sinatra)).

Use this gem to easily get connected to one or multiple databases and to
enjoy some of the common Sequel Rake tasks similar to those in Rails.


## Installation

Add this line to your application's Gemfile:

    gem 'wd_sinatra_sequel'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install wd_sinatra_sequel


Don't forget to set a gem dependency for the DB adapter you need.
For instance:

    mysql2


## Usage

Add an Sequel `database.yml` file in your config folder and then require this
gem in your `app.rb` file and connect to the DB:

    require 'wd_sinatra_sequel'
    DB = WdSinatraSequel::DBConnector.set_db_connection


The DB settings can be accessed via:

    DBConnector::DB_CONFIG[RACK_ENV]

## Rake tasks

A Rake task file is also provided so you can load Sequel specific
tasks. To do that, create a new rake file in your `lib/tasks` folder, load
`WDSinatra` and the rake task file:

```
$ echo "require 'wd_sinatra_sequel'
load WdSinatraSequel.task_path" > lib/tasks/db.rake
```

The tasks are very basic, feel free to send patches and improvements.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
