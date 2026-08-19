# frozen_string_literal: true

require 'sequel'

module Nex
  module Db
    def self.connect!
      url = ENV.fetch('DATABASE_URL')
      db = Sequel.connect(url)
      db.extension :pg_json
      db
    end

    def self.migrate!(db)
      sql = File.read(File.expand_path('../db/migrate.sql', __dir__))
      db.run(sql)
    end
  end
end
