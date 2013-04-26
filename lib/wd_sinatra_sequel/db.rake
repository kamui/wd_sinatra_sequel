require 'wd_sinatra_sequel'
require 'pry'

db_namespace = namespace :db do

  task :load_config => :setup_app do
    require 'sequel'
    @config = WdSinatraSequel::DBConnector.db_configuration
    if @config['uri']
      opts = Sequel.connect(@config['uri'], @config).opts
      %w{adapter host port user password database}.each do |k|
        @config[k] = opts[k.to_sym]
      end
    end
    @migrations_path = File.join(WDSinatra::AppLoader.root_path, 'db/migrate')
  end

  desc 'Create the database from config/database.yml for the current RACK_ENV (use db:create:all to create all dbs in the config)'
  task :create do
    old_connect_env = ENV['DONT_CONNECT'] ? 'true' : nil
    ENV['DONT_CONNECT'] = 'true'
    Rake::Task["db:load_config"].invoke
    create_database(@config)
    ENV['DONT_CONNECT'] = old_connect_env
  end

  def create_database(config)
    begin
      if config['adapter'] =~ /sqlite/
        if File.exist?(config['database'])
          $stderr.puts "#{config['database']} already exists"
        else
          begin
            # Create the SQLite database
            Sequel.connect(config)
          rescue Exception => e
            $stderr.puts e, *(e.backtrace)
            $stderr.puts "Couldn't create database for #{config.inspect}"
          end
        end
        return # Skip the else clause of begin/rescue
      else
        Sequel.connect(config, test: true)

      end
    rescue
      case config['adapter']
      when /mysql/
        if config['adapter'] =~ /jdbc/
          error_class = Sequel::DatabaseConnectionError
        else
          error_class = config['adapter'] =~ /mysql2/ ? Mysql2::Error : Mysql::Error
        end
        access_denied_error = 1045

        charset   = ENV['CHARSET']   || 'utf8'
        collation = ENV['COLLATION'] || 'utf8_unicode_ci'

        begin
          arguments = mysql_cli_args(config)
          arguments << '-e'
          arguments << "CREATE DATABASE #{config['database']} DEFAULT CHARACTER SET #{charset} DEFAULT COLLATE #{collation}"

          system('mysql',*arguments)
          Sequel.connect(config)
        rescue error_class => sqlerr
          if sqlerr.errno == access_denied_error
            print "#{sqlerr.error}. \nPlease provide the root password for your mysql installation\n>"
            root_password = $stdin.gets.strip
            grant_statement = "GRANT ALL PRIVILEGES ON #{config['database']}.* " \
              "TO '#{config['user']}'@'localhost' " \
              "IDENTIFIED BY '#{config['password']}' WITH GRANT OPTION;"
            system('mysql', '-u', 'root', '--password', root_password, '-h', config['host'], '-e', grant_statement)
            system('mysql',*arguments)
            Sequel.connect(config)
          else
            $stderr.puts sqlerr.error
            $stderr.puts "Couldn't create database for #{config.inspect}, charset: #{config['charset'] || charset}, collation: #{config['collation'] || collation}"
            $stderr.puts "(if you set the charset manually, make sure you have a matching collation)" if config['charset']
          end
        end
      when /postgres/
        encoding = config['encoding'] || ENV['CHARSET'] || 'utf8'
        begin
          system("createdb", "-E", encoding, "-h", config['host'], "-U", config['user'], config['database'])
          Sequel.connect(config)
        rescue Exception => e
          $stderr.puts e, *(e.backtrace)
          $stderr.puts "Couldn't create database for #{config.inspect}"
        end
      end
    else
      # Bug with 1.9.2 Calling return within begin still executes else
      $stderr.puts "#{config['database']} already exists" unless config['adapter'] =~ /sqlite/
    end
  end

  desc 'Drops the database for the current RACK_ENV (use db:drop:all to drop all databases)'
  task :drop do
    Rake::Task["db:load_config"].invoke
    begin
      drop_database(@config)
    rescue Exception => e
      $stderr.puts "Couldn't drop #{@config['database']} : #{e.inspect}"
    end
  end

  def local_database?(config, &block)
    if config['host'].in?(['127.0.0.1', 'localhost']) || config['host'].blank?
      yield
    else
      $stderr.puts "This task only modifies local databases. #{config['database']} is on a remote host."
    end
  end

  desc "Migrate the database"
  task :migrate do
    Rake::Task[:environment].invoke
    Rake::Task["db:load_config"].invoke
    Sequel.extension :migration
    db = Sequel.connect(@config)
    Sequel::Migrator.run(db, @migrations_path)
    db_namespace["schema:dump"].invoke
  end

  namespace :migrate do
    # desc  'Rollbacks the database one migration and re migrate up (options: VERSION=x).'
    task :redo => [:environment, :load_config] do
      if ENV['VERSION']
        db_namespace['migrate:to'].invoke
      else
        db_namespace['rollback'].invoke
      end
      db_namespace['migrate'].invoke
    end

    # desc 'Resets your database using your migrations for the current environment'
    task :reset => ['db:drop', 'db:create', 'db:migrate']

    # desc 'Runs the "to" for a given migration VERSION.'
    task :to, [:version] => [:environment, :load_config] do |t, args|
      version = (args[:version] || ENV['VERSION']).to_s.strip
      raise 'VERSION is required' unless version
      Sequel.extension :migration
      db = Sequel.connect(@config)
      Sequel::Migrator.run(db, @migrations_path, :target => version)
      db_namespace['schema:dump'].invoke
    end
  end

  desc 'Rolls the schema back (erase all data).'
  task :rollback => [:environment, :load_config] do
    Sequel.extension :migration
    db = Sequel.connect(@config)
    Sequel::Migrator.run(db, @migrations_path, :target => 0)
    db_namespace['schema:dump'].invoke
  end

  # desc 'Drops and recreates the database from db/schema.rb for the current environment and loads the seeds.'
  task :reset => [ 'db:drop', 'db:setup' ]

  # desc "Raises an error if there are pending migrations"
  task :abort_if_pending_migrations => [:environment, :setup_app, :load_config] do
    if defined? Sequel
      Sequel.extension :migration
      db = Sequel.connect(@config)

      if Sequel::Migrator.is_current?(db, @migrations_path)
        puts "You have pending migrations."
        abort %{Run "rake db:migrate" to update your database then try again.}
      end
    end
  end

  desc 'Create the database, and initialize with the seed data (use db:reset to also drop the db first)'
  task :setup => [ 'db:create', 'db:seed' ]

  desc 'Load the seed data from db/seeds.rb'
  task :seed do
    old_no_redis = ENV['NO_REDIS'] ? 'true' : nil
    ENV['NO_REDIS'] = 'true'
    Rake::Task[:environment].invoke
    Rake::Task["db:abort_if_pending_migrations"].invoke
    seed = File.join(WDSinatra::AppLoader.root_path, "db", "seed.rb")
    if File.exist?(seed)
      puts "seeding #{seed}"
      load seed
    else
      puts "Seed file: #{seed} is missing"
    end
    ENV['NO_REDIS'] = old_no_redis
  end

  namespace :schema do
    desc 'Create a db/schema.rb file that can be portably used against any DB supported by AR'
    task :dump => :load_config do
      Sequel.extension :schema_dumper
      db = Sequel.connect(@config)
      filename = ENV['SCHEMA'] || "#{WDSinatra::AppLoader.root_path}/db/schema.rb"
      File.open(filename, "w:utf-8") do |file|
        file.write(db.dump_schema_migration)
      end
      db_namespace['schema:dump'].reenable
    end

    desc 'Load a schema.rb file into the database'
    task :load => [:environment, :load_config] do
      Sequel.extension :schema_dumper
      Sequel.extension :migration
      db = Sequel.connect(@config)
      file = ENV['SCHEMA'] || "#{WDSinatra::AppLoader.root_path}/db/schema.rb"
      if File.exists?(file)
        load(file)
      else
        abort %{#{file} doesn't exist yet. Run "rake db:migrate" to create it then try again. If you do not intend to use a database, you should instead alter #{WDSinatra::AppLoader.root_path}/config/application.rb to limit the frameworks that will be loaded}
      end
    end
  end

  namespace :test do
    # desc "Empty the test database"
    task :purge => :setup_app do
      ENV['RACK_ENV'] = 'test'
      Rake::Task["db:load_config"].invoke
      drop_database(@config)
      create_database(@config)
    end
  end
end

def  mysql_cli_args(config)
    arguments = ["--user=#{config['user']}"]
    arguments << "--password=#{config['password']}" if config['password']

    unless %w[127.0.0.1 localhost].include?(config['host'])
      arguments << "--host=#{config['host']}"
    end
    arguments
end

def drop_database(config)
  case config['adapter']
  when /mysql/
    arguments = mysql_cli_args(config)
    arguments << '-e'
    arguments << "DROP DATABASE IF EXISTS #{config['database']}"

    system('mysql',*arguments)
  when /sqlite/
    require 'pathname'
    path = Pathname.new(config['database'])
    file = path.absolute? ? path.to_s : File.join(WDSinatra::AppLoader.root_path, path)

    FileUtils.rm(file) if File.exist?(file)
  when /postgres/
    system("dropdb", "-h", config['host'], "-U", config['user'], config['database'])
  else
    raise "Task not supported by '#{config['adapter']}'"
  end
end
