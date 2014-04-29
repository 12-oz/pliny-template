require "uri"
require "sequel"
require "sequel/extensions/migration"

require_relative "../../vendor/pliny/lib/pliny/utils"

namespace :db do
  desc "Run database migrations"
  task :migrate do
    next if Dir["./db/migrate/*.rb"].empty?
    database_urls.each do |database_url|
      db = Sequel.connect(database_url)
      Sequel::Migrator.apply(db, "./db/migrate")
      puts "Migrated `#{name_from_uri(database_url)}`"
    end
  end

  desc "Rollback the database"
  task :rollback do
    next if Dir["./db/migrate/*.rb"].empty?
    database_urls.each do |database_url|
      db = Sequel.connect(database_url)
      Sequel::Migrator.apply(db, "./db/migrate", -1)
      puts "Rolled back `#{name_from_uri(database_url)}`"
    end
  end

  desc "Nuke the database (drop all tables)"
  task :nuke do
    database_urls.each do |database_url|
      db = Sequel.connect(database_url)
      db.tables.each do |table|
        db.run(%{DROP TABLE "#{table}"})
      end
      puts "Nuked `#{name_from_uri(database_url)}`"
    end
  end

  desc "Reset the database"
  task :reset, [:env] => [:nuke, :migrate]

  desc "Create the database"
  task :create do
    db = Sequel.connect("postgres://localhost/postgres")
    database_urls.each do |database_url|
      exists = false
      name = name_from_uri(database_url)
      begin
        db.run(%{CREATE DATABASE "#{name}"})
      rescue Sequel::DatabaseError
        raise unless $!.message =~ /already exists/
        exists = true
      end
      puts "Created `#{name}`" if !exists
    end
  end

  desc "Drop the database"
  task :drop do
    db = Sequel.connect("postgres://localhost/postgres")
    database_urls.each do |database_url|
      name = name_from_uri(database_url)
      db.run(%{DROP DATABASE IF EXISTS "#{name}"})
      puts "Dropped `#{name}`"
    end
  end

  namespace :schema do
    desc "Load the database schema"
    task :load do
      schema = File.read("./db/schema.sql")
      database_urls.each do |database_url|
        db = Sequel.connect(database_url)
        db.run(schema)
        puts "Loaded `#{name_from_uri(database_url)}`"
      end
    end

    desc "Dump the database schema"
    task :dump do
      database_url = database_urls.first
      `pg_dump -i -s -x -O -f ./db/schema.sql #{database_url}`
      puts "Dumped `#{name_from_uri(database_url)}` to db/schema.sql"
    end

    desc "Merges migrations into schema and removes them"
    task :merge => ["db:setup", "db:schema:load", "db:migrate", "db:schema:dump"] do
      FileUtils.rm Dir["./db/migrate/*.rb"]
      puts "Removed migrations"
    end
  end

  desc "Setup the database"
  task :setup, [:env] => [:drop, :create]

  private

  def database_urls
    if ENV["DATABASE_URL"]
      [ENV["DATABASE_URL"]]
    else
      %w(.env .env.test).map { |env_file|
        env_path = "./#{env_file}"
        if File.exists?(env_path)
          Pliny::Utils.parse_env(env_path)["DATABASE_URL"]
        else
          nil
        end
      }.compact
    end
  end

  def name_from_uri(uri)
    URI.parse(uri).path[1..-1]
  end
end
