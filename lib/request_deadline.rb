require "request_deadline/version"

require 'active_record'
require 'rails'
require 'request_store'

module ActiveRecord
  class DeadlineExceeded < StatementTimeout
    def initialize(sql)
      super("Query execution was aborted, request deadline exceeded", sql: sql)
    end
  end
end

module RequestDeadline
  class << self
    attr_accessor :deadline_seconds

    def skip_deadline
      Thread.current[:skip_request_deadline] = true
      yield
    ensure
      Thread.current[:skip_request_deadline] = false
    end
  end

  self.deadline_seconds = 5 # default

  module ActiveRecordExtension
    ROOM = 0.9

    def execute(sql, name = nil)
      verify_deadline_configuration_once

      if has_deadline? && query_supports_deadline?(sql)
        if request_time_left <= 0
          raise ActiveRecord::DeadlineExceeded.new(sql)
        end
      end
      super
    end

    private

    def query_supports_deadline?(sql)
      sql =~ /\ASELECT/
    end

    def verify_deadline_configuration_once
      return if defined?(@deadline_configuration_verified)
      if read_timeout && read_timeout < RequestDeadline.deadline_seconds
        Rails.logger.warn("[RequestDeadline] MySQL client read_timeout is set to be less than RequestDeadline.deadline_seconds. This is likely a case of misconfigured timeout and a deadline")
      end
      @deadline_configuration_verified = true
    end

    def request_time_left
      deadline = RequestStore.store[:deadline]
      unless deadline
        raise "Unexpected invocation of #request_time_left: context is outside of web request"
      end
      deadline - Concurrent.monotonic_time
    end

    def has_deadline?
      !Thread.current[:skip_request_deadline] && RequestStore.store[:deadline]
    end

    def read_timeout
      raw_connection.read_timeout
    end
  end

  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      RequestStore.store[:deadline] = now + RequestDeadline.deadline_seconds
      @app.call(env)
    end

    private

    def now
      Concurrent.monotonic_time
    end
  end

  module RelationExtension
    def optimizer_hints_values
      values = super
      if has_deadline? && !values.find { |v| v =~ /MAX_EXECUTION_TIME/ }
        left = RequestStore.store[:deadline] - Concurrent.monotonic_time
        values = values + ["MAX_EXECUTION_TIME(#{(left * 1000).round})"]
      end
      values
    end

    private

    def has_deadline?
      !Thread.current[:skip_request_deadline] && RequestStore.store[:deadline]
    end
  end

  def self.insert_active_record
    ActiveRecord::ConnectionAdapters::Mysql2Adapter.prepend(RequestDeadline::ActiveRecordExtension)

    ActiveRecord::Relation.prepend(RelationExtension)
  end

  class Railtie < Rails::Railtie
    initializer 'request_deadline' do
      Rails.application.config.middleware.use(RequestDeadline::Middleware)

      ActiveSupport.on_load :active_record do
        RequestDeadline.insert_active_record
      end
    end
  end
end
