# RequestDeadline

RequestDeadline brings the concept of [RPC deadlines](https://grpc.io/blog/deadlines/) to Rails and ActiveRecord (only MySQL adapter is supported).

Imagine a web endpoint that executes heavy queries on the DB. If the web request timeout is configured to be 30s and DB query timeout is 10s, there's very little point point in starting to execute new heavy query when the request is beyond 21s. At that point it's likely that the DB will return the result when the request will already be inactive by a time out. To save the capacity, it's preferred to abort the request early.

The gem implements 2 features that are somewhat coupled to each other:

1) Propagating MySQL's `MAX_EXECUTION_TIME` optimizer hint with the current deadline
2) Early aborting query execution if the request is beyond the deadline

## Configuration

It's important to understand how all settings play together to have correctly configured deadlines.

```ruby
# default value, tweak in config/initializers/request_deadline.rb
RequestDeadline.deadline_seconds = 5
```

It's highly recommended to have `RequestDeadline.deadline_seconds` to be less than `read_timeout` of MySQL client (mysql2) and less than web server request timeout. If it's not, you're likely relying on very ineffective timeout strategy.

## Usage

On application boot, the gem embeds a middleware to track deadline, and hooks into ActiveRecord to control query execution. You don't need to change any code to make the default strategy work.

Use `RequestDeadline.skip_deadline` with a block to disable deadlines for code that you want to exclude from deadline control:

```ruby
class MoneysController < ApplicationController
  def index
    RequestDeadline.skip_deadline do
      MySlowService.call
    end
  end
end
```

To rescue and ignore a deadline:

```ruby
begin
  # potentially slow query
  Order.archived.for_user(User.find(1)).page(2)
rescue ::ActiveRecord::StatementTimeout => e
  logger.warn "Timeout: #{e}"
end
```

### Implementation choices

### ActiveRecord::Base#optimizer_hints

Since Rails 6.0, ActiveRecord comes with [official support for optimizer_hints](https://github.com/rails/rails/commit/97347d8c409f14b682dd9ec52ded3c869d0ba479).

It should be possible to add `MAX_EXECUTION_TIME` to `default_scope` to make it applied to all queries.

```ruby
class Job < ApplicationRecord
  default_scope { optimizer_hints("MAX_EXECUTION_TIME(3000)") }
end
```

However, this is too easy to undo by `.unscoped` on the relation.

This is the reason why the gem author preferred a separate implementation to append `MAX_EXECUTION_TIME` on top of the query, instead of using ActiveRecord scope.

#### Consistency

You might be curious what happens to operations with data that were cancelled due the deadline.
The deadline check is best effort and only applies to `SELECT` queries.

If the `SELECT` was part of the transaction, it's expected for the transaction to get rolled back


