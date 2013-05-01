require "wd_sinatra_sequel/version"
require "sequel"

# Set the default value, feel free to overwrite
Sequel.default_timezone = :utc


module WdSinatraSequel

  # Path to the rake task file so it can be loaded as such:
  #     load WdSinatraSequel.task_path
  # (Note that the app loaded should have been started using something like:
  #   WDSinatra::AppLoader.console(RAKE_APP_ROOT)
  # before loading this rake task.)
  def self.task_path
    File.join(File.expand_path(File.dirname(__FILE__), ".."), "wd_sinatra_sequel", "db.rake")
  end

  ##### DB Connection ########
  module DBConnector
    DB_CONFIG = YAML.load_file(File.join(WDSinatra::AppLoader.root_path, "config", "database.yml"))

    module_function

    def set_db_connection(env=RACK_ENV)
      # Set the Sequel logger
      loggers = []
      if Object.const_defined?(:LOGGER)
        loggers << LOGGER
      else
        loggers << Logger.new($stdout)
      end

      # Establish the DB connection
      db_file = File.join(WDSinatra::AppLoader.root_path, "config", "database.yml")
      if File.exist?(db_file)
        hash_settings = YAML.load_file(db_file)
        if hash_settings && hash_settings[env]
          @db_configurations = hash_settings
          @db_configuration = @db_configurations[env]
          # add loggers
          @db_configuration['loggers'] ||= []
          @db_configuration['loggers'].concat(loggers)
          # overwrite DB name by using an ENV variable
          if ENV['FORCED_DB_NAME']
            print "Database name overwritten to be #{ENV['FORCED_DB_NAME']}\n"
            @db_configurations[env]['database'] = @db_configuration['database'] = ENV['FORCED_DB_NAME']
          end
          connect_to_db unless ENV['DONT_CONNECT']
        else
          raise "#{db_file} doesn't have an entry for the #{env} environment"
        end
      else
        raise "#{db_file} file missing, can't connect to the DB"
      end
    end

    def db_configuration(env=RACK_ENV)
      old_connect_status = ENV['DONT_CONNECT']
      set_db_connection(env)
      ENV['DONT_CONNECT'] = old_connect_status
      @db_configuration
    end

    def db_configurations
      db_configuration unless @db_configurations
      @db_configurations
    end

    def connect_to_db
      if @db_configuration
        if @db_configuration.has_key?('uri')
          uri = @db_configuration['uri']
          config_without_uri = @db_configuration.clone
          config_without_uri.delete('uri')
          connection = Sequel.connect(uri, config_without_uri)
        else
          connection = Sequel.connect(@db_configuration)
        end
      else
        raise "Can't connect without the config previously set"
      end
    end
  end
end
