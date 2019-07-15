require "test_helper"

class RequestDeadlineTest < Minitest::Test
  def setup
    Product.all.load # warm up
  end

  def test_does_not_prepend_when_no_request_deadline
    Product.create!(name: "omg")

    queries = capture_sql { Product.all.load }

    assert_match(/SELECT `products`/, queries.first)
  end

  def test_prepends_when_deadline_present
    RequestStore.store[:deadline] = Concurrent.monotonic_time + 30 # seconds
    queries = capture_sql { 10.times { Product.all.load } }

    deadlines = queries.map { |q| q.match(/SELECT \/\*\+ MAX_EXECUTION_TIME\((\d+)\) \*\//)[1].to_i }

    assert_equal deadlines, deadlines.sort.reverse
  end

  def test_only_annotates_select
    # RequestStore.store[:deadline] = Concurrent.monotonic_time + 30 # seconds
    # queries = capture_sql { 10.times { Product.all.load } }

    # deadlines = queries.map { |q| q.match(/SELECT \/\*\+ MAX_EXECUTION_TIME\((\d+)\) \*\//)[1].to_i }

    # assert_equal deadlines, deadlines.sort.reverse
  end

  def test_raises_on_deadline_exceed
    RequestStore.store[:deadline] = Concurrent.monotonic_time - 1
    assert_raises(ActiveRecord::DeadlineExceeded) { Product.all.load }
  end

  def test_with_opt_hints
    RequestStore.store[:deadline] = Concurrent.monotonic_time + 30 # seconds

    queries = capture_sql do
      Product.optimizer_hints("NO_INDEX_MERGE(topics)").all.load
    end

    assert queries.first.start_with?("SELECT /*+ MAX_EXECUTION_TIME(30000) NO_INDEX_MERGE(topics) */")
  end
end
