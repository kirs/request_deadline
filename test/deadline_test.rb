require "test_helper"

class RequestDeadlineTest < Minitest::Test
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
end
