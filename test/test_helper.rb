$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "request_deadline"
require 'pry'
require "minitest/autorun"

class Product < ActiveRecord::Base
end

CONN_CONFIG = {
  adapter: "mysql2",
  database: "request_deadline_test",
  username: "root",
  host: "localhost",
}

ActiveRecord::Base.establish_connection(CONN_CONFIG)

ActiveRecord::Base.connection.create_table(Product.table_name, force: true) do |t|
  t.string(:name)
  t.timestamps
end

class SQLCounter
  class << self
    attr_accessor :ignored_sql, :log, :log_all
    def clear_log; self.log = []; self.log_all = []; end
  end

  clear_log

  def call(name, start, finish, message_id, values)
    return if values[:cached]

    sql = values[:sql]
    self.class.log_all << sql
    self.class.log << sql unless ["SCHEMA", "TRANSACTION"].include? values[:name]
  end
end

class Minitest::Test
  def capture_sql
    SQLCounter.clear_log
    yield
    SQLCounter.log.dup
  end

  def teardown
    RequestStore.clear!
    super
  end

  def setup
    Minitest.backtrace_filter = Minitest::BacktraceFilter.new
    super
  end
end

ActiveSupport::Notifications.subscribe("sql.active_record", SQLCounter.new)

RequestDeadline.insert_active_record
# Rails.application.initialize!